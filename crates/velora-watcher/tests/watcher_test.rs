use std::fs;
use velora_index::VolumeIndex;
use velora_watcher::{FileSystemEvent, FsWatcher};

#[test]
fn test_live_incremental_sync() {
    let mut volume = VolumeIndex::new("Live Test", "/tmp");

    let temp_file = std::env::temp_dir().join("velora_live_sync_test.txt");
    fs::write(&temp_file, "Hello Velora Live Sync!").unwrap();

    let initial_count = volume.total_files();

    // 1. Apply Created event
    FsWatcher::apply_event(&mut volume, &FileSystemEvent::Created(temp_file.clone()));
    assert_eq!(volume.total_files(), initial_count + 1);

    let last_rec = volume.records.last().unwrap();
    assert_eq!(volume.get_file_name(last_rec), "velora_live_sync_test.txt");
    assert_eq!(last_rec.size, 23);

    // 2. Apply Renamed event
    let renamed_file = std::env::temp_dir().join("velora_renamed_sync_test.txt");
    FsWatcher::apply_event(
        &mut volume,
        &FileSystemEvent::Renamed {
            from: temp_file.clone(),
            to: renamed_file.clone(),
        },
    );
    let last_rec = volume.records.last().unwrap();
    assert_eq!(volume.get_file_name(last_rec), "velora_renamed_sync_test.txt");

    // 3. Apply Removed event
    FsWatcher::apply_event(&mut volume, &FileSystemEvent::Removed(renamed_file.clone()));
    assert_eq!(volume.total_files(), initial_count);

    let _ = fs::remove_file(&temp_file);
    let _ = fs::remove_file(&renamed_file);
}

#[test]
fn test_watcher_lifecycle() {
    let watcher = FsWatcher::new();
    watcher.start_watching("/tmp");
    std::thread::sleep(std::time::Duration::from_millis(50));
    watcher.stop();
}
