//
//  SpecialCabinetDetector.swift
//  cabinetscan
//
//  Created for Story 4.10: Stacked & Special Cabinet Detection
//

import Foundation
import simd
import os.log

// MARK: - Special Cabinet Detector Protocol

/// Protocol for special cabinet detection implementations.
/// Enables testing with mock detectors.
protocol SpecialCabinetDetectorProtocol {
    /// Detects special cabinets from existing cabinet and appliance detection results.
    ///
    /// - Parameters:
    ///   - cabinets: Previously detected cabinets
    ///   - appliances: Previously detected appliances
    ///   - roomStructure: Room structure (walls, floor plane, ceiling)
    ///   - pointCloud: Calibrated point cloud in inches
    /// - Returns: Special cabinet detection result with updated cabinets
    func detect(
        cabinets: [AIDetectedCabinet],
        appliances: ApplianceDetectionResult,
        roomStructure: AIRoomStructure,
        pointCloud: AIPointCloud
    ) async -> SpecialCabinetDetectionResult
}

// MARK: - Special Cabinet Detection Result

/// Result of special cabinet detection containing updated cabinets and metadata.
struct SpecialCabinetDetectionResult: Equatable {
    /// Updated cabinets with special cabinet flags applied
    let cabinets: [AIDetectedCabinet]

    /// Number of stacked cabinet rows detected
    let stackedCount: Int

    /// Number of refrigerator upper cabinets detected
    let refrigeratorUpperCount: Int

    /// Number of microwave housing cabinets detected
    let microwaveHousingCount: Int

    /// Number of oven housing cabinets detected
    let ovenHousingCount: Int

    /// Empty spaces detected above refrigerators (upsell opportunities)
    let emptySpacesAboveRefrigerator: [EmptySpaceAboveAppliance]

    /// Warnings generated during detection
    let warnings: [String]

    /// Processing time in milliseconds
    let processingTimeMs: Int

    /// Total special cabinets detected
    var totalSpecialCount: Int {
        stackedCount + refrigeratorUpperCount + microwaveHousingCount + ovenHousingCount
    }
}

// MARK: - Empty Space Above Appliance

/// Represents an empty space above an appliance where a cabinet could be installed.
struct EmptySpaceAboveAppliance: Equatable, Codable {
    /// ID of the appliance this space is above
    let applianceId: UUID

    /// Type of appliance (for display)
    let applianceType: String

    /// Available width (inches)
    let widthInches: Float

    /// Available height (inches)
    let heightInches: Float

    /// Available depth (inches)
    let depthInches: Float

    /// Wall ID where this space is located
    let wallId: UUID

    /// Position along wall (inches)
    let positionOnWallInches: Float
}

// MARK: - Stacked Cabinet Pair

/// Represents a pair of stacked cabinets (lower and upper row).
struct StackedCabinetPair {
    /// The lower (standard) upper cabinet
    let lowerCabinet: AIDetectedCabinet

    /// The stacked (shorter) upper cabinet above
    let stackedCabinet: AIDetectedCabinet

    /// Gap between the two cabinets (inches)
    let gapInches: Float
}

// MARK: - Special Cabinet Detector

/// Detects special cabinet configurations including stacked uppers and appliance cabinets.
///
/// **Detection Types:**
/// 1. Stacked Upper Cabinets - Double-row upper configurations
/// 2. Refrigerator Upper Cabinets - 24" deep cabinets above refrigerators
/// 3. Microwave Housing - Cabinets containing built-in microwaves
/// 4. Wall Oven Housing - Tall cabinets containing wall ovens
///
/// **Dependencies:**
/// - Requires completed cabinet detection (Story 4.2/4.3)
/// - Requires completed appliance detection (Story 4.4)
///
/// **Performance Budget:** <200ms (Story 4.10 requirement)
@MainActor
final class SpecialCabinetDetector: SpecialCabinetDetectorProtocol {

    // MARK: - Constants

    // Stacked Cabinet Detection Constants
    private static let stackedMinGapAbove: Float = 0.0
    private static let stackedMaxGapAbove: Float = 6.0
    private static let stackedMinHeight: Float = 12.0
    private static let stackedMaxHeight: Float = 24.0
    private static let stackedScanRangeAboveCabinet: Float = 30.0 // Scan up to 30" above upper

