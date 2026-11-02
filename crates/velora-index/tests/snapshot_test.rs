use velora_index::{FileFlags, FileRecord, VolumeIndex};

#[test]
fn test_save_and_load_offline_snapshot() {
    let temp_dir = std::env::temp_dir();
    let snapshot_file = temp_dir.join("test_samsung_t7.vcat");

    let mut volume = VolumeIndex::new("Samsung T7", "/Volumes/Samsung T7");
    let (d_off, d_len) = volume.pool.push("Photos");
    let photos_dir = volume.dirs.insert(d_off, d_len, None);

    let (f_off, f_len) = volume.pool.push("vacation_japan_2026.heic");
    volume.add_file(FileRecord::new(
        f_off,
        f_len,
        FileFlags::empty(),
        photos_dir,
        12 * 1024 * 1024,
        1740000000,
    ));

    assert!(volume.is_online);
    assert_eq!(volume.total_files(), 1);

    // 1. Save to snapshot
    let save_res = volume.save_snapshot(&snapshot_file);
    assert!(save_res.is_ok());

    // 2. Load from offline snapshot
    let loaded = VolumeIndex::load_snapshot(&snapshot_file).expect("Failed to load snapshot");
    assert!(!loaded.is_online, "Restored volume snapshot should be marked offline");
    assert_eq!(loaded.volume_name, "Samsung T7");
    assert_eq!(loaded.total_files(), 1);

    let record = &loaded.records[0];
    assert_eq!(loaded.get_file_name(record), "vacation_japan_2026.heic");
    assert_eq!(loaded.resolve_full_path(record), "/Photos/vacation_japan_2026.heic");

    let _ = std::fs::remove_file(snapshot_file);
}

#[test]
fn test_tombstone_deletion_and_snapshot() {
    let temp_dir = std::env::temp_dir();
    let snapshot_file = temp_dir.join("test_tombstone.vcat");

    let mut volume = VolumeIndex::new("Macintosh HD", "/");
    let (app_off, app_len) = volume.pool.push("Applications");
    let app_dir = volume.dirs.insert(app_off, app_len, None);

    let (slack_off, slack_len) = volume.pool.push("Slack.app");
    let slack_dir = volume.dirs.insert(slack_off, slack_len, Some(app_dir));

    let (f1_off, f1_len) = volume.pool.push("Slack");
    volume.add_file(FileRecord::new(
        f1_off,
        f1_len,
        FileFlags::empty(),
        slack_dir,
        50_000_000,
        1700000000,
    ));

    let (f2_off, f2_len) = volume.pool.push("Other.app");
    volume.add_file(FileRecord::new(
        f2_off,
        f2_len,
        FileFlags::empty(),
        app_dir,
        20_000_000,
        1700000000,
    ));

    assert_eq!(volume.total_files(), 2);
    assert_eq!(volume.active_files(), 2);
    assert_eq!(volume.active_bytes(), 70_000_000);

    // Delete /Applications/Slack.app directory tree
    let freed = volume.mark_deleted_by_path("/Applications/Slack.app");
    assert_eq!(freed, 50_000_000);
    assert_eq!(volume.total_files(), 2);
    assert_eq!(volume.active_files(), 1);
    assert_eq!(volume.active_bytes(), 20_000_000);

    // Save and reload snapshot to verify tombstone persistence
    volume.save_snapshot(&snapshot_file).unwrap();
    let loaded = VolumeIndex::load_snapshot(&snapshot_file).unwrap();
    assert_eq!(loaded.total_files(), 2);
    assert_eq!(loaded.active_files(), 1);
    assert_eq!(loaded.active_bytes(), 20_000_000);
    assert!(loaded.records[0].is_deleted());
    assert!(!loaded.records[1].is_deleted());

    let _ = std::fs::remove_file(snapshot_file);
}

