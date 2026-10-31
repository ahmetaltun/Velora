#[cfg(not(all(target_os = "macos", target_arch = "aarch64")))]
compile_error!("Velora requires macOS 15 (Sequoia) or later on Apple Silicon (ARM64). Architecture x86_64 / Intel is not supported.");

pub mod flags;
pub mod pool;
pub mod record;
pub mod table;
pub mod volume;

pub use flags::FileFlags;
pub use pool::StringPool;
pub use record::{DirId, FileId, FileRecord};
pub use table::DirectoryTable;
pub use volume::{AppMetadataEntry, VolumeIndex};
