#[cfg(not(all(target_os = "macos", target_arch = "aarch64")))]
compile_error!("Velora requires macOS 15 (Sequoia) or later on Apple Silicon (ARM64). Architecture x86_64 / Intel is not supported.");

pub mod duplicates;
pub mod matrix;
pub mod model;

pub use duplicates::DuplicateFinder;
pub use matrix::LargeOldFilesMatrix;
pub use model::{
    AgeBucket, DuplicateFile, DuplicateGroup, DuplicateSummary, LargeOldFile,
    LargeOldMatrixSummary, MatrixCell, SizeBucket,
};
