use crate::model::{
    AiModelEcosystem, AiModelItem, InactivityTier, ModelFormat, ModelMetadata,
};
use crate::parsers::SafetensorsParser;
use std::fs;
use std::path::Path;

pub struct MlxLocator;

impl MlxLocator {
    pub fn locate(home: &Path, now_secs: u64) -> Vec<AiModelItem> {
        let mut dirs = Vec::new();
        let mlx_dir = home.join(".cache").join("mlx");
        if mlx_dir.is_dir() {
            dirs.push(mlx_dir);
        }
        let dot_mlx = home.join(".mlx");
        if dot_mlx.is_dir() {
            dirs.push(dot_mlx);
        }

        let mut items = Vec::new();

        for root in dirs {
            if let Ok(entries) = fs::read_dir(&root) {
                for entry in entries.flatten() {
                    let path = entry.path();
                    if path.is_dir() {
                        let name = entry.file_name().to_string_lossy().to_string();
                        if name.starts_with('.') {
                            continue;
                        }

                        let (size_bytes, metadata, mod_secs, acc_secs) = inspect_mlx_dir(&path);
                        if size_bytes == 0 {
                            continue;
                        }

                        let inactivity = InactivityTier::from_timestamps(mod_secs, acc_secs, now_secs);

                        items.push(AiModelItem {
                            name,
                            path: path.to_string_lossy().to_string(),
                            organization: None,
                            ecosystem: AiModelEcosystem::AppleMlx,
                            format: ModelFormat::Safetensors,
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

        items
    }
}

fn inspect_mlx_dir(dir: &Path) -> (u64, ModelMetadata, u64, u64) {
    let mut total_size = 0u64;
    let mut metadata = ModelMetadata::default();
    let mut latest_mod_secs = 0u64;
    let mut latest_acc_secs = 0u64;

    if let Ok(entries) = fs::read_dir(dir) {
        for entry in entries.flatten() {
            let path = entry.path();
            if let Ok(meta) = entry.metadata() {
                if meta.is_file() {
                    total_size += meta.len();
                    if let Ok(m) = meta.modified() {
                        if let Ok(d) = m.duration_since(std::time::UNIX_EPOCH) {
                            latest_mod_secs = latest_mod_secs.max(d.as_secs());
                        }
                    }
                    if let Ok(a) = meta.accessed() {
                        if let Ok(d) = a.duration_since(std::time::UNIX_EPOCH) {
                            latest_acc_secs = latest_acc_secs.max(d.as_secs());
                        }
                    }

                    let fname = entry.file_name().to_string_lossy().to_string();
                    if fname.ends_with(".safetensors") && metadata.architecture.is_none() {
                        if let Some(m) = SafetensorsParser::parse_file(&path) {
                            metadata = m;
                        }
                    }
                }
            }
        }
    }

    let dir_name = dir.file_name().and_then(|s| s.to_str()).unwrap_or("");
    if metadata.architecture.is_none() {
        metadata.architecture = crate::parsers::gguf::extract_arch_from_name(dir_name);
    }
    if metadata.parameter_size.is_none() {
        metadata.parameter_size = crate::parsers::gguf::extract_param_size_from_name(dir_name);
    }
    if metadata.quantization.is_none() {
        metadata.quantization = crate::parsers::gguf::extract_quant_from_name(dir_name);
    }

    (total_size, metadata, latest_mod_secs, latest_acc_secs)
}
