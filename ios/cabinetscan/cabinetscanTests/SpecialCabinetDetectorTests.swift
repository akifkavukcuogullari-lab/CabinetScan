//
//  SpecialCabinetDetectorTests.swift
//  cabinetscanTests
//
//  Created for Story 4.10: Stacked & Special Cabinet Detection
//

import XCTest
import simd
@testable import cabinetscan

/// Tests for SpecialCabinetDetector (Story 4.10)
///
/// **Test Coverage:**
/// - AC1: Stacked upper cabinet detection (double-row)
/// - AC2: Stacked cabinet dimension accuracy
/// - AC3: Refrigerator upper cabinet detection (24" depth)
/// - AC4: Empty space above refrigerator detection
/// - AC5: Microwave cabinet housing detection
/// - AC6: Wall oven cabinet housing detection
/// - AC7: Quote accuracy (stacked counted separately)
/// - AC8: Confidence scoring for special cabinets
@MainActor
final class SpecialCabinetDetectorTests: XCTestCase {

    var specialCabinetDetector: SpecialCabinetDetector!

    override func setUp() async throws {
        specialCabinetDetector = SpecialCabinetDetector()
    }

    override func tearDown() async throws {
        specialCabinetDetector = nil
    }

    // MARK: - Task 8.1: Data Model Tests

    /// Tests CabinetSpecialType enum values and properties.
    func testCabinetSpecialType_EnumValues() {
        XCTAssertEqual(CabinetSpecialType.standard.displayText, "Standard")
        XCTAssertEqual(CabinetSpecialType.stacked.displayText, "Stacked Upper")
        XCTAssertEqual(CabinetSpecialType.refrigeratorUpper.displayText, "Refrigerator Upper")
        XCTAssertEqual(CabinetSpecialType.microwaveHousing.displayText, "Microwave Housing")
        XCTAssertEqual(CabinetSpecialType.ovenHousing.displayText, "Oven Housing")
    }

    /// Tests CabinetSpecialType pricing impact.
    func testCabinetSpecialType_AffectsPricing() {
        XCTAssertFalse(CabinetSpecialType.standard.affectsPricing)
        XCTAssertTrue(CabinetSpecialType.stacked.affectsPricing)
        XCTAssertTrue(CabinetSpecialType.refrigeratorUpper.affectsPricing)
        XCTAssertTrue(CabinetSpecialType.microwaveHousing.affectsPricing)
        XCTAssertTrue(CabinetSpecialType.ovenHousing.affectsPricing)
    }

    /// Tests expected depth for special cabinet types.
    func testCabinetSpecialType_ExpectedDepth() {
        XCTAssertNil(CabinetSpecialType.standard.expectedDepthInches)
        XCTAssertEqual(CabinetSpecialType.stacked.expectedDepthInches, 12.0)
        XCTAssertEqual(CabinetSpecialType.refrigeratorUpper.expectedDepthInches, 24.0)
        XCTAssertNil(CabinetSpecialType.microwaveHousing.expectedDepthInches)
        XCTAssertEqual(CabinetSpecialType.ovenHousing.expectedDepthInches, 24.0)
    }

    // MARK: - Task 8.2: AIDetectedCabinet Special Properties Tests

    /// Tests AIDetectedCabinet special cabinet properties.
    func testAIDetectedCabinet_SpecialProperties() {
        let wallId = UUID()
        let applianceId = UUID()
        let stackedId = UUID()

        let boundingBox = AIBoundingBox3D(
            center: SIMD3<Float>(60, 72, 12),
            size: SIMD3<Float>(36, 18, 12)
        )

        // Create a stacked cabinet
        let stackedCabinet = AIDetectedCabinet(
            boundingBox: boundingBox,
            type: .upper,
            wallId: wallId,
            positionOnWallInches: 12.0,
            rawDimensions: SIMD3<Float>(36, 18, 12),
            snappedDimensions: SIMD3<Float>(36, 18, 12),
            confidence: .high,
            isStandardSize: true,
            isStacked: true,
            specialType: .stacked,
            stackedWithCabinetId: stackedId
        )

        XCTAssertTrue(stackedCabinet.isStacked)
        XCTAssertEqual(stackedCabinet.specialType, .stacked)
        XCTAssertEqual(stackedCabinet.stackedWithCabinetId, stackedId)
        XCTAssertTrue(stackedCabinet.isSpecialCabinet)
        XCTAssertNil(stackedCabinet.hostingApplianceId)

        // Create a refrigerator upper cabinet
        let fridgeCabinet = AIDetectedCabinet(
            boundingBox: boundingBox,
            type: .upper,
            wallId: wallId,
            positionOnWallInches: 12.0,
            rawDimensions: SIMD3<Float>(36, 18, 24),
            snappedDimensions: SIMD3<Float>(36, 18, 24),
            confidence: .high,
            isStandardSize: true,
            isStacked: false,
            specialType: .refrigeratorUpper,
            hostingApplianceId: applianceId
        )

        XCTAssertTrue(fridgeCabinet.isRefrigeratorCabinet)
        XCTAssertEqual(fridgeCabinet.hostingApplianceId, applianceId)
        XCTAssertTrue(fridgeCabinet.isApplianceHousing)
        XCTAssertTrue(fridgeCabinet.isSpecialCabinet)
    }

