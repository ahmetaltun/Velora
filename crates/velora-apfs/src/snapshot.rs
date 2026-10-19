use crate::model::SnapshotInfo;
use std::path::Path;
use std::process::Command;

pub struct SnapshotManager;

impl SnapshotManager {
    /// Queries local Time Machine snapshots for a given mount point using standard user privileges.
    pub fn list_snapshots(mount_point: &Path) -> Vec<SnapshotInfo> {
        let mount_str = mount_point.to_string_lossy();
        let output = match Command::new("tmutil")
            .arg("listlocalsnapshots")
            .arg(mount_str.as_ref())
            .output()
        {
            Ok(out) if out.status.success() => String::from_utf8_lossy(&out.stdout).to_string(),
            _ => return Vec::new(),
        };

        Self::parse_tmutil_output(&output)
    }

    pub fn parse_tmutil_output(output: &str) -> Vec<SnapshotInfo> {
        let mut snapshots = Vec::new();

        for line in output.lines() {
            let trimmed = line.trim();
            if trimmed.contains("com.apple.TimeMachine.") {
                let name = trimmed.to_string();
                let date_formatted = Self::extract_date_from_name(&name);
                snapshots.push(SnapshotInfo {
                    name,
                    date_formatted,
                });
            }
        }

        snapshots
    }

    fn extract_date_from_name(name: &str) -> String {
        // e.g. "com.apple.TimeMachine.2026-06-05-200115.local"
        if let Some(start) = name.find("com.apple.TimeMachine.") {
            let remainder = &name[start + "com.apple.TimeMachine.".len()..];
            let date_part = remainder.trim_end_matches(".local");
            // format: 2026-06-05-200115 -> "2026-06-05 20:01:15"
            let parts: Vec<&str> = date_part.split('-').collect();
            if parts.len() == 4 {
                let date = format!("{}-{}-{}", parts[0], parts[1], parts[2]);
                let time_raw = parts[3];
                if time_raw.len() == 6 {
                    let time = format!("{}:{}:{}", &time_raw[0..2], &time_raw[2..4], &time_raw[4..6]);
                    return format!("{} {}", date, time);
                }
                return format!("{} {}", date, time_raw);
            }
            return date_part.to_string();
        }
        "Unknown Date".to_string()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_parse_tmutil_output() {
        let raw = "Snapshots for disk /:\ncom.apple.TimeMachine.2026-06-05-200115.local\ncom.apple.TimeMachine.2026-10-18-091530.local\n";
        let list = SnapshotManager::parse_tmutil_output(raw);
        assert_eq!(list.len(), 2);
        assert_eq!(list[0].name, "com.apple.TimeMachine.2026-06-05-200115.local");
        assert_eq!(list[0].date_formatted, "2026-06-05 20:01:15");
        assert_eq!(list[1].date_formatted, "2026-10-18 09:15:30");
    }
}