    // Refrigerator Upper Cabinet Constants
    private static let refrigeratorUpperMinHeight: Float = 12.0
    private static let refrigeratorUpperMaxHeight: Float = 24.0
    private static let refrigeratorUpperExpectedDepth: Float = 24.0
    private static let refrigeratorUpperDepthTolerance: Float = 3.0
    private static let refrigeratorScanAboveAppliance: Float = 30.0

    // Microwave Cabinet Constants
    private static let microwaveHousingMinHeight: Float = 15.0
    private static let microwaveHousingMaxHeight: Float = 18.0
    private static let microwaveContainmentTolerance: Float = 2.0

    // Wall Oven Cabinet Constants
    private static let singleOvenMinCutoutHeight: Float = 25.0
    private static let doubleOvenMinCutoutHeight: Float = 48.0
    private static let ovenContainmentTolerance: Float = 3.0
    private static let doubleOvenMinCabinetHeight: Float = 84.0

    // General Constants
    private static let positionMatchTolerance: Float = 6.0 // inches

    // MARK: - Properties

    private let logger = Logger(subsystem: "com.cabinetscan", category: "SpecialCabinetDetector")

    // MARK: - Initialization

    init() {
        #if DEBUG
        logger.info("SpecialCabinetDetector initialized")
        #endif
    }

    // MARK: - Main Detection Entry Point

    /// Detects all special cabinet configurations.
    ///
    /// - Parameters:
    ///   - cabinets: Previously detected cabinets
    ///   - appliances: Previously detected appliances
    ///   - roomStructure: Room structure (walls, floor plane, ceiling)
    ///   - pointCloud: Calibrated point cloud in inches
    /// - Returns: Special cabinet detection result
    func detect(
        cabinets: [AIDetectedCabinet],
        appliances: ApplianceDetectionResult,
        roomStructure: AIRoomStructure,
        pointCloud: AIPointCloud
    ) async -> SpecialCabinetDetectionResult {
        logger.info("Starting special cabinet detection with \(cabinets.count) cabinets, \(appliances.appliances.count) appliances")

        let startTime = CFAbsoluteTimeGetCurrent()
        var warnings: [String] = []
        var updatedCabinets = cabinets
        var emptySpaces: [EmptySpaceAboveAppliance] = []

        var stackedCount = 0
        var refrigeratorUpperCount = 0
        var microwaveHousingCount = 0
        var ovenHousingCount = 0

        // Task 2: Detect stacked upper cabinets
        let stackedResult = detectStackedUppers(
            cabinets: updatedCabinets,
            roomStructure: roomStructure,
            pointCloud: pointCloud
        )
        updatedCabinets = stackedResult.cabinets
        stackedCount = stackedResult.stackedCount
        warnings.append(contentsOf: stackedResult.warnings)

        // Task 3: Detect refrigerator upper cabinets
        let refrigeratorResult = detectRefrigeratorCabinets(
            refrigerators: appliances.appliances.filter { $0.type == .refrigerator },
            cabinets: updatedCabinets,
            roomStructure: roomStructure,
            pointCloud: pointCloud
        )
        updatedCabinets = refrigeratorResult.cabinets
        refrigeratorUpperCount = refrigeratorResult.refrigeratorUpperCount
        emptySpaces.append(contentsOf: refrigeratorResult.emptySpaces)
        warnings.append(contentsOf: refrigeratorResult.warnings)

        // Task 4: Detect microwave cabinet housing
        let microwaveResult = detectMicrowaveCabinets(
            microwaves: appliances.appliances.filter { $0.type == .microwave },
            cabinets: updatedCabinets
        )
        updatedCabinets = microwaveResult.cabinets
        microwaveHousingCount = microwaveResult.microwaveHousingCount
        warnings.append(contentsOf: microwaveResult.warnings)

        // Task 5: Detect wall oven cabinet housing
        let ovenResult = detectOvenCabinets(
            wallOvens: appliances.appliances.filter { $0.type == .wallOven },
            cabinets: updatedCabinets
        )
        updatedCabinets = ovenResult.cabinets
        ovenHousingCount = ovenResult.ovenHousingCount
        warnings.append(contentsOf: ovenResult.warnings)

        let processingTimeMs = Int((CFAbsoluteTimeGetCurrent() - startTime) * 1000)

        logger.info("Special cabinet detection complete in \(processingTimeMs)ms: \(stackedCount) stacked, \(refrigeratorUpperCount) fridge upper, \(microwaveHousingCount) microwave, \(ovenHousingCount) oven")

        return SpecialCabinetDetectionResult(
            cabinets: updatedCabinets,
            stackedCount: stackedCount,
            refrigeratorUpperCount: refrigeratorUpperCount,
            microwaveHousingCount: microwaveHousingCount,
            ovenHousingCount: ovenHousingCount,
            emptySpacesAboveRefrigerator: emptySpaces,
            warnings: warnings,
            processingTimeMs: processingTimeMs
        )
    }

