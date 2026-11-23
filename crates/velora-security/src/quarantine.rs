use serde::{Deserialize, Serialize};
use std::ffi::CString;
use std::fs;
use std::io::{self, Write};
use std::os::unix::ffi::OsStrExt;
use std::os::unix::fs::{DirBuilderExt, PermissionsExt};
use std::path::{Path, PathBuf};
use std::process::Command;

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct AssociatedQuarantinedPath {
    pub original_path: String,
    pub quarantined_path: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct QuarantinedItemEntry {
    pub id: String,
    pub original_path: String,
    pub quarantined_path: String,
    pub original_mode: u32,
    pub quarantined_at_secs: u64,
    pub associated_paths: Vec<String>,
    #[serde(default)]
    pub associated_entries: Vec<AssociatedQuarantinedPath>,
}

#[derive(Debug, Default, Clone, Serialize, Deserialize)]
pub struct QuarantineManifest {
    pub items: Vec<QuarantinedItemEntry>,
}

fn unique_suffix() -> String {
    let now = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .unwrap_or_default();
    format!("{}-{}", std::process::id(), now.as_nanos())
}

fn c_path(path: &Path) -> io::Result<CString> {
    CString::new(path.as_os_str().as_bytes())
        .map_err(|err| io::Error::new(io::ErrorKind::InvalidInput, err))
}

fn rename_exclusive(src: &Path, dst: &Path) -> io::Result<()> {
    let src = c_path(src)?;
    let dst = c_path(dst)?;
    // Both C strings remain valid for the duration of the call.
    if unsafe { libc::renamex_np(src.as_ptr(), dst.as_ptr(), libc::RENAME_EXCL) } == 0 {
        Ok(())
    } else {
        Err(io::Error::last_os_error())
    }
}

/// Moves an item without replacing a file at the destination.
fn move_or_copy(src: &Path, dst: &Path) -> io::Result<()> {
    match rename_exclusive(src, dst) {
        Err(err) if err.raw_os_error() == Some(libc::EXDEV) => {}
        result => return result,
    }

    // Complete the copy before publishing it under the destination name.
    let parent = dst.parent().ok_or(io::ErrorKind::InvalidInput)?;
    let stage = parent.join(format!(".velora-copy-{}", unique_suffix()));
    fs::DirBuilder::new().mode(0o700).create(&stage)?;
    let staged_file = stage.join("item");
    let result = (|| {
        let src_c = c_path(src)?;
        let stage_c = c_path(&staged_file)?;
        let flags = libc::COPYFILE_ACL
            | libc::COPYFILE_STAT
            | libc::COPYFILE_XATTR
            | libc::COPYFILE_DATA
            | libc::COPYFILE_RECURSIVE
            | libc::COPYFILE_NOFOLLOW;
        if unsafe {
            libc::copyfile(
                src_c.as_ptr(),
                stage_c.as_ptr(),
                std::ptr::null_mut(),
                flags,
            )
        } != 0
        {
            return Err(io::Error::last_os_error());
        }
        rename_exclusive(&staged_file, dst)?;
        if fs::symlink_metadata(src)?.is_dir() {
            fs::remove_dir_all(src)
        } else {
            fs::remove_file(src)
        }
    })();
    let _ = fs::remove_dir_all(stage);
    result
}

fn is_present(path: &Path) -> bool {
    fs::symlink_metadata(path).is_ok()
}

pub struct QuarantineVault {
    vault_dir: PathBuf,
}

impl QuarantineVault {
    pub fn new(home_path: &Path) -> Self {
        let vault_dir = home_path.join("Library/Application Support/Velora/Quarantine");
        Self { vault_dir }
    }

    fn manifest_path(&self) -> PathBuf {
        self.vault_dir.join("manifest.json")
    }

    fn load_manifest(&self) -> io::Result<QuarantineManifest> {
        match fs::read(self.manifest_path()) {
            Ok(bytes) => serde_json::from_slice(&bytes)
                .map_err(|err| io::Error::new(io::ErrorKind::InvalidData, err)),
            Err(err) if err.kind() == io::ErrorKind::NotFound => Ok(QuarantineManifest::default()),
            Err(err) => Err(err),
        }
    }

    fn save_manifest(&self, manifest: &QuarantineManifest) -> io::Result<()> {
        let temporary = self
            .vault_dir
            .join(format!(".manifest-{}.tmp", unique_suffix()));
        let result = (|| {
            let mut file = fs::OpenOptions::new()
                .write(true)
                .create_new(true)
                .open(&temporary)?;
            serde_json::to_writer_pretty(&mut file, manifest)?;
            file.flush()?;
            file.sync_all()?;
            fs::rename(&temporary, self.manifest_path())
        })();
        if result.is_err() {
            let _ = fs::remove_file(temporary);
        }
        result
    }

    fn has_vaulted_files(entry: &QuarantinedItemEntry) -> bool {
        is_present(Path::new(&entry.quarantined_path))
            || entry
                .associated_paths
                .iter()
                .any(|path| is_present(Path::new(path)))
    }

    pub fn items(&self) -> io::Result<Vec<QuarantinedItemEntry>> {
        let mut items = self.load_manifest()?.items;
        items.retain(Self::has_vaulted_files);
        items.sort_unstable_by_key(|entry| std::cmp::Reverse(entry.quarantined_at_secs));
        Ok(items)
    }

    /// Quarantines a target and its associated LaunchAgent plists.
    pub fn quarantine(
        &self,
        id: &str,
        target_path: &Path,
        associated_paths: &[String],
    ) -> io::Result<QuarantinedItemEntry> {
        fs::create_dir_all(&self.vault_dir)?;
        let mut manifest = self.load_manifest()?;
        if manifest
            .items
            .iter()
            .any(|entry| entry.id == id && Self::has_vaulted_files(entry))
        {
            return Err(io::Error::new(
                io::ErrorKind::AlreadyExists,
                "Item is already in the vault",
            ));
        }
        manifest.items.retain(|entry| entry.id != id);

        let target = match fs::symlink_metadata(target_path) {
            Ok(meta) if meta.is_file() || meta.is_dir() => Some(meta),
            Ok(_) => {
                return Err(io::Error::new(
                    io::ErrorKind::InvalidInput,
                    "Quarantine requires a regular file or folder",
                ))
            }
            Err(err) if err.kind() == io::ErrorKind::NotFound => None,
            Err(err) => return Err(err),
        };

        let key = unique_suffix();
        let dest_path = self.vault_dir.join(format!("{key}.quarantine"));
        let mut associated_entries = Vec::new();
        for assoc in associated_paths {
            let path = Path::new(assoc);
            if path != target_path
                && is_present(path)
                && !associated_entries
                    .iter()
                    .any(|entry: &AssociatedQuarantinedPath| entry.original_path == *assoc)
            {
                let index = associated_entries.len();
                associated_entries.push(AssociatedQuarantinedPath {
                    original_path: assoc.clone(),
                    quarantined_path: self
                        .vault_dir
                        .join(format!("{key}-{index}.quarantine_meta"))
                        .to_string_lossy()
                        .into_owned(),
                });
            }
        }
        if target.is_none() && associated_entries.is_empty() {
            return Err(io::ErrorKind::NotFound.into());
        }
        let entry = QuarantinedItemEntry {
            id: id.to_string(),
            original_path: target_path.to_string_lossy().into_owned(),
            quarantined_path: dest_path.to_string_lossy().into_owned(),
            original_mode: target.as_ref().map_or(0, |meta| meta.permissions().mode()),
            quarantined_at_secs: std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .unwrap_or_default()
                .as_secs(),
            associated_paths: associated_entries
                .iter()
                .map(|item| item.quarantined_path.clone())
                .collect(),
            associated_entries,
        };

        // Record the destinations first so interrupted moves remain discoverable and restorable.
        manifest.items.push(entry.clone());
        self.save_manifest(&manifest)?;

        // Ask launchctl to unload associated agents before moving their plists.
        for assoc in associated_paths {
            let path = Path::new(assoc);
            if assoc.ends_with(".plist") && is_present(path) {
                let _ = Command::new("/bin/launchctl")
                    .arg("unload")
                    .arg(path)
                    .output();
            }
        }
        if target.is_some() {
            move_or_copy(target_path, &dest_path)?;
            fs::set_permissions(&dest_path, fs::Permissions::from_mode(0o000))?;
        }
        for assoc in &entry.associated_entries {
            move_or_copy(
                Path::new(&assoc.original_path),
                Path::new(&assoc.quarantined_path),
            )?;
        }
        Ok(entry)
    }

    /// Restores vaulted files to their original locations without overwriting existing items.
    pub fn restore(&self, id: &str) -> io::Result<bool> {
        let mut manifest = self.load_manifest()?;
        let Some(pos) = manifest.items.iter().position(|entry| entry.id == id) else {
            return Ok(false);
        };
        let entry = &manifest.items[pos];
        if !Self::has_vaulted_files(entry) {
            return Ok(false);
        }
        if entry.associated_entries.is_empty() && !entry.associated_paths.is_empty() {
            return Err(io::Error::new(
                io::ErrorKind::InvalidData,
                "Original paths for associated files are unavailable",
            ));
        }

        let primary = (
            entry.quarantined_path.as_str(),
            entry.original_path.as_str(),
            Some(entry.original_mode),
        );
        let files: Vec<_> = std::iter::once(primary)
            .chain(entry.associated_entries.iter().map(|assoc| {
                (
                    assoc.quarantined_path.as_str(),
                    assoc.original_path.as_str(),
                    None,
                )
            }))
            .filter(|(quarantined, _, _)| is_present(Path::new(quarantined)))
            .collect();

        for (_, original, _) in &files {
            if is_present(Path::new(original)) {
                return Err(io::Error::new(
                    io::ErrorKind::AlreadyExists,
                    format!("A file already exists at {original}"),
                ));
            }
        }
        for (quarantined, original, mode) in files {
            let source = Path::new(quarantined);
            let dest = Path::new(original);
            if let Some(parent) = dest.parent() {
                fs::create_dir_all(parent)?;
            }
            if let Some(mode) = mode {
                fs::set_permissions(source, fs::Permissions::from_mode(mode))?;
            }
            if let Err(err) = move_or_copy(source, dest) {
                if mode.is_some() {
                    let _ = fs::set_permissions(source, fs::Permissions::from_mode(0o000));
                }
                return Err(err);
            }
        }

        manifest.items.remove(pos);
        self.save_manifest(&manifest)?;
        Ok(true)
    }
}
