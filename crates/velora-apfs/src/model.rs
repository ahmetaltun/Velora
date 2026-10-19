use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ApfsVolume {
    pub device_id: String,
    pub name: String,
    pub roles: Vec<String>,
    pub capacity_in_use: u64,
}

impl ApfsVolume {
    pub fn is_system(&self) -> bool {
        self.roles.iter().any(|r| r.eq_ignore_ascii_case("system"))
    }

    pub fn is_data(&self) -> bool {
        self.roles.iter().any(|r| r.eq_ignore_ascii_case("data"))
    }

    pub fn is_vm(&self) -> bool {
        self.roles.iter().any(|r| r.eq_ignore_ascii_case("vm"))
    }

    pub fn is_recovery(&self) -> bool {
        self.roles.iter().any(|r| r.eq_ignore_ascii_case("recovery"))
    }

    pub fn is_preboot(&self) -> bool {
        self.roles.iter().any(|r| r.eq_ignore_ascii_case("preboot"))
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ApfsContainer {
    pub container_reference: String,
    pub capacity_ceiling: u64,
    pub capacity_free: u64,
    pub volumes: Vec<ApfsVolume>,
}

impl ApfsContainer {
    pub fn system_volume(&self) -> Option<&ApfsVolume> {
        self.volumes.iter().find(|v| v.is_system())
    }

    pub fn data_volume(&self) -> Option<&ApfsVolume> {
        self.volumes.iter().find(|v| v.is_data())
    }

    pub fn vm_volume(&self) -> Option<&ApfsVolume> {
        self.volumes.iter().find(|v| v.is_vm())
    }

    pub fn total_other_volumes_bytes(&self) -> u64 {
        self.volumes
            .iter()
            .filter(|v| !v.is_data())
            .map(|v| v.capacity_in_use)
            .sum()
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SnapshotInfo {
    pub name: String,
    pub date_formatted: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct StorageReconciliation {
    pub container_total_bytes: u64,
    pub container_free_bytes: u64,
    pub user_scanned_bytes: u64,
    pub system_volume_bytes: u64,
    pub vm_swap_bytes: u64,
    pub other_volumes_bytes: u64,
    pub purgeable_bytes: u64,
    pub hidden_system_bytes: u64,
    pub snapshots: Vec<SnapshotInfo>,
}
