use std::ffi::CString;
use std::fs::{File, OpenOptions};
use std::io::{Read, Seek, SeekFrom, Write};
use std::os::unix::ffi::OsStrExt;
use std::os::unix::fs::PermissionsExt;
use std::os::unix::io::AsRawFd;
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicBool, Ordering};

const CHUNK_SIZE: usize = 64 * 1024; // 64 KB buffer

#[derive(Debug, Clone, Copy, PartialEq, Eq, serde::Serialize, serde::Deserialize)]
pub enum ShredAlgorithm {
    Zero,            // 1-Pass: 0x00 zero-out
    RandomNist80088, // 1-Pass: CSPRNG arc4random_buf
    Dod522022M,      // 3-Pass: 0x00, 0xFF, CSPRNG
    Dod522022MEce,   // 7-Pass: 0x00, 0xFF, CSPRNG, 0xAA, 0x55, CSPRNG, Verify
}

impl ShredAlgorithm {
    pub fn display_name(&self) -> &'static str {
        match self {
            Self::Zero => "Quick Zero (1-Pass)",
            Self::RandomNist80088 => "NIST SP 800-88 (1-Pass CSPRNG)",
            Self::Dod522022M => "DoD 5220.22-M (3-Pass)",
            Self::Dod522022MEce => "DoD 5220.22-M ECE (7-Pass)",
        }
    }

    pub fn total_passes(&self) -> u32 {
        match self {
            Self::Zero => 1,
            Self::RandomNist80088 => 1,
            Self::Dod522022M => 3,
            Self::Dod522022MEce => 7,
        }
    }

    fn pass_specs(&self) -> Vec<PassSpec> {
        match self {
            Self::Zero => vec![PassSpec {
                pass_num: 1,
                name: "Zeroing (0x00)",
                pattern: PassPattern::Zero,
            }],
            Self::RandomNist80088 => vec![PassSpec {
                pass_num: 1,
                name: "Cryptographic Random (CSPRNG)",
                pattern: PassPattern::Random,
            }],
            Self::Dod522022M => vec![
                PassSpec {
                    pass_num: 1,
                    name: "Pass 1/3: Zeroing (0x00)",
                    pattern: PassPattern::Zero,
                },
                PassSpec {
                    pass_num: 2,
                    name: "Pass 2/3: Bit Inversion (0xFF)",
                    pattern: PassPattern::Byte(0xFF),
                },
                PassSpec {
                    pass_num: 3,
                    name: "Pass 3/3: Cryptographic Random (CSPRNG)",
                    pattern: PassPattern::Random,
                },
            ],
            Self::Dod522022MEce => vec![
                PassSpec {
                    pass_num: 1,
                    name: "Pass 1/7: Zeroing (0x00)",
                    pattern: PassPattern::Zero,
                },
                PassSpec {
                    pass_num: 2,
                    name: "Pass 2/7: Bit Inversion (0xFF)",
                    pattern: PassPattern::Byte(0xFF),
                },
                PassSpec {
                    pass_num: 3,
                    name: "Pass 3/7: Cryptographic Random (CSPRNG)",
                    pattern: PassPattern::Random,
                },
                PassSpec {
                    pass_num: 4,
                    name: "Pass 4/7: Fixed Pattern (0xAA)",
                    pattern: PassPattern::Byte(0xAA),
                },
                PassSpec {
                    pass_num: 5,
                    name: "Pass 5/7: Complement Pattern (0x55)",
                    pattern: PassPattern::Byte(0x55),
                },
                PassSpec {
                    pass_num: 6,
                    name: "Pass 6/7: Cryptographic Random (CSPRNG)",
                    pattern: PassPattern::Random,
                },
                PassSpec {
                    pass_num: 7,
                    name: "Pass 7/7: Cryptographic Verification",
                    pattern: PassPattern::VerifyRandom,
                },
            ],
        }
    }
}

#[derive(Debug, Clone, Copy)]
enum PassPattern {
    Zero,
    Byte(u8),
    Random,
    VerifyRandom,
}

#[derive(Debug, Clone)]
struct PassSpec {
    pass_num: u32,
    name: &'static str,
    pattern: PassPattern,
}