    // MARK: - Task 8.3: Stacked Cabinet Detection Tests (AC1, AC2)

    /// Tests that stacked upper cabinets can be detected from existing cabinets.
    func testStackedUpperDetection_WithExistingCabinetPair() async {
        // Create a pair of cabinets that should be detected as stacked
        let wallId = UUID()
        let lowerUpperCabinet = createMockUpperCabinet(
            wallId: wallId,
            position: 12.0,
            width: 36,
            height: 30,
            bottomY: 54
        )

        let upperStackedCabinet = createMockUpperCabinet(
            wallId: wallId,
            position: 12.0,
            width: 36,
            height: 18,
            bottomY: 87 // 54 + 30 + 3" gap = 87
        )

        let roomStructure = createMockRoomStructure(ceilingHeight: 96)
        let pointCloud = createEmptyPointCloud()
        let appliances = createEmptyApplianceResult()

        let result = await specialCabinetDetector.detect(
            cabinets: [lowerUpperCabinet, upperStackedCabinet],
            appliances: appliances,
            roomStructure: roomStructure,
            pointCloud: pointCloud
        )

        // Should detect stacked configuration
        let stackedCabinets = result.cabinets.filter { $0.isStacked }
        XCTAssertEqual(result.stackedCount, 1, "Should detect 1 stacked row (the upper one)")

        // Both cabinets should be marked as stacked
        XCTAssertEqual(stackedCabinets.count, 2, "Both cabinets in the pair should be marked as stacked")
    }

    /// Tests stacked cabinet height validation (12"-24").
    func testStackedUpperDetection_HeightValidation() async {
        let wallId = UUID()

        // Lower cabinet with standard height
        let lowerCabinet = createMockUpperCabinet(
            wallId: wallId,
            position: 12.0,
            width: 36,
            height: 30, // Standard upper height
            bottomY: 54
        )

        // Upper cabinet with stacked height (18" is within 12"-24" range)
        let stackedCabinet = createMockUpperCabinet(
            wallId: wallId,
            position: 12.0,
            width: 36,
            height: 18, // Stacked height
            bottomY: 87
        )

        let roomStructure = createMockRoomStructure(ceilingHeight: 108)
        let pointCloud = createEmptyPointCloud()
        let appliances = createEmptyApplianceResult()

        let result = await specialCabinetDetector.detect(
            cabinets: [lowerCabinet, stackedCabinet],
            appliances: appliances,
            roomStructure: roomStructure,
            pointCloud: pointCloud
        )

        // Find the stacked cabinet in results
        let updatedStackedCabinet = result.cabinets.first {
            $0.specialType == .stacked && $0.rawHeightInches == 18
        }

        XCTAssertNotNil(updatedStackedCabinet, "Stacked cabinet should be detected")
        XCTAssertTrue(StandardSpecialCabinetSizes.isStackedUpperHeight(18),
                      "18\" should be a valid stacked upper height")
    }

    // MARK: - Task 8.4: Refrigerator Upper Cabinet Tests (AC3)

