#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ComparisonOp {
    GreaterThan,
    GreaterThanOrEqual,
    LessThan,
    LessThanOrEqual,
    Equal,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct SizeConstraint {
    pub op: ComparisonOp,
    pub bytes: u64,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct DateConstraint {
    pub op: ComparisonOp,
    pub timestamp_secs: u64,
}

#[derive(Debug, Clone, PartialEq, Eq, Default)]
pub struct SearchQuery {
    pub raw_text: String,
    pub terms: Vec<String>,
    pub or_groups: Vec<Vec<String>>,
    pub negated_terms: Vec<String>,
    pub extensions: Vec<String>,
    pub size_constraints: Vec<SizeConstraint>,
    pub date_constraints: Vec<DateConstraint>,
    pub path_prefix: Option<String>,
    pub is_dir_only: bool,
    pub is_file_only: bool,
}

impl SearchQuery {
    pub fn parse(input: &str) -> Self {
        let mut query = SearchQuery {
            raw_text: input.to_string(),
            ..Default::default()
        };

        let trimmed = input.trim();
        if trimmed.is_empty() {
            return query;
        }

        let mut current_or_group: Vec<String> = Vec::new();
        let mut pending_or = false;

        for token in trimmed.split_whitespace() {
            if let Some(exts) = token.strip_prefix("ext:") {
                for ext in exts.split(',') {
                    let cleaned = ext.trim().trim_start_matches('.').to_lowercase();
                    if !cleaned.is_empty() {
                        query.extensions.push(cleaned);
                    }
                }
            } else if let Some(size_str) = token.strip_prefix("size:") {
                if let Some(sc) = parse_size_constraint(size_str) {
                    query.size_constraints.push(sc);
                }
            } else if let Some(dm_str) = token.strip_prefix("dm:") {
                if let Some(dc) = parse_date_constraint(dm_str) {
                    query.date_constraints.push(dc);
                }
            } else if let Some(path_str) = token.strip_prefix("path:") {
                query.path_prefix = Some(path_str.trim().to_string());
            } else if token == "type:folder" || token == "type:dir" {
                query.is_dir_only = true;
            } else if token == "type:file" {
                query.is_file_only = true;
            } else if let Some(negated) = token.strip_prefix('!') {
                let cleaned = negated.trim().to_lowercase();
                if !cleaned.is_empty() {
                    query.negated_terms.push(cleaned);
                }
            } else if token == "|" {
                pending_or = true;
                if current_or_group.is_empty() {
                    if let Some(prev) = query.terms.pop() {
                        current_or_group.push(prev);
                    }
                }
            } else {
                let cleaned = token.to_lowercase();
                if cleaned.contains('|') {
                    let parts: Vec<String> = cleaned
                        .split('|')
                        .map(|s| s.trim().to_string())
                        .filter(|s| !s.is_empty())
                        .collect();
                    if !current_or_group.is_empty() {
                        current_or_group.extend(parts);
                    } else if pending_or {
                        if let Some(prev) = query.terms.pop() {
                            current_or_group.push(prev);
                        }
                        current_or_group.extend(parts);
                    } else if parts.len() > 1 {
                        query.or_groups.push(parts);
                    } else if let Some(single) = parts.into_iter().next() {
                        query.terms.push(single);
                    }
                    pending_or = false;
                } else if pending_or {
                    current_or_group.push(cleaned);
                    pending_or = false;
                } else {
                    if current_or_group.len() > 1 {
                        query.or_groups.push(std::mem::take(&mut current_or_group));
                    } else {
                        current_or_group.clear();
                    }
                    query.terms.push(cleaned);
                }
            }
        }

        if current_or_group.len() > 1 {
            query.or_groups.push(current_or_group);
        } else if let Some(single) = current_or_group.pop() {
            query.terms.push(single);
        }

        query
    }
}

fn parse_size_constraint(s: &str) -> Option<SizeConstraint> {
    let (op, rest) = if let Some(r) = s.strip_prefix(">=") {
        (ComparisonOp::GreaterThanOrEqual, r)
    } else if let Some(r) = s.strip_prefix('>') {
        (ComparisonOp::GreaterThan, r)
    } else if let Some(r) = s.strip_prefix("<=") {
        (ComparisonOp::LessThanOrEqual, r)
    } else if let Some(r) = s.strip_prefix('<') {
        (ComparisonOp::LessThan, r)
    } else if let Some(r) = s.strip_prefix('=') {
        (ComparisonOp::Equal, r)
    } else {
        (ComparisonOp::Equal, s)
    };

    let multiplier = if rest.ends_with("gb") || rest.ends_with("GB") {
        1024 * 1024 * 1024
    } else if rest.ends_with("mb") || rest.ends_with("MB") {
        1024 * 1024
    } else if rest.ends_with("kb") || rest.ends_with("KB") {
        1024
    } else if rest.ends_with('b') || rest.ends_with('B') {
        1
    } else {
        1
    };

    let numeric_part: String = rest.chars().filter(|c| c.is_ascii_digit() || *c == '.').collect();
    let value: f64 = numeric_part.parse().ok()?;
    let bytes = (value * multiplier as f64) as u64;

    Some(SizeConstraint { op, bytes })
}

fn parse_date_constraint(s: &str) -> Option<DateConstraint> {
    let now_secs = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .ok()?
        .as_secs();

    let day_secs = 86400u64;

    match s.to_lowercase().as_str() {
        "today" => Some(DateConstraint {
            op: ComparisonOp::GreaterThanOrEqual,
            timestamp_secs: now_secs.saturating_sub(day_secs),
        }),
        "yesterday" => Some(DateConstraint {
            op: ComparisonOp::GreaterThanOrEqual,
            timestamp_secs: now_secs.saturating_sub(day_secs * 2),
        }),
        "lastweek" | "week" => Some(DateConstraint {
            op: ComparisonOp::GreaterThanOrEqual,
            timestamp_secs: now_secs.saturating_sub(day_secs * 7),
        }),
        "lastmonth" | "month" => Some(DateConstraint {
            op: ComparisonOp::GreaterThanOrEqual,
            timestamp_secs: now_secs.saturating_sub(day_secs * 30),
        }),
        _ => None,
    }
}
