pub mod duplicates;
pub mod matrix;
pub mod model;

pub use duplicates::DuplicateFinder;
pub use matrix::LargeOldFilesMatrix;
pub use model::{
    AgeBucket, DuplicateFile, DuplicateGroup, DuplicateSummary, LargeOldFile,
    LargeOldMatrixSummary, MatrixCell, SizeBucket,
};
