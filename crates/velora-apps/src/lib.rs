pub mod associated;
pub mod bundle;
pub mod index_resolver;
pub mod model;
pub mod orphans;

pub use associated::AssociatedFileResolver;
pub use bundle::BundleScanner;
pub use index_resolver::IndexFootprintResolver;
pub use model::{AppPart, AppPartKind, InstalledApp, OrphanedResidue};
pub use orphans::OrphanDetector;
use std::path::Path;
use velora_index::VolumeIndex;

pub struct AppManager;

impl AppManager {
    /// Discovers all installed apps and resolves their complete ~/Library footprints,
    /// leveraging the pre-indexed `VolumeIndex` when available to bypass physical disk I/O.
    pub fn list_apps_with_footprint(
        home_path: &Path,
        volume: Option<&VolumeIndex>,
    ) -> Vec<InstalledApp> {
        let resolver = volume
            .filter(|v| v.total_files() > 0)
            .map(|v| IndexFootprintResolver::new(v, home_path));
        let mut apps = BundleScanner::scan_installed_apps(home_path, resolver.as_ref());
        for app in &mut apps {
            AssociatedFileResolver::resolve_associated_files(app, home_path, resolver.as_ref());
        }
        // Sort descending by total size (largest apps first)
        apps.sort_by(|a, b| b.total_size_bytes.cmp(&a.total_size_bytes));
        apps
    }

    /// Discovers leftover folders belonging to apps that are no longer installed.
    pub fn find_orphaned_residue(
        home_path: &Path,
        volume: Option<&VolumeIndex>,
    ) -> Vec<OrphanedResidue> {
        let resolver = volume
            .filter(|v| v.total_files() > 0)
            .map(|v| IndexFootprintResolver::new(v, home_path));
        let apps = BundleScanner::scan_installed_apps(home_path, resolver.as_ref());
        OrphanDetector::find_orphaned_residue(home_path, &apps, resolver.as_ref())
    }
}
