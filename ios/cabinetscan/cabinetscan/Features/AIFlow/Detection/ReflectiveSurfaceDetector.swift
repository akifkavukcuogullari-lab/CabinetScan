//
//  ReflectiveSurfaceDetector.swift
//  cabinetscan
//
//  Created for Story 6.4: Reflective Surface Handling
//

import Foundation
import Combine
import simd
import os.log

// MARK: - Reflective Surface Analysis Result (Task 1.5)

/// Result of reflective surface analysis containing metrics and detected regions.
///
/// **Usage:**
/// ```swift
/// let result = try await detector.analyzeReflectiveSurfaces(volume: tsdfVolume)
/// if result.highVariancePercentage > 0.1 {
///     warnings.append("Reflective surfaces detected")
/// }
/// ```
struct ReflectiveSurfaceAnalysisResult: Equatable {
    /// Total voxels analyzed
    let totalVoxelsAnalyzed: Int

    /// Number of high-variance voxels detected
    let highVarianceVoxelCount: Int

    /// Percentage of voxels with high variance (0.0 - 1.0)
    var highVariancePercentage: Float {
        guard totalVoxelsAnalyzed > 0 else { return 0 }
        return Float(highVarianceVoxelCount) / Float(totalVoxelsAnalyzed)
    }

    /// Detected reflective surface regions
    let reflectiveRegions: [ReflectiveRegion]

    /// Detected mirror regions (specific type of reflective surface)
    let mirrorRegions: [MirrorRegion]

    /// Impact factor for confidence scoring (0.0 = no impact, 1.0 = severe)
    var confidenceImpact: Float {
        // Impact scales with high-variance percentage
        // 10% high-variance = 0.1 impact, 50% = 0.5 impact, etc.
        // Capped at 1.0
        return min(1.0, highVariancePercentage)
    }

    /// Whether reflective surfaces were detected
    var hasReflectiveSurfaces: Bool {
        !reflectiveRegions.isEmpty || highVariancePercentage > 0.05
    }

    /// Processing time in milliseconds
    let processingTimeMs: Int

    /// Empty result (no analysis performed)
    static let empty = ReflectiveSurfaceAnalysisResult(
        totalVoxelsAnalyzed: 0,
        highVarianceVoxelCount: 0,
        reflectiveRegions: [],
        mirrorRegions: [],
        processingTimeMs: 0
    )
}

// MARK: - Reflective Region

/// A detected region with high depth variance indicating potential reflective surface.
struct ReflectiveRegion: Equatable, Identifiable {
    let id: UUID

    /// Voxel indices that form this region
    let voxelIndices: [VoxelIndex]

    /// Bounding box center in world coordinates
    let center: SIMD3<Float>

    /// Approximate size of the region in meters
    let size: SIMD3<Float>

    /// Average variance in this region
    let averageVariance: Float

    /// Number of voxels in the region
    var voxelCount: Int { voxelIndices.count }

    init(
        id: UUID = UUID(),
        voxelIndices: [VoxelIndex],
        center: SIMD3<Float>,
        size: SIMD3<Float>,
        averageVariance: Float
    ) {
        self.id = id
        self.voxelIndices = voxelIndices
        self.center = center
        self.size = size
        self.averageVariance = averageVariance
    }
}

// MARK: - Mirror Region (Task 3.5)

/// A detected mirror region with wall association.
struct MirrorRegion: Equatable, Identifiable {
    let id: UUID

    /// Bounding box of the mirror region
    let bounds: AIBoundingBox3D

    /// ID of the wall this mirror is on (if associated)
    let wallId: UUID?

    /// Voxel indices that form this region
    let voxelIndices: [VoxelIndex]

    /// Average variance in this region
    let averageVariance: Float

    init(
        id: UUID = UUID(),
        bounds: AIBoundingBox3D,
        wallId: UUID?,
        voxelIndices: [VoxelIndex],
        averageVariance: Float
    ) {
        self.id = id
        self.bounds = bounds
        self.wallId = wallId
        self.voxelIndices = voxelIndices
        self.averageVariance = averageVariance
    }
}

// MARK: - Reflective Surface Detector

