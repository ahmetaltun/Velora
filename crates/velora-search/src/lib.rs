pub mod engine;
pub mod matcher;
pub mod query;

pub use engine::{SearchEngine, SearchHit, SearchReport};
pub use query::{ComparisonOp, DateConstraint, SearchQuery, SizeConstraint};
