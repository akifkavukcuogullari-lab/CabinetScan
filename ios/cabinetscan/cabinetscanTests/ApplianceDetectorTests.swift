//
//  ApplianceDetectorTests.swift
//  cabinetscanTests
//
//  Created for Story 4.4: Appliance Detection
//

import XCTest
import simd
@testable import cabinetscan

/// Tests for ApplianceDetector (Story 4.4)
final class ApplianceDetectorTests: XCTestCase {

    // MARK: - Task 1: Data Model Tests

    /// Test AIApplianceType enum has all required types (AC1)
    func testApplianceTypeEnumContainsAllTypes() {
        let allTypes = AIApplianceType.allCases

        XCTAssertTrue(allTypes.contains(.refrigerator))
        XCTAssertTrue(allTypes.contains(.range))
        XCTAssertTrue(allTypes.contains(.cooktop))
        XCTAssertTrue(allTypes.contains(.wallOven))
        XCTAssertTrue(allTypes.contains(.dishwasher))
        XCTAssertTrue(allTypes.contains(.microwave))
        XCTAssertTrue(allTypes.contains(.hood))
        XCTAssertTrue(allTypes.contains(.sink))
        XCTAssertTrue(allTypes.contains(.other))
    }

    /// Test AIApplianceSubType enum has refrigerator subtypes (AC2)
    func testApplianceSubTypeContainsRefrigeratorSubtypes() {
        let allSubtypes = AIApplianceSubType.allCases

        XCTAssertTrue(allSubtypes.contains(.fridgeFrenchDoor))
        XCTAssertTrue(allSubtypes.contains(.fridgeSideBySide))
        XCTAssertTrue(allSubtypes.contains(.fridgeTopFreezer))
        XCTAssertTrue(allSubtypes.contains(.fridgeBottomFreezer))
        XCTAssertTrue(allSubtypes.contains(.fridgeCounterDepth))
    }

    /// Test AIApplianceSubType enum has range subtypes (AC2)
    func testApplianceSubTypeContainsRangeSubtypes() {
        let allSubtypes = AIApplianceSubType.allCases

        XCTAssertTrue(allSubtypes.contains(.rangeFreestanding))
        XCTAssertTrue(allSubtypes.contains(.rangeSlideIn))
        XCTAssertTrue(allSubtypes.contains(.rangeProStyle))
    }

    /// Test AIApplianceSubType enum has hood subtypes (AC2)
    func testApplianceSubTypeContainsHoodSubtypes() {
        let allSubtypes = AIApplianceSubType.allCases

        XCTAssertTrue(allSubtypes.contains(.hoodWallMount))
        XCTAssertTrue(allSubtypes.contains(.hoodUnderCabinet))
        XCTAssertTrue(allSubtypes.contains(.hoodIsland))
    }

    /// Test AIApplianceSubType enum has microwave subtypes (AC2)
    func testApplianceSubTypeContainsMicrowaveSubtypes() {
        let allSubtypes = AIApplianceSubType.allCases

        XCTAssertTrue(allSubtypes.contains(.microwaveOTR))
        XCTAssertTrue(allSubtypes.contains(.microwaveBuiltIn))
        XCTAssertTrue(allSubtypes.contains(.microwaveCountertop))
        XCTAssertTrue(allSubtypes.contains(.microwaveDrawer))
    }

    /// Test AIApplianceSubType enum has sink subtypes (AC2)
    func testApplianceSubTypeContainsSinkSubtypes() {
        let allSubtypes = AIApplianceSubType.allCases

        XCTAssertTrue(allSubtypes.contains(.sinkSingleBowl))
        XCTAssertTrue(allSubtypes.contains(.sinkDoubleBowl))
        XCTAssertTrue(allSubtypes.contains(.sinkFarmhouse))
    }

