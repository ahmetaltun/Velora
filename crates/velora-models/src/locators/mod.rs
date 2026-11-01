pub mod comfyui;
pub mod huggingface;
pub mod lmstudio;
pub mod loose;
pub mod mlx;
pub mod ollama;
pub mod pytorch;

pub use comfyui::ComfyUiLocator;
pub use huggingface::HuggingFaceLocator;
pub use lmstudio::LmStudioLocator;
pub use loose::LooseWeightLocator;
pub use mlx::MlxLocator;
pub use ollama::OllamaLocator;
pub use pytorch::PyTorchLocator;
