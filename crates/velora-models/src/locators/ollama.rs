use crate::model::{
    AiModelEcosystem, AiModelItem, InactivityTier, ModelFormat, ModelMetadata,
};
use crate::parsers::GgufParser;
use std::collections::{HashMap, HashSet};
use std::fs;
use std::path::{Path, PathBuf};

pub struct OllamaLocator;

impl OllamaLocator {
    pub fn locate(home: &Path, now_secs: u64) -> Vec<AiModelItem> {
        let models_dir = match std::env::var("OLLAMA_MODELS") {
            Ok(p) => PathBuf::from(p),
            Err(_) => home.join(".ollama").join("models"),
        };

        if !models_dir.is_dir() {
            return Vec::new();
        }

        let manifests_dir = models_dir.join("manifests");
        let blobs_dir = models_dir.join("blobs");

        if !manifests_dir.is_dir() {
            return Vec::new();
        }

        // 1. Gather all manifest files recursively
        let mut manifest_files = Vec::new();
        collect_manifests(&manifests_dir, &mut manifest_files);

        // 2. Count references for each blob to determine if it's shared
        let mut blob_ref_counts: HashMap<String, usize> = HashMap::new();
        let mut parsed_manifests = Vec::new();

        for m_path in manifest_files {
            if let Ok(content) = fs::read_to_string(&m_path) {
                if let Ok(json) = serde_json::from_str::<serde_json::Value>(&content) {
                    let mut blob_names = Vec::new();
                    let mut total_size = 0u64;
                    let mut model_blob_name = None;

                    if let Some(layers) = json.get("layers").and_then(|l| l.as_array()) {
                        for layer in layers {
                            if let Some(digest) = layer.get("digest").and_then(|d| d.as_str()) {
                                // digest format is "sha256:abc..." -> filename is "sha256-abc..."
                                let clean_blob = digest.replace(':', "-");
                                *blob_ref_counts.entry(clean_blob.clone()).or_insert(0) += 1;

                                let sz = layer.get("size").and_then(|s| s.as_u64()).unwrap_or(0);
                                total_size += sz;

                                if let Some(media) = layer.get("mediaType").and_then(|m| m.as_str()) {
                                    if media == "application/vnd.ollama.image.model" {
                                        model_blob_name = Some(clean_blob.clone());
                                    }
                                }
                                blob_names.push(clean_blob);
                            }
                        }
                    }

                    parsed_manifests.push((m_path, total_size, model_blob_name, blob_names));
                }
            }
        }

        let mut items = Vec::new();

        for (m_path, total_size, model_blob_name, blob_names) in parsed_manifests {
            // Derive model name and tag from relative path
            // e.g. manifests/registry.ollama.ai/library/llama3.2/3b -> "llama3.2:3b"
            let rel = m_path.strip_prefix(&manifests_dir).unwrap_or(&m_path);
            let components: Vec<&str> = rel
                .iter()
                .filter_map(|c| c.to_str())
                .collect();

            let (org, display_name) = if components.len() >= 3 {
                let org = components[components.len() - 3].to_string();
                let model = components[components.len() - 2];
                let tag = components[components.len() - 1];
                (Some(org), format!("{}:{}", model, tag))
            } else if components.len() == 2 {
                (None, format!("{}:{}", components[0], components[1]))
            } else {
                (None, rel.to_string_lossy().to_string())
            };

            // Inspect model blob with GGUF parser if present
            let mut metadata = ModelMetadata::default();
            if let Some(ref mb) = model_blob_name {
                let blob_path = blobs_dir.join(mb);
                if blob_path.is_file() {
                    if let Some(meta) = GgufParser::parse_file(&blob_path) {
                        metadata = meta;
                    }
                }
            }

            // Fallback metadata from name
            if metadata.architecture.is_none() {
                metadata.architecture = crate::parsers::gguf::extract_arch_from_name(&display_name);
            }
            if metadata.parameter_size.is_none() {
                metadata.parameter_size = crate::parsers::gguf::extract_param_size_from_name(&display_name);
            }
            if metadata.quantization.is_none() {
                metadata.quantization = crate::parsers::gguf::extract_quant_from_name(&display_name);
            }

            let meta = fs::metadata(&m_path).ok();
            let modified_secs = meta
                .as_ref()
                .and_then(|m| m.modified().ok())
                .and_then(|t| t.duration_since(std::time::UNIX_EPOCH).ok())
                .map(|d| d.as_secs())
                .unwrap_or(0);

            let accessed_secs = meta
                .as_ref()
                .and_then(|m| m.accessed().ok())
                .and_then(|t| t.duration_since(std::time::UNIX_EPOCH).ok())
                .map(|d| d.as_secs())
                .unwrap_or(modified_secs);

            let inactivity = InactivityTier::from_timestamps(modified_secs, accessed_secs, now_secs);

            let mut associated = Vec::new();
            associated.push(m_path.to_string_lossy().to_string());
            for b in &blob_names {
                // If blob is only referenced by this manifest, include it in collectable paths
                if blob_ref_counts.get(b).copied().unwrap_or(0) == 1 {
                    associated.push(blobs_dir.join(b).to_string_lossy().to_string());
                }
            }

            items.push(AiModelItem {
                name: display_name,
                path: m_path.to_string_lossy().to_string(),
                organization: org,
                ecosystem: AiModelEcosystem::Ollama,
                format: ModelFormat::OllamaBlob,
                metadata,
                size_bytes: total_size,
                modified_secs,
                accessed_secs,
                inactivity,
                can_collect: true,
                associated_paths: associated,
            });
        }

        items
    }