    // MARK: - Task 2: Stacked Upper Detection (AC1, AC2)

    /// Result of stacked upper detection.
    private struct StackedDetectionResult {
        let cabinets: [AIDetectedCabinet]
        let stackedCount: Int
        let warnings: [String]
    }

    /// Detects stacked upper cabinets (double-row configurations).
    ///
    /// Stacked cabinets are detected by:
    /// 1. Finding existing upper cabinets
    /// 2. Scanning above each upper for additional cabinet
    /// 3. Checking for horizontal divider between rows
    /// 4. Measuring heights separately
    ///
    /// - Parameters:
    ///   - cabinets: All detected cabinets
    ///   - roomStructure: Room structure with ceiling height
    ///   - pointCloud: Calibrated point cloud
    /// - Returns: Updated cabinets with stacked flags and new stacked cabinets
    private func detectStackedUppers(
        cabinets: [AIDetectedCabinet],
        roomStructure: AIRoomStructure,
        pointCloud: AIPointCloud
    ) -> StackedDetectionResult {
        var updatedCabinets = cabinets
        var warnings: [String] = []
        var stackedCount = 0

        // Get upper cabinets to check for stacking
        let upperCabinets = cabinets.filter { $0.type == .upper && !$0.isStacked }
        let ceilingHeight = Float(roomStructure.ceilingHeightInches)

        for upperCabinet in upperCabinets {
            // Calculate the top of this upper cabinet
            let cabinetTop = upperCabinet.boundingBox.max.y

            // Check if there's room for a stacked cabinet above
            let spaceAbove = ceilingHeight - cabinetTop
            guard spaceAbove >= Self.stackedMinHeight else {
                continue
            }

            // Check if there's already a cabinet detected in this space
            // Look for cabinets on same wall with center Y above this cabinet's top
            let potentialStackedCabinet = cabinets.first { candidate in
                guard candidate.type == .upper && candidate.id != upperCabinet.id else {
                    return false
                }
                guard candidate.wallId == upperCabinet.wallId else {
                    return false
                }

                // Check horizontal overlap (same position along wall)
                let positionDiff = abs(candidate.positionOnWallInches - upperCabinet.positionOnWallInches)
                guard positionDiff < Self.positionMatchTolerance else {
                    return false
                }

                // Check vertical position (candidate should be above current cabinet)
                let candidateBottom = candidate.boundingBox.min.y
                let gap = candidateBottom - cabinetTop

                // Gap should be within stacked range
                return gap >= Self.stackedMinGapAbove && gap <= Self.stackedMaxGapAbove
            }

            if let stacked = potentialStackedCabinet {
                // Found an existing cabinet that's a stacked configuration
                // Update both cabinets to mark them as stacked

                // Update the lower cabinet
                if let lowerIndex = updatedCabinets.firstIndex(where: { $0.id == upperCabinet.id }) {
                    let lowerCabinet = updatedCabinets[lowerIndex]
                    let updatedLower = createStackedCabinet(
                        from: lowerCabinet,
                        stackedWithId: stacked.id,
                        isUpperRow: false
                    )
                    updatedCabinets[lowerIndex] = updatedLower
                }

                // Update the upper (stacked) cabinet
                if let upperIndex = updatedCabinets.firstIndex(where: { $0.id == stacked.id }) {
                    let stackedCabinet = updatedCabinets[upperIndex]
                    let updatedStacked = createStackedCabinet(
                        from: stackedCabinet,
                        stackedWithId: upperCabinet.id,
                        isUpperRow: true
                    )
                    updatedCabinets[upperIndex] = updatedStacked
                    stackedCount += 1
                }

                logger.debug("Detected stacked cabinet pair: lower \(upperCabinet.id), upper \(stacked.id)")

            } else {
                // No existing cabinet found - try to detect from point cloud
                let detectedStacked = detectStackedFromPointCloud(
                    belowCabinet: upperCabinet,
                    roomStructure: roomStructure,
                    pointCloud: pointCloud
                )

                if let newStacked = detectedStacked {
                    // Update the lower cabinet to link to the new stacked cabinet
                    if let lowerIndex = updatedCabinets.firstIndex(where: { $0.id == upperCabinet.id }) {
                        let lowerCabinet = updatedCabinets[lowerIndex]
                        let updatedLower = createStackedCabinet(
                            from: lowerCabinet,
                            stackedWithId: newStacked.id,
                            isUpperRow: false
                        )
                        updatedCabinets[lowerIndex] = updatedLower
                    }

                    // Add the new stacked cabinet
                    updatedCabinets.append(newStacked)
                    stackedCount += 1

                    logger.debug("Detected new stacked cabinet above \(upperCabinet.id)")
                }
            }
        }

        if stackedCount > 0 {
            logger.info("Detected \(stackedCount) stacked upper cabinet rows")
        }

        return StackedDetectionResult(
            cabinets: updatedCabinets,
            stackedCount: stackedCount,
            warnings: warnings
        )
    }