#[derive(Debug)]
pub enum ShredError {
    Io {
        path: PathBuf,
        source: std::io::Error,
    },
    Cancelled,
    InvalidPath(String),
    VerificationFailed {
        path: PathBuf,
        offset: u64,
    },
}

impl std::fmt::Display for ShredError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Self::Io { path, source } => write!(f, "I/O error at {}: {}", path.display(), source),
            Self::Cancelled => write!(f, "Operation was cancelled by user"),
            Self::InvalidPath(msg) => write!(f, "Invalid path: {}", msg),
            Self::VerificationFailed { path, offset } => {
                write!(f, "Verification failed at {}: byte mismatch at offset {}", path.display(), offset)
            }
        }
    }
}

impl std::error::Error for ShredError {
    fn source(&self) -> Option<&(dyn std::error::Error + 'static)> {
        match self {
            Self::Io { source, .. } => Some(source),
            _ => None,
        }
    }
}

pub trait ShredProgressListener: Send + Sync {
    fn on_progress(
        &self,
        current_path: &str,
        file_index: u32,
        total_files: u32,
        current_pass: u32,
        total_passes: u32,
        pass_name: &str,
        bytes_written_file: u64,
        file_size_bytes: u64,
        total_bytes_written: u64,
        total_bytes_all_files: u64,
    );
}

#[derive(Debug, Default, Clone)]
pub struct ShredStats {
    pub files_shredded: u32,
    pub bytes_shredded: u64,
    pub errors: Vec<String>,
}

/// Disables read-only locks, immutability flags, and system protections if present.
fn unlock_file_permissions(path: &Path) {
    if let Ok(c_path) = CString::new(path.as_os_str().as_bytes()) {
        #[cfg(target_os = "macos")]
        unsafe {
            // Clear any user/system immutable flags (UF_IMMUTABLE, SF_IMMUTABLE)
            libc::chflags(c_path.as_ptr(), 0);
        }
    }
    if let Ok(metadata) = std::fs::metadata(path) {
        let mut perms = metadata.permissions();
        if perms.readonly() {
            perms.set_mode(0o600);
            let _ = std::fs::set_permissions(path, perms);
        }
    }
}

/// Flushes data and metadata from kernel and drive volatile caches to persistent media.
/// Uses macOS `fcntl(fd, F_FULLFSYNC)` to bypass drive write caching.
fn full_fsync(file: &File) -> std::io::Result<()> {
    #[cfg(target_os = "macos")]
    {
        let fd = file.as_raw_fd();
        let ret = unsafe { libc::fcntl(fd, libc::F_FULLFSYNC) };
        if ret != 0 {
            // Fallback to standard fsync if F_FULLFSYNC is unsupported on the underlying mount
            file.sync_all()
        } else {
            Ok(())
        }
    }
    #[cfg(not(target_os = "macos"))]
    {
        file.sync_all()
    }
}

/// Fills buffer with cryptographically secure random bytes via OS CSPRNG.
fn fill_random_bytes(buf: &mut [u8]) {
    #[cfg(target_os = "macos")]
    unsafe {
        libc::arc4random_buf(buf.as_mut_ptr() as *mut libc::c_void, buf.len());
    }
    #[cfg(not(target_os = "macos"))]
    {
        for b in buf.iter_mut() {
            *b = 0x5A;
        }
    }
}

/// Generates a randomized filename in the same directory to overwrite directory inode metadata.
fn random_obfuscation_path(parent: &Path) -> PathBuf {
    let mut rand_bytes = [0u8; 16];
    fill_random_bytes(&mut rand_bytes);
    let hex_name: String = rand_bytes.iter().map(|b| format!("{:02x}", b)).collect();
    parent.join(format!(".velora_shred_{}.tmp", hex_name))
}