    /// Finds and deletes unreferenced blobs from ~/.ollama/models/blobs/
    pub fn prune_orphaned_blobs(home: &Path) -> u64 {
        let models_dir = match std::env::var("OLLAMA_MODELS") {
            Ok(p) => PathBuf::from(p),
            Err(_) => home.join(".ollama").join("models"),
        };

        let manifests_dir = models_dir.join("manifests");
        let blobs_dir = models_dir.join("blobs");

        if !manifests_dir.is_dir() || !blobs_dir.is_dir() {
            return 0;
        }

        let mut manifest_files = Vec::new();
        collect_manifests(&manifests_dir, &mut manifest_files);

        let mut referenced_blobs: HashSet<String> = HashSet::new();
        for m_path in manifest_files {
            if let Ok(content) = fs::read_to_string(&m_path) {
                if let Ok(json) = serde_json::from_str::<serde_json::Value>(&content) {
                    if let Some(layers) = json.get("layers").and_then(|l| l.as_array()) {
                        for layer in layers {
                            if let Some(digest) = layer.get("digest").and_then(|d| d.as_str()) {
                                referenced_blobs.insert(digest.replace(':', "-"));
                            }
                        }
                    }
                }
            }
        }

        let mut freed_bytes = 0u64;
        if let Ok(entries) = fs::read_dir(&blobs_dir) {
            for entry in entries.flatten() {
                let name = entry.file_name().to_string_lossy().to_string();
                if name.starts_with("sha256-") && !referenced_blobs.contains(&name) {
                    if let Ok(meta) = entry.metadata() {
                        let sz = meta.len();
                        if fs::remove_file(entry.path()).is_ok() {
                            freed_bytes += sz;
                        }
                    }
                }
            }
        }

        freed_bytes
    }
}

fn collect_manifests(dir: &Path, out: &mut Vec<PathBuf>) {
    if let Ok(entries) = fs::read_dir(dir) {
        for entry in entries.flatten() {
            let path = entry.path();
            if path.is_dir() {
                collect_manifests(&path, out);
            } else if path.is_file() {
                // Ignore dot files or ds_store
                if let Some(name) = path.file_name().and_then(|n| n.to_str()) {
                    if !name.starts_with('.') {
                        out.push(path);
                    }
                }
            }
        }
    }
}
