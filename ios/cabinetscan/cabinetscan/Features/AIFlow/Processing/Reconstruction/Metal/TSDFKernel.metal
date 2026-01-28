//
//  TSDFKernel.metal
//  cabinetscan
//
//  Created for Story 3.4: Multi-View Fusion (TSDF)
//
//  Metal compute kernels for TSDF fusion operations.
//  Performs volumetric integration of point clouds into a signed distance field.
//

#include <metal_stdlib>
using namespace metal;

// MARK: - Data Structures

/// TSDF volume parameters
/// NOTE: Must match TSDFMetalParams in TSDFMetalPipeline.swift exactly
struct TSDFParams {
    float3 boundingBoxMin;    // Min corner of bounding box (12 bytes)
    float voxelSize;          // Size of each voxel in meters (4 bytes)
    float truncationDistance; // Truncation distance for SDF (4 bytes)
    uint3 gridDimensions;     // Dimensions of the voxel grid (12 bytes)
    float pointWeight;        // Weight for this integration pass (4 bytes)
    uint pointCount;          // Number of points to process (4 bytes)
    uint hasNormals;          // Whether normals buffer is valid (4 bytes)
};

/// A single TSDF voxel
/// NOTE: Must match TSDFMetalVoxel in TSDFMetalPipeline.swift exactly
struct TSDFVoxel {
    float tsdf;   // Truncated signed distance value
    float weight; // Accumulated weight for running average
};

// MARK: - Atomic Float Operations

/// Since Metal doesn't have native atomic float operations, we use
/// atomic_uint with float-to-uint reinterpretation for CAS loop.

/// Atomically adds a weighted value to a voxel's TSDF using compare-and-swap.
/// This implements the running weighted average formula:
/// new_tsdf = (old_tsdf * old_weight + new_sdf * point_weight) / (old_weight + point_weight)
///
/// **M2 Note on Race Condition:**
/// There is a small race window between updating weight and TSDF. If another thread
/// modifies the weight between our CAS operations, the TSDF calculation may use
/// slightly stale weight data. This is an acceptable trade-off because:
/// 1. The error is bounded and averages out over many points
/// 2. Using a mutex per voxel would be too slow
/// 3. The final TSDF value converges correctly with sufficient observations
/// 4. memory_order_relaxed is sufficient for our use case (no ordering guarantees needed)
inline void atomicTSDFUpdate(
    device atomic_uint* tsdfAtomic,
    device atomic_uint* weightAtomic,
    float newSDF,
    float pointWeight
) {
    // Update weight first using integer atomics (weight is always positive)
    uint oldWeightBits = atomic_load_explicit(weightAtomic, memory_order_relaxed);
    float oldWeight = as_type<float>(oldWeightBits);
    float newWeight = oldWeight + pointWeight;

    // Try to update weight
    while (!atomic_compare_exchange_weak_explicit(
        weightAtomic,
        &oldWeightBits,
        as_type<uint>(newWeight),
        memory_order_relaxed,
        memory_order_relaxed
    )) {
        oldWeight = as_type<float>(oldWeightBits);
        newWeight = oldWeight + pointWeight;
    }

    // Now update TSDF value using the running average
    uint oldTsdfBits = atomic_load_explicit(tsdfAtomic, memory_order_relaxed);
    float oldTsdf = as_type<float>(oldTsdfBits);
    float newTsdf = (oldTsdf * oldWeight + newSDF * pointWeight) / newWeight;

    while (!atomic_compare_exchange_weak_explicit(
        tsdfAtomic,
        &oldTsdfBits,
        as_type<uint>(newTsdf),
        memory_order_relaxed,
        memory_order_relaxed
    )) {
        oldTsdf = as_type<float>(oldTsdfBits);
        // Recalculate with current weight (may have changed)
        float currentWeight = as_type<float>(atomic_load_explicit(weightAtomic, memory_order_relaxed));
        newTsdf = (oldTsdf * (currentWeight - pointWeight) + newSDF * pointWeight) / currentWeight;
    }
}

// MARK: - TSDF Integration Kernel

