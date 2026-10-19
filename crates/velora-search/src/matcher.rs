/// High-performance substring matching optimized for ASCII file names.
#[inline(always)]
pub fn contains_ignore_case_ascii(haystack: &str, needle_lower: &str) -> bool {
    if needle_lower.is_empty() {
        return true;
    }
    if haystack.len() < needle_lower.len() {
        return false;
    }

    let needle_bytes = needle_lower.as_bytes();
    let haystack_bytes = haystack.as_bytes();
    let first_needle = needle_bytes[0];
    let needle_len = needle_bytes.len();
    let limit = haystack_bytes.len() - needle_len + 1;

    for i in 0..limit {
        let b = haystack_bytes[i].to_ascii_lowercase();
        if b == first_needle {
            let mut matches = true;
            for j in 1..needle_len {
                if haystack_bytes[i + j].to_ascii_lowercase() != needle_bytes[j] {
                    matches = false;
                    break;
                }
            }
            if matches {
                return true;
            }
        }
    }

    false
}

#[inline(always)]
pub fn has_extension(filename: &str, allowed_exts: &[String]) -> bool {
    if allowed_exts.is_empty() {
        return true;
    }

    if let Some(pos) = filename.rfind('.') {
        let ext = &filename[pos + 1..];
        for allowed in allowed_exts {
            if ext.eq_ignore_ascii_case(allowed) {
                return true;
            }
        }
    }

    false
}
