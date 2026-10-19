use crate::model::{AppPart, AppPartKind, InstalledApp};
use plist::Value;
use std::fs;
use std::io::Cursor;
use std::path::{Path, PathBuf};

pub struct BundleScanner;

impl BundleScanner {
    /// Discovers all installed applications across `/Applications` and `~/Applications`.
    pub fn scan_installed_apps(home_path: &Path) -> Vec<InstalledApp> {
        let mut app_roots = vec![PathBuf::from("/Applications")];
        let user_apps = home_path.join("Applications");
        if user_apps.exists() {
            app_roots.push(user_apps);
        }

        let mut apps = Vec::new();

        for root in &app_roots {
            Self::scan_directory_for_apps(root, false, &mut apps);
        }

        // Also discover system apps for completeness (marked protected)
        let sys_apps = PathBuf::from("/System/Applications");
        if sys_apps.exists() {
            Self::scan_directory_for_apps(&sys_apps, true, &mut apps);
        }

        apps.sort_by(|a, b| a.name.to_lowercase().cmp(&b.name.to_lowercase()));
        apps
    }

    pub fn scan_directory_for_apps(dir: &Path, is_system: bool, out: &mut Vec<InstalledApp>) {
        let entries = match fs::read_dir(dir) {
            Ok(e) => e,
            Err(_) => return,
        };

        for entry_res in entries {
            let entry = match entry_res {
                Ok(e) => e,
                Err(_) => continue,
            };

            let path = entry.path();
            if path.extension().and_then(|e| e.to_str()) == Some("app") {
                if let Some(app) = Self::inspect_app_bundle(&path, is_system) {
                    out.push(app);
                }
            } else if path.is_dir() && !path.is_symlink() {
                // Check subdirectories (e.g., /Applications/Utilities)
                let name = entry.file_name().to_string_lossy().to_string();
                if name == "Utilities" {
                    Self::scan_directory_for_apps(&path, is_system, out);
                }
            }
        }
    }

    pub fn inspect_app_bundle(app_path: &Path, is_system_app: bool) -> Option<InstalledApp> {
        let info_plist_path = app_path.join("Contents/Info.plist");
        let (bundle_id, name, version) = if info_plist_path.exists() {
            Self::parse_info_plist(&info_plist_path)
        } else {
            (None, None, None)
        };

        let fallback_name = app_path
            .file_stem()
            .and_then(|s| s.to_str())
            .unwrap_or("Unknown App")
            .to_string();

        let final_name = name.unwrap_or(fallback_name);
        let final_bundle_id = bundle_id.unwrap_or_else(|| {
            format!("local.velora.{}", final_name.to_lowercase().replace(' ', "-"))
        });
        let final_version = version.unwrap_or_else(|| "1.0".to_string());

        let bundle_size = Self::calculate_dir_size(app_path);

        let bundle_part = AppPart {
            name: format!("{}.app", final_name),
            path: app_path.to_string_lossy().to_string(),
            kind: AppPartKind::ApplicationBundle,
            size_bytes: bundle_size,
            color_hex: AppPartKind::ApplicationBundle.color_hex().to_string(),
        };

        Some(InstalledApp {
            name: final_name,
            bundle_id: final_bundle_id,
            version: final_version,
            app_path: app_path.to_string_lossy().to_string(),
            is_system_app,
            total_size_bytes: bundle_size,
            parts: vec![bundle_part],
        })
    }

    fn parse_info_plist(path: &Path) -> (Option<String>, Option<String>, Option<String>) {
        let bytes = match fs::read(path) {
            Ok(b) => b,
            Err(_) => return (None, None, None),
        };

        let val: Value = match Value::from_reader(Cursor::new(&bytes)) {
            Ok(v) => v,
            Err(_) => return (None, None, None),
        };

        let dict = match val.as_dictionary() {
            Some(d) => d,
            None => return (None, None, None),
        };

        let bundle_id = dict
            .get("CFBundleIdentifier")
            .and_then(|v| v.as_string())
            .map(|s| s.to_string());

        let name = dict
            .get("CFBundleDisplayName")
            .or_else(|| dict.get("CFBundleName"))
            .and_then(|v| v.as_string())
            .map(|s| s.to_string());

        let version = dict
            .get("CFBundleShortVersionString")
            .or_else(|| dict.get("CFBundleVersion"))
            .and_then(|v| v.as_string())
            .map(|s| s.to_string());

        (bundle_id, name, version)
    }

    pub fn calculate_dir_size(path: &Path) -> u64 {
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
    fn test_inspect_dummy_app_bundle() {
        let temp = std::env::temp_dir().join("velora_dummy_app.app");
        let contents = temp.join("Contents");
        let _ = fs::remove_dir_all(&temp);
        fs::create_dir_all(&contents).unwrap();

        let plist_xml = r#"<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key>
    <string>com.velora.testapp</string>
    <key>CFBundleName</key>
    <string>TestApp</string>
    <key>CFBundleShortVersionString</key>
    <string>2.4.0</string>
</dict>
</plist>"#;

        fs::write(contents.join("Info.plist"), plist_xml).unwrap();
        fs::write(contents.join("binary"), vec![0u8; 5000]).unwrap();

        let app = BundleScanner::inspect_app_bundle(&temp, false).unwrap();
        assert_eq!(app.name, "TestApp");
        assert_eq!(app.bundle_id, "com.velora.testapp");
        assert_eq!(app.version, "2.4.0");
        assert!(app.total_size_bytes >= 5000);

        let _ = fs::remove_dir_all(&temp);
    }
}
