use std::path::{Path, PathBuf};
use velora_index::VolumeIndex;

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum CandidateKind {
    LaunchAgentPlist,
    LaunchDaemonPlist,
    ShellProfileHook,
    SuspiciousDoubleExtension,
    SuspiciousHiddenExecutable,
}

#[derive(Debug, Clone)]
pub struct CandidateFile {
    pub path: PathBuf,
    pub name: String,
    pub size: u64,
    pub modified_secs: u64,
    pub kind: CandidateKind,
}

pub struct SecurityTriage;

impl SecurityTriage {
    /// Ingests `VolumeIndex` entirely from memory (catalog.bin) and extracts high-risk candidate files.
    /// Operates with 0 physical disk I/O in single-digit milliseconds.
    pub fn triage_candidates(volume: &VolumeIndex, home_path: &Path) -> Vec<CandidateFile> {
        let mut candidates = Vec::with_capacity(256);

        // 1. Identify key Persistence Directory IDs in memory
        let user_launch_agents_dir = home_path.join("Library/LaunchAgents");
        let system_launch_agents_dir = Path::new("/Library/LaunchAgents");
        let system_launch_daemons_dir = Path::new("/Library/LaunchDaemons");

        let user_la_id = volume.find_dir_by_path(&user_launch_agents_dir);
        let sys_la_id = volume.find_dir_by_path(system_launch_agents_dir);
        let sys_ld_id = volume.find_dir_by_path(system_launch_daemons_dir);

        // 2. Map home directory ID for shell rc files
        let home_dir_id = volume.find_dir_by_path(home_path);

        // 3. Scan records in memory
        for record in &volume.records {
            if record.is_deleted() || record.is_dir() {
                continue;
            }

            let name = volume.get_file_name(record);

            // A. Check LaunchAgents / LaunchDaemons
            if Some(record.parent_dir) == user_la_id || Some(record.parent_dir) == sys_la_id {
                if name.ends_with(".plist") {
                    let full_path = volume.resolve_full_path(record);
                    candidates.push(CandidateFile {
                        path: PathBuf::from(full_path),
                        name: name.to_string(),
                        size: record.size,
                        modified_secs: record.modified_secs,
                        kind: CandidateKind::LaunchAgentPlist,
                    });
                    continue;
                }
            } else if Some(record.parent_dir) == sys_ld_id {
                if name.ends_with(".plist") {
                    let full_path = volume.resolve_full_path(record);
                    candidates.push(CandidateFile {
                        path: PathBuf::from(full_path),
                        name: name.to_string(),
                        size: record.size,
                        modified_secs: record.modified_secs,
                        kind: CandidateKind::LaunchDaemonPlist,
                    });
                    continue;
                }
            }

            // B. Shell Profile Startup Files (~/.zshrc, ~/.bash_profile, etc.)
            if Some(record.parent_dir) == home_dir_id {
                if matches!(
                    name,
                    ".zshrc" | ".zshenv" | ".zprofile" | ".bash_profile" | ".bashrc" | ".profile"
                ) {
                    let full_path = volume.resolve_full_path(record);
                    candidates.push(CandidateFile {
                        path: PathBuf::from(full_path),
                        name: name.to_string(),
                        size: record.size,
                        modified_secs: record.modified_secs,
                        kind: CandidateKind::ShellProfileHook,
                    });
                    continue;
                }
            }

            // C. Deceptive Double Extensions (e.g. invoice.pdf.app, photo.png.command)
            if is_suspicious_double_extension(name) {
                let full_path = volume.resolve_full_path(record);
                candidates.push(CandidateFile {
                    path: PathBuf::from(full_path),
                    name: name.to_string(),
                    size: record.size,
                    modified_secs: record.modified_secs,
                    kind: CandidateKind::SuspiciousDoubleExtension,
                });
                continue;
            }

            // D. Suspicious Hidden Executable Scripts in User Space
            if name.starts_with('.') && (name.ends_with(".sh") || name.ends_with(".command") || name.ends_with(".py") || name.ends_with(".scpt")) {
                let full_path = volume.resolve_full_path(record);
                // Flag if residing in user writable locations like /tmp or ~/Library/Application Support
                if full_path.contains("/Library/Application Support/") || full_path.starts_with("/tmp/") || full_path.starts_with("/Users/Shared/") {
                    candidates.push(CandidateFile {
                        path: PathBuf::from(full_path),
                        name: name.to_string(),
                        size: record.size,
                        modified_secs: record.modified_secs,
                        kind: CandidateKind::SuspiciousHiddenExecutable,
                    });
                }
            }
        }

        candidates
    }
}

fn is_suspicious_double_extension(name: &str) -> bool {
    let lower = name.to_lowercase();
    let suspicious_tails = [".app", ".command", ".sh", ".scpt", ".applescript", ".action"];
    let deceptive_inners = [".pdf", ".jpg", ".jpeg", ".png", ".gif", ".mp4", ".mp3", ".doc", ".docx", ".xls", ".xlsx", ".zip"];

    for tail in &suspicious_tails {
        if lower.ends_with(tail) {
            let stem = &lower[..lower.len() - tail.len()];
            for inner in &deceptive_inners {
                if stem.ends_with(inner) {
                    return true;
                }
            }
        }
    }
    false
}
