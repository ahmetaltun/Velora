use parking_lot::RwLock;
use std::path::Path;
use std::sync::Arc;
use velora_analyzer::{Analyzer, CategoryKind, SunburstSector};
use velora_index::{DirId, VolumeIndex};
use velora_ops::{CollectedItem, CollectorTray};
use velora_search::{SearchEngine, SearchQuery};

uniffi::setup_scaffolding!();

#[derive(Debug, Clone, uniffi::Record)]
pub struct SearchResultItem {
    pub name: String,
    pub path: String,
    pub size_bytes: u64,
    pub modified_secs: u64,
    pub is_dir: bool,
    pub color_hex: String,
}

#[derive(Debug, Clone, uniffi::Record)]
pub struct SunburstSectorItem {
    pub name: String,
    pub path: String,
    pub size_bytes: u64,
    pub start_angle: f32,
    pub sweep_angle: f32,
    pub depth: u32,
    pub color_hex: String,
    pub is_dir: bool,
    pub is_grouped: bool,
    pub children: Vec<SunburstSectorItem>,
}

impl From<SunburstSector> for SunburstSectorItem {
    fn from(s: SunburstSector) -> Self {
        Self {
            name: s.name,
            path: s.path,
            size_bytes: s.size_bytes,
            start_angle: s.start_angle,
            sweep_angle: s.sweep_angle,
            depth: s.depth,
            color_hex: s.color_hex,
            is_dir: s.is_dir,
            is_grouped: s.is_grouped,
            children: s.children.into_iter().map(Into::into).collect(),
        }
    }
}

#[derive(Debug, Clone, uniffi::Record)]
pub struct CollectedFile {
    pub path: String,
    pub size_bytes: u64,
    pub is_dir: bool,
}

#[derive(Debug, Clone, uniffi::Record)]
pub struct StorageSnapshotItem {
    pub name: String,
    pub date_formatted: String,
}

#[derive(Debug, Clone, uniffi::Record)]
pub struct StorageReconciliationItem {
    pub container_total_bytes: u64,
    pub container_free_bytes: u64,
    pub user_scanned_bytes: u64,
    pub system_volume_bytes: u64,
    pub vm_swap_bytes: u64,
    pub other_volumes_bytes: u64,
    pub purgeable_bytes: u64,
    pub hidden_system_bytes: u64,
    pub snapshots: Vec<StorageSnapshotItem>,
}

#[derive(Debug, Clone, uniffi::Record)]
pub struct DevArtifactRecord {
    pub path: String,
    pub name: String,
    pub kind_name: String,
    pub size_bytes: u64,
    pub modified_secs: u64,
    pub inactivity_label: String,
    pub parent_project_name: String,
    pub color_hex: String,
}

#[derive(Debug, Clone, uniffi::Record)]
pub struct XcodeItemRecord {
    pub name: String,
    pub path: String,
    pub category_name: String,
    pub size_bytes: u64,
    pub modified_secs: u64,
    pub color_hex: String,
}

#[derive(Debug, Clone, uniffi::Record)]
pub struct XcodeSummaryRecord {
    pub derived_data_bytes: u64,
    pub archives_bytes: u64,
    pub device_support_bytes: u64,
    pub simulator_bytes: u64,
    pub total_bytes: u64,
    pub items: Vec<XcodeItemRecord>,
}

#[derive(Debug, Clone, uniffi::Record)]
pub struct PackageCacheRecord {
    pub name: String,
    pub path: String,
    pub ecosystem_name: String,
    pub size_bytes: u64,
    pub modified_secs: u64,
    pub color_hex: String,
    pub can_collect: bool,
}

#[derive(Debug, Clone, uniffi::Record)]
pub struct PackageCacheSummaryRecord {
    pub total_bytes: u64,
    pub items: Vec<PackageCacheRecord>,
}

#[derive(Debug, Clone, uniffi::Record)]
pub struct AppPartRecord {
    pub name: String,
    pub path: String,
    pub kind_name: String,
    pub size_bytes: u64,
    pub color_hex: String,
}

#[derive(Debug, Clone, uniffi::Record)]
pub struct InstalledAppRecord {
    pub name: String,
    pub bundle_id: String,
    pub version: String,
    pub app_path: String,
    pub is_system_app: bool,
    pub total_size_bytes: u64,
    pub parts: Vec<AppPartRecord>,
}

#[derive(Debug, Clone, uniffi::Record)]
pub struct OrphanedResidueRecord {
    pub name: String,
    pub path: String,
    pub inferred_bundle_id: String,
    pub category_name: String,
    pub size_bytes: u64,
    pub modified_secs: u64,
}