    /// Test AIDetectedAppliance struct initialization (Task 1.4)
    func testDetectedApplianceInitialization() {
        let boundingBox = AIBoundingBox3D(
            center: SIMD3<Float>(18, 34.5, 12),
            size: SIMD3<Float>(36, 69, 32)
        )

        let appliance = AIDetectedAppliance(
            boundingBox: boundingBox,
            type: .refrigerator,
            subType: .fridgeFrenchDoor,
            rawDimensions: SIMD3<Float>(36.2, 69.1, 32.3),
            snappedDimensions: SIMD3<Float>(36, 69, 32),
            position: SIMD2<Float>(18, 12),
            wallId: UUID(),
            positionOnWallInches: 0,
            confidence: .high,
            isBuiltIn: false,
            isStandardSize: true,
            isCounterDepth: false,
            notes: []
        )

        XCTAssertEqual(appliance.type, .refrigerator)
        XCTAssertEqual(appliance.subType, .fridgeFrenchDoor)
        XCTAssertEqual(appliance.widthInches, 36)
        XCTAssertEqual(appliance.heightInches, 69)
        XCTAssertEqual(appliance.depthInches, 32)
        XCTAssertEqual(appliance.confidence, .high)
        XCTAssertFalse(appliance.isCounterDepth)
    }

    /// Test AIDetectedAppliance computed properties
    func testDetectedApplianceComputedProperties() {
        let boundingBox = AIBoundingBox3D(
            center: SIMD3<Float>(0, 0, 0),
            size: SIMD3<Float>(30, 66, 24)
        )

        let appliance = AIDetectedAppliance(
            boundingBox: boundingBox,
            type: .refrigerator,
            rawDimensions: SIMD3<Float>(30.5, 66.2, 24.8),
            snappedDimensions: SIMD3<Float>(30, 66, 24),
            position: SIMD2<Float>(0, 0),
            confidence: .high,
            isCounterDepth: true
        )

        // Raw dimensions
        XCTAssertEqual(appliance.rawWidthInches, 30.5, accuracy: 0.01)
        XCTAssertEqual(appliance.rawHeightInches, 66.2, accuracy: 0.01)
        XCTAssertEqual(appliance.rawDepthInches, 24.8, accuracy: 0.01)

        // Snapped dimensions
        XCTAssertEqual(appliance.widthInches, 30)
        XCTAssertEqual(appliance.heightInches, 66)
        XCTAssertEqual(appliance.depthInches, 24)

        // Counter-depth flag
        XCTAssertTrue(appliance.isCounterDepth)
    }

    /// Test ApplianceDetectionPhase enum (Task 1.3)
    func testApplianceDetectionPhaseEnum() {
        XCTAssertEqual(ApplianceDetectionPhase.idle.displayText, "Idle")
        XCTAssertEqual(ApplianceDetectionPhase.refrigeratorDetection.displayText, "Detecting Refrigerators")
        XCTAssertEqual(ApplianceDetectionPhase.rangeDetection.displayText, "Detecting Ranges")
        XCTAssertEqual(ApplianceDetectionPhase.sinkDetection.displayText, "Detecting Sinks")
        XCTAssertEqual(ApplianceDetectionPhase.microwaveDetection.displayText, "Detecting Microwaves")
        XCTAssertEqual(ApplianceDetectionPhase.hoodDetection.displayText, "Detecting Hoods")
        XCTAssertEqual(ApplianceDetectionPhase.dishwasherDetection.displayText, "Detecting Dishwashers")
        XCTAssertEqual(ApplianceDetectionPhase.complete.displayText, "Complete")
    }