#[test]
fn test_mark_deleted_batch() {
    let mut volume = VolumeIndex::new("Macintosh HD", "/");
    let (d_off, d_len) = volume.pool.push("Documents");
    let docs_dir = volume.dirs.insert(d_off, d_len, None);

    let (f1_off, f1_len) = volume.pool.push("file1.pdf");
    volume.add_file(FileRecord::new(
        f1_off,
        f1_len,
        FileFlags::empty(),
        docs_dir,
        1000,
        1700000000,
    ));

    let (f2_off, f2_len) = volume.pool.push("file2.pdf");
    volume.add_file(FileRecord::new(
        f2_off,
        f2_len,
        FileFlags::empty(),
        docs_dir,
        2000,
        1700000000,
    ));

    let (f3_off, f3_len) = volume.pool.push("file3.pdf");
    volume.add_file(FileRecord::new(
        f3_off,
        f3_len,
        FileFlags::empty(),
        docs_dir,
        3000,
        1700000000,
    ));

    assert_eq!(volume.active_files(), 3);
    assert_eq!(volume.active_bytes(), 6000);

    let batch = vec![
        "/Documents/file1.pdf".to_string(),
        "/Documents/file3.pdf".to_string(),
    ];
    let freed = volume.mark_deleted_batch(&batch);
    assert_eq!(freed, 4000);
    assert_eq!(volume.active_files(), 1);
    assert_eq!(volume.active_bytes(), 2000);
    assert!(volume.records[0].is_deleted());
    assert!(!volume.records[1].is_deleted());
    assert!(volume.records[2].is_deleted());
}

#[test]
fn test_snapshot_corrupted_payload_detection() {
    let temp_dir = std::env::temp_dir();
    let snapshot_file = temp_dir.join(format!("test_corrupt_{}.vcat", std::process::id()));

    let mut volume = VolumeIndex::new("CorruptTest", "/");
    let (d_off, d_len) = volume.pool.push("Data");
    let dir = volume.dirs.insert(d_off, d_len, None);
    let (f_off, f_len) = volume.pool.push("data.bin");
    volume.add_file(FileRecord::new(
        f_off,
        f_len,
        FileFlags::empty(),
        dir,
        1024,
        1700000000,
    ));

    volume.save_snapshot(&snapshot_file).unwrap();

    // Read bytes and flip one byte in the payload area (after 64-byte header)
    let mut bytes = std::fs::read(&snapshot_file).unwrap();
    assert!(bytes.len() > 66);
    let last = bytes.len() - 1;
    bytes[last] ^= 0xFF; // Corrupt payload byte
    std::fs::write(&snapshot_file, &bytes).unwrap();

    // Loading must fail with checksum mismatch
    let load_res = VolumeIndex::load_snapshot(&snapshot_file);
    assert!(load_res.is_err(), "Corrupted snapshot must fail to load");
    let err = load_res.unwrap_err();
    assert_eq!(err.kind(), std::io::ErrorKind::InvalidData);
    assert!(err.to_string().contains("checksum mismatch"));

    let _ = std::fs::remove_file(snapshot_file);
}

#[test]
fn test_snapshot_invalid_magic_header_rejection() {
    let temp_dir = std::env::temp_dir();
    let bad_file = temp_dir.join(format!("test_bad_magic_{}.vcat", std::process::id()));

    std::fs::write(&bad_file, b"NOT_A_VALID_SNAPSHOT_HEADER_DATA_123456").unwrap();

    let load_res = VolumeIndex::load_snapshot(&bad_file);
    assert!(load_res.is_err(), "Invalid magic header must be rejected");
    let err = load_res.unwrap_err();
    assert_eq!(err.kind(), std::io::ErrorKind::InvalidData);
    assert!(err.to_string().contains("VELORASN"));

    let _ = std::fs::remove_file(bad_file);
}

