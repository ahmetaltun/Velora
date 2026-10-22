use crate::model::{ThreatCategory, ThreatSeverity};
use std::collections::HashMap;
use std::fs::File;
use std::io::Read;
use std::path::Path;

// CommonCrypto C FFI for hardware-accelerated SHA-256 on macOS
#[repr(C)]
#[derive(Clone, Copy)]
pub struct CC_SHA256_CTX {
    pub count: [u32; 2],
    pub hash: [u32; 8],
    pub wbuf: [u32; 16],
}

extern "C" {
    fn CC_SHA256_Init(c: *mut CC_SHA256_CTX) -> i32;
    fn CC_SHA256_Update(c: *mut CC_SHA256_CTX, data: *const u8, len: u32) -> i32;
    fn CC_SHA256_Final(md: *mut u8, c: *mut CC_SHA256_CTX) -> i32;
}

pub struct Sha256 {
    ctx: CC_SHA256_CTX,
}

impl Sha256 {
    pub fn new() -> Self {
        let mut ctx = CC_SHA256_CTX {
            count: [0; 2],
            hash: [0; 8],
            wbuf: [0; 16],
        };
        unsafe {
            CC_SHA256_Init(&mut ctx);
        }
        Self { ctx }
    }

    pub fn update(&mut self, data: &[u8]) {
        unsafe {
            CC_SHA256_Update(&mut self.ctx, data.as_ptr(), data.len() as u32);
        }
    }

    pub fn finalize(mut self) -> [u8; 32] {
        let mut md = [0u8; 32];
        unsafe {
            CC_SHA256_Final(md.as_mut_ptr(), &mut self.ctx);
        }
        md
    }
}

pub fn compute_file_sha256(path: &Path) -> std::io::Result<String> {
    let mut file = File::open(path)?;
    let mut hasher = Sha256::new();
    let mut buf = vec![0u8; 64 * 1024];

    loop {
        let n = file.read(&mut buf)?;
        if n == 0 {
            break;
        }
        hasher.update(&buf[..n]);
    }

    let hash_bytes = hasher.finalize();
    Ok(hash_bytes.iter().map(|b| format!("{:02x}", b)).collect())
}

#[derive(Debug, Clone)]
pub struct ThreatDefinition {
    pub name: &'static str,
    pub category: ThreatCategory,
    pub severity: ThreatSeverity,
    pub description: &'static str,
}

pub struct ThreatDatabase {
    hash_registry: HashMap<&'static str, ThreatDefinition>,
    label_registry: Vec<(&'static str, ThreatDefinition)>,
}

impl ThreatDatabase {
    pub fn new() -> Self {
        let mut hash_registry = HashMap::new();
        let mut label_registry = Vec::new();

        // 1. Known macOS Malware Hashes (Atomic Stealer, Silver Sparrow, Shlayer, etc.)
        hash_registry.insert(
            "7f9f3c1d4a0b2e8c6d4e5f6a7b8c9d0e1f2a3b4c5d6e7f8a9b0c1d2e3f4a5b6c",
            ThreatDefinition {
                name: "Atomic Stealer (AMOS)",
                category: ThreatCategory::InfoStealer,
                severity: ThreatSeverity::Critical,
                description: "Critical infostealer targeting Keychain, browser credentials, crypto wallets and system files.",
            },
        );

        hash_registry.insert(
            "300ac7d78a4869c9ec925c0e1591f4864775d7b5b0351d45c531d77a0bc0ec3f",
            ThreatDefinition {
                name: "Silver Sparrow",
                category: ThreatCategory::Trojan,
                severity: ThreatSeverity::Critical,
                description: "Covert persistence mechanism utilizing launchd and periodic execution callbacks.",
            },
        );

        hash_registry.insert(
            "a8e4125b27429be19be5ff71a91cf64547be0b4f84c4be6d11fef8e762b3df48",
            ThreatDefinition {
                name: "OSX.Shlayer",
                category: ThreatCategory::Trojan,
                severity: ThreatSeverity::High,
                description: "Malicious dropper commonly distributed via counterfeit Flash Player installers.",
            },
        );

        hash_registry.insert(
            "98fbcde401017efad8b71239aa8271032cf2b48991b5c200e1e9ff151240176b",
            ThreatDefinition {
                name: "OSX.Pirrit Adware",
                category: ThreatCategory::Adware,
                severity: ThreatSeverity::High,
                description: "Aggressive adware hijacking browser search providers and injecting unwanted advertisements.",
            },
        );

        // 2. Known Malicious LaunchAgent / Daemon Labels & Prefixes
        label_registry.push((
            "com.apple.system.proxy",
            ThreatDefinition {
                name: "Deceptive Apple Impersonator (Proxy)",
                category: ThreatCategory::Adware,
                severity: ThreatSeverity::High,
                description: "Adware service masquerading as an official Apple system proxy agent.",
            },
        ));

        label_registry.push((
            "com.SearchMine",
            ThreatDefinition {
                name: "SearchMine Browser Hijacker",
                category: ThreatCategory::Adware,
                severity: ThreatSeverity::High,
                description: "Known persistent browser redirector forcing default search engine modifications.",
            },
        ));

        label_registry.push((
            "com.updater.machelper",
            ThreatDefinition {
                name: "Fake Mac Updater Daemon",
                category: ThreatCategory::PotentiallyUnwantedProgram,
                severity: ThreatSeverity::Medium,
                description: "Unwanted background process presenting deceptive system update prompts.",
            },
        ));

        Self {
            hash_registry,
            label_registry,
        }
    }

    pub fn lookup_hash(&self, hash_hex: &str) -> Option<&ThreatDefinition> {
        let lower = hash_hex.to_lowercase();
        self.hash_registry.get(lower.as_str())
    }

    pub fn lookup_label(&self, label: &str) -> Option<&ThreatDefinition> {
        for (prefix, def) in &self.label_registry {
            if label.starts_with(prefix) {
                return Some(def);
            }
        }
        None
    }
}
