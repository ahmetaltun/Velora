#[cfg(not(all(target_os = "macos", target_arch = "aarch64")))]
compile_error!("Velora requires macOS 15 (Sequoia) or later on Apple Silicon (ARM64). Architecture x86_64 / Intel is not supported.");

pub mod engine;
pub mod matcher;
pub mod query;

pub use engine::{SearchEngine, SearchHit, SearchReport};
pub use query::{ComparisonOp, DateConstraint, SearchQuery, SizeConstraint};
