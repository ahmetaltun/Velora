use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
pub enum AiModelEcosystem {
    Ollama,
    HuggingFace,
    LmStudio,
    TorchHub,
    AppleMlx,
    ComfyUi,
    Jan,
    LooseWeight,
}

impl AiModelEcosystem {
    pub fn display_name(&self) -> &'static str {
        match self {
            Self::Ollama => "Ollama",
            Self::HuggingFace => "Hugging Face Hub",
            Self::LmStudio => "LM Studio",
            Self::TorchHub => "PyTorch / Torch Hub",
            Self::AppleMlx => "Apple MLX",
            Self::ComfyUi => "ComfyUI / Diffusion",
            Self::Jan => "Jan.ai",
            Self::LooseWeight => "Loose Weights",
        }
    }

    pub fn color_hex(&self) -> &'static str {
        match self {
            Self::Ollama => "#F97316",      // Orange
            Self::HuggingFace => "#FBBF24", // Amber / HF Gold
            Self::LmStudio => "#38BDF8",    // Sky Blue
            Self::TorchHub => "#EF4444",    // PyTorch Red
            Self::AppleMlx => "#A855F7",    // Apple Purple
            Self::ComfyUi => "#10B981",     // Emerald Mint
            Self::Jan => "#6366F1",         // Indigo
            Self::LooseWeight => "#94A3B8", // Slate
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
pub enum ModelFormat {
    Gguf,
    Safetensors,
    PyTorchCheckpoint,
    Onnx,
    OllamaBlob,
    GenericWeight,
}

impl ModelFormat {
    pub fn display_name(&self) -> &'static str {
        match self {
            Self::Gguf => "GGUF",
            Self::Safetensors => "Safetensors",
            Self::PyTorchCheckpoint => "PyTorch (.pth/.pt)",
            Self::Onnx => "ONNX",
            Self::OllamaBlob => "Ollama Blob",
            Self::GenericWeight => "Model Weight",
        }
    }

    pub fn from_extension(ext: &str) -> Self {
        match ext.to_lowercase().as_str() {
            "gguf" => Self::Gguf,
            "safetensors" => Self::Safetensors,
            "pt" | "pth" | "bin" | "ckpt" => Self::PyTorchCheckpoint,
            "onnx" => Self::Onnx,
            _ => Self::GenericWeight,
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum InactivityTier {
    Active, // < 14 days
    Idle,   // 14..60 days
    Stale,  // > 60 days (Safe to delete)
}

impl InactivityTier {
    pub fn label(&self) -> &'static str {
        match self {
            Self::Active => "Active (< 14d)",
            Self::Idle => "Idle (14–60d)",
            Self::Stale => "Stale (> 60d)",
        }
    }

    pub fn color_hex(&self) -> &'static str {
        match self {
            Self::Active => "#10B981", // Green (frequently used)
            Self::Idle => "#F59E0B",   // Amber
            Self::Stale => "#EF4444",  // Coral / Safe to reclaim
        }
    }

    pub fn from_timestamps(modified_secs: u64, accessed_secs: u64, now_secs: u64) -> Self {
        let last_activity = modified_secs.max(accessed_secs);
        if last_activity >= now_secs {
            return Self::Active;
        }
        let age_secs = now_secs.saturating_sub(last_activity);
        let days = age_secs / 86_400;

        if days < 14 {
            Self::Active
        } else if days <= 60 {
            Self::Idle
        } else {
            Self::Stale
        }
    }
}

#[derive(Debug, Default, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct ModelMetadata {
    pub architecture: Option<String>,
    pub quantization: Option<String>,
    pub parameter_size: Option<String>,
    pub context_length: Option<u32>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AiModelItem {
    pub name: String,
    pub path: String,
    pub organization: Option<String>,
    pub ecosystem: AiModelEcosystem,
    pub format: ModelFormat,
    pub metadata: ModelMetadata,
    pub size_bytes: u64,
    pub modified_secs: u64,
    pub accessed_secs: u64,
    pub inactivity: InactivityTier,
    pub can_collect: bool,
    pub associated_paths: Vec<String>,
}

#[derive(Debug, Default, Clone, Serialize, Deserialize)]
pub struct AiModelSummary {
    pub total_bytes: u64,
    pub stale_bytes: u64,
    pub total_model_count: u32,
    pub stale_model_count: u32,
    pub items: Vec<AiModelItem>,
}
