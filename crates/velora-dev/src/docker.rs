use crate::model::{
    DockerBuildCacheItem, DockerContainerItem, DockerDaemonStatus, DockerEngineKind,
    DockerImageItem, DockerPruneResult, DockerStorageSummary, DockerVmDisk, DockerVolumeItem,
};
use std::fs;
use std::io::{Read, Write};
use std::os::unix::fs::MetadataExt;
use std::os::unix::net::UnixStream;
use std::path::{Path, PathBuf};
use std::process::Command;
use std::time::Duration;

pub struct DockerInspector;

impl DockerInspector {
    /// Detects all known Docker/container VM disk images on the host macOS APFS filesystem.
    pub fn detect_vm_disks(home_path: &Path) -> Vec<DockerVmDisk> {
        let mut disks = Vec::new();

        let targets = [
            // Docker Desktop (Modern raw sparse disk)
            (
                "Docker Desktop Virtual Disk (Raw)",
                home_path.join("Library/Containers/com.docker.docker/Data/vms/0/data/Docker.raw"),
                DockerEngineKind::DockerDesktop,
            ),
            // Docker Desktop (Legacy QCOW2 disk)
            (
                "Docker Desktop Legacy Disk (QCOW2)",
                home_path.join("Library/Containers/com.docker.docker/Data/vms/0/Docker.qcow2"),
                DockerEngineKind::DockerDesktop,
            ),
            // OrbStack (APFS sparse VM image)
            (
                "OrbStack Container Disk",
                home_path.join(".orbstack/data/docker.img"),
                DockerEngineKind::OrbStack,
            ),
            // Colima (Default Lima QCOW2)
            (
                "Colima Machine Disk",
                home_path.join(".colima/default/diffdisk.qcow2"),
                DockerEngineKind::Colima,
            ),
            // Colima alternative Lima path
            (
                "Colima Lima Diffdisk",
                home_path.join(".colima/_lima/colima/diffdisk"),
                DockerEngineKind::Colima,
            ),
        ];

        for (name, path, engine) in targets {
            if path.exists() {
                if let Ok(meta) = fs::metadata(&path) {
                    // In APFS, blocks() returns 512-byte blocks physically allocated to the sparse file
                    let allocated_bytes = meta.blocks() * 512;
                    let virtual_capacity_bytes = meta.len();
                    let modified_secs = meta
                        .modified()
                        .ok()
                        .and_then(|t| t.duration_since(std::time::UNIX_EPOCH).ok())
                        .map(|d| d.as_secs())
                        .unwrap_or(0);

                    disks.push(DockerVmDisk {
                        name: name.to_string(),
                        path: path.to_string_lossy().to_string(),
                        engine,
                        allocated_bytes,
                        virtual_capacity_bytes,
                        modified_secs,
                    });
                }
            }
        }

        disks
    }

    /// Discovers candidate Docker daemon Unix domain sockets in order of standard priority.
    pub fn discover_socket(home_path: &Path) -> Option<PathBuf> {
        // 1. DOCKER_HOST env var
        if let Ok(host) = std::env::var("DOCKER_HOST") {
            if let Some(sock_str) = host.strip_prefix("unix://") {
                let p = PathBuf::from(sock_str);
                if p.exists() {
                    return Some(p);
                }
            }
        }

        let candidates = [
            // Docker Desktop modern user socket (macOS Sequoia default)
            home_path.join(".docker/run/docker.sock"),
            // Standard system socket / symlink
            PathBuf::from("/var/run/docker.sock"),
            // OrbStack socket
            home_path.join(".orbstack/run/docker.sock"),
            // Colima socket
            home_path.join(".colima/default/docker.sock"),
        ];

        for c in candidates {
            if c.exists() {
                return Some(c);
            }
        }

        None
    }

