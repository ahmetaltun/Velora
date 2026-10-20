use crate::model::{DuplicateFile, DuplicateGroup, DuplicateSummary};
use rayon::prelude::*;
use std::collections::HashMap;
use std::fs::File;
use std::io::{Read, Seek, SeekFrom};
use std::path::Path;
use velora_analyzer::CategoryKind;
use velora_index::VolumeIndex;

// CommonCrypto C FFI for hardware-accelerated SHA-256 on macOS
#[repr(C)]
#[derive(Clone, Copy)]
pub struct CC_SHA256_CTX {
    pub count: [u32; 2],
    pub hash: [u32; 8],
    pub wbuf: [u32; 16],
}

extern "C" {
    fn CC_SHA256_Init(c: *mut CC_SHA256_CTX) -> i32;
    fn CC_SHA256_Update(c: *mut CC_SHA256_CTX, data: *const u8, len: u32) -> i32;
    fn CC_SHA256_Final(md: *mut u8, c: *mut CC_SHA256_CTX) -> i32;
}

pub struct Sha256 {
    ctx: CC_SHA256_CTX,
}

impl Sha256 {
    pub fn new() -> Self {
        let mut ctx = std::mem::MaybeUninit::uninit();
        unsafe {
            CC_SHA256_Init(ctx.as_mut_ptr());
            Self {
                ctx: ctx.assume_init(),
            }
        }
    }

    pub fn update(&mut self, data: &[u8]) {
        unsafe {
            CC_SHA256_Update(&mut self.ctx, data.as_ptr(), data.len() as u32);
        }
    }

    pub fn finalize(mut self) -> [u8; 32] {
        let mut out = [0u8; 32];
        unsafe {
            CC_SHA256_Final(out.as_mut_ptr(), &mut self.ctx);
        }
        out
    }

    pub fn digest(data: &[u8]) -> [u8; 32] {
        let mut hasher = Self::new();
        hasher.update(data);
        hasher.finalize()
    }

    pub fn to_hex(bytes: &[u8; 32]) -> String {
        let mut s = String::with_capacity(64);
        for b in bytes {
            use std::fmt::Write;
            let _ = write!(s, "{:02x}", b);
        }
        s
    }
}

pub struct DuplicateFinder;

