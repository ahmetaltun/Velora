use crate::model::{
    AiModelEcosystem, AiModelItem, InactivityTier, ModelFormat, ModelMetadata,
};
use crate::parsers::SafetensorsParser;
use std::fs;
use std::path::{Path, PathBuf};

pub struct ComfyUiLocator;

impl ComfyUiLocator {
    pub fn locate(home: &Path, now_secs: u64) -> Vec<AiModelItem> {
        let mut model_dirs = Vec::new();

        // Standard locations
        let candidates = [
            home.join("ComfyUI").join("models"),
            home.join("comfyui").join("models"),
            home.join(".cache").join("comfyui"),
            PathBuf::from("/Applications/ComfyUI.app/Contents/Resources/ComfyUI/models"),
        ];

        for c in candidates {
            if c.is_dir() && !model_dirs.contains(&c) {
                model_dirs.push(c);
            }
        }

        // Check extra_model_paths.yaml
        let yaml_candidates = [
            home.join("ComfyUI").join("extra_model_paths.yaml"),
            home.join("extra_model_paths.yaml"),
        ];
        for y in yaml_candidates {
            if y.is_file() {
                if let Ok(content) = fs::read_to_string(&y) {
                    for line in content.lines() {
                        let trimmed = line.trim();
                        if trimmed.starts_with("base_path:") || trimmed.starts_with("checkpoints:") {
                            if let Some(val) = trimmed.split(':').nth(1) {
                                let raw_p = val.trim().trim_matches('\'').trim_matches('"');
                                let p = if raw_p.starts_with('~') {
                                    home.join(raw_p.trim_start_matches("~/"))
                                } else {
                                    PathBuf::from(raw_p)
                                };
                                if p.is_dir() && !model_dirs.contains(&p) {
                                    model_dirs.push(p);
                                }
                            }
                        }
                    }
                }
            }
        }

        let mut items = Vec::new();
        let subcategories = ["checkpoints", "unet", "loras", "vae", "clip", "diffusion_models"];

        for root in model_dirs {
            for sub in subcategories {
                let sub_path = root.join(sub);
                if sub_path.is_dir() {
                    scan_directory_models(&sub_path, sub, now_secs, &mut items);
                }
            }
            // Also scan root itself if loose weights are directly inside
            scan_directory_models(&root, "models", now_secs, &mut items);
        }

        items
    }
}

fn scan_directory_models(dir: &Path, category: &str, now_secs: u64, out: &mut Vec<AiModelItem>) {
    if let Ok(entries) = fs::read_dir(dir) {
        for entry in entries.flatten() {
            let path = entry.path();
            if let Ok(meta) = entry.metadata() {
                if meta.is_file() {
                    let fname = entry.file_name().to_string_lossy().to_string();
                    let lower = fname.to_lowercase();
                    if lower.ends_with(".safetensors") || lower.ends_with(".ckpt") || lower.ends_with(".pt") {
                        let size_bytes = meta.len();
                        if size_bytes < 50 * 1024 * 1024 {
                            // Ignore tiny weights < 50MB
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

                        let mut metadata = ModelMetadata::default();
                        let format = if lower.ends_with(".safetensors") {
                            if let Some(m) = SafetensorsParser::parse_file(&path) {
                                metadata = m;
                            }
                            ModelFormat::Safetensors
                        } else {
                            ModelFormat::PyTorchCheckpoint
                        };

                        if metadata.architecture.is_none() {
                            metadata.architecture = Some(if lower.contains("flux") {
                                "Flux.1".to_string()
                            } else if lower.contains("sdxl") {
                                "SDXL".to_string()
                            } else if lower.contains("sd15") || lower.contains("v1-5") {
                                "Stable Diffusion 1.5".to_string()
                            } else {
                                format!("Diffusion ({})", category)
                            });
                        }

                        out.push(AiModelItem {
                            name: fname,
                            path: path.to_string_lossy().to_string(),
                            organization: Some(category.to_string()),
                            ecosystem: AiModelEcosystem::ComfyUi,
                            format,
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
}