    /// Creates a stacked cabinet by copying properties from an existing cabinet.
    ///
    /// - Parameters:
    ///   - cabinet: Original cabinet to copy from
    ///   - stackedWithId: ID of the cabinet this one is stacked with
    ///   - isUpperRow: Whether this is the upper (stacked) row
    /// - Returns: Cabinet with stacked properties set
    private func createStackedCabinet(
        from cabinet: AIDetectedCabinet,
        stackedWithId: UUID,
        isUpperRow: Bool
    ) -> AIDetectedCabinet {
        let specialType: CabinetSpecialType = isUpperRow ? .stacked : .standard
        var notes = cabinet.notes

        if isUpperRow {
            notes.append("Stacked upper row")
        } else {
            notes.append("Lower row of stacked configuration")
        }

        return AIDetectedCabinet(
            id: cabinet.id,
            boundingBox: cabinet.boundingBox,
            type: cabinet.type,
            wallId: cabinet.wallId,
            positionOnWallInches: cabinet.positionOnWallInches,
            rawDimensions: cabinet.rawDimensions,
            snappedDimensions: cabinet.snappedDimensions,
            confidence: cabinet.confidence,
            isStandardSize: cabinet.isStandardSize,
            cornerType: cabinet.cornerType,
            cornerDetails: cabinet.cornerDetails,
            isStacked: true,
            specialType: specialType,
            stackedWithCabinetId: stackedWithId,
            hostingApplianceId: cabinet.hostingApplianceId,
            notes: notes
        )
    }

