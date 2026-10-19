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
