use crate::bundle::BundleScanner;
use crate::model::{InstalledApp, OrphanedResidue};
use std::collections::HashSet;
use std::fs;
use std::path::Path;

pub struct OrphanDetector;

impl OrphanDetector {
    /// Detects leftover folders in `~/Library` belonging to applications that have already been uninstalled.
    pub fn find_orphaned_residue(
        home_path: &Path,
        installed_apps: &[InstalledApp],
    ) -> Vec<OrphanedResidue> {
        let lib_path = home_path.join("Library");

        // Build index of known bundle IDs and app names (lowercase for fuzzy matching)
        let mut known_ids = HashSet::new();
        let mut known_names = HashSet::new();

        for app in installed_apps {
            known_ids.insert(app.bundle_id.to_lowercase());
            known_names.insert(app.name.to_lowercase());
        }

        let mut orphans = Vec::new();

        // Target locations to check for residue
        let targets = [
            (lib_path.join("Application Support"), "Application Support"),
            (lib_path.join("Caches"), "Cache Storage"),
            (lib_path.join("Containers"), "Sandboxed Container"),
            (lib_path.join("Saved Application State"), "Saved Window State"),
        ];

        for (dir_path, category) in &targets {
            Self::scan_target_for_orphans(dir_path, category, &known_ids, &known_names, &mut orphans);
        }

        // Sort descending by size
        orphans.sort_by(|a, b| b.size_bytes.cmp(&a.size_bytes));
        orphans
    }

    fn scan_target_for_orphans(
        dir: &Path,
        category: &str,
        known_ids: &HashSet<String>,
        known_names: &HashSet<String>,
        out: &mut Vec<OrphanedResidue>,
    ) {
        let entries = match fs::read_dir(dir) {
            Ok(e) => e,
            Err(_) => return,
        };

        for entry_res in entries.flatten() {
            let path = entry_res.path();
            let raw_name = entry_res.file_name().to_string_lossy().to_string();

            // Skip Apple system folders and internal components
            if raw_name.starts_with("com.apple.")
                || raw_name == "Apple"
                || raw_name == "iCloud"
                || raw_name == "CloudDocs"
                || raw_name == "AddressBook"
                || raw_name == "CallHistoryDB"
                || raw_name == "Safari"
                || raw_name == "Messages"
                || raw_name == "Mail"
                || raw_name == "Photos"
                || raw_name == "MobileSync"
                || raw_name.starts_with('.')
            {
                continue;
            }

            let name_lower = raw_name.to_lowercase();
            let clean_name = name_lower.trim_end_matches(".savedstate");

            // Check if matches any active installed app
            let is_active = known_ids.contains(clean_name)
                || known_names.contains(clean_name)
                || known_ids.iter().any(|id| clean_name.contains(id.as_str()))
                || known_names.iter().any(|name| clean_name.contains(name.as_str()));

            if !is_active {
                let size_bytes = if path.is_file() {
                    path.metadata().map(|m| m.len()).unwrap_or(0)
                } else {
                    BundleScanner::calculate_dir_size(&path)
                };

                // Only surface non-trivial leftovers (> 500 KB)
                if size_bytes < 500_000 {
                    continue;
                }

                let modified_secs = path
                    .metadata()
                    .ok()
                    .and_then(|m| m.modified().ok())
                    .and_then(|t| t.duration_since(std::time::UNIX_EPOCH).ok())
                    .map(|d| d.as_secs())
                    .unwrap_or(0);

                out.push(OrphanedResidue {
                    name: raw_name.clone(),
                    path: path.to_string_lossy().to_string(),
                    inferred_bundle_id: clean_name.to_string(),
                    category_name: category.to_string(),
                    size_bytes,
                    modified_secs,
                });
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_orphan_detection() {
        let temp = std::env::temp_dir().join("velora_test_orphans");
        let _ = fs::remove_dir_all(&temp);
        let app_support = temp.join("Library/Application Support");
        fs::create_dir_all(&app_support).unwrap();

        // Installed app folder
        let installed_dir = app_support.join("com.test.installed");
        fs::create_dir_all(&installed_dir).unwrap();
        fs::write(installed_dir.join("data"), vec![0u8; 1_000_000]).unwrap();

        // Orphan folder from uninstalled app
        let orphan_dir = app_support.join("com.olduninstalled.app");
        fs::create_dir_all(&orphan_dir).unwrap();
        fs::write(orphan_dir.join("data"), vec![0u8; 2_000_000]).unwrap();

        let installed_apps = vec![InstalledApp {
            name: "Installed App".to_string(),
            bundle_id: "com.test.installed".to_string(),
            version: "1.0".to_string(),
            app_path: "/Applications/Installed.app".to_string(),
            is_system_app: false,
            total_size_bytes: 1_000_000,
            parts: Vec::new(),
        }];

        let orphans = OrphanDetector::find_orphaned_residue(&temp, &installed_apps);
        assert_eq!(orphans.len(), 1);
        assert_eq!(orphans[0].name, "com.olduninstalled.app");
        assert_eq!(orphans[0].size_bytes, 2_000_000);

        let _ = fs::remove_dir_all(&temp);
    }
}
