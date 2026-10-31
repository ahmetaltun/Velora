use crate::pool::StringPool;
use crate::record::{DirId, FileId, FileRecord};
use crate::snapshot::{compute_crc32, SnapshotHeader, SNAPSHOT_MAGIC, SNAPSHOT_VERSION};
use crate::table::DirectoryTable;
use serde::{Deserialize, Serialize};
use std::io::{Read, Write};
use std::path::Path;

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct AppMetadataEntry {
    pub name: String,
    pub bundle_id: String,
    pub version: String,
    pub app_path: String,
    pub is_system_app: bool,
}

#[derive(Debug, Default, Clone, Serialize, Deserialize)]
pub struct VolumeIndex {
    pub volume_name: String,
    pub mount_point: String,
    pub is_online: bool,
    pub pool: StringPool,
    pub dirs: DirectoryTable,
    pub records: Vec<FileRecord>,
    #[serde(default)]
    pub apps: Vec<AppMetadataEntry>,
}

impl VolumeIndex {
    pub fn new(volume_name: impl Into<String>, mount_point: impl Into<String>) -> Self {
        Self {
            volume_name: volume_name.into(),
            mount_point: mount_point.into(),
            is_online: true,
            pool: StringPool::new(),
            dirs: DirectoryTable::new(),
            records: Vec::with_capacity(1024 * 1024),
            apps: Vec::new(),
        }
    }

    #[inline]
    pub fn add_file(&mut self, record: FileRecord) -> FileId {
        let id = FileId(self.records.len() as u32);
        self.records.push(record);
        id
    }

    #[inline]
    pub fn get_file_name(&self, record: &FileRecord) -> &str {
        self.pool.get(record.name_offset, record.name_len)
    }

    #[inline]
    pub fn total_files(&self) -> usize {
        self.records.len()
    }

    #[inline]
    pub fn active_files(&self) -> usize {
        self.records.iter().filter(|r| !r.is_deleted()).count()
    }

    #[inline]
    pub fn total_scanned_bytes(&self) -> u64 {
        self.records.iter().map(|r| r.size).sum()
    }

    #[inline]
    pub fn active_bytes(&self) -> u64 {
        self.records
            .iter()
            .filter(|r| !r.is_deleted())
            .map(|r| r.size)
            .sum()
    }

    /// Marks a specific record as deleted by its ID and returns its size.
    pub fn mark_deleted_by_id(&mut self, id: FileId) -> u64 {
        if let Some(record) = self.records.get_mut(id.0 as usize) {
            if !record.is_deleted() {
                record.mark_deleted();
                return record.size;
            }
        }
        0
    }

    /// Marks all records matching any of the given paths or inside any directory prefix as deleted.
    /// Performs a single-pass index traversal matching against an in-memory hash set and prefix list.
    /// Returns the total bytes freed by this batch tombstoning operation.
    pub fn mark_deleted_batch(&mut self, target_paths: &[String]) -> u64 {
        if target_paths.is_empty() {
            return 0;
        }

        let mut exact_set = std::collections::HashSet::with_capacity(target_paths.len());
        let mut dir_prefixes = Vec::new();

        for p in target_paths {
            let clean = p.trim_end_matches('/');
            if !clean.is_empty() {
                exact_set.insert(clean);
                dir_prefixes.push(format!("{}/", clean));
            }
        }

        let mut freed_bytes = 0u64;
        let mut full_path = String::with_capacity(256);

        for record in &mut self.records {
            if record.is_deleted() {
                continue;
            }

            full_path.clear();
            self.dirs.build_full_path(record.parent_dir, &self.pool, &mut full_path);
            if !full_path.ends_with('/') {
                full_path.push('/');
            }
            full_path.push_str(self.pool.get(record.name_offset, record.name_len));

            let clean_full = full_path.trim_end_matches('/');

            if exact_set.contains(clean_full) {
                record.mark_deleted();
                freed_bytes += record.size;
                continue;
            }

            for prefix in &dir_prefixes {
                if clean_full.starts_with(prefix) {
                    record.mark_deleted();
                    freed_bytes += record.size;
                    break;
                }
            }
        }

        freed_bytes
    }

    /// Marks all records matching the given path or inside the directory prefix as deleted.
    /// Returns the total bytes freed by this tombstoning operation.
    pub fn mark_deleted_by_path(&mut self, target_path: &str) -> u64 {
        self.mark_deleted_batch(&[target_path.to_string()])
    }

    pub fn resolve_full_path(&self, record: &FileRecord) -> String {
        let mut path = String::with_capacity(128);
        self.dirs.build_full_path(record.parent_dir, &self.pool, &mut path);
        if !path.ends_with('/') {
            path.push('/');
        }
        path.push_str(self.get_file_name(record));
        path
    }

