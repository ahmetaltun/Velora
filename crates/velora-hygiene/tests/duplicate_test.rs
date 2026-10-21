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

    // 5. File F: Same size (10,000 bytes) and identical first 4KB, but differing suffix -> eliminated by Tier 2 sparse probe
    let mut content_f = vec![0xAB; 10_000];
    for b in &mut content_f[6_000..10_000] {
        *b = 0xFE;
    }
    let file_f_path = temp.join("file_f.bin");
    fs::write(&file_f_path, &content_f).unwrap();

    let (ff_off, ff_len) = volume.pool.push("file_f.bin");
    volume.add_file(FileRecord::new(ff_off, ff_len, FileFlags::empty(), dup_dir, 10_000, 6000));

    // 6. File Symlink: Points to file_a.bin, has identical size, but marked IS_SYMLINK -> eliminated by Tier 1
    let sym_path = temp.join("file_symlink.bin");
    #[cfg(unix)]
    let _ = std::os::unix::fs::symlink(&file_a_path, &sym_path);
    let (fsym_off, fsym_len) = volume.pool.push("file_symlink.bin");
    volume.add_file(FileRecord::new(fsym_off, fsym_len, FileFlags::IS_SYMLINK, dup_dir, 10_000, 7000));

    // 7. File inside .app bundle: Points to a bundle resource with identical size & content -> protected & excluded
    let app_bundle_dir = temp.join("TestApp.app");
    fs::create_dir_all(&app_bundle_dir).unwrap();
    let bundle_file = app_bundle_dir.join("asset.bin");
    fs::write(&bundle_file, &content_ab).unwrap();

    let (app_off, app_len) = volume.pool.push("TestApp.app");
    let app_dir = volume.dirs.insert(app_off, app_len, Some(dup_dir));
    let (bf_off, bf_len) = volume.pool.push("asset.bin");
    volume.add_file(FileRecord::new(bf_off, bf_len, FileFlags::empty(), app_dir, 10_000, 8000));

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

#[test]
fn test_lockstep_early_abort_internal_mismatch() {
    let temp = std::env::temp_dir().join("velora_test_dups_abort");
    let _ = fs::remove_dir_all(&temp);
    fs::create_dir_all(&temp).unwrap();

    let mut volume = VolumeIndex::new("Macintosh HD", "/");
    let (d_off, d_len) = volume.pool.push(temp.to_str().unwrap().trim_start_matches('/'));
    let dup_dir = volume.dirs.insert(d_off, d_len, None);

    // Two 200,000 byte files
    // File G and File H: identical prefix (0..4096), identical suffix (195904..200000), identical midpoint (98000..102000)
    // But they differ at byte 80,000
    let data_g = vec![0x77; 200_000];
    let mut data_h = vec![0x77; 200_000];
    data_h[80_000] = 0x99; // Differing byte between midpoint and prefix

    let file_g_path = temp.join("file_g.bin");
    let file_h_path = temp.join("file_h.bin");
    fs::write(&file_g_path, &data_g).unwrap();
    fs::write(&file_h_path, &data_h).unwrap();

    let (fg_off, fg_len) = volume.pool.push("file_g.bin");
    volume.add_file(FileRecord::new(fg_off, fg_len, FileFlags::empty(), dup_dir, 200_000, 100));

    let (fh_off, fh_len) = volume.pool.push("file_h.bin");
    volume.add_file(FileRecord::new(fh_off, fh_len, FileFlags::empty(), dup_dir, 200_000, 200));

    let summary = DuplicateFinder::find_duplicates(&volume, 1_000);

    // They should NOT be confirmed as duplicates
    assert_eq!(summary.total_duplicate_groups, 0);
    assert_eq!(summary.total_duplicate_files, 0);

    let _ = fs::remove_dir_all(&temp);
}

#[test]
fn test_hardlink_deduplication() {
    let temp = std::env::temp_dir().join("velora_test_dups_hardlink");
    let _ = fs::remove_dir_all(&temp);
    fs::create_dir_all(&temp).unwrap();

    let mut volume = VolumeIndex::new("Macintosh HD", "/");
    let (d_off, d_len) = volume.pool.push(temp.to_str().unwrap().trim_start_matches('/'));
    let dup_dir = volume.dirs.insert(d_off, d_len, None);

    // 1. Original file: 15,000 bytes
    let content = vec![0x42; 15_000];
    let file_orig = temp.join("orig.bin");
    fs::write(&file_orig, &content).unwrap();

    let (fo_off, fo_len) = volume.pool.push("orig.bin");
    volume.add_file(FileRecord::new(fo_off, fo_len, FileFlags::empty(), dup_dir, 15_000, 100));

    // 2. Hard link to original file: shares same inode, zero extra physical disk space
    let file_hl = temp.join("hl.bin");
    fs::hard_link(&file_orig, &file_hl).unwrap();

    let (fhl_off, fhl_len) = volume.pool.push("hl.bin");
    volume.add_file(FileRecord::new(fhl_off, fhl_len, FileFlags::empty(), dup_dir, 15_000, 200));

    // Pure hardlink case: exactly 1 file with hardlinks -> 0 duplicate groups, 0 wasted space
    let summary_hl_only = DuplicateFinder::find_duplicates(&volume, 1_000);
    assert_eq!(summary_hl_only.total_duplicate_groups, 0);
    assert_eq!(summary_hl_only.total_duplicate_files, 0);
    assert_eq!(summary_hl_only.total_wasted_bytes, 0);

    // 3. Independent physical copy with distinct inode: genuine duplicate wasting 15,000 bytes
    let file_copy = temp.join("copy.bin");
    fs::write(&file_copy, &content).unwrap();

    let (fc_off, fc_len) = volume.pool.push("copy.bin");
    volume.add_file(FileRecord::new(fc_off, fc_len, FileFlags::empty(), dup_dir, 15_000, 300));

    let summary = DuplicateFinder::find_duplicates(&volume, 1_000);
    assert_eq!(summary.total_duplicate_groups, 1);
    assert_eq!(summary.total_duplicate_files, 2); // orig.bin and copy.bin (hl.bin deduplicated!)
    assert_eq!(summary.total_wasted_bytes, 15_000); // Only 1 duplicate wasted

    let _ = fs::remove_dir_all(&temp);
}
