use velora_index::{FileFlags, FileRecord, VolumeIndex};
use velora_search::{SearchEngine, SearchQuery};

#[test]
fn test_query_parsing() {
    let q = SearchQuery::parse("report ext:pdf,docx size:>5MB dm:today !draft type:file");
    assert_eq!(q.terms, vec!["report"]);
    assert_eq!(q.extensions, vec!["pdf", "docx"]);
    assert_eq!(q.negated_terms, vec!["draft"]);
    assert!(q.is_file_only);
    assert!(!q.is_dir_only);
    assert_eq!(q.size_constraints.len(), 1);
    assert_eq!(q.size_constraints[0].bytes, 5 * 1024 * 1024);
    assert_eq!(q.date_constraints.len(), 1);
}

#[test]
fn test_boolean_or_query_parsing() {
    let q1 = SearchQuery::parse("target | node_modules | deriveddata");
    assert_eq!(q1.terms.len(), 0);
    assert_eq!(q1.or_groups.len(), 1);
    assert_eq!(q1.or_groups[0], vec!["target", "node_modules", "deriveddata"]);

    let q2 = SearchQuery::parse("report|invoice ext:pdf");
    assert_eq!(q2.terms.len(), 0);
    assert_eq!(q2.or_groups.len(), 1);
    assert_eq!(q2.or_groups[0], vec!["report", "invoice"]);
    assert_eq!(q2.extensions, vec!["pdf"]);

    let q3 = SearchQuery::parse("important note | memo !archive");
    assert_eq!(q3.terms, vec!["important"]);
    assert_eq!(q3.or_groups, vec![vec!["note", "memo"]]);
    assert_eq!(q3.negated_terms, vec!["archive"]);
}

#[test]
fn test_boolean_or_search_execution() {
    let mut volume = VolumeIndex::new("Macintosh HD", "/");
    let (r_off, r_len) = volume.pool.push("Users");
    let root = volume.dirs.insert(r_off, r_len, None);

    let items = [
        ("target", true),
        ("node_modules", true),
        ("DerivedData", true),
        ("src", true),
        ("main.rs", false),
        ("Cargo.toml", false),
    ];

    for (name, is_dir) in items {
        let (n_off, n_len) = volume.pool.push(name);
        let flags = if is_dir { FileFlags::IS_DIRECTORY } else { FileFlags::empty() };
        volume.add_file(FileRecord::new(n_off, n_len, flags, root, 0, 100));
    }

    let query = SearchQuery::parse("target | node_modules | deriveddata");
    let report = SearchEngine::search(&volume, &query, None, 10);

    assert_eq!(report.total_matched, 3);
    let matched_names: Vec<&str> = report
        .hits
        .iter()
        .map(|h| volume.get_file_name(&volume.records[h.record_index]))
        .collect();
    assert!(matched_names.contains(&"target"));
    assert!(matched_names.contains(&"node_modules"));
    assert!(matched_names.contains(&"DerivedData"));
}

#[test]
fn test_half_million_records_search_latency() {
    let mut volume = VolumeIndex::new("Macintosh HD", "/");

    let (root_offset, root_len) = volume.pool.push("Users");
    let root_dir = volume.dirs.insert(root_offset, root_len, None);

    let filenames = [
        "annual_financial_report_2026.pdf",
        "quarterly_financial_report_q1.pdf",
        "quarterly_financial_report_q2.pdf",
        "quarterly_financial_report_q3_draft.pdf",
        "marketing_strategy_notes.docx",
        "velora_system_architecture.rs",
        "project_invoice_september.pdf",
        "family_photo_vacation.jpg",
        "system_cache_backup.tmp",
        "client_presentation_slides.key",
    ];

    let offsets_lens: Vec<(u32, u16)> = filenames
        .iter()
        .map(|&name| volume.pool.push(name))
        .collect();

    let total = 500_000;
    for i in 0..total {
        let (name_offset, name_len) = offsets_lens[i % offsets_lens.len()];
        let size = ((i % 20 + 1) * 1024 * 1024) as u64; // 1MB to 20MB
        let record = FileRecord::new(
            name_offset,
            name_len,
            FileFlags::empty(),
            root_dir,
            size,
            1730000000 + i as u64,
        );
        volume.add_file(record);
    }

    assert_eq!(volume.total_files(), total);

    // 1. Cold sweep search: "financial"
    let q1 = SearchQuery::parse("financial ext:pdf size:>5MB !draft");
    let report1 = SearchEngine::search(&volume, &q1, None, 100);

    println!(
        "Cold search across {} files matched {} items in {:.3} ms ({} µs)",
        total,
        report1.total_matched,
        report1.duration_micros as f64 / 1000.0,
        report1.duration_micros
    );

    assert!(report1.total_matched > 0);
    // Cold search should be well within interactive response budget (higher tolerance for unoptimized debug builds)
    let max_cold_micros = if cfg!(debug_assertions) { 200_000 } else { 50_000 };
    assert!(
        report1.duration_micros < max_cold_micros,
        "Cold search latency exceeded {}ms (took {:.2}ms)",
        max_cold_micros / 1000,
        report1.duration_micros as f64 / 1000.0
    );

    // 2. Incremental search: user narrows by typing "annual"
    let candidate_indices: Vec<usize> = report1.hits.iter().map(|h| h.record_index).collect();
    let q2 = SearchQuery::parse("financial annual ext:pdf size:>5MB !draft");
    let report2 = SearchEngine::search(&volume, &q2, Some(&candidate_indices), 100);

    println!(
        "Incremental narrowing over {} candidates finished in {:.3} ms ({} µs)",
        candidate_indices.len(),
        report2.duration_micros as f64 / 1000.0,
        report2.duration_micros
    );

    assert!(report2.total_matched > 0);
    assert!(report2.total_matched <= report1.total_matched);
    // Incremental narrowing should be sub-millisecond (higher tolerance for unoptimized debug builds)
    let max_narrowing_micros = if cfg!(debug_assertions) { 25_000 } else { 5_000 };
    assert!(
        report2.duration_micros < max_narrowing_micros,
        "Incremental narrowing latency exceeded {}ms (took {:.2}ms)",
        max_narrowing_micros / 1000,
        report2.duration_micros as f64 / 1000.0
    );
}
