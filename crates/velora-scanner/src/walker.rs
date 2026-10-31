use rayon::prelude::*;
use std::fs;
use std::os::unix::fs::MetadataExt;
#[cfg(target_os = "macos")]
use std::os::macos::fs::MetadataExt as MacMetadataExt;
use std::path::Path;
use std::sync::atomic::{AtomicBool, AtomicU64, Ordering};
use std::sync::Mutex;
use std::time::Instant;
use velora_index::{DirId, FileFlags, FileRecord, VolumeIndex};

/// BSD SF_DATALESS flag on macOS indicating the item's contents are stored in cloud storage (e.g., iCloud Drive)
/// and have been evicted locally. Reading or opening this file will trigger an on-demand cloud download.
const SF_DATALESS: u32 = 0x40000000;

/// Progress listener interface for receiving throttled traversal updates.
pub trait ProgressListener: Send + Sync {
    fn on_progress(&self, current_path: &str, files_scanned: u64, bytes_scanned: u64);
}

struct ScanContext<'a> {
    listener: Option<&'a dyn ProgressListener>,
    cancel_token: Option<&'a AtomicBool>,
    files_scanned: AtomicU64,
    bytes_scanned: AtomicU64,
    last_reported_time: Mutex<Instant>,
}

impl<'a> ScanContext<'a> {
    fn new(listener: Option<&'a dyn ProgressListener>, cancel_token: Option<&'a AtomicBool>) -> Self {
        Self {
            listener,
            cancel_token,
            files_scanned: AtomicU64::new(0),
            bytes_scanned: AtomicU64::new(0),
            last_reported_time: Mutex::new(Instant::now()),
        }
    }

    #[inline]
    fn is_cancelled(&self) -> bool {
        if let Some(token) = self.cancel_token {
            token.load(Ordering::Relaxed)
        } else {
            false
        }
    }

    #[inline]
    fn record_entry(&self, size: u64, current_dir_path: &Path) {
        let count = self.files_scanned.fetch_add(1, Ordering::Relaxed) + 1;
        let bytes = self.bytes_scanned.fetch_add(size, Ordering::Relaxed) + size;

        // Throttle check: test every 512 files via bitmask and emit if at least 66ms (~15Hz) have elapsed
        if (count & 511) == 0 {
            if let Ok(mut last) = self.last_reported_time.try_lock() {
                if last.elapsed().as_millis() >= 66 {
                    if let Some(listener) = self.listener {
                        listener.on_progress(
                            &current_dir_path.to_string_lossy(),
                            count,
                            bytes,
                        );
                    }
                    *last = Instant::now();
                }
            }
        }
    }

    fn finish(&self, root_path: &Path) {
        if let Some(listener) = self.listener {
            listener.on_progress(
                &root_path.to_string_lossy(),
                self.files_scanned.load(Ordering::Relaxed),
                self.bytes_scanned.load(Ordering::Relaxed),
            );
        }
    }
}

/// Scans a root path recursively and populates the VolumeIndex without progress callbacks.
pub fn scan_directory(root_path: &Path, volume: &mut VolumeIndex) -> std::io::Result<()> {
    scan_directory_with_progress(root_path, volume, None)
}

/// Scans a root path recursively, reporting progress through an optional ProgressListener.
pub fn scan_directory_with_progress(
    root_path: &Path,
    volume: &mut VolumeIndex,
    listener: Option<&dyn ProgressListener>,
) -> std::io::Result<()> {
    scan_directories_with_progress_and_cancel(&[root_path], volume, listener, None)
}

/// Scans multiple root paths recursively into a single VolumeIndex, reporting progress through an optional ProgressListener.
pub fn scan_directories_with_progress(
    roots: &[&Path],
    volume: &mut VolumeIndex,
    listener: Option<&dyn ProgressListener>,
) -> std::io::Result<()> {
    scan_directories_with_progress_and_cancel(roots, volume, listener, None)
}