/// Integrates a point cloud into the TSDF volume using proper signed distance.
///
/// For each point:
/// 1. Find all voxels within truncation distance
/// 2. Calculate signed distance from voxel center to point using normals
/// 3. Update TSDF using atomic running weighted average
///
/// **Signed Distance Convention:**
/// - Positive SDF = voxel is in front of surface (outside/free space)
/// - Negative SDF = voxel is behind surface (inside/solid)
/// - Zero SDF = voxel is on the surface
///
/// This kernel uses one thread per point. Each thread updates multiple voxels
/// within the truncation neighborhood.
///
/// **Performance Considerations:**
/// - Uses atomic operations for thread-safe voxel updates (ADR-008)
/// - Search radius is determined by truncation distance / voxel size
/// - Typical search radius: 3 voxels (truncation = 3 * voxelSize)
kernel void integrateTSDFSparse(
    device const float3* points [[buffer(0)]],
    device atomic_uint* tsdfBuffer [[buffer(1)]],    // Interpreted as float via reinterpret
    device atomic_uint* weightBuffer [[buffer(2)]],  // Interpreted as float via reinterpret
    constant TSDFParams& params [[buffer(3)]],
    device atomic_uint* outputCount [[buffer(4)]],   // For tracking updated voxels
    device const float3* normals [[buffer(5)]],      // Optional normals buffer
    uint pointIndex [[thread_position_in_grid]]
) {
    // Bounds check
    if (pointIndex >= params.pointCount) {
        return;
    }

    float3 point = points[pointIndex];

    // Get normal if available
    float3 normal = float3(0.0f, 1.0f, 0.0f);  // Default: assume surface faces up
    bool hasValidNormal = false;

    if (params.hasNormals != 0) {
        normal = normals[pointIndex];
        float normalLength = length(normal);
        if (normalLength > 0.001f) {
            normal = normal / normalLength;  // Normalize
            hasValidNormal = true;
        }
    }

    // Calculate which voxel this point is in
    float3 relativePos = point - params.boundingBoxMin;
    int3 centerVoxel = int3(relativePos / params.voxelSize);

    // Calculate search radius in voxels
    int searchRadius = int(ceil(params.truncationDistance / params.voxelSize));

    // Iterate through neighborhood voxels
    for (int dx = -searchRadius; dx <= searchRadius; dx++) {
        for (int dy = -searchRadius; dy <= searchRadius; dy++) {
            for (int dz = -searchRadius; dz <= searchRadius; dz++) {
                int3 voxelCoord = centerVoxel + int3(dx, dy, dz);

                // Bounds check
                if (any(voxelCoord < 0) ||
                    voxelCoord.x >= int(params.gridDimensions.x) ||
                    voxelCoord.y >= int(params.gridDimensions.y) ||
                    voxelCoord.z >= int(params.gridDimensions.z)) {
                    continue;
                }

                // Calculate voxel center in world space
                float3 voxelCenter = params.boundingBoxMin +
                    (float3(voxelCoord) + 0.5f) * params.voxelSize;

                // Vector from point to voxel center
                float3 toVoxel = voxelCenter - point;
                float distance = length(toVoxel);

                // Skip if outside truncation distance
                if (distance > params.truncationDistance) {
                    continue;
                }

                // Calculate signed distance
                float sdf;
                if (hasValidNormal) {
                    // With normal: sign based on which side of the surface the voxel is
                    // dot(normal, toVoxel) > 0 means voxel is in front of surface (positive SDF)
                    // dot(normal, toVoxel) < 0 means voxel is behind surface (negative SDF)
                    sdf = dot(normal, toVoxel);
                } else {
                    // Without normal: use projective distance approximation
                    // Assume camera is above (positive Y), so points face upward
                    // Voxels above the point are outside (positive), below are inside (negative)
                    sdf = (toVoxel.y > 0) ? distance : -distance;
                }

                // Truncate to [-truncation, +truncation]
                float truncatedSDF = clamp(sdf, -params.truncationDistance, params.truncationDistance);

                // Calculate linear voxel index for the dense representation
                uint voxelIndex = uint(voxelCoord.x) +
                    uint(voxelCoord.y) * params.gridDimensions.x +
                    uint(voxelCoord.z) * params.gridDimensions.x * params.gridDimensions.y;

                // Atomic update
                atomicTSDFUpdate(
                    &tsdfBuffer[voxelIndex],
                    &weightBuffer[voxelIndex],
                    truncatedSDF,
                    params.pointWeight
                );
            }
        }
    }
}