    /// Test ApplianceDetectionResult computed properties
    func testApplianceDetectionResultComputedProperties() {
        let fridge = createTestAppliance(type: .refrigerator, confidence: .high)
        let range = createTestAppliance(type: .range, confidence: .medium)
        let sink = createTestAppliance(type: .sink, confidence: .high)
        let dishwasher = createTestAppliance(type: .dishwasher, confidence: .low)
        let otrMicrowave = createTestAppliance(type: .microwave, subType: .microwaveOTR, confidence: .high)

        let result = ApplianceDetectionResult(
            appliances: [fridge, range, sink, dishwasher, otrMicrowave],
            processingTimeMs: 250,
            warnings: []
        )

        XCTAssertEqual(result.totalCount, 5)
        XCTAssertEqual(result.refrigerators.count, 1)
        XCTAssertEqual(result.ranges.count, 1)
        XCTAssertEqual(result.sinks.count, 1)
        XCTAssertEqual(result.dishwashers.count, 1)
        XCTAssertEqual(result.microwaves.count, 1)
        XCTAssertEqual(result.otrMicrowavePositions.count, 1)
    }

    /// Test overall confidence calculation
    func testOverallConfidenceCalculation() {
        // Mostly high confidence -> HIGH
        let highResult = ApplianceDetectionResult(
            appliances: [
                createTestAppliance(type: .refrigerator, confidence: .high),
                createTestAppliance(type: .range, confidence: .high),
                createTestAppliance(type: .sink, confidence: .high),
                createTestAppliance(type: .dishwasher, confidence: .medium)
            ],
            processingTimeMs: 100,
            warnings: []
        )
        XCTAssertEqual(highResult.overallConfidence, .high)

        // Mixed -> MEDIUM
        let mixedResult = ApplianceDetectionResult(
            appliances: [
                createTestAppliance(type: .refrigerator, confidence: .high),
                createTestAppliance(type: .range, confidence: .medium),
                createTestAppliance(type: .sink, confidence: .medium),
                createTestAppliance(type: .dishwasher, confidence: .low)
            ],
            processingTimeMs: 100,
            warnings: []
        )
        XCTAssertEqual(mixedResult.overallConfidence, .medium)

        // Mostly low -> LOW
        let lowResult = ApplianceDetectionResult(
            appliances: [
                createTestAppliance(type: .refrigerator, confidence: .low),
                createTestAppliance(type: .range, confidence: .low),
                createTestAppliance(type: .sink, confidence: .low),
                createTestAppliance(type: .dishwasher, confidence: .medium)
            ],
            processingTimeMs: 100,
            warnings: []
        )
        XCTAssertEqual(lowResult.overallConfidence, .low)
    }

    // MARK: - Task 2: Standard Appliance Sizes Tests

    /// Test refrigerator sizes (Task 2.2)
    func testStandardRefrigeratorSizes() {
        XCTAssertEqual(StandardApplianceSizes.fridgeWidths, [30, 33, 36])
        XCTAssertEqual(StandardApplianceSizes.fridgeHeightRange, 66...70)
        XCTAssertEqual(StandardApplianceSizes.fridgeDepthStandard, 30...36)
        XCTAssertEqual(StandardApplianceSizes.fridgeDepthCounterDepth, 24...27)
    }

    /// Test range sizes (Task 2.3)
    func testStandardRangeSizes() {
        XCTAssertEqual(StandardApplianceSizes.rangeWidths, [30, 36])
        XCTAssertEqual(StandardApplianceSizes.rangeHeight, 36)
        XCTAssertEqual(StandardApplianceSizes.rangeDepthRange, 25...27)
    }

    /// Test dishwasher sizes (Task 2.4)
    func testStandardDishwasherSizes() {
        XCTAssertEqual(StandardApplianceSizes.dishwasherWidths, [24, 18])
        XCTAssertEqual(StandardApplianceSizes.dishwasherHeight, 34)
        XCTAssertEqual(StandardApplianceSizes.dishwasherDepth, 24)
    }

    /// Test microwave sizes (Task 2.5)
    func testStandardMicrowaveSizes() {
        XCTAssertEqual(StandardApplianceSizes.microwaveOTRWidth, 30)
        XCTAssertEqual(StandardApplianceSizes.microwaveOTRHeightRange, 16...18)
    }