impl DuplicateFinder {
    /// Discovers exact byte-level duplicates using a 3-tier progressive zero-thrash pipeline.
    /// Operates on `VolumeIndex` first to eliminate non-colliding files without disk reads.
    pub fn find_duplicates(volume: &VolumeIndex, min_size_bytes: u64) -> DuplicateSummary {
        // TIER 1: In-memory exact byte size grouping
        // Files with unique sizes cannot be duplicates and are discarded with 0 disk I/O.
        let mut size_buckets: HashMap<u64, Vec<usize>> = HashMap::new();

        for (idx, record) in volume.records.iter().enumerate() {
            if record.is_deleted() || record.is_dir() || record.size < min_size_bytes {
                continue;
            }
            size_buckets.entry(record.size).or_default().push(idx);
        }

        // Retain only sizes with 2 or more files
        let candidate_size_groups: Vec<(u64, Vec<usize>)> = size_buckets
            .into_iter()
            .filter(|(_, indices)| indices.len() >= 2)
            .collect();

        // TIER 2: Parallel multi-point sparse probe (< 12KB disk I/O)
        // Samples 4KB prefix, 4KB suffix, and 4KB midpoint to eliminate non-duplicates early.
        let candidate_sparse_groups: Vec<Vec<(usize, String, [u8; 32])>> = candidate_size_groups
            .into_par_iter()
            .flat_map(|(size, indices)| {
                let mut sparse_buckets: HashMap<[u8; 32], Vec<(usize, String, [u8; 32])>> = HashMap::new();

                for idx in indices {
                    let record = &volume.records[idx];
                    let path = volume.resolve_full_path(record);

                    if let Some(sparse_hash) = Self::probe_sparse_fingerprint(Path::new(&path), size) {
                        sparse_buckets
                            .entry(sparse_hash)
                            .or_default()
                            .push((idx, path, sparse_hash));
                    }
                }

                sparse_buckets
                    .into_values()
                    .filter(|group| group.len() >= 2)
                    .collect::<Vec<_>>()
            })
            .collect();

        // TIER 3: Lockstep early-abort parallel byte comparison & simultaneous hashing
        // Streams candidate files in lockstep 64KB chunks, aborting immediately on the first byte mismatch.
        // Small files (<= 4KB) reuse the sparse probe hash with zero additional disk reads.
        let confirmed_groups: Vec<DuplicateGroup> = candidate_sparse_groups
            .into_par_iter()
            .filter_map(|candidates| {
                if candidates.len() < 2 {
                    return None;
                }

                let first_idx = candidates[0].0;
                let single_size = volume.records[first_idx].size;
                let mut matched_groups: Vec<([u8; 32], Vec<(usize, String)>)> = Vec::new();

                if single_size <= 4096 {
                    // Small files (<= 4KB): Sparse fingerprint was already 100% full content
                    let hash = candidates[0].2;
                    let files: Vec<(usize, String)> = candidates
                        .into_iter()
                        .map(|(idx, path, _)| (idx, path))
                        .collect();
                    matched_groups.push((hash, files));
                } else if candidates.len() == 2 {
                    // Fast path for 2 files (>95% of collisions): single lockstep early-abort stream
                    let (idx0, path0, _) = &candidates[0];
                    let (idx1, path1, _) = &candidates[1];

                    if let Some(hash) = Self::compare_and_hash_pair(Path::new(path0), Path::new(path1)) {
                        matched_groups.push((hash, vec![(*idx0, path0.clone()), (*idx1, path1.clone())]));
                    }
                } else {
                    // Multi-candidate (N >= 3) partition with early-abort streaming
                    for (idx, path, _) in candidates {
                        let mut found_group = false;
                        for (hash, members) in &mut matched_groups {
                            let ref_path = &members[0].1;
                            if let Some(cmp_hash) = Self::compare_and_hash_pair(Path::new(&path), Path::new(ref_path)) {
                                *hash = cmp_hash;
                                members.push((idx, path.clone()));
                                found_group = true;
                                break;
                            }
                        }
                        if !found_group {
                            matched_groups.push(([0u8; 32], vec![(idx, path)]));
                        }
                    }
                }

                let mut local_groups = Vec::new();
                for (hash, matched) in matched_groups {
                    if matched.len() < 2 {
                        continue;
                    }

                    let hash_hex = Sha256::to_hex(&hash);
                    let wasted = single_size * (matched.len() as u64 - 1);

                    // Build duplicate file items and sort by modified_secs ascending (oldest is original)
                    let mut files: Vec<DuplicateFile> = matched
                        .into_iter()
                        .map(|(idx, path)| {
                            let rec = &volume.records[idx];
                            let name = volume.get_file_name(rec).to_string();
                            let cat = CategoryKind::classify(&name, false);
                            DuplicateFile {
                                path,
                                name,
                                size_bytes: rec.size,
                                modified_secs: rec.modified_secs,
                                category_name: cat.display_name().to_string(),
                                color_hex: cat.color_hex().to_string(),
                                is_original: false,
                            }
                        })
                        .collect();

                    files.sort_unstable_by_key(|f| f.modified_secs);
                    if let Some(first) = files.first_mut() {
                        first.is_original = true; // Mark the oldest file as original
                    }

                    local_groups.push(DuplicateGroup {
                        group_id: hash_hex.clone(),
                        hash_hex,
                        size_bytes: single_size,
                        total_wasted_bytes: wasted,
                        file_count: files.len() as u32,
                        files,
                    });
                }

                if local_groups.is_empty() {
                    None
                } else {
                    Some(local_groups)
                }
            })
            .flatten()
            .collect();

        // Aggregate summary metrics
        let mut total_duplicate_files = 0u32;
        let mut total_wasted_bytes = 0u64;

        let mut groups = confirmed_groups;
        // Sort groups by total wasted space descending (highest impact first)
        groups.sort_unstable_by(|a, b| b.total_wasted_bytes.cmp(&a.total_wasted_bytes));

        for g in &groups {
            total_duplicate_files += g.file_count;
            total_wasted_bytes += g.total_wasted_bytes;
        }

        DuplicateSummary {
            total_duplicate_files,
            total_duplicate_groups: groups.len() as u32,
            total_wasted_bytes,
            groups,
        }
    }

