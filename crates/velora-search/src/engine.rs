use crate::matcher::{contains_ignore_case_ascii, has_extension};
use crate::query::{ComparisonOp, DateConstraint, SearchQuery, SizeConstraint};
use rayon::prelude::*;
use std::time::Instant;
use velora_index::{FileRecord, VolumeIndex};

#[derive(Debug, Clone)]
pub struct SearchHit {
    pub record_index: usize,
    pub score: u32,
}

#[derive(Debug, Clone)]
pub struct SearchReport {
    pub hits: Vec<SearchHit>,
    pub total_matched: usize,
    pub duration_micros: u128,
}

pub struct SearchEngine;

impl SearchEngine {
    /// Executes search across volume records, with optional previous candidates for incremental narrowing.
    pub fn search(
        volume: &VolumeIndex,
        query: &SearchQuery,
        previous_candidates: Option<&[usize]>,
        max_results: usize,
    ) -> SearchReport {
        let start = Instant::now();

        let evaluate_record = |idx: usize, record: &FileRecord| -> Option<SearchHit> {
            if record.is_deleted() {
                return None;
            }

            // Type filters
            if query.is_dir_only && !record.is_dir() {
                return None;
            }
            if query.is_file_only && record.is_dir() {
                return None;
            }

            // Size constraints
            for sc in &query.size_constraints {
                if !matches_size(record.size, sc) {
                    return None;
                }
            }

            // Date constraints
            for dc in &query.date_constraints {
                if !matches_date(record.modified_secs, dc) {
                    return None;
                }
            }

            let file_name = volume.get_file_name(record);

            // Extension filters
            if !has_extension(file_name, &query.extensions) {
                return None;
            }

            // Negated terms
            for neg in &query.negated_terms {
                if contains_ignore_case_ascii(file_name, neg) {
                    return None;
                }
            }

            // Required positive terms
            let mut score = 100u32;
            for term in &query.terms {
                if !contains_ignore_case_ascii(file_name, term) {
                    return None;
                }
                // Bonus score for exact match or prefix match
                if file_name.eq_ignore_ascii_case(term) {
                    score += 50;
                } else if file_name.to_ascii_lowercase().starts_with(term) {
                    score += 25;
                }
            }

            Some(SearchHit {
                record_index: idx,
                score,
            })
        };

        let hits: Vec<SearchHit> = if let Some(candidates) = previous_candidates {
            // Incremental search over prior subset
            candidates
                .par_iter()
                .filter_map(|&idx| {
                    let record = volume.records.get(idx)?;
                    evaluate_record(idx, record)
                })
                .collect()
        } else {
            // Full parallel sweep across all cores
            volume
                .records
                .par_iter()
                .enumerate()
                .filter_map(|(idx, record)| evaluate_record(idx, record))
                .collect()
        };

        let total_matched = hits.len();
        let mut sorted_hits = hits;
        // Sort highest score first
        sorted_hits.sort_unstable_by(|a, b| b.score.cmp(&a.score));

        if sorted_hits.len() > max_results {
            sorted_hits.truncate(max_results);
        }

        let elapsed = start.elapsed();

        SearchReport {
            hits: sorted_hits,
            total_matched,
            duration_micros: elapsed.as_micros(),
        }
    }
}

#[inline(always)]
fn matches_size(size: u64, sc: &SizeConstraint) -> bool {
    match sc.op {
        ComparisonOp::GreaterThan => size > sc.bytes,
        ComparisonOp::GreaterThanOrEqual => size >= sc.bytes,
        ComparisonOp::LessThan => size < sc.bytes,
        ComparisonOp::LessThanOrEqual => size <= sc.bytes,
        ComparisonOp::Equal => size == sc.bytes,
    }
}

#[inline(always)]
fn matches_date(timestamp: u64, dc: &DateConstraint) -> bool {
    match dc.op {
        ComparisonOp::GreaterThan => timestamp > dc.timestamp_secs,
        ComparisonOp::GreaterThanOrEqual => timestamp >= dc.timestamp_secs,
        ComparisonOp::LessThan => timestamp < dc.timestamp_secs,
        ComparisonOp::LessThanOrEqual => timestamp <= dc.timestamp_secs,
        ComparisonOp::Equal => timestamp == dc.timestamp_secs,
    }
}
