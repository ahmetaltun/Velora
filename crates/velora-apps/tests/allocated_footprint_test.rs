use std::fs::{self, File};
use std::io::Write;
use std::os::unix::fs::{symlink, MetadataExt};
use std::path::{Path, PathBuf};
use velora_apps::{AppManager, AssociatedFileResolver, BundleScanner, IndexFootprintResolver};
use velora_index::{AppMetadataEntry, FileFlags, FileRecord, VolumeIndex};

struct Fixture(PathBuf);

impl Fixture {
    fn new() -> Self {
        let nonce = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .unwrap()
            .as_nanos();
        Self(std::env::temp_dir().join(format!("velora-allocation-{}-{nonce}", std::process::id())))
    }

    fn write(&self, relative: &str, sparse: bool) -> PathBuf {
        let path = self.0.join(relative);
        fs::create_dir_all(path.parent().unwrap()).unwrap();
        let mut file = File::create(&path).unwrap();
        file.write_all(b"allocated data").unwrap();
        if sparse {
            file.set_len(1_000_000_000_000).unwrap();
        }
        file.sync_all().unwrap();
        path
    }
}

impl Drop for Fixture {
    fn drop(&mut self) {
        let _ = fs::remove_dir_all(&self.0);
    }
}

fn allocated(path: &Path) -> u64 {
    fs::symlink_metadata(path).unwrap().blocks() * 512
}

fn add_record(volume: &mut VolumeIndex, path: &Path, flags: FileFlags) {
    let mut parent = None;
    // Reuse catalog directories while preserving parent-before-child ordering.
    let mut current = PathBuf::from("/");
    for component in path.parent().unwrap().components() {
        if let std::path::Component::Normal(name) = component {
            current.push(name);
            let id = volume.find_dir_by_path(&current).unwrap_or_else(|| {
                let (offset, len) = volume.pool.push(&name.to_string_lossy());
                volume.dirs.insert(offset, len, parent)
            });
            parent = Some(id);
        }
    }
    let (offset, len) = volume
        .pool
        .push(&path.file_name().unwrap().to_string_lossy());
    let size = fs::metadata(path).map(|m| m.len()).unwrap_or(999_999);
    volume.add_file(FileRecord::new(
        offset,
        len,
        flags,
        parent.unwrap(),
        size,
        0,
    ));
}

#[test]
fn sparse_app_footprint_matches_disk_and_existing_logical_catalog() {
    let fixture = Fixture::new();
    let binary = fixture.write("Applications/Docker.app/Contents/binary", false);
    let image = fixture.write(
        "Library/Containers/com.docker.docker/Data/vms/0/data/Docker.raw",
        true,
    );
    let prefs = fixture.write("Library/Preferences/com.docker.docker.plist", false);
    let alias = image.parent().unwrap().join("alias.raw");
    symlink(&image, &alias).unwrap();
    let empty_image = image.parent().unwrap().join("empty.raw");
    File::create(&empty_image)
        .unwrap()
        .set_len(1_000_000_000_000)
        .unwrap();
    assert!(allocated(&image) < fs::metadata(&image).unwrap().len());
    assert_eq!(allocated(&empty_image), 0);

    let app_path = fixture.0.join("Applications/Docker.app");
    let mut disk_app = BundleScanner::inspect_app_bundle(&app_path, false, None).unwrap();
    disk_app.bundle_id = "com.docker.docker".into();
    AssociatedFileResolver::resolve_associated_files(&mut disk_app, &fixture.0, None);
    let expected = allocated(&binary) + allocated(&image) + allocated(&prefs);
    assert_eq!(disk_app.total_size_bytes, expected);

    let mut volume = VolumeIndex::new("Fixture", "/");
    for path in [&binary, &image, &prefs, &empty_image] {
        add_record(&mut volume, path, FileFlags::empty());
    }
    add_record(&mut volume, &alias, FileFlags::IS_SYMLINK);
    add_record(
        &mut volume,
        &image.with_file_name("deleted.raw"),
        FileFlags::IS_DELETED,
    );
    let logical_sizes: Vec<_> = volume.records.iter().map(|r| r.size).collect();
    let resolver = IndexFootprintResolver::new(&volume, &fixture.0);
    let mut indexed_app =
        BundleScanner::inspect_app_bundle(&app_path, false, Some(&resolver)).unwrap();
    indexed_app.bundle_id = "com.docker.docker".into();
    AssociatedFileResolver::resolve_associated_files(&mut indexed_app, &fixture.0, Some(&resolver));
    assert_eq!(indexed_app.total_size_bytes, expected);
    assert_eq!(indexed_app.parts.len(), disk_app.parts.len());
    for part in &indexed_app.parts {
        let disk_part = disk_app.parts.iter().find(|p| p.path == part.path).unwrap();
        assert_eq!(part.size_bytes, disk_part.size_bytes, "{}", part.path);
    }
    assert_eq!(
        volume.records.iter().map(|r| r.size).collect::<Vec<_>>(),
        logical_sizes
    );

    // A home-only catalog may omit /Applications and files created since the scan.
    let added = fixture.write("Library/Containers/com.docker.docker/new.raw", true);
    let mut partial = VolumeIndex::new("Partial fixture", "/");
    add_record(&mut partial, &image, FileFlags::empty());
    partial.apps.push(AppMetadataEntry {
        name: "Docker".into(),
        bundle_id: "com.docker.docker".into(),
        version: "1.0".into(),
        app_path: app_path.to_string_lossy().into_owned(),
        is_system_app: false,
    });
    let apps = AppManager::list_apps_with_footprint(&fixture.0, Some(&partial));
    assert_eq!(apps.len(), 1);
    assert_eq!(apps[0].total_size_bytes, expected + allocated(&added));
}
