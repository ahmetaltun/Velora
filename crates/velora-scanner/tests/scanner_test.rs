use std::fs;
use velora_index::VolumeIndex;
use velora_scanner::scan_directory;

#[test]
fn test_scan_real_directory() {
    let temp_root = std::env::temp_dir().join("velora_test_scanner_fixture");
    let _ = fs::remove_dir_all(&temp_root);

    // Create a lightweight, controlled directory hierarchy: 3 directories + 3 files = 6 records
    let sub1 = temp_root.join("sub1/nested");
    let sub2 = temp_root.join("sub2");
    fs::create_dir_all(&sub1).unwrap();
    fs::create_dir_all(&sub2).unwrap();

    fs::write(temp_root.join("root_file.txt"), "hello").unwrap();
    fs::write(sub1.join("nested_file.bin"), vec![0u8; 1024]).unwrap();
    fs::write(sub2.join("data.json"), "{}").unwrap();

    let mut volume = VolumeIndex::new("Test Scanner", temp_root.to_str().unwrap());
    let res = scan_directory(&temp_root, &mut volume);
    assert!(res.is_ok());
    assert_eq!(volume.total_files(), 6); // 3 subdirectories + 3 files

    let dirs_count = volume.records.iter().filter(|r| r.is_dir()).count();
    let files_count = volume.records.iter().filter(|r| !r.is_dir()).count();
    assert_eq!(dirs_count, 3);
    assert_eq!(files_count, 3);

    println!(
        "Successfully scanned {} items in test directory tree. Estimated memory: {:.2} KB",
        volume.total_files(),
        volume.estimated_memory_bytes() as f64 / 1024.0
    );

    // Verify each record can resolve its path
    for record in &volume.records {
        let full_path = volume.resolve_full_path(record);
        assert!(!full_path.is_empty());
    }

    let _ = fs::remove_dir_all(&temp_root);
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

    let temp_root = std::env::temp_dir().join("velora_test_scanner_progress_fixture");
    let _ = fs::remove_dir_all(&temp_root);
    // 2 directories + 3 files = 5 records
    fs::create_dir_all(temp_root.join("dir1")).unwrap();
    fs::create_dir_all(temp_root.join("dir2")).unwrap();

    fs::write(temp_root.join("file1.txt"), "abc").unwrap();
    fs::write(temp_root.join("dir1/file2.txt"), "def").unwrap();
    fs::write(temp_root.join("dir2/file3.txt"), "ghi").unwrap();

    let mut volume = VolumeIndex::new("Test Scanner Progress", temp_root.to_str().unwrap());
    let listener = TestListener {
        call_count: AtomicU64::new(0),
        last_count: AtomicU64::new(0),
    };

    let res = scan_directory_with_progress(&temp_root, &mut volume, Some(&listener));
    assert!(res.is_ok());
    assert_eq!(volume.total_files(), 5);
    assert!(listener.call_count.load(Ordering::SeqCst) > 0);
    assert_eq!(listener.last_count.load(Ordering::SeqCst), 5);

    let _ = fs::remove_dir_all(&temp_root);
}
