use crate::pool::StringPool;
use crate::record::{DirId, FileId, FileRecord};
use crate::snapshot::{
    compute_crc32, SnapshotHeader, SnapshotHeaderV2, SNAPSHOT_FLAG_UNCOMPRESSED,
    SNAPSHOT_MAGIC, SNAPSHOT_VERSION_V2,
};
use crate::table::{DirectoryTable, RawDirectoryEntry};
use serde::{Deserialize, Serialize};
use std::io::Write;
use std::path::Path;

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct AppMetadataEntry {
    pub name: String,
    pub bundle_id: String,
    pub version: String,
    pub app_path: String,
    pub is_system_app: bool,
}

#[derive(Serialize, Deserialize)]
struct SnapshotMetadata {
    volume_name: String,
    mount_point: String,
    apps: Vec<AppMetadataEntry>,
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

    /// Collects the specified root directory and all of its recursive child directory IDs.
    pub fn collect_descendant_dirs(
        &self,
        root_dir: DirId,
        out: &mut std::collections::HashSet<DirId>,
    ) {
        out.insert(root_dir);
        let mut queue = vec![root_dir];
        let dir_count = self.dirs.len();

        let mut children_map: std::collections::HashMap<DirId, Vec<DirId>> =
            std::collections::HashMap::new();
        for i in 0..dir_count {
            let id = DirId(i as u32);
            if let Some(entry) = self.dirs.get(id) {
                if let Some(parent) = entry.parent {
                    children_map.entry(parent).or_default().push(id);
                }
            }
        }

        while let Some(parent) = queue.pop() {
            if let Some(children) = children_map.get(&parent) {
                for &child in children {
                    if out.insert(child) {
                        queue.push(child);
                    }
                }
            }
        }
    }

