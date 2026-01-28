//
//  PointCloudMetalPipeline.swift
//  cabinetscan
//
//  Created for Story 3.3: Point Cloud Generation
//

import Foundation
import Metal
import simd
import os.log

// MARK: - Metal Pipeline Data Structures

/// Camera intrinsics struct matching Metal shader layout
struct MetalCameraIntrinsics {
    var fx: Float
    var fy: Float
    var cx: Float
    var cy: Float

    init(from intrinsics: AICameraIntrinsics) {
        self.fx = intrinsics.fx
        self.fy = intrinsics.fy
        self.cx = intrinsics.cx
        self.cy = intrinsics.cy
    }
}

/// Kernel parameters struct matching Metal shader layout
struct MetalKernelParams {
    var dimensions: SIMD2<UInt32>
    var outputDimensions: SIMD2<UInt32>
    var downsampleFactor: Int32
    var minDepth: Float
    var maxDepth: Float

    // Padding to ensure proper alignment
    var _padding: Float = 0
}

// MARK: - Point Cloud Metal Pipeline

/// Manages Metal resources and executes GPU compute kernels for point cloud generation.
///
/// **ADR-001:** Metal is REQUIRED for production - this pipeline must succeed on all iOS 17+ devices.
/// **ADR-002:** Outputs to MTLBuffer for zero-copy handoff to TSDF fusion.
final class PointCloudMetalPipeline {

    // MARK: - Constants

    /// Depth filtering thresholds (ADR-004)
    private static let minValidDepth: Float = 0.001
    private static let maxValidDepth: Float = 0.999

    /// Thread group size for compute kernels
    private static let threadGroupSize = MTLSize(width: 16, height: 16, depth: 1)

    // MARK: - Metal Resources

    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private let depthToPointCloudPipeline: MTLComputePipelineState

    private let logger = Logger(subsystem: "com.cabinetscan", category: "PointCloudMetalPipeline")

    // MARK: - Buffer Pool (for reuse)

    /// Reusable depth buffer (resized as needed)
    private var depthBuffer: MTLBuffer?
    private var depthBufferSize: Int = 0

    /// Reusable output buffer (resized as needed)
    private var outputBuffer: MTLBuffer?
    private var outputBufferSize: Int = 0

    /// Reusable counter buffer (4 bytes for atomic_uint)
    private var counterBuffer: MTLBuffer?

    // MARK: - Initialization

    /// Creates a Metal pipeline for point cloud generation.
    ///
    /// - Parameter device: Metal device to use
    /// - Throws: PointCloudGenerationError if pipeline creation fails
    init(device: MTLDevice) throws {
        self.device = device

        // Create command queue
        guard let queue = device.makeCommandQueue() else {
            throw PointCloudGenerationError.pipelineCreationFailed("Failed to create command queue")
        }
        self.commandQueue = queue

        // Load shader library
        guard let library = device.makeDefaultLibrary() else {
            throw PointCloudGenerationError.pipelineCreationFailed("Failed to load default Metal library")
        }

        // Create compute pipeline for depth-to-point-cloud kernel
        guard let kernelFunction = library.makeFunction(name: "depthToPointCloud") else {
            throw PointCloudGenerationError.pipelineCreationFailed("Failed to find depthToPointCloud kernel function")
        }

        do {
            self.depthToPointCloudPipeline = try device.makeComputePipelineState(function: kernelFunction)
        } catch {
            throw PointCloudGenerationError.pipelineCreationFailed("Failed to create pipeline state: \(error.localizedDescription)")
        }

        // Create counter buffer (reused across all invocations)
        guard let counter = device.makeBuffer(length: MemoryLayout<UInt32>.size, options: .storageModeShared) else {
            throw PointCloudGenerationError.bufferAllocationFailed
        }
        self.counterBuffer = counter

        logger.info("Metal pipeline initialized successfully")
    }

    // MARK: - Point Cloud Generation