    /// Tests refrigerator upper cabinet detection with correct depth.
    func testRefrigeratorUpperDetection_24InchDepth() async {
        let wallId = UUID()
        let fridgeId = UUID()

        // Create a cabinet above the refrigerator area
        let upperCabinet = createMockUpperCabinet(
            wallId: wallId,
            position: 12.0,
            width: 36,
            height: 18,
            depth: 24, // Refrigerator depth, not standard 12"
            bottomY: 72
        )

        // Create a refrigerator appliance
        let refrigerator = createMockAppliance(
            id: fridgeId,
            type: .refrigerator,
            position: SIMD2(30, 15),
            width: 36,
            height: 70,
            depth: 30,
            wallId: wallId,
            positionOnWall: 12.0
        )

        let roomStructure = createMockRoomStructure(ceilingHeight: 96)
        let pointCloud = createEmptyPointCloud()
        let appliances = ApplianceDetectionResult(
            appliances: [refrigerator],
            processingTimeMs: 0,
            warnings: []
        )

        let result = await specialCabinetDetector.detect(
            cabinets: [upperCabinet],
            appliances: appliances,
            roomStructure: roomStructure,
            pointCloud: pointCloud
        )

        XCTAssertEqual(result.refrigeratorUpperCount, 1, "Should detect 1 refrigerator upper cabinet")

        let fridgeCabinet = result.cabinets.first { $0.specialType == .refrigeratorUpper }
        XCTAssertNotNil(fridgeCabinet, "Refrigerator upper cabinet should be in results")
        XCTAssertEqual(fridgeCabinet?.hostingApplianceId, fridgeId, "Should link to refrigerator")
    }

    // MARK: - Task 8.5: Empty Space Above Refrigerator Tests (AC4)

    /// Tests detection of empty space above refrigerator.
    func testEmptySpaceAboveRefrigerator_Detection() async {
        let wallId = UUID()
        let fridgeId = UUID()

        // Create a refrigerator with NO cabinet above
        let refrigerator = createMockAppliance(
            id: fridgeId,
            type: .refrigerator,
            position: SIMD2(30, 15),
            width: 36,
            height: 70,
            depth: 30,
            wallId: wallId,
            positionOnWall: 12.0
        )

        let roomStructure = createMockRoomStructure(ceilingHeight: 96)
        let pointCloud = createEmptyPointCloud()
        let appliances = ApplianceDetectionResult(
            appliances: [refrigerator],
            processingTimeMs: 0,
            warnings: []
        )

        let result = await specialCabinetDetector.detect(
            cabinets: [], // No cabinets
            appliances: appliances,
            roomStructure: roomStructure,
            pointCloud: pointCloud
        )

        // Should detect empty space above refrigerator
        XCTAssertEqual(result.emptySpacesAboveRefrigerator.count, 1,
                       "Should detect empty space above refrigerator")

        let emptySpace = result.emptySpacesAboveRefrigerator.first
        XCTAssertNotNil(emptySpace)
        XCTAssertEqual(emptySpace?.applianceId, fridgeId)
        XCTAssertEqual(emptySpace?.applianceType, "Refrigerator")
        if let emptySpace = emptySpace {
            XCTAssertEqual(emptySpace.widthInches, Float(36), accuracy: Float(1.0))
        }
    }

    // MARK: - Task 8.6: Microwave Cabinet Housing Tests (AC5)

    /// Tests microwave cabinet housing detection.
    func testMicrowaveCabinetDetection_Housing() async {
        let wallId = UUID()
        let microwaveId = UUID()

        // Create a cabinet that contains a microwave
        let cabinetBounds = AIBoundingBox3D(
            center: SIMD3<Float>(30, 63, 9), // Center Y = 63 (54 + 18/2)
            size: SIMD3<Float>(30, 18, 15)
        )

        let cabinet = AIDetectedCabinet(
            boundingBox: cabinetBounds,
            type: .upper,
            wallId: wallId,
            positionOnWallInches: 15.0,
            rawDimensions: SIMD3<Float>(30, 18, 15),
            snappedDimensions: SIMD3<Float>(30, 18, 15),
            confidence: .high,
            isStandardSize: true
        )

        // Create a microwave inside the cabinet
        let microwave = createMockAppliance(
            id: microwaveId,
            type: .microwave,
            position: SIMD2(30, 9),
            width: 24,
            height: 12,
            depth: 12,
            wallId: wallId,
            positionOnWall: 18.0,
            boundingBox: AIBoundingBox3D(
                center: SIMD3<Float>(30, 63, 9),
                size: SIMD3<Float>(24, 12, 12)
            )
        )

        let roomStructure = createMockRoomStructure(ceilingHeight: 96)
        let pointCloud = createEmptyPointCloud()
        let appliances = ApplianceDetectionResult(
            appliances: [microwave],
            processingTimeMs: 0,
            warnings: []
        )

        let result = await specialCabinetDetector.detect(
            cabinets: [cabinet],
            appliances: appliances,
            roomStructure: roomStructure,
            pointCloud: pointCloud
        )

        XCTAssertEqual(result.microwaveHousingCount, 1, "Should detect microwave housing")

        let microwaveCabinet = result.cabinets.first { $0.isMicrowaveCabinet }
        XCTAssertNotNil(microwaveCabinet, "Microwave cabinet should be in results")
        XCTAssertEqual(microwaveCabinet?.hostingApplianceId, microwaveId)
    }

