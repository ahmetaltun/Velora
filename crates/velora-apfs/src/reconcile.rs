use crate::model::StorageReconciliation;
use crate::snapshot::SnapshotManager;
use crate::telemetry::ApfsTelemetry;
use std::path::Path;

pub struct Reconciler;

impl Reconciler {
    /// Reconciles APFS storage telemetry with the user-scanned bytes from velora-index.
    pub fn reconcile(mount_point: &Path, user_scanned_bytes: u64) -> StorageReconciliation {
        let vfs = ApfsTelemetry::get_vfs_stats(mount_point);
        let container = ApfsTelemetry::query_container_for_mount(mount_point);
        let snapshots = SnapshotManager::list_snapshots(mount_point);

        let (container_total_bytes, container_free_bytes) = if let Some(ref c) = container {
            (c.capacity_ceiling, c.capacity_free)
        } else if let Some(ref v) = vfs {
            (v.total_bytes, v.free_bytes)
        } else {
            (0, 0)
        };

        let mut system_volume_bytes = 0;
        let mut vm_swap_bytes = 0;
        let mut other_volumes_bytes = 0;
        let mut data_volume_used = user_scanned_bytes;

        if let Some(ref c) = container {
            for vol in &c.volumes {
                if vol.is_system() {
                    system_volume_bytes += vol.capacity_in_use;
                } else if vol.is_vm() {
                    vm_swap_bytes += vol.capacity_in_use;
                } else if vol.is_data() {
                    data_volume_used = vol.capacity_in_use;
                } else {
                    other_volumes_bytes += vol.capacity_in_use;
                }
            }
        }

        // Calculate the gap in the Data volume:
        // Files that couldn't be read due to permissions (~/Library parts, root caches)
        let hidden_system_bytes = data_volume_used.saturating_sub(user_scanned_bytes);

        // Calculate purgeable space based on VFS available vs free delta if available
        let purgeable_bytes = if let Some(ref v) = vfs {
            v.available_bytes.saturating_sub(v.free_bytes)
        } else {
            0
        };

        StorageReconciliation {
            container_total_bytes,
            container_free_bytes,
            user_scanned_bytes,
            system_volume_bytes,
            vm_swap_bytes,
            other_volumes_bytes,
            purgeable_bytes,
            hidden_system_bytes,
            snapshots,
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_reconciliation_math() {
        let rec = Reconciler::reconcile(Path::new("/"), 50_000_000_000);
        assert!(rec.container_total_bytes > 0);
        assert!(rec.container_free_bytes > 0);
    }
}