    /// Detects a stacked cabinet from point cloud data above an existing upper cabinet.
    ///
    /// - Parameters:
    ///   - belowCabinet: The upper cabinet to check above
    ///   - roomStructure: Room structure
    ///   - pointCloud: Calibrated point cloud
    /// - Returns: A new stacked cabinet if detected, nil otherwise
    private func detectStackedFromPointCloud(
        belowCabinet: AIDetectedCabinet,
        roomStructure: AIRoomStructure,
        pointCloud: AIPointCloud
    ) -> AIDetectedCabinet? {
        // Get cabinet boundaries
        let cabinetTop = belowCabinet.boundingBox.max.y
        let ceilingHeight = Float(roomStructure.ceilingHeightInches)

        // Define scan region above the cabinet
        let scanMinY = cabinetTop + Self.stackedMinGapAbove
        let scanMaxY = min(cabinetTop + Self.stackedScanRangeAboveCabinet, ceilingHeight)

        // Get points from point cloud
        var mutablePointCloud = pointCloud
        let points = mutablePointCloud.getPoints()

        // Filter points in the scan region
        let regionPoints = points.filter { point in
            // Vertical check
            guard point.y >= scanMinY && point.y <= scanMaxY else {
                return false
            }

            // Horizontal check - point should be within cabinet's XZ bounds
            let minX = belowCabinet.boundingBox.min.x - 3.0 // Small tolerance
            let maxX = belowCabinet.boundingBox.max.x + 3.0
            let minZ = belowCabinet.boundingBox.min.z - 3.0
            let maxZ = belowCabinet.boundingBox.max.z + 3.0

            return point.x >= minX && point.x <= maxX &&
                   point.z >= minZ && point.z <= maxZ
        }

        // Need enough points to detect a cabinet
        guard regionPoints.count >= 30 else {
            return nil
        }

        // Calculate dimensions from points
        let minY = regionPoints.map { $0.y }.min() ?? scanMinY
        let maxY = regionPoints.map { $0.y }.max() ?? scanMaxY
        let height = maxY - minY

        // Verify height is in stacked cabinet range
        guard height >= Self.stackedMinHeight && height <= Self.stackedMaxHeight else {
            return nil
        }

        // Use same width as below cabinet
        let width = belowCabinet.rawWidthInches

        // Use standard stacked depth
        let depth = StandardSpecialCabinetSizes.stackedUpperDepth

        // Create bounding box
        let centerY = minY + height / 2
        let center = SIMD3<Float>(
            belowCabinet.boundingBox.center.x,
            centerY,
            belowCabinet.boundingBox.center.z
        )

        let boundingBox = AIBoundingBox3D(
            center: center,
            size: SIMD3<Float>(width, height, depth)
        )

        // Apply snapping
        let rawDimensions = SIMD3<Float>(width, height, depth)
        let snappedHeight = StandardSpecialCabinetSizes.stackedUpperHeights
            .min(by: { abs($0 - height) < abs($1 - height) }) ?? height
        let snappedDimensions = SIMD3<Float>(
            belowCabinet.snappedDimensions.x, // Match width of below cabinet
            snappedHeight,
            depth
        )

        // Determine if standard size
        let isStandard = StandardSpecialCabinetSizes.isStackedUpperHeight(snappedHeight)

        // Calculate confidence
        let confidence: AIConfidenceLevel
        if isStandard && regionPoints.count >= 50 {
            confidence = .high
        } else if regionPoints.count >= 30 {
            confidence = .medium
        } else {
            confidence = .low
        }

        var notes: [String] = ["Stacked upper row"]
        if !isStandard {
            notes.append("Non-standard stacked height")
        }
        if confidence == .low {
            notes.append("Verify stacked cabinet dimensions")
        }

        return AIDetectedCabinet(
            boundingBox: boundingBox,
            type: .upper,
            wallId: belowCabinet.wallId,
            positionOnWallInches: belowCabinet.positionOnWallInches,
            rawDimensions: rawDimensions,
            snappedDimensions: snappedDimensions,
            confidence: confidence,
            isStandardSize: isStandard,
            cornerType: nil,
            cornerDetails: nil,
            isStacked: true,
            specialType: .stacked,
            stackedWithCabinetId: belowCabinet.id,
            hostingApplianceId: nil,
            notes: notes
        )
    }

    // MARK: - Task 3: Refrigerator Upper Cabinet Detection (AC3, AC4)

    /// Result of refrigerator cabinet detection.
    private struct RefrigeratorCabinetResult {
        let cabinets: [AIDetectedCabinet]
        let refrigeratorUpperCount: Int
        let emptySpaces: [EmptySpaceAboveAppliance]
        let warnings: [String]
    }

