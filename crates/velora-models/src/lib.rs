#[cfg(not(all(target_os = "macos", target_arch = "aarch64")))]
compile_error!("Velora requires macOS 15 (Sequoia) or later on Apple Silicon (ARM64). Architecture x86_64 / Intel is not supported.");

pub mod hunter;
pub mod locators;
pub mod model;
pub mod parsers;

pub use hunter::ModelWeightHunter;
pub use model::{
    AiModelEcosystem, AiModelItem, AiModelSummary, InactivityTier, ModelFormat, ModelMetadata,
};
pub use parsers::{GgufParser, SafetensorsParser};

#[cfg(test)]
mod tests {
    use super::*;
    use std::fs;
    use std::io::Write;

    #[test]
    fn test_inactivity_tier_calculation() {
        let now = 100_000_000u64;
        let active_time = now - 5 * 86_400; // 5 days ago
        let idle_time = now - 25 * 86_400;  // 25 days ago
        let stale_time = now - 75 * 86_400; // 75 days ago

        assert_eq!(
            InactivityTier::from_timestamps(active_time, active_time, now),
            InactivityTier::Active
        );
        assert_eq!(
            InactivityTier::from_timestamps(idle_time, idle_time, now),
            InactivityTier::Idle
        );
        assert_eq!(
            InactivityTier::from_timestamps(stale_time, stale_time, now),
            InactivityTier::Stale
        );
    }

    #[test]
    fn test_format_parameter_count() {
        use parsers::gguf::format_parameter_count;
        assert_eq!(format_parameter_count(70_000_000_000), "70B");
        assert_eq!(format_parameter_count(32_470_000_000), "32.5B");
        assert_eq!(format_parameter_count(8_000_000_000), "8B");
        assert_eq!(format_parameter_count(1_200_000_000), "1.2B");
        assert_eq!(format_parameter_count(400_000_000), "400M");
    }

    #[test]
    fn test_mock_gguf_header_parser() {
        let dir = std::env::temp_dir().join("velora_test_gguf");
        let _ = fs::remove_dir_all(&dir);
        fs::create_dir_all(&dir).unwrap();
        let gguf_path = dir.join("mock.gguf");

        // Construct valid minimal GGUF v3 header
        let mut bytes = Vec::new();
        // Magic
        bytes.extend_from_slice(&[0x47, 0x47, 0x55, 0x46]);
        // Version (u32 = 3)
        bytes.extend_from_slice(&3u32.to_le_bytes());
        // Tensor count (u64 = 10)
        bytes.extend_from_slice(&10u64.to_le_bytes());
        // Metadata KV count (u64 = 2)
        bytes.extend_from_slice(&2u64.to_le_bytes());

        // Key 1: "general.architecture"
        let key1 = "general.architecture";
        bytes.extend_from_slice(&(key1.len() as u64).to_le_bytes());
        bytes.extend_from_slice(key1.as_bytes());
        // Value type 8 (STRING)
        bytes.extend_from_slice(&8u32.to_le_bytes());
        let val1 = "qwen2";
        bytes.extend_from_slice(&(val1.len() as u64).to_le_bytes());
        bytes.extend_from_slice(val1.as_bytes());

        // Key 2: "general.file_type"
        let key2 = "general.file_type";
        bytes.extend_from_slice(&(key2.len() as u64).to_le_bytes());
        bytes.extend_from_slice(key2.as_bytes());
        // Value type 4 (UINT32)
        bytes.extend_from_slice(&4u32.to_le_bytes());
        // File type 15 = Q4_K_M
        bytes.extend_from_slice(&15u32.to_le_bytes());

        let mut file = std::fs::File::create(&gguf_path).unwrap();
        file.write_all(&bytes).unwrap();

        let meta = GgufParser::parse_file(&gguf_path).expect("Failed to parse mock GGUF");
        assert_eq!(meta.architecture.as_deref(), Some("Qwen 2.5"));
        assert_eq!(meta.quantization.as_deref(), Some("Q4_K_M"));
        let _ = fs::remove_dir_all(&dir);
    }

