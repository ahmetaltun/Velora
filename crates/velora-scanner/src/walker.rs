use std::fs;
use std::os::unix::fs::MetadataExt;
use std::path::Path;
use velora_index::{DirId, FileFlags, FileRecord, VolumeIndex};

/// Scans a root path recursively and populates the VolumeIndex.
pub fn scan_directory(root_path: &Path, volume: &mut VolumeIndex) -> std::io::Result<()> {
    let root_str = root_path.to_string_lossy();
    let (offset, len) = volume.pool.push(&root_str);
    let root_dir_id = volume.dirs.insert(offset, len, None);

    scan_dir_recursive(root_path, root_dir_id, volume)
}

fn scan_dir_recursive(path: &Path, current_dir: DirId, volume: &mut VolumeIndex) -> std::io::Result<()> {
    let entries = match fs::read_dir(path) {
        Ok(e) => e,
        Err(_) => return Ok(()), // Skip unreadable/permission-denied folders safely
    };

    let mut subdirs = Vec::new();

    for entry_res in entries {
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

        if file_type.is_dir() {
            flags.insert(FileFlags::IS_DIRECTORY);
            let (name_offset, name_len) = volume.pool.push(&file_name);
            let dir_id = volume.dirs.insert(name_offset, name_len, Some(current_dir));

            let meta = entry.metadata().ok();
            let modified = meta.map(|m| m.mtime() as u64).unwrap_or(0);

            volume.add_file(FileRecord::new(
                name_offset,
                name_len,
                flags,
                current_dir,
                0,
                modified,
            ));

            subdirs.push((entry.path(), dir_id));
        } else {
            let meta = entry.metadata().ok();
            let size = meta.as_ref().map(|m| m.size()).unwrap_or(0);
            let modified = meta.as_ref().map(|m| m.mtime() as u64).unwrap_or(0);

            if file_type.is_symlink() {
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
        }
    }

    // Recurse into subdirectories
    for (subdir_path, subdir_id) in subdirs {
        let _ = scan_dir_recursive(&subdir_path, subdir_id, volume);
    }

    Ok(())
}
