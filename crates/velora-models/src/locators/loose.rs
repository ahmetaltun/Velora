use crate::model::{
    AiModelEcosystem, AiModelItem, InactivityTier, ModelFormat, ModelMetadata,
};
use crate::parsers::{GgufParser, SafetensorsParser};
use std::fs;
use std::path::Path;

const DEFAULT_MIN_LOOSE_SIZE_BYTES: u64 = 200 * 1024 * 1024; // 200 MB

pub struct LooseWeightLocator;

impl LooseWeightLocator {
    pub fn locate(home: &Path, min_size_bytes: Option<u64>, now_secs: u64) -> Vec<AiModelItem> {
        let min_size = min_size_bytes.unwrap_or(DEFAULT_MIN_LOOSE_SIZE_BYTES);

        let search_dirs = [
            home.join("Downloads"),
            home.join("Models"),
            home.join("models"),
            home.join("Documents"),
            home.join("Desktop"),
        ];

        let mut items = Vec::new();

        for dir in search_dirs {
            if dir.is_dir() {
                scan_loose_recursive(&dir, min_size, 3, now_secs, &mut items);
            }
        }

        items
    }
}

fn scan_loose_recursive(
    dir: &Path,
    min_size: u64,
    depth: usize,
    now_secs: u64,
    out: &mut Vec<AiModelItem>,
) {
    if depth == 0 {
        return;
    }

    if let Ok(entries) = fs::read_dir(dir) {
        for entry in entries.flatten() {
            let path = entry.path();
            let fname = entry.file_name().to_string_lossy().to_string();

            // Skip hidden or build directories
            if fname.starts_with('.') || fname == "target" || fname == "node_modules" || fname == ".git" {
                continue;
            }

            if let Ok(meta) = entry.metadata() {
                if meta.is_dir() {
                    scan_loose_recursive(&path, min_size, depth - 1, now_secs, out);
                } else if meta.is_file() {
                    let sz = meta.len();
                    if sz < min_size {
                        continue;
                    }

                    let lower = fname.to_lowercase();
                    let format = if lower.ends_with(".gguf") {
                        Some(ModelFormat::Gguf)
                    } else if lower.ends_with(".safetensors") {
                        Some(ModelFormat::Safetensors)
                    } else if lower.ends_with(".onnx") {
                        Some(ModelFormat::Onnx)
                    } else if lower.ends_with(".pth") || lower.ends_with(".pt") || lower.ends_with(".ckpt") {
                        Some(ModelFormat::PyTorchCheckpoint)
                    } else {
                        None
                    };

                    if let Some(fmt) = format {
                        let mut metadata = ModelMetadata::default();
                        match fmt {
                            ModelFormat::Gguf => {
                                if let Some(m) = GgufParser::parse_file(&path) {
                                    metadata = m;
                                }
                            }
                            ModelFormat::Safetensors => {
                                if let Some(m) = SafetensorsParser::parse_file(&path) {
                                    metadata = m;
                                }
                            }
                            _ => {}
                        }

                        if metadata.architecture.is_none() {
                            metadata.architecture = crate::parsers::gguf::extract_arch_from_name(&fname);
                        }
                        if metadata.parameter_size.is_none() {
                            metadata.parameter_size = crate::parsers::gguf::extract_param_size_from_name(&fname);
                        }
                        if metadata.quantization.is_none() {
                            metadata.quantization = crate::parsers::gguf::extract_quant_from_name(&fname);
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

                        out.push(AiModelItem {
                            name: fname,
                            path: path.to_string_lossy().to_string(),
                            organization: None,
                            ecosystem: AiModelEcosystem::LooseWeight,
                            format: fmt,
                            metadata,
                            size_bytes: sz,
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
}
