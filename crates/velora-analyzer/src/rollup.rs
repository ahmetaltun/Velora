use velora_index::{DirId, VolumeIndex};

pub struct SizeRollup {
    pub dir_sizes: Vec<u64>,
}

impl SizeRollup {
    pub fn compute(volume: &VolumeIndex) -> Self {
        let dir_count = volume.dirs.len();
        let mut dir_sizes = vec![0u64; dir_count];

        // Pass 1: Aggregate direct file sizes
        for record in &volume.records {
            if !record.is_dir() && !record.is_deleted() {
                let p = record.parent_dir.0 as usize;
                if p < dir_count {
                    dir_sizes[p] += record.size;
                }
            }
        }

        // Pass 2: Bottom-up aggregation using reverse topological order
        // In DirectoryTable, children are created after parents (child_id > parent_id)
        for i in (0..dir_count).rev() {
            let child_size = dir_sizes[i];
            if let Some(entry) = volume.dirs.get(DirId(i as u32)) {
                if let Some(parent) = entry.parent {
                    let p = parent.0 as usize;
                    if p < dir_count {
                        dir_sizes[p] += child_size;
                    }
                }
            }
        }

        Self { dir_sizes }
    }

    #[inline(always)]
    pub fn get_size(&self, dir_id: DirId) -> u64 {
        self.dir_sizes.get(dir_id.0 as usize).copied().unwrap_or(0)
    }
}
