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
