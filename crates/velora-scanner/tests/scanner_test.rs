use std::path::Path;
use velora_index::VolumeIndex;
use velora_scanner::scan_directory;

#[test]
fn test_scan_real_directory() {
    let mut volume = VolumeIndex::new("Velora Workspace", ".");
    let path = Path::new(".");

    let res = scan_directory(path, &mut volume);
    assert!(res.is_ok());
    assert!(volume.total_files() > 0);

    println!(
        "Successfully scanned {} items in current directory tree. Estimated memory: {:.2} KB",
        volume.total_files(),
        volume.estimated_memory_bytes() as f64 / 1024.0
    );

    // Verify each record can resolve its path
    for record in &volume.records {
        let full_path = volume.resolve_full_path(record);
        assert!(!full_path.is_empty());
    }
}
