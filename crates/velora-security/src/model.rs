use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Copy, PartialEq, Eq, PartialOrd, Ord, Serialize, Deserialize)]
pub enum ThreatSeverity {
    Warning,
    Medium,
    High,
    Critical,
}

impl ThreatSeverity {
    pub fn display_name(&self) -> &'static str {
        match self {
            Self::Warning => "Warning",
            Self::Medium => "Medium",
            Self::High => "High",
            Self::Critical => "Critical",
        }
    }

    pub fn color_hex(&self) -> &'static str {
        match self {
            Self::Warning => "#F59E0B",  // Amber
            Self::Medium => "#FB923C",   // Orange
            Self::High => "#EF4444",     // Red
            Self::Critical => "#DC2626", // Deep Red
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum ThreatCategory {
    InfoStealer,
    Adware,
    Trojan,
    SuspiciousPersistence,
    InvalidSignature,
    PotentiallyUnwantedProgram,
}

impl ThreatCategory {
    pub fn display_name(&self) -> &'static str {
        match self {
            Self::InfoStealer => "Info Stealer",
            Self::Adware => "Adware / Hijacker",
            Self::Trojan => "Trojan / Backdoor",
            Self::SuspiciousPersistence => "Suspicious Persistence",
            Self::InvalidSignature => "Invalid Signature",
            Self::PotentiallyUnwantedProgram => "PUP / PUA",
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub enum SigningStatus {
    AppleInternal,
    DeveloperIdSigned {
        authority: String,
        team_id: Option<String>,
    },
    AdHoc,
    Unsigned,
    InvalidSignature {
        error: String,
    },
    Unknown,
}

impl SigningStatus {
    pub fn label(&self) -> String {
        match self {
            Self::AppleInternal => "Apple System Signed".to_string(),
            Self::DeveloperIdSigned { authority, .. } => format!("Developer Signed ({})", authority),
            Self::AdHoc => "Ad-Hoc (Self-Signed)".to_string(),
            Self::Unsigned => "Unsigned Code".to_string(),
            Self::InvalidSignature { error } => format!("Tampered/Invalid Signature: {}", error),
            Self::Unknown => "Unknown Signature".to_string(),
        }
    }

    pub fn is_trusted(&self) -> bool {
        matches!(self, Self::AppleInternal | Self::DeveloperIdSigned { .. })
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ThreatRecord {
    pub id: String,
    pub name: String,
    pub category: ThreatCategory,
    pub severity: ThreatSeverity,
    pub target_path: String,
    pub associated_paths: Vec<String>,
    pub file_size: u64,
    pub sha256_hex: String,
    pub signing_status: String,
    pub description: String,
    pub detection_method: String,
    pub can_quarantine: bool,
}

#[derive(Debug, Default, Clone, Serialize, Deserialize)]
pub struct SecurityScanSummary {
    pub total_candidates_triaged: u32,
    pub total_asep_inspected: u32,
    pub threat_count: u32,
    pub threats: Vec<ThreatRecord>,
    pub scan_duration_ms: u64,
}
