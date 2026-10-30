use std::path::Path;
use velora_apps::AppManager;
use velora_index::{AppMetadataEntry, FileFlags, FileRecord, VolumeIndex};

#[test]
fn test_index_powered_footprint_resolution() {
    let mut volume = VolumeIndex::new("Macintosh HD", "/");

    // Pre-populate volume.apps so it leverages in-memory metadata without scanning host /Applications
    volume.apps.push(AppMetadataEntry {
        name: "MockApp".to_string(),
        bundle_id: "com.mock.app".to_string(),
        version: "1.0.0".to_string(),
        app_path: "/Applications/MockApp.app".to_string(),
        is_system_app: false,
    });

    // Add /Users/test/Library/Application Support
    let (u_off, u_len) = volume.pool.push("Users");
    let u_dir = volume.dirs.insert(u_off, u_len, None);

    let (t_off, t_len) = volume.pool.push("test");
    let t_dir = volume.dirs.insert(t_off, t_len, Some(u_dir));

    let (l_off, l_len) = volume.pool.push("Library");
    let l_dir = volume.dirs.insert(l_off, l_len, Some(t_dir));

    let (as_off, as_len) = volume.pool.push("Application Support");
    let as_dir = volume.dirs.insert(as_off, as_len, Some(l_dir));

    // Orphan residue folder under Application Support
    let (orph_off, orph_len) = volume.pool.push("com.previouslydeleted.app");
    let orph_dir = volume.dirs.insert(orph_off, orph_len, Some(as_dir));

    let (f1_off, f1_len) = volume.pool.push("database.sqlite");
    volume.add_file(FileRecord::new(
        f1_off,
        f1_len,
        FileFlags::empty(),
        orph_dir,
        15_000_000,
        1700000000,
    ));

    let home = Path::new("/Users/test");
    let orphans = AppManager::find_orphaned_residue(home, Some(&volume));

    assert_eq!(orphans.len(), 1);
    assert_eq!(orphans[0].name, "com.previouslydeleted.app");
    assert_eq!(orphans[0].size_bytes, 15_000_000);
}
