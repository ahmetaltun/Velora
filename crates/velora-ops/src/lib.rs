#[cfg(not(all(target_os = "macos", target_arch = "aarch64")))]
compile_error!("Velora requires macOS 15 (Sequoia) or later on Apple Silicon (ARM64). Architecture x86_64 / Intel is not supported.");

use serde::{Deserialize, Serialize};
use std::path::PathBuf;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CollectedItem {
    pub path: PathBuf,
    pub size_bytes: u64,
    pub is_dir: bool,
}

#[derive(Debug, Default, Clone, Serialize, Deserialize)]
pub struct CollectorTray {
    items: Vec<CollectedItem>,
}

impl CollectorTray {
    pub fn new() -> Self {
        Self { items: Vec::new() }
    }

    pub fn add(&mut self, item: CollectedItem) {
        if !self.items.iter().any(|i| i.path == item.path) {
            self.items.push(item);
        }
    }

    pub fn remove(&mut self, path: &std::path::Path) {
        self.items.retain(|i| i.path != path);
    }

    pub fn clear(&mut self) {
        self.items.clear();
    }

    pub fn total_size(&self) -> u64 {
        self.items.iter().map(|i| i.size_bytes).sum()
    }

    pub fn items(&self) -> &[CollectedItem] {
        &self.items
    }
}