/// Scans multiple root paths recursively into a single VolumeIndex using a parallel Rayon crawler,
/// reporting progress through an optional ProgressListener and cooperatively checking an optional cancellation token.
pub fn scan_directories_with_progress_and_cancel(
    roots: &[&Path],
    volume: &mut VolumeIndex,
    listener: Option<&dyn ProgressListener>,
    cancel_token: Option<&AtomicBool>,
) -> std::io::Result<()> {
    let context = ScanContext::new(listener, cancel_token);
    for &root_path in roots {
        if !root_path.exists() {
            continue;
        }
        let root_str = root_path.to_string_lossy();
        let (offset, len) = volume.pool.push(&root_str);
        let root_dir_id = volume.dirs.insert(offset, len, None);
        scan_single_root(root_path, root_dir_id, volume, &context)?;
    }
    if let Some(&first) = roots.first() {
        context.finish(first);
    }
    Ok(())
}

#[inline]
fn should_skip_directory(path: &Path, root_path: &Path) -> bool {
    let path_str = path.to_string_lossy();
    // Skip /System/Volumes which contains Data (firmlink mirror of /Users, /Applications), Update, xarts, etc.
    // Preventing recursive traversal of /System/Volumes eliminates double-counting of all user data.
    if path_str == "/System/Volumes" || path_str.starts_with("/System/Volumes/") {
        return true;
    }
    if root_path == Path::new("/") {
        // When scanning the root filesystem, do not cross into external mount points or synthetic virtual fs
        if path_str == "/Volumes"
            || path_str == "/dev"
            || path_str == "/net"
            || path_str == "/home"
            || path_str == "/cores"
        {
            return true;
        }
    }
    false
}

fn scan_single_root(
    root_path: &Path,
    root_dir_id: DirId,
    volume: &mut VolumeIndex,
    context: &ScanContext,
) -> std::io::Result<()> {
    if context.is_cancelled() {
        return Err(std::io::Error::new(
            std::io::ErrorKind::Interrupted,
            "Scan cancelled by user",
        ));
    }

    let entries = match fs::read_dir(root_path) {
        Ok(e) => e,
        Err(_) => return Ok(()),
    };

    let mut direct_subdirs = Vec::new();

    // 1. Process root's immediate contents
    for entry_res in entries {
        if context.is_cancelled() {
            return Err(std::io::Error::new(
                std::io::ErrorKind::Interrupted,
                "Scan cancelled by user",
            ));
        }

        let entry = match entry_res {
            Ok(e) => e,
            Err(_) => continue,
        };

        let file_type = match entry.file_type() {
            Ok(ft) => ft,
            Err(_) => continue,
        };

        let file_name_os = entry.file_name();
        let file_name = file_name_os.to_string_lossy();

        let mut flags = FileFlags::empty();
        if file_name.starts_with('.') {
            flags.insert(FileFlags::IS_HIDDEN);
        }

        let is_symlink = file_type.is_symlink();
        let meta = entry.metadata().ok();

        #[cfg(target_os = "macos")]
        if let Some(ref m) = meta {
            if (m.st_flags() & SF_DATALESS) != 0 {
                flags.insert(FileFlags::IS_DATALESS);
            }
        }

        if file_type.is_dir() {
            let entry_path = entry.path();
            if should_skip_directory(&entry_path, root_path) {
                continue;
            }

            flags.insert(FileFlags::IS_DIRECTORY);
            let (name_offset, name_len) = volume.pool.push(&file_name);
            let dir_id = volume.dirs.insert(name_offset, name_len, Some(root_dir_id));

            let modified = meta.as_ref().map(|m| m.mtime() as u64).unwrap_or(0);

            volume.add_file(FileRecord::new(
                name_offset,
                name_len,
                flags,
                root_dir_id,
                0,
                modified,
            ));

            context.record_entry(0, root_path);
            direct_subdirs.push((entry_path, dir_id));
        } else {
            let size = meta.as_ref().map(|m| m.size()).unwrap_or(0);
            let modified = meta.as_ref().map(|m| m.mtime() as u64).unwrap_or(0);

            if is_symlink {
                flags.insert(FileFlags::IS_SYMLINK);
            }

            let (name_offset, name_len) = volume.pool.push(&file_name);
            volume.add_file(FileRecord::new(
                name_offset,
                name_len,
                flags,
                root_dir_id,
                size,
                modified,
            ));

            context.record_entry(size, root_path);
        }
    }

    if direct_subdirs.is_empty() {
        return Ok(());
    }

    // 2. Parallelize branch traversal across Rayon thread pool
    // Each branch crawler operates independently on its own local VolumeIndex with zero locks
    let branch_results: Result<Vec<VolumeIndex>, std::io::Error> = direct_subdirs
        .par_iter()
        .map(|(subdir_path, _)| {
            if context.is_cancelled() {
                return Err(std::io::Error::new(
                    std::io::ErrorKind::Interrupted,
                    "Scan cancelled by user",
                ));
            }

            let mut local_vol = VolumeIndex::new("", "");
            let (s_off, s_len) = local_vol.pool.push(&subdir_path.to_string_lossy());
            let local_root = local_vol.dirs.insert(s_off, s_len, None);

            scan_dir_recursive(subdir_path, root_path, local_root, &mut local_vol, context)?;
            Ok(local_vol)
        })
        .collect();

    let local_volumes = branch_results?;

    // 3. Fast lock-free sequential merge of all sub-branches into main volume index
    for ((_, subdir_id), local_vol) in direct_subdirs.into_iter().zip(local_volumes) {
        volume.merge_subtree(local_vol, subdir_id);
    }

    Ok(())
}

