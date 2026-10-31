use crc32fast::Hasher;
use std::io::{Read, Write};

pub const SNAPSHOT_MAGIC: [u8; 8] = *b"VELORASN";
pub const SNAPSHOT_VERSION_V1: u32 = 1;
pub const SNAPSHOT_VERSION_V2: u32 = 2;
pub const SNAPSHOT_VERSION: u32 = SNAPSHOT_VERSION_V2;

pub const SNAPSHOT_FLAG_UNCOMPRESSED: u32 = 0;

/// Standard IEEE 802.3 CRC-32 (polynomial 0xEDB88320)
/// Accelerated via ARM64 SIMD hardware instructions on Apple Silicon.
#[inline]
pub fn compute_crc32(data: &[u8]) -> u32 {
    let mut hasher = Hasher::new();
    hasher.update(data);
    hasher.finalize()
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum SnapshotHeader {
    V1(SnapshotHeaderV1),
    V2(SnapshotHeaderV2),
}

impl SnapshotHeader {
    #[inline]
    pub fn version(&self) -> u32 {
        match self {
            Self::V1(h) => h.version,
            Self::V2(h) => h.version,
        }
    }

    #[inline]
    pub fn flags(&self) -> u32 {
        match self {
            Self::V1(h) => h.flags,
            Self::V2(h) => h.flags,
        }
    }

    #[inline]
    pub fn checksum(&self) -> u32 {
        match self {
            Self::V1(h) => h.checksum,
            Self::V2(h) => h.checksum,
        }
    }

    #[inline]
    pub fn payload_len(&self) -> u64 {
        match self {
            Self::V1(h) => h.payload_len,
            Self::V2(h) => h.payload_len,
        }
    }

    pub fn read_from<R: Read>(reader: &mut R) -> std::io::Result<Self> {
        let mut magic = [0u8; 8];
        reader.read_exact(&mut magic)?;
        if magic != SNAPSHOT_MAGIC {
            return Err(std::io::Error::new(
                std::io::ErrorKind::InvalidData,
                "Invalid snapshot format: missing VELORASN magic header",
            ));
        }

        let mut buf4 = [0u8; 4];
        reader.read_exact(&mut buf4)?;
        let version = u32::from_le_bytes(buf4);

        match version {
            SNAPSHOT_VERSION_V1 => {
                let mut buf_flags = [0u8; 4];
                reader.read_exact(&mut buf_flags)?;
                let flags = u32::from_le_bytes(buf_flags);

                let mut buf_crc = [0u8; 4];
                reader.read_exact(&mut buf_crc)?;
                let checksum = u32::from_le_bytes(buf_crc);

                let mut buf_len = [0u8; 8];
                reader.read_exact(&mut buf_len)?;
                let payload_len = u64::from_le_bytes(buf_len);

                Ok(SnapshotHeader::V1(SnapshotHeaderV1 {
                    magic,
                    version,
                    flags,
                    checksum,
                    payload_len,
                }))
            }
            SNAPSHOT_VERSION_V2 => {
                let mut rest = [0u8; 52];
                reader.read_exact(&mut rest)?;

                let flags = u32::from_le_bytes(rest[0..4].try_into().unwrap());
                let checksum = u32::from_le_bytes(rest[4..8].try_into().unwrap());
                let _reserved1 = u32::from_le_bytes(rest[8..12].try_into().unwrap());
                let payload_len = u64::from_le_bytes(rest[12..20].try_into().unwrap());
                let pool_len = u64::from_le_bytes(rest[20..28].try_into().unwrap());
                let dirs_count = u64::from_le_bytes(rest[28..36].try_into().unwrap());
                let records_count = u64::from_le_bytes(rest[36..44].try_into().unwrap());
                let metadata_len = u64::from_le_bytes(rest[44..52].try_into().unwrap());

                Ok(SnapshotHeader::V2(SnapshotHeaderV2 {
                    magic,
                    version,
                    flags,
                    checksum,
                    _reserved1,
                    payload_len,
                    pool_len,
                    dirs_count,
                    records_count,
                    metadata_len,
                }))
            }
            other => Err(std::io::Error::new(
                std::io::ErrorKind::InvalidData,
                format!(
                    "Unsupported snapshot version {} (expected version {} or {})",
                    other, SNAPSHOT_VERSION_V1, SNAPSHOT_VERSION_V2
                ),
            )),
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct SnapshotHeaderV1 {
    pub magic: [u8; 8],
    pub version: u32,
    pub flags: u32,
    pub checksum: u32,
    pub payload_len: u64,
}

impl SnapshotHeaderV1 {
    pub fn write_to<W: Write>(&self, writer: &mut W) -> std::io::Result<()> {
        writer.write_all(&self.magic)?;
        writer.write_all(&self.version.to_le_bytes())?;
        writer.write_all(&self.flags.to_le_bytes())?;
        writer.write_all(&self.checksum.to_le_bytes())?;
        writer.write_all(&self.payload_len.to_le_bytes())?;
        Ok(())
    }
}

#[repr(C)]
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct SnapshotHeaderV2 {
    pub magic: [u8; 8],
    pub version: u32,
    pub flags: u32,
    pub checksum: u32,
    pub _reserved1: u32,
    pub payload_len: u64,
    pub pool_len: u64,
    pub dirs_count: u64,
    pub records_count: u64,
    pub metadata_len: u64,
}

unsafe impl bytemuck::Zeroable for SnapshotHeaderV2 {}
unsafe impl bytemuck::Pod for SnapshotHeaderV2 {}

impl SnapshotHeaderV2 {
    pub const SIZE: usize = 64;

    pub fn write_to<W: Write>(&self, writer: &mut W) -> std::io::Result<()> {
        let bytes: &[u8; 64] = bytemuck::cast_ref(self);
        writer.write_all(bytes)?;
        Ok(())
    }
}