    /// Performs full dual-layer Docker inspection: Host VM disk telemetry + Guest Engine API /system/df.
    pub fn inspect(home_path: &Path) -> DockerStorageSummary {
        let mut summary = DockerStorageSummary::default();

        // Layer 1: Host VM Disk Telemetry
        summary.vm_disks = Self::detect_vm_disks(home_path);
        summary.total_host_allocated_bytes = summary.vm_disks.iter().map(|d| d.allocated_bytes).sum();

        // Determine likely engine name from detected disks
        if let Some(first_disk) = summary.vm_disks.first() {
            summary.engine_name = first_disk.engine.display_name().to_string();
        } else {
            summary.engine_name = "Docker Engine".to_string();
        }

        // Layer 2: Container Engine REST API Telemetry
        let socket_opt = Self::discover_socket(home_path);

        if let Some(ref sock_path) = socket_opt {
            summary.socket_path = sock_path.to_string_lossy().to_string();

            match Self::query_socket_df(sock_path) {
                Ok(df_json) => {
                    summary.daemon_status = DockerDaemonStatus::Running;
                    Self::populate_from_df_json(&mut summary, &df_json);
                }
                Err(_) => {
                    // Try CLI fallback
                    if let Some(df_json) = Self::query_cli_df() {
                        summary.daemon_status = DockerDaemonStatus::Running;
                        Self::populate_from_df_json(&mut summary, &df_json);
                    } else {
                        summary.daemon_status = DockerDaemonStatus::Stopped;
                    }
                }
            }
        } else {
            // No socket found, try CLI fallback
            if let Some(df_json) = Self::query_cli_df() {
                summary.daemon_status = DockerDaemonStatus::Running;
                summary.socket_path = "CLI Pipe".to_string();
                Self::populate_from_df_json(&mut summary, &df_json);
            } else {
                summary.daemon_status = DockerDaemonStatus::SocketNotFound;
            }
        }

        // Calculate Phantom Bloat: Difference between host APFS sparse allocation and active live guest data
        summary.phantom_bloat_bytes = summary
            .total_host_allocated_bytes
            .saturating_sub(summary.total_guest_active_bytes);

        summary
    }

    /// Communicates directly with the Docker Engine over a local Unix domain socket using HTTP/1.1.
    fn query_socket_df(socket_path: &Path) -> Result<serde_json::Value, String> {
        let mut stream = UnixStream::connect(socket_path)
            .map_err(|e| format!("Failed to connect to socket: {}", e))?;

        stream
            .set_read_timeout(Some(Duration::from_secs(3)))
            .map_err(|e| e.to_string())?;
        stream
            .set_write_timeout(Some(Duration::from_secs(2)))
            .map_err(|e| e.to_string())?;

        let request = "GET /system/df HTTP/1.1\r\nHost: localhost\r\nAccept: application/json\r\nConnection: close\r\n\r\n";
        stream
            .write_all(request.as_bytes())
            .map_err(|e| format!("Failed to send GET /system/df: {}", e))?;

        let mut buffer = Vec::new();
        stream
            .read_to_end(&mut buffer)
            .map_err(|e| format!("Failed to read response: {}", e))?;

        Self::extract_http_json_body(&buffer)
    }

    /// Sends a POST prune request over the Unix domain socket or falls back to the CLI.
    fn send_socket_prune(socket_path: &Path, endpoint: &str) -> Result<serde_json::Value, String> {
        let mut stream = UnixStream::connect(socket_path)
            .map_err(|e| format!("Failed to connect to socket: {}", e))?;

        stream
            .set_read_timeout(Some(Duration::from_secs(30)))
            .map_err(|e| e.to_string())?;
        stream
            .set_write_timeout(Some(Duration::from_secs(5)))
            .map_err(|e| e.to_string())?;

        let request = format!(
            "POST {} HTTP/1.1\r\nHost: localhost\r\nAccept: application/json\r\nConnection: close\r\n\r\n",
            endpoint
        );
        stream
            .write_all(request.as_bytes())
            .map_err(|e| format!("Failed to send POST request: {}", e))?;

        let mut buffer = Vec::new();
        stream
            .read_to_end(&mut buffer)
            .map_err(|e| format!("Failed to read prune response: {}", e))?;

        Self::extract_http_json_body(&buffer)
    }