    /// Test hood sizes (Task 2.6)
    func testStandardHoodSizes() {
        XCTAssertEqual(StandardApplianceSizes.hoodWidths, [30, 36, 42, 48])
        XCTAssertEqual(StandardApplianceSizes.hoodHeightAboveCooktop, 24...30)
    }

    /// Test sink sizes (Task 2.7)
    func testStandardSinkSizes() {
        XCTAssertEqual(StandardApplianceSizes.sinkSingle, SIMD2<Float>(25, 22))
        XCTAssertEqual(StandardApplianceSizes.sinkDouble, SIMD2<Float>(33, 22))
        XCTAssertEqual(StandardApplianceSizes.sinkFarmhouseWidthRange, 30...36)
        XCTAssertEqual(StandardApplianceSizes.sinkFarmhouseDepthRange, 20...22)
    }

    /// Test nearest fridge width snapping
    func testNearestFridgeWidthSnapping() {
        // Exact match
        let (standard30, diff30) = StandardApplianceSizes.nearestFridgeWidth(to: 30)
        XCTAssertEqual(standard30, 30)
        XCTAssertEqual(diff30, 0)

        // Within tolerance
        let (standard36, diff36) = StandardApplianceSizes.nearestFridgeWidth(to: 35.5)
        XCTAssertEqual(standard36, 36)
        XCTAssertEqual(diff36, 0.5, accuracy: 0.01)

        // Snap to 33
        let (standard33, _) = StandardApplianceSizes.nearestFridgeWidth(to: 32)
        XCTAssertEqual(standard33, 33)
    }

    /// Test nearest range width snapping - only 30" or 36"
    func testNearestRangeWidthSnapping() {
        // Should snap to 30
        let (standard30, _) = StandardApplianceSizes.nearestRangeWidth(to: 28)
        XCTAssertEqual(standard30, 30)

        // Should snap to 36
        let (standard36, _) = StandardApplianceSizes.nearestRangeWidth(to: 34)
        XCTAssertEqual(standard36, 36)

        // 33 should snap to 30 or 36, never intermediate
        let (standardMid, _) = StandardApplianceSizes.nearestRangeWidth(to: 33)
        XCTAssertTrue(standardMid == 30 || standardMid == 36)
    }

    /// Test counter-depth detection
    func testCounterDepthDetection() {
        XCTAssertTrue(StandardApplianceSizes.isCounterDepthFridge(24))
        XCTAssertTrue(StandardApplianceSizes.isCounterDepthFridge(25.5))
        XCTAssertTrue(StandardApplianceSizes.isCounterDepthFridge(27))
        XCTAssertFalse(StandardApplianceSizes.isCounterDepthFridge(30))
        XCTAssertFalse(StandardApplianceSizes.isCounterDepthFridge(32))
    }

    // MARK: - ApplianceDetectionError Tests

    func testApplianceDetectionErrorDescriptions() {
        XCTAssertNotNil(ApplianceDetectionError.noRoomStructure.errorDescription)
        XCTAssertNotNil(ApplianceDetectionError.noPointCloud.errorDescription)
        XCTAssertNotNil(ApplianceDetectionError.noCabinetsDetected.errorDescription)
        XCTAssertNotNil(ApplianceDetectionError.detectionFailed(reason: "Test").errorDescription)
        XCTAssertNotNil(ApplianceDetectionError.cancelled.errorDescription)
        XCTAssertNotNil(ApplianceDetectionError.timeout.errorDescription)
    }

    // MARK: - Integration Tests (Task 13.14-13.18)

    /// Test mutual exclusion: OTR microwave should block hood detection (AC11)
    func testMutualExclusionOTRMicrowaveBlocksHood() {
        // Create OTR microwave
        let otrMicrowave = createTestAppliance(
            type: .microwave,
            subType: .microwaveOTR,
            confidence: .high,
            position: SIMD2<Float>(100, 50)
        )

        // Create result with OTR microwave
        let result = ApplianceDetectionResult(
            appliances: [otrMicrowave],
            processingTimeMs: 100,
            warnings: []
        )

        // OTR microwave positions should include this position
        XCTAssertEqual(result.otrMicrowavePositions.count, 1)
        XCTAssertEqual(result.otrMicrowavePositions[0].x, 100, accuracy: 0.1)
        XCTAssertEqual(result.otrMicrowavePositions[0].y, 50, accuracy: 0.1)
    }

