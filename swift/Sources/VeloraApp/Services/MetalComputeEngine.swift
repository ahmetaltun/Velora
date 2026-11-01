import Foundation
import Metal
import VeloraCore

/// Hardware-accelerated Metal compute engine leveraging Apple Silicon's Unified Memory Architecture (UMA).
/// Operates directly on the in-memory array of `FileRecord` structures with zero copies over the memory bus.
public final class MetalComputeEngine {
    public static let shared: MetalComputeEngine? = {
        do {
            return try MetalComputeEngine()
        } catch {
            print("⚠️ [MetalComputeEngine] Hardware initialization failed: \(error.localizedDescription). Falling back to CPU.")
            return nil
        }
    }()

    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private let matrixComputePipeline: MTLComputePipelineState

    private init() throws {
        guard let defaultDevice = MTLCreateSystemDefaultDevice() else {
            throw NSError(
                domain: "MetalComputeEngine",
                code: 201,
                userInfo: [NSLocalizedDescriptionKey: "No Apple Silicon Metal device detected."]
            )
        }
        self.device = defaultDevice

        guard let queue = defaultDevice.makeCommandQueue() else {
            throw NSError(
                domain: "MetalComputeEngine",
                code: 202,
                userInfo: [NSLocalizedDescriptionKey: "Failed to initialize Metal command queue."]
            )
        }
        self.commandQueue = queue

        // Compile compute kernel at runtime via Metal driver
        let source = MetalComputeShaders.kernelSource
        let compileOptions = MTLCompileOptions()
        compileOptions.mathMode = .fast

        let library = try defaultDevice.makeLibrary(source: source, options: compileOptions)
        guard let function = library.makeFunction(name: "compute_large_old_matrix") else {
            throw NSError(
                domain: "MetalComputeEngine",
                code: 203,
                userInfo: [NSLocalizedDescriptionKey: "Compute kernel 'compute_large_old_matrix' not found in library."]
            )
        }

        self.matrixComputePipeline = try defaultDevice.makeComputePipelineState(function: function)
        print("⚡️ [MetalComputeEngine] Initialized Apple Silicon Metal compute pipeline for zero-copy catalog analysis.")
    }

    /// Computes the 2D Large & Old Files Matrix (Age × Size) directly on the Apple Silicon GPU
    /// by mapping the in-memory `FileRecord` array into a zero-copy shared Metal buffer.
    public func computeLargeOldMatrix(engine: VeloraEngine) -> LargeOldMatrixSummaryRecord? {
        let descriptor = engine.getRecordsBufferDescriptor()
        guard descriptor.count > 0, descriptor.pointer != 0 else {
            return nil
        }

        guard let rawPtr = UnsafeMutableRawPointer(bitPattern: UInt(descriptor.pointer)) else {
            return nil
        }

        let totalRecords = Int(descriptor.count)
        let byteLength = totalRecords * Int(descriptor.recordSize)

        // Zero-copy UMA buffer mapping: wraps host RAM pointer without memory duplication
        guard let recordsBuffer = device.makeBuffer(
            bytesNoCopy: rawPtr,
            length: byteLength,
            options: .storageModeShared,
            deallocator: nil
        ) else {
            print("⚠️ [MetalComputeEngine] Failed to map \(byteLength) bytes into zero-copy Metal buffer.")
            return nil
        }

        let numCells = 16
        guard let countsBuffer = device.makeBuffer(
            length: numCells * MemoryLayout<UInt32>.stride,
            options: .storageModeShared
        ) else { return nil }

        let maxCandidates = 10000
        guard let candidatesBuffer = device.makeBuffer(
            length: maxCandidates * MemoryLayout<UInt32>.stride,
            options: .storageModeShared
        ) else { return nil }

        guard let candidateCountBuffer = device.makeBuffer(
            length: MemoryLayout<UInt32>.stride,
            options: .storageModeShared
        ) else { return nil }

        // Clear output buffers
        memset(countsBuffer.contents(), 0, numCells * MemoryLayout<UInt32>.stride)
        memset(candidateCountBuffer.contents(), 0, MemoryLayout<UInt32>.stride)

        var nowSecs = UInt64(Date().timeIntervalSince1970)
        var totalRecordsCount = UInt32(totalRecords)

        guard let commandBuffer = commandQueue.makeCommandBuffer(),
              let encoder = commandBuffer.makeComputeCommandEncoder() else {
            return nil
        }

        encoder.setComputePipelineState(matrixComputePipeline)
        encoder.setBuffer(recordsBuffer, offset: 0, index: 0)
        encoder.setBuffer(countsBuffer, offset: 0, index: 1)
        encoder.setBuffer(candidatesBuffer, offset: 0, index: 2)
        encoder.setBuffer(candidateCountBuffer, offset: 0, index: 3)
        encoder.setBytes(&nowSecs, length: MemoryLayout<UInt64>.size, index: 4)
        encoder.setBytes(&totalRecordsCount, length: MemoryLayout<UInt32>.size, index: 5)

        let threadgroupWidth = min(matrixComputePipeline.maxTotalThreadsPerThreadgroup, 256)
        let threadgroupSize = MTLSize(width: threadgroupWidth, height: 1, depth: 1)
        let gridSize = MTLSize(width: totalRecords, height: 1, depth: 1)

        encoder.dispatchThreads(gridSize, threadsPerThreadgroup: threadgroupSize)
        encoder.endEncoding()

        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()

        // Read back aggregated results
        let countsPtr = countsBuffer.contents().bindMemory(to: UInt32.self, capacity: numCells)
        let rawCandCount = candidateCountBuffer.contents().bindMemory(to: UInt32.self, capacity: 1).pointee
        let candCount = min(Int(rawCandCount), maxCandidates)

        let candidateIndices: [UInt32]
        if candCount > 0 {
            let candPtr = candidatesBuffer.contents().bindMemory(to: UInt32.self, capacity: candCount)
            candidateIndices = Array(UnsafeBufferPointer(start: candPtr, count: candCount))
        } else {
            candidateIndices = []
        }

        // Resolve top candidate files via Rust FFI
        let resolvedFiles = engine.resolveLargeOldCandidates(
            candidateIndices: candidateIndices,
            maxResults: 1000
        )

        // Compute total counts and bytes
        var cellRecords: [MatrixCellRecord] = []
        var totalFilesCount: UInt32 = 0
        var totalBytesCount: UInt64 = 0

        let ageLabels = ["Recent (< 1 mo)", "1 – 6 Months", "6 – 12 Months", "Ancient (> 1 yr)"]
        let sizeLabels = ["> 1 GB", "500 MB – 1 GB", "100 – 500 MB", "50 – 100 MB"]

        for ageI in 0..<4 {
            for sizeI in 0..<4 {
                let cellIdx = ageI * 4 + sizeI
                let count = countsPtr[cellIdx]
                totalFilesCount += count

                // Sum bytes for this cell from resolved candidate files
                let cellBytes = resolvedFiles
                    .filter { $0.ageIdx == UInt32(ageI) && $0.sizeIdx == UInt32(sizeI) }
                    .reduce(UInt64(0)) { $0 + $1.sizeBytes }

                totalBytesCount += cellBytes

                cellRecords.append(
                    MatrixCellRecord(
                        ageIdx: UInt32(ageI),
                        sizeIdx: UInt32(sizeI),
                        ageLabel: ageLabels[ageI],
                        sizeLabel: sizeLabels[sizeI],
                        fileCount: count,
                        totalBytes: cellBytes
                    )
                )
            }
        }

        return LargeOldMatrixSummaryRecord(
            totalFiles: totalFilesCount,
            totalBytes: totalBytesCount,
            cells: cellRecords,
            files: resolvedFiles
        )
    }
}

