use crate::model::{DevArtifactItem, DevArtifactKind, InactivityTier};
use std::collections::HashMap;
use std::time::{SystemTime, UNIX_EPOCH};
use velora_analyzer::SizeRollup;
use velora_index::{DirId, VolumeIndex};

#[derive(Default, Clone, Copy)]
struct DirMarkers {
    has_cargo_toml: bool,
    has_package_json: bool,
    has_package_swift: bool,
    has_pyproject_or_reqs: bool,
    has_gradle: bool,
}

pub struct ArtifactHunter;

impl ArtifactHunter {
    /// Discovers developer build artifacts across the indexed volume using strict context verification.
    pub fn hunt(volume: &VolumeIndex, min_size_bytes: u64) -> Vec<DevArtifactItem> {
        let rollup = SizeRollup::compute(volume);
        let now_secs = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap_or_default()
            .as_secs();

        // Pass 1: Build directory markers to strictly verify project context in O(N)
        let dir_count = volume.dirs.len();
        let mut markers = vec![DirMarkers::default(); dir_count];

        for record in &volume.records {
            let p = record.parent_dir.0 as usize;
            if p >= dir_count {
                continue;
            }
            let name = volume.get_file_name(record);
            match name {
                "Cargo.toml" | "Cargo.lock" => markers[p].has_cargo_toml = true,
                "package.json" => markers[p].has_package_json = true,
                "Package.swift" => markers[p].has_package_swift = true,
                "pyproject.toml" | "requirements.txt" | "pyvenv.cfg" | "setup.py" => {
                    markers[p].has_pyproject_or_reqs = true
                }
                "build.gradle" | "build.gradle.kts" | "settings.gradle" => {
                    markers[p].has_gradle = true
                }
                _ => {}
            }
        }

        // Build mapping from (ParentDirId, name) -> ChildDirId to quickly find DirId for rollup size
        let mut dir_lookup: HashMap<(DirId, &str), DirId> = HashMap::with_capacity(dir_count);
        for i in 0..dir_count {
            let id = DirId(i as u32);
            if let Some(entry) = volume.dirs.get(id) {
                if let Some(parent) = entry.parent {
                    let name = volume.pool.get(entry.name_offset, entry.name_len);
                    dir_lookup.insert((parent, name), id);
                }
            }
        }

        let mut results = Vec::new();

        // Pass 2: Identify genuine build artifacts with verified parent markers
        for record in &volume.records {
            if !record.is_dir() {
                continue;
            }

            let name = volume.get_file_name(record);
            let parent = record.parent_dir;
            let p_idx = parent.0 as usize;
            if p_idx >= dir_count {
                continue;
            }

            let marker = markers[p_idx];

            let kind = if name == "target" && marker.has_cargo_toml {
                Some(DevArtifactKind::RustTarget)
            } else if name == "node_modules" && marker.has_package_json {
                Some(DevArtifactKind::NodeModules)
            } else if name == ".build" && marker.has_package_swift {
                Some(DevArtifactKind::SwiftBuild)
            } else if (name == ".venv" || name == "venv") && marker.has_pyproject_or_reqs {
                Some(DevArtifactKind::PythonVenv)
            } else if (name == "build" || name == ".gradle") && marker.has_gradle {
                Some(DevArtifactKind::GradleBuild)
            } else {
                None
            };

            if let Some(artifact_kind) = kind {
                // Find directory id to get recursive rollup size
                let child_id = dir_lookup.get(&(parent, name)).copied();
                let size_bytes = child_id.map(|id| rollup.get_size(id)).unwrap_or(0);

                if size_bytes < min_size_bytes {
                    continue;
                }

                let path = volume.resolve_full_path(record);

                // Parent project name from parent dir entry
                let parent_project_name = if let Some(parent_entry) = volume.dirs.get(parent) {
                    volume.pool.get(parent_entry.name_offset, parent_entry.name_len).to_string()
                } else {
                    "Unknown Project".to_string()
                };

                // Inactivity calculation
                let age_secs = now_secs.saturating_sub(record.modified_secs);
                let inactivity = if age_secs < 14 * 86_400 {
                    InactivityTier::Active
                } else if age_secs < 60 * 86_400 {
                    InactivityTier::Idle
                } else {
                    InactivityTier::Stale
                };

                results.push(DevArtifactItem {
                    path,
                    name: name.to_string(),
                    kind: artifact_kind,
                    size_bytes,
                    modified_secs: record.modified_secs,
                    inactivity,
                    parent_project_name,
                    color_hex: artifact_kind.color_hex().to_string(),
                });
            }
        }

        // Sort descending by size (largest artifacts first)
        results.sort_by(|a, b| b.size_bytes.cmp(&a.size_bytes));
        results
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use velora_index::{FileFlags, FileRecord};

    #[test]
    fn test_strict_context_verification() {
        let mut vol = VolumeIndex::new("Test", "/");
        let (root_off, root_len) = vol.pool.push("/");
        let root_dir = vol.dirs.insert(root_off, root_len, None);

        // Project folder: my_rust_app
        let (proj_off, proj_len) = vol.pool.push("my_rust_app");
        let proj_dir = vol.dirs.insert(proj_off, proj_len, Some(root_dir));
        vol.add_file(FileRecord::new(proj_off, proj_len, FileFlags::IS_DIRECTORY, root_dir, 0, 1000));

        // Cargo.toml inside my_rust_app
        let (cargo_off, cargo_len) = vol.pool.push("Cargo.toml");
        vol.add_file(FileRecord::new(cargo_off, cargo_len, FileFlags::empty(), proj_dir, 500, 1000));

        // target/ inside my_rust_app
        let (target_off, target_len) = vol.pool.push("target");
        let target_dir = vol.dirs.insert(target_off, target_len, Some(proj_dir));
        vol.add_file(FileRecord::new(target_off, target_len, FileFlags::IS_DIRECTORY, proj_dir, 0, 1000));

        // File inside target/
        let (bin_off, bin_len) = vol.pool.push("debug_binary");
        vol.add_file(FileRecord::new(bin_off, bin_len, FileFlags::empty(), target_dir, 50_000_000, 1000));

        // Fake target folder without Cargo.toml (should be skipped!)
        let (other_off, other_len) = vol.pool.push("random_folder");
        let other_dir = vol.dirs.insert(other_off, other_len, Some(root_dir));
        let (fake_off, fake_len) = vol.pool.push("target");
        let fake_dir = vol.dirs.insert(fake_off, fake_len, Some(other_dir));
        vol.add_file(FileRecord::new(fake_off, fake_len, FileFlags::IS_DIRECTORY, other_dir, 0, 1000));
        let (dummy_off, dummy_len) = vol.pool.push("some_file");
        vol.add_file(FileRecord::new(dummy_off, dummy_len, FileFlags::empty(), fake_dir, 10_000, 1000));

        let artifacts = ArtifactHunter::hunt(&vol, 0);

        // Should only match genuine my_rust_app/target!
        assert_eq!(artifacts.len(), 1);
        assert_eq!(artifacts[0].name, "target");
        assert_eq!(artifacts[0].kind, DevArtifactKind::RustTarget);
        assert_eq!(artifacts[0].size_bytes, 50_000_000);
        assert_eq!(artifacts[0].parent_project_name, "my_rust_app");
    }
}
