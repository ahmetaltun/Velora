use crate::pool::StringPool;
use crate::record::{FileId, FileRecord};
use crate::table::DirectoryTable;
use serde::{Deserialize, Serialize};
use std::path::Path;

#[derive(Debug, Default, Clone, Serialize, Deserialize)]
pub struct VolumeIndex {
    pub volume_name: String,
    pub mount_point: String,
    pub is_online: bool,
    pub pool: StringPool,
    pub dirs: DirectoryTable,
    pub records: Vec<FileRecord>,
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

    /// Marks all records matching the given path or inside the directory prefix as deleted.
    /// Returns the total bytes freed by this tombstoning operation.
    pub fn mark_deleted_by_path(&mut self, target_path: &str) -> u64 {
        let clean_target = target_path.trim_end_matches('/');
        let mut freed_bytes = 0u64;

        for record in &mut self.records {
            if record.is_deleted() {
                continue;
            }

            let full_path = {
                let mut path = String::with_capacity(128);
                self.dirs.build_full_path(record.parent_dir, &self.pool, &mut path);
                if !path.ends_with('/') {
                    path.push('/');
                }
                path.push_str(self.pool.get(record.name_offset, record.name_len));
                path
            };

            let clean_full = full_path.trim_end_matches('/');
            if clean_full == clean_target
                || clean_full.starts_with(&format!("{}/", clean_target))
            {
                record.mark_deleted();
                freed_bytes += record.size;
            }
        }

        freed_bytes
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

    /// Saves binary compressed snapshot of the entire volume index to disk.
    pub fn save_snapshot(&self, dest: &Path) -> std::io::Result<()> {
        let bytes = bincode::serialize(self)
            .map_err(|e| std::io::Error::new(std::io::ErrorKind::Other, e.to_string()))?;
        std::fs::write(dest, bytes)
    }

    /// Loads an offline volume catalog snapshot from disk.
    pub fn load_snapshot(src: &Path) -> std::io::Result<Self> {
        let bytes = std::fs::read(src)?;
        let mut index: Self = bincode::deserialize(&bytes)
            .map_err(|e| std::io::Error::new(std::io::ErrorKind::Other, e.to_string()))?;
        index.is_online = false; // Loaded from offline snapshot
        Ok(index)
    }

    /// Approximate heap memory consumed in bytes.
    pub fn estimated_memory_bytes(&self) -> usize {
        self.pool.len_bytes()
            + (self.records.len() * std::mem::size_of::<FileRecord>())
            + (self.dirs.len() * 16)
    }
}