    /// Computes a multi-point sparse fingerprint (under 12KB disk I/O):
    /// - Files <= 4KB: Reads up to 4096 bytes (full content hash).
    /// - Files > 4KB: Reads 4KB prefix, 4KB suffix, and 4KB midpoint (if > 64KB).
    fn probe_sparse_fingerprint(path: &Path, file_size: u64) -> Option<[u8; 32]> {
        let mut file = File::open(path).ok()?;
        let mut hasher = Sha256::new();
        let mut buffer = [0u8; 4096];

        // 1. Prefix probe (first 4KB)
        let bytes_read = file.read(&mut buffer).ok()?;
        if bytes_read == 0 {
            return None;
        }
        hasher.update(&buffer[..bytes_read]);

        if file_size <= 4096 {
            return Some(hasher.finalize());
        }

        // 2. Suffix probe (last 4KB via seek)
        if file_size > 8192 {
            if file.seek(SeekFrom::End(-4096)).is_ok() {
                if let Ok(n) = file.read(&mut buffer) {
                    if n > 0 {
                        hasher.update(&buffer[..n]);
                    }
                }
            }
        }

        // 3. Midpoint probe (4KB around center for files > 64KB)
        if file_size > 65536 {
            let mid_offset = (file_size / 2).saturating_sub(2048);
            if file.seek(SeekFrom::Start(mid_offset)).is_ok() {
                if let Ok(n) = file.read(&mut buffer) {
                    if n > 0 {
                        hasher.update(&buffer[..n]);
                    }
                }
            }
        }

        Some(hasher.finalize())
    }

    /// Streams two files in lockstep 64KB chunks:
    /// - Computes SHA-256 hash incrementally as chunks match.
    /// - Aborts immediately on the very first mismatched byte without reading the rest of the files.
    fn compare_and_hash_pair(path_a: &Path, path_b: &Path) -> Option<[u8; 32]> {
        let mut file_a = File::open(path_a).ok()?;
        let mut file_b = File::open(path_b).ok()?;

        let mut hasher = Sha256::new();
        let mut buf_a = [0u8; 65536];
        let mut buf_b = [0u8; 65536];

        loop {
            let n_a = match file_a.read(&mut buf_a) {
                Ok(n) => n,
                Err(_) => return None,
            };
            let n_b = match file_b.read(&mut buf_b) {
                Ok(n) => n,
                Err(_) => return None,
            };

            // If bytes read differ, files differ
            if n_a != n_b {
                return None;
            }

            // End of both files reached cleanly and identically
            if n_a == 0 {
                break;
            }

            // Early abort if chunk differs
            if buf_a[..n_a] != buf_b[..n_b] {
                return None;
            }

            // Accumulate hash over verified matching chunk
            hasher.update(&buf_a[..n_a]);
        }

        Some(hasher.finalize())
    }

    /// Streams entire file in 64KB buffers and computes the cryptographic SHA-256 hash.
    #[allow(dead_code)]
    fn compute_full_file_hash(path: &Path) -> Option<[u8; 32]> {
        let mut file = File::open(path).ok()?;
        let mut hasher = Sha256::new();
        let mut buffer = [0u8; 65536];

        loop {
            match file.read(&mut buffer) {
                Ok(0) => break,
                Ok(n) => hasher.update(&buffer[..n]),
                Err(_) => return None,
            }
        }

        Some(hasher.finalize())
    }
}