    fn extract_http_json_body(buffer: &[u8]) -> Result<serde_json::Value, String> {
        let header_end = b"\r\n\r\n";
        if let Some(pos) = buffer
            .windows(header_end.len())
            .position(|window| window == header_end)
        {
            let body_bytes = &buffer[pos + header_end.len()..];
            // Handle HTTP chunked transfer encoding if present
            let body_str = String::from_utf8_lossy(body_bytes);
            let cleaned_str = if body_str.starts_with(|c: char| c.is_ascii_hexdigit())
                && body_str.contains("\r\n")
            {
                // Simple de-chunk: skip first chunk size line
                if let Some(second_pos) = body_str.find("\r\n") {
                    &body_str[second_pos + 2..]
                } else {
                    &body_str
                }
            } else {
                &body_str
            };

            serde_json::from_str::<serde_json::Value>(cleaned_str.trim())
                .or_else(|_| serde_json::from_slice::<serde_json::Value>(body_bytes))
                .map_err(|e| format!("JSON parse error: {}", e))
        } else {
            Err("Malformed HTTP response: missing CRLF CRLF".to_string())
        }
    }

    /// Invokes `docker system df --format '{{json .}}'` as a fallback.
    fn query_cli_df() -> Option<serde_json::Value> {
        let output = Command::new("docker")
            .args(["system", "df", "--format", "{{json .}}"])
            .output()
            .ok()?;

        if !output.status.success() {
            return None;
        }

        let stdout = String::from_utf8_lossy(&output.stdout);
        let mut images_val = Vec::new();
        let mut containers_val = Vec::new();
        let mut volumes_val = Vec::new();
        let mut build_cache_val = Vec::new();

        for line in stdout.lines() {
            if let Ok(entry) = serde_json::from_str::<serde_json::Value>(line) {
                if let Some(t) = entry.get("Type").and_then(|v| v.as_str()) {
                    match t {
                        "Images" => images_val.push(entry),
                        "Containers" => containers_val.push(entry),
                        "Local Volumes" => volumes_val.push(entry),
                        "Build Cache" => build_cache_val.push(entry),
                        _ => {}
                    }
                }
            }
        }

        Some(serde_json::json!({
            "CliRows": {
                "Images": images_val,
                "Containers": containers_val,
                "Volumes": volumes_val,
                "BuildCache": build_cache_val,
            }
        }))
    }