    /// Marks all records matching any of the given paths or inside any directory prefix as deleted.
    /// Performs an indexed $O(1)$ directory and file match without reconstructing full paths
    /// for millions of records, with an edge-case fallback for unresolved paths.
    /// Returns the total bytes freed by this batch tombstoning operation.
    pub fn mark_deleted_batch(&mut self, target_paths: &[String]) -> u64 {
        if target_paths.is_empty() {
            return 0;
        }

        let mut target_dirs: std::collections::HashSet<DirId> = std::collections::HashSet::new();
        let mut target_files: std::collections::HashMap<DirId, std::collections::HashSet<String>> =
            std::collections::HashMap::new();

        let mut unresolved_exact = std::collections::HashSet::new();
        let mut unresolved_prefixes = Vec::new();

        for p in target_paths {
            let clean = p.trim_end_matches('/');
            if clean.is_empty() {
                continue;
            }

            let path_obj = Path::new(clean);
            if let Some(dir_id) = self.find_dir_by_path(path_obj) {
                // Target is a directory in the index: tombstone dir and all recursive children
                self.collect_descendant_dirs(dir_id, &mut target_dirs);
            } else if let Some(parent) = path_obj.parent() {
                if let Some(parent_id) = self.find_dir_by_path(parent) {
                    if let Some(file_name) = path_obj.file_name().and_then(|f| f.to_str()) {
                        target_files
                            .entry(parent_id)
                            .or_default()
                            .insert(file_name.to_string());
                        continue;
                    }
                }
                // Could not resolve parent DirId: queue for path fallback
                unresolved_exact.insert(clean);
                unresolved_prefixes.push(format!("{}/", clean));
            } else {
                unresolved_exact.insert(clean);
                unresolved_prefixes.push(format!("{}/", clean));
            }
        }

        let has_unresolved = !unresolved_exact.is_empty() || !unresolved_prefixes.is_empty();
        let mut freed_bytes = 0u64;
        let mut full_path = if has_unresolved {
            String::with_capacity(256)
        } else {
            String::new()
        };

        for record in &mut self.records {
            if record.is_deleted() {
                continue;
            }

            // 1. Fast indexed directory match
            if target_dirs.contains(&record.parent_dir) {
                record.mark_deleted();
                freed_bytes += record.size;
                continue;
            }

            // 2. Fast indexed file match (by parent DirId and file name in pool)
            if let Some(names) = target_files.get(&record.parent_dir) {
                let name = self.pool.get(record.name_offset, record.name_len);
                if names.contains(name) {
                    record.mark_deleted();
                    freed_bytes += record.size;
                    continue;
                }
            }

            // 3. Fallback for unresolved paths only
            if has_unresolved {
                full_path.clear();
                self.dirs
                    .build_full_path(record.parent_dir, &self.pool, &mut full_path);
                if !full_path.ends_with('/') {
                    full_path.push('/');
                }
                full_path.push_str(self.pool.get(record.name_offset, record.name_len));

                let clean_full = full_path.trim_end_matches('/');
                if unresolved_exact.contains(clean_full) {
                    record.mark_deleted();
                    freed_bytes += record.size;
                    continue;
                }

                for prefix in &unresolved_prefixes {
                    if clean_full.starts_with(prefix) {
                        record.mark_deleted();
                        freed_bytes += record.size;
                        break;
                    }
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

    /// Saves binary uncompressed snapshot of the entire volume index to disk atomically in V2 format.
    ///
    /// Guardrails:
    /// 1. Writes to a unique hidden temporary file in the same parent directory to avoid race conditions and EXDEV.
    /// 2. Prepends a 64-byte aligned magic container header (`VELORASN`), schema version 2, and payload CRC-32 checksum.
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

        // 1. Serialize metadata (volume name, mount point, app metadata)
        let meta = SnapshotMetadata {
            volume_name: self.volume_name.clone(),
            mount_point: self.mount_point.clone(),
            apps: self.apps.clone(),
        };
        let meta_bytes = bincode::serialize(&meta)
            .map_err(|e| std::io::Error::new(std::io::ErrorKind::Other, e.to_string()))?;

        // 2. Sections
        let pool_bytes = self.pool.buffer();
        let raw_dirs = self.dirs.to_raw_entries();
        let dir_bytes: &[u8] = bytemuck::cast_slice(&raw_dirs);
        let records_bytes: &[u8] = bytemuck::cast_slice(&self.records);

        let payload_len = pool_bytes.len() + dir_bytes.len() + records_bytes.len() + meta_bytes.len();

        // 3. Compute IEEE CRC-32 with hardware acceleration
        let mut hasher = crc32fast::Hasher::new();
        hasher.update(pool_bytes);
        hasher.update(dir_bytes);
        hasher.update(records_bytes);
        hasher.update(&meta_bytes);
        let checksum = hasher.finalize();

        let header = SnapshotHeaderV2 {
            magic: SNAPSHOT_MAGIC,
            version: SNAPSHOT_VERSION_V2,
            flags: SNAPSHOT_FLAG_UNCOMPRESSED,
            checksum,
            _reserved1: 0,
            payload_len: payload_len as u64,
            pool_len: pool_bytes.len() as u64,
            dirs_count: raw_dirs.len() as u64,
            records_count: self.records.len() as u64,
            metadata_len: meta_bytes.len() as u64,
        };

        // Write header + sections to temp file
        let write_result = (|| -> std::io::Result<()> {
            let file = std::fs::File::create(&temp_path)?;
            let mut writer = std::io::BufWriter::with_capacity(512 * 1024, file);
            header.write_to(&mut writer)?;
            writer.write_all(pool_bytes)?;
            writer.write_all(dir_bytes)?;
            writer.write_all(records_bytes)?;
            writer.write_all(&meta_bytes)?;
            writer.flush()?;
            let file = writer.into_inner().map_err(|e| e.into_error())?;
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
    /// Memory maps the snapshot via `memmap2`, verifies IEEE CRC-32 via hardware SIMD instructions,
    /// and performs zero-deserialization block slice loading (V2) or fallback Bincode decoding (V1).
    pub fn load_snapshot(src: &Path) -> std::io::Result<Self> {
        let file = std::fs::File::open(src)?;
        let file_len = file.metadata()?.len();

        // Snapshot requires at least the 28-byte V1 header or 64-byte V2 header
        if file_len < 28 {
            return Err(std::io::Error::new(
                std::io::ErrorKind::UnexpectedEof,
                "Snapshot file too short to contain valid header",
            ));
        }

        let mmap = unsafe { memmap2::MmapOptions::new().map(&file)? };
        let _ = mmap.advise(memmap2::Advice::WillNeed);

        let mut slice = &mmap[..];
        let header = SnapshotHeader::read_from(&mut slice)?;

        match header {
            SnapshotHeader::V1(h) => {
                let payload_start = 28;
                let payload_end = payload_start + h.payload_len as usize;

                if mmap.len() < payload_end {
                    return Err(std::io::Error::new(
                        std::io::ErrorKind::UnexpectedEof,
                        format!(
                            "Snapshot payload truncated: expected {} bytes, read {}",
                            h.payload_len,
                            mmap.len().saturating_sub(payload_start)
                        ),
                    ));
                }

                let payload = &mmap[payload_start..payload_end];
                let actual_checksum = compute_crc32(payload);
                if actual_checksum != h.checksum {
                    return Err(std::io::Error::new(
                        std::io::ErrorKind::InvalidData,
                        format!(
                            "Snapshot checksum mismatch: corrupted data (computed 0x{:08X}, expected 0x{:08X})",
                            actual_checksum, h.checksum
                        ),
                    ));
                }

                let mut index: Self = bincode::deserialize(payload)
                    .map_err(|e| std::io::Error::new(std::io::ErrorKind::Other, e.to_string()))?;
                index.is_online = false;
                Ok(index)
            }
            SnapshotHeader::V2(h) => {
                let payload_start = SnapshotHeaderV2::SIZE;
                let payload_end = payload_start + h.payload_len as usize;

                if mmap.len() < payload_end {
                    return Err(std::io::Error::new(
                        std::io::ErrorKind::UnexpectedEof,
                        format!(
                            "Snapshot payload truncated: expected {} bytes, read {}",
                            h.payload_len,
                            mmap.len().saturating_sub(payload_start)
                        ),
                    ));
                }

                let payload = &mmap[payload_start..payload_end];
                let actual_checksum = compute_crc32(payload);
                if actual_checksum != h.checksum {
                    return Err(std::io::Error::new(
                        std::io::ErrorKind::InvalidData,
                        format!(
                            "Snapshot checksum mismatch: corrupted data (computed 0x{:08X}, expected 0x{:08X})",
                            actual_checksum, h.checksum
                        ),
                    ));
                }

                let pool_len = h.pool_len as usize;
                let dirs_bytes_len = (h.dirs_count as usize)
                    .checked_mul(std::mem::size_of::<RawDirectoryEntry>())
                    .ok_or_else(|| std::io::Error::new(std::io::ErrorKind::InvalidData, "dirs byte length overflow"))?;
                let records_bytes_len = (h.records_count as usize)
                    .checked_mul(std::mem::size_of::<FileRecord>())
                    .ok_or_else(|| std::io::Error::new(std::io::ErrorKind::InvalidData, "records byte length overflow"))?;
                let metadata_len = h.metadata_len as usize;

                let expected_total = pool_len
                    .checked_add(dirs_bytes_len)
                    .and_then(|v| v.checked_add(records_bytes_len))
                    .and_then(|v| v.checked_add(metadata_len))
                    .ok_or_else(|| std::io::Error::new(std::io::ErrorKind::InvalidData, "Snapshot section lengths overflow"))?;

                if expected_total != h.payload_len as usize {
                    return Err(std::io::Error::new(
                        std::io::ErrorKind::InvalidData,
                        format!(
                            "Snapshot section size mismatch: sections sum to {} but payload_len is {}",
                            expected_total, h.payload_len
                        ),
                    ));
                }

                let pool_start = 0;
                let pool_end = pool_start + pool_len;

                let dirs_start = pool_end;
                let dirs_end = dirs_start + dirs_bytes_len;

                let records_start = dirs_end;
                let records_end = records_start + records_bytes_len;

                let meta_start = records_end;
                let meta_end = meta_start + metadata_len;

                // 1. String Pool: bulk copy
                let pool = StringPool::from_buffer(payload[pool_start..pool_end].to_vec());

                // 2. Directory Table: fast contiguous mapping
                let dirs_count = h.dirs_count as usize;
                let mut raw_dirs: Vec<RawDirectoryEntry> = Vec::with_capacity(dirs_count);
                unsafe {
                    raw_dirs.set_len(dirs_count);
                    let dst = std::slice::from_raw_parts_mut(
                        raw_dirs.as_mut_ptr() as *mut u8,
                        dirs_count * std::mem::size_of::<RawDirectoryEntry>(),
                    );
                    dst.copy_from_slice(&payload[dirs_start..dirs_end]);
                }
                let dirs = DirectoryTable::from_raw_entries(&raw_dirs);

                // 3. File Records: zero-deserialization POD bulk copy
                let records_count = h.records_count as usize;
                let mut records: Vec<FileRecord> = Vec::with_capacity(records_count);
                unsafe {
                    records.set_len(records_count);
                    let dst = std::slice::from_raw_parts_mut(
                        records.as_mut_ptr() as *mut u8,
                        records_count * std::mem::size_of::<FileRecord>(),
                    );
                    dst.copy_from_slice(&payload[records_start..records_end]);
                }

                // 4. Metadata: small auxiliary bincode payload
                let meta: SnapshotMetadata = bincode::deserialize(&payload[meta_start..meta_end])
                    .map_err(|e| std::io::Error::new(std::io::ErrorKind::Other, e.to_string()))?;

                Ok(Self {
                    volume_name: meta.volume_name,
                    mount_point: meta.mount_point,
                    is_online: false,
                    pool,
                    dirs,
                    records,
                    apps: meta.apps,
                })
            }
        }
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
        let clean_rel = clean.trim_start_matches('/');

        let dir_count = self.dirs.len();

        for i in 0..dir_count {
            let dir_id = DirId(i as u32);
            if let Some(entry) = self.dirs.get(dir_id) {
                if entry.parent.is_none() {
                    let root_name = self.pool.get(entry.name_offset, entry.name_len);
                    let clean_root = root_name.trim_start_matches('/').trim_end_matches('/');

                    if clean_root.is_empty() {
                        if clean_rel.is_empty() {
                            return Some(dir_id);
                        }
                        if let Some(found) = self.find_child_by_rel_path(dir_id, clean_rel) {
                            return Some(found);
                        }
                        continue;
                    }

                    if clean_rel == clean_root {
                        return Some(dir_id);
                    }

                    if clean_rel.starts_with(clean_root) {
                        let remainder = &clean_rel[clean_root.len()..];
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
