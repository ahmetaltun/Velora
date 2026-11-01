use crate::model::ModelMetadata;
use std::fs::File;
use std::io::{BufReader, Read};
use std::path::Path;

const GGUF_MAGIC: [u8; 4] = [0x47, 0x47, 0x55, 0x46]; // "GGUF"
const MAX_HEADER_READ: u64 = 128 * 1024; // 128 KB max header budget

pub struct GgufParser;

impl GgufParser {
    pub fn parse_file(path: &Path) -> Option<ModelMetadata> {
        let file = File::open(path).ok()?;
        let mut reader = BufReader::new(file.take(MAX_HEADER_READ));

        let mut magic = [0u8; 4];
        reader.read_exact(&mut magic).ok()?;
        if magic != GGUF_MAGIC {
            return None;
        }

        let version = read_u32(&mut reader)?;
        if version != 2 && version != 3 {
            return None;
        }

        let _tensor_count = read_u64(&mut reader)?;
        let kv_count = read_u64(&mut reader)?;

        let mut metadata = ModelMetadata::default();

        for _ in 0..kv_count {
            let key = match read_string(&mut reader) {
                Some(k) => k,
                None => break, // EOF reached within header budget
            };

            let val_type = match read_u32(&mut reader) {
                Some(t) => t,
                None => break,
            };

            match val_type {
                0 => { // UINT8
                    let _ = read_u8(&mut reader);
                }
                1 => { // INT8
                    let _ = read_u8(&mut reader);
                }
                2 => { // UINT16
                    let _ = read_u16(&mut reader);
                }
                3 => { // INT16
                    let _ = read_u16(&mut reader);
                }
                4 => { // UINT32
                    if let Some(v) = read_u32(&mut reader) {
                        if key == "general.file_type" {
                            metadata.quantization = Some(map_file_type_to_quant(v).to_string());
                        } else if key.ends_with(".context_length") {
                            metadata.context_length = Some(v);
                        }
                    }
                }
                5 => { // INT32
                    let _ = read_u32(&mut reader);
                }
                6 => { // FLOAT32
                    let _ = read_u32(&mut reader);
                }
                7 => { // BOOL
                    let _ = read_u8(&mut reader);
                }
                8 => { // STRING
                    if let Some(str_val) = read_string(&mut reader) {
                        if key == "general.architecture" {
                            metadata.architecture = Some(format_architecture(&str_val));
                        } else if key == "general.name" && metadata.architecture.is_none() {
                            metadata.architecture = Some(str_val);
                        } else if key == "general.quantization_version" || key == "general.file_type_name" {
                            if metadata.quantization.is_none() {
                                metadata.quantization = Some(str_val);
                            }
                        }
                    }
                }
                9 => { // ARRAY
                    if !skip_array(&mut reader) {
                        break;
                    }
                }
                10 => { // UINT64
                    if let Some(v) = read_u64(&mut reader) {
                        if key == "general.parameter_count" {
                            metadata.parameter_size = Some(format_parameter_count(v));
                        } else if key.ends_with(".context_length") {
                            metadata.context_length = Some((v.min(u32::MAX as u64)) as u32);
                        }
                    }
                }
                11 => { // INT64
                    let _ = read_u64(&mut reader);
                }
                12 => { // FLOAT64
                    let _ = read_u64(&mut reader);
                }
                _ => break, // Unknown type
            }
        }

        // If quantization is not in metadata, attempt to extract from path or filename
        if metadata.quantization.is_none() {
            if let Some(fname) = path.file_name().and_then(|s| s.to_str()) {
                metadata.quantization = extract_quant_from_name(fname);
            }
        }

        // If parameter size is not in metadata, attempt to extract from filename
        if metadata.parameter_size.is_none() {
            if let Some(fname) = path.file_name().and_then(|s| s.to_str()) {
                metadata.parameter_size = extract_param_size_from_name(fname);
            }
        }

        // Fallback for architecture from filename
        if metadata.architecture.is_none() {
            if let Some(fname) = path.file_name().and_then(|s| s.to_str()) {
                metadata.architecture = extract_arch_from_name(fname);
            }
        }

        Some(metadata)
    }
}

fn read_u8<R: Read>(r: &mut R) -> Option<u8> {
    let mut b = [0u8; 1];
    r.read_exact(&mut b).ok()?;
    Some(b[0])
}

fn read_u16<R: Read>(r: &mut R) -> Option<u16> {
    let mut b = [0u8; 2];
    r.read_exact(&mut b).ok()?;
    Some(u16::from_le_bytes(b))
}

fn read_u32<R: Read>(r: &mut R) -> Option<u32> {
    let mut b = [0u8; 4];
    r.read_exact(&mut b).ok()?;
    Some(u32::from_le_bytes(b))
}

fn read_u64<R: Read>(r: &mut R) -> Option<u64> {
    let mut b = [0u8; 8];
    r.read_exact(&mut b).ok()?;
    Some(u64::from_le_bytes(b))
}

fn read_string<R: Read>(r: &mut R) -> Option<String> {
    let len = read_u64(r)? as usize;
    if len > 8192 {
        // Prevent huge allocations
        return None;
    }
    let mut buf = vec![0u8; len];
    r.read_exact(&mut buf).ok()?;
    String::from_utf8(buf).ok()
}

