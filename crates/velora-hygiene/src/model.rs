use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
pub enum AgeBucket {
    /// Modified within the last 30 days
    Recent = 0,
    /// Modified between 30 and 180 days ago (1 - 6 months)
    Months1To6 = 1,
    /// Modified between 180 and 365 days ago (6 - 12 months)
    Months6To12 = 2,
    /// Modified more than 365 days ago (> 1 year)
    Ancient = 3,
}

impl AgeBucket {
    pub fn from_age_secs(age_secs: u64) -> Self {
        const DAY: u64 = 86_400;
        if age_secs < 30 * DAY {
            AgeBucket::Recent
        } else if age_secs < 180 * DAY {
            AgeBucket::Months1To6
        } else if age_secs < 365 * DAY {
            AgeBucket::Months6To12
        } else {
            AgeBucket::Ancient
        }
    }

    pub fn display_name(&self) -> &'static str {
        match self {
            AgeBucket::Recent => "Recent (< 1 mo)",
            AgeBucket::Months1To6 => "1 – 6 Months",
            AgeBucket::Months6To12 => "6 – 12 Months",
            AgeBucket::Ancient => "Ancient (> 1 yr)",
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
pub enum SizeBucket {
    /// Greater than or equal to 1 GB
    Gigabytes = 0,
    /// 500 MB to 1 GB
    Huge = 1,
    /// 100 MB to 500 MB
    Large = 2,
    /// 50 MB to 100 MB
    Medium = 3,
}

impl SizeBucket {
    pub fn from_bytes(bytes: u64) -> Option<Self> {
        if bytes >= 1_000_000_000 {
            Some(SizeBucket::Gigabytes)
        } else if bytes >= 500_000_000 {
            Some(SizeBucket::Huge)
        } else if bytes >= 100_000_000 {
            Some(SizeBucket::Large)
        } else if bytes >= 50_000_000 {
            Some(SizeBucket::Medium)
        } else {
            None
        }
    }

    pub fn display_name(&self) -> &'static str {
        match self {
            SizeBucket::Gigabytes => "Gigabytes (> 1 GB)",
            SizeBucket::Huge => "Huge (500 MB – 1 GB)",
            SizeBucket::Large => "Large (100 – 500 MB)",
            SizeBucket::Medium => "Medium (50 – 100 MB)",
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct MatrixCell {
    pub age_idx: u32,
    pub size_idx: u32,
    pub age_label: String,
    pub size_label: String,
    pub file_count: u32,
    pub total_bytes: u64,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct LargeOldFile {
    pub path: String,
    pub name: String,
    pub size_bytes: u64,
    pub modified_secs: u64,
    pub category_name: String,
    pub color_hex: String,
    pub age_label: String,
    pub age_idx: u32,
    pub size_idx: u32,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct LargeOldMatrixSummary {
    pub total_files: u32,
    pub total_bytes: u64,
    pub cells: Vec<MatrixCell>,
    pub files: Vec<LargeOldFile>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DuplicateFile {
    pub path: String,
    pub name: String,
    pub size_bytes: u64,
    pub modified_secs: u64,
    pub category_name: String,
    pub color_hex: String,
    pub is_original: bool,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DuplicateGroup {
    pub group_id: String,
    pub hash_hex: String,
    pub size_bytes: u64,
    pub total_wasted_bytes: u64,
    pub file_count: u32,
    pub files: Vec<DuplicateFile>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DuplicateSummary {
    pub total_duplicate_files: u32,
    pub total_duplicate_groups: u32,
    pub total_wasted_bytes: u64,
    pub groups: Vec<DuplicateGroup>,
}