    /// Detects cabinets above refrigerators.
    ///
    /// - Parameters:
    ///   - refrigerators: Detected refrigerators
    ///   - cabinets: All detected cabinets
    ///   - roomStructure: Room structure
    ///   - pointCloud: Calibrated point cloud
    /// - Returns: Updated cabinets and empty space information
    private func detectRefrigeratorCabinets(
        refrigerators: [AIDetectedAppliance],
        cabinets: [AIDetectedCabinet],
        roomStructure: AIRoomStructure,
        pointCloud: AIPointCloud
    ) -> RefrigeratorCabinetResult {
        var updatedCabinets = cabinets
        var emptySpaces: [EmptySpaceAboveAppliance] = []
        var warnings: [String] = []
        var refrigeratorUpperCount = 0

        for refrigerator in refrigerators {
            // Look for cabinet above refrigerator
            let fridgeTop = refrigerator.boundingBox.max.y
            let ceilingHeight = Float(roomStructure.ceilingHeightInches)

            // Find cabinet that's above this refrigerator
            let cabinetAbove = cabinets.first { cabinet in
                guard cabinet.type == .upper else { return false }

                // Check if cabinet is above refrigerator
                let cabinetBottom = cabinet.boundingBox.min.y
                let verticalGap = cabinetBottom - fridgeTop
                guard verticalGap >= -3.0 && verticalGap <= 6.0 else {
                    return false
                }

                // Check horizontal overlap
                let fridgeMinX = refrigerator.boundingBox.min.x
                let fridgeMaxX = refrigerator.boundingBox.max.x
                let cabinetMinX = cabinet.boundingBox.min.x
                let cabinetMaxX = cabinet.boundingBox.max.x

                let overlap = min(fridgeMaxX, cabinetMaxX) - max(fridgeMinX, cabinetMinX)
                return overlap > refrigerator.rawWidthInches * 0.5 // At least 50% overlap
            }

            if let cabinet = cabinetAbove {
                // Found a cabinet above the refrigerator
                if let index = updatedCabinets.firstIndex(where: { $0.id == cabinet.id }) {
                    // Check if depth is refrigerator-like (24") vs standard upper (12")
                    let isRefrigeratorDepth = StandardSpecialCabinetSizes.isRefrigeratorUpperDepth(cabinet.rawDepthInches)

                    var notes = cabinet.notes
                    notes.append("Above refrigerator")

                    // Calculate confidence
                    let confidence: AIConfidenceLevel
                    if isRefrigeratorDepth && StandardSpecialCabinetSizes.isStackedUpperHeight(cabinet.rawHeightInches) {
                        confidence = .high
                    } else if isRefrigeratorDepth || StandardSpecialCabinetSizes.isStackedUpperHeight(cabinet.rawHeightInches) {
                        confidence = .medium
                    } else {
                        confidence = .low
                        notes.append("Verify refrigerator upper dimensions")
                    }

                    if !isRefrigeratorDepth {
                        notes.append("Depth may not match refrigerator (expected 24\")")
                    }

                    let updatedCabinet = AIDetectedCabinet(
                        id: cabinet.id,
                        boundingBox: cabinet.boundingBox,
                        type: cabinet.type,
                        wallId: cabinet.wallId,
                        positionOnWallInches: cabinet.positionOnWallInches,
                        rawDimensions: cabinet.rawDimensions,
                        snappedDimensions: cabinet.snappedDimensions,
                        confidence: confidence,
                        isStandardSize: cabinet.isStandardSize,
                        cornerType: cabinet.cornerType,
                        cornerDetails: cabinet.cornerDetails,
                        isStacked: cabinet.isStacked,
                        specialType: .refrigeratorUpper,
                        stackedWithCabinetId: cabinet.stackedWithCabinetId,
                        hostingApplianceId: refrigerator.id,
                        notes: notes
                    )
                    updatedCabinets[index] = updatedCabinet
                    refrigeratorUpperCount += 1

                    logger.debug("Detected refrigerator upper cabinet: \(cabinet.id) above fridge \(refrigerator.id)")
                }

            } else {
                // No cabinet above refrigerator - check for empty space
                let spaceAbove = ceilingHeight - fridgeTop

                if spaceAbove >= Self.refrigeratorUpperMinHeight, let wallId = refrigerator.wallId {
                    // There's space for a cabinet but none detected
                    let emptySpace = EmptySpaceAboveAppliance(
                        applianceId: refrigerator.id,
                        applianceType: "Refrigerator",
                        widthInches: refrigerator.rawWidthInches,
                        heightInches: min(spaceAbove, Self.refrigeratorUpperMaxHeight),
                        depthInches: Self.refrigeratorUpperExpectedDepth,
                        wallId: wallId,
                        positionOnWallInches: refrigerator.positionOnWallInches ?? 0
                    )
                    emptySpaces.append(emptySpace)
                    warnings.append("No cabinet above refrigerator - space available for \(String(format: "%.0f", emptySpace.widthInches))\"W x \(String(format: "%.0f", emptySpace.heightInches))\"H x \(String(format: "%.0f", emptySpace.depthInches))\"D cabinet")

                    logger.info("Empty space detected above refrigerator \(refrigerator.id): \(emptySpace.widthInches)\"W x \(emptySpace.heightInches)\"H")
                }
            }
        }

        return RefrigeratorCabinetResult(
            cabinets: updatedCabinets,
            refrigeratorUpperCount: refrigeratorUpperCount,
            emptySpaces: emptySpaces,
            warnings: warnings
        )
    }

