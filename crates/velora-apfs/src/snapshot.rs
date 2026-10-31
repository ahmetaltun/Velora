use crate::model::SnapshotInfo;
use plist::Value;
use std::io::Cursor;
use std::path::Path;
use std::process::Command;

pub struct SnapshotManager;

impl SnapshotManager {
    /// Queries all APFS snapshots for a given mount point using `diskutil apfs listSnapshots -plist`.
    /// Captures OS update snapshots, Time Machine snapshots, and third-party utility snapshots.
    /// Falls back to `tmutil listlocalsnapshots` if diskutil is unavailable.
    pub fn list_snapshots(mount_point: &Path) -> Vec<SnapshotInfo> {
        let mut snapshots = Vec::new();

        // 1. Query diskutil apfs listSnapshots <target> -plist
        let mut targets = vec![mount_point.to_path_buf()];
        // If inspecting root "/", also inspect "/System/Volumes/Data" which holds user and TM snapshots
        if mount_point == Path::new("/") {
            let data_vol = Path::new("/System/Volumes/Data");
            if data_vol.exists() {
                targets.push(data_vol.to_path_buf());
            }
        }

        for target in &targets {
            if let Ok(output) = Command::new("diskutil")
                .arg("apfs")
                .arg("listSnapshots")
                .arg(target)
                .arg("-plist")
                .output()
            {
                if output.status.success() {
                    let parsed = Self::parse_diskutil_plist(&output.stdout);
                    for snap in parsed {
                        if !snapshots.iter().any(|s: &SnapshotInfo| s.name == snap.name) {
                            snapshots.push(snap);
                        }
                    }
                }
            }
        }

        // 2. Fallback to tmutil if no snapshots were returned by diskutil
        if snapshots.is_empty() {
            let mount_str = mount_point.to_string_lossy();
            if let Ok(output) = Command::new("tmutil")
                .arg("listlocalsnapshots")
                .arg(mount_str.as_ref())
                .output()
            {
                if output.status.success() {
                    let text = String::from_utf8_lossy(&output.stdout);
                    snapshots = Self::parse_tmutil_output(&text);
                }
            }
        }

        snapshots
    }

    /// Parses XML plist returned by `diskutil apfs listSnapshots <volume> -plist`.
    pub fn parse_diskutil_plist(xml_bytes: &[u8]) -> Vec<SnapshotInfo> {
        let val: Value = match Value::from_reader(Cursor::new(xml_bytes)) {
            Ok(v) => v,
            Err(_) => return Vec::new(),
        };

        let root_dict = match val.as_dictionary() {
            Some(d) => d,
            None => return Vec::new(),
        };

        let snapshots_arr = match root_dict.get("Snapshots").and_then(|s| s.as_array()) {
            Some(arr) => arr,
            None => return Vec::new(),
        };

        let mut list = Vec::new();
        for item in snapshots_arr {
            if let Some(dict) = item.as_dictionary() {
                if let Some(name) = dict.get("SnapshotName").and_then(|n| n.as_string()) {
                    let date_formatted = Self::extract_date_from_name(name);
                    list.push(SnapshotInfo {
                        name: name.to_string(),
                        date_formatted,
                    });
                }
            }
        }
        list
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

    pub fn extract_date_from_name(name: &str) -> String {
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
        } else if name.starts_with("com.apple.os.update") {
            return "macOS System Update".to_string();
        } else if let Some(start) = name.find("com.bombich.ccc.") {
            let remainder = &name[start + "com.bombich.ccc.".len()..];
            return format!("CCC Backup: {}", remainder);
        }
        "APFS Snapshot".to_string()
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

    #[test]
    fn test_parse_diskutil_plist() {
        let xml = r#"<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>Snapshots</key>
	<array>
		<dict>
			<key>SnapshotName</key>
			<string>com.apple.os.update-624F4BC7A0EC2C5EBA734EA2307E0510B256421BF0861324585CDEBB770167BB</string>
			<key>SnapshotUUID</key>
			<string>CDDC8F83-35CF-4D6B-B341-8557FDA80B45</string>
		</dict>
		<dict>
			<key>SnapshotName</key>
			<string>com.apple.TimeMachine.2026-10-30-131900.local</string>
			<key>SnapshotUUID</key>
			<string>1319C0B4-BE71-440A-8881-AB974E462A34</string>
		</dict>
	</array>
</dict>
</plist>"#;

        let list = SnapshotManager::parse_diskutil_plist(xml.as_bytes());
        assert_eq!(list.len(), 2);
        assert_eq!(list[0].date_formatted, "macOS System Update");
        assert_eq!(list[1].date_formatted, "2026-10-30 13:19:00");
    }
}
