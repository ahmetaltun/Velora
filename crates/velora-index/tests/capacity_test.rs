use velora_index::{FileFlags, FileRecord, VolumeIndex};
use std::time::Instant;

#[test]
fn test_one_million_records_memory_footprint() {
    let mut volume = VolumeIndex::new("Macintosh HD", "/");

    let (root_offset, root_len) = volume.pool.push("Users");
    let users_dir = volume.dirs.insert(root_offset, root_len, None);

    let (home_offset, home_len) = volume.pool.push("ahmet");
    let home_dir = volume.dirs.insert(home_offset, home_len, Some(users_dir));

    let (docs_offset, docs_len) = volume.pool.push("Documents");
    let docs_dir = volume.dirs.insert(docs_offset, docs_len, Some(home_dir));

    let is_ci = std::env::var("CI").is_ok();
    // In CI or unoptimized debug runs, test 100k records for instant feedback.
    // In release/benchmark runs, test full 1M scale.
    let total_records = if is_ci || cfg!(debug_assertions) {
        100_000
    } else {
        1_000_000
    };

    let start = Instant::now();
    // Simulate files sharing pool names
    let (name_offset, name_len) = volume.pool.push("financial_report_2026_q3_final_draft.pdf");

    for i in 0..total_records {
        let record = FileRecord::new(
            name_offset,
            name_len,
            FileFlags::empty(),
            docs_dir,
            1024 * (i % 1000 + 1) as u64,
            1730000000 + i as u64,
        );
        volume.add_file(record);
    }

    let elapsed = start.elapsed();
    let mem_bytes = volume.estimated_memory_bytes();
    let mem_mb = mem_bytes as f64 / (1024.0 * 1024.0);
    let bytes_per_record = mem_bytes as f64 / total_records as f64;

    println!(
        "Indexed {} records in {:?}. Total estimated memory: {:.2} MB ({:.2} bytes/record)",
        total_records,
        elapsed,
        mem_mb,
        bytes_per_record
    );

    assert_eq!(volume.total_files(), total_records);
    // Density check: records must comfortably stay under 40 bytes per record (40MB per 1M records)
    assert!(
        bytes_per_record < 40.0,
        "Memory footprint exceeded 40 bytes/record limit (got {:.2} bytes/record)",
        bytes_per_record
    );

    // Test zero-copy full path resolution
    let first_record = &volume.records[0];
    let path = volume.resolve_full_path(first_record);
    assert_eq!(path, "/Users/ahmet/Documents/financial_report_2026_q3_final_draft.pdf");
}
