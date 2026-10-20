use crate::model::{DuplicateFile, DuplicateGroup, DuplicateSummary};
use rayon::prelude::*;
use std::collections::HashMap;
use std::fs::File;
use std::io::Read;
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

        // TIER 2: 4KB prefix probe
        // Reads only the first 4KB of files in candidate size groups to eliminate mismatches early.
        let mut prefix_groups: HashMap<(u64, [u8; 32]), Vec<(usize, String)>> = HashMap::new();

        for (size, indices) in candidate_size_groups {
            for idx in indices {
                let record = &volume.records[idx];
                let path = volume.resolve_full_path(record);

                if let Some(prefix_hash) = Self::probe_prefix_hash(Path::new(&path)) {
                    prefix_groups
                        .entry((size, prefix_hash))
                        .or_default()
                        .push((idx, path));
                }
            }
        }

        // Retain only prefix buckets with 2 or more files
        let candidate_prefix_groups: Vec<Vec<(usize, String)>> = prefix_groups
            .into_values()
            .filter(|group| group.len() >= 2)
            .collect();

        // TIER 3: Parallel full-file cryptographic SHA-256 hash
        // Only streams full contents for candidates whose size AND prefix collided.
        let confirmed_groups: Vec<DuplicateGroup> = candidate_prefix_groups
            .into_par_iter()
            .filter_map(|candidates| {
                let mut hash_map: HashMap<[u8; 32], Vec<(usize, String)>> = HashMap::new();

                for (idx, path) in candidates {
                    if let Some(full_hash) = Self::compute_full_file_hash(Path::new(&path)) {
                        hash_map.entry(full_hash).or_default().push((idx, path));
                    }
                }

                let mut local_groups = Vec::new();
                for (hash, matched) in hash_map {
                    if matched.len() < 2 {
                        continue;
                    }

                    let hash_hex = Sha256::to_hex(&hash);
                    let single_size = volume.records[matched[0].0].size;
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

    /// Reads up to 4096 bytes and computes the prefix hash.
    fn probe_prefix_hash(path: &Path) -> Option<[u8; 32]> {
        let mut file = File::open(path).ok()?;
        let mut buffer = [0u8; 4096];
        let bytes_read = file.read(&mut buffer).ok()?;
        if bytes_read == 0 {
            return None;
        }
        Some(Sha256::digest(&buffer[..bytes_read]))
    }

    /// Streams entire file in 64KB buffers and computes the cryptographic SHA-256 hash.
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
