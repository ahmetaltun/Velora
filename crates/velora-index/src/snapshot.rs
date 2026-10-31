use std::io::{Read, Write};

pub const SNAPSHOT_MAGIC: [u8; 8] = *b"VELORASN";
pub const SNAPSHOT_VERSION: u32 = 1;

/// Standard IEEE 802.3 CRC-32 (polynomial 0xEDB88320)
pub fn compute_crc32(data: &[u8]) -> u32 {
    const TABLE: [u32; 256] = {
        let mut table = [0u32; 256];
        let mut i = 0;
        while i < 256 {
            let mut c = i as u32;
            let mut j = 0;
            while j < 8 {
                if c & 1 != 0 {
                    c = 0xEDB88320 ^ (c >> 1);
                } else {
                    c >>= 1;
                }
                j += 1;
            }
            table[i] = c;
            i += 1;
        }
        table
    };

    let mut crc = !0u32;
    for &b in data {
        crc = TABLE[((crc ^ (b as u32)) & 0xFF) as usize] ^ (crc >> 8);
    }
    !crc
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct SnapshotHeader {
    pub magic: [u8; 8],
    pub version: u32,
    pub flags: u32,
    pub checksum: u32,
    pub payload_len: u64,
}

impl SnapshotHeader {
    pub fn write_to<W: Write>(&self, writer: &mut W) -> std::io::Result<()> {
        writer.write_all(&self.magic)?;
        writer.write_all(&self.version.to_le_bytes())?;
        writer.write_all(&self.flags.to_le_bytes())?;
        writer.write_all(&self.checksum.to_le_bytes())?;
        writer.write_all(&self.payload_len.to_le_bytes())?;
        Ok(())
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
        if version != SNAPSHOT_VERSION {
            return Err(std::io::Error::new(
                std::io::ErrorKind::InvalidData,
                format!(
                    "Unsupported snapshot version {} (expected version {})",
                    version, SNAPSHOT_VERSION
                ),
            ));
        }

        reader.read_exact(&mut buf4)?;
        let flags = u32::from_le_bytes(buf4);

        reader.read_exact(&mut buf4)?;
        let checksum = u32::from_le_bytes(buf4);

        let mut buf8 = [0u8; 8];
        reader.read_exact(&mut buf8)?;
        let payload_len = u64::from_le_bytes(buf8);

        Ok(Self {
            magic,
            version,
            flags,
            checksum,
            payload_len,
        })
    }
}
