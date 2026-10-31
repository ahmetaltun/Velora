#[cfg(not(all(target_os = "macos", target_arch = "aarch64")))]
compile_error!("Velora requires macOS 15 (Sequoia) or later on Apple Silicon (ARM64). Architecture x86_64 / Intel is not supported.");

pub mod model;
pub mod reconcile;
pub mod snapshot;
pub mod telemetry;

pub use model::{ApfsContainer, ApfsVolume, SnapshotInfo, StorageReconciliation};
pub use reconcile::Reconciler;
pub use snapshot::SnapshotManager;
pub use telemetry::{ApfsTelemetry, VfsStats};