    pub fn populate_from_df_json(summary: &mut DockerStorageSummary, json: &serde_json::Value) {
        // 1. Parse Images
        if let Some(images_arr) = json.get("Images").and_then(|v| v.as_array()) {
            for img in images_arr {
                let id = img.get("Id").and_then(|v| v.as_str()).unwrap_or("").to_string();
                let short_id = if id.starts_with("sha256:") && id.len() >= 19 {
                    id[7..19].to_string()
                } else {
                    id.clone()
                };

                let mut repo_tags = Vec::new();
                if let Some(tags) = img.get("RepoTags").and_then(|v| v.as_array()) {
                    for tag in tags {
                        if let Some(t_str) = tag.as_str() {
                            repo_tags.push(t_str.to_string());
                        }
                    }
                }

                let is_dangling = repo_tags.is_empty()
                    || repo_tags.iter().all(|t| t == "<none>:<none>" || t.is_empty());
                let containers_count = img.get("Containers").and_then(|v| v.as_i64()).unwrap_or(0);
                let in_use = containers_count > 0;
                let size_bytes = img.get("Size").and_then(|v| v.as_u64()).unwrap_or(0);
                let shared_size_bytes = img.get("SharedSize").and_then(|v| v.as_u64()).unwrap_or(0);
                let created_secs = img.get("Created").and_then(|v| v.as_u64()).unwrap_or(0);

                summary.images_total_bytes += size_bytes;
                if is_dangling {
                    summary.dangling_images_bytes += size_bytes;
                } else if !in_use {
                    summary.unused_images_bytes += size_bytes;
                }

                summary.images.push(DockerImageItem {
                    id: short_id,
                    repo_tags,
                    size_bytes,
                    shared_size_bytes,
                    is_dangling,
                    in_use,
                    created_secs,
                });
            }
        }

        // 2. Parse Volumes
        if let Some(vols_arr) = json.get("Volumes").and_then(|v| v.as_array()) {
            for vol in vols_arr {
                let name = vol.get("Name").and_then(|v| v.as_str()).unwrap_or("").to_string();
                let driver = vol.get("Driver").and_then(|v| v.as_str()).unwrap_or("local").to_string();

                let (size_bytes, ref_count) = if let Some(ud) = vol.get("UsageData") {
                    let sz = ud.get("Size").and_then(|v| v.as_i64()).unwrap_or(0).max(0) as u64;
                    let rc = ud.get("RefCount").and_then(|v| v.as_i64()).unwrap_or(0);
                    (sz, rc)
                } else {
                    (0, 0)
                };

                // Check if anonymous volume (e.g. 64-char hex hash)
                let is_anonymous = name.len() == 64 && name.chars().all(|c| c.is_ascii_hexdigit());
                let in_use = ref_count > 0;

                summary.volumes_total_bytes += size_bytes;
                if !in_use {
                    if is_anonymous {
                        summary.dangling_anonymous_volumes_bytes += size_bytes;
                    } else {
                        summary.dangling_named_volumes_bytes += size_bytes;
                    }
                }

                summary.volumes.push(DockerVolumeItem {
                    name,
                    driver,
                    size_bytes,
                    is_anonymous,
                    in_use,
                    ref_count,
                });
            }
        }

        // 3. Parse BuildCache
        if let Some(bc_arr) = json.get("BuildCache").and_then(|v| v.as_array()) {
            for bc in bc_arr {
                let id = bc.get("ID").and_then(|v| v.as_str()).unwrap_or("").to_string();
                let cache_type = bc.get("Type").and_then(|v| v.as_str()).unwrap_or("regular").to_string();
                let description = bc.get("Description").and_then(|v| v.as_str()).unwrap_or("").to_string();
                let size_bytes = bc.get("Size").and_then(|v| v.as_u64()).unwrap_or(0);
                let in_use = bc.get("InUse").and_then(|v| v.as_bool()).unwrap_or(false);
                let shared = bc.get("Shared").and_then(|v| v.as_bool()).unwrap_or(false);

                summary.build_cache_total_bytes += size_bytes;
                if !in_use {
                    summary.build_cache_reclaimable_bytes += size_bytes;
                }

                summary.build_cache.push(DockerBuildCacheItem {
                    id,
                    cache_type,
                    description,
                    size_bytes,
                    in_use,
                    shared,
                });
            }
        }

        // 4. Parse Containers
        if let Some(cnt_arr) = json.get("Containers").and_then(|v| v.as_array()) {
            for cnt in cnt_arr {
                let id = cnt.get("Id").and_then(|v| v.as_str()).unwrap_or("").to_string();
                let short_id = if id.len() >= 12 { id[0..12].to_string() } else { id.clone() };

                let mut names = Vec::new();
                if let Some(names_arr) = cnt.get("Names").and_then(|v| v.as_array()) {
                    for n in names_arr {
                        if let Some(n_str) = n.as_str() {
                            names.push(n_str.trim_start_matches('/').to_string());
                        }
                    }
                }

                let image = cnt.get("Image").and_then(|v| v.as_str()).unwrap_or("").to_string();
                let state = cnt.get("State").and_then(|v| v.as_str()).unwrap_or("unknown").to_string();
                let size_rw_bytes = cnt.get("SizeRw").and_then(|v| v.as_i64()).unwrap_or(0).max(0) as u64;

                if state != "running" {
                    summary.stopped_containers_bytes += size_rw_bytes;
                }

                summary.containers.push(DockerContainerItem {
                    id: short_id,
                    names,
                    image,
                    state,
                    size_rw_bytes,
                });
            }
        }

        // Total guest active bytes = Images in use + Active volumes + Running container write layers + In-use build cache
        let active_images_bytes = summary.images_total_bytes.saturating_sub(
            summary.dangling_images_bytes + summary.unused_images_bytes,
        );
        let active_volumes_bytes = summary.volumes_total_bytes.saturating_sub(
            summary.dangling_anonymous_volumes_bytes + summary.dangling_named_volumes_bytes,
        );
        let active_build_cache = summary.build_cache_total_bytes.saturating_sub(summary.build_cache_reclaimable_bytes);

        summary.total_guest_active_bytes =
            active_images_bytes + active_volumes_bytes + active_build_cache;
    }

