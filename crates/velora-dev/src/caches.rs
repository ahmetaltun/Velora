use crate::docker::DockerInspector;
use crate::model::{CacheEcosystem, PackageCacheItem, PackageCacheSummary};
use std::fs;
use std::path::{Path, PathBuf};
use std::process::Command;
use velora_analyzer::SizeRollup;
use velora_index::VolumeIndex;

pub struct PackageCacheScanner;

struct CacheTarget {
    name: &'static str,
    relative_path: &'static str,
    ecosystem: CacheEcosystem,
    can_collect: bool,
}

const TARGETS: &[CacheTarget] = &[
    // Homebrew
    CacheTarget {
        name: "Homebrew Bottles & Downloads",
        relative_path: "Library/Caches/Homebrew",
        ecosystem: CacheEcosystem::Homebrew,
        can_collect: true,
    },
    // Rust (Cargo)
    CacheTarget {
        name: "Cargo Crate Archives Cache",
        relative_path: ".cargo/registry/cache",
        ecosystem: CacheEcosystem::RustCargo,
        can_collect: true,
    },
    CacheTarget {
        name: "Cargo Git Clones Cache",
        relative_path: ".cargo/git/checkouts",
        ecosystem: CacheEcosystem::RustCargo,
        can_collect: true,
    },
    // Node.js
    CacheTarget {
        name: "NPM Global Cache",
        relative_path: ".npm",
        ecosystem: CacheEcosystem::NodeNpm,
        can_collect: true,
    },
    CacheTarget {
        name: "Yarn Global Cache",
        relative_path: "Library/Caches/Yarn",
        ecosystem: CacheEcosystem::NodeNpm,
        can_collect: true,
    },
    CacheTarget {
        name: "PNPM Store",
        relative_path: "Library/pnpm/store",
        ecosystem: CacheEcosystem::NodeNpm,
        can_collect: true,
    },
    // Python
    CacheTarget {
        name: "Pip Wheel & Download Cache",
        relative_path: "Library/Caches/pip",
        ecosystem: CacheEcosystem::PythonPip,
        can_collect: true,
    },
    CacheTarget {
        name: "UV Package Cache",
        relative_path: ".cache/uv",
        ecosystem: CacheEcosystem::PythonPip,
        can_collect: true,
    },
    // JVM / Gradle / Maven
    CacheTarget {
        name: "Gradle Dependency & Wrapper Cache",
        relative_path: ".gradle/caches",
        ecosystem: CacheEcosystem::JvmGradle,
        can_collect: true,
    },
    CacheTarget {
        name: "Maven Local Repository Cache",
        relative_path: ".m2/repository",
        ecosystem: CacheEcosystem::JvmGradle,
        can_collect: true,
    },
    // Go
    CacheTarget {
        name: "Go Build Cache",
        relative_path: "Library/Caches/go-build",
        ecosystem: CacheEcosystem::Golang,
        can_collect: true,
    },
    CacheTarget {
        name: "Go Module Cache",
        relative_path: "go/pkg/mod/cache",
        ecosystem: CacheEcosystem::Golang,
        can_collect: true,
    },
    // CocoaPods
    CacheTarget {
        name: "CocoaPods Specs & Pod Cache",
        relative_path: "Library/Caches/CocoaPods",
        ecosystem: CacheEcosystem::AppleCocoaPods,
        can_collect: true,
    },
    // Docker & Container Runtimes
    CacheTarget {
        name: "Docker Virtual Machine Disk",
        relative_path: "Library/Containers/com.docker.docker/Data/vms/0/data/Docker.raw",
        ecosystem: CacheEcosystem::Docker,
        can_collect: false, // Don't move active VM raw disk to trash directly
    },
    CacheTarget {
        name: "OrbStack Container Machine Disk",
        relative_path: ".orbstack/data/docker.img",
        ecosystem: CacheEcosystem::Docker,
        can_collect: false,
    },
    CacheTarget {
        name: "Colima Machine Disk",
        relative_path: ".colima/default/diffdisk.qcow2",
        ecosystem: CacheEcosystem::Docker,
        can_collect: false,
    },
];

impl PackageCacheScanner {
    /// Discovers and measures all package manager and developer tool caches under the user's home directory.
    /// When a populated `VolumeIndex` is provided, queries memory/catalog.bin for package caches.
    /// VM disk sizes are refreshed from host allocation metadata, matching Docker Deep Inspection.
    pub fn scan_home(home_path: &Path, volume: Option<&VolumeIndex>) -> PackageCacheSummary {
        let mut summary = if let Some(vol) = volume.filter(|v| v.total_files() > 0) {
            Self::scan_from_volume(home_path, vol)
        } else {
            Self::scan_from_disk(home_path)
        };

        // Catalog lengths describe virtual capacity, not space occupied by sparse VM disks.
        let vm_disks = DockerInspector::detect_vm_disks(home_path);
        summary.items.retain_mut(|item| {
            if item.ecosystem != CacheEcosystem::Docker {
                return true;
            }
            if let Some(disk) = vm_disks.iter().find(|disk| disk.path == item.path) {
                item.size_bytes = disk.allocated_bytes;
                item.modified_secs = disk.modified_secs;
                true
            } else {
                // An unavailable disk cannot be measured; never present its capacity as disk usage.
                false
            }
        });
        summary.total_bytes = summary.items.iter().map(|item| item.size_bytes).sum();
        summary
            .items
            .sort_by(|a, b| b.size_bytes.cmp(&a.size_bytes));
        summary
    }

