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

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum DockerEngineKind {
    DockerDesktop,
    OrbStack,
    Colima,
    Generic,
}

impl DockerEngineKind {
    pub fn display_name(&self) -> &'static str {
        match self {
            Self::DockerDesktop => "Docker Desktop",
            Self::OrbStack => "OrbStack",
            Self::Colima => "Colima",
            Self::Generic => "Docker Engine",
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum DockerDaemonStatus {
    Running,
    Stopped,
    SocketNotFound,
    PermissionDenied,
}

impl DockerDaemonStatus {
    pub fn display_name(&self) -> &'static str {
        match self {
            Self::Running => "Running",
            Self::Stopped => "Stopped",
            Self::SocketNotFound => "Socket Not Found",
            Self::PermissionDenied => "Permission Denied",
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DockerVmDisk {
    pub name: String,
    pub path: String,
    pub engine: DockerEngineKind,
    pub allocated_bytes: u64,
    pub virtual_capacity_bytes: u64,
    pub modified_secs: u64,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DockerImageItem {
    pub id: String,
    pub repo_tags: Vec<String>,
    pub size_bytes: u64,
    pub shared_size_bytes: u64,
    pub is_dangling: bool,
    pub in_use: bool,
    pub created_secs: u64,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DockerVolumeItem {
    pub name: String,
    pub driver: String,
    pub size_bytes: u64,
    pub is_anonymous: bool,
    pub in_use: bool,
    pub ref_count: i64,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DockerBuildCacheItem {
    pub id: String,
    pub cache_type: String,
    pub description: String,
    pub size_bytes: u64,
    pub in_use: bool,
    pub shared: bool,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DockerContainerItem {
    pub id: String,
    pub names: Vec<String>,
    pub image: String,
    pub state: String,
    pub size_rw_bytes: u64,
}

#[derive(Debug, Default, Clone, Serialize, Deserialize)]
pub struct DockerStorageSummary {
    pub daemon_status: DockerDaemonStatus,
    pub engine_name: String,
    pub socket_path: String,
    pub vm_disks: Vec<DockerVmDisk>,
    pub total_host_allocated_bytes: u64,
    pub total_guest_active_bytes: u64,
    pub phantom_bloat_bytes: u64,
    pub images_total_bytes: u64,
    pub dangling_images_bytes: u64,
    pub unused_images_bytes: u64,
    pub volumes_total_bytes: u64,
    pub dangling_anonymous_volumes_bytes: u64,
    pub dangling_named_volumes_bytes: u64,
    pub build_cache_total_bytes: u64,
    pub build_cache_reclaimable_bytes: u64,
    pub stopped_containers_bytes: u64,
    pub images: Vec<DockerImageItem>,
    pub volumes: Vec<DockerVolumeItem>,
    pub build_cache: Vec<DockerBuildCacheItem>,
    pub containers: Vec<DockerContainerItem>,
}

impl Default for DockerDaemonStatus {
    fn default() -> Self {
        Self::Stopped
    }
}

#[derive(Debug, Default, Clone, Serialize, Deserialize)]
pub struct DockerPruneResult {
    pub success: bool,
    pub reclaimed_bytes: u64,
    pub message: String,
}
