use serde::{Deserialize, Serialize};
use std::fs;
use std::os::unix::fs::PermissionsExt;
use std::path::{Path, PathBuf};
use std::process::Command;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct QuarantinedItemEntry {
    pub id: String,
    pub original_path: String,
    pub quarantined_path: String,
    pub original_mode: u32,
    pub quarantined_at_secs: u64,
    pub associated_paths: Vec<String>,
}

#[derive(Debug, Default, Clone, Serialize, Deserialize)]
pub struct QuarantineManifest {
    pub items: Vec<QuarantinedItemEntry>,
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

    fn load_manifest(&self) -> QuarantineManifest {
        let path = self.manifest_path();
        if path.exists() {
            if let Ok(bytes) = fs::read(&path) {
                if let Ok(manifest) = serde_json::from_slice(&bytes) {
                    return manifest;
                }
            }
        }
        QuarantineManifest::default()
    }

    fn save_manifest(&self, manifest: &QuarantineManifest) -> std::io::Result<()> {
        let path = self.manifest_path();
        let bytes = serde_json::to_vec_pretty(manifest)
            .map_err(|e| std::io::Error::new(std::io::ErrorKind::Other, e.to_string()))?;
        fs::write(path, bytes)
    }

    /// Quarantines a malicious target path and any associated LaunchAgent plists.
    pub fn quarantine(
        &self,
        id: &str,
        target_path: &Path,
        associated_paths: &[String],
    ) -> std::io::Result<QuarantinedItemEntry> {
        fs::create_dir_all(&self.vault_dir)?;

        let mut manifest = self.load_manifest();

        // 1. If any associated path is a LaunchAgent, attempt to unload via launchctl
        for assoc in associated_paths {
            let assoc_path = Path::new(assoc);
            if assoc.ends_with(".plist") && assoc_path.exists() {
                // Attempt launchctl unload
                let _ = Command::new("/bin/launchctl")
                    .arg("unload")
                    .arg(assoc_path)
                    .output();
            }
        }

        // 2. Quarantine the primary binary if it exists
        let mut original_mode = 0o755;
        let file_name = target_path
            .file_name()
            .map(|f| f.to_string_lossy().to_string())
            .unwrap_or_else(|| "unknown_threat".to_string());

        let quarantined_file_name = format!("{}_{}.quarantine", id, file_name);
        let dest_path = self.vault_dir.join(quarantined_file_name);

        if target_path.exists() {
            if let Ok(meta) = fs::metadata(target_path) {
                original_mode = meta.permissions().mode();
            }

            // Move file into vault
            fs::rename(target_path, &dest_path)?;

            // Strip all permissions (chmod 000) so it cannot be executed
            let _ = fs::set_permissions(&dest_path, fs::Permissions::from_mode(0o000));
        }

        // 3. Move associated plists into vault
        let mut quarantined_assocs = Vec::new();
        for assoc in associated_paths {
            let p = Path::new(assoc);
            if p.exists() {
                let a_name = p
                    .file_name()
                    .map(|f| f.to_string_lossy().to_string())
                    .unwrap_or_else(|| "assoc".to_string());
                let dest_assoc = self.vault_dir.join(format!("{}_{}.quarantine_meta", id, a_name));
                if fs::rename(p, &dest_assoc).is_ok() {
                    quarantined_assocs.push(dest_assoc.to_string_lossy().to_string());
                }
            }
        }

        let entry = QuarantinedItemEntry {
            id: id.to_string(),
            original_path: target_path.to_string_lossy().to_string(),
            quarantined_path: dest_path.to_string_lossy().to_string(),
            original_mode,
            quarantined_at_secs: std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .map(|d| d.as_secs())
                .unwrap_or(0),
            associated_paths: quarantined_assocs,
        };

        manifest.items.push(entry.clone());
        let _ = self.save_manifest(&manifest);

        Ok(entry)
    }

    /// Restores a previously quarantined item to its original location and restores its permissions.
    pub fn restore(&self, id: &str) -> std::io::Result<bool> {
        let mut manifest = self.load_manifest();
        let idx = manifest.items.iter().position(|i| i.id == id);

        if let Some(pos) = idx {
            let entry = manifest.items.remove(pos);
            let q_path = Path::new(&entry.quarantined_path);
            let orig_path = Path::new(&entry.original_path);

            if q_path.exists() {
                // Restore original permissions first
                let _ = fs::set_permissions(q_path, fs::Permissions::from_mode(entry.original_mode));

                if let Some(parent) = orig_path.parent() {
                    let _ = fs::create_dir_all(parent);
                }

                fs::rename(q_path, orig_path)?;
            }

            let _ = self.save_manifest(&manifest);
            Ok(true)
        } else {
            Ok(false)
        }
    }
}