    // MARK: - Task 4: Microwave Cabinet Detection (AC5)

    /// Result of microwave cabinet detection.
    private struct MicrowaveCabinetResult {
        let cabinets: [AIDetectedCabinet]
        let microwaveHousingCount: Int
        let warnings: [String]
    }

    /// Detects cabinets housing built-in microwaves.
    ///
    /// - Parameters:
    ///   - microwaves: Detected microwaves
    ///   - cabinets: All detected cabinets
    /// - Returns: Updated cabinets with microwave housing flags
    private func detectMicrowaveCabinets(
        microwaves: [AIDetectedAppliance],
        cabinets: [AIDetectedCabinet]
    ) -> MicrowaveCabinetResult {
        var updatedCabinets = cabinets
        var warnings: [String] = []
        var microwaveHousingCount = 0

        for microwave in microwaves {
            // Find cabinet that contains this microwave
            let hostingCabinet = cabinets.first { cabinet in
                // Microwave can be in upper or tall cabinet
                guard cabinet.type == .upper || cabinet.type == .tall else {
                    return false
                }

                // Check if microwave is contained within cabinet bounds
                return isBoundingBoxContained(
                    inner: microwave.boundingBox,
                    outer: cabinet.boundingBox,
                    tolerance: Self.microwaveContainmentTolerance
                )
            }

            if let cabinet = hostingCabinet {
                if let index = updatedCabinets.firstIndex(where: { $0.id == cabinet.id }) {
                    // Verify microwave fits within cabinet
                    let microwaveWidth = microwave.rawWidthInches
                    let microwaveHeight = microwave.boundingBox.size.y
                    let cabinetWidth = cabinet.rawWidthInches
                    let cabinetHeight = cabinet.rawHeightInches

                    var notes = cabinet.notes
                    notes.append("Microwave housing")

                    let confidence: AIConfidenceLevel
                    if microwaveWidth <= cabinetWidth + 1 && microwaveHeight <= cabinetHeight + 1 {
                        confidence = .high
                    } else {
                        confidence = .medium
                        notes.append("Verify microwave fits within cabinet")
                    }

                    let updatedCabinet = AIDetectedCabinet(
                        id: cabinet.id,
                        boundingBox: cabinet.boundingBox,
                        type: cabinet.type,
                        wallId: cabinet.wallId,
                        positionOnWallInches: cabinet.positionOnWallInches,
                        rawDimensions: cabinet.rawDimensions,
                        snappedDimensions: cabinet.snappedDimensions,
                        confidence: confidence,
                        isStandardSize: cabinet.isStandardSize,
                        cornerType: cabinet.cornerType,
                        cornerDetails: cabinet.cornerDetails,
                        isStacked: cabinet.isStacked,
                        specialType: .microwaveHousing,
                        stackedWithCabinetId: cabinet.stackedWithCabinetId,
                        hostingApplianceId: microwave.id,
                        notes: notes
                    )
                    updatedCabinets[index] = updatedCabinet
                    microwaveHousingCount += 1

                    logger.debug("Detected microwave housing cabinet: \(cabinet.id) for microwave \(microwave.id)")
                }
            }
        }

        return MicrowaveCabinetResult(
            cabinets: updatedCabinets,
            microwaveHousingCount: microwaveHousingCount,
            warnings: warnings
        )
    }

    // MARK: - Task 5: Wall Oven Cabinet Detection (AC6)

    /// Result of wall oven cabinet detection.
    private struct OvenCabinetResult {
        let cabinets: [AIDetectedCabinet]
        let ovenHousingCount: Int
        let warnings: [String]
    }