    #[test]
    fn test_mock_safetensors_header_parser() {
        let dir = std::env::temp_dir().join("velora_test_st");
        let _ = fs::remove_dir_all(&dir);
        fs::create_dir_all(&dir).unwrap();
        let st_path = dir.join("mock.safetensors");

        let json_header = r#"{"__metadata__":{"model_type":"llama","dtype":"BF16"},"weight":{"dtype":"BF16","shape":[128,128]}}"#;
        let mut bytes = Vec::new();
        let header_len = json_header.len() as u64;
        bytes.extend_from_slice(&header_len.to_le_bytes());
        bytes.extend_from_slice(json_header.as_bytes());

        let mut file = std::fs::File::create(&st_path).unwrap();
        file.write_all(&bytes).unwrap();

        let meta = SafetensorsParser::parse_file(&st_path).expect("Failed to parse mock Safetensors");
        assert_eq!(meta.architecture.as_deref(), Some("Llama"));
        assert_eq!(meta.quantization.as_deref(), Some("BF16"));
        let _ = fs::remove_dir_all(&dir);
    }

    #[test]
    fn test_model_weight_hunter_e2e() {
        let temp_home = std::env::temp_dir().join("velora_test_ai_home");
        let _ = fs::remove_dir_all(&temp_home);

        // 1. Setup LM Studio mock
        let lm_model_dir = temp_home.join(".cache/lm-studio/models/meta/Llama-3-8B");
        fs::create_dir_all(&lm_model_dir).unwrap();
        fs::write(lm_model_dir.join("Llama-3-8B-Q4_K_M.gguf"), vec![0u8; 500_000]).unwrap();

        // 2. Setup Ollama mock
        let ollama_manifest_dir = temp_home.join(".ollama/models/manifests/registry.ollama.ai/library/qwen2.5/7b");
        let ollama_blobs_dir = temp_home.join(".ollama/models/blobs");
        fs::create_dir_all(&ollama_manifest_dir.parent().unwrap()).unwrap();
        fs::create_dir_all(&ollama_blobs_dir).unwrap();

        let blob_name = "sha256-abcdef1234567890";
        fs::write(ollama_blobs_dir.join(blob_name), vec![0u8; 1_000_000]).unwrap();

        let manifest_json = format!(
            r#"{{"schemaVersion":2,"mediaType":"application/vnd.docker.distribution.manifest.v2+json","layers":[{{"mediaType":"application/vnd.ollama.image.model","digest":"sha256:abcdef1234567890","size":1000000}}]}}"#
        );
        fs::write(&ollama_manifest_dir, manifest_json).unwrap();

        let summary = ModelWeightHunter::hunt_home(&temp_home);
        assert_eq!(summary.total_model_count, 2);
        assert_eq!(summary.total_bytes, 1_500_000);
        assert_eq!(summary.items[0].size_bytes, 1_000_000); // Largest first
        assert_eq!(summary.items[0].ecosystem, AiModelEcosystem::Ollama);
        assert_eq!(summary.items[1].ecosystem, AiModelEcosystem::LmStudio);

        let _ = fs::remove_dir_all(&temp_home);
    }

    #[test]
    fn test_live_host_inspection() {
        let home = std::path::Path::new("/Users/ahmet");
        if home.is_dir() {
            let summary = ModelWeightHunter::hunt_home(home);
            println!("Discovered {} live AI models (total bytes: {})", summary.total_model_count, summary.total_bytes);
            for item in &summary.items {
                println!(
                    " - [{}] {} ({:?}, {:?}) - {} bytes",
                    item.ecosystem.display_name(),
                    item.name,
                    item.metadata.architecture,
                    item.metadata.quantization,
                    item.size_bytes
                );
            }
            assert!(summary.total_model_count >= 1);
        }
    }
}