    // -------------------------------------------------------------------------
    // Targeted Safe Pruning Actions
    // -------------------------------------------------------------------------

    /// Prunes untagged intermediate image layers (`<none>:<none>`). 100% safe.
    pub fn prune_dangling_images(home_path: &Path) -> DockerPruneResult {
        if let Some(sock) = Self::discover_socket(home_path) {
            if let Ok(res) = Self::send_socket_prune(
                &sock,
                "/images/prune?filters=%7B%22dangling%22%3A%5B%22true%22%5D%7D",
            ) {
                let reclaimed = res.get("SpaceReclaimed").and_then(|v| v.as_u64()).unwrap_or(0);
                return DockerPruneResult {
                    success: true,
                    reclaimed_bytes: reclaimed,
                    message: "Dangling image layers pruned successfully.".to_string(),
                };
            }
        }

        // Fallback to CLI
        let output = Command::new("docker")
            .args(["image", "prune", "-f"])
            .output();

        match output {
            Ok(out) if out.status.success() => DockerPruneResult {
                success: true,
                reclaimed_bytes: 0,
                message: "Dangling image layers pruned via Docker CLI.".to_string(),
            },
            Ok(out) => DockerPruneResult {
                success: false,
                reclaimed_bytes: 0,
                message: String::from_utf8_lossy(&out.stderr).to_string(),
            },
            Err(e) => DockerPruneResult {
                success: false,
                reclaimed_bytes: 0,
                message: format!("CLI execution failed: {}", e),
            },
        }
    }

    /// Prunes all unused images (both dangling and tagged images not currently attached).
    pub fn prune_unused_images(home_path: &Path) -> DockerPruneResult {
        if let Some(sock) = Self::discover_socket(home_path) {
            if let Ok(res) = Self::send_socket_prune(&sock, "/images/prune") {
                let reclaimed = res.get("SpaceReclaimed").and_then(|v| v.as_u64()).unwrap_or(0);
                return DockerPruneResult {
                    success: true,
                    reclaimed_bytes: reclaimed,
                    message: "All unused images pruned successfully.".to_string(),
                };
            }
        }

        let output = Command::new("docker")
            .args(["image", "prune", "-a", "-f"])
            .output();

        match output {
            Ok(out) if out.status.success() => DockerPruneResult {
                success: true,
                reclaimed_bytes: 0,
                message: "All unused images pruned via Docker CLI.".to_string(),
            },
            Ok(out) => DockerPruneResult {
                success: false,
                reclaimed_bytes: 0,
                message: String::from_utf8_lossy(&out.stderr).to_string(),
            },
            Err(e) => DockerPruneResult {
                success: false,
                reclaimed_bytes: 0,
                message: format!("CLI execution failed: {}", e),
            },
        }
    }

    /// Prunes dangling anonymous volumes (64-character hash residue).
    pub fn prune_anonymous_volumes(home_path: &Path) -> DockerPruneResult {
        // Query inspector to identify anonymous volume names
        let summary = Self::inspect(home_path);
        let anon_names: Vec<String> = summary
            .volumes
            .into_iter()
            .filter(|v| v.is_anonymous && !v.in_use)
            .map(|v| v.name)
            .collect();

        if anon_names.is_empty() {
            return DockerPruneResult {
                success: true,
                reclaimed_bytes: 0,
                message: "No unattached anonymous volumes found to prune.".to_string(),
            };
        }

        let mut deleted_count = 0;
        let total_reclaimed = 0;

        for name in &anon_names {
            let output = Command::new("docker")
                .args(["volume", "rm", name])
                .output();
            if let Ok(out) = output {
                if out.status.success() {
                    deleted_count += 1;
                }
            }
        }

        DockerPruneResult {
            success: true,
            reclaimed_bytes: total_reclaimed,
            message: format!("Pruned {} dangling anonymous volume(s).", deleted_count),
        }
    }