    fn scan_from_volume(home_path: &Path, volume: &VolumeIndex) -> PackageCacheSummary {
        let rollup = SizeRollup::compute(volume);
        let mut summary = PackageCacheSummary::default();

        for target in TARGETS {
            let full_path = home_path.join(target.relative_path);

            if let Some(dir_id) = volume.find_dir_by_path(&full_path) {
                let size_bytes = rollup.get_size(dir_id);
                if size_bytes == 0 {
                    continue;
                }
                let path = volume.build_dir_path(dir_id);
                let modified_secs = volume.get_dir_modified_secs(dir_id);

                summary.total_bytes += size_bytes;
                summary.items.push(PackageCacheItem {
                    name: target.name.to_string(),
                    path,
                    ecosystem: target.ecosystem,
                    size_bytes,
                    modified_secs,
                    color_hex: target.ecosystem.color_hex().to_string(),
                    can_collect: target.can_collect,
                });
            } else {
                // If it's a single file (e.g. Docker.raw), check volume records
                let clean_full = full_path
                    .to_string_lossy()
                    .trim_end_matches('/')
                    .to_string();
                if let Some(parent_path) = full_path.parent() {
                    if let Some(parent_id) = volume.find_dir_by_path(parent_path) {
                        let file_name =
                            full_path.file_name().and_then(|f| f.to_str()).unwrap_or("");
                        for rec in &volume.records {
                            if !rec.is_deleted() && !rec.is_dir() && rec.parent_dir == parent_id {
                                if volume.get_file_name(rec) == file_name && rec.size > 0 {
                                    summary.total_bytes += rec.size;
                                    summary.items.push(PackageCacheItem {
                                        name: target.name.to_string(),
                                        path: clean_full.clone(),
                                        ecosystem: target.ecosystem,
                                        size_bytes: rec.size,
                                        modified_secs: rec.modified_secs,
                                        color_hex: target.ecosystem.color_hex().to_string(),
                                        can_collect: target.can_collect,
                                    });
                                    break;
                                }
                            }
                        }
                    }
                }
            }
        }

        // Sort largest caches first
        summary
            .items
            .sort_by(|a, b| b.size_bytes.cmp(&a.size_bytes));
        summary
    }

    fn scan_from_disk(home_path: &Path) -> PackageCacheSummary {
        let mut summary = PackageCacheSummary::default();

        for target in TARGETS {
            let full_path = home_path.join(target.relative_path);
            if !full_path.exists() {
                continue;
            }

            let (size_bytes, modified_secs) = if full_path.is_file() {
                let meta = full_path.metadata().ok();
                let sz = meta.as_ref().map(|m| m.len()).unwrap_or(0);
                let mod_time = meta
                    .and_then(|m| m.modified().ok())
                    .and_then(|t| t.duration_since(std::time::UNIX_EPOCH).ok())
                    .map(|d| d.as_secs())
                    .unwrap_or(0);
                (sz, mod_time)
            } else {
                let sz = Self::calculate_dir_size(&full_path);
                let mod_time = full_path
                    .metadata()
                    .ok()
                    .and_then(|m| m.modified().ok())
                    .and_then(|t| t.duration_since(std::time::UNIX_EPOCH).ok())
                    .map(|d| d.as_secs())
                    .unwrap_or(0);
                (sz, mod_time)
            };

            if size_bytes == 0 {
                continue;
            }

            summary.total_bytes += size_bytes;
            summary.items.push(PackageCacheItem {
                name: target.name.to_string(),
                path: full_path.to_string_lossy().to_string(),
                ecosystem: target.ecosystem,
                size_bytes,
                modified_secs,
                color_hex: target.ecosystem.color_hex().to_string(),
                can_collect: target.can_collect,
            });
        }

        // Sort largest caches first
        summary
            .items
            .sort_by(|a, b| b.size_bytes.cmp(&a.size_bytes));
        summary
    }

    /// Invokes `docker system prune -f` in user-space if Docker CLI is installed and responsive.
    pub fn prune_docker() -> bool {
        Command::new("docker")
            .arg("system")
            .arg("prune")
            .arg("-f")
            .output()
            .map(|out| out.status.success())
            .unwrap_or(false)
    }