/// Detects reflective surfaces in TSDF volumes using depth variance analysis.
///
/// **Architecture Decision (ADR-6.4.1):** Uses depth observation variance to detect
/// reflective surfaces rather than image-based specular highlight detection.
///
/// **Key Insight:** Reflective surfaces produce view-dependent depth errors.
/// Multi-view fusion with variance analysis can detect and filter these inconsistencies.
///
/// **Usage:**
/// ```swift
/// let detector = ReflectiveSurfaceDetector()
/// let result = try await detector.analyzeReflectiveSurfaces(volume: tsdfVolume)
/// if result.hasReflectiveSurfaces {
///     confidenceScorer.applyReflectiveImpact(result.confidenceImpact)
/// }
/// ```
@MainActor
final class ReflectiveSurfaceDetector: ObservableObject {

    // MARK: - Constants (Task 1.6)

    /// Variance threshold for detecting reflective surfaces.
    /// Value of 0.04 corresponds to ~2cm standard deviation in depth.
    /// Voxels with variance above this are flagged as potentially reflective.
    static let varianceThreshold: Float = 0.04

    /// Minimum number of adjacent high-variance voxels to form a reflective region.
    /// Small clusters are likely noise; larger clusters indicate actual reflective surfaces.
    static let clusterMinSize: Int = 5

    /// Maximum distance (in voxel units) for voxels to be considered neighbors in clustering.
    private static let clusterNeighborDistance: Int = 2

    /// Variance threshold multiplier for mirror detection (more lenient than surface detection).
    /// Mirrors may show moderate variance even when not extreme.
    private static let mirrorVarianceMultiplier: Float = 0.5

    /// Tolerance in inches for mirror region validation against room bounds.
    private static let mirrorBoundsToleranceInches: Float = 6.0

    // MARK: - Properties

    private let logger: Logger

    // MARK: - Initialization

    init() {
        self.logger = Logger(subsystem: "com.cabinetscan", category: "ReflectiveSurfaceDetector")
        #if DEBUG
        logger.debug("ReflectiveSurfaceDetector initialized")
        #endif
    }

    // MARK: - Main Analysis (Task 1.4)

    /// Analyzes a TSDF volume for reflective surfaces.
    ///
    /// **Pipeline Position:** Called AFTER TSDF fusion completes, BEFORE ConfidenceScorer.
    ///
    /// - Parameter volume: The fused TSDF volume to analyze
    /// - Returns: Analysis result with detected regions and metrics
    func analyzeReflectiveSurfaces(volume: TSDFVolume) async throws -> ReflectiveSurfaceAnalysisResult {
        let startTime = CFAbsoluteTimeGetCurrent()

        logger.info("Starting reflective surface analysis")

        // Step 1: Collect variance data from all voxels
        var voxelVariances: [(VoxelIndex, Float)] = []
        var totalVoxels = 0

        volume.forEachVoxel { index, voxel in
            // Only analyze voxels with sufficient observations
            guard voxel.weight >= 2.0 else { return }

            totalVoxels += 1

            // Get variance from voxel (requires Task 2 enhancement)
            let variance = voxel.observationVariance
            voxelVariances.append((index, variance))
        }

        // Handle empty volume case (no voxels with sufficient observations)
        if totalVoxels == 0 {
            logger.warning("No voxels with sufficient observations for reflective surface analysis")
            return ReflectiveSurfaceAnalysisResult(
                totalVoxelsAnalyzed: 0,
                highVarianceVoxelCount: 0,
                reflectiveRegions: [],
                mirrorRegions: [],
                processingTimeMs: Int((CFAbsoluteTimeGetCurrent() - startTime) * 1000)
            )
        }

        try Task.checkCancellation()

        // Step 2: Detect high-variance voxels
        let highVarianceVoxels = detectHighVarianceRegions(
            voxelVariances: voxelVariances,
            threshold: Self.varianceThreshold
        )

        logger.info("Found \(highVarianceVoxels.count) high-variance voxels out of \(totalVoxels)")

        try Task.checkCancellation()

        // Create variance lookup for calculating average variance in clusters
        let varianceLookup = Dictionary(uniqueKeysWithValues: voxelVariances)

        // Step 3: Cluster high-variance voxels into regions
        let reflectiveRegions = identifyReflectiveSurfaces(
            highVarianceVoxels: highVarianceVoxels,
            voxelSize: volume.voxelSize,
            varianceLookup: varianceLookup
        )

        let processingTimeMs = Int((CFAbsoluteTimeGetCurrent() - startTime) * 1000)

        logger.info("Reflective surface analysis complete: \(reflectiveRegions.count) regions in \(processingTimeMs)ms")

        return ReflectiveSurfaceAnalysisResult(
            totalVoxelsAnalyzed: totalVoxels,
            highVarianceVoxelCount: highVarianceVoxels.count,
            reflectiveRegions: reflectiveRegions,
            mirrorRegions: [],  // Mirror detection is Task 3
            processingTimeMs: processingTimeMs
        )
    }

