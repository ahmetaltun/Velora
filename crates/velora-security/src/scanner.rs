use crate::asep::AsepAuditor;
use crate::codesign::CodeSignVerifier;
use crate::model::{
    SecurityScanSummary, SigningStatus, ThreatCategory, ThreatRecord, ThreatSeverity,
};
use crate::threat_db::{compute_file_sha256, ThreatDatabase};
use crate::triage::{CandidateKind, SecurityTriage};
use std::collections::HashSet;
use std::path::Path;
use std::time::Instant;
use velora_index::VolumeIndex;

pub struct SecurityScanner;

impl SecurityScanner {
    /// Performs a high-speed multi-stage security audit leveraging in-memory catalog.bin data.
    pub fn scan(volume: &VolumeIndex, home_path: &Path) -> SecurityScanSummary {
        let start_time = Instant::now();
        let db = ThreatDatabase::new();

        // Stage 1: Zero-Disk-I/O In-Memory Candidate Triage (<10ms)
        let candidates = SecurityTriage::triage_candidates(volume, home_path);
        let total_candidates = candidates.len() as u32;

        let mut threats = Vec::new();
        let mut asep_count = 0u32;
        let mut seen_targets = HashSet::new();

        for candidate in candidates {
            match candidate.kind {
                CandidateKind::LaunchAgentPlist | CandidateKind::LaunchDaemonPlist => {
                    asep_count += 1;
                    if let Some(asep) = AsepAuditor::audit_launch_item(&candidate.path) {
                        let plist_str = candidate.path.to_string_lossy().to_string();

                        // 1. Check known malicious label in Threat DB
                        if let Some(def) = db.lookup_label(&asep.label) {
                            threats.push(ThreatRecord {
                                id: format!("label_{}", asep.label),
                                name: def.name.to_string(),
                                category: def.category,
                                severity: def.severity,
                                target_path: asep
                                    .program_path
                                    .as_ref()
                                    .map(|p| p.to_string_lossy().to_string())
                                    .unwrap_or_else(|| plist_str.clone()),
                                associated_paths: vec![plist_str.clone()],
                                file_size: candidate.size,
                                sha256_hex: String::new(),
                                signing_status: "Flagged by Threat Intelligence".to_string(),
                                description: def.description.to_string(),
                                detection_method: "Known Threat Label Registry".to_string(),
                                can_quarantine: true,
                            });
                            continue;
                        }

                        // 2. Check referenced executable target
                        if let Some(ref target) = asep.program_path {
                            let target_str = target.to_string_lossy().to_string();
                            if !seen_targets.insert(target_str.clone()) {
                                continue;
                            }

                            if asep.target_exists {
                                let file_size = std::fs::metadata(target)
                                    .map(|m| m.len())
                                    .unwrap_or(0);

                                // A. Hash Matching
                                let hash_hex = compute_file_sha256(target).unwrap_or_default();
                                if let Some(def) = db.lookup_hash(&hash_hex) {
                                    threats.push(ThreatRecord {
                                        id: format!("hash_{}", &hash_hex[..12]),
                                        name: def.name.to_string(),
                                        category: def.category,
                                        severity: def.severity,
                                        target_path: target_str.clone(),
                                        associated_paths: vec![plist_str.clone()],
                                        file_size,
                                        sha256_hex: hash_hex.clone(),
                                        signing_status: "Verified Malicious Hash".to_string(),
                                        description: def.description.to_string(),
                                        detection_method: "SHA-256 IOC Threat Database".to_string(),
                                        can_quarantine: true,
                                    });
                                    continue;
                                }

                                // B. Code Signature Verification
                                let sig = CodeSignVerifier::verify(target);
                                match sig {
                                    SigningStatus::InvalidSignature { error } => {
                                        threats.push(ThreatRecord {
                                            id: format!("tampered_{}", candidate.name),
                                            name: "Tampered / Invalid Code Signature".to_string(),
                                            category: ThreatCategory::InvalidSignature,
                                            severity: ThreatSeverity::Critical,
                                            target_path: target_str.clone(),
                                            associated_paths: vec![plist_str.clone()],
                                            file_size,
                                            sha256_hex: hash_hex,
                                            signing_status: format!("Tampered: {}", error),
                                            description: format!(
                                                "Binary signature integrity check failed. The file has been modified or corrupted after signing: {}",
                                                error
                                            ),
                                            detection_method: "Apple Security Framework Integrity Check".to_string(),
                                            can_quarantine: true,
                                        });
                                    }
                                    SigningStatus::Unsigned => {
                                        // If unsigned and configured to run automatically at load
                                        threats.push(ThreatRecord {
                                            id: format!("unsigned_asep_{}", candidate.name),
                                            name: "Unsigned Boot Persistence Binary".to_string(),
                                            category: ThreatCategory::SuspiciousPersistence,
                                            severity: ThreatSeverity::Warning,
                                            target_path: target_str.clone(),
                                            associated_paths: vec![plist_str.clone()],
                                            file_size,
                                            sha256_hex: hash_hex,
                                            signing_status: "Unsigned Code".to_string(),
                                            description: format!(
                                                "Binary configured to run automatically at boot lacks Apple Developer ID signature (Service: {})",
                                                asep.label
                                            ),
                                            detection_method: "macOS ASEP CodeSign Verification".to_string(),
                                            can_quarantine: true,
                                        });
                                    }
                                    _ => {
                                        // If suspicious script runner commands were found
                                        if !asep.suspicious_reasons.is_empty() && !sig.is_trusted() {
                                            threats.push(ThreatRecord {
                                                id: format!("suspicious_script_{}", candidate.name),
                                                name: "Suspicious Launch Command".to_string(),
                                                category: ThreatCategory::SuspiciousPersistence,
                                                severity: ThreatSeverity::High,
                                                target_path: target_str.clone(),
                                                associated_paths: vec![plist_str.clone()],
                                                file_size,
                                                sha256_hex: hash_hex,
                                                signing_status: sig.label(),
                                                description: asep.suspicious_reasons.join("; "),
                                                detection_method: "Launchd Command Pattern Heuristics".to_string(),
                                                can_quarantine: true,
                                            });
                                        }
                                    }
                                }
                            } else {
                                // Missing target executable
                                threats.push(ThreatRecord {
                                    id: format!("orphaned_asep_{}", candidate.name),
                                    name: "Orphaned Launch Persistence Residue".to_string(),
                                    category: ThreatCategory::SuspiciousPersistence,
                                    severity: ThreatSeverity::Warning,
                                    target_path: plist_str.clone(),
                                    associated_paths: vec![],
                                    file_size: candidate.size,
                                    sha256_hex: String::new(),
                                    signing_status: "Target Not Found".to_string(),
                                    description: format!(
                                        "Launch plist is registered for auto-start, but referenced binary does not exist ({})",
                                        target_str
                                    ),
                                    detection_method: "Orphaned Service Detector".to_string(),
                                    can_quarantine: true,
                                });
                            }
                        }
                    }
                }

                CandidateKind::SuspiciousDoubleExtension => {
                    let target_path = &candidate.path;
                    let target_str = target_path.to_string_lossy().to_string();
                    let sig = CodeSignVerifier::verify(target_path);

                    if !sig.is_trusted() {
                        let hash_hex = compute_file_sha256(target_path).unwrap_or_default();
                        threats.push(ThreatRecord {
                            id: format!("double_ext_{}", candidate.name),
                            name: "Deceptive Double-Extension Binary".to_string(),
                            category: ThreatCategory::Trojan,
                            severity: ThreatSeverity::High,
                            target_path: target_str,
                            associated_paths: vec![],
                            file_size: candidate.size,
                            sha256_hex: hash_hex,
                            signing_status: sig.label(),
                            description: format!(
                                "File '{}' uses a deceptive double extension to disguise executable code as an innocuous document.",
                                candidate.name
                            ),
                            detection_method: "Deceptive Extension Heuristic".to_string(),
                            can_quarantine: true,
                        });
                    }
                }

                CandidateKind::SuspiciousHiddenExecutable => {
                    let target_path = &candidate.path;
                    let target_str = target_path.to_string_lossy().to_string();
                    let sig = CodeSignVerifier::verify(target_path);

                    if !sig.is_trusted() {
                        let hash_hex = compute_file_sha256(target_path).unwrap_or_default();
                        threats.push(ThreatRecord {
                            id: format!("hidden_exec_{}", candidate.name),
                            name: "Suspicious Hidden Script in User Space".to_string(),
                            category: ThreatCategory::SuspiciousPersistence,
                            severity: ThreatSeverity::Medium,
                            target_path: target_str,
                            associated_paths: vec![],
                            file_size: candidate.size,
                            sha256_hex: hash_hex,
                            signing_status: sig.label(),
                            description: format!(
                                "Hidden executable script located in unconfined user folder: {}",
                                candidate.name
                            ),
                            detection_method: "Hidden File In User Space Heuristic".to_string(),
                            can_quarantine: true,
                        });
                    }
                }

                _ => {}
            }
        }

        let threat_count = threats.len() as u32;
        let scan_duration_ms = start_time.elapsed().as_millis() as u64;

        SecurityScanSummary {
            total_candidates_triaged: total_candidates,
            total_asep_inspected: asep_count,
            threat_count,
            threats,
            scan_duration_ms,
        }
    }
}
