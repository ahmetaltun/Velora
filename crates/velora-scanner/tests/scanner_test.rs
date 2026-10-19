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

#[test]
fn test_scan_directory_with_progress() {
    use std::sync::atomic::{AtomicU64, Ordering};
    use velora_scanner::{scan_directory_with_progress, ProgressListener};

    struct TestListener {
        call_count: AtomicU64,
        last_count: AtomicU64,
    }

    impl ProgressListener for TestListener {
        fn on_progress(&self, _path: &str, files_scanned: u64, _bytes_scanned: u64) {
            self.call_count.fetch_add(1, Ordering::SeqCst);
            self.last_count.store(files_scanned, Ordering::SeqCst);
        }
    }

    let mut volume = VolumeIndex::new("Velora Workspace", ".");
    let path = Path::new(".");
    let listener = TestListener {
        call_count: AtomicU64::new(0),
        last_count: AtomicU64::new(0),
    };

    let res = scan_directory_with_progress(path, &mut volume, Some(&listener));
    assert!(res.is_ok());
    assert!(listener.call_count.load(Ordering::SeqCst) > 0);
    assert_eq!(listener.last_count.load(Ordering::SeqCst), volume.total_files() as u64);
}
