#[cfg(not(all(target_os = "macos", target_arch = "aarch64")))]
compile_error!("Velora requires macOS 15 (Sequoia) or later on Apple Silicon (ARM64). Architecture x86_64 / Intel is not supported.");

pub mod artifacts;
pub mod caches;
pub mod model;
pub mod xcode;

pub use artifacts::ArtifactHunter;
pub use caches::PackageCacheScanner;
pub use model::{
    CacheEcosystem, DevArtifactItem, DevArtifactKind, InactivityTier, PackageCacheItem,
    PackageCacheSummary, XcodeCategoryKind, XcodeItem, XcodeStorageSummary,
};
pub use xcode::XcodeInspector;
