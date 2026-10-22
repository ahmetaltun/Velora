use crate::model::SigningStatus;
use std::path::Path;
use std::process::Command;

pub struct CodeSignVerifier;

impl CodeSignVerifier {
    /// Inspects the Mach-O code signature and notarization status of an executable binary or bundle.
    pub fn verify(path: &Path) -> SigningStatus {
        if !path.exists() {
            return SigningStatus::Unknown;
        }

        // 1. Run codesign -dv --verbose=4 to extract signing metadata
        let output = match Command::new("/usr/bin/codesign")
            .arg("-dv")
            .arg("--verbose=4")
            .arg(path)
            .output()
        {
            Ok(out) => out,
            Err(e) => {
                return SigningStatus::InvalidSignature {
                    error: format!("Failed to execute codesign utility: {}", e),
                }
            }
        };

        let stderr = String::from_utf8_lossy(&output.stderr);
        let stdout = String::from_utf8_lossy(&output.stdout);
        let combined = format!("{}\n{}", stdout, stderr);

        if !output.status.success() {
            if combined.contains("code object is not signed at all") {
                return SigningStatus::Unsigned;
            }
            return SigningStatus::InvalidSignature {
                error: stderr.trim().to_string(),
            };
        }

        // 2. Run codesign --verify --strict to ensure binary integrity has not been tampered with
        if let Ok(verify_out) = Command::new("/usr/bin/codesign")
            .arg("--verify")
            .arg("--strict")
            .arg(path)
            .output()
        {
            if !verify_out.status.success() {
                let verify_err = String::from_utf8_lossy(&verify_out.stderr);
                return SigningStatus::InvalidSignature {
                    error: format!("Signature integrity verification failed: {}", verify_err.trim()),
                };
            }
        }

        // 3. Parse authority and signatures from codesign -dv output
        let mut authorities = Vec::new();
        let mut team_id = None;
        let mut is_adhoc = false;

        for line in combined.lines() {
            let trimmed = line.trim();
            if let Some(auth) = trimmed.strip_prefix("Authority=") {
                authorities.push(auth.to_string());
            } else if let Some(team) = trimmed.strip_prefix("TeamIdentifier=") {
                if team != "not set" && !team.is_empty() {
                    team_id = Some(team.to_string());
                }
            } else if trimmed.starts_with("Signature=adhoc") {
                is_adhoc = true;
            }
        }

        if authorities.iter().any(|a| a.contains("Apple Root CA") || a.contains("Software Signing"))
            && authorities.iter().any(|a| a.contains("Apple"))
            && team_id.is_none()
        {
            return SigningStatus::AppleInternal;
        }

        if let Some(dev_auth) = authorities.iter().find(|a| a.starts_with("Developer ID Application:")) {
            return SigningStatus::DeveloperIdSigned {
                authority: dev_auth.clone(),
                team_id,
            };
        }

        if is_adhoc || authorities.is_empty() {
            return SigningStatus::AdHoc;
        }

        // Fallback with first authority if available
        if let Some(first) = authorities.into_iter().next() {
            return SigningStatus::DeveloperIdSigned {
                authority: first,
                team_id,
            };
        }

        SigningStatus::Unknown
    }
}