    /// Saves binary compressed snapshot of the entire volume index to disk atomically.
    ///
    /// Guardrails:
    /// 1. Writes to a unique hidden temporary file in the same parent directory to avoid race conditions and EXDEV.
    /// 2. Prepends a 28-byte magic container header (`VELORASN`), schema version, and payload CRC-32 checksum.
    /// 3. Flushes and syncs data to disk before performing an atomic `rename` swap.
    /// 4. Cleans up temporary file on serialization or I/O failure.
    pub fn save_snapshot(&self, dest: &Path) -> std::io::Result<()> {
        let parent = dest.parent().unwrap_or_else(|| Path::new("."));
        let file_name = dest
            .file_name()
            .and_then(|f| f.to_str())
            .unwrap_or("catalog");

        std::fs::create_dir_all(parent)?;

        // Unique temporary filename to prevent collisions during concurrent scans
        let unique_suffix = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .map(|d| d.as_nanos())
            .unwrap_or(0);
        let temp_path = parent.join(format!(
            ".{}.{}_{}.tmp",
            file_name,
            std::process::id(),
            unique_suffix
        ));

        // Serialize index payload
        let payload = bincode::serialize(self)
            .map_err(|e| std::io::Error::new(std::io::ErrorKind::Other, e.to_string()))?;
        let checksum = compute_crc32(&payload);

        let header = SnapshotHeader {
            magic: SNAPSHOT_MAGIC,
            version: SNAPSHOT_VERSION,
            flags: 0,
            checksum,
            payload_len: payload.len() as u64,
        };

        // Write header + payload to temp file
        let write_result = (|| -> std::io::Result<()> {
            let mut file = std::fs::File::create(&temp_path)?;
            header.write_to(&mut file)?;
            file.write_all(&payload)?;
            file.sync_data()?;
            Ok(())
        })();

        if let Err(err) = write_result {
            let _ = std::fs::remove_file(&temp_path);
            return Err(err);
        }

        // Atomically replace destination snapshot
        if let Err(err) = std::fs::rename(&temp_path, dest) {
            let _ = std::fs::remove_file(&temp_path);
            return Err(err);
        }

        Ok(())
    }

    /// Loads an offline volume catalog snapshot from disk.
    ///
    /// Validates the `VELORASN` magic header, schema version, and IEEE CRC-32 payload checksum
    /// before deserializing into memory to prevent corrupt or partial loads.
    pub fn load_snapshot(src: &Path) -> std::io::Result<Self> {
        let mut file = std::fs::File::open(src)?;
        let header = SnapshotHeader::read_from(&mut file)?;

        let mut payload = Vec::with_capacity(header.payload_len as usize);
        file.read_to_end(&mut payload)?;

        if payload.len() as u64 != header.payload_len {
            return Err(std::io::Error::new(
                std::io::ErrorKind::UnexpectedEof,
                format!(
                    "Snapshot payload truncated: expected {} bytes, read {}",
                    header.payload_len,
                    payload.len()
                ),
            ));
        }

        let actual_checksum = compute_crc32(&payload);
        if actual_checksum != header.checksum {
            return Err(std::io::Error::new(
                std::io::ErrorKind::InvalidData,
                format!(
                    "Snapshot checksum mismatch: corrupted data (computed 0x{:08X}, expected 0x{:08X})",
                    actual_checksum, header.checksum
                ),
            ));
        }

        let mut index: Self = bincode::deserialize(&payload)
            .map_err(|e| std::io::Error::new(std::io::ErrorKind::Other, e.to_string()))?;
        index.is_online = false; // Loaded from offline snapshot
        Ok(index)
    }

    /// Merges an independently scanned subtree volume index into this volume index.
    ///
    /// `sub`: The partial index scanned for a subdirectory branch.
    /// `sub_root_in_self`: The `DirId` in `self` corresponding to the root directory of `sub`.
    pub fn merge_subtree(&mut self, sub: VolumeIndex, sub_root_in_self: DirId) {
        if sub.dirs.is_empty() {
            return;
        }

        // Mapping from sub's DirId -> self's DirId
        let mut dir_map: Vec<DirId> = Vec::with_capacity(sub.dirs.len());
        // Sub's root (DirId(0)) maps to sub_root_in_self
        dir_map.push(sub_root_in_self);

        // Remap directories (from index 1 onward, skipping sub's root)
        for i in 1..sub.dirs.len() {
            if let Some(entry) = sub.dirs.get(DirId(i as u32)) {
                let name = sub.pool.get(entry.name_offset, entry.name_len);
                let (new_off, new_len) = self.pool.push(name);
                let new_parent = entry.parent.map(|p| {
                    let p_idx = p.0 as usize;
                    if p_idx < dir_map.len() {
                        dir_map[p_idx]
                    } else {
                        sub_root_in_self
                    }
                });
                let new_id = self.dirs.insert(new_off, new_len, new_parent);
                dir_map.push(new_id);
            }
        }

        // Remap and append file records
        self.records.reserve(sub.records.len());
        for rec in &sub.records {
            let name = sub.pool.get(rec.name_offset, rec.name_len);
            let (new_off, new_len) = self.pool.push(name);
            let p_idx = rec.parent_dir.0 as usize;
            let new_parent = if p_idx < dir_map.len() {
                dir_map[p_idx]
            } else {
                sub_root_in_self
            };
            self.records.push(FileRecord::new(
                new_off,
                new_len,
                rec.flags,
                new_parent,
                rec.size,
                rec.modified_secs,
            ));
        }
    }

