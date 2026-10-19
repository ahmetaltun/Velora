use serde::{Deserialize, Serialize};

/// High-throughput contiguous string arena avoiding pointer chasing.
#[derive(Debug, Default, Clone, Serialize, Deserialize)]
pub struct StringPool {
    buffer: Vec<u8>,
}

impl StringPool {
    pub fn new() -> Self {
        Self {
            buffer: Vec::with_capacity(1024 * 1024 * 16), // 16MB initial buffer
        }
    }

    #[inline]
    pub fn push(&mut self, s: &str) -> (u32, u16) {
        let bytes = s.as_bytes();
        let offset = self.buffer.len() as u32;
        let len = bytes.len() as u16;
        self.buffer.extend_from_slice(bytes);
        (offset, len)
    }

    #[inline(always)]
    pub fn get(&self, offset: u32, len: u16) -> &str {
        let start = offset as usize;
        let end = start + len as usize;
        unsafe {
            std::str::from_utf8_unchecked(&self.buffer[start..end])
        }
    }

    pub fn len_bytes(&self) -> usize {
        self.buffer.len()
    }
}
