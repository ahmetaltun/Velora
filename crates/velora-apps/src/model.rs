use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum AppPartKind {
    ApplicationBundle,
    ApplicationSupport,
    CachesAndLogs,
    SandboxedContainer,
    PreferencesAndDaemons,
}

impl AppPartKind {
    pub fn display_name(&self) -> &'static str {
        match self {
            Self::ApplicationBundle => "Application Bundle (.app)",
            Self::ApplicationSupport => "Application Support Data",
            Self::CachesAndLogs => "Caches & WebKit Storage",
            Self::SandboxedContainer => "Sandboxed Container",
            Self::PreferencesAndDaemons => "Preferences & LaunchDaemons",
        }
    }

    pub fn color_hex(&self) -> &'static str {
        match self {
            Self::ApplicationBundle => "#3B82F6",    // Blue
            Self::ApplicationSupport => "#10B981",   // Emerald
            Self::CachesAndLogs => "#F59E0B",        // Amber
            Self::SandboxedContainer => "#8B5CF6",   // Purple
            Self::PreferencesAndDaemons => "#6B7280",// Slate
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AppPart {
    pub name: String,
    pub path: String,
    pub kind: AppPartKind,
    pub size_bytes: u64,
    pub color_hex: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct InstalledApp {
    pub name: String,
    pub bundle_id: String,
    pub version: String,
    pub app_path: String,
    pub is_system_app: bool,
    pub total_size_bytes: u64,
    pub parts: Vec<AppPart>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct OrphanedResidue {
    pub name: String,
    pub path: String,
    pub inferred_bundle_id: String,
    pub category_name: String,
    pub size_bytes: u64,
    pub modified_secs: u64,
}