    /// Prunes all unattached volumes (both anonymous and named).
    pub fn prune_all_unattached_volumes(home_path: &Path) -> DockerPruneResult {
        if let Some(sock) = Self::discover_socket(home_path) {
            if let Ok(res) = Self::send_socket_prune(&sock, "/volumes/prune") {
                let reclaimed = res.get("SpaceReclaimed").and_then(|v| v.as_u64()).unwrap_or(0);
                return DockerPruneResult {
                    success: true,
                    reclaimed_bytes: reclaimed,
                    message: "All unattached volumes pruned successfully.".to_string(),
                };
            }
        }

        let output = Command::new("docker")
            .args(["volume", "prune", "-f"])
            .output();

        match output {
            Ok(out) if out.status.success() => DockerPruneResult {
                success: true,
                reclaimed_bytes: 0,
                message: "All unattached volumes pruned via Docker CLI.".to_string(),
            },
            Ok(out) => DockerPruneResult {
                success: false,
                reclaimed_bytes: 0,
                message: String::from_utf8_lossy(&out.stderr).to_string(),
            },
            Err(e) => DockerPruneResult {
                success: false,
                reclaimed_bytes: 0,
                message: format!("CLI execution failed: {}", e),
            },
        }
    }

    /// Prunes BuildKit build cache stages.
    pub fn prune_build_cache(home_path: &Path) -> DockerPruneResult {
        if let Some(sock) = Self::discover_socket(home_path) {
            if let Ok(res) = Self::send_socket_prune(&sock, "/build/prune") {
                let reclaimed = res.get("SpaceReclaimed").and_then(|v| v.as_u64()).unwrap_or(0);
                return DockerPruneResult {
                    success: true,
                    reclaimed_bytes: reclaimed,
                    message: "BuildKit build cache pruned successfully.".to_string(),
                };
            }
        }

        let output = Command::new("docker")
            .args(["builder", "prune", "-f"])
            .output();

        match output {
            Ok(out) if out.status.success() => DockerPruneResult {
                success: true,
                reclaimed_bytes: 0,
                message: "BuildKit build cache pruned via Docker CLI.".to_string(),
            },
            Ok(out) => DockerPruneResult {
                success: false,
                reclaimed_bytes: 0,
                message: String::from_utf8_lossy(&out.stderr).to_string(),
            },
            Err(e) => DockerPruneResult {
                success: false,
                reclaimed_bytes: 0,
                message: format!("CLI execution failed: {}", e),
            },
        }
    }

    /// Prunes stopped and exited containers.
    pub fn prune_stopped_containers(home_path: &Path) -> DockerPruneResult {
        if let Some(sock) = Self::discover_socket(home_path) {
            if let Ok(res) = Self::send_socket_prune(&sock, "/containers/prune") {
                let reclaimed = res.get("SpaceReclaimed").and_then(|v| v.as_u64()).unwrap_or(0);
                return DockerPruneResult {
                    success: true,
                    reclaimed_bytes: reclaimed,
                    message: "Stopped containers pruned successfully.".to_string(),
                };
            }
        }

        let output = Command::new("docker")
            .args(["container", "prune", "-f"])
            .output();

        match output {
            Ok(out) if out.status.success() => DockerPruneResult {
                success: true,
                reclaimed_bytes: 0,
                message: "Stopped containers pruned via Docker CLI.".to_string(),
            },
            Ok(out) => DockerPruneResult {
                success: false,
                reclaimed_bytes: 0,
                message: String::from_utf8_lossy(&out.stderr).to_string(),
            },
            Err(e) => DockerPruneResult {
                success: false,
                reclaimed_bytes: 0,
                message: format!("CLI execution failed: {}", e),
            },
        }
    }