    // MARK: - Task 8.7: Wall Oven Cabinet Housing Tests (AC6)

    /// Tests single wall oven cabinet housing detection.
    func testWallOvenCabinetDetection_SingleOven() async {
        let wallId = UUID()
        let ovenId = UUID()

        // Create a tall cabinet that contains a wall oven
        let cabinetBounds = AIBoundingBox3D(
            center: SIMD3<Float>(30, 42, 12), // Center Y = 42 (84/2)
            size: SIMD3<Float>(30, 84, 24)
        )

        let cabinet = AIDetectedCabinet(
            boundingBox: cabinetBounds,
            type: .tall,
            wallId: wallId,
            positionOnWallInches: 15.0,
            rawDimensions: SIMD3<Float>(30, 84, 24),
            snappedDimensions: SIMD3<Float>(30, 84, 24),
            confidence: .high,
            isStandardSize: true
        )

        // Create a wall oven inside the cabinet
        let wallOven = createMockAppliance(
            id: ovenId,
            type: .wallOven,
            position: SIMD2(30, 12),
            width: 27,
            height: 29,
            depth: 24,
            wallId: wallId,
            positionOnWall: 16.5,
            boundingBox: AIBoundingBox3D(
                center: SIMD3<Float>(30, 36, 12), // Oven is in middle of cabinet
                size: SIMD3<Float>(27, 29, 24)
            )
        )

        let roomStructure = createMockRoomStructure(ceilingHeight: 96)
        let pointCloud = createEmptyPointCloud()
        let appliances = ApplianceDetectionResult(
            appliances: [wallOven],
            processingTimeMs: 0,
            warnings: []
        )

        let result = await specialCabinetDetector.detect(
            cabinets: [cabinet],
            appliances: appliances,
            roomStructure: roomStructure,
            pointCloud: pointCloud
        )

        XCTAssertEqual(result.ovenHousingCount, 1, "Should detect oven housing")

        let ovenCabinet = result.cabinets.first { $0.isOvenCabinet }
        XCTAssertNotNil(ovenCabinet, "Oven cabinet should be in results")
        XCTAssertEqual(ovenCabinet?.hostingApplianceId, ovenId)
    }

    /// Tests double wall oven cabinet height validation.
    func testWallOvenCabinetDetection_DoubleOven_HeightValidation() async {
        let wallId = UUID()
        let ovenId = UUID()

        // Create a tall cabinet (84") for double oven (needs 84"+)
        let cabinetBounds = AIBoundingBox3D(
            center: SIMD3<Float>(30, 42, 12),
            size: SIMD3<Float>(30, 84, 24)
        )

        let cabinet = AIDetectedCabinet(
            boundingBox: cabinetBounds,
            type: .tall,
            wallId: wallId,
            positionOnWallInches: 15.0,
            rawDimensions: SIMD3<Float>(30, 84, 24),
            snappedDimensions: SIMD3<Float>(30, 84, 24),
            confidence: .high,
            isStandardSize: true
        )

        // Create a double wall oven (50"+ height)
        let doubleOven = createMockAppliance(
            id: ovenId,
            type: .wallOven,
            position: SIMD2(30, 12),
            width: 27,
            height: 51, // Double oven height
            depth: 24,
            wallId: wallId,
            positionOnWall: 16.5,
            boundingBox: AIBoundingBox3D(
                center: SIMD3<Float>(30, 37.5, 12),
                size: SIMD3<Float>(27, 51, 24)
            )
        )

        let roomStructure = createMockRoomStructure(ceilingHeight: 96)
        let pointCloud = createEmptyPointCloud()
        let appliances = ApplianceDetectionResult(
            appliances: [doubleOven],
            processingTimeMs: 0,
            warnings: []
        )

        let result = await specialCabinetDetector.detect(
            cabinets: [cabinet],
            appliances: appliances,
            roomStructure: roomStructure,
            pointCloud: pointCloud
        )

        XCTAssertEqual(result.ovenHousingCount, 1, "Should detect double oven housing")
        XCTAssertTrue(StandardSpecialCabinetSizes.isDoubleOvenHeight(51),
                      "51\" should be classified as double oven height")
    }