#[derive(Debug, Clone, uniffi::Record)]
pub struct MatrixCellRecord {
    pub age_idx: u32,
    pub size_idx: u32,
    pub age_label: String,
    pub size_label: String,
    pub file_count: u32,
    pub total_bytes: u64,
}

#[derive(Debug, Clone, uniffi::Record)]
pub struct LargeOldFileRecord {
    pub path: String,
    pub name: String,
    pub size_bytes: u64,
    pub modified_secs: u64,
    pub category_name: String,
    pub color_hex: String,
    pub age_label: String,
    pub age_idx: u32,
    pub size_idx: u32,
}

#[derive(Debug, Clone, uniffi::Record)]
pub struct LargeOldMatrixSummaryRecord {
    pub total_files: u32,
    pub total_bytes: u64,
    pub cells: Vec<MatrixCellRecord>,
    pub files: Vec<LargeOldFileRecord>,
}

#[derive(Debug, Clone, uniffi::Record)]
pub struct DuplicateFileRecord {
    pub path: String,
    pub name: String,
    pub size_bytes: u64,
    pub modified_secs: u64,
    pub category_name: String,
    pub color_hex: String,
    pub is_original: bool,
}

#[derive(Debug, Clone, uniffi::Record)]
pub struct DuplicateGroupRecord {
    pub group_id: String,
    pub hash_hex: String,
    pub size_bytes: u64,
    pub total_wasted_bytes: u64,
    pub file_count: u32,
    pub files: Vec<DuplicateFileRecord>,
}

#[derive(Debug, Clone, uniffi::Record)]
pub struct DuplicateSummaryRecord {
    pub total_duplicate_files: u32,
    pub total_duplicate_groups: u32,
    pub total_wasted_bytes: u64,
    pub groups: Vec<DuplicateGroupRecord>,
}

#[uniffi::export(callback_interface)]
pub trait ScanProgressCallback: Send + Sync + 'static {
    fn on_progress(&self, current_path: String, scanned_count: u64, bytes_scanned: u64);
}

struct CallbackBridge<'a> {
    callback: &'a dyn ScanProgressCallback,
}

impl<'a> velora_scanner::ProgressListener for CallbackBridge<'a> {
    fn on_progress(&self, current_path: &str, files_scanned: u64, bytes_scanned: u64) {
        self.callback.on_progress(current_path.to_string(), files_scanned, bytes_scanned);
    }
}

#[derive(uniffi::Object)]
pub struct VeloraEngine {
    volume: RwLock<VolumeIndex>,
    collector: RwLock<CollectorTray>,
}

#[uniffi::export]
impl VeloraEngine {
    #[uniffi::constructor]
    pub fn new() -> Arc<Self> {
        Arc::new(Self {
            volume: RwLock::new(VolumeIndex::new("Macintosh HD", "/")),
            collector: RwLock::new(CollectorTray::new()),
        })
    }

    pub fn scan_volume(
        &self,
        mount_point: String,
        volume_name: String,
        callback: Option<Box<dyn ScanProgressCallback>>,
    ) -> bool {
        let mut vol = VolumeIndex::new(volume_name, &mount_point);
        let path = Path::new(&mount_point);
        let roots: Vec<&Path> = vec![path];

        let res = match callback.as_ref() {
            Some(cb) => {
                let bridge = CallbackBridge { callback: cb.as_ref() };
                velora_scanner::scan_directories_with_progress(&roots, &mut vol, Some(&bridge))
            }
            None => velora_scanner::scan_directories_with_progress(&roots, &mut vol, None),
        };

        if res.is_ok() {
            velora_apps::AppManager::index_apps_into_volume(&mut vol, path);
            *self.volume.write() = vol;
            true
        } else {
            false
        }
    }

    pub fn total_files(&self) -> u64 {
        self.volume.read().total_files() as u64
    }

    pub fn search(&self, query_str: String, max_results: u32) -> Vec<SearchResultItem> {
        let vol = self.volume.read();
        let query = SearchQuery::parse(&query_str);
        let report = SearchEngine::search(&vol, &query, None, max_results as usize);

        report
            .hits
            .into_iter()
            .filter_map(|hit| {
                let record = vol.records.get(hit.record_index)?;
                let name = vol.get_file_name(record);
                let path = vol.resolve_full_path(record);
                let cat = CategoryKind::classify(name, record.is_dir());

                Some(SearchResultItem {
                    name: name.to_string(),
                    path,
                    size_bytes: record.size,
                    modified_secs: record.modified_secs,
                    is_dir: record.is_dir(),
                    color_hex: cat.color_hex().to_string(),
                })
            })
            .collect()
    }