    // MARK: - Variance Calculation (Task 1.2)

    /// Calculates the observation variance from a set of TSDF observations.
    ///
    /// Uses the formula: Var(X) = E[X²] - E[X]²
    ///
    /// - Parameter observations: Array of (tsdf, weight) tuples representing observations
    /// - Returns: Calculated variance (0.0 if insufficient data)
    func calculateObservationVariance(observations: [(tsdf: Float, weight: Float)]) -> Float {
        guard observations.count > 1 else { return 0.0 }

        var totalWeight: Float = 0
        var weightedSum: Float = 0
        var weightedSumSquared: Float = 0

        for obs in observations {
            totalWeight += obs.weight
            weightedSum += obs.tsdf * obs.weight
            weightedSumSquared += obs.tsdf * obs.tsdf * obs.weight
        }

        guard totalWeight > 0 else { return 0.0 }

        let mean = weightedSum / totalWeight
        let meanSquared = weightedSumSquared / totalWeight

        // Variance = E[X²] - E[X]²
        let variance = max(0, meanSquared - mean * mean)

        return variance
    }

    // MARK: - High Variance Detection (Task 1.3)

    /// Detects voxels with variance above the threshold.
    ///
    /// - Parameters:
    ///   - voxelVariances: Array of (index, variance) tuples
    ///   - threshold: Variance threshold (default: varianceThreshold)
    /// - Returns: Array of voxel indices with high variance
    func detectHighVarianceRegions(
        voxelVariances: [(VoxelIndex, Float)],
        threshold: Float
    ) -> [VoxelIndex] {
        return voxelVariances
            .filter { $0.1 > threshold }
            .map { $0.0 }
    }

    // MARK: - Reflective Surface Identification (Task 1.4)

    /// Clusters high-variance voxels into reflective surface regions.
    ///
    /// Uses simple spatial clustering - adjacent high-variance voxels form a region.
    /// Only clusters with at least `clusterMinSize` voxels are reported.
    ///
    /// - Parameters:
    ///   - highVarianceVoxels: Voxel indices with high variance
    ///   - voxelSize: Size of each voxel in meters
    ///   - varianceLookup: Dictionary mapping voxel indices to their variance values
    /// - Returns: Array of detected reflective regions
    func identifyReflectiveSurfaces(
        highVarianceVoxels: [VoxelIndex],
        voxelSize: Float,
        varianceLookup: [VoxelIndex: Float] = [:]
    ) -> [ReflectiveRegion] {
        guard !highVarianceVoxels.isEmpty else { return [] }

        // Simple clustering: group adjacent voxels
        var remainingVoxels = Set(highVarianceVoxels)
        var clusters: [[VoxelIndex]] = []

        while let seedVoxel = remainingVoxels.first {
            var cluster: [VoxelIndex] = []
            var queue: [VoxelIndex] = [seedVoxel]
            remainingVoxels.remove(seedVoxel)

            while let current = queue.popLast() {
                cluster.append(current)

                // Find neighbors within distance
                let neighbors = findNeighbors(
                    of: current,
                    in: remainingVoxels,
                    maxDistance: Self.clusterNeighborDistance
                )

                for neighbor in neighbors {
                    remainingVoxels.remove(neighbor)
                    queue.append(neighbor)
                }
            }

            clusters.append(cluster)
        }

        // Filter by minimum size and create regions
        return clusters
            .filter { $0.count >= Self.clusterMinSize }
            .map { cluster in
                let bounds = calculateClusterBounds(cluster, voxelSize: voxelSize)

                // Calculate actual average variance from cluster voxels
                let averageVariance: Float
                if !varianceLookup.isEmpty {
                    let totalVariance = cluster.compactMap { varianceLookup[$0] }.reduce(0, +)
                    let count = cluster.count
                    averageVariance = count > 0 ? totalVariance / Float(count) : Self.varianceThreshold
                } else {
                    // Fallback for backwards compatibility
                    averageVariance = Self.varianceThreshold * 1.5
                }

                return ReflectiveRegion(
                    voxelIndices: cluster,
                    center: bounds.center,
                    size: bounds.size,
                    averageVariance: averageVariance
                )
            }
    }