#[test]
fn test_snapshot_unsupported_version_rejection() {
    let temp_dir = std::env::temp_dir();
    let version_file = temp_dir.join(format!("test_bad_version_{}.vcat", std::process::id()));

    let mut buf = Vec::new();
    buf.extend_from_slice(b"VELORASN"); // Valid magic
    buf.extend_from_slice(&999u32.to_le_bytes()); // Unsupported version 999
    buf.extend_from_slice(&0u32.to_le_bytes()); // Flags
    buf.extend_from_slice(&0u32.to_le_bytes()); // Checksum
    buf.extend_from_slice(&0u64.to_le_bytes()); // Payload len

    std::fs::write(&version_file, &buf).unwrap();

    let load_res = VolumeIndex::load_snapshot(&version_file);
    assert!(load_res.is_err(), "Unsupported version must be rejected");
    let err = load_res.unwrap_err();
    assert_eq!(err.kind(), std::io::ErrorKind::InvalidData);
    assert!(err.to_string().contains("version 999"));

    let _ = std::fs::remove_file(version_file);
}

#[test]
fn test_snapshot_truncated_payload_detection() {
    let temp_dir = std::env::temp_dir();
    let trunc_file = temp_dir.join(format!("test_trunc_{}.vcat", std::process::id()));

    let mut buf = Vec::new();
    buf.extend_from_slice(b"VELORASN"); // Valid magic
    buf.extend_from_slice(&1u32.to_le_bytes()); // Valid version 1
    buf.extend_from_slice(&0u32.to_le_bytes()); // Flags
    buf.extend_from_slice(&12345u32.to_le_bytes()); // Checksum
    buf.extend_from_slice(&100u64.to_le_bytes()); // Claims 100 bytes of payload
    buf.extend_from_slice(b"only_10_by"); // Only 10 bytes provided

    std::fs::write(&trunc_file, &buf).unwrap();

    let load_res = VolumeIndex::load_snapshot(&trunc_file);
    assert!(load_res.is_err(), "Truncated snapshot must be rejected");
    let err = load_res.unwrap_err();
    assert_eq!(err.kind(), std::io::ErrorKind::UnexpectedEof);

    let _ = std::fs::remove_file(trunc_file);
}

#[test]
fn test_v1_legacy_snapshot_backward_compatibility() {
    let temp_dir = std::env::temp_dir();
    let v1_file = temp_dir.join(format!("test_v1_compat_{}.vcat", std::process::id()));

    let mut volume = VolumeIndex::new("LegacyHD", "/");
    let (d_off, d_len) = volume.pool.push("System");
    let sys_dir = volume.dirs.insert(d_off, d_len, None);

    let (f_off, f_len) = volume.pool.push("kernel");
    volume.add_file(FileRecord::new(
        f_off,
        f_len,
        FileFlags::IS_SYSTEM,
        sys_dir,
        4096,
        1700000000,
    ));

    // Manually serialize in legacy V1 Bincode format
    let payload = bincode::serialize(&volume).unwrap();
    let checksum = velora_index::snapshot::compute_crc32(&payload);

    let header = velora_index::snapshot::SnapshotHeaderV1 {
        magic: velora_index::snapshot::SNAPSHOT_MAGIC,
        version: velora_index::snapshot::SNAPSHOT_VERSION_V1,
        flags: 0,
        checksum,
        payload_len: payload.len() as u64,
    };

    let mut file = std::fs::File::create(&v1_file).unwrap();
    header.write_to(&mut file).unwrap();
    std::io::Write::write_all(&mut file, &payload).unwrap();
    drop(file);

    // Verify VolumeIndex::load_snapshot loads legacy V1 transparently
    let loaded = VolumeIndex::load_snapshot(&v1_file).expect("Failed to load V1 snapshot");
    assert_eq!(loaded.volume_name, "LegacyHD");
    assert_eq!(loaded.total_files(), 1);
    let record = &loaded.records[0];
    assert_eq!(loaded.get_file_name(record), "kernel");
    assert_eq!(loaded.resolve_full_path(record), "/System/kernel");
    assert!(record.flags.contains(FileFlags::IS_SYSTEM));

    let _ = std::fs::remove_file(v1_file);
}