    pub fn compute_sunburst(&self, max_depth: u32, min_angle_deg: f32) -> Option<SunburstSectorItem> {
        let vol = self.volume.read();
        let sector = Analyzer::analyze(&vol, DirId(0), max_depth, min_angle_deg)?;
        Some(sector.into())
    }

    pub fn collect_item(&self, path: String, size_bytes: u64, is_dir: bool) {
        self.collector.write().add(CollectedItem {
            path: path.into(),
            size_bytes,
            is_dir,
        });
    }

    pub fn remove_collected(&self, path: String) {
        self.collector.write().remove(Path::new(&path));
    }

    pub fn clear_collector(&self) {
        self.collector.write().clear();
    }

    pub fn collector_items(&self) -> Vec<CollectedFile> {
        self.collector
            .read()
            .items()
            .iter()
            .map(|i| CollectedFile {
                path: i.path.to_string_lossy().to_string(),
                size_bytes: i.size_bytes,
                is_dir: i.is_dir,
            })
            .collect()
    }

    pub fn collector_total_size(&self) -> u64 {
        self.collector.read().total_size()
    }

    pub fn save_snapshot(&self, dest_path: String) -> bool {
        let vol = self.volume.read();
        vol.save_snapshot(Path::new(&dest_path)).is_ok()
    }

    pub fn load_offline_snapshot(&self, src_path: String) -> bool {
        if let Ok(snapshot) = VolumeIndex::load_snapshot(Path::new(&src_path)) {
            *self.volume.write() = snapshot;
            true
        } else {
            false
        }
    }

    pub fn is_online(&self) -> bool {
        self.volume.read().is_online
    }

    pub fn mark_deleted_by_path(&self, path: String) -> u64 {
        self.volume.write().mark_deleted_by_path(&path)
    }

    pub fn active_files(&self) -> u64 {
        self.volume.read().active_files() as u64
    }

    pub fn active_bytes(&self) -> u64 {
        self.volume.read().active_bytes()
    }

    pub fn reconcile_storage(&self, mount_point: String) -> StorageReconciliationItem {
        let scanned_bytes = self.volume.read().total_scanned_bytes();
        let rec = velora_apfs::Reconciler::reconcile(Path::new(&mount_point), scanned_bytes);
        StorageReconciliationItem {
            container_total_bytes: rec.container_total_bytes,
            container_free_bytes: rec.container_free_bytes,
            user_scanned_bytes: rec.user_scanned_bytes,
            system_volume_bytes: rec.system_volume_bytes,
            vm_swap_bytes: rec.vm_swap_bytes,
            other_volumes_bytes: rec.other_volumes_bytes,
            purgeable_bytes: rec.purgeable_bytes,
            hidden_system_bytes: rec.hidden_system_bytes,
            snapshots: rec
                .snapshots
                .into_iter()
                .map(|s| StorageSnapshotItem {
                    name: s.name,
                    date_formatted: s.date_formatted,
                })
                .collect(),
        }
    }

    pub fn find_dev_artifacts(&self, min_size_bytes: u64) -> Vec<DevArtifactRecord> {
        let vol = self.volume.read();
        let artifacts = velora_dev::ArtifactHunter::hunt(&vol, min_size_bytes);
        artifacts
            .into_iter()
            .map(|a| DevArtifactRecord {
                path: a.path,
                name: a.name,
                kind_name: a.kind.display_name().to_string(),
                size_bytes: a.size_bytes,
                modified_secs: a.modified_secs,
                inactivity_label: a.inactivity.label().to_string(),
                parent_project_name: a.parent_project_name,
                color_hex: a.color_hex,
            })
            .collect()
    }

    pub fn inspect_xcode(&self, home_path: String) -> XcodeSummaryRecord {
        let vol = self.volume.read();
        let summary = velora_dev::XcodeInspector::inspect_home(Path::new(&home_path), Some(&*vol));
        XcodeSummaryRecord {
            derived_data_bytes: summary.derived_data_bytes,
            archives_bytes: summary.archives_bytes,
            device_support_bytes: summary.device_support_bytes,
            simulator_bytes: summary.simulator_bytes,
            total_bytes: summary.total_bytes,
            items: summary
                .items
                .into_iter()
                .map(|item| XcodeItemRecord {
                    name: item.name,
                    path: item.path,
                    category_name: item.category.display_name().to_string(),
                    size_bytes: item.size_bytes,
                    modified_secs: item.modified_secs,
                    color_hex: item.color_hex,
                })
                .collect(),
        }
    }

    pub fn prune_unavailable_simulators(&self) -> bool {
        velora_dev::XcodeInspector::prune_unavailable_simulators()
    }

