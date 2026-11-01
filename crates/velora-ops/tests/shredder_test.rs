use std::fs::File;
use std::io::Write;
use std::path::PathBuf;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Arc, Mutex};
use velora_ops::{shred_paths, ShredAlgorithm, ShredProgressListener};

struct TestProgressListener {
    events: Arc<Mutex<Vec<String>>>,
}

impl ShredProgressListener for TestProgressListener {
    fn on_progress(
        &self,
        current_path: &str,
        file_index: u32,
        total_files: u32,
        current_pass: u32,
        total_passes: u32,
        pass_name: &str,
        bytes_written_file: u64,
        file_size_bytes: u64,
        _total_bytes_written: u64,
        _total_bytes_all_files: u64,
    ) {
        let mut ev = self.events.lock().unwrap();
        ev.push(format!(
            "[{}/{}] pass {}/{} ({}): {}/{} bytes for {}",
            file_index,
            total_files,
            current_pass,
            total_passes,
            pass_name,
            bytes_written_file,
            file_size_bytes,
            current_path
        ));
    }
}

fn create_temp_test_dir(name: &str) -> PathBuf {
    let dir = std::env::temp_dir().join(format!("velora_shred_test_{}_{}", name, std::process::id()));
    let _ = std::fs::remove_dir_all(&dir);
    std::fs::create_dir_all(&dir).unwrap();
    dir
}

#[test]
fn test_single_pass_zeroing() {
    let dir = create_temp_test_dir("zero");
    let file_path = dir.join("sensitive_secret.txt");

    // Write 128 KB of test payload
    {
        let mut f = File::create(&file_path).unwrap();
        let payload = vec![0x42u8; 128 * 1024];
        f.write_all(&payload).unwrap();
        f.sync_all().unwrap();
    }
    assert!(file_path.exists());

    let cancel = AtomicBool::new(false);
    let events = Arc::new(Mutex::new(Vec::new()));
    let listener = TestProgressListener {
        events: events.clone(),
    };

    let stats = shred_paths(&[file_path.clone()], ShredAlgorithm::Zero, &cancel, Some(&listener));

    assert_eq!(stats.files_shredded, 1);
    assert_eq!(stats.bytes_shredded, 128 * 1024);
    assert!(stats.errors.is_empty());
    assert!(!file_path.exists(), "Target file must be completely unlinked");

    let ev_list = events.lock().unwrap();
    assert!(!ev_list.is_empty(), "Progress listener should receive callbacks");

    let _ = std::fs::remove_dir_all(&dir);
}

#[test]
fn test_empty_file_shredding() {
    let dir = create_temp_test_dir("empty");
    let file_path = dir.join("empty_secret.txt");

    // Create 0-byte file
    File::create(&file_path).unwrap();
    assert!(file_path.exists());

    let cancel = AtomicBool::new(false);
    let events = Arc::new(Mutex::new(Vec::new()));
    let listener = TestProgressListener {
        events: events.clone(),
    };

    let stats = shred_paths(&[file_path.clone()], ShredAlgorithm::Dod522022M, &cancel, Some(&listener));

    assert_eq!(stats.files_shredded, 1);
    assert_eq!(stats.bytes_shredded, 0);
    assert!(stats.errors.is_empty());
    assert!(!file_path.exists(), "0-byte file must be completely unlinked");

    let ev_list = events.lock().unwrap();
    assert!(!ev_list.is_empty(), "0-byte file must still emit progress callbacks for each pass");
    let has_pass1 = ev_list.iter().any(|e| e.contains("pass 1/3"));
    let has_pass3 = ev_list.iter().any(|e| e.contains("pass 3/3"));
    assert!(has_pass1);
    assert!(has_pass3);

    let _ = std::fs::remove_dir_all(&dir);
}