#[test]
fn test_large_snapshot_load_performance() {
    let temp_dir = std::env::temp_dir();
    let snapshot_file = temp_dir.join(format!("test_perf_{}.vcat", std::process::id()));

    let mut volume = VolumeIndex::new("Macintosh HD", "/");
    let (d_off, d_len) = volume.pool.push("Library");
    let lib_dir = volume.dirs.insert(d_off, d_len, None);

    let (sub_off, sub_len) = volume.pool.push("Frameworks");
    let fw_dir = volume.dirs.insert(sub_off, sub_len, Some(lib_dir));

    let (f_off, f_len) = volume.pool.push("Foundation.framework");

    let count = if cfg!(debug_assertions) { 100_000 } else { 1_000_000 };
    for i in 0..count {
        volume.add_file(FileRecord::new(
            f_off,
            f_len,
            FileFlags::empty(),
            fw_dir,
            1024 * (i as u64 % 500 + 1),
            1730000000 + i as u64,
        ));
    }

    let t_save = std::time::Instant::now();
    volume.save_snapshot(&snapshot_file).expect("save failed");
    let save_elapsed = t_save.elapsed();

    let meta = std::fs::metadata(&snapshot_file).unwrap();
    let size_mb = meta.len() as f64 / (1024.0 * 1024.0);

    let t_load = std::time::Instant::now();
    let loaded = VolumeIndex::load_snapshot(&snapshot_file).expect("load failed");
    let load_elapsed = t_load.elapsed();

    println!(
        "\n⚡ PERFORMANCE: {} records ({:.2} MB) -> Saved in {:?}, Loaded in {:?}",
        count, size_mb, save_elapsed, load_elapsed
    );

    assert_eq!(loaded.total_files(), count);
    assert_eq!(loaded.records[0].size, volume.records[0].size);

    let _ = std::fs::remove_file(snapshot_file);
}

#[test]
fn test_mark_deleted_batch_scale_performance() {
    let mut volume = VolumeIndex::new("Macintosh HD", "/");
    let (d_off, d_len) = volume.pool.push("Users");
    let users_dir = volume.dirs.insert(d_off, d_len, None);

    let (u_off, u_len) = volume.pool.push("testuser");
    let user_dir = volume.dirs.insert(u_off, u_len, Some(users_dir));

    let (p_off, p_len) = volume.pool.push("Project");
    let proj_dir = volume.dirs.insert(p_off, p_len, Some(user_dir));

    let (readme_off, readme_len) = volume.pool.push("README.md");
    let (dummy_off, dummy_len) = volume.pool.push("dummy.txt");

    let count = 100_000;
    for i in 0..count {
        let (f_off, f_len) = if i == 42 {
            (readme_off, readme_len)
        } else {
            (dummy_off, dummy_len)
        };
        volume.add_file(FileRecord::new(
            f_off,
            f_len,
            FileFlags::empty(),
            proj_dir,
            16_384,
            1730000000 + i as u64,
        ));
    }

    assert_eq!(volume.active_files(), count);

    // Tombstone single file out of 100,000 using batch API
    let t_start = std::time::Instant::now();
    let freed = volume.mark_deleted_batch(&["/Users/testuser/Project/README.md".to_string()]);
    let elapsed = t_start.elapsed();

    println!("\n⚡ BATCH DELETION: 1 out of {} files tombstoned in {:?}", count, elapsed);
    assert_eq!(freed, 16_384);
    assert_eq!(volume.active_files(), count - 1);
    assert!(volume.records[42].is_deleted());
    // High threshold (250ms) to accommodate virtualized shared CI runner variance
    assert!(elapsed.as_millis() < 250, "Batch tombstone should finish quickly (<250ms for 100k items), took {:?}", elapsed);
}
