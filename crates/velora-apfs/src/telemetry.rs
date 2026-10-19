use crate::model::{ApfsContainer, ApfsVolume};
use plist::Value;
use std::ffi::CString;
use std::io::Cursor;
use std::path::Path;
use std::process::Command;

pub struct ApfsTelemetry;

pub struct VfsStats {
    pub total_bytes: u64,
    pub free_bytes: u64,
    pub available_bytes: u64,
}

impl ApfsTelemetry {
    /// Fast POSIX statvfs system call to get raw filesystem blocks.
    pub fn get_vfs_stats(mount_point: &Path) -> Option<VfsStats> {
        let path_cstr = CString::new(mount_point.to_string_lossy().as_bytes()).ok()?;
        unsafe {
            let mut stat: libc::statvfs = std::mem::zeroed();
            if libc::statvfs(path_cstr.as_ptr(), &mut stat) == 0 {
                let block_size = stat.f_frsize as u64;
                Some(VfsStats {
                    total_bytes: stat.f_blocks as u64 * block_size,
                    free_bytes: stat.f_bfree as u64 * block_size,
                    available_bytes: stat.f_bavail as u64 * block_size,
                })
            } else {
                None
            }
        }
    }

    /// Queries the container reference (e.g., "disk3") for a specific mount point using diskutil info.
    pub fn get_container_reference(mount_point: &Path) -> Option<String> {
        let output = Command::new("diskutil")
            .arg("info")
            .arg("-plist")
            .arg(mount_point)
            .output()
            .ok()?;

        if !output.status.success() {
            return None;
        }

        let val: Value = Value::from_reader(Cursor::new(output.stdout.as_slice())).ok()?;
        let dict = val.as_dictionary()?;
        dict.get("APFSContainerReference")
            .and_then(|v| v.as_string())
            .map(|s| s.to_string())
    }

    /// Queries all APFS containers and volumes via diskutil apfs list -plist.
    pub fn query_containers() -> Vec<ApfsContainer> {
        let output = match Command::new("diskutil")
            .arg("apfs")
            .arg("list")
            .arg("-plist")
            .output()
        {
            Ok(out) if out.status.success() => out.stdout,
            _ => return Vec::new(),
        };

        Self::parse_apfs_list_plist(&output)
    }

    pub fn query_container_for_mount(mount_point: &Path) -> Option<ApfsContainer> {
        let containers = Self::query_containers();
        if let Some(cont_ref) = Self::get_container_reference(mount_point) {
            if let Some(c) = containers.into_iter().find(|c| c.container_reference == cont_ref) {
                return Some(c);
            }
        }
        // Fallback: return the largest container found
        Self::query_containers()
            .into_iter()
            .max_by_key(|c| c.capacity_ceiling)
    }

    pub fn parse_apfs_list_plist(xml_bytes: &[u8]) -> Vec<ApfsContainer> {
        let val: Value = match Value::from_reader(Cursor::new(xml_bytes)) {
            Ok(v) => v,
            Err(_) => return Vec::new(),
        };

        let root_dict = match val.as_dictionary() {
            Some(d) => d,
            None => return Vec::new(),
        };

        let containers_arr = match root_dict.get("Containers").and_then(|c| c.as_array()) {
            Some(a) => a,
            None => return Vec::new(),
        };

        let mut containers = Vec::new();

        for cont_val in containers_arr {
            if let Some(cdict) = cont_val.as_dictionary() {
                let container_reference = cdict
                    .get("ContainerReference")
                    .and_then(|v| v.as_string())
                    .unwrap_or_default()
                    .to_string();

                let capacity_ceiling = cdict
                    .get("CapacityCeiling")
                    .and_then(|v| v.as_unsigned_integer())
                    .unwrap_or(0);

                let capacity_free = cdict
                    .get("CapacityFree")
                    .and_then(|v| v.as_unsigned_integer())
                    .unwrap_or(0);

                let mut volumes = Vec::new();
                if let Some(vols_arr) = cdict.get("Volumes").and_then(|v| v.as_array()) {
                    for vol_val in vols_arr {
                        if let Some(vdict) = vol_val.as_dictionary() {
                            let device_id = vdict
                                .get("DeviceIdentifier")
                                .and_then(|v| v.as_string())
                                .unwrap_or_default()
                                .to_string();

                            let name = vdict
                                .get("Name")
                                .and_then(|v| v.as_string())
                                .unwrap_or_default()
                                .to_string();

                            let capacity_in_use = vdict
                                .get("CapacityInUse")
                                .and_then(|v| v.as_unsigned_integer())
                                .unwrap_or(0);

                            let mut roles = Vec::new();
                            if let Some(roles_arr) = vdict.get("Roles").and_then(|r| r.as_array()) {
                                for r in roles_arr {
                                    if let Some(rs) = r.as_string() {
                                        roles.push(rs.to_string());
                                    }
                                }
                            }

                            volumes.push(ApfsVolume {
                                device_id,
                                name,
                                roles,
                                capacity_in_use,
                            });
                        }
                    }
                }

                containers.push(ApfsContainer {
                    container_reference,
                    capacity_ceiling,
                    capacity_free,
                    volumes,
                });
            }
        }

        containers
    }
}
