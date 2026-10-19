use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum DevArtifactKind {
    NodeModules,
    RustTarget,
    PythonVenv,
    SwiftBuild,
    GradleBuild,
    GenericBuild,
}

impl DevArtifactKind {
    pub fn display_name(&self) -> &'static str {
        match self {
            Self::NodeModules => "Node.js (node_modules)",
            Self::RustTarget => "Rust (target/)",
            Self::PythonVenv => "Python Virtualenv",
            Self::SwiftBuild => "SwiftPM (.build/)",
            Self::GradleBuild => "Gradle / JVM Build",
            Self::GenericBuild => "Build Artifact",
        }
    }

    pub fn color_hex(&self) -> &'static str {
        match self {
            Self::NodeModules => "#10B981", // Emerald Green (Node)
            Self::RustTarget => "#F59E0B",  // Rust Amber
            Self::PythonVenv => "#3B82F6",  // Blue (Python)
            Self::SwiftBuild => "#EC4899",  // Swift Orange/Pink
            Self::GradleBuild => "#8B5CF6", // Purple
            Self::GenericBuild => "#6B7280",// Slate
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
            Self::Active => "#10B981", // Green (caution)
            Self::Idle => "#F59E0B",   // Amber
            Self::Stale => "#EF4444",  // Red / Safe to clear
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DevArtifactItem {
    pub path: String,
    pub name: String,
    pub kind: DevArtifactKind,
    pub size_bytes: u64,
    pub modified_secs: u64,
    pub inactivity: InactivityTier,
    pub parent_project_name: String,
    pub color_hex: String,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum XcodeCategoryKind {
    DerivedData,
    Archives,
    DeviceSupport,
    Simulators,
    DocumentationCache,
}

impl XcodeCategoryKind {
    pub fn display_name(&self) -> &'static str {
        match self {
            Self::DerivedData => "DerivedData (Build Output)",
            Self::Archives => "Xcode Archives (.xcarchive)",
            Self::DeviceSupport => "Device Support Symbols",
            Self::Simulators => "CoreSimulator Devices",
            Self::DocumentationCache => "Documentation & Tool Caches",
        }
    }

    pub fn color_hex(&self) -> &'static str {
        match self {
            Self::DerivedData => "#3B82F6",    // Blue
            Self::Archives => "#8B5CF6",       // Purple
            Self::DeviceSupport => "#F59E0B",  // Amber
            Self::Simulators => "#10B981",     // Emerald
            Self::DocumentationCache => "#6B7280", // Slate
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct XcodeItem {
    pub name: String,
    pub path: String,
    pub category: XcodeCategoryKind,
    pub size_bytes: u64,
    pub modified_secs: u64,
    pub color_hex: String,
}

#[derive(Debug, Default, Clone, Serialize, Deserialize)]
pub struct XcodeStorageSummary {
    pub derived_data_bytes: u64,
    pub archives_bytes: u64,
    pub device_support_bytes: u64,
    pub simulator_bytes: u64,
    pub total_bytes: u64,
    pub items: Vec<XcodeItem>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum CacheEcosystem {
    Homebrew,
    RustCargo,
    NodeNpm,
    PythonPip,
    JvmGradle,
    Golang,
    AppleCocoaPods,
    Docker,
}

impl CacheEcosystem {
    pub fn display_name(&self) -> &'static str {
        match self {
            Self::Homebrew => "Homebrew",
            Self::RustCargo => "Rust (Cargo)",
            Self::NodeNpm => "Node (npm/yarn/pnpm)",
            Self::PythonPip => "Python (pip/uv)",
            Self::JvmGradle => "JVM (Gradle/Maven)",
            Self::Golang => "Go (build cache)",
            Self::AppleCocoaPods => "CocoaPods",
            Self::Docker => "Docker Containers",
        }
    }

    pub fn color_hex(&self) -> &'static str {
        match self {
            Self::Homebrew => "#FBBF24",
            Self::RustCargo => "#F97316",
            Self::NodeNpm => "#10B981",
            Self::PythonPip => "#3B82F6",
            Self::JvmGradle => "#8B5CF6",
            Self::Golang => "#00E5FF",
            Self::AppleCocoaPods => "#EC4899",
            Self::Docker => "#2563EB",
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PackageCacheItem {
    pub name: String,
    pub path: String,
    pub ecosystem: CacheEcosystem,
    pub size_bytes: u64,
    pub modified_secs: u64,
    pub color_hex: String,
    pub can_collect: bool,
}

#[derive(Debug, Default, Clone, Serialize, Deserialize)]
pub struct PackageCacheSummary {
    pub total_bytes: u64,
    pub items: Vec<PackageCacheItem>,
}