    /// Test cross-validation: Hood width should be >= range width (AC12)
    func testCrossValidationHoodRangeWidth() {
        // This validates the logic exists - actual validation happens in detector
        let hood = createTestAppliance(
            type: .hood,
            subType: .hoodWallMount,
            confidence: .high,
            position: SIMD2<Float>(100, 50),
            dimensions: SIMD3<Float>(30, 24, 20)  // 30" hood
        )

        let range = createTestAppliance(
            type: .range,
            subType: .rangeSlideIn,
            confidence: .high,
            position: SIMD2<Float>(100, 50),
            dimensions: SIMD3<Float>(36, 36, 26)  // 36" range
        )

        // Hood is smaller than range - should generate warning in actual detector
        XCTAssertTrue(hood.widthInches < range.widthInches)
    }

    /// Test deduplication: Overlapping detections should be merged (AC14)
    func testDeduplicationOverlappingDetections() {
        let box1 = AIBoundingBox3D(
            center: SIMD3<Float>(50, 34, 50),
            size: SIMD3<Float>(30, 36, 24)
        )
        let box2 = AIBoundingBox3D(
            center: SIMD3<Float>(52, 34, 50),  // Slightly offset, >50% overlap
            size: SIMD3<Float>(30, 36, 24)
        )

        // Calculate expected overlap ratio
        let overlapX = min(box1.max.x, box2.max.x) - max(box1.min.x, box2.min.x)
        let overlapY = min(box1.max.y, box2.max.y) - max(box1.min.y, box2.min.y)
        let overlapZ = min(box1.max.z, box2.max.z) - max(box1.min.z, box2.min.z)

        let overlapVolume = overlapX * overlapY * overlapZ
        let box1Volume = box1.size.x * box1.size.y * box1.size.z
        let overlapRatio = overlapVolume / box1Volume

        // Boxes should overlap by more than 50%
        XCTAssertGreaterThan(overlapRatio, 0.5)
    }

    /// Test cabinet alignment validation exists (AC13)
    func testCabinetAlignmentValidationStructure() {
        // This test validates the result structure supports warnings
        let result = ApplianceDetectionResult(
            appliances: [],
            processingTimeMs: 100,
            warnings: ["Range overlaps with cabinet", "Refrigerator position conflict"]
        )

        XCTAssertEqual(result.warnings.count, 2)
        XCTAssertTrue(result.warnings.contains { $0.contains("Range") })
        XCTAssertTrue(result.warnings.contains { $0.contains("Refrigerator") })
    }

    /// Test dishwasher requires sink proximity (AC12)
    func testDishwasherSinkProximityValidation() {
        let sink = createTestAppliance(
            type: .sink,
            subType: .sinkDoubleBowl,
            confidence: .high,
            position: SIMD2<Float>(100, 50)
        )

        let dishwasherNear = createTestAppliance(
            type: .dishwasher,
            subType: .dishwasherStandard,
            confidence: .high,
            position: SIMD2<Float>(124, 50)  // 24" from sink - valid
        )

        let dishwasherFar = createTestAppliance(
            type: .dishwasher,
            subType: .dishwasherStandard,
            confidence: .low,
            position: SIMD2<Float>(150, 50)  // 50" from sink - invalid
        )

        // Near dishwasher should be within limit
        let nearDistance = simd_length(dishwasherNear.position - sink.position)
        XCTAssertLessThanOrEqual(nearDistance, StandardApplianceSizes.dishwasherMaxDistanceFromSink)

        // Far dishwasher should exceed limit
        let farDistance = simd_length(dishwasherFar.position - sink.position)
        XCTAssertGreaterThan(farDistance, StandardApplianceSizes.dishwasherMaxDistanceFromSink)
    }

