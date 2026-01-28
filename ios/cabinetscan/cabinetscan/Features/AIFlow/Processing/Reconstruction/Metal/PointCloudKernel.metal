//
//  PointCloudKernel.metal
//  cabinetscan
//
//  Created for Story 3.3: Point Cloud Generation
//
//  Metal compute kernel for converting depth maps to 3D point clouds.
//  Performs depth unprojection and world transformation in a single pass.
//

#include <metal_stdlib>
using namespace metal;

// MARK: - Data Structures

/// Camera intrinsic parameters.
/// Note (ADR-005): These are already zoom-adjusted by ARKit - do NOT multiply by zoomFactor.
struct CameraIntrinsics {
    float fx;  // Focal length X (pixels) - already zoom-adjusted
    float fy;  // Focal length Y (pixels) - already zoom-adjusted
    float cx;  // Principal point X (pixels) - already zoom-adjusted
    float cy;  // Principal point Y (pixels) - already zoom-adjusted
};

/// Kernel parameters packed into a single struct for efficient transfer
/// NOTE: Must match MetalKernelParams in PointCloudMetalPipeline.swift exactly
struct KernelParams {
    uint2 dimensions;        // Width and height of depth map (8 bytes)
    uint2 outputDimensions;  // Width and height after downsampling (8 bytes)
    int downsampleFactor;    // Downsampling step (1 = no downsample, 2 = every other pixel) (4 bytes)
    float minDepth;          // Minimum valid depth (ADR-004: 0.001) (4 bytes)
    float maxDepth;          // Maximum valid depth (ADR-004: 0.999) (4 bytes)
    float _padding;          // Explicit padding to match Swift struct (4 bytes)
};

// MARK: - Depth to Point Cloud Kernel

/// Converts a depth map to a 3D point cloud in world coordinates.
///
/// This kernel performs the following operations per pixel:
/// 1. Reads depth value and validates it (ADR-004)
/// 2. Unprojects to camera space using intrinsics (ADR-005: no zoom adjustment)
/// 3. Transforms to world space using pose matrix
/// 4. Outputs the world-space point
///
/// **Performance Target:** <20ms per frame (518x518 = 268K pixels)
///
/// - Parameters:
///   - depthBuffer: Input depth values (height x width, row-major)
///   - pointBuffer: Output 3D points in world space
///   - validCount: Atomic counter for number of valid points
///   - intrinsics: Camera intrinsic parameters
///   - poseTransform: 4x4 world transformation matrix
///   - params: Kernel parameters (dimensions, downsampling, depth thresholds)
///   - gid: Thread position in 2D grid
kernel void depthToPointCloud(
    device const float* depthBuffer [[buffer(0)]],
    device float3* pointBuffer [[buffer(1)]],
    device atomic_uint* validCount [[buffer(2)]],
    constant CameraIntrinsics& intrinsics [[buffer(3)]],
    constant float4x4& poseTransform [[buffer(4)]],
    constant KernelParams& params [[buffer(5)]],
    uint2 gid [[thread_position_in_grid]]
) {
    // Check bounds (accounting for downsampling)
    if (gid.x >= params.outputDimensions.x || gid.y >= params.outputDimensions.y) {
        return;
    }

    // Map output coordinates to input coordinates (for downsampling)
    uint inputX = gid.x * params.downsampleFactor;
    uint inputY = gid.y * params.downsampleFactor;

    // Ensure we're within input bounds
    if (inputX >= params.dimensions.x || inputY >= params.dimensions.y) {
        return;
    }

    // Read depth value
    uint pixelIndex = inputY * params.dimensions.x + inputX;
    float depth = depthBuffer[pixelIndex];

    // Filter invalid depths (ADR-004)
    // Valid range: 0.001 to 0.999 for relative depth
    if (depth < params.minDepth || depth > params.maxDepth || isnan(depth)) {
        return;
    }

    // Unproject to camera space using pinhole camera model
    // Note (ADR-005): intrinsics are already zoom-adjusted by ARKit
    float x = (float(inputX) - intrinsics.cx) * depth / intrinsics.fx;
    float y = (float(inputY) - intrinsics.cy) * depth / intrinsics.fy;
    float z = depth;

    // Transform to world space
    float4 cameraPoint = float4(x, y, z, 1.0);
    float4 worldPoint = poseTransform * cameraPoint;

    // Store result using atomic counter for thread-safe output indexing
    uint outputIndex = atomic_fetch_add_explicit(validCount, 1, memory_order_relaxed);
    pointBuffer[outputIndex] = worldPoint.xyz;
}

// MARK: - Separate Kernels (for flexibility)

/// Depth to camera-space points only (without world transform).
/// Useful for debugging or when transform is applied separately.
kernel void depthToCameraSpace(
    device const float* depthBuffer [[buffer(0)]],
    device float3* pointBuffer [[buffer(1)]],
    device atomic_uint* validCount [[buffer(2)]],
    constant CameraIntrinsics& intrinsics [[buffer(3)]],
    constant KernelParams& params [[buffer(4)]],
    uint2 gid [[thread_position_in_grid]]
) {
    if (gid.x >= params.outputDimensions.x || gid.y >= params.outputDimensions.y) {
        return;
    }

    uint inputX = gid.x * params.downsampleFactor;
    uint inputY = gid.y * params.downsampleFactor;

    if (inputX >= params.dimensions.x || inputY >= params.dimensions.y) {
        return;
    }

    uint pixelIndex = inputY * params.dimensions.x + inputX;
    float depth = depthBuffer[pixelIndex];

    if (depth < params.minDepth || depth > params.maxDepth || isnan(depth)) {
        return;
    }

    float x = (float(inputX) - intrinsics.cx) * depth / intrinsics.fx;
    float y = (float(inputY) - intrinsics.cy) * depth / intrinsics.fy;
    float z = depth;

    uint outputIndex = atomic_fetch_add_explicit(validCount, 1, memory_order_relaxed);
    pointBuffer[outputIndex] = float3(x, y, z);
}

/// Transforms camera-space points to world space.
/// Applied after depthToCameraSpace if needed separately.
kernel void transformToWorldSpace(
    device const float3* cameraPoints [[buffer(0)]],
    device float3* worldPoints [[buffer(1)]],
    constant float4x4& poseTransform [[buffer(2)]],
    constant uint& pointCount [[buffer(3)]],
    uint gid [[thread_position_in_grid]]
) {
    if (gid >= pointCount) {
        return;
    }

    float3 cameraPoint = cameraPoints[gid];
    float4 homogeneous = float4(cameraPoint, 1.0);
    float4 worldPoint = poseTransform * homogeneous;

    worldPoints[gid] = worldPoint.xyz;
}
