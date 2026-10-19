pub mod category;
pub mod rollup;
pub mod sector;

pub use category::CategoryKind;
pub use rollup::SizeRollup;
pub use sector::{SectorBuilder, SunburstSector};
use velora_index::{DirId, VolumeIndex};

pub struct Analyzer;

impl Analyzer {
    /// Computes full disk size rollup and returns SunburstSector hierarchy ready for visual rendering.
    pub fn analyze(
        volume: &VolumeIndex,
        root_dir: DirId,
        max_depth: u32,
        min_angle_deg: f32,
    ) -> Option<SunburstSector> {
        let rollup = SizeRollup::compute(volume);
        SectorBuilder::build(volume, &rollup, root_dir, max_depth, min_angle_deg)
    }
}