    // MARK: - Clustering Helpers

    /// Finds neighbors of a voxel within the specified distance.
    private func findNeighbors(
        of voxel: VoxelIndex,
        in candidates: Set<VoxelIndex>,
        maxDistance: Int
    ) -> [VoxelIndex] {
        var neighbors: [VoxelIndex] = []

        for dx in -maxDistance...maxDistance {
            for dy in -maxDistance...maxDistance {
                for dz in -maxDistance...maxDistance {
                    guard dx != 0 || dy != 0 || dz != 0 else { continue }

                    let neighbor = VoxelIndex(
                        x: voxel.x + dx,
                        y: voxel.y + dy,
                        z: voxel.z + dz
                    )

                    if candidates.contains(neighbor) {
                        neighbors.append(neighbor)
                    }
                }
            }
        }

        return neighbors
    }

    /// Calculates the bounding box of a voxel cluster.
    private func calculateClusterBounds(
        _ cluster: [VoxelIndex],
        voxelSize: Float
    ) -> (center: SIMD3<Float>, size: SIMD3<Float>) {
        guard !cluster.isEmpty else {
            return (center: .zero, size: .zero)
        }

        var minX = Int.max, maxX = Int.min
        var minY = Int.max, maxY = Int.min
        var minZ = Int.max, maxZ = Int.min

        for voxel in cluster {
            minX = min(minX, voxel.x)
            maxX = max(maxX, voxel.x)
            minY = min(minY, voxel.y)
            maxY = max(maxY, voxel.y)
            minZ = min(minZ, voxel.z)
            maxZ = max(maxZ, voxel.z)
        }

        let center = SIMD3<Float>(
            Float(minX + maxX) / 2.0 * voxelSize,
            Float(minY + maxY) / 2.0 * voxelSize,
            Float(minZ + maxZ) / 2.0 * voxelSize
        )

        let size = SIMD3<Float>(
            Float(maxX - minX + 1) * voxelSize,
            Float(maxY - minY + 1) * voxelSize,
            Float(maxZ - minZ + 1) * voxelSize
        )

        return (center: center, size: size)
    }

    // MARK: - Mirror Detection (Task 3: AC2)

    /// Minimum number of behind-wall voxels to consider a mirror region.
    private static let mirrorMinVoxelCount: Int = 20

    /// Depth threshold behind wall to consider as mirror depth (in inches).
    private static let behindWallThreshold: Float = 2.0

    /// Detects mirror regions in the volume by analyzing depth data relative to walls.
    ///
    /// Mirrors create a specific signature:
    /// 1. Depth behind wall: Points appear BEHIND the expected wall plane
    /// 2. High variance: Reflection changes with viewing angle
    /// 3. Edge discontinuity: Sharp depth change at mirror border
    ///
    /// - Parameters:
    ///   - volume: TSDF volume to analyze
    ///   - walls: Detected walls to check for mirror regions
    /// - Returns: Array of detected mirror regions
    func detectMirrorRegions(
        volume: TSDFVolume,
        walls: [AIWall]
    ) -> [MirrorRegion] {
        guard !walls.isEmpty else { return [] }

        logger.info("Checking \(walls.count) walls for mirror regions")

        var mirrorRegions: [MirrorRegion] = []

        for wall in walls {
            let wallNormal = calculateWallNormal(wall)
            let wallPlaneDistance = calculateWallPlaneDistance(wall)

            // Find voxels near this wall with high variance
            var behindWallVoxels: [VoxelIndex] = []
            var totalVariance: Float = 0

            volume.forEachVoxel { index, voxel in
                // Only consider voxels with multiple observations
                guard voxel.weight >= 2.0 else { return }

                let voxelCenter = volume.voxelCenter(for: index)

                // Check if voxel is behind wall plane
                let distanceToWall = distanceToWallPlane(
                    point: voxelCenter,
                    wallNormal: wallNormal,
                    wallPlaneDistance: wallPlaneDistance
                )

                // Behind wall = negative distance beyond threshold
                if distanceToWall < -Self.behindWallThreshold {
                    // Check if also has high variance (more lenient for mirrors)
                    if voxel.observationVariance > Self.varianceThreshold * Self.mirrorVarianceMultiplier {
                        behindWallVoxels.append(index)
                        totalVariance += voxel.observationVariance
                    }
                }
            }

            // If significant behind-wall voxels with high variance = mirror
            if behindWallVoxels.count >= Self.mirrorMinVoxelCount {
                let avgVariance = totalVariance / Float(behindWallVoxels.count)
                let bounds = calculateVoxelBounds(behindWallVoxels, volume: volume)

                let mirrorRegion = MirrorRegion(
                    bounds: bounds,
                    wallId: wall.id,
                    voxelIndices: behindWallVoxels,
                    averageVariance: avgVariance
                )

                mirrorRegions.append(mirrorRegion)
                logger.info("Detected mirror on wall \(wall.id): \(behindWallVoxels.count) voxels")
            }
        }

        return mirrorRegions
    }

