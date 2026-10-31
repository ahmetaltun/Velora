#[cfg(not(all(target_os = "macos", target_arch = "aarch64")))]
compile_error!("Velora requires macOS 15 (Sequoia) or later on Apple Silicon (ARM64). Architecture x86_64 / Intel is not supported.");

pub mod walker;

pub use walker::{scan_directories_with_progress, scan_directory, scan_directory_with_progress, ProgressListener};
