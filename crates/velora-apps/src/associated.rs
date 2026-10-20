use crate::bundle::BundleScanner;
use crate::index_resolver::IndexFootprintResolver;
use crate::model::{AppPart, AppPartKind, InstalledApp};
use std::path::Path;

pub struct AssociatedFileResolver;

impl AssociatedFileResolver {
    /// Discovers all associated files and sandboxed containers for an application across `~/Library`.
    pub fn resolve_associated_files(
        app: &mut InstalledApp,
        home_path: &Path,
        resolver: Option<&IndexFootprintResolver>,
    ) {
        let lib_path = home_path.join("Library");
        let bundle_id = &app.bundle_id;
        let app_name = &app.name;

        let mut additional_parts = Vec::new();

        // 1. Application Support
        let app_support = lib_path.join("Application Support");
        Self::check_candidate(
            &app_support.join(bundle_id),
            AppPartKind::ApplicationSupport,
            "App Support Data",
            resolver,
            &mut additional_parts,
        );
        if bundle_id != app_name {
            Self::check_candidate(
                &app_support.join(app_name),
                AppPartKind::ApplicationSupport,
                "App Support Data",
                resolver,
                &mut additional_parts,
            );
        }

        // 2. Caches & WebKit & Logs
        let caches = lib_path.join("Caches");
        Self::check_candidate(
            &caches.join(bundle_id),
            AppPartKind::CachesAndLogs,
            "Caches",
            resolver,
            &mut additional_parts,
        );
        if bundle_id != app_name {
            Self::check_candidate(
                &caches.join(app_name),
                AppPartKind::CachesAndLogs,
                "Caches",
                resolver,
                &mut additional_parts,
            );
        }

        let webkit = lib_path.join("WebKit");
        Self::check_candidate(
            &webkit.join(bundle_id),
            AppPartKind::CachesAndLogs,
            "WebKit Storage",
            resolver,
            &mut additional_parts,
        );

        let logs = lib_path.join("Logs");
        Self::check_candidate(
            &logs.join(bundle_id),
            AppPartKind::CachesAndLogs,
            "Logs",
            resolver,
            &mut additional_parts,
        );
        if bundle_id != app_name {
            Self::check_candidate(
                &logs.join(app_name),
                AppPartKind::CachesAndLogs,
                "Logs",
                resolver,
                &mut additional_parts,
            );
        }

        let http_storages = lib_path.join("HTTPStorages");
        Self::check_candidate(
            &http_storages.join(bundle_id),
            AppPartKind::CachesAndLogs,
            "HTTP Storage",
            resolver,
            &mut additional_parts,
        );

        // 3. Sandboxed Container
        let containers = lib_path.join("Containers");
        Self::check_candidate(
            &containers.join(bundle_id),
            AppPartKind::SandboxedContainer,
            "Sandboxed Container",
            resolver,
            &mut additional_parts,
        );

        // Group Containers
        let group_containers = lib_path.join("Group Containers");
        if let Some(res) = resolver {
            for (p, folder_name, _) in res.list_subdirs(&group_containers) {
                if folder_name.contains(bundle_id) || folder_name.contains(app_name) {
                    Self::check_candidate(
                        &p,
                        AppPartKind::SandboxedContainer,
                        "Group Container",
                        resolver,
                        &mut additional_parts,
                    );
                }
            }
        } else if group_containers.exists() {
            if let Ok(entries) = std::fs::read_dir(&group_containers) {
                for entry_res in entries.flatten() {
                    let p = entry_res.path();
                    let folder_name = entry_res.file_name().to_string_lossy().to_string();
                    if folder_name.contains(bundle_id) || folder_name.contains(app_name) {
                        Self::check_candidate(
                            &p,
                            AppPartKind::SandboxedContainer,
                            "Group Container",
                            resolver,
                            &mut additional_parts,
                        );
                    }
                }
            }
        }

        // 4. Preferences & Saved Application State & LaunchAgents
        let prefs = lib_path.join("Preferences");
        Self::check_candidate(
            &prefs.join(format!("{}.plist", bundle_id)),
            AppPartKind::PreferencesAndDaemons,
            "Preferences Plist",
            resolver,
            &mut additional_parts,
        );

        let saved_state = lib_path.join("Saved Application State");
        Self::check_candidate(
            &saved_state.join(format!("{}.savedState", bundle_id)),
            AppPartKind::PreferencesAndDaemons,
            "Saved Window State",
            resolver,
            &mut additional_parts,
        );

        let launch_agents = lib_path.join("LaunchAgents");
        if let Some(res) = resolver {
            if let Some(la_dir) = res.volume.find_dir_by_path(&launch_agents) {
                for rec in &res.volume.records {
                    if !rec.is_deleted() && !rec.is_dir() && rec.parent_dir == la_dir {
                        let file_name = res.volume.get_file_name(rec);
                        if file_name.contains(bundle_id) || file_name.contains(app_name) {
                            let p = res.volume.resolve_full_path(rec);
                            Self::check_candidate(
                                Path::new(&p),
                                AppPartKind::PreferencesAndDaemons,
                                "Background LaunchAgent",
                                resolver,
                                &mut additional_parts,
                            );
                        }
                    }
                }
            }
        } else if launch_agents.exists() {
            if let Ok(entries) = std::fs::read_dir(&launch_agents) {
                for entry_res in entries.flatten() {
                    let p = entry_res.path();
                    let file_name = entry_res.file_name().to_string_lossy().to_string();
                    if file_name.contains(bundle_id) || file_name.contains(app_name) {
                        Self::check_candidate(
                            &p,
                            AppPartKind::PreferencesAndDaemons,
                            "Background LaunchAgent",
                            resolver,
                            &mut additional_parts,
                        );
                    }
                }
            }
        }

        // Deduplicate and append
        for part in additional_parts {
            if !app.parts.iter().any(|existing| existing.path == part.path) {
                app.total_size_bytes += part.size_bytes;
                app.parts.push(part);
            }
        }
    }

    fn check_candidate(
        path: &Path,
        kind: AppPartKind,
        label: &str,
        resolver: Option<&IndexFootprintResolver>,
        out: &mut Vec<AppPart>,
    ) {
        let size_bytes = if let Some(res) = resolver {
            res.query_size(path).unwrap_or(0)
        } else {
            if !path.exists() {
                return;
            }
            if path.is_file() {
                path.metadata().map(|m| m.len()).unwrap_or(0)
            } else {
                BundleScanner::calculate_dir_size(path)
            }
        };

        if size_bytes == 0 {
            return;
        }

        out.push(AppPart {
            name: format!(
                "{} ({})",
                label,
                path.file_name()
                    .map(|n| n.to_string_lossy().to_string())
                    .unwrap_or_default()
            ),
            path: path.to_string_lossy().to_string(),
            kind,
            size_bytes,
            color_hex: kind.color_hex().to_string(),
        });
    }
}
