use std::time::{SystemTime, UNIX_EPOCH};
use velora_hygiene::LargeOldFilesMatrix;
use velora_index::{FileFlags, FileRecord, VolumeIndex};

#[test]
fn test_large_old_files_matrix_computation() {
    let mut volume = VolumeIndex::new("Macintosh HD", "/");
    let (d_off, d_len) = volume.pool.push("Downloads");
    let dl_dir = volume.dirs.insert(d_off, d_len, None);

    let now = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap()
        .as_secs();

    const DAY: u64 = 86_400;

    // 1. Massive ancient file (2 GB, modified 500 days ago)
    let (f1_off, f1_len) = volume.pool.push("backup_2024.iso");
    volume.add_file(FileRecord::new(
        f1_off,
        f1_len,
        FileFlags::empty(),
        dl_dir,
        2_000_000_000,
        now - (500 * DAY),
    ));

    // 2. Huge 6-month file (750 MB, modified 100 days ago)
    let (f2_off, f2_len) = volume.pool.push("video_edit.mov");
    volume.add_file(FileRecord::new(
        f2_off,
        f2_len,
        FileFlags::empty(),
        dl_dir,
        750_000_000,
        now - (100 * DAY),
    ));

    // 3. Medium recent file (80 MB, modified 5 days ago)
    let (f3_off, f3_len) = volume.pool.push("installer.dmg");
    volume.add_file(FileRecord::new(
        f3_off,
        f3_len,
        FileFlags::empty(),
        dl_dir,
        80_000_000,
        now - (5 * DAY),
    ));

    // 4. Small file (10 MB, should be excluded from matrix < 50MB)
    let (f4_off, f4_len) = volume.pool.push("document.pdf");
    volume.add_file(FileRecord::new(
        f4_off,
        f4_len,
        FileFlags::empty(),
        dl_dir,
        10_000_000,
        now - (10 * DAY),
    ));

    // 5. Deleted massive file (should be ignored by tombstone)
    let (f5_off, f5_len) = volume.pool.push("deleted_large.zip");
    volume.add_file(FileRecord::new(
        f5_off,
        f5_len,
        FileFlags::IS_DELETED,
        dl_dir,
        3_000_000_000,
        now - (600 * DAY),
    ));

    let summary = LargeOldFilesMatrix::compute(&volume);

    // Only 3 non-deleted files >= 50MB
    assert_eq!(summary.total_files, 3);
    assert_eq!(summary.total_bytes, 2_000_000_000 + 750_000_000 + 80_000_000);
    assert_eq!(summary.cells.len(), 16);

    // Ancient Gigabytes cell: age 3, size 0 (cell index = 3*4 + 0 = 12)
    let ancient_gb_cell = &summary.cells[12];
    assert_eq!(ancient_gb_cell.age_idx, 3);
    assert_eq!(ancient_gb_cell.size_idx, 0);
    assert_eq!(ancient_gb_cell.file_count, 1);
    assert_eq!(ancient_gb_cell.total_bytes, 2_000_000_000);

    // Recent Medium cell: age 0, size 3 (cell index = 0*4 + 3 = 3)
    let recent_med_cell = &summary.cells[3];
    assert_eq!(recent_med_cell.file_count, 1);
    assert_eq!(recent_med_cell.total_bytes, 80_000_000);

    // Files list should have 3 items
    assert_eq!(summary.files.len(), 3);
    assert_eq!(summary.files[0].name, "backup_2024.iso");
    assert_eq!(summary.files[0].category_name, "Archives");
}