    /// Generates a point cloud from a depth frame using GPU compute.
    ///
    /// - Parameters:
    ///   - depthFrame: Depth frame to convert
    ///   - downsampleFactor: Factor to downsample by (1 = no downsampling)
    /// - Returns: Generated point cloud with Metal buffer for zero-copy access
    /// - Throws: PointCloudGenerationError on failure
    func generatePointCloud(
        from depthFrame: AIDepthFrame,
        downsampleFactor: Int = 1
    ) throws -> AIPointCloud {
        let width = depthFrame.width
        let height = depthFrame.height
        let depthData = depthFrame.depthData

        // Calculate output dimensions after downsampling
        let outputWidth = (width + downsampleFactor - 1) / downsampleFactor
        let outputHeight = (height + downsampleFactor - 1) / downsampleFactor
        let maxOutputPoints = outputWidth * outputHeight

        // Ensure buffers are allocated
        try ensureDepthBuffer(size: width * height * MemoryLayout<Float>.size)
        try ensureOutputBuffer(size: maxOutputPoints * MemoryLayout<SIMD3<Float>>.stride)

        guard let depthBuffer = depthBuffer,
              let outputBuffer = outputBuffer,
              let counterBuffer = counterBuffer else {
            throw PointCloudGenerationError.bufferAllocationFailed
        }

        // Copy depth data to Metal buffer
        copyDepthDataToBuffer(depthData, buffer: depthBuffer, width: width, height: height)

        // Reset counter
        let counterPointer = counterBuffer.contents().bindMemory(to: UInt32.self, capacity: 1)
        counterPointer.pointee = 0

        // Create command buffer
        guard let commandBuffer = commandQueue.makeCommandBuffer(),
              let encoder = commandBuffer.makeComputeCommandEncoder() else {
            throw PointCloudGenerationError.processingFailed("Failed to create command buffer or encoder")
        }

        // Set pipeline state
        encoder.setComputePipelineState(depthToPointCloudPipeline)

        // Set buffers
        encoder.setBuffer(depthBuffer, offset: 0, index: 0)      // depthBuffer
        encoder.setBuffer(outputBuffer, offset: 0, index: 1)     // pointBuffer
        encoder.setBuffer(counterBuffer, offset: 0, index: 2)    // validCount

        // Set intrinsics (ADR-005: use directly without zoom adjustment)
        var intrinsics = MetalCameraIntrinsics(from: depthFrame.pose.intrinsics)
        encoder.setBytes(&intrinsics, length: MemoryLayout<MetalCameraIntrinsics>.size, index: 3)

        // Set pose transform
        var transform = depthFrame.pose.transform
        encoder.setBytes(&transform, length: MemoryLayout<simd_float4x4>.size, index: 4)

        // Set kernel parameters
        var params = MetalKernelParams(
            dimensions: SIMD2<UInt32>(UInt32(width), UInt32(height)),
            outputDimensions: SIMD2<UInt32>(UInt32(outputWidth), UInt32(outputHeight)),
            downsampleFactor: Int32(downsampleFactor),
            minDepth: Self.minValidDepth,
            maxDepth: Self.maxValidDepth
        )
        encoder.setBytes(&params, length: MemoryLayout<MetalKernelParams>.size, index: 5)

        // Calculate thread groups
        let threadGroupsPerGrid = MTLSize(
            width: (outputWidth + Self.threadGroupSize.width - 1) / Self.threadGroupSize.width,
            height: (outputHeight + Self.threadGroupSize.height - 1) / Self.threadGroupSize.height,
            depth: 1
        )

        encoder.dispatchThreadgroups(threadGroupsPerGrid, threadsPerThreadgroup: Self.threadGroupSize)
        encoder.endEncoding()

        // Execute and wait
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()

        // Check for errors
        if let error = commandBuffer.error {
            throw PointCloudGenerationError.processingFailed("GPU execution failed: \(error.localizedDescription)")
        }

        // Read valid point count
        let validPointCount = Int(counterPointer.pointee)

        // Log filtered point percentage for quality monitoring (ADR-004)
        let filteredCount = maxOutputPoints - validPointCount
        if maxOutputPoints > 0 {
            let filteredPercentage = Double(filteredCount) / Double(maxOutputPoints) * 100.0
            logger.debug("GPU point cloud: \(validPointCount) valid points, \(filteredCount)/\(maxOutputPoints) filtered (\(String(format: "%.1f", filteredPercentage))%)")
        }

        // Create new buffer with exact size for the result (ADR-002: keep in GPU memory)
        let resultBufferSize = validPointCount * MemoryLayout<SIMD3<Float>>.stride
        guard let resultBuffer = device.makeBuffer(length: max(resultBufferSize, 1), options: .storageModeShared) else {
            throw PointCloudGenerationError.bufferAllocationFailed
        }

        // Copy valid points to result buffer
        if validPointCount > 0 {
            memcpy(resultBuffer.contents(), outputBuffer.contents(), resultBufferSize)
        }

        return AIPointCloud(
            points: [],  // Empty - use metalBuffer instead (ADR-002)
            colors: nil,
            normals: nil,
            metalBuffer: resultBuffer,
            pointCount: validPointCount
        )
    }

    // MARK: - Buffer Management

    /// Ensures the depth buffer is at least the specified size.
    private func ensureDepthBuffer(size: Int) throws {
        if depthBuffer == nil || depthBufferSize < size {
            guard let buffer = device.makeBuffer(length: size, options: .storageModeShared) else {
                throw PointCloudGenerationError.bufferAllocationFailed
            }
            depthBuffer = buffer
            depthBufferSize = size
        }
    }

    /// Ensures the output buffer is at least the specified size.
    private func ensureOutputBuffer(size: Int) throws {
        if outputBuffer == nil || outputBufferSize < size {
            guard let buffer = device.makeBuffer(length: size, options: .storageModeShared) else {
                throw PointCloudGenerationError.bufferAllocationFailed
            }
            outputBuffer = buffer
            outputBufferSize = size
        }
    }

    /// Copies 2D depth data array to a flat Metal buffer.
    private func copyDepthDataToBuffer(_ depthData: [[Float]], buffer: MTLBuffer, width: Int, height: Int) {
        let pointer = buffer.contents().bindMemory(to: Float.self, capacity: width * height)

        for y in 0..<height {
            for x in 0..<width {
                pointer[y * width + x] = depthData[y][x]
            }
        }
    }

    // MARK: - Resource Cleanup

    /// Releases reusable buffers to free memory.
    /// Call this when point cloud generation is complete for all frames.
    func releaseBuffers() {
        depthBuffer = nil
        depthBufferSize = 0
        outputBuffer = nil
        outputBufferSize = 0
        // Keep counterBuffer - it's tiny (4 bytes)
    }
}
