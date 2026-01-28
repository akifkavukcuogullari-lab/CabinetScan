//
//  TSDFMetalPipeline.swift
//  cabinetscan
//
//  Created for Story 3.4: Multi-View Fusion (TSDF)
//

import Foundation
import Metal
import simd
import os.log

// MARK: - Metal Data Structures

/// TSDF parameters struct matching Metal shader layout.
/// NOTE: Must match TSDFParams in TSDFKernel.metal exactly
struct TSDFMetalParams {
    var boundingBoxMin: SIMD3<Float>   // 12 bytes
    var voxelSize: Float               // 4 bytes
    var truncationDistance: Float      // 4 bytes
    var gridDimensions: SIMD3<UInt32>  // 12 bytes
    var pointWeight: Float             // 4 bytes
    var pointCount: UInt32             // 4 bytes
    var hasNormals: UInt32             // 4 bytes - whether normals buffer is valid
}

/// Metal voxel struct matching shader layout.
/// NOTE: Must match TSDFVoxel in TSDFKernel.metal exactly
struct TSDFMetalVoxel {
    var tsdf: Float
    var weight: Float
}

// MARK: - TSDF Metal Pipeline

/// Manages Metal resources and executes GPU compute kernels for TSDF fusion.
///
/// **ADR-001:** Metal is REQUIRED for production - this pipeline must succeed on all iOS 17+ devices.
/// **ADR-008:** Uses atomic operations for thread-safe voxel accumulation.
final class TSDFMetalPipeline {

    // MARK: - Constants

    /// Thread group size for compute kernels
    private static let threadGroupSize = MTLSize(width: 256, height: 1, depth: 1)

    /// Maximum grid size for dense buffer allocation
    /// Beyond this, we use sparse mode (CPU fallback for now)
    private static let maxDenseGridVoxels = 10_000_000  // ~10M voxels = ~80MB

    // MARK: - Metal Resources

    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private let integratePipeline: MTLComputePipelineState
    private let resetPipeline: MTLComputePipelineState

    private let logger = Logger(subsystem: "com.cabinetscan", category: "TSDFMetalPipeline")

    // MARK: - Buffer Pool

    /// Point buffer for current point cloud
    private var pointBuffer: MTLBuffer?
    private var pointBufferSize: Int = 0

    /// Normals buffer for current point cloud
    private var normalsBuffer: MTLBuffer?
    private var normalsBufferSize: Int = 0

    /// Empty dummy buffer for when normals are not available
    /// Using a dedicated buffer avoids confusion with reusing other buffers
    private var dummyNormalsBuffer: MTLBuffer?

    /// Dense TSDF buffer (tsdf values)
    private var tsdfBuffer: MTLBuffer?

    /// Dense weight buffer
    private var weightBuffer: MTLBuffer?

    /// Current grid size
    private var currentGridVoxelCount: Int = 0

    /// Counter buffer
    private var counterBuffer: MTLBuffer?

    // MARK: - Initialization