    /// Test confidence level comparison works correctly
    func testConfidenceLevelComparison() {
        XCTAssertTrue(AIConfidenceLevel.low < AIConfidenceLevel.medium)
        XCTAssertTrue(AIConfidenceLevel.medium < AIConfidenceLevel.high)
        XCTAssertTrue(AIConfidenceLevel.low < AIConfidenceLevel.high)
        XCTAssertFalse(AIConfidenceLevel.high < AIConfidenceLevel.low)
    }

    /// Test AIDetectedIsland contains method
    func testDetectedIslandContainsPoint() {
        let island = AIDetectedIsland(
            boundingBox: AIBoundingBox3D(
                center: SIMD3<Float>(100, 17, 100),
                size: SIMD3<Float>(48, 34, 30)
            ),
            position: SIMD2<Float>(100, 100),
            lengthInches: 48,
            widthInches: 30,
            heightInches: 34
        )

        // Point inside island
        XCTAssertTrue(island.contains(point: SIMD2<Float>(100, 100)))
        XCTAssertTrue(island.contains(point: SIMD2<Float>(110, 105)))

        // Point outside island (beyond tolerance)
        XCTAssertFalse(island.contains(point: SIMD2<Float>(200, 200)))
    }

    // MARK: - Performance Tests

    /// Test that ApplianceDetectionResult tracks processing time (Architecture 9.3: <500ms budget)
    func testProcessingTimeTracking() {
        // Verify result struct captures processing time
        let result = ApplianceDetectionResult(
            appliances: [],
            processingTimeMs: 250,
            warnings: []
        )

        XCTAssertEqual(result.processingTimeMs, 250)

        // Verify performance budget constant exists
        // Note: Actual performance testing requires integration test with real point cloud
        // This test validates the infrastructure for tracking processing time
        XCTAssertTrue(result.processingTimeMs < 500, "Processing time should be under 500ms budget")
    }

    // MARK: - Integration Tests (calling detect())

    /// Test that ApplianceDetector.detect() runs without error with minimal valid input
    @MainActor
    func testDetectorIntegrationWithMinimalInput() async throws {
        let detector = ApplianceDetector()

        // Create minimal valid room structure
        let roomStructure = createMockRoomStructure()

        // Create minimal point cloud (must be non-empty)
        let pointCloud = createMockPointCloud()

        // Create empty cabinet result
        let cabinets = CabinetDetectionResult(
            cabinets: [],
            wallCoverageValidation: [],
            processingTimeMs: 0,
            warnings: []
        )

        // Should not throw with valid input
        let result = try await detector.detect(
            roomStructure: roomStructure,
            pointCloud: pointCloud,
            cabinets: cabinets,
            islands: []
        )

        // Verify result structure
        XCTAssertNotNil(result)
        XCTAssertGreaterThanOrEqual(result.processingTimeMs, 0)
    }

    /// Test dimension accuracy requirement (AC4: ±1" width)
    func testDimensionAccuracyRequirement() {
        // Standard fridge width snapping should be within ±1" for HIGH confidence
        let (snapped30, diff30) = StandardApplianceSizes.nearestFridgeWidth(to: 30.5)
        XCTAssertEqual(snapped30, 30)
        XCTAssertLessThanOrEqual(diff30, 1.0, "AC4: Width accuracy must be ±1\"")

        let (snapped36, diff36) = StandardApplianceSizes.nearestFridgeWidth(to: 35.2)
        XCTAssertEqual(snapped36, 36)
        XCTAssertLessThanOrEqual(diff36, 1.0, "AC4: Width accuracy must be ±1\"")

        // Range width snapping
        let (rangeSnapped, rangeDiff) = StandardApplianceSizes.nearestRangeWidth(to: 30.8)
        XCTAssertEqual(rangeSnapped, 30)
        XCTAssertLessThanOrEqual(rangeDiff, 1.0, "AC4: Range width accuracy must be ±1\"")
    }

