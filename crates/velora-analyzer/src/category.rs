use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
pub enum CategoryKind {
    DevCaches,
    Media,
    Documents,
    Archives,
    SystemPurgeable,
    Other,
}

impl CategoryKind {
    pub fn classify(name: &str, is_dir: bool) -> Self {
        let lower = name.to_lowercase();

        if is_dir {
            if lower == "node_modules"
                || lower == "target"
                || lower == ".build"
                || lower == "deriveddata"
                || lower == ".gradle"
                || lower == "venv"
                || lower == ".venv"
                || lower == "__pycache__"
            {
                return CategoryKind::DevCaches;
            }
            if lower == "caches" || lower == "logs" || lower == "crashreporter" {
                return CategoryKind::SystemPurgeable;
            }
        }

        if let Some(ext) = lower.rsplit('.').next() {
            match ext {
                "mp4" | "mkv" | "mov" | "avi" | "mp3" | "flac" | "wav" | "png" | "jpg"
                | "jpeg" | "heic" | "webp" | "gif" | "svg" => CategoryKind::Media,
                "pdf" | "docx" | "doc" | "xlsx" | "pptx" | "txt" | "md" | "json" | "csv" => {
                    CategoryKind::Documents
                }
                "zip" | "tar" | "gz" | "bz2" | "xz" | "7z" | "dmg" | "iso" | "pkg" => {
                    CategoryKind::Archives
                }
                _ => CategoryKind::Other,
            }
        } else {
            CategoryKind::Other
        }
    }

    pub fn color_hex(&self) -> &'static str {
        match self {
            CategoryKind::DevCaches => "#F59E0B",      // Amber
            CategoryKind::Media => "#3B82F6",          // Blue
            CategoryKind::Documents => "#10B981",      // Emerald
            CategoryKind::Archives => "#8B5CF6",       // Purple
            CategoryKind::SystemPurgeable => "#EF4444",// Red
            CategoryKind::Other => "#6B7280",          // Gray
        }
    }

    pub fn display_name(&self) -> &'static str {
        match self {
            CategoryKind::DevCaches => "Developer",
            CategoryKind::Media => "Media",
            CategoryKind::Documents => "Documents",
            CategoryKind::Archives => "Archives",
            CategoryKind::SystemPurgeable => "System Purgeable",
            CategoryKind::Other => "Other",
        }
    }
}