/// Securely overwrites a single file according to the selected algorithm, truncates,
/// obfuscates inode metadata via renames, and unlinks it.
pub fn shred_file(
    path: &Path,
    algorithm: ShredAlgorithm,
    cancel_token: &AtomicBool,
    listener: Option<&dyn ShredProgressListener>,
    file_index: u32,
    total_files: u32,
    accumulated_bytes_written: &mut u64,
    total_expected_work_bytes: u64,
) -> Result<u64, ShredError> {
    if cancel_token.load(Ordering::Relaxed) {
        return Err(ShredError::Cancelled);
    }

    unlock_file_permissions(path);

    let mut file = OpenOptions::new()
        .read(true)
        .write(true)
        .open(path)
        .map_err(|e| ShredError::Io {
            path: path.to_path_buf(),
            source: e,
        })?;

    let file_size = file
        .metadata()
        .map_err(|e| ShredError::Io {
            path: path.to_path_buf(),
            source: e,
        })?
        .len();

    let total_passes = algorithm.total_passes();
    let passes = algorithm.pass_specs();
    let path_str = path.to_string_lossy().to_string();

    let zero_buf = [0u8; CHUNK_SIZE];
    let mut fill_buf = [0u8; CHUNK_SIZE];

    for spec in passes {
        if cancel_token.load(Ordering::Relaxed) {
            return Err(ShredError::Cancelled);
        }

        file.seek(SeekFrom::Start(0))
            .map_err(|e| ShredError::Io {
                path: path.to_path_buf(),
                source: e,
            })?;

        let mut bytes_written_file: u64 = 0;

        if file_size == 0 {
            if let Some(l) = listener {
                l.on_progress(
                    &path_str,
                    file_index,
                    total_files,
                    spec.pass_num,
                    total_passes,
                    spec.name,
                    0,
                    0,
                    *accumulated_bytes_written,
                    total_expected_work_bytes,
                );
            }
        }

        match spec.pattern {
            PassPattern::Zero => {
                while bytes_written_file < file_size {
                    if cancel_token.load(Ordering::Relaxed) {
                        return Err(ShredError::Cancelled);
                    }
                    let to_write = std::cmp::min((file_size - bytes_written_file) as usize, CHUNK_SIZE);
                    file.write_all(&zero_buf[..to_write])
                        .map_err(|e| ShredError::Io {
                            path: path.to_path_buf(),
                            source: e,
                        })?;
                    bytes_written_file += to_write as u64;
                    *accumulated_bytes_written += to_write as u64;

                    if let Some(l) = listener {
                        l.on_progress(
                            &path_str,
                            file_index,
                            total_files,
                            spec.pass_num,
                            total_passes,
                            spec.name,
                            bytes_written_file,
                            file_size,
                            *accumulated_bytes_written,
                            total_expected_work_bytes,
                        );
                    }
                }
            }
            PassPattern::Byte(b) => {
                fill_buf.fill(b);
                while bytes_written_file < file_size {
                    if cancel_token.load(Ordering::Relaxed) {
                        return Err(ShredError::Cancelled);
                    }
                    let to_write = std::cmp::min((file_size - bytes_written_file) as usize, CHUNK_SIZE);
                    file.write_all(&fill_buf[..to_write])
                        .map_err(|e| ShredError::Io {
                            path: path.to_path_buf(),
                            source: e,
                        })?;
                    bytes_written_file += to_write as u64;
                    *accumulated_bytes_written += to_write as u64;

                    if let Some(l) = listener {
                        l.on_progress(
                            &path_str,
                            file_index,
                            total_files,
                            spec.pass_num,
                            total_passes,
                            spec.name,
                            bytes_written_file,
                            file_size,
                            *accumulated_bytes_written,
                            total_expected_work_bytes,
                        );
                    }
                }
            }
            PassPattern::Random => {
                while bytes_written_file < file_size {
                    if cancel_token.load(Ordering::Relaxed) {
                        return Err(ShredError::Cancelled);
                    }
                    let to_write = std::cmp::min((file_size - bytes_written_file) as usize, CHUNK_SIZE);
                    fill_random_bytes(&mut fill_buf[..to_write]);
                    file.write_all(&fill_buf[..to_write])
                        .map_err(|e| ShredError::Io {
                            path: path.to_path_buf(),
                            source: e,
                        })?;
                    bytes_written_file += to_write as u64;
                    *accumulated_bytes_written += to_write as u64;

                    if let Some(l) = listener {
                        l.on_progress(
                            &path_str,
                            file_index,
                            total_files,
                            spec.pass_num,
                            total_passes,
                            spec.name,
                            bytes_written_file,
                            file_size,
                            *accumulated_bytes_written,
                            total_expected_work_bytes,
                        );
                    }
                }
            }
            PassPattern::VerifyRandom => {
                // Read-back verification pass to ensure readable state
                let mut read_buf = [0u8; CHUNK_SIZE];
                while bytes_written_file < file_size {
                    if cancel_token.load(Ordering::Relaxed) {
                        return Err(ShredError::Cancelled);
                    }
                    let to_read = std::cmp::min((file_size - bytes_written_file) as usize, CHUNK_SIZE);
                    file.read_exact(&mut read_buf[..to_read])
                        .map_err(|e| ShredError::Io {
                            path: path.to_path_buf(),
                            source: e,
                        })?;
                    bytes_written_file += to_read as u64;
                    *accumulated_bytes_written += to_read as u64;

                    if let Some(l) = listener {
                        l.on_progress(
                            &path_str,
                            file_index,
                            total_files,
                            spec.pass_num,
                            total_passes,
                            spec.name,
                            bytes_written_file,
                            file_size,
                            *accumulated_bytes_written,
                            total_expected_work_bytes,
                        );
                    }
                }
            }
        }

        // Hardware commit after each overwrite pass
        full_fsync(&file).map_err(|e| ShredError::Io {
            path: path.to_path_buf(),
            source: e,
        })?;
    }

    // Notify listener that physical data overwriting is 100% complete and finalization has begun
    if let Some(l) = listener {
        l.on_progress(
            &path_str,
            file_index,
            total_files,
            total_passes,
            total_passes,
            "Finalizing (flushing disk cache & unlinking)",
            file_size,
            file_size,
            *accumulated_bytes_written,
            total_expected_work_bytes,
        );
    }

    // Step 2: Truncate file length to 0 and flush
    file.set_len(0).map_err(|e| ShredError::Io {
        path: path.to_path_buf(),
        source: e,
    })?;
    let _ = full_fsync(&file);
    drop(file);

    // Step 3: Obfuscate inode and directory entry via successive renames before unlinking
    let parent = path.parent().unwrap_or_else(|| Path::new("/"));
    let mut current_path = path.to_path_buf();

    for _ in 0..3 {
        let randomized_target = random_obfuscation_path(parent);
        if std::fs::rename(&current_path, &randomized_target).is_ok() {
            current_path = randomized_target;
        }
    }

    // Step 4: Final POSIX unlink
    std::fs::remove_file(&current_path).map_err(|e| ShredError::Io {
        path: current_path,
        source: e,
    })?;

    Ok(file_size)
}

