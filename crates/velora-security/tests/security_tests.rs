use std::path::Path;
use velora_index::{FileFlags, FileRecord, VolumeIndex};
use velora_security::codesign::CodeSignVerifier;
use velora_security::model::{SigningStatus, ThreatCategory};
use velora_security::threat_db::ThreatDatabase;
use velora_security::triage::{CandidateKind, SecurityTriage};

#[test]
fn test_threat_database_lookups() {
    let db = ThreatDatabase::new();

    // Verify known AMOS hash lookup
    let amos = db.lookup_hash("7f9f3c1d4a0b2e8c6d4e5f6a7b8c9d0e1f2a3b4c5d6e7f8a9b0c1d2e3f4a5b6c");
    assert!(amos.is_some());
    let def = amos.unwrap();
    assert_eq!(def.name, "Atomic Stealer (AMOS)");
    assert_eq!(def.category, ThreatCategory::InfoStealer);

    // Verify known label lookup
    let label = db.lookup_label("com.SearchMine.agent.plist");
    assert!(label.is_some());
    assert_eq!(label.unwrap().name, "SearchMine Browser Hijacker");
}

#[test]
fn test_codesign_verifier_on_system_binary() {
    let zsh_path = Path::new("/bin/zsh");
    if zsh_path.exists() {
        let status = CodeSignVerifier::verify(zsh_path);
        assert!(
            matches!(status, SigningStatus::AppleInternal | SigningStatus::DeveloperIdSigned { .. }),
            "Expected /bin/zsh to be verified as trusted Apple binary, got: {:?}", status
        );
        assert!(status.is_trusted());
    }
}

#[test]
fn test_in_memory_triage_zero_io() {
    let mut vol = VolumeIndex::new("Macintosh HD", "/");

    // 1. Insert fake home root
    let (h_off, h_len) = vol.pool.push("/Users/testuser");
    let home_id = vol.dirs.insert(h_off, h_len, None);

    // 2. Insert fake ~/Library/LaunchAgents
    let (la_off, la_len) = vol.pool.push("/Users/testuser/Library/LaunchAgents");
    let la_id = vol.dirs.insert(la_off, la_len, None);

    // Add LaunchAgent plist
    let (p_off, p_len) = vol.pool.push("com.suspicious.miner.plist");
    vol.add_file(FileRecord::new(
        p_off,
        p_len,
        FileFlags::empty(),
        la_id,
        512,
        1700000000,
    ));

    // Add normal document (should NOT be triaged)
    let (d_off, d_len) = vol.pool.push("my_notes.txt");
    vol.add_file(FileRecord::new(
        d_off,
        d_len,
        FileFlags::empty(),
        home_id,
        2048,
        1700000000,
    ));

    // Add deceptive double extension
    let (de_off, de_len) = vol.pool.push("Salary_Slip.pdf.app");
    vol.add_file(FileRecord::new(
        de_off,
        de_len,
        FileFlags::empty(),
        home_id,
        4096,
        1700000000,
    ));

    let candidates = SecurityTriage::triage_candidates(&vol, Path::new("/Users/testuser"));

    assert_eq!(candidates.len(), 2);
    assert!(candidates.iter().any(|c| c.name == "com.suspicious.miner.plist" && c.kind == CandidateKind::LaunchAgentPlist));
    assert!(candidates.iter().any(|c| c.name == "Salary_Slip.pdf.app" && c.kind == CandidateKind::SuspiciousDoubleExtension));
}

#[test]
fn test_quarantine_and_restore_cycle() {
    use std::fs;
    use std::os::unix::fs::PermissionsExt;
    use velora_security::quarantine::QuarantineVault;

    let temp_dir = std::env::temp_dir().join(format!("velora_sec_test_{}", std::process::id()));
    let _ = fs::remove_dir_all(&temp_dir);
    fs::create_dir_all(&temp_dir).unwrap();

    let target_bin = temp_dir.join("evil_miner");
    fs::write(&target_bin, b"#!/bin/sh\necho mining").unwrap();
    fs::set_permissions(&target_bin, fs::Permissions::from_mode(0o755)).unwrap();

    let assoc_plist = temp_dir.join("evil_miner.plist");
    fs::write(&assoc_plist, b"<plist><dict></dict></plist>").unwrap();

    let vault = QuarantineVault::new(&temp_dir);
    let entry = vault
        .quarantine(
            "threat_test_1",
            &target_bin,
            &[assoc_plist.to_string_lossy().to_string()],
        )
        .expect("Quarantine should succeed");

    // Verify original paths are moved
    assert!(!target_bin.exists(), "Target binary should be moved to vault");
    assert!(!assoc_plist.exists(), "Associated plist should be moved to vault");

    // Verify quarantined file has 000 permissions
    let q_meta = fs::metadata(&entry.quarantined_path).unwrap();
    assert_eq!(
        q_meta.permissions().mode() & 0o777,
        0o000,
        "Quarantined item must have 000 permissions"
    );

    // Test restore
    let restored = vault.restore(&entry.id).expect("Restore should succeed");
    assert!(restored, "Expected restore to return true");

    // Verify both items are restored
    assert!(target_bin.exists(), "Target binary must be restored to original path");
    assert!(assoc_plist.exists(), "Associated plist must be restored to original path");

    let restored_meta = fs::metadata(&target_bin).unwrap();
    assert_eq!(
        restored_meta.permissions().mode() & 0o777,
        0o755,
        "Original mode 0755 must be restored"
    );

    let _ = fs::remove_dir_all(&temp_dir);
}
