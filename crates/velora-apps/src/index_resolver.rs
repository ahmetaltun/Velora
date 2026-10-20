use std::collections::HashMap;
use std::path::{Path, PathBuf};
use velora_analyzer::SizeRollup;
use velora_index::{DirId, VolumeIndex};

/// In-memory catalog resolver for application bundles and associated library footprints.
/// Queries the pre-indexed `VolumeIndex` and `SizeRollup` in RAM, avoiding physical disk I/O.
pub struct IndexFootprintResolver<'a> {
    pub volume: &'a VolumeIndex,
    pub rollup: SizeRollup,
    dir_sizes: HashMap<String, u64>,
    file_sizes: HashMap<String, u64>,
}

impl<'a> IndexFootprintResolver<'a> {
    pub fn new(volume: &'a VolumeIndex, home_path: &Path) -> Self {
        let rollup = SizeRollup::compute(volume);
        let dir_count = volume.dirs.len();

        let mut dir_sizes = HashMap::with_capacity(dir_count.min(10_000));
        let mut file_sizes = HashMap::with_capacity(5_000);

        let home_str = home_path.to_string_lossy().to_string();
        let lib_prefix = format!("{}/Library", home_str.trim_end_matches('/'));

        // 1. Index relevant directories (/Applications and ~/Library) with their precomputed rollup sizes
        for i in 0..dir_count {
            let id = DirId(i as u32);
            let mut path = String::with_capacity(128);
            volume.dirs.build_full_path(id, &volume.pool, &mut path);
            let clean = path.trim_end_matches('/').to_string();

            if clean.starts_with("/Applications")
                || clean.starts_with("/System/Applications")
                || clean.starts_with(&lib_prefix)
            {
                let size = rollup.get_size(id);
                dir_sizes.insert(clean, size);
            }
        }

        // 2. Index relevant single files (e.g. Preferences plists and LaunchAgents)
        for record in &volume.records {
            if record.is_deleted() || record.is_dir() {
                continue;
            }

            let full = volume.resolve_full_path(record);
            if full.contains("/Library/Preferences/") || full.contains("/Library/LaunchAgents/") {
                file_sizes.insert(full, record.size);
            }
        }

        Self {
            volume,
            rollup,
            dir_sizes,
            file_sizes,
        }
    }

    /// Queries the pre-computed size of a directory or file in memory.
    pub fn query_size(&self, path: &Path) -> Option<u64> {
        let path_str = path.to_string_lossy();
        let clean = path_str.trim_end_matches('/');

        if let Some(&size) = self.dir_sizes.get(clean) {
            return Some(size);
        }

        if let Some(&size) = self.file_sizes.get(clean) {
            return Some(size);
        }

        None
    }

    /// Lists immediate subdirectories located directly under `parent_dir` with their precomputed sizes.
    pub fn list_subdirs(&self, parent_dir: &Path) -> Vec<(PathBuf, String, u64)> {
        let parent_str = parent_dir.to_string_lossy();
        let clean_parent = parent_str.trim_end_matches('/');
        let prefix = format!("{}/", clean_parent);

        let mut results = Vec::new();

        for (dir_path, &size) in &self.dir_sizes {
            if dir_path.starts_with(&prefix) {
                let remainder = &dir_path[prefix.len()..];
                // Only immediate children (no subsequent slash)
                if !remainder.contains('/') && !remainder.is_empty() {
                    results.push((PathBuf::from(dir_path), remainder.to_string(), size));
                }
            }
        }

        results
    }
}
