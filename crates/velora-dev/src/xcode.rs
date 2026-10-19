use crate::model::{XcodeCategoryKind, XcodeItem, XcodeStorageSummary};
use std::fs;
use std::path::{Path, PathBuf};
use std::process::Command;

pub struct XcodeInspector;

impl XcodeInspector {
    /// Discovers and summarizes all Xcode storage locations starting from a user's home directory.
    pub fn inspect_home(home_path: &Path) -> XcodeStorageSummary {
        let dev_dir = home_path.join("Library/Developer");
        let xcode_dir = dev_dir.join("Xcode");
        let sim_dir = dev_dir.join("CoreSimulator/Devices");

        let mut summary = XcodeStorageSummary::default();

        // 1. DerivedData
        let derived_data_path = xcode_dir.join("DerivedData");
        Self::scan_subdirectories(
            &derived_data_path,
            XcodeCategoryKind::DerivedData,
            &mut summary,
        );

        // 2. Archives
        let archives_path = xcode_dir.join("Archives");
        Self::scan_archives(&archives_path, &mut summary);

        // 3. Device Support (iOS, watchOS, tvOS)
        let support_dirs = [
            xcode_dir.join("iOS DeviceSupport"),
            xcode_dir.join("watchOS DeviceSupport"),
            xcode_dir.join("tvOS DeviceSupport"),
        ];
        for s_dir in &support_dirs {
            Self::scan_subdirectories(s_dir, XcodeCategoryKind::DeviceSupport, &mut summary);
        }

        // 4. CoreSimulator Devices
        Self::scan_subdirectories(&sim_dir, XcodeCategoryKind::Simulators, &mut summary);

        // Compute category totals
        for item in &summary.items {
            summary.total_bytes += item.size_bytes;
            match item.category {
                XcodeCategoryKind::DerivedData => summary.derived_data_bytes += item.size_bytes,
                XcodeCategoryKind::Archives => summary.archives_bytes += item.size_bytes,
                XcodeCategoryKind::DeviceSupport => summary.device_support_bytes += item.size_bytes,
                XcodeCategoryKind::Simulators => summary.simulator_bytes += item.size_bytes,
                XcodeCategoryKind::DocumentationCache => {}
            }
        }

        // Sort items descending by size
        summary.items.sort_by(|a, b| b.size_bytes.cmp(&a.size_bytes));
        summary
    }

    /// Invokes the native non-privileged Xcode CLI to delete unavailable simulator runtimes.
    pub fn prune_unavailable_simulators() -> bool {
        Command::new("xcrun")
            .arg("simctl")
            .arg("delete")
            .arg("unavailable")
            .output()
            .map(|out| out.status.success())
            .unwrap_or(false)
    }

    fn scan_subdirectories(
        parent_path: &Path,
        category: XcodeCategoryKind,
        summary: &mut XcodeStorageSummary,
    ) {
        let entries = match fs::read_dir(parent_path) {
            Ok(e) => e,
            Err(_) => return,
        };

        for entry_res in entries {
            let entry = match entry_res {
                Ok(e) => e,
                Err(_) => continue,
            };

            let path = entry.path();
            if !path.is_dir() {
                continue;
            }

            let raw_name = entry.file_name().to_string_lossy().to_string();
            // Clean project name from DerivedData folder hash (e.g. "Velora-abcdefgh..." -> "Velora")
            let display_name = if category == XcodeCategoryKind::DerivedData {
                if let Some(hyphen_idx) = raw_name.rfind('-') {
                    if hyphen_idx > 0 && hyphen_idx + 20 <= raw_name.len() {
                        raw_name[0..hyphen_idx].to_string()
                    } else {
                        raw_name.clone()
                    }
                } else {
                    raw_name.clone()
                }
            } else {
                raw_name.clone()
            };

            let meta = entry.metadata().ok();
            let modified_secs = meta
                .and_then(|m| m.modified().ok())
                .and_then(|t| t.duration_since(std::time::UNIX_EPOCH).ok())
                .map(|d| d.as_secs())
                .unwrap_or(0);

            let size_bytes = Self::calculate_dir_size(&path);

            summary.items.push(XcodeItem {
                name: display_name,
                path: path.to_string_lossy().to_string(),
                category,
                size_bytes,
                modified_secs,
                color_hex: category.color_hex().to_string(),
            });
        }
    }

    fn scan_archives(archives_root: &Path, summary: &mut XcodeStorageSummary) {
        let date_entries = match fs::read_dir(archives_root) {
            Ok(e) => e,
            Err(_) => return,
        };

        for date_res in date_entries {
            let date_dir = match date_res {
                Ok(d) if d.path().is_dir() => d.path(),
                _ => continue,
            };

            let archive_entries = match fs::read_dir(&date_dir) {
                Ok(e) => e,
                Err(_) => continue,
            };

            for entry_res in archive_entries {
                let entry = match entry_res {
                    Ok(e) => e,
                    Err(_) => continue,
                };

                let path = entry.path();
                if path.extension().and_then(|e| e.to_str()) == Some("xcarchive") {
                    let name = entry.file_name().to_string_lossy().to_string();
                    let meta = entry.metadata().ok();
                    let modified_secs = meta
                        .and_then(|m| m.modified().ok())
                        .and_then(|t| t.duration_since(std::time::UNIX_EPOCH).ok())
                        .map(|d| d.as_secs())
                        .unwrap_or(0);

                    let size_bytes = Self::calculate_dir_size(&path);

                    summary.items.push(XcodeItem {
                        name,
                        path: path.to_string_lossy().to_string(),
                        category: XcodeCategoryKind::Archives,
                        size_bytes,
                        modified_secs,
                        color_hex: XcodeCategoryKind::Archives.color_hex().to_string(),
                    });
                }
            }
        }
    }

    fn calculate_dir_size(path: &Path) -> u64 {
        let mut total = 0u64;
        let mut stack = vec![PathBuf::from(path)];

        while let Some(current) = stack.pop() {
            if let Ok(entries) = fs::read_dir(&current) {
                for entry_res in entries {
                    if let Ok(entry) = entry_res {
                        let p = entry.path();
                        if p.is_symlink() {
                            continue;
                        }
                        if p.is_dir() {
                            stack.push(p);
                        } else if let Ok(meta) = entry.metadata() {
                            total += meta.len();
                        }
                    }
                }
            }
        }

        total
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_xcode_inspector_empty_dir() {
        let temp = std::env::temp_dir().join("velora_test_xcode_inspector");
        let _ = fs::remove_dir_all(&temp);
        fs::create_dir_all(&temp).unwrap();

        let summary = XcodeInspector::inspect_home(&temp);
        assert_eq!(summary.total_bytes, 0);
        assert!(summary.items.is_empty());

        let _ = fs::remove_dir_all(&temp);
    }
}