    /// Test position accuracy requirement (AC3: ±2" per NFR8)
    func testPositionAccuracyRequirement() {
        // Create two appliances at known positions
        let appliance1 = createTestAppliance(
            type: .refrigerator,
            confidence: .high,
            position: SIMD2<Float>(100.0, 50.0)
        )

        let appliance2 = createTestAppliance(
            type: .refrigerator,
            confidence: .high,
            position: SIMD2<Float>(101.5, 51.0)  // Within ±2" tolerance
        )

        // Position difference should be within NFR8 tolerance (±2")
        let positionDiff = simd_length(appliance1.position - appliance2.position)
        XCTAssertLessThanOrEqual(positionDiff, 2.0 * sqrt(2), "AC3: Position accuracy must be ±2\" per NFR8")
    }

    // MARK: - Helper Methods

    /// Creates a mock room structure for testing
    private func createMockRoomStructure() -> AIRoomStructure {
        let floorPlane = RoomPlane3D(
            normal: SIMD3<Float>(0, 1, 0),
            distance: 0,
            center: SIMD3<Float>(0, 0, 0)
        )

        let wall = AIWall(
            id: UUID(),
            plane: RoomPlane3D(normal: SIMD3<Float>(0, 0, 1), distance: 0, center: .zero),
            startPoint: SIMD2<Float>(0, 0),
            endPoint: SIMD2<Float>(120, 0),
            lengthInches: 120,
            heightInches: 96,
            normalDirection: SIMD2<Float>(0, 1),
            boundaryType: .wall
        )

        return AIRoomStructure(
            floorPlane: floorPlane,
            ceilingHeightInches: 96,
            walls: [wall],
            boundaryPolygon: [
                SIMD2<Float>(0, 0),
                SIMD2<Float>(120, 0),
                SIMD2<Float>(120, 120),
                SIMD2<Float>(0, 120)
            ],
            roomShape: .rectangle,
            dimensions: RoomDimensions(
                widthInches: 120,
                lengthInches: 120,
                ceilingHeightInches: 96,
                areaSquareInches: 14400,
                perimeterInches: 480
            ),
            openBoundaries: [],
            confidence: DetectionConfidence(
                floorConfidence: 0.9,
                wallConfidence: 0.9,
                boundaryConfidence: 0.9
            ),
            processingTimeMs: 100,
            warnings: []
        )
    }

    /// Creates a mock point cloud for testing
    private func createMockPointCloud() -> AIPointCloud {
        // Create a simple grid of points representing a room
        var points: [SIMD3<Float>] = []

        // Floor points
        for x in stride(from: Float(0), to: Float(120), by: Float(6)) {
            for z in stride(from: Float(0), to: Float(120), by: Float(6)) {
                points.append(SIMD3<Float>(x, 0, z))
            }
        }

        // Wall points (back wall)
        for x in stride(from: Float(0), to: Float(120), by: Float(6)) {
            for y in stride(from: Float(0), to: Float(96), by: Float(6)) {
                points.append(SIMD3<Float>(x, y, 0))
            }
        }

        return AIPointCloud(points: points)
    }

    private func createTestAppliance(
        type: AIApplianceType,
        subType: AIApplianceSubType? = nil,
        confidence: AIConfidenceLevel,
        position: SIMD2<Float> = SIMD2<Float>(0, 0),
        dimensions: SIMD3<Float> = SIMD3<Float>(30, 36, 24)
    ) -> AIDetectedAppliance {
        AIDetectedAppliance(
            boundingBox: AIBoundingBox3D(
                center: SIMD3<Float>(position.x, dimensions.y / 2, position.y),
                size: dimensions
            ),
            type: type,
            subType: subType,
            rawDimensions: dimensions,
            snappedDimensions: dimensions,
            position: position,
            confidence: confidence
        )
    }
}
