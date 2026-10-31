#[cfg(not(all(target_os = "macos", target_arch = "aarch64")))]
compile_error!("Velora requires macOS 15 (Sequoia) or later on Apple Silicon (ARM64). Architecture x86_64 / Intel is not supported.");

pub mod asep;
pub mod codesign;
pub mod model;
pub mod quarantine;
pub mod scanner;
pub mod threat_db;
pub mod triage;

pub use model::{
    SecurityScanSummary, SigningStatus, ThreatCategory, ThreatRecord, ThreatSeverity,
};
pub use quarantine::{QuarantineManifest, QuarantineVault, QuarantinedItemEntry};
pub use scanner::SecurityScanner;