#[test]
fn test_dod_5220_22_m_3pass() {
    let dir = create_temp_test_dir("dod3");
    let file_path = dir.join("classified_dossier.dat");

    // Write 256 KB of test data
    {
        let mut f = File::create(&file_path).unwrap();
        let payload = vec![0xABu8; 256 * 1024];
        f.write_all(&payload).unwrap();
        f.sync_all().unwrap();
    }

    let cancel = AtomicBool::new(false);
    let events = Arc::new(Mutex::new(Vec::new()));
    let listener = TestProgressListener {
        events: events.clone(),
    };

    let stats = shred_paths(
        &[file_path.clone()],
        ShredAlgorithm::Dod522022M,
        &cancel,
        Some(&listener),
    );

    assert_eq!(stats.files_shredded, 1);
    assert_eq!(stats.bytes_shredded, 256 * 1024);
    assert!(stats.errors.is_empty());
    assert!(!file_path.exists());

    let ev_list = events.lock().unwrap();
    let has_pass1 = ev_list.iter().any(|e| e.contains("pass 1/3"));
    let has_pass2 = ev_list.iter().any(|e| e.contains("pass 2/3"));
    let has_pass3 = ev_list.iter().any(|e| e.contains("pass 3/3"));
    assert!(has_pass1, "Must execute pass 1 (zeros)");
    assert!(has_pass2, "Must execute pass 2 (ones)");
    assert!(has_pass3, "Must execute pass 3 (random)");

    let _ = std::fs::remove_dir_all(&dir);
}

#[test]
fn test_recursive_directory_shred() {
    let dir = create_temp_test_dir("recursive");
    let sub1 = dir.join("folder_a");
    let sub2 = sub1.join("subfolder_b");
    std::fs::create_dir_all(&sub2).unwrap();

    let file1 = dir.join("root_file.txt");
    let file2 = sub1.join("mid_file.log");
    let file3 = sub2.join("deep_secret.bin");

    for p in &[&file1, &file2, &file3] {
        let mut f = File::create(p).unwrap();
        f.write_all(b"CONFIDENTIAL_RECORD_DO_NOT_REVEAL").unwrap();
    }

    let cancel = AtomicBool::new(false);
    let stats = shred_paths(&[dir.clone()], ShredAlgorithm::RandomNist80088, &cancel, None);

    assert_eq!(stats.files_shredded, 1); // 1 directory entry processed
    assert!(stats.errors.is_empty());
    assert!(!dir.exists(), "Root directory and all children must be completely removed");
    assert!(!file1.exists());
    assert!(!file2.exists());
    assert!(!file3.exists());
}

#[test]
fn test_shred_cancellation() {
    let dir = create_temp_test_dir("cancel");
    let file_path = dir.join("huge_file.bin");

    // Write 5 MB payload
    {
        let mut f = File::create(&file_path).unwrap();
        let payload = vec![0x7Fu8; 5 * 1024 * 1024];
        f.write_all(&payload).unwrap();
    }

    let cancel = Arc::new(AtomicBool::new(false));
    let cancel_clone = cancel.clone();

    struct CancellingListener {
        cancel_token: Arc<AtomicBool>,
    }

    impl ShredProgressListener for CancellingListener {
        fn on_progress(
            &self,
            _path: &str,
            _idx: u32,
            _total: u32,
            _pass: u32,
            _total_passes: u32,
            _name: &str,
            bytes_written: u64,
            _size: u64,
            _total_written: u64,
            _total_expected: u64,
        ) {
            // Cancel after first chunk is written
            if bytes_written > 64 * 1024 {
                self.cancel_token.store(true, Ordering::SeqCst);
            }
        }
    }

    let listener = CancellingListener {
        cancel_token: cancel_clone,
    };

    let stats = shred_paths(
        &[file_path.clone()],
        ShredAlgorithm::Dod522022M,
        &cancel,
        Some(&listener),
    );

    assert!(
        stats.errors.iter().any(|e| e.contains("cancelled")),
        "Stats should report cancellation"
    );

    let _ = std::fs::remove_dir_all(&dir);
}