    pub fn inspect_package_caches(&self, home_path: String) -> PackageCacheSummaryRecord {
        let vol = self.volume.read();
        let summary = velora_dev::PackageCacheScanner::scan_home(Path::new(&home_path), Some(&*vol));
        PackageCacheSummaryRecord {
            total_bytes: summary.total_bytes,
            items: summary
                .items
                .into_iter()
                .map(|item| PackageCacheRecord {
                    name: item.name,
                    path: item.path,
                    ecosystem_name: item.ecosystem.display_name().to_string(),
                    size_bytes: item.size_bytes,
                    modified_secs: item.modified_secs,
                    color_hex: item.color_hex,
                    can_collect: item.can_collect,
                })
                .collect(),
        }
    }

    pub fn prune_docker(&self) -> bool {
        velora_dev::PackageCacheScanner::prune_docker()
    }

    pub fn list_apps_with_footprint(&self, home_path: String) -> Vec<InstalledAppRecord> {
        let vol = self.volume.read();
        let apps = velora_apps::AppManager::list_apps_with_footprint(Path::new(&home_path), Some(&*vol));
        apps.into_iter()
            .map(|app| InstalledAppRecord {
                name: app.name,
                bundle_id: app.bundle_id,
                version: app.version,
                app_path: app.app_path,
                is_system_app: app.is_system_app,
                total_size_bytes: app.total_size_bytes,
                parts: app
                    .parts
                    .into_iter()
                    .map(|p| AppPartRecord {
                        name: p.name,
                        path: p.path,
                        kind_name: p.kind.display_name().to_string(),
                        size_bytes: p.size_bytes,
                        color_hex: p.color_hex,
                    })
                    .collect(),
            })
            .collect()
    }

    pub fn find_orphaned_residue(&self, home_path: String) -> Vec<OrphanedResidueRecord> {
        let vol = self.volume.read();
        let orphans = velora_apps::AppManager::find_orphaned_residue(Path::new(&home_path), Some(&*vol));
        orphans
            .into_iter()
            .map(|o| OrphanedResidueRecord {
                name: o.name,
                path: o.path,
                inferred_bundle_id: o.inferred_bundle_id,
                category_name: o.category_name,
                size_bytes: o.size_bytes,
                modified_secs: o.modified_secs,
            })
            .collect()
    }

    pub fn compute_large_old_matrix(&self) -> LargeOldMatrixSummaryRecord {
        let vol = self.volume.read();
        let summary = velora_hygiene::LargeOldFilesMatrix::compute(&vol);
        LargeOldMatrixSummaryRecord {
            total_files: summary.total_files,
            total_bytes: summary.total_bytes,
            cells: summary
                .cells
                .into_iter()
                .map(|c| MatrixCellRecord {
                    age_idx: c.age_idx,
                    size_idx: c.size_idx,
                    age_label: c.age_label,
                    size_label: c.size_label,
                    file_count: c.file_count,
                    total_bytes: c.total_bytes,
                })
                .collect(),
            files: summary
                .files
                .into_iter()
                .map(|f| LargeOldFileRecord {
                    path: f.path,
                    name: f.name,
                    size_bytes: f.size_bytes,
                    modified_secs: f.modified_secs,
                    category_name: f.category_name,
                    color_hex: f.color_hex,
                    age_label: f.age_label,
                    age_idx: f.age_idx,
                    size_idx: f.size_idx,
                })
                .collect(),
        }
    }

    pub fn find_duplicates(&self, min_size_bytes: u64) -> DuplicateSummaryRecord {
        let vol = self.volume.read();
        let summary = velora_hygiene::DuplicateFinder::find_duplicates(&vol, min_size_bytes);
        DuplicateSummaryRecord {
            total_duplicate_files: summary.total_duplicate_files,
            total_duplicate_groups: summary.total_duplicate_groups,
            total_wasted_bytes: summary.total_wasted_bytes,
            groups: summary
                .groups
                .into_iter()
                .map(|g| DuplicateGroupRecord {
                    group_id: g.group_id,
                    hash_hex: g.hash_hex,
                    size_bytes: g.size_bytes,
                    total_wasted_bytes: g.total_wasted_bytes,
                    file_count: g.file_count,
                    files: g
                        .files
                        .into_iter()
                        .map(|f| DuplicateFileRecord {
                            path: f.path,
                            name: f.name,
                            size_bytes: f.size_bytes,
                            modified_secs: f.modified_secs,
                            category_name: f.category_name,
                            color_hex: f.color_hex,
                            is_original: f.is_original,
                        })
                        .collect(),
                })
                .collect(),
        }
    }
}