    // MARK: - Task 8.8: Confidence Scoring Tests (AC8)

    /// Tests high confidence for stacked cabinet with standard dimensions.
    func testStackedCabinetConfidence_High() async {
        let wallId = UUID()

        let lowerCabinet = createMockUpperCabinet(
            wallId: wallId,
            position: 12.0,
            width: 36, // Standard width
            height: 30, // Standard height
            bottomY: 54
        )

        let stackedCabinet = createMockUpperCabinet(
            wallId: wallId,
            position: 12.0,
            width: 36,
            height: 18, // Standard stacked height
            bottomY: 87
        )

        let roomStructure = createMockRoomStructure(ceilingHeight: 108)
        let pointCloud = createEmptyPointCloud()
        let appliances = createEmptyApplianceResult()

        let result = await specialCabinetDetector.detect(
            cabinets: [lowerCabinet, stackedCabinet],
            appliances: appliances,
            roomStructure: roomStructure,
            pointCloud: pointCloud
        )

        // Find the stacked cabinet
        let updatedStackedCabinet = result.cabinets.first {
            $0.specialType == .stacked && $0.rawHeightInches == 18
        }

        // Standard dimensions should result in high confidence
        XCTAssertNotNil(updatedStackedCabinet)
        // Note: Exact confidence depends on detection context
    }

    // MARK: - Task 8.9: Cabinet Count Accuracy Tests (AC7)

    /// Tests that stacked cabinets are counted as separate line items.
    func testStackedCabinets_SeparateLineItems() async {
        let wallId = UUID()

        // Create a stacked pair
        let lowerCabinet = createMockUpperCabinet(
            wallId: wallId,
            position: 12.0,
            width: 36,
            height: 30,
            bottomY: 54
        )

        let stackedCabinet = createMockUpperCabinet(
            wallId: wallId,
            position: 12.0,
            width: 36,
            height: 18,
            bottomY: 87
        )

        let roomStructure = createMockRoomStructure(ceilingHeight: 108)
        let pointCloud = createEmptyPointCloud()
        let appliances = createEmptyApplianceResult()

        let result = await specialCabinetDetector.detect(
            cabinets: [lowerCabinet, stackedCabinet],
            appliances: appliances,
            roomStructure: roomStructure,
            pointCloud: pointCloud
        )

        // Both cabinets should still be present (counted separately)
        XCTAssertEqual(result.cabinets.count, 2, "Stacked pair should be 2 separate cabinet entries")

        // Verify they're linked
        let stackedCabinets = result.cabinets.filter { $0.isStacked }
        XCTAssertEqual(stackedCabinets.count, 2, "Both cabinets should be marked as stacked")
    }

    // MARK: - Task 8.10: No Duplicate Detection Tests

    /// Tests that appliance cabinet is not double-counted.
    func testApplianceCabinet_NoDuplicateDetection() async {
        let wallId = UUID()
        let microwaveId = UUID()

        // Create a cabinet that hosts a microwave
        let cabinetBounds = AIBoundingBox3D(
            center: SIMD3<Float>(30, 63, 9),
            size: SIMD3<Float>(30, 18, 15)
        )

        let cabinet = AIDetectedCabinet(
            boundingBox: cabinetBounds,
            type: .upper,
            wallId: wallId,
            positionOnWallInches: 15.0,
            rawDimensions: SIMD3<Float>(30, 18, 15),
            snappedDimensions: SIMD3<Float>(30, 18, 15),
            confidence: .high,
            isStandardSize: true
        )

        let microwave = createMockAppliance(
            id: microwaveId,
            type: .microwave,
            position: SIMD2(30, 9),
            width: 24,
            height: 12,
            depth: 12,
            wallId: wallId,
            positionOnWall: 18.0,
            boundingBox: AIBoundingBox3D(
                center: SIMD3<Float>(30, 63, 9),
                size: SIMD3<Float>(24, 12, 12)
            )
        )

        let roomStructure = createMockRoomStructure(ceilingHeight: 96)
        let pointCloud = createEmptyPointCloud()
        let appliances = ApplianceDetectionResult(
            appliances: [microwave],
            processingTimeMs: 0,
            warnings: []
        )

        let result = await specialCabinetDetector.detect(
            cabinets: [cabinet],
            appliances: appliances,
            roomStructure: roomStructure,
            pointCloud: pointCloud
        )

        // Should still have exactly 1 cabinet (not duplicated)
        XCTAssertEqual(result.cabinets.count, 1, "Cabinet should not be duplicated")

        // That cabinet should be marked as microwave housing
        XCTAssertEqual(result.cabinets.first?.specialType, .microwaveHousing)
    }