fn scan_dir_recursive(
    path: &Path,
    root_path: &Path,
    current_dir: DirId,
    volume: &mut VolumeIndex,
    context: &ScanContext,
) -> std::io::Result<()> {
    if context.is_cancelled() {
        return Err(std::io::Error::new(
            std::io::ErrorKind::Interrupted,
            "Scan cancelled by user",
        ));
    }

    let entries = match fs::read_dir(path) {
        Ok(e) => e,
        Err(_) => return Ok(()), // Skip unreadable/permission-denied folders safely
    };

    let mut subdirs = Vec::new();

    for entry_res in entries {
        if context.is_cancelled() {
            return Err(std::io::Error::new(
                std::io::ErrorKind::Interrupted,
                "Scan cancelled by user",
            ));
        }

        let entry = match entry_res {
            Ok(e) => e,
            Err(_) => continue,
        };

        let file_type = match entry.file_type() {
            Ok(ft) => ft,
            Err(_) => continue,
        };

        let file_name_os = entry.file_name();
        let file_name = file_name_os.to_string_lossy();

        let mut flags = FileFlags::empty();
        if file_name.starts_with('.') {
            flags.insert(FileFlags::IS_HIDDEN);
        }

        let is_symlink = file_type.is_symlink();
        let meta = entry.metadata().ok();

        #[cfg(target_os = "macos")]
        if let Some(ref m) = meta {
            if (m.st_flags() & SF_DATALESS) != 0 {
                flags.insert(FileFlags::IS_DATALESS);
            }
        }

        if file_type.is_dir() {
            let entry_path = entry.path();
            if should_skip_directory(&entry_path, root_path) {
                continue;
            }

            flags.insert(FileFlags::IS_DIRECTORY);
            let (name_offset, name_len) = volume.pool.push(&file_name);
            let dir_id = volume.dirs.insert(name_offset, name_len, Some(current_dir));

            let modified = meta.as_ref().map(|m| m.mtime() as u64).unwrap_or(0);

            volume.add_file(FileRecord::new(
                name_offset,
                name_len,
                flags,
                current_dir,
                0,
                modified,
            ));

            context.record_entry(0, path);
            subdirs.push((entry_path, dir_id));
        } else {
            let size = meta.as_ref().map(|m| m.size()).unwrap_or(0);
            let modified = meta.as_ref().map(|m| m.mtime() as u64).unwrap_or(0);

            if is_symlink {
                flags.insert(FileFlags::IS_SYMLINK);
            }

            let (name_offset, name_len) = volume.pool.push(&file_name);
            volume.add_file(FileRecord::new(
                name_offset,
                name_len,
                flags,
                current_dir,
                size,
                modified,
            ));

            context.record_entry(size, path);
        }
    }

    // Recurse into subdirectories
    for (subdir_path, subdir_id) in subdirs {
        scan_dir_recursive(&subdir_path, root_path, subdir_id, volume, context)?;
    }

    Ok(())
}
