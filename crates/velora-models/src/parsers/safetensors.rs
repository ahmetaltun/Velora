use crate::model::ModelMetadata;
use crate::parsers::gguf::{
    extract_arch_from_name, extract_param_size_from_name, extract_quant_from_name,
    format_architecture,
};
use std::fs::File;
use std::io::{BufReader, Read};
use std::path::Path;

const MAX_SAFETENSORS_HEADER: u64 = 512 * 1024; // 512 KB max JSON header budget

pub struct SafetensorsParser;

impl SafetensorsParser {
    pub fn parse_file(path: &Path) -> Option<ModelMetadata> {
        let file = File::open(path).ok()?;
        let mut reader = BufReader::new(file.take(MAX_SAFETENSORS_HEADER + 8));

        let mut len_bytes = [0u8; 8];
        reader.read_exact(&mut len_bytes).ok()?;
        let header_len = u64::from_le_bytes(len_bytes);

        if header_len == 0 || header_len > MAX_SAFETENSORS_HEADER {
            // Either corrupt or exceeds budget, fallback to heuristics
            return Self::fallback_heuristics(path);
        }

        let mut json_buf = vec![0u8; header_len as usize];
        if reader.read_exact(&mut json_buf).is_err() {
            return Self::fallback_heuristics(path);
        }

        let mut metadata = ModelMetadata::default();
        if let Ok(v) = serde_json::from_slice::<serde_json::Value>(&json_buf) {
            if let Some(obj) = v.as_object() {
                // Check __metadata__
                if let Some(meta_val) = obj.get("__metadata__").and_then(|m| m.as_object()) {
                    if let Some(arch) = meta_val.get("model_type").or_else(|| meta_val.get("architecture")).and_then(|s| s.as_str()) {
                        metadata.architecture = Some(format_architecture(arch));
                    }
                    if let Some(quant) = meta_val.get("quantization").or_else(|| meta_val.get("dtype")).and_then(|s| s.as_str()) {
                        metadata.quantization = Some(quant.to_string());
                    }
                }

                // If quantization not found yet, check tensor dtypes
                if metadata.quantization.is_none() {
                    for (k, val) in obj {
                        if k == "__metadata__" {
                            continue;
                        }
                        if let Some(dtype) = val.get("dtype").and_then(|d| d.as_str()) {
                            metadata.quantization = Some(dtype.to_string());
                            break;
                        }
                    }
                }
            }
        }

        // Check companion config.json in parent directory if available
        if metadata.architecture.is_none() || metadata.parameter_size.is_none() || metadata.context_length.is_none() {
            if let Some(parent) = path.parent() {
                let config_path = parent.join("config.json");
                if config_path.is_file() {
                    if let Ok(content) = std::fs::read_to_string(&config_path) {
                        if let Ok(cfg) = serde_json::from_str::<serde_json::Value>(&content) {
                            if metadata.architecture.is_none() {
                                if let Some(arch) = cfg.get("model_type").or_else(|| cfg.get("architectures").and_then(|a| a.get(0))).and_then(|s| s.as_str()) {
                                    metadata.architecture = Some(format_architecture(arch));
                                }
                            }
                            if metadata.context_length.is_none() {
                                if let Some(ctx) = cfg.get("max_position_embeddings").or_else(|| cfg.get("context_length")).and_then(|c| c.as_u64()) {
                                    metadata.context_length = Some(ctx as u32);
                                }
                            }
                        }
                    }
                }
            }
        }

        // Apply fallback heuristics from parent and file name
        let parent_name = path.parent().and_then(|p| p.file_name()).and_then(|s| s.to_str()).unwrap_or("");
        let file_name = path.file_name().and_then(|s| s.to_str()).unwrap_or("");
        let combined = format!("{} {}", parent_name, file_name);

        if metadata.architecture.is_none() {
            metadata.architecture = extract_arch_from_name(&combined);
        }
        if let Some(explicit_quant) = extract_quant_from_name(&combined) {
            metadata.quantization = Some(explicit_quant);
        } else if metadata.quantization.is_none() {
            metadata.quantization = extract_quant_from_name(&combined);
        }
        if metadata.parameter_size.is_none() {
            metadata.parameter_size = extract_param_size_from_name(&combined);
        }

        Some(metadata)
    }

    fn fallback_heuristics(path: &Path) -> Option<ModelMetadata> {
        let parent_name = path.parent().and_then(|p| p.file_name()).and_then(|s| s.to_str()).unwrap_or("");
        let file_name = path.file_name().and_then(|s| s.to_str()).unwrap_or("");
        let combined = format!("{} {}", parent_name, file_name);

        Some(ModelMetadata {
            architecture: extract_arch_from_name(&combined),
            quantization: extract_quant_from_name(&combined),
            parameter_size: extract_param_size_from_name(&combined),
            context_length: None,
        })
    }
}
