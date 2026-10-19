pub mod associated;
pub mod bundle;
pub mod model;
pub mod orphans;

pub use associated::AssociatedFileResolver;
pub use bundle::BundleScanner;
pub use model::{AppPart, AppPartKind, InstalledApp, OrphanedResidue};
pub use orphans::OrphanDetector;
use std::path::Path;

pub struct AppManager;

impl AppManager {
    /// Discovers all installed apps and resolves their complete ~/Library footprints.
    pub fn list_apps_with_footprint(home_path: &Path) -> Vec<InstalledApp> {
        let mut apps = BundleScanner::scan_installed_apps(home_path);
        for app in &mut apps {
            AssociatedFileResolver::resolve_associated_files(app, home_path);
        }
        // Sort descending by total size (largest apps first)
        apps.sort_by(|a, b| b.total_size_bytes.cmp(&a.total_size_bytes));
        apps
    }

    /// Discovers leftover folders belonging to apps that are no longer installed.
    pub fn find_orphaned_residue(home_path: &Path) -> Vec<OrphanedResidue> {
        let apps = BundleScanner::scan_installed_apps(home_path);
        OrphanDetector::find_orphaned_residue(home_path, &apps)
    }
}