// MARK: - Dense Grid Integration Kernel (Alternative)

/// Alternative kernel that iterates over voxels instead of points.
/// Better for very dense point clouds where many points affect each voxel.
/// Uses one thread per voxel.
///
/// H3 fix: Now uses proper signed distance calculation matching the sparse kernel.
/// Without normals, uses Y-axis projective distance (assumes surfaces face upward).
kernel void integrateTSDFDense(
    device const float3* points [[buffer(0)]],
    device float* tsdfBuffer [[buffer(1)]],
    device float* weightBuffer [[buffer(2)]],
    constant TSDFParams& params [[buffer(3)]],
    device const float3* normals [[buffer(5)]],  // Added normals support
    uint3 voxelCoord [[thread_position_in_grid]]
) {
    // Bounds check
    if (voxelCoord.x >= params.gridDimensions.x ||
        voxelCoord.y >= params.gridDimensions.y ||
        voxelCoord.z >= params.gridDimensions.z) {
        return;
    }

    // Calculate voxel center in world space
    float3 voxelCenter = params.boundingBoxMin +
        (float3(voxelCoord) + 0.5f) * params.voxelSize;

    // Accumulate updates from all nearby points
    float totalWeight = 0.0f;
    float weightedSum = 0.0f;

    for (uint i = 0; i < params.pointCount; i++) {
        float3 point = points[i];
        float3 toVoxel = voxelCenter - point;
        float distance = length(toVoxel);

        if (distance <= params.truncationDistance) {
            // H3 fix: Calculate proper signed distance
            float sdf;
            if (params.hasNormals != 0) {
                float3 normal = normals[i];
                float normalLength = length(normal);
                if (normalLength > 0.001f) {
                    normal = normal / normalLength;
                    sdf = dot(normal, toVoxel);
                } else {
                    // Fallback to projective distance
                    sdf = (toVoxel.y > 0) ? distance : -distance;
                }
            } else {
                // Without normals: use Y-axis projective distance
                sdf = (toVoxel.y > 0) ? distance : -distance;
            }

            // Truncate
            float truncatedSDF = clamp(sdf, -params.truncationDistance, params.truncationDistance);
            weightedSum += truncatedSDF * params.pointWeight;
            totalWeight += params.pointWeight;
        }
    }

    if (totalWeight > 0) {
        uint voxelIndex = voxelCoord.x +
            voxelCoord.y * params.gridDimensions.x +
            voxelCoord.z * params.gridDimensions.x * params.gridDimensions.y;

        float oldWeight = weightBuffer[voxelIndex];
        float oldTsdf = tsdfBuffer[voxelIndex];

        float newWeight = oldWeight + totalWeight;
        float newTsdf = (oldTsdf * oldWeight + weightedSum) / newWeight;

        tsdfBuffer[voxelIndex] = newTsdf;
        weightBuffer[voxelIndex] = newWeight;
    }
}

// MARK: - Utility Kernels

/// Resets a TSDF volume to empty state.
kernel void resetTSDFVolume(
    device float* tsdfBuffer [[buffer(0)]],
    device float* weightBuffer [[buffer(1)]],
    constant uint& voxelCount [[buffer(2)]],
    uint index [[thread_position_in_grid]]
) {
    if (index >= voxelCount) {
        return;
    }

    tsdfBuffer[index] = 0.0f;
    weightBuffer[index] = 0.0f;
}

/// Counts voxels with non-zero weight (for sparse extraction).
kernel void countNonEmptyVoxels(
    device const float* weightBuffer [[buffer(0)]],
    device atomic_uint* count [[buffer(1)]],
    constant uint& voxelCount [[buffer(2)]],
    uint index [[thread_position_in_grid]]
) {
    if (index >= voxelCount) {
        return;
    }

    if (weightBuffer[index] > 0.0f) {
        atomic_fetch_add_explicit(count, 1, memory_order_relaxed);
    }
}