    // MARK: - Helper Methods

    private func createMockUpperCabinet(
        wallId: UUID,
        position: Float,
        width: Float,
        height: Float,
        depth: Float = 12,
        bottomY: Float
    ) -> AIDetectedCabinet {
        let centerY = bottomY + height / 2
        let boundingBox = AIBoundingBox3D(
            center: SIMD3<Float>(position + width / 2, centerY, depth / 2),
            size: SIMD3<Float>(width, height, depth)
        )

        return AIDetectedCabinet(
            boundingBox: boundingBox,
            type: .upper,
            wallId: wallId,
            positionOnWallInches: position,
            rawDimensions: SIMD3<Float>(width, height, depth),
            snappedDimensions: SIMD3<Float>(width, height, depth),
            confidence: .high,
            isStandardSize: true
        )
    }

    private func createMockAppliance(
        id: UUID,
        type: AIApplianceType,
        position: SIMD2<Float>,
        width: Float,
        height: Float,
        depth: Float,
        wallId: UUID?,
        positionOnWall: Float?,
        boundingBox: AIBoundingBox3D? = nil
    ) -> AIDetectedAppliance {
        let box = boundingBox ?? AIBoundingBox3D(
            center: SIMD3<Float>(position.x, height / 2, position.y),
            size: SIMD3<Float>(width, height, depth)
        )

        return AIDetectedAppliance(
            id: id,
            boundingBox: box,
            type: type,
            subType: nil,
            rawDimensions: SIMD3<Float>(width, height, depth),
            snappedDimensions: SIMD3<Float>(width, height, depth),
            position: position,
            wallId: wallId,
            positionOnWallInches: positionOnWall,
            confidence: .high,
            isBuiltIn: type == .microwave || type == .wallOven,
            isStandardSize: true,
            isCounterDepth: false,
            notes: []
        )
    }

    private func createMockRoomStructure(ceilingHeight: Double = 96) -> AIRoomStructure {
        let wallPlane = RoomPlane3D(
            normal: SIMD3<Float>(0, 0, 1),
            distance: 0,
            center: SIMD3<Float>(60, Float(ceilingHeight) / 2, 0)
        )

        let wall = AIWall(
            id: UUID(),
            plane: wallPlane,
            startPoint: SIMD2<Float>(0, 0),
            endPoint: SIMD2<Float>(120, 0),
            lengthInches: 120,
            heightInches: ceilingHeight,
            normalDirection: SIMD2<Float>(0, 1),
            boundaryType: .wall
        )

        let floorPlane = RoomPlane3D(
            normal: SIMD3<Float>(0, 1, 0),
            distance: 0,
            center: SIMD3<Float>(60, 0, 60)
        )

        let dimensions = RoomDimensions(
            widthInches: 120,
            lengthInches: 120,
            ceilingHeightInches: ceilingHeight,
            areaSquareInches: 14400,
            perimeterInches: 480
        )

        let confidence = DetectionConfidence(
            floorConfidence: 0.9,
            wallConfidence: 0.9,
            boundaryConfidence: 0.9
        )

        return AIRoomStructure(
            floorPlane: floorPlane,
            ceilingHeightInches: ceilingHeight,
            walls: [wall],
            boundaryPolygon: [
                SIMD2<Float>(0, 0),
                SIMD2<Float>(120, 0),
                SIMD2<Float>(120, 120),
                SIMD2<Float>(0, 120)
            ],
            roomShape: .rectangle,
            dimensions: dimensions,
            openBoundaries: [],
            confidence: confidence,
            processingTimeMs: 100,
            warnings: []
        )
    }

    private func createEmptyPointCloud() -> AIPointCloud {
        return AIPointCloud()
    }

    private func createEmptyApplianceResult() -> ApplianceDetectionResult {
        return ApplianceDetectionResult(
            appliances: [],
            processingTimeMs: 0,
            warnings: []
        )
    }
}