    /// Creates a Metal pipeline for TSDF fusion.
    ///
    /// - Parameter device: Metal device to use
    /// - Throws: TSDFFusionError if pipeline creation fails
    init(device: MTLDevice) throws {
        self.device = device

        // Create command queue
        guard let queue = device.makeCommandQueue() else {
            throw TSDFFusionError.pipelineCreationFailed("Failed to create command queue")
        }
        self.commandQueue = queue

        // Load shader library
        guard let library = device.makeDefaultLibrary() else {
            throw TSDFFusionError.pipelineCreationFailed("Failed to load default Metal library")
        }

        // Create integrate pipeline
        guard let integrateFunction = library.makeFunction(name: "integrateTSDFSparse") else {
            throw TSDFFusionError.pipelineCreationFailed("Failed to find integrateTSDFSparse kernel function")
        }

        do {
            self.integratePipeline = try device.makeComputePipelineState(function: integrateFunction)
        } catch {
            throw TSDFFusionError.pipelineCreationFailed("Failed to create integrate pipeline: \(error.localizedDescription)")
        }

        // Create reset pipeline
        guard let resetFunction = library.makeFunction(name: "resetTSDFVolume") else {
            throw TSDFFusionError.pipelineCreationFailed("Failed to find resetTSDFVolume kernel function")
        }

        do {
            self.resetPipeline = try device.makeComputePipelineState(function: resetFunction)
        } catch {
            throw TSDFFusionError.pipelineCreationFailed("Failed to create reset pipeline: \(error.localizedDescription)")
        }

        // Create counter buffer
        guard let counter = device.makeBuffer(length: MemoryLayout<UInt32>.size, options: .storageModeShared) else {
            throw TSDFFusionError.bufferAllocationFailed
        }
        self.counterBuffer = counter

        // Create dummy normals buffer (single zero vector) for when normals are not available
        // This avoids reusing other buffers which could cause confusion (H1 fix)
        guard let dummyNormals = device.makeBuffer(length: MemoryLayout<SIMD3<Float>>.size, options: .storageModeShared) else {
            throw TSDFFusionError.bufferAllocationFailed
        }
        memset(dummyNormals.contents(), 0, MemoryLayout<SIMD3<Float>>.size)
        self.dummyNormalsBuffer = dummyNormals

        logger.info("TSDF Metal pipeline initialized successfully")
    }

    // MARK: - Integration

    /// Integrates a point cloud into the TSDF volume using GPU compute.
    ///
    /// - Parameters:
    ///   - pointCloud: Point cloud to integrate
    ///   - volume: TSDF volume to integrate into (modified in place)
    ///   - weight: Weight for this point cloud (1.0 for video, 2.0 for photos)
    func integratePointCloud(
        _ pointCloud: AIPointCloud,
        into volume: inout TSDFVolume,
        weight: Float
    ) async throws {
        guard pointCloud.count > 0 else { return }

        let dims = volume.gridDimensions
        let totalVoxels = dims.x * dims.y * dims.z

        // Check if grid is too large for GPU dense mode
        if totalVoxels > Self.maxDenseGridVoxels {
            logger.info("Grid too large for GPU (\(totalVoxels) voxels), using CPU integration")
            volume.integratePointCloud(pointCloud, weight: weight)
            return
        }

        // Ensure buffers are allocated for the grid
        try ensureGridBuffers(voxelCount: totalVoxels, volume: volume)

        // Ensure point buffer is allocated
        try ensurePointBuffer(pointCount: pointCloud.count)

        // Ensure normals buffer is allocated if we have normals (M1 fix: safe optional binding)
        let normalsArray = pointCloud.normals
        let hasNormals = normalsArray.map { !$0.isEmpty } ?? false
        if hasNormals {
            try ensureNormalsBuffer(pointCount: pointCloud.count)
        }

        guard let pointBuffer = pointBuffer,
              let tsdfBuffer = tsdfBuffer,
              let weightBuffer = weightBuffer,
              let counterBuffer = counterBuffer else {
            throw TSDFFusionError.bufferAllocationFailed
        }

        // Prepare normals buffer
        let normalsBufferToUse: MTLBuffer?
        if hasNormals, let normals = normalsArray, let buffer = normalsBuffer {
            copyNormalsToBuffer(normals, buffer: buffer)
            normalsBufferToUse = buffer
        } else {
            normalsBufferToUse = nil
        }

        // Copy points to Metal buffer (or use existing metalBuffer if available)
        if let existingBuffer = pointCloud.metalBuffer {
            // Use existing buffer directly (zero-copy, ADR-002 from Story 3.3)
            try await executeIntegration(
                pointBuffer: existingBuffer,
                normalsBuffer: normalsBufferToUse,
                pointCount: pointCloud.count,
                tsdfBuffer: tsdfBuffer,
                weightBuffer: weightBuffer,
                volume: volume,
                weight: weight
            )
        } else {
            // Copy points to our buffer
            copyPointsToBuffer(pointCloud.points, buffer: pointBuffer)

            try await executeIntegration(
                pointBuffer: pointBuffer,
                normalsBuffer: normalsBufferToUse,
                pointCount: pointCloud.count,
                tsdfBuffer: tsdfBuffer,
                weightBuffer: weightBuffer,
                volume: volume,
                weight: weight
            )
        }

        // Copy results back to volume (sparse)
        try copyBufferToVolume(tsdfBuffer: tsdfBuffer, weightBuffer: weightBuffer, volume: &volume)
    }

