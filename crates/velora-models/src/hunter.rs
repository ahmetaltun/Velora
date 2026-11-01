use crate::locators::{
    ComfyUiLocator, HuggingFaceLocator, LmStudioLocator, LooseWeightLocator, MlxLocator,
    OllamaLocator, PyTorchLocator,
};
use crate::model::{AiModelItem, AiModelSummary, InactivityTier};
use std::collections::HashSet;
use std::path::Path;
use std::time::{SystemTime, UNIX_EPOCH};

pub struct ModelWeightHunter;

impl ModelWeightHunter {
    /// Discovers all local AI and LLM model weights across standard caches and loose folders.
    pub fn hunt_home(home: &Path) -> AiModelSummary {
        let now_secs = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap_or_default()
            .as_secs();

        let mut all_items: Vec<AiModelItem> = Vec::new();
        let mut seen_paths: HashSet<String> = HashSet::new();

        let mut add_items = |items: Vec<AiModelItem>| {
            for item in items {
                if !seen_paths.contains(&item.path) {
                    seen_paths.insert(item.path.clone());
                    all_items.push(item);
                }
            }
        };

        // 1. Ollama
        add_items(OllamaLocator::locate(home, now_secs));

        // 2. Hugging Face Hub
        add_items(HuggingFaceLocator::locate(home, now_secs));

        // 3. LM Studio
        add_items(LmStudioLocator::locate(home, now_secs));

        // 4. Apple MLX
        add_items(MlxLocator::locate(home, now_secs));

        // 5. PyTorch / Torch Hub
        add_items(PyTorchLocator::locate(home, now_secs));

        // 6. ComfyUI / Diffusion
        add_items(ComfyUiLocator::locate(home, now_secs));

        // 7. Loose Model Weights (> 200 MB)
        add_items(LooseWeightLocator::locate(home, None, now_secs));

        // Sort items by size descending (largest model weights first)
        all_items.sort_by(|a, b| b.size_bytes.cmp(&a.size_bytes));

        let mut total_bytes = 0u64;
        let mut stale_bytes = 0u64;
        let mut stale_count = 0u32;

        for item in &all_items {
            total_bytes += item.size_bytes;
            if item.inactivity == InactivityTier::Stale {
                stale_bytes += item.size_bytes;
                stale_count += 1;
            }
        }

        let total_count = all_items.len() as u32;

        AiModelSummary {
            total_bytes,
            stale_bytes,
            total_model_count: total_count,
            stale_model_count: stale_count,
            items: all_items,
        }
    }
}
