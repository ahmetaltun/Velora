use crate::model::{
    AiModelEcosystem, AiModelItem, InactivityTier, ModelFormat, ModelMetadata,
};
use crate::parsers::{GgufParser, SafetensorsParser};
use std::fs;
use std::path::{Path, PathBuf};

pub struct HuggingFaceLocator;

impl HuggingFaceLocator {
    pub fn locate(home: &Path, now_secs: u64) -> Vec<AiModelItem> {
        let hub_dir = match std::env::var("HF_HUB_CACHE") {
            Ok(p) => PathBuf::from(p),
            Err(_) => match std::env::var("HF_HOME") {
                Ok(p) => PathBuf::from(p).join("hub"),
                Err(_) => home.join(".cache").join("huggingface").join("hub"),
            },
        };

        if !hub_dir.is_dir() {
            return Vec::new();
        }

        let mut items = Vec::new();

        if let Ok(entries) = fs::read_dir(&hub_dir) {
            for entry in entries.flatten() {
                let path = entry.path();
                if !path.is_dir() {
                    continue;
                }

                let dir_name = entry.file_name().to_string_lossy().to_string();
                if !dir_name.starts_with("models--") {
                    continue;
                }

                // Parse org and model name: models--org--name or models--name
                let parts: Vec<&str> = dir_name.strip_prefix("models--").unwrap().split("--").collect();
                let (org, model_name) = if parts.len() >= 2 {
                    (Some(parts[0].to_string()), parts[1..].join("/"))
                } else if parts.len() == 1 {
                    (None, parts[0].to_string())
                } else {
                    (None, dir_name.clone())
                };

                // Measure size strictly by scanning blobs/ to avoid symlink double-counting
                let blobs_dir = path.join("blobs");
                let mut total_size = 0u64;
                let mut latest_mod_secs = 0u64;
                let mut latest_acc_secs = 0u64;

                if blobs_dir.is_dir() {
                    if let Ok(blob_entries) = fs::read_dir(&blobs_dir) {
                        for b in blob_entries.flatten() {
                            // Check symlink vs normal file
                            if let Ok(ft) = b.file_type() {
                                if ft.is_file() && !ft.is_symlink() {
                                    if let Ok(meta) = b.metadata() {
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
                                    }
                                }
                            }
                        }
                    }
                } else {
                    // Fallback: directory size
                    total_size = calculate_dir_size(&path);
                }

                if total_size == 0 {
                    continue;
                }

                if latest_mod_secs == 0 {
                    if let Ok(meta) = fs::metadata(&path) {
                        latest_mod_secs = meta
                            .modified()
                            .ok()
                            .and_then(|t| t.duration_since(std::time::UNIX_EPOCH).ok())
                            .map(|d| d.as_secs())
                            .unwrap_or(0);
                        latest_acc_secs = meta
                            .accessed()
                            .ok()
                            .and_then(|t| t.duration_since(std::time::UNIX_EPOCH).ok())
                            .map(|d| d.as_secs())
                            .unwrap_or(latest_mod_secs);
                    }
                }

                // Inspect snapshots for config.json or weights
                let mut metadata = ModelMetadata::default();
                let mut format = ModelFormat::Safetensors;
                let snapshots_dir = path.join("snapshots");

                if snapshots_dir.is_dir() {
                    if let Ok(snap_entries) = fs::read_dir(&snapshots_dir) {
                        for snap in snap_entries.flatten() {
                            if snap.path().is_dir() {
                                // 1. Read config.json
                                let cfg_path = snap.path().join("config.json");
                                if cfg_path.is_file() {
                                    if let Ok(content) = fs::read_to_string(&cfg_path) {
                                        if let Ok(cfg) = serde_json::from_str::<serde_json::Value>(&content) {
                                            if let Some(arch) = cfg.get("model_type").or_else(|| cfg.get("architectures").and_then(|a| a.get(0))).and_then(|s| s.as_str()) {
                                                metadata.architecture = Some(crate::parsers::gguf::format_architecture(arch));
                                            }
                                            if let Some(ctx) = cfg.get("max_position_embeddings").or_else(|| cfg.get("context_length")).and_then(|c| c.as_u64()) {
                                                metadata.context_length = Some(ctx as u32);
                                            }
                                            if let Some(dtype) = cfg.get("torch_dtype").and_then(|s| s.as_str()) {
                                                metadata.quantization = Some(dtype.to_string());
                                            }
                                        }
                                    }
                                }

                                // 2. Check for weight files in snapshot
                                if let Ok(files) = fs::read_dir(snap.path()) {
                                    for f in files.flatten() {
                                        let fname = f.file_name().to_string_lossy().to_string();
                                        if fname.ends_with(".safetensors") {
                                            format = ModelFormat::Safetensors;
                                            if let Some(meta) = SafetensorsParser::parse_file(&f.path()) {
                                                if metadata.architecture.is_none() {
                                                    metadata.architecture = meta.architecture;
                                                }
                                                if metadata.quantization.is_none() {
                                                    metadata.quantization = meta.quantization;
                                                }
                                                if metadata.parameter_size.is_none() {
                                                    metadata.parameter_size = meta.parameter_size;
                                                }
                                            }
                                            break;
                                        } else if fname.ends_with(".gguf") {
                                            format = ModelFormat::Gguf;
                                            if let Some(meta) = GgufParser::parse_file(&f.path()) {
                                                metadata = meta;
                                            }
                                            break;
                                        } else if fname.ends_with(".bin") || fname.ends_with(".pt") {
                                            format = ModelFormat::PyTorchCheckpoint;
                                        }
                                    }
                                }
                                break; // Checked latest snapshot
                            }
                        }
                    }
                }

                // Fallback heuristics
                if metadata.architecture.is_none() {
                    metadata.architecture = crate::parsers::gguf::extract_arch_from_name(&model_name);
                }
                if metadata.parameter_size.is_none() {
                    metadata.parameter_size = crate::parsers::gguf::extract_param_size_from_name(&model_name);
                }
                if metadata.quantization.is_none() {
                    metadata.quantization = crate::parsers::gguf::extract_quant_from_name(&model_name);
                }

                let inactivity = InactivityTier::from_timestamps(latest_mod_secs, latest_acc_secs, now_secs);

                items.push(AiModelItem {
                    name: model_name,
                    path: path.to_string_lossy().to_string(),
                    organization: org,
                    ecosystem: AiModelEcosystem::HuggingFace,
                    format,
                    metadata,
                    size_bytes: total_size,
                    modified_secs: latest_mod_secs,
                    accessed_secs: latest_acc_secs,
                    inactivity,
                    can_collect: true,
                    associated_paths: vec![path.to_string_lossy().to_string()],
                });
            }
        }

        items
    }
}

fn calculate_dir_size(dir: &Path) -> u64 {
    let mut total = 0u64;
    if let Ok(entries) = fs::read_dir(dir) {
        for entry in entries.flatten() {
            let path = entry.path();
            if let Ok(ft) = entry.file_type() {
                if ft.is_file() && !ft.is_symlink() {
                    if let Ok(meta) = entry.metadata() {
                        total += meta.len();
                    }
                } else if ft.is_dir() && !ft.is_symlink() {
                    total += calculate_dir_size(&path);
                }
            }
        }
    }
    total
}