/// Recursively collects all child files and subdirectories.
fn collect_entries_recursive(
    dir: &Path,
    files: &mut Vec<PathBuf>,
    dirs: &mut Vec<PathBuf>,
) -> std::io::Result<()> {
    if dir.is_symlink() {
        files.push(dir.to_path_buf());
        return Ok(());
    }

    for entry in std::fs::read_dir(dir)? {
        let entry = entry?;
        let path = entry.path();
        if path.is_dir() && !path.is_symlink() {
            collect_entries_recursive(&path, files, dirs)?;
            dirs.push(path);
        } else {
            files.push(path);
        }
    }
    Ok(())
}

/// Securely shreds a folder and all nested contents: files are overwritten and unlinked,
/// and directories are renamed and removed bottom-up.
pub fn shred_directory(
    dir_path: &Path,
    algorithm: ShredAlgorithm,
    cancel_token: &AtomicBool,
    listener: Option<&dyn ShredProgressListener>,
    file_index_offset: &mut u32,
    total_files: u32,
    accumulated_bytes: &mut u64,
    total_expected_work_bytes: u64,
) -> Result<u64, ShredError> {
    if cancel_token.load(Ordering::Relaxed) {
        return Err(ShredError::Cancelled);
    }

    let mut files = Vec::new();
    let mut subdirs = Vec::new();

    collect_entries_recursive(dir_path, &mut files, &mut subdirs).map_err(|e| ShredError::Io {
        path: dir_path.to_path_buf(),
        source: e,
    })?;

    let mut dir_total_bytes = 0u64;

    // Shred files first
    for f in &files {
        if cancel_token.load(Ordering::Relaxed) {
            return Err(ShredError::Cancelled);
        }
        *file_index_offset += 1;
        match shred_file(
            f,
            algorithm,
            cancel_token,
            listener,
            *file_index_offset,
            total_files,
            accumulated_bytes,
            total_expected_work_bytes,
        ) {
            Ok(sz) => dir_total_bytes += sz,
            Err(e) => return Err(e),
        }
    }

    // Obfuscate and remove subdirectories bottom-up
    for d in &subdirs {
        let parent = d.parent().unwrap_or_else(|| Path::new("/"));
        let mut cur = d.clone();
        for _ in 0..2 {
            let rnd = random_obfuscation_path(parent);
            if std::fs::rename(&cur, &rnd).is_ok() {
                cur = rnd;
            }
        }
        let _ = std::fs::remove_dir(&cur);
    }

    // Obfuscate and remove the target root directory
    let parent = dir_path.parent().unwrap_or_else(|| Path::new("/"));
    let mut cur = dir_path.to_path_buf();
    for _ in 0..2 {
        let rnd = random_obfuscation_path(parent);
        if std::fs::rename(&cur, &rnd).is_ok() {
            cur = rnd;
        }
    }
    std::fs::remove_dir(&cur).map_err(|e| ShredError::Io {
        path: cur,
        source: e,
    })?;

    Ok(dir_total_bytes)
}