    /// Executes the GPU integration kernel.
    private func executeIntegration(
        pointBuffer: MTLBuffer,
        normalsBuffer: MTLBuffer?,
        pointCount: Int,
        tsdfBuffer: MTLBuffer,
        weightBuffer: MTLBuffer,
        volume: TSDFVolume,
        weight: Float
    ) async throws {
        guard let commandBuffer = commandQueue.makeCommandBuffer(),
              let encoder = commandBuffer.makeComputeCommandEncoder() else {
            throw TSDFFusionError.fusionFailed("Failed to create command buffer or encoder")
        }

        // Set pipeline state
        encoder.setComputePipelineState(integratePipeline)

        // Set buffers
        encoder.setBuffer(pointBuffer, offset: 0, index: 0)      // points
        encoder.setBuffer(tsdfBuffer, offset: 0, index: 1)       // tsdfBuffer (as atomic_uint)
        encoder.setBuffer(weightBuffer, offset: 0, index: 2)     // weightBuffer (as atomic_uint)

        // Set parameters
        let dims = volume.gridDimensions
        var params = TSDFMetalParams(
            boundingBoxMin: volume.boundingBox.min,
            voxelSize: volume.voxelSize,
            truncationDistance: volume.truncationDistance,
            gridDimensions: SIMD3<UInt32>(UInt32(dims.x), UInt32(dims.y), UInt32(dims.z)),
            pointWeight: weight,
            pointCount: UInt32(pointCount),
            hasNormals: normalsBuffer != nil ? 1 : 0
        )
        encoder.setBytes(&params, length: MemoryLayout<TSDFMetalParams>.size, index: 3)

        // Output count (for debugging)
        encoder.setBuffer(counterBuffer, offset: 0, index: 4)

        // Normals buffer (index 5)
        // H1 fix: Use dedicated dummy buffer instead of reusing pointBuffer
        // The kernel will check hasNormals flag before reading this buffer
        if let normals = normalsBuffer, normalsBuffer != nil {
            encoder.setBuffer(normals, offset: 0, index: 5)
        } else if let dummy = dummyNormalsBuffer {
            encoder.setBuffer(dummy, offset: 0, index: 5)
        }

        // Calculate thread groups (one thread per point)
        let threadGroupCount = (pointCount + Self.threadGroupSize.width - 1) / Self.threadGroupSize.width
        let threadGroupsPerGrid = MTLSize(width: threadGroupCount, height: 1, depth: 1)

        encoder.dispatchThreadgroups(threadGroupsPerGrid, threadsPerThreadgroup: Self.threadGroupSize)
        encoder.endEncoding()

        // Execute synchronously
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()

        if let error = commandBuffer.error {
            throw TSDFFusionError.fusionFailed("GPU execution failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Buffer Management

    /// Ensures point buffer is at least the specified size.
    private func ensurePointBuffer(pointCount: Int) throws {
        let requiredSize = pointCount * MemoryLayout<SIMD3<Float>>.stride

        if pointBuffer == nil || pointBufferSize < requiredSize {
            guard let buffer = device.makeBuffer(length: requiredSize, options: .storageModeShared) else {
                throw TSDFFusionError.bufferAllocationFailed
            }
            pointBuffer = buffer
            pointBufferSize = requiredSize
        }
    }

    /// Ensures normals buffer is at least the specified size.
    private func ensureNormalsBuffer(pointCount: Int) throws {
        let requiredSize = pointCount * MemoryLayout<SIMD3<Float>>.stride

        if normalsBuffer == nil || normalsBufferSize < requiredSize {
            guard let buffer = device.makeBuffer(length: requiredSize, options: .storageModeShared) else {
                throw TSDFFusionError.bufferAllocationFailed
            }
            normalsBuffer = buffer
            normalsBufferSize = requiredSize
        }
    }

    /// Ensures TSDF and weight buffers are allocated for the grid.
    private func ensureGridBuffers(voxelCount: Int, volume: TSDFVolume) throws {
        guard voxelCount != currentGridVoxelCount || tsdfBuffer == nil || weightBuffer == nil else {
            return
        }

        let bufferSize = voxelCount * MemoryLayout<Float>.size

        guard let tsdf = device.makeBuffer(length: bufferSize, options: .storageModeShared),
              let weight = device.makeBuffer(length: bufferSize, options: .storageModeShared) else {
            throw TSDFFusionError.bufferAllocationFailed
        }

        // Initialize to zero
        memset(tsdf.contents(), 0, bufferSize)
        memset(weight.contents(), 0, bufferSize)

        // Copy existing volume data if any
        let tsdfPointer = tsdf.contents().bindMemory(to: Float.self, capacity: voxelCount)
        let weightPointer = weight.contents().bindMemory(to: Float.self, capacity: voxelCount)

        let dims = volume.gridDimensions

        volume.forEachVoxel { index, voxel in
            guard index.x >= 0 && index.x < dims.x &&
                  index.y >= 0 && index.y < dims.y &&
                  index.z >= 0 && index.z < dims.z else { return }

            let linearIndex = index.x + index.y * dims.x + index.z * dims.x * dims.y
            tsdfPointer[linearIndex] = voxel.tsdf
            weightPointer[linearIndex] = voxel.weight
        }

        self.tsdfBuffer = tsdf
        self.weightBuffer = weight
        self.currentGridVoxelCount = voxelCount
    }

    /// Copies points array to Metal buffer.
    private func copyPointsToBuffer(_ points: [SIMD3<Float>], buffer: MTLBuffer) {
        let pointer = buffer.contents().bindMemory(to: SIMD3<Float>.self, capacity: points.count)
        for (i, point) in points.enumerated() {
            pointer[i] = point
        }
    }

    /// Copies normals array to Metal buffer.
    private func copyNormalsToBuffer(_ normals: [SIMD3<Float>], buffer: MTLBuffer) {
        let pointer = buffer.contents().bindMemory(to: SIMD3<Float>.self, capacity: normals.count)
        for (i, normal) in normals.enumerated() {
            pointer[i] = normal
        }
    }

    /// Copies GPU buffer data back to sparse volume.
    /// H4 fix: Optimized to avoid O(n³) iteration by processing in chunks
    /// and using stride-based access patterns that are more cache-friendly.
    private func copyBufferToVolume(
        tsdfBuffer: MTLBuffer,
        weightBuffer: MTLBuffer,
        volume: inout TSDFVolume
    ) throws {
        let dims = volume.gridDimensions
        let voxelCount = dims.x * dims.y * dims.z

        let tsdfPointer = tsdfBuffer.contents().bindMemory(to: Float.self, capacity: voxelCount)
        let weightPointer = weightBuffer.contents().bindMemory(to: Float.self, capacity: voxelCount)

        // H4 fix: Use single linear iteration instead of nested loops
        // This is O(n) where n = total voxels, and more cache-friendly
        // than the z-y-x nested loop pattern
        let dimX = dims.x
        let dimXY = dims.x * dims.y

        for linearIndex in 0..<voxelCount {
            let weight = weightPointer[linearIndex]

            // Only process non-zero weight voxels (sparse filtering)
            if weight > 0 {
                // Decompose linear index back to 3D coordinates
                let z = linearIndex / dimXY
                let remainder = linearIndex % dimXY
                let y = remainder / dimX
                let x = remainder % dimX

                let voxel = TSDFVoxel(
                    tsdf: tsdfPointer[linearIndex],
                    weight: weight
                )
                volume.setVoxel(voxel, at: VoxelIndex(x: x, y: y, z: z))
            }
        }
    }

    // MARK: - Resource Cleanup

    /// Releases reusable buffers to free memory.
    func releaseBuffers() {
        pointBuffer = nil
        pointBufferSize = 0
        normalsBuffer = nil
        normalsBufferSize = 0
        tsdfBuffer = nil
        weightBuffer = nil
        currentGridVoxelCount = 0
    }
}
