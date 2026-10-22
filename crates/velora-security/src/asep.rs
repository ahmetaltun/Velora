use std::path::{Path, PathBuf};

#[derive(Debug, Clone)]
pub struct AsepItem {
    pub plist_path: PathBuf,
    pub label: String,
    pub program_path: Option<PathBuf>,
    pub arguments: Vec<String>,
    pub run_at_load: bool,
    pub is_hidden_target: bool,
    pub target_exists: bool,
    pub is_script_runner: bool,
    pub suspicious_reasons: Vec<String>,
}

pub struct AsepAuditor;

impl AsepAuditor {
    /// Inspects a LaunchAgent or LaunchDaemon plist file on disk and extracts its execution target.
    pub fn audit_launch_item(plist_path: &Path) -> Option<AsepItem> {
        let value = plist::Value::from_file(plist_path).ok()?;
        let dict = value.into_dictionary()?;

        let label = dict
            .get("Label")
            .and_then(|v| v.as_string())
            .unwrap_or("")
            .to_string();

        let run_at_load = dict
            .get("RunAtLoad")
            .and_then(|v| v.as_boolean())
            .unwrap_or(false);

        let program_str = dict.get("Program").and_then(|v| v.as_string());
        let program_args: Vec<String> = dict
            .get("ProgramArguments")
            .and_then(|v| v.as_array())
            .map(|arr| {
                arr.iter()
                    .filter_map(|item| item.as_string().map(|s| s.to_string()))
                    .collect()
            })
            .unwrap_or_default();

        // Determine effective target executable
        let target_str = match program_str {
            Some(p) => Some(p.to_string()),
            None => program_args.first().cloned(),
        };

        let program_path = target_str.map(PathBuf::from);

        let mut suspicious_reasons = Vec::new();
        let mut is_hidden_target = false;
        let mut target_exists = false;
        let mut is_script_runner = false;

        if let Some(ref target) = program_path {
            target_exists = target.exists();
            let target_lossy = target.to_string_lossy();

            // Check if pointing to a non-existent binary (orphaned launch daemon residue)
            if !target_exists {
                suspicious_reasons.push(format!(
                    "Referenced executable target does not exist: {}",
                    target_lossy
                ));
            }

            // Check if hidden target or located in suspicious unconfined directories
            if let Some(file_name) = target.file_name() {
                if file_name.to_string_lossy().starts_with('.') {
                    is_hidden_target = true;
                    suspicious_reasons.push("Target binary is a hidden file".to_string());
                }
            }

            if target_lossy.starts_with("/tmp/")
                || target_lossy.starts_with("/var/tmp/")
                || target_lossy.starts_with("/Users/Shared/")
            {
                suspicious_reasons.push(format!(
                    "Target binary resides in temporary or shared directory: {}",
                    target_lossy
                ));
            }

            // Check if invoking an interpreter / shell with inline script
            let target_name = target
                .file_name()
                .map(|f| f.to_string_lossy())
                .unwrap_or_default();

            if matches!(
                target_name.as_ref(),
                "sh" | "bash" | "zsh" | "python" | "python3" | "osascript" | "perl"
            ) {
                is_script_runner = true;
                for arg in &program_args {
                    let arg_lower = arg.to_lowercase();
                    if arg_lower.contains("curl ")
                        || arg_lower.contains("wget ")
                        || arg_lower.contains("base64 ")
                        || arg_lower.contains("nohup ")
                        || arg_lower.contains("nc ")
                    {
                        suspicious_reasons.push(format!(
                            "Shell executes inline command containing network or encoding tools: {}",
                            arg
                        ));
                    }
                }
            }
        } else {
            suspicious_reasons.push("Launch plist defines neither 'Program' nor 'ProgramArguments'".to_string());
        }

        Some(AsepItem {
            plist_path: plist_path.to_path_buf(),
            label,
            program_path,
            arguments: program_args,
            run_at_load,
            is_hidden_target,
            target_exists,
            is_script_runner,
            suspicious_reasons,
        })
    }
}