    /// Detects tall cabinets housing wall ovens.
    ///
    /// - Parameters:
    ///   - wallOvens: Detected wall ovens
    ///   - cabinets: All detected cabinets
    /// - Returns: Updated cabinets with oven housing flags
    private func detectOvenCabinets(
        wallOvens: [AIDetectedAppliance],
        cabinets: [AIDetectedCabinet]
    ) -> OvenCabinetResult {
        var updatedCabinets = cabinets
        var warnings: [String] = []
        var ovenHousingCount = 0

        for wallOven in wallOvens {
            // Find tall cabinet that contains this wall oven
            let hostingCabinet = cabinets.first { cabinet in
                // Wall ovens should be in tall cabinets
                guard cabinet.type == .tall else {
                    return false
                }

                // Check if oven is contained within cabinet bounds
                return isBoundingBoxContained(
                    inner: wallOven.boundingBox,
                    outer: cabinet.boundingBox,
                    tolerance: Self.ovenContainmentTolerance
                )
            }

            if let cabinet = hostingCabinet {
                if let index = updatedCabinets.firstIndex(where: { $0.id == cabinet.id }) {
                    // Determine if single or double oven based on height
                    let ovenHeight = wallOven.boundingBox.size.y
                    let isDoubleOven = StandardSpecialCabinetSizes.isDoubleOvenHeight(ovenHeight)

                    var notes = cabinet.notes
                    notes.append(isDoubleOven ? "Double wall oven housing" : "Single wall oven housing")

                    // For double oven, verify cabinet height is sufficient
                    var confidence: AIConfidenceLevel = .high
                    if isDoubleOven {
                        if cabinet.rawHeightInches < Self.doubleOvenMinCabinetHeight {
                            confidence = .low
                            notes.append("Cabinet height may be insufficient for double oven")
                            warnings.append("Double wall oven in \(String(format: "%.0f", cabinet.rawHeightInches))\" tall cabinet (minimum \(Int(Self.doubleOvenMinCabinetHeight))\" recommended)")
                        }
                    }

                    let updatedCabinet = AIDetectedCabinet(
                        id: cabinet.id,
                        boundingBox: cabinet.boundingBox,
                        type: cabinet.type,
                        wallId: cabinet.wallId,
                        positionOnWallInches: cabinet.positionOnWallInches,
                        rawDimensions: cabinet.rawDimensions,
                        snappedDimensions: cabinet.snappedDimensions,
                        confidence: confidence,
                        isStandardSize: cabinet.isStandardSize,
                        cornerType: cabinet.cornerType,
                        cornerDetails: cabinet.cornerDetails,
                        isStacked: cabinet.isStacked,
                        specialType: .ovenHousing,
                        stackedWithCabinetId: cabinet.stackedWithCabinetId,
                        hostingApplianceId: wallOven.id,
                        notes: notes
                    )
                    updatedCabinets[index] = updatedCabinet
                    ovenHousingCount += 1

                    logger.debug("Detected oven housing cabinet: \(cabinet.id) for wall oven \(wallOven.id), isDouble: \(isDoubleOven)")
                }
            }
        }

        return OvenCabinetResult(
            cabinets: updatedCabinets,
            ovenHousingCount: ovenHousingCount,
            warnings: warnings
        )
    }

    // MARK: - Helper Methods

    /// Checks if one bounding box is contained within another.
    ///
    /// - Parameters:
    ///   - inner: The inner bounding box (should be contained)
    ///   - outer: The outer bounding box (container)
    ///   - tolerance: Tolerance for overlap (inches)
    /// - Returns: True if inner is mostly contained within outer
    private func isBoundingBoxContained(
        inner: AIBoundingBox3D,
        outer: AIBoundingBox3D,
        tolerance: Float
    ) -> Bool {
        // Check X axis
        let innerMinX = inner.min.x
        let innerMaxX = inner.max.x
        let outerMinX = outer.min.x - tolerance
        let outerMaxX = outer.max.x + tolerance

        guard innerMinX >= outerMinX && innerMaxX <= outerMaxX else {
            return false
        }

        // Check Y axis
        let innerMinY = inner.min.y
        let innerMaxY = inner.max.y
        let outerMinY = outer.min.y - tolerance
        let outerMaxY = outer.max.y + tolerance

        guard innerMinY >= outerMinY && innerMaxY <= outerMaxY else {
            return false
        }

        // Check Z axis
        let innerMinZ = inner.min.z
        let innerMaxZ = inner.max.z
        let outerMinZ = outer.min.z - tolerance
        let outerMaxZ = outer.max.z + tolerance

        guard innerMinZ >= outerMinZ && innerMaxZ <= outerMaxZ else {
            return false
        }

        return true
    }
}
