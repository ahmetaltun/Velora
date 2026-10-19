use crate::category::CategoryKind;
use crate::rollup::SizeRollup;
use serde::{Deserialize, Serialize};
use velora_index::{DirId, VolumeIndex};

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SunburstSector {
    pub name: String,
    pub path: String,
    pub size_bytes: u64,
    pub start_angle: f32,
    pub sweep_angle: f32,
    pub depth: u32,
    pub color_hex: String,
    pub is_dir: bool,
    pub is_grouped: bool,
    pub children: Vec<SunburstSector>,
}

pub struct SectorBuilder;

impl SectorBuilder {
    pub fn build(
        volume: &VolumeIndex,
        rollup: &SizeRollup,
        root_dir: DirId,
        max_depth: u32,
        min_angle_deg: f32,
    ) -> Option<SunburstSector> {
        let total_size = rollup.get_size(root_dir);
        let mut path = String::new();
        volume.dirs.build_full_path(root_dir, &volume.pool, &mut path);

        let root_name = if let Some(entry) = volume.dirs.get(root_dir) {
            volume.pool.get(entry.name_offset, entry.name_len).to_string()
        } else {
            "Root".to_string()
        };

        let mut root_sector = SunburstSector {
            name: root_name,
            path,
            size_bytes: total_size,
            start_angle: 0.0,
            sweep_angle: 360.0,
            depth: 0,
            color_hex: CategoryKind::Other.color_hex().to_string(),
            is_dir: true,
            is_grouped: false,
            children: Vec::new(),
        };

        if total_size > 0 && max_depth > 0 {
            Self::build_children(
                volume,
                rollup,
                root_dir,
                &mut root_sector,
                0.0,
                360.0,
                1,
                max_depth,
                min_angle_deg,
            );
        }

        Some(root_sector)
    }

    fn build_children(
        volume: &VolumeIndex,
        rollup: &SizeRollup,
        dir_id: DirId,
        parent_sector: &mut SunburstSector,
        parent_start: f32,
        parent_sweep: f32,
        current_depth: u32,
        max_depth: u32,
        min_angle_deg: f32,
    ) {
        if current_depth > max_depth || parent_sector.size_bytes == 0 {
            return;
        }

        struct ChildCandidate<'a> {
            name: &'a str,
            size: u64,
            is_dir: bool,
            child_dir_id: Option<DirId>,
        }

        let mut candidates = Vec::new();

        // 1. Collect direct child files and subdirectories
        for record in &volume.records {
            if record.parent_dir == dir_id {
                let name = volume.get_file_name(record);
                if record.is_dir() {
                    let mut matched_id = None;
                    for i in 0..volume.dirs.len() {
                        let cid = DirId(i as u32);
                        if let Some(entry) = volume.dirs.get(cid) {
                            if entry.parent == Some(dir_id) {
                                let dname = volume.pool.get(entry.name_offset, entry.name_len);
                                if dname == name {
                                    matched_id = Some(cid);
                                    break;
                                }
                            }
                        }
                    }
                    if let Some(cid) = matched_id {
                        let dir_size = rollup.get_size(cid);
                        candidates.push(ChildCandidate {
                            name,
                            size: dir_size,
                            is_dir: true,
                            child_dir_id: Some(cid),
                        });
                    }
                } else {
                    candidates.push(ChildCandidate {
                        name,
                        size: record.size,
                        is_dir: false,
                        child_dir_id: None,
                    });
                }
            }
        }

        // Sort descending by size
        candidates.sort_unstable_by(|a, b| b.size.cmp(&a.size));

        let mut current_angle = parent_start;
        let mut small_items_size = 0u64;
        let mut small_items_count = 0usize;

        for cand in candidates {
            if cand.size == 0 {
                continue;
            }

            let sweep = (cand.size as f32 / parent_sector.size_bytes as f32) * parent_sweep;

            if sweep < min_angle_deg {
                small_items_size += cand.size;
                small_items_count += 1;
                continue;
            }

            let category = CategoryKind::classify(cand.name, cand.is_dir);
            let mut full_path = parent_sector.path.clone();
            if !full_path.ends_with('/') {
                full_path.push('/');
            }
            full_path.push_str(cand.name);

            let mut sector = SunburstSector {
                name: cand.name.to_string(),
                path: full_path,
                size_bytes: cand.size,
                start_angle: current_angle,
                sweep_angle: sweep,
                depth: current_depth,
                color_hex: category.color_hex().to_string(),
                is_dir: cand.is_dir,
                is_grouped: false,
                children: Vec::new(),
            };

            if cand.is_dir && current_depth < max_depth {
                if let Some(cid) = cand.child_dir_id {
                    Self::build_children(
                        volume,
                        rollup,
                        cid,
                        &mut sector,
                        current_angle,
                        sweep,
                        current_depth + 1,
                        max_depth,
                        min_angle_deg,
                    );
                }
            }

            current_angle += sweep;
            parent_sector.children.push(sector);
        }

        // Add aggregated small items sector if any exist
        if small_items_count > 0 && small_items_size > 0 {
            let small_sweep = (small_items_size as f32 / parent_sector.size_bytes as f32) * parent_sweep;
            parent_sector.children.push(SunburstSector {
                name: format!("Other ({} items)", small_items_count),
                path: parent_sector.path.clone(),
                size_bytes: small_items_size,
                start_angle: current_angle,
                sweep_angle: small_sweep,
                depth: current_depth,
                color_hex: "#9CA3AF".to_string(), // Muted Gray
                is_dir: false,
                is_grouped: true,
                children: Vec::new(),
            });
        }
    }
}
