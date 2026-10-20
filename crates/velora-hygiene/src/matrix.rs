use crate::model::{AgeBucket, LargeOldFile, LargeOldMatrixSummary, MatrixCell, SizeBucket};
use std::time::{SystemTime, UNIX_EPOCH};
use velora_analyzer::CategoryKind;
use velora_index::VolumeIndex;

pub struct LargeOldFilesMatrix;

impl LargeOldFilesMatrix {
    /// Computes the 2D Temporal × Size matrix from the in-memory `VolumeIndex`.
    /// Operates entirely in RAM with zero physical disk I/O.
    pub fn compute(volume: &VolumeIndex) -> LargeOldMatrixSummary {
        let now_secs = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap_or_default()
            .as_secs();

        // Initialize 4x4 matrix grid (16 cells)
        let mut cell_counts = [0u32; 16];
        let mut cell_bytes = [0u64; 16];

        let mut matched_files = Vec::new();
        let mut total_files = 0u32;
        let mut total_bytes = 0u64;

        for record in &volume.records {
            if record.is_deleted() || record.is_dir() {
                continue;
            }

            // Only consider files >= 50 MB
            let size_bucket = match SizeBucket::from_bytes(record.size) {
                Some(sb) => sb,
                None => continue,
            };

            let age_secs = now_secs.saturating_sub(record.modified_secs);
            let age_bucket = AgeBucket::from_age_secs(age_secs);

            let age_idx = age_bucket as u32;
            let size_idx = size_bucket as u32;
            let cell_idx = (age_idx * 4 + size_idx) as usize;

            cell_counts[cell_idx] += 1;
            cell_bytes[cell_idx] += record.size;
            total_files += 1;
            total_bytes += record.size;

            let file_name = volume.get_file_name(record);
            let category = CategoryKind::classify(file_name, false);

            let age_label = Self::format_relative_age(age_secs);
            let full_path = volume.resolve_full_path(record);

            matched_files.push(LargeOldFile {
                path: full_path,
                name: file_name.to_string(),
                size_bytes: record.size,
                modified_secs: record.modified_secs,
                category_name: category.display_name().to_string(),
                color_hex: category.color_hex().to_string(),
                age_label,
                age_idx,
                size_idx,
            });
        }

        // Sort files descending by size
        matched_files.sort_unstable_by(|a, b| b.size_bytes.cmp(&a.size_bytes));
        if matched_files.len() > 1000 {
            matched_files.truncate(1000);
        }

        // Build 16 MatrixCell records
        let mut cells = Vec::with_capacity(16);
        for age_i in 0..4u32 {
            for size_i in 0..4u32 {
                let idx = (age_i * 4 + size_i) as usize;
                let age_b = match age_i {
                    0 => AgeBucket::Recent,
                    1 => AgeBucket::Months1To6,
                    2 => AgeBucket::Months6To12,
                    _ => AgeBucket::Ancient,
                };
                let size_b = match size_i {
                    0 => SizeBucket::Gigabytes,
                    1 => SizeBucket::Huge,
                    2 => SizeBucket::Large,
                    _ => SizeBucket::Medium,
                };

                cells.push(MatrixCell {
                    age_idx: age_i,
                    size_idx: size_i,
                    age_label: age_b.display_name().to_string(),
                    size_label: size_b.display_name().to_string(),
                    file_count: cell_counts[idx],
                    total_bytes: cell_bytes[idx],
                });
            }
        }

        LargeOldMatrixSummary {
            total_files,
            total_bytes,
            cells,
            files: matched_files,
        }
    }

    fn format_relative_age(age_secs: u64) -> String {
        const DAY: u64 = 86_400;
        const MONTH: u64 = 30 * DAY;
        const YEAR: u64 = 365 * DAY;

        if age_secs < DAY {
            "Today".to_string()
        } else if age_secs < 2 * DAY {
            "Yesterday".to_string()
        } else if age_secs < MONTH {
            format!("{}d ago", age_secs / DAY)
        } else if age_secs < YEAR {
            let months = (age_secs / MONTH).max(1);
            format!("{}mo ago", months)
        } else {
            let years = (age_secs / YEAR).max(1);
            format!("{}yr ago", years)
        }
    }
}
