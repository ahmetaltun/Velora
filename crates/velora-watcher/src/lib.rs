use crossbeam_channel::{unbounded, Receiver, Sender};
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Arc;
use std::thread;
use std::time::Duration;
use velora_index::{FileFlags, FileRecord, VolumeIndex};

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum FileSystemEvent {
    Created(PathBuf),
    Modified(PathBuf),
    Removed(PathBuf),
    Renamed { from: PathBuf, to: PathBuf },
}

pub struct FsWatcher {
    receiver: Receiver<FileSystemEvent>,
    sender: Sender<FileSystemEvent>,
    is_running: Arc<AtomicBool>,
}

impl FsWatcher {
    pub fn new() -> Self {
        let (sender, receiver) = unbounded();
        Self {
            receiver,
            sender,
            is_running: Arc::new(AtomicBool::new(false)),
        }
    }

    pub fn events(&self) -> &Receiver<FileSystemEvent> {
        &self.receiver
    }

    pub fn start_watching(&self, path: impl Into<PathBuf>) {
        let watch_path = path.into();
        let sender = self.sender.clone();
        let running = self.is_running.clone();
        running.store(true, Ordering::SeqCst);

        thread::Builder::new()
            .name("velora-fsevents-watcher".to_string())
            .spawn(move || {
                #[cfg(target_os = "macos")]
                {
                    run_fsevent_loop(watch_path, sender, running);
                }
                #[cfg(not(target_os = "macos"))]
                {
                    while running.load(Ordering::SeqCst) {
                        thread::sleep(Duration::from_millis(1000));
                    }
                }
            })
            .expect("Failed to spawn filesystem watcher thread");
    }

    pub fn stop(&self) {
        self.is_running.store(false, Ordering::SeqCst);
    }

    pub fn apply_event(volume: &mut VolumeIndex, event: &FileSystemEvent) {
        match event {
            FileSystemEvent::Created(path) | FileSystemEvent::Modified(path) => {
                if let Ok(meta) = std::fs::metadata(path) {
                    let file_name = path
                        .file_name()
                        .map(|n| n.to_string_lossy().to_string())
                        .unwrap_or_default();

                    let parent_path = path.parent().unwrap_or(Path::new("/"));
                    let mut flags = FileFlags::empty();
                    if meta.is_dir() {
                        flags.insert(FileFlags::IS_DIRECTORY);
                    }
                    if file_name.starts_with('.') {
                        flags.insert(FileFlags::IS_HIDDEN);
                    }

                    let path_str = path.to_string_lossy();
                    let mut existing_idx = None;
                    let mut buf = String::with_capacity(128);

                    for (idx, rec) in volume.records.iter().enumerate() {
                        if volume.get_file_name(rec) == file_name {
                            buf.clear();
                            volume.dirs.build_full_path(rec.parent_dir, &volume.pool, &mut buf);
                            if !buf.ends_with('/') {
                                buf.push('/');
                            }
                            buf.push_str(volume.pool.get(rec.name_offset, rec.name_len));
                            if buf == path_str {
                                existing_idx = Some(idx);
                                break;
                            }
                        }
                    }

                    if let Some(idx) = existing_idx {
                        volume.records[idx].size = meta.len();
                        volume.records[idx].modified_secs = meta
                            .modified()
                            .ok()
                            .and_then(|t| t.duration_since(std::time::UNIX_EPOCH).ok())
                            .map(|d| d.as_secs())
                            .unwrap_or(0);
                    } else {
                        let (name_off, name_len) = volume.pool.push(&file_name);
                        let (p_off, p_len) = volume.pool.push(&parent_path.to_string_lossy());
                        let parent_dir = volume.dirs.insert(p_off, p_len, None);

                        volume.add_file(FileRecord::new(
                            name_off,
                            name_len,
                            flags,
                            parent_dir,
                            meta.len(),
                            meta.modified()
                                .ok()
                                .and_then(|t| t.duration_since(std::time::UNIX_EPOCH).ok())
                                .map(|d| d.as_secs())
                                .unwrap_or(0),
                        ));
                    }
                }
            }
            FileSystemEvent::Removed(path) => {
                let path_str = path.to_string_lossy();
                let mut buf = String::with_capacity(128);
                let dirs = &volume.dirs;
                let pool = &volume.pool;

                volume.records.retain(|rec| {
                    buf.clear();
                    dirs.build_full_path(rec.parent_dir, pool, &mut buf);
                    if !buf.ends_with('/') {
                        buf.push('/');
                    }
                    buf.push_str(pool.get(rec.name_offset, rec.name_len));
                    buf != path_str
                });
            }
            FileSystemEvent::Renamed { from, to } => {
                let from_str = from.to_string_lossy();
                let to_name = to
                    .file_name()
                    .map(|n| n.to_string_lossy().to_string())
                    .unwrap_or_default();

                let mut target_idx = None;
                let mut buf = String::with_capacity(128);

                for (idx, rec) in volume.records.iter().enumerate() {
                    buf.clear();
                    volume.dirs.build_full_path(rec.parent_dir, &volume.pool, &mut buf);
                    if !buf.ends_with('/') {
                        buf.push('/');
                    }
                    buf.push_str(volume.pool.get(rec.name_offset, rec.name_len));
                    if buf == from_str {
                        target_idx = Some(idx);
                        break;
                    }
                }

                if let Some(idx) = target_idx {
                    let (off, len) = volume.pool.push(&to_name);
                    volume.records[idx].name_offset = off;
                    volume.records[idx].name_len = len;
                }
            }
        }
    }
}

impl Default for FsWatcher {
    fn default() -> Self {
        Self::new()
    }
}

#[cfg(target_os = "macos")]
fn run_fsevent_loop(
    _watch_path: PathBuf,
    _sender: Sender<FileSystemEvent>,
    running: Arc<AtomicBool>,
) {
    while running.load(Ordering::SeqCst) {
        thread::sleep(Duration::from_millis(250));
    }
}
