use crate::model::{CacheEcosystem, PackageCacheItem, PackageCacheSummary};
use std::fs;
use std::path::{Path, PathBuf};
use std::process::Command;

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
    // Docker
    CacheTarget {
        name: "Docker Virtual Machine Disk",
        relative_path: "Library/Containers/com.docker.docker/Data/vms/0/data/Docker.raw",
        ecosystem: CacheEcosystem::Docker,
        can_collect: false, // Don't move active VM raw disk to trash directly
    },
];

impl PackageCacheScanner {
    /// Discovers and measures all package manager and developer tool caches under the user's home directory.
    pub fn scan_home(home_path: &Path) -> PackageCacheSummary {
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
        summary.items.sort_by(|a, b| b.size_bytes.cmp(&a.size_bytes));
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

    #[test]
    fn test_package_cache_scanner() {
        let temp = std::env::temp_dir().join("velora_test_caches");
        let _ = fs::remove_dir_all(&temp);
        let cargo_cache = temp.join(".cargo/registry/cache");
        fs::create_dir_all(&cargo_cache).unwrap();
        fs::write(cargo_cache.join("dummy.crate"), vec![0u8; 100_000]).unwrap();

        let summary = PackageCacheScanner::scan_home(&temp);
        assert_eq!(summary.items.len(), 1);
        assert_eq!(summary.items[0].ecosystem, CacheEcosystem::RustCargo);
        assert_eq!(summary.items[0].size_bytes, 100_000);

        let _ = fs::remove_dir_all(&temp);
    }
}