    fn calculate_dir_size(path: &Path) -> u64 {
        let mut total = 0u64;
        let mut stack = vec![PathBuf::from(path)];

        while let Some(current) = stack.pop() {
            if let Ok(entries) = fs::read_dir(&current) {
                for entry_res in entries {
                    if let Ok(entry) = entry_res {
                        let p = entry.path();
                        if p.is_symlink() {
                            continue;
                        }
                        if p.is_dir() {
                            stack.push(p);
                        } else if let Ok(meta) = entry.metadata() {
                            total += meta.len();
                        }
                    }
                }
            }
        }

        total
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::io::Write;
    use velora_index::{FileFlags, FileRecord};

    struct CacheFixture(PathBuf);

    impl Drop for CacheFixture {
        fn drop(&mut self) {
            let _ = fs::remove_dir_all(&self.0);
        }
    }

    fn index_file(volume: &mut VolumeIndex, path: &Path) {
        let mut parent = None;
        let mut current = PathBuf::from("/");
        for component in path.parent().unwrap().components() {
            if let std::path::Component::Normal(name) = component {
                current.push(name);
                let id = volume.find_dir_by_path(&current).unwrap_or_else(|| {
                    let (offset, len) = volume.pool.push(&name.to_string_lossy());
                    volume.dirs.insert(offset, len, parent)
                });
                parent = Some(id);
            }
        }
        let (offset, len) = volume
            .pool
            .push(&path.file_name().unwrap().to_string_lossy());
        volume.add_file(FileRecord::new(
            offset,
            len,
            FileFlags::empty(),
            parent.unwrap(),
            fs::metadata(path).unwrap().len(),
            0,
        ));
    }

    #[test]
    fn sparse_vm_usage_matches_inspector_from_disk_and_saved_catalog() {
        let nonce = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .unwrap()
            .as_nanos();
        let fixture = CacheFixture(std::env::temp_dir().join(format!(
            "velora-sparse-caches-{}-{nonce}",
            std::process::id()
        )));
        let mut volume = VolumeIndex::new("Fixture", "/");
        let cache = fixture.0.join(".cargo/registry/cache/dummy.crate");
        fs::create_dir_all(cache.parent().unwrap()).unwrap();
        fs::write(&cache, vec![0u8; 100_000]).unwrap();
        index_file(&mut volume, &cache);

        for target in TARGETS
            .iter()
            .filter(|target| target.ecosystem == CacheEcosystem::Docker)
        {
            let path = fixture.0.join(target.relative_path);
            fs::create_dir_all(path.parent().unwrap()).unwrap();
            let mut file = fs::File::create(&path).unwrap();
            file.set_len(1_000_000_000_000).unwrap();
            // Also exercise a completely unallocated sparse image.
            if target.relative_path != ".orbstack/data/docker.img" {
                file.write_all(b"allocated data").unwrap();
            }
            file.sync_all().unwrap();
            index_file(&mut volume, &path);
        }
        let snapshot = fixture.0.join("catalog.bin");
        volume.save_snapshot(&snapshot).unwrap();
        let saved = VolumeIndex::load_snapshot(&snapshot).unwrap();
        let disks = DockerInspector::detect_vm_disks(&fixture.0);
        assert_eq!(disks.len(), 3);
        let expected_total = 100_000 + disks.iter().map(|disk| disk.allocated_bytes).sum::<u64>();
        for catalog in [None, Some(&saved)] {
            let summary = PackageCacheScanner::scan_home(&fixture.0, catalog);
            assert_eq!(summary.items.len(), 4);
            assert_eq!(summary.total_bytes, expected_total);
            assert!(summary
                .items
                .windows(2)
                .all(|pair| pair[0].size_bytes >= pair[1].size_bytes));
            assert_eq!(
                summary
                    .items
                    .iter()
                    .find(|item| item.can_collect)
                    .unwrap()
                    .size_bytes,
                100_000
            );
            for disk in &disks {
                let item = summary
                    .items
                    .iter()
                    .find(|item| item.path == disk.path)
                    .unwrap();
                assert_eq!(item.size_bytes, disk.allocated_bytes);
                assert!(item.size_bytes < disk.virtual_capacity_bytes);
                assert_eq!(item.modified_secs, disk.modified_secs);
                assert!(!item.can_collect);
            }
        }

        // A stale catalog must not turn a missing disk's capacity into measured usage.
        fs::remove_file(&disks[0].path).unwrap();
        let summary = PackageCacheScanner::scan_home(&fixture.0, Some(&saved));
        assert!(summary.items.iter().all(|item| item.path != disks[0].path));
        assert_eq!(
            summary.total_bytes,
            expected_total - disks[0].allocated_bytes
        );
    }

    #[test]
    fn test_package_cache_scanner() {
        let temp = std::env::temp_dir().join("velora_test_caches");
        let _ = fs::remove_dir_all(&temp);
        let cargo_cache = temp.join(".cargo/registry/cache");
        fs::create_dir_all(&cargo_cache).unwrap();
        fs::write(cargo_cache.join("dummy.crate"), vec![0u8; 100_000]).unwrap();

        let summary = PackageCacheScanner::scan_home(&temp, None);
        assert_eq!(summary.items.len(), 1);
        assert_eq!(summary.items[0].ecosystem, CacheEcosystem::RustCargo);
        assert_eq!(summary.items[0].size_bytes, 100_000);

        let _ = fs::remove_dir_all(&temp);
    }
}
