use crate::model::{
    AiModelEcosystem, AiModelItem, InactivityTier, ModelFormat, ModelMetadata,
};
use std::fs;
use std::path::{Path, PathBuf};

pub struct PyTorchLocator;

impl PyTorchLocator {
    pub fn locate(home: &Path, now_secs: u64) -> Vec<AiModelItem> {
        let torch_dir = match std::env::var("TORCH_HOME") {
            Ok(p) => PathBuf::from(p).join("hub").join("checkpoints"),
            Err(_) => home.join(".cache").join("torch").join("hub").join("checkpoints"),
        };

        if !torch_dir.is_dir() {
            return Vec::new();
        }

        let mut items = Vec::new();

        if let Ok(entries) = fs::read_dir(&torch_dir) {
            for entry in entries.flatten() {
                let path = entry.path();
                if let Ok(meta) = entry.metadata() {
                    if meta.is_file() {
                        let fname = entry.file_name().to_string_lossy().to_string();
                        if fname.ends_with(".pth") || fname.ends_with(".pt") || fname.ends_with(".bin") {
                            let size_bytes = meta.len();
                            if size_bytes == 0 {
                                continue;
                            }

                            let mod_secs = meta
                                .modified()
                                .ok()
                                .and_then(|t| t.duration_since(std::time::UNIX_EPOCH).ok())
                                .map(|d| d.as_secs())
                                .unwrap_or(0);

                            let acc_secs = meta
                                .accessed()
                                .ok()
                                .and_then(|t| t.duration_since(std::time::UNIX_EPOCH).ok())
                                .map(|d| d.as_secs())
                                .unwrap_or(mod_secs);

                            let inactivity = InactivityTier::from_timestamps(mod_secs, acc_secs, now_secs);

                            let metadata = ModelMetadata {
                                architecture: crate::parsers::gguf::extract_arch_from_name(&fname),
                                quantization: crate::parsers::gguf::extract_quant_from_name(&fname),
                                parameter_size: crate::parsers::gguf::extract_param_size_from_name(&fname),
                                context_length: None,
                            };

                            items.push(AiModelItem {
                                name: fname,
                                path: path.to_string_lossy().to_string(),
                                organization: None,
                                ecosystem: AiModelEcosystem::TorchHub,
                                format: ModelFormat::PyTorchCheckpoint,
                                metadata,
                                size_bytes,
                                modified_secs: mod_secs,
                                accessed_secs: acc_secs,
                                inactivity,
                                can_collect: true,
                                associated_paths: vec![path.to_string_lossy().to_string()],
                            });
                        }
                    }
                }
            }
        }

        items
    }
}
