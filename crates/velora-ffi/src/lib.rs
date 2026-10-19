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
        let res = match callback.as_ref() {
            Some(cb) => {
                let bridge = CallbackBridge { callback: cb.as_ref() };
                velora_scanner::scan_directory_with_progress(path, &mut vol, Some(&bridge))
            }
            None => velora_scanner::scan_directory(path, &mut vol),
        };

        if res.is_ok() {
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
}