    /// Comprehensive system prune (`docker system prune -a --volumes -f`).
    pub fn prune_system_all(_home_path: &Path) -> DockerPruneResult {
        let output = Command::new("docker")
            .args(["system", "prune", "-a", "--volumes", "-f"])
            .output();

        match output {
            Ok(out) if out.status.success() => DockerPruneResult {
                success: true,
                reclaimed_bytes: 0,
                message: "Docker system fully pruned via Docker CLI.".to_string(),
            },
            Ok(out) => DockerPruneResult {
                success: false,
                reclaimed_bytes: 0,
                message: String::from_utf8_lossy(&out.stderr).to_string(),
            },
            Err(e) => DockerPruneResult {
                success: false,
                reclaimed_bytes: 0,
                message: format!("CLI execution failed: {}", e),
            },
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_docker_vm_disk_detection() {
        let temp = std::env::temp_dir().join("velora_test_docker_disks");
        let _ = fs::remove_dir_all(&temp);
        let docker_raw_dir = temp.join("Library/Containers/com.docker.docker/Data/vms/0/data");
        fs::create_dir_all(&docker_raw_dir).unwrap();

        let raw_file = docker_raw_dir.join("Docker.raw");
        fs::write(&raw_file, vec![0u8; 1024]).unwrap();

        let disks = DockerInspector::detect_vm_disks(&temp);
        assert_eq!(disks.len(), 1);
        assert_eq!(disks[0].engine, DockerEngineKind::DockerDesktop);
        assert_eq!(disks[0].virtual_capacity_bytes, 1024);

        let _ = fs::remove_dir_all(&temp);
    }

    #[test]
    fn test_populate_from_df_json() {
        let mock_json = serde_json::json!({
            "Images": [
                {
                    "Id": "sha256:1234567890abcdef1234567890abcdef",
                    "RepoTags": ["<none>:<none>"],
                    "Size": 1000000,
                    "Containers": 0,
                    "SharedSize": 0,
                    "Created": 1600000000
                },
                {
                    "Id": "sha256:abcdef1234567890abcdef1234567890",
                    "RepoTags": ["myapp:latest"],
                    "Size": 2000000,
                    "Containers": 1,
                    "SharedSize": 500000,
                    "Created": 1600000100
                }
            ],
            "Volumes": [
                {
                    "Name": "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef",
                    "Driver": "local",
                    "UsageData": {
                        "Size": 5000000,
                        "RefCount": 0
                    }
                },
                {
                    "Name": "postgres_data",
                    "Driver": "local",
                    "UsageData": {
                        "Size": 15000000,
                        "RefCount": 1
                    }
                }
            ],
            "BuildCache": [
                {
                    "ID": "build1",
                    "Type": "regular",
                    "Description": "pip install",
                    "Size": 3000000,
                    "InUse": false,
                    "Shared": false
                }
            ],
            "Containers": [
                {
                    "Id": "cnt1",
                    "Names": ["/web_app"],
                    "Image": "myapp:latest",
                    "State": "running",
                    "SizeRw": 4096
                },
                {
                    "Id": "cnt2",
                    "Names": ["/old_job"],
                    "Image": "busybox",
                    "State": "exited",
                    "SizeRw": 20480
                }
            ]
        });

        let mut summary = DockerStorageSummary::default();
        summary.total_host_allocated_bytes = 50_000_000;
        DockerInspector::populate_from_df_json(&mut summary, &mock_json);

        assert_eq!(summary.images.len(), 2);
        assert_eq!(summary.dangling_images_bytes, 1000000);
        assert_eq!(summary.images_total_bytes, 3000000);

        assert_eq!(summary.volumes.len(), 2);
        assert_eq!(summary.dangling_anonymous_volumes_bytes, 5000000);
        assert_eq!(summary.volumes_total_bytes, 20000000);

        assert_eq!(summary.build_cache.len(), 1);
        assert_eq!(summary.build_cache_reclaimable_bytes, 3000000);

        assert_eq!(summary.containers.len(), 2);
        assert_eq!(summary.stopped_containers_bytes, 20480);

        // Active guest bytes:
        // Active images (3M - 1M = 2M)
        // Active volumes (20M - 5M = 15M)
        // Active build cache (3M - 3M = 0)
        // Total = 17,000,000
        assert_eq!(summary.total_guest_active_bytes, 17_000_000);

        // Phantom bloat: 50,000,000 - 17,000,000 = 33,000,000
        summary.phantom_bloat_bytes = summary
            .total_host_allocated_bytes
            .saturating_sub(summary.total_guest_active_bytes);
        assert_eq!(summary.phantom_bloat_bytes, 33_000_000);
    }
}