    /// Approximate heap memory consumed in bytes.
    pub fn estimated_memory_bytes(&self) -> usize {
        self.pool.len_bytes()
            + (self.records.len() * std::mem::size_of::<FileRecord>())
            + (self.dirs.len() * 16)
    }

    /// Resolves a path (relative or absolute) to a DirId inside the index.
    pub fn find_dir_by_path(&self, target_path: &Path) -> Option<DirId> {
        let target_str = target_path.to_string_lossy();
        let clean = target_str.trim_end_matches('/');

        let dir_count = self.dirs.len();

        // 1. Check if it matches any root directory directly or starts with that root
        for i in 0..dir_count {
            let dir_id = DirId(i as u32);
            if let Some(entry) = self.dirs.get(dir_id) {
                if entry.parent.is_none() {
                    let root_name = self.pool.get(entry.name_offset, entry.name_len);
                    let clean_root = root_name.trim_end_matches('/');

                    if clean == clean_root {
                        return Some(dir_id);
                    }

                    if clean.starts_with(clean_root) {
                        let remainder = &clean[clean_root.len()..];
                        if remainder.starts_with('/') {
                            let sub_path = &remainder[1..];
                            if let Some(found) = self.find_child_by_rel_path(dir_id, sub_path) {
                                return Some(found);
                            }
                        }
                    }
                }
            }
        }

        // 2. Also support relative path matching across roots (e.g. "Library/Developer")
        let clean_rel = clean.trim_start_matches('/');
        for i in 0..dir_count {
            let dir_id = DirId(i as u32);
            if let Some(entry) = self.dirs.get(dir_id) {
                if entry.parent.is_none() {
                    if let Some(found) = self.find_child_by_rel_path(dir_id, clean_rel) {
                        return Some(found);
                    }
                }
            }
        }

        None
    }

    /// Recursively traverses child directory components from a parent DirId.
    fn find_child_by_rel_path(&self, start: DirId, rel_path: &str) -> Option<DirId> {
        let mut curr = start;
        let dir_count = self.dirs.len();

        for component in rel_path.split('/').filter(|s| !s.is_empty()) {
            let mut found = None;
            for i in 0..dir_count {
                let id = DirId(i as u32);
                if let Some(entry) = self.dirs.get(id) {
                    if entry.parent == Some(curr) {
                        let name = self.pool.get(entry.name_offset, entry.name_len);
                        if name == component {
                            found = Some(id);
                            break;
                        }
                    }
                }
            }
            match found {
                Some(next) => curr = next,
                None => return None,
            }
        }
        Some(curr)
    }

    /// Returns immediate child directories of the given parent directory as (DirId, name).
    pub fn get_child_dirs(&self, parent: DirId) -> Vec<(DirId, &str)> {
        let mut children = Vec::new();
        let dir_count = self.dirs.len();
        for i in 0..dir_count {
            let id = DirId(i as u32);
            if let Some(entry) = self.dirs.get(id) {
                if entry.parent == Some(parent) {
                    let name = self.pool.get(entry.name_offset, entry.name_len);
                    children.push((id, name));
                }
            }
        }
        children
    }

    /// Returns the name of the directory.
    pub fn get_dir_name(&self, dir_id: DirId) -> Option<&str> {
        self.dirs.get(dir_id).map(|e| self.pool.get(e.name_offset, e.name_len))
    }

    /// Reconstructs the full path for a directory ID.
    pub fn build_dir_path(&self, dir_id: DirId) -> String {
        let mut path = String::with_capacity(128);
        self.dirs.build_full_path(dir_id, &self.pool, &mut path);
        path
    }

    /// Retrieves modification timestamp for a directory if recorded.
    pub fn get_dir_modified_secs(&self, dir_id: DirId) -> u64 {
        if let Some(entry) = self.dirs.get(dir_id) {
            let parent = entry.parent.unwrap_or(dir_id);
            let name = self.pool.get(entry.name_offset, entry.name_len);
            for rec in &self.records {
                if rec.is_dir() && rec.parent_dir == parent {
                    if self.get_file_name(rec) == name {
                        return rec.modified_secs;
                    }
                }
            }
        }
        0
    }
}