    /// Validates that a mirror region doesn't incorrectly extend the room boundary.
    ///
    /// - Parameters:
    ///   - mirrorRegion: The detected mirror region
    ///   - roomMin: Minimum bounds of the room
    ///   - roomMax: Maximum bounds of the room
    /// - Returns: True if the mirror region is valid (doesn't corrupt room bounds)
    func validateMirrorRegion(
        _ mirrorRegion: MirrorRegion,
        roomMin: SIMD3<Float>,
        roomMax: SIMD3<Float>
    ) -> Bool {
        // Mirror bounds should be WITHIN room bounds (not extending them)
        let mirrorCenter = mirrorRegion.bounds.center

        // Check if mirror center is within room bounds (with tolerance)
        let adjustedMin = roomMin - SIMD3<Float>(repeating: Self.mirrorBoundsToleranceInches)
        let adjustedMax = roomMax + SIMD3<Float>(repeating: Self.mirrorBoundsToleranceInches)

        let isWithinBounds = mirrorCenter.x >= adjustedMin.x && mirrorCenter.x <= adjustedMax.x &&
                             mirrorCenter.y >= adjustedMin.y && mirrorCenter.y <= adjustedMax.y &&
                             mirrorCenter.z >= adjustedMin.z && mirrorCenter.z <= adjustedMax.z

        return isWithinBounds
    }

    // MARK: - Wall Geometry Helpers

    /// Calculates the normal vector for a wall (pointing into the room).
    private func calculateWallNormal(_ wall: AIWall) -> SIMD3<Float> {
        // Wall direction in XZ plane
        let wallDir = simd_normalize(SIMD2<Float>(
            wall.endPoint.x - wall.startPoint.x,
            wall.endPoint.y - wall.startPoint.y
        ))

        // Normal is perpendicular (rotate 90 degrees)
        let normal2D = SIMD2<Float>(-wallDir.y, wallDir.x)

        return SIMD3<Float>(normal2D.x, 0, normal2D.y)
    }

    /// Calculates the plane distance (d in ax + by + cz = d) for a wall.
    private func calculateWallPlaneDistance(_ wall: AIWall) -> Float {
        let normal = calculateWallNormal(wall)
        // Use wall start point to calculate d
        return normal.x * wall.startPoint.x + normal.z * wall.startPoint.y
    }

    /// Calculates signed distance from a point to a wall plane.
    private func distanceToWallPlane(
        point: SIMD3<Float>,
        wallNormal: SIMD3<Float>,
        wallPlaneDistance: Float
    ) -> Float {
        return point.x * wallNormal.x + point.z * wallNormal.z - wallPlaneDistance
    }

    /// Calculates bounding box for a set of voxel indices.
    private func calculateVoxelBounds(_ voxels: [VoxelIndex], volume: TSDFVolume) -> AIBoundingBox3D {
        guard !voxels.isEmpty else {
            return AIBoundingBox3D(center: .zero, size: .zero)
        }

        var minPoint = SIMD3<Float>(Float.greatestFiniteMagnitude, Float.greatestFiniteMagnitude, Float.greatestFiniteMagnitude)
        var maxPoint = SIMD3<Float>(-Float.greatestFiniteMagnitude, -Float.greatestFiniteMagnitude, -Float.greatestFiniteMagnitude)

        for voxel in voxels {
            let center = volume.voxelCenter(for: voxel)
            minPoint = simd_min(minPoint, center)
            maxPoint = simd_max(maxPoint, center)
        }

        // Use min/max constructor
        return AIBoundingBox3D(min: minPoint, max: maxPoint)
    }
}