private enum MetalComputeShaders {
    static let kernelSource = """
    #include <metal_stdlib>
    using namespace metal;

    struct FileRecordMetal {
        uint name_offset;
        ushort name_len;
        ushort flags;
        uint parent_dir;
        uint _reserved;
        ulong size;
        ulong modified_secs;
    };

    kernel void compute_large_old_matrix(
        device const FileRecordMetal* records [[buffer(0)]],
        device atomic_uint* cell_counts       [[buffer(1)]],
        device uint* candidate_indices        [[buffer(2)]],
        device atomic_uint* candidate_count   [[buffer(3)]],
        constant ulong& now_secs              [[buffer(4)]],
        constant uint& total_records          [[buffer(5)]],
        uint gid                              [[thread_position_in_grid]]
    ) {
        if (gid >= total_records) return;

        FileRecordMetal rec = records[gid];

        // Filter deleted (flags & 0x0040) or directory (flags & 0x0001) or size < 50MB (50,000,000 bytes)
        if ((rec.flags & 0x0041) != 0 || rec.size < 50000000UL) return;

        // Classify Size (0: >=1GB, 1: 500MB-1GB, 2: 100MB-500MB, 3: 50MB-100MB)
        uint size_idx;
        if (rec.size >= 1000000000UL)        size_idx = 0;
        else if (rec.size >= 500000000UL)    size_idx = 1;
        else if (rec.size >= 100000000UL)    size_idx = 2;
        else                                 size_idx = 3;

        // Classify Age (0: <30d, 1: 30-180d, 2: 180-365d, 3: >365d)
        ulong age_secs = (now_secs > rec.modified_secs) ? (now_secs - rec.modified_secs) : 0;
        uint age_idx;
        if (age_secs < 2592000UL)            age_idx = 0;
        else if (age_secs < 15552000UL)      age_idx = 1;
        else if (age_secs < 31536000UL)      age_idx = 2;
        else                                 age_idx = 3;

        uint cell_idx = age_idx * 4 + size_idx;
        atomic_fetch_add_explicit(&cell_counts[cell_idx], 1, memory_order_relaxed);

        uint slot = atomic_fetch_add_explicit(candidate_count, 1, memory_order_relaxed);
        if (slot < 10000) {
            candidate_indices[slot] = gid;
        }
    }
    """
}
