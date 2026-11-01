use crate::model::{
    AiModelEcosystem, AiModelItem, InactivityTier, ModelFormat, ModelMetadata,
};
use crate::parsers::{GgufParser, SafetensorsParser};
use std::fs;
use std::path::{Path, PathBuf};

pub struct LmStudioLocator;

impl LmStudioLocator {
    pub fn locate(home: &Path, now_secs: u64) -> Vec<AiModelItem> {
        let mut search_dirs = Vec::new();

        // 1. Check custom path in settings.json if exists
        let settings_path = home.join(".cache").join("lm-studio").join("settings.json");
        if settings_path.is_file() {
            if let Ok(content) = fs::read_to_string(&settings_path) {
                if let Ok(json) = serde_json::from_str::<serde_json::Value>(&content) {
                    if let Some(custom_dir) = json.get("modelDirectory").or_else(|| json.get("downloadDirectory")).and_then(|d| d.as_str()) {
                        let p = PathBuf::from(custom_dir);
                        if p.is_dir() {
                            search_dirs.push(p);
                        }
                    }
                }
            }
        }

        // 2. Standard paths
        let standard_1 = home.join(".cache").join("lm-studio").join("models");
        if standard_1.is_dir() && !search_dirs.contains(&standard_1) {
            search_dirs.push(standard_1);
        }

        let standard_2 = home.join(".lmstudio").join("models");
        if standard_2.is_dir() && !search_dirs.contains(&standard_2) {
            search_dirs.push(standard_2);
        }

        let mut items = Vec::new();

        for root in search_dirs {
            // Traverse <org>/<repo>/
            if let Ok(org_entries) = fs::read_dir(&root) {
                for org_entry in org_entries.flatten() {
                    let org_path = org_entry.path();
                    if !org_path.is_dir() {
                        continue;
                    }

                    let org_name = org_entry.file_name().to_string_lossy().to_string();
                    if org_name.starts_with('.') {
                        continue;
                    }

                    if let Ok(repo_entries) = fs::read_dir(&org_path) {
                        for repo_entry in repo_entries.flatten() {
                            let repo_path = repo_entry.path();
                            if !repo_path.is_dir() {
                                continue;
                            }

                            let repo_name = repo_entry.file_name().to_string_lossy().to_string();
                            if repo_name.starts_with('.') {
                                continue;
                            }

                            // Inspect contents of repo_path
                            let (size_bytes, format, metadata, mod_secs, acc_secs) =
                                inspect_lm_studio_repo(&repo_path);

                            if size_bytes == 0 {
                                continue;
                            }

                            let inactivity = InactivityTier::from_timestamps(mod_secs, acc_secs, now_secs);

                            items.push(AiModelItem {
                                name: repo_name,
                                path: repo_path.to_string_lossy().to_string(),
                                organization: Some(org_name.clone()),
                                ecosystem: AiModelEcosystem::LmStudio,
                                format,
                                metadata,
                                size_bytes,
                                modified_secs: mod_secs,
                                accessed_secs: acc_secs,
                                inactivity,
                                can_collect: true,
                                associated_paths: vec![repo_path.to_string_lossy().to_string()],
                            });
                        }
                    }
                }
            }
        }

        items
    }
}

fn inspect_lm_studio_repo(repo_path: &Path) -> (u64, ModelFormat, ModelMetadata, u64, u64) {
    let mut total_size = 0u64;
    let mut detected_format = ModelFormat::GenericWeight;
    let mut metadata = ModelMetadata::default();
    let mut latest_mod_secs = 0u64;
    let mut latest_acc_secs = 0u64;

    if let Ok(entries) = fs::read_dir(repo_path) {
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
                    if fname.ends_with(".gguf") {
                        detected_format = ModelFormat::Gguf;
                        if metadata.architecture.is_none() {
                            if let Some(m) = GgufParser::parse_file(&path) {
                                metadata = m;
                            }
                        }
                    } else if fname.ends_with(".safetensors") {
                        if detected_format != ModelFormat::Gguf {
                            detected_format = ModelFormat::Safetensors;
                        }
                        if metadata.architecture.is_none() {
                            if let Some(m) = SafetensorsParser::parse_file(&path) {
                                metadata = m;
                            }
                        }
                    } else if fname == "config.json" && metadata.architecture.is_none() {
                        if let Ok(content) = fs::read_to_string(&path) {
                            if let Ok(cfg) = serde_json::from_str::<serde_json::Value>(&content) {
                                if let Some(arch) = cfg.get("model_type").and_then(|s| s.as_str()) {
                                    metadata.architecture = Some(crate::parsers::gguf::format_architecture(arch));
                                }
                                if let Some(ctx) = cfg.get("max_position_embeddings").and_then(|c| c.as_u64()) {
                                    metadata.context_length = Some(ctx as u32);
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // Fallback metadata from repo folder name
    let repo_name = repo_path.file_name().and_then(|s| s.to_str()).unwrap_or("");
    if metadata.architecture.is_none() {
        metadata.architecture = crate::parsers::gguf::extract_arch_from_name(repo_name);
    }
    if metadata.parameter_size.is_none() {
        metadata.parameter_size = crate::parsers::gguf::extract_param_size_from_name(repo_name);
    }
    if metadata.quantization.is_none() {
        metadata.quantization = crate::parsers::gguf::extract_quant_from_name(repo_name);
    }

    (total_size, detected_format, metadata, latest_mod_secs, latest_acc_secs)
}
