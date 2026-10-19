use crate::flags::FileFlags;
use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Default, Serialize, Deserialize)]
pub struct DirId(pub u32);

#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Default, Serialize, Deserialize)]
pub struct FileId(pub u32);

/// Packed 32-byte representation of file metadata.
/// Fits two complete records per 64-byte L1 cache line on Apple Silicon.
#[repr(C)]
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub struct FileRecord {
    pub name_offset: u32,
    pub name_len: u16,
    pub flags: FileFlags,
    pub parent_dir: DirId,
    pub size: u64,
    pub modified_secs: u64,
}

impl FileRecord {
    #[inline(always)]
    pub fn new(
        name_offset: u32,
        name_len: u16,
        flags: FileFlags,
        parent_dir: DirId,
        size: u64,
        modified_secs: u64,
    ) -> Self {
        Self {
            name_offset,
            name_len,
            flags,
            parent_dir,
            size,
            modified_secs,
        }
    }

    #[inline(always)]
    pub fn is_dir(&self) -> bool {
        self.flags.contains(FileFlags::IS_DIRECTORY)
    }

    #[inline(always)]
    pub fn is_hidden(&self) -> bool {
        self.flags.contains(FileFlags::IS_HIDDEN)
    }
}
