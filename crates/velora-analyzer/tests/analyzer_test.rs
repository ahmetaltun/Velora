use velora_analyzer::{Analyzer, CategoryKind, SizeRollup};
use velora_index::{FileFlags, FileRecord, VolumeIndex};

#[test]
fn test_bottom_up_rollup_and_sunburst() {
    let mut volume = VolumeIndex::new("Macintosh HD", "/");

    // Root -> Users -> ahmet
    let (u_off, u_len) = volume.pool.push("Users");
    let users_dir = volume.dirs.insert(u_off, u_len, None);

    let (a_off, a_len) = volume.pool.push("ahmet");
    let ahmet_dir = volume.dirs.insert(a_off, a_len, Some(users_dir));

    // ahmet/Movies (300 MB)
    let (mov_off, mov_len) = volume.pool.push("Movies");
    let movies_dir = volume.dirs.insert(mov_off, mov_len, Some(ahmet_dir));
    volume.add_file(FileRecord::new(
        mov_off,
        mov_len,
        FileFlags::IS_DIRECTORY,
        ahmet_dir,
        0,
        1700000000,
    ));

    let (vid_off, vid_len) = volume.pool.push("vacation.mov");
    volume.add_file(FileRecord::new(
        vid_off,
        vid_len,
        FileFlags::empty(),
        movies_dir,
        300 * 1024 * 1024,
        1700000000,
    ));

    // ahmet/Projects/target (700 MB, DevCaches)
    let (proj_off, proj_len) = volume.pool.push("Projects");
    let proj_dir = volume.dirs.insert(proj_off, proj_len, Some(ahmet_dir));
    volume.add_file(FileRecord::new(
        proj_off,
        proj_len,
        FileFlags::IS_DIRECTORY,
        ahmet_dir,
        0,
        1700000000,
    ));

    let (tgt_off, tgt_len) = volume.pool.push("target");
    let target_dir = volume.dirs.insert(tgt_off, tgt_len, Some(proj_dir));
    volume.add_file(FileRecord::new(
        tgt_off,
        tgt_len,
        FileFlags::IS_DIRECTORY,
        proj_dir,
        0,
        1700000000,
    ));

    let (bin_off, bin_len) = volume.pool.push("velora_bin");
    volume.add_file(FileRecord::new(
        bin_off,
        bin_len,
        FileFlags::empty(),
        target_dir,
        700 * 1024 * 1024,
        1700000000,
    ));

    // 1. Verify bottom-up size rollup
    let rollup = SizeRollup::compute(&volume);
    assert_eq!(rollup.get_size(target_dir), 700 * 1024 * 1024);
    assert_eq!(rollup.get_size(proj_dir), 700 * 1024 * 1024);
    assert_eq!(rollup.get_size(movies_dir), 300 * 1024 * 1024);
    assert_eq!(rollup.get_size(ahmet_dir), 1000 * 1024 * 1024);
    assert_eq!(rollup.get_size(users_dir), 1000 * 1024 * 1024);

    // 2. Verify Sunburst generation from ahmet_dir
    let sunburst = Analyzer::analyze(&volume, ahmet_dir, 3, 2.0).expect("Sunburst generation failed");
    assert_eq!(sunburst.name, "ahmet");
    assert_eq!(sunburst.size_bytes, 1000 * 1024 * 1024);
    assert_eq!(sunburst.children.len(), 2);

    // Projects (70%) and Movies (30%)
    let proj_sector = &sunburst.children[0];
    assert_eq!(proj_sector.name, "Projects");
    assert!((proj_sector.sweep_angle - 252.0).abs() < 0.1); // 70% of 360 = 252

    let mov_sector = &sunburst.children[1];
    assert_eq!(mov_sector.name, "Movies");
    assert!((mov_sector.sweep_angle - 108.0).abs() < 0.1); // 30% of 360 = 108

    // Verify category classification
    assert_eq!(CategoryKind::classify("target", true), CategoryKind::DevCaches);
    assert_eq!(CategoryKind::classify("vacation.mov", false), CategoryKind::Media);
    assert_eq!(CategoryKind::classify("contract.pdf", false), CategoryKind::Documents);
}
