use bitflags::bitflags;
use serde::{Deserialize, Serialize};

bitflags! {
    #[derive(Debug, Clone, Copy, PartialEq, Eq, Default, Serialize, Deserialize)]
    pub struct FileFlags: u16 {
        const IS_DIRECTORY = 1 << 0;
        const IS_SYMLINK   = 1 << 1;
        const IS_HIDDEN    = 1 << 2;
        const IS_SYSTEM    = 1 << 3;
        const IS_PACKAGE   = 1 << 4;
        const IS_READONLY  = 1 << 5;
        const IS_DELETED   = 1 << 6;
    }
}