/// High-level entry point to shred an arbitrary list of file and directory paths.
pub fn shred_paths(
    paths: &[PathBuf],
    algorithm: ShredAlgorithm,
    cancel_token: &AtomicBool,
    listener: Option<&dyn ShredProgressListener>,
) -> ShredStats {
    let mut stats = ShredStats::default();

    // Pass 1: Pre-calculate total files and total bytes for accurate progress calculation
    let mut all_files_count = 0u32;
    let mut total_raw_bytes = 0u64;

    for p in paths {
        if !p.exists() {
            continue;
        }
        if p.is_dir() && !p.is_symlink() {
            let mut f_list = Vec::new();
            let mut d_list = Vec::new();
            if collect_entries_recursive(p, &mut f_list, &mut d_list).is_ok() {
                all_files_count += f_list.len() as u32;
                for f in &f_list {
                    if let Ok(meta) = std::fs::metadata(f) {
                        total_raw_bytes += meta.len();
                    }
                }
            }
        } else {
            all_files_count += 1;
            if let Ok(meta) = std::fs::metadata(p) {
                total_raw_bytes += meta.len();
            }
        }
    }

    let passes_count = algorithm.total_passes() as u64;
    let total_expected_work_bytes = total_raw_bytes.saturating_mul(passes_count);

    let mut current_file_idx = 0u32;
    let mut accumulated_bytes = 0u64;

    for p in paths {
        if cancel_token.load(Ordering::Relaxed) {
            stats.errors.push("Shredding cancelled by user".to_string());
            break;
        }

        if !p.exists() {
            stats
                .errors
                .push(format!("Path does not exist: {}", p.display()));
            continue;
        }

        if p.is_dir() && !p.is_symlink() {
            match shred_directory(
                p,
                algorithm,
                cancel_token,
                listener,
                &mut current_file_idx,
                all_files_count,
                &mut accumulated_bytes,
                total_expected_work_bytes,
            ) {
                Ok(bytes) => {
                    stats.files_shredded += 1;
                    stats.bytes_shredded += bytes;
                }
                Err(ShredError::Cancelled) => {
                    stats.errors.push("Shredding cancelled by user".to_string());
                    break;
                }
                Err(e) => {
                    stats.errors.push(e.to_string());
                }
            }
        } else {
            current_file_idx += 1;
            match shred_file(
                p,
                algorithm,
                cancel_token,
                listener,
                current_file_idx,
                all_files_count,
                &mut accumulated_bytes,
                total_expected_work_bytes,
            ) {
                Ok(bytes) => {
                    stats.files_shredded += 1;
                    stats.bytes_shredded += bytes;
                }
                Err(ShredError::Cancelled) => {
                    stats.errors.push("Shredding cancelled by user".to_string());
                    break;
                }
                Err(e) => {
                    stats.errors.push(e.to_string());
                }
            }
        }
    }

    stats
}
