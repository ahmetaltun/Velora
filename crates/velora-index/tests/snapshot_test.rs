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
