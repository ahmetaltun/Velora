use std::fs;
use velora_hygiene::DuplicateFinder;
use velora_index::{FileFlags, FileRecord, VolumeIndex};

#[test]
fn test_progressive_duplicate_detection() {
    let temp = std::env::temp_dir().join("velora_test_dups");
    let _ = fs::remove_dir_all(&temp);
    fs::create_dir_all(&temp).unwrap();

    let mut volume = VolumeIndex::new("Macintosh HD", "/");
    let (d_off, d_len) = volume.pool.push(temp.to_str().unwrap().trim_start_matches('/'));
    let dup_dir = volume.dirs.insert(d_off, d_len, None);

    // 1. Two genuine duplicates (file A and file B: 10,000 identical bytes)
    let content_ab = vec![0xAB; 10_000];
    let file_a_path = temp.join("file_a.bin");
    let file_b_path = temp.join("file_b.bin");
    fs::write(&file_a_path, &content_ab).unwrap();
    fs::write(&file_b_path, &content_ab).unwrap();

    let (fa_off, fa_len) = volume.pool.push("file_a.bin");
    volume.add_file(FileRecord::new(fa_off, fa_len, FileFlags::empty(), dup_dir, 10_000, 1000));

    let (fb_off, fb_len) = volume.pool.push("file_b.bin");
    volume.add_file(FileRecord::new(fb_off, fb_len, FileFlags::empty(), dup_dir, 10_000, 2000));

    // 2. File C: Same size (10,000 bytes) but different content
    let content_c = vec![0xCC; 10_000];
    let file_c_path = temp.join("file_c.bin");
    fs::write(&file_c_path, &content_c).unwrap();

    let (fc_off, fc_len) = volume.pool.push("file_c.bin");
    volume.add_file(FileRecord::new(fc_off, fc_len, FileFlags::empty(), dup_dir, 10_000, 3000));

    // 3. File D: Unique size (5,000 bytes) -> eliminated by Tier 1
    let content_d = vec![0xDD; 5_000];
    let file_d_path = temp.join("file_d.bin");
    fs::write(&file_d_path, &content_d).unwrap();

    let (fd_off, fd_len) = volume.pool.push("file_d.bin");
    volume.add_file(FileRecord::new(fd_off, fd_len, FileFlags::empty(), dup_dir, 5_000, 4000));

    // 4. File E: Identical to A and B, but marked IS_DELETED -> eliminated by Tier 1
    let file_e_path = temp.join("file_e.bin");
    fs::write(&file_e_path, &content_ab).unwrap();

    let (fe_off, fe_len) = volume.pool.push("file_e.bin");
    volume.add_file(FileRecord::new(fe_off, fe_len, FileFlags::IS_DELETED, dup_dir, 10_000, 5000));

    let summary = DuplicateFinder::find_duplicates(&volume, 1_000);

    assert_eq!(summary.total_duplicate_groups, 1);
    assert_eq!(summary.total_duplicate_files, 2);
    assert_eq!(summary.total_wasted_bytes, 10_000);

    let group = &summary.groups[0];
    assert_eq!(group.file_count, 2);
    assert_eq!(group.size_bytes, 10_000);

    // Oldest file should be marked original
    assert!(group.files[0].is_original);
    assert_eq!(group.files[0].modified_secs, 1000);
    assert!(!group.files[1].is_original);
    assert_eq!(group.files[1].modified_secs, 2000);

    let _ = fs::remove_dir_all(&temp);
}
