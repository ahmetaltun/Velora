use crate::pool::StringPool;
use crate::record::DirId;
use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub struct DirectoryEntry {
    pub name_offset: u32,
    pub name_len: u16,
    pub parent: Option<DirId>,
}

#[derive(Debug, Default, Clone, Serialize, Deserialize)]
pub struct DirectoryTable {
    entries: Vec<DirectoryEntry>,
}

impl DirectoryTable {
    pub fn new() -> Self {
        Self {
            entries: Vec::with_capacity(128 * 1024),
        }
    }

    pub fn insert(&mut self, name_offset: u32, name_len: u16, parent: Option<DirId>) -> DirId {
        let id = DirId(self.entries.len() as u32);
        self.entries.push(DirectoryEntry {
            name_offset,
            name_len,
            parent,
        });
        id
    }

    pub fn get(&self, id: DirId) -> Option<&DirectoryEntry> {
        self.entries.get(id.0 as usize)
    }

    pub fn len(&self) -> usize {
        self.entries.len()
    }

    pub fn is_empty(&self) -> bool {
        self.entries.is_empty()
    }

    /// Reconstructs full path into a target String buffer without allocating intermediate strings.
    pub fn build_full_path(&self, id: DirId, pool: &StringPool, out: &mut String) {
        let mut components = Vec::with_capacity(16);
        let mut curr = Some(id);
        while let Some(dir_id) = curr {
            if let Some(entry) = self.get(dir_id) {
                components.push((entry.name_offset, entry.name_len));
                curr = entry.parent;
            } else {
                break;
            }
        }

        for (offset, len) in components.into_iter().rev() {
            let part = pool.get(offset, len);
            if !part.is_empty() {
                if !out.ends_with('/') && !part.starts_with('/') {
                    out.push('/');
                }
                out.push_str(part);
            }
        }
    }
}