fn skip_array<R: Read>(r: &mut R) -> bool {
    let elem_type = match read_u32(r) {
        Some(t) => t,
        None => return false,
    };
    let count = match read_u64(r) {
        Some(c) => c as usize,
        None => return false,
    };

    if count > 65536 {
        return false;
    }

    match elem_type {
        0 | 1 | 7 => {
            let mut buf = vec![0u8; count];
            r.read_exact(&mut buf).is_ok()
        }
        2 | 3 => {
            let mut buf = vec![0u8; count * 2];
            r.read_exact(&mut buf).is_ok()
        }
        4 | 5 | 6 => {
            let mut buf = vec![0u8; count * 4];
            r.read_exact(&mut buf).is_ok()
        }
        8 => {
            for _ in 0..count {
                if read_string(r).is_none() {
                    return false;
                }
            }
            true
        }
        10 | 11 | 12 => {
            let mut buf = vec![0u8; count * 8];
            r.read_exact(&mut buf).is_ok()
        }
        _ => false,
    }
}

pub fn format_architecture(arch: &str) -> String {
    match arch.to_lowercase().as_str() {
        "llama" => "Llama".to_string(),
        "qwen2" | "qwen2.5" | "qwen" => "Qwen 2.5".to_string(),
        "qwen3" | "qwen3_5" | "qwen3.5" => "Qwen 3.5".to_string(),
        "spark" | "spark2_5" | "spark2.5" => "Spark 2.5".to_string(),
        "lfm" | "lfm2" | "liquid" => "Liquid LFM".to_string(),
        "phi3" | "phi" => "Phi-3".to_string(),
        "gemma" | "gemma2" => "Gemma 2".to_string(),
        "mistral" => "Mistral".to_string(),
        "deepseek2" | "deepseek" => "DeepSeek".to_string(),
        "starcoder2" => "StarCoder 2".to_string(),
        "command-r" => "Command R".to_string(),
        "falcon" => "Falcon".to_string(),
        "flux" => "Flux.1".to_string(),
        other => {
            let cleaned = other.replace('_', " ");
            let mut result = String::new();
            for word in cleaned.split_whitespace() {
                let mut chars = word.chars();
                if let Some(f) = chars.next() {
                    if !result.is_empty() {
                        result.push(' ');
                    }
                    result.push_str(&f.to_uppercase().to_string());
                    result.push_str(chars.as_str());
                }
            }
            if result.is_empty() {
                other.to_string()
            } else {
                result
            }
        }
    }
}

pub fn format_parameter_count(count: u64) -> String {
    if count >= 1_000_000_000 {
        let billions = count as f64 / 1_000_000_000.0;
        if billions.fract() < 0.05 {
            format!("{:.0}B", billions)
        } else {
            format!("{:.1}B", billions)
        }
    } else if count >= 1_000_000 {
        format!("{:.0}M", count as f64 / 1_000_000.0)
    } else {
        format!("{}", count)
    }
}

pub fn map_file_type_to_quant(file_type: u32) -> &'static str {
    match file_type {
        0 => "F32",
        1 => "F16",
        2 => "Q4_0",
        3 => "Q4_1",
        7 => "Q8_0",
        8 => "Q5_0",
        9 => "Q5_1",
        10 => "Q2_K",
        11 => "Q3_K_S",
        12 => "Q3_K_M",
        13 => "Q3_K_L",
        14 => "Q4_K_S",
        15 => "Q4_K_M",
        16 => "Q5_K_S",
        17 => "Q5_K_M",
        18 => "Q6_K",
        19 => "IQ2_XXS",
        20 => "IQ2_XS",
        21 => "Q2_K_S",
        22 => "IQ3_XS",
        23 => "IQ3_XXS",
        24 => "IQ1_S",
        25 => "IQ4_NL",
        26 => "IQ3_S",
        27 => "IQ3_M",
        28 => "IQ2_S",
        29 => "IQ2_M",
        30 => "IQ4_XS",
        31 => "IQ1_M",
        32 => "BF16",
        _ => "Quantized",
    }
}

pub fn extract_quant_from_name(name: &str) -> Option<String> {
    let quants = [
        "Q4_K_M", "Q4_K_S", "Q4_0", "Q4_1", "Q5_K_M", "Q5_K_S", "Q5_0", "Q5_1",
        "Q8_0", "Q6_K", "Q2_K", "Q3_K_M", "Q3_K_S", "Q3_K_L", "IQ4_XS", "IQ4_NL",
        "IQ3_M", "IQ3_S", "IQ2_M", "IQ2_S", "IQ1_M", "IQ1_S", "BF16", "FP16", "F16",
        "4-bit", "4bit", "8-bit", "8bit", "FP8", "INT8", "INT4",
    ];
    let upper = name.to_uppercase();
    for q in quants {
        if upper.contains(&q.to_uppercase()) {
            return Some(q.to_string());
        }
    }
    None
}

pub fn extract_param_size_from_name(name: &str) -> Option<String> {
    let tokens = ["70B", "32B", "27B", "14B", "8B", "7B", "4B", "3B", "2B", "1.5B", "1.2B", "0.5B"];
    let upper = name.to_uppercase();
    for t in tokens {
        if upper.contains(t) {
            return Some(t.to_string());
        }
    }
    None
}

pub fn extract_arch_from_name(name: &str) -> Option<String> {
    let lower = name.to_lowercase();
    if lower.contains("llama") {
        Some("Llama".to_string())
    } else if lower.contains("qwen") {
        Some("Qwen".to_string())
    } else if lower.contains("deepseek") {
        Some("DeepSeek".to_string())
    } else if lower.contains("mistral") {
        Some("Mistral".to_string())
    } else if lower.contains("phi") {
        Some("Phi".to_string())
    } else if lower.contains("gemma") {
        Some("Gemma".to_string())
    } else if lower.contains("flux") {
        Some("Flux".to_string())
    } else if lower.contains("stable-diffusion") || lower.contains("sdxl") {
        Some("Stable Diffusion".to_string())
    } else {
        None
    }
}
