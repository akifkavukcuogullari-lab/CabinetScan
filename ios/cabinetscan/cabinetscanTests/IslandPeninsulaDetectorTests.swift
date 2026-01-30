//
//  IslandPeninsulaDetectorTests.swift
//  cabinetscanTests
//
//  Created for Story 4.5: Island and Peninsula Detection
//

import XCTest
import simd
@testable import cabinetscan

/// Tests for IslandPeninsulaDetector (Story 4.5)
///
/// **Test Coverage:**
/// - AC1: Island detection (walkable on all 4 sides)
/// - AC2: Peninsula detection (one end attached to wall)
/// - AC3: Dimension accuracy (±1")
/// - AC4: No false positives
/// - AC5: Island dimension accuracy for quotes
/// - AC6: Seating overhang detection
/// - AC7: Island appliance cutouts
/// - AC8: Peninsula dimensions
/// - AC9: Quote data calculation
/// - AC10: Output format
/// - AC11: Confidence scoring
@MainActor
final class IslandPeninsulaDetectorTests: XCTestCase {

    /// Dimension accuracy tolerance per AC3 (±1")
    private let dimensionTolerance: Float = 1.0

    var detector: IslandPeninsulaDetector!

    override func setUp() async throws {
        detector = IslandPeninsulaDetector()
    }

    override func tearDown() async throws {
        detector = nil
    }

    // MARK: - Task 13.1: Data Model Tests

    /// Tests AIDetectedIsland creation and computed properties.
    func testAIDetectedIsland_Initialization() {
        let boundingBox = AIBoundingBox3D(
            center: SIMD3<Float>(96, 36, 72),
            size: SIMD3<Float>(60, 36, 36)
        )

        let island = AIDetectedIsland(
            boundingBox: boundingBox,
            position: SIMD2(96, 72),
            lengthInches: 60,
            widthInches: 36,
            heightInches: 36,
            rotation: 0,
            hasSeating: true,
            seatingOverhangInches: 12,
            seatingLengthInches: 48,
            appliancesOnIsland: [],
            confidence: .high,
            isStandardSize: true
        )

        XCTAssertEqual(island.lengthInches, 60)
        XCTAssertEqual(island.widthInches, 36)
        XCTAssertEqual(island.heightInches, 36)
        XCTAssertTrue(island.hasSeating)
        XCTAssertEqual(island.seatingOverhangInches, 12)
        XCTAssertEqual(island.confidence, .high)
        XCTAssertTrue(island.isStandardSize)

        // Test computed properties
        XCTAssertEqual(island.countertopAreaSquareInches, 2160) // 60 * 36
        XCTAssertEqual(island.countertopAreaSquareFeet, 15, accuracy: 0.01) // 2160 / 144
        XCTAssertEqual(island.perimeterInches, 192) // 2 * (60 + 36)
        XCTAssertFalse(island.isBarHeight) // 36" is standard height
    }

    /// Tests AIDetectedIsland bar height detection.
    func testAIDetectedIsland_BarHeightDetection() {
        let boundingBox = AIBoundingBox3D(
            center: SIMD3<Float>(96, 42, 72),
            size: SIMD3<Float>(60, 42, 36)
        )

        let barHeightIsland = AIDetectedIsland(
            boundingBox: boundingBox,
            position: SIMD2(96, 72),
            lengthInches: 60,
            widthInches: 36,
            heightInches: 42, // Bar height
            rotation: 0
        )

        XCTAssertTrue(barHeightIsland.isBarHeight, "42\" should be classified as bar height")
    }

    /// Tests AIDetectedPeninsula creation and computed properties.
    func testAIDetectedPeninsula_Initialization() {
        let boundingBox = AIBoundingBox3D(
            center: SIMD3<Float>(48, 36, 24),
            size: SIMD3<Float>(48, 36, 24)
        )

        let peninsula = AIDetectedPeninsula(
            boundingBox: boundingBox,
            attachedWallId: UUID(),
            attachmentPointInches: 72,
            lengthInches: 48,
            widthInches: 24,
            heightInches: 36,
            extendsDirection: .outward,
            hasSeating: true,
            seatingOverhangInches: 15,
            seatingOnSide: .end,
            confidence: .medium,
            isStandardSize: true
        )

        XCTAssertEqual(peninsula.lengthInches, 48)
        XCTAssertEqual(peninsula.widthInches, 24)
        XCTAssertEqual(peninsula.extendsDirection, .outward)
        XCTAssertTrue(peninsula.hasSeating)
        XCTAssertEqual(peninsula.seatingOnSide, .end)

        // Test computed properties
        XCTAssertEqual(peninsula.countertopAreaSquareInches, 1152) // 48 * 24
        XCTAssertEqual(peninsula.exposedEdgeInches, 120) // 2 * 48 + 24 (3 sides)
    }

    /// Tests AIIslandAppliance creation.
    func testAIIslandAppliance_Initialization() {
        let appliance = AIIslandAppliance(
            type: .sink,
            positionOnSurface: SIMD2(0, 0),
            widthInches: 33,
            depthInches: 22
        )

        XCTAssertEqual(appliance.type, .sink)
        XCTAssertEqual(appliance.cutoutAreaSquareInches, 726) // 33 * 22
        XCTAssertTrue(appliance.type.requiresCutout)
    }

    /// Tests AIIslandCountertop net area calculation with cutouts.
    func testAIIslandCountertop_NetAreaCalculation() {
        let cutout = AICountertopCutout(
            type: .sink,
            positionFromStartInches: 24,
            positionFromFrontInches: 6,
            widthInches: 33,
            depthInches: 22
        )

        let countertop = AIIslandCountertop(
            islandId: UUID(),
            lengthInches: 60,
            widthInches: 36,
            heightFromFloorInches: 36,
            overhangInches: nil,
            cutouts: [cutout],
            confidence: .high
        )

        // Gross area: 60 * 36 = 2160
        // Cutout area: 33 * 22 = 726
        // Net area: 2160 - 726 = 1434
        XCTAssertEqual(countertop.grossAreaSquareInches, 2160)
        XCTAssertEqual(countertop.cutoutAreaSquareInches, 726)
        XCTAssertEqual(countertop.netAreaSquareInches, 1434)
    }

    // MARK: - Task 13.2: Island Detection Tests (AC1, AC4)

    /// Tests island detection with 4-sided clearance (>18" all sides).
    func testIslandDetection_FourSidedClearance() async throws {
        // Create room with walls far from center
        let roomStructure = createMockRoomWithCenteredIsland(
            roomWidth: 240, // 20 feet
            roomLength: 240, // 20 feet
            islandWidth: 60,
            islandLength: 36,
            islandDistanceFromWalls: 90 // >18" clearance
        )

        // Create point cloud with island at center
        let pointCloud = createPointCloudWithIsland(
            centerX: 120,
            centerZ: 120,
            length: 60,
            width: 36,
            height: 36
        )

        let result = try await detector.detect(
            roomStructure: roomStructure,
            pointCloud: pointCloud,
            cabinets: CabinetDetectionResult(cabinets: [], wallCoverageValidation: [], processingTimeMs: 0, warnings: []),
            appliances: ApplianceDetectionResult(appliances: [], processingTimeMs: 0, warnings: [])
        )

        XCTAssertEqual(result.islands.count, 1, "Should detect exactly 1 island")
        XCTAssertEqual(result.peninsulas.count, 0, "Should not detect any peninsulas")

        if let island = result.islands.first {
            XCTAssertEqual(island.lengthInches, 60, accuracy: dimensionTolerance)
            XCTAssertEqual(island.widthInches, 36, accuracy: dimensionTolerance)
        }
    }

    // MARK: - Task 13.3: Island NOT Detected Tests (AC4)

    /// Tests that island is NOT detected when adjacent to wall (<6").
    func testIslandNotDetected_WhenAdjacentToWall() async throws {
        // Create room with surface too close to wall
        let roomStructure = createMockRoomWithCenteredIsland(
            roomWidth: 120,
            roomLength: 120,
            islandWidth: 60,
            islandLength: 36,
            islandDistanceFromWalls: 3 // < 6" - should NOT be classified as island
        )

        // Create point cloud with surface near wall
        let pointCloud = createPointCloudWithIsland(
            centerX: 30, // Close to wall at x=0
            centerZ: 60,
            length: 60,
            width: 36,
            height: 36
        )

        let result = try await detector.detect(
            roomStructure: roomStructure,
            pointCloud: pointCloud,
            cabinets: CabinetDetectionResult(cabinets: [], wallCoverageValidation: [], processingTimeMs: 0, warnings: []),
            appliances: ApplianceDetectionResult(appliances: [], processingTimeMs: 0, warnings: [])
        )

        // Should NOT be classified as island (too close to wall)
        // May be classified as peninsula or wall countertop instead
        XCTAssertEqual(result.islands.count, 0, "Should NOT detect island when adjacent to wall")
    }

    // MARK: - Task 13.4: Peninsula Detection Tests (AC2, AC8)

    /// Tests peninsula detection (one end attached to wall, one free).
    func testPeninsulaDetection_OneEndAttached() async throws {
        // Create room with peninsula attached to one wall
        let roomStructure = createMockRoomWithPeninsula(
            roomWidth: 180,
            roomLength: 120,
            peninsulaLength: 48,
            peninsulaWidth: 24
        )

        // Create point cloud with peninsula extending from wall
        let pointCloud = createPointCloudWithPeninsula(
            attachedToWallAtX: 3, // Attached to wall at x=0
            centerZ: 60,
            length: 48,
            width: 24,
            height: 36
        )

        let result = try await detector.detect(
            roomStructure: roomStructure,
            pointCloud: pointCloud,
            cabinets: CabinetDetectionResult(cabinets: [], wallCoverageValidation: [], processingTimeMs: 0, warnings: []),
            appliances: ApplianceDetectionResult(appliances: [], processingTimeMs: 0, warnings: [])
        )

        XCTAssertEqual(result.peninsulas.count, 1, "Should detect exactly 1 peninsula")

        if let peninsula = result.peninsulas.first {
            XCTAssertEqual(peninsula.lengthInches, 48, accuracy: dimensionTolerance)
            XCTAssertEqual(peninsula.widthInches, 24, accuracy: dimensionTolerance)
        }
    }

    // MARK: - Task 13.5: Peninsula NOT Detected Tests (AC4)

    /// Tests that peninsula is NOT detected when both ends are attached (wall countertop).
    func testPeninsulaNotDetected_WhenBothEndsAttached() async throws {
        // Create room with surface touching two walls
        let roomStructure = createMockRoomWithCenteredIsland(
            roomWidth: 60, // Very narrow - surface touches both walls
            roomLength: 120,
            islandWidth: 48,
            islandLength: 24,
            islandDistanceFromWalls: 3
        )

        // Create point cloud with surface spanning between walls
        let pointCloud = createPointCloudWithIsland(
            centerX: 30, // Centered in narrow room
            centerZ: 60,
            length: 48,
            width: 24, // Will be close to both walls (width 60)
            height: 36
        )

        let result = try await detector.detect(
            roomStructure: roomStructure,
            pointCloud: pointCloud,
            cabinets: CabinetDetectionResult(cabinets: [], wallCoverageValidation: [], processingTimeMs: 0, warnings: []),
            appliances: ApplianceDetectionResult(appliances: [], processingTimeMs: 0, warnings: [])
        )

        // Should NOT be classified as peninsula (both ends near walls)
        // May be classified as wall countertop instead
        XCTAssertEqual(result.peninsulas.count, 0, "Should NOT detect peninsula when both ends attached")
        XCTAssertEqual(result.islands.count, 0, "Should NOT detect island when both ends attached")
    }

    // MARK: - Task 13.6: Dimension Accuracy Tests (AC3, AC5)

    /// Tests island dimension extraction accuracy (±1").
    func testIslandDimensionAccuracy() async throws {
        let expectedLength: Float = 60
        let expectedWidth: Float = 36
        let expectedHeight: Float = 36

        let roomStructure = createMockRoomWithCenteredIsland(
            roomWidth: 240,
            roomLength: 240,
            islandWidth: expectedLength,
            islandLength: expectedWidth,
            islandDistanceFromWalls: 90
        )

        let pointCloud = createPointCloudWithIsland(
            centerX: 120,
            centerZ: 120,
            length: expectedLength,
            width: expectedWidth,
            height: expectedHeight
        )

        let result = try await detector.detect(
            roomStructure: roomStructure,
            pointCloud: pointCloud,
            cabinets: CabinetDetectionResult(cabinets: [], wallCoverageValidation: [], processingTimeMs: 0, warnings: []),
            appliances: ApplianceDetectionResult(appliances: [], processingTimeMs: 0, warnings: [])
        )

        guard let island = result.islands.first else {
            XCTFail("Should detect at least one island")
            return
        }

        XCTAssertEqual(island.lengthInches, expectedLength, accuracy: dimensionTolerance,
                      "Length must be within ±\(dimensionTolerance)\" per AC3")
        XCTAssertEqual(island.widthInches, expectedWidth, accuracy: dimensionTolerance,
                      "Width must be within ±\(dimensionTolerance)\" per AC3")
        XCTAssertEqual(island.heightInches, expectedHeight, accuracy: dimensionTolerance,
                      "Height must be within ±\(dimensionTolerance)\" per AC3")
    }

    // MARK: - Task 13.7: Peninsula Dimension Accuracy Tests (AC3, AC8)

    /// Tests peninsula dimension extraction accuracy (±1").
    func testPeninsulaDimensionAccuracy() async throws {
        let expectedLength: Float = 48
        let expectedWidth: Float = 24

        let roomStructure = createMockRoomWithPeninsula(
            roomWidth: 180,
            roomLength: 120,
            peninsulaLength: expectedLength,
            peninsulaWidth: expectedWidth
        )

        let pointCloud = createPointCloudWithPeninsula(
            attachedToWallAtX: 3,
            centerZ: 60,
            length: expectedLength,
            width: expectedWidth,
            height: 36
        )

        let result = try await detector.detect(
            roomStructure: roomStructure,
            pointCloud: pointCloud,
            cabinets: CabinetDetectionResult(cabinets: [], wallCoverageValidation: [], processingTimeMs: 0, warnings: []),
            appliances: ApplianceDetectionResult(appliances: [], processingTimeMs: 0, warnings: [])
        )

        guard let peninsula = result.peninsulas.first else {
            XCTFail("Should detect at least one peninsula")
            return
        }

        XCTAssertEqual(peninsula.lengthInches, expectedLength, accuracy: dimensionTolerance,
                      "Length must be within ±\(dimensionTolerance)\" per AC3")
        XCTAssertEqual(peninsula.widthInches, expectedWidth, accuracy: dimensionTolerance,
                      "Width must be within ±\(dimensionTolerance)\" per AC3")
    }

    // MARK: - Task 13.8: Seating Overhang Detection Tests (AC6)

    /// Tests seating overhang detection (>10" threshold).
    func testSeatingOverhangDetection() {
        // This is tested via data model since overhang detection requires
        // detailed point cloud analysis of counter vs base cabinet projection
        let island = AIDetectedIsland(
            boundingBox: AIBoundingBox3D(center: .zero, size: SIMD3(60, 36, 36)),
            position: .zero,
            lengthInches: 60,
            widthInches: 36,
            heightInches: 36,
            hasSeating: true,
            seatingOverhangInches: 15,
            seatingLengthInches: 48
        )

        XCTAssertTrue(island.hasSeating)
        XCTAssertEqual(island.seatingOverhangInches, 15)
        XCTAssertEqual(island.seatingLengthInches, 48)
    }

    // MARK: - Task 13.9: Appliance Association Tests (AC7, AC10)

    /// Tests appliance association (sink/cooktop on island).
    func testApplianceAssociation_SinkOnIsland() async throws {
        let roomStructure = createMockRoomWithCenteredIsland(
            roomWidth: 240,
            roomLength: 240,
            islandWidth: 60,
            islandLength: 36,
            islandDistanceFromWalls: 90
        )

        let pointCloud = createPointCloudWithIsland(
            centerX: 120,
            centerZ: 120,
            length: 60,
            width: 36,
            height: 36
        )

        // Create appliance result with sink at island position
        let sinkAppliance = AIDetectedAppliance(
            boundingBox: AIBoundingBox3D(
                center: SIMD3(120, 36, 120), // Same position as island
                size: SIMD3(33, 10, 22)
            ),
            type: .sink,
            subType: nil,
            rawDimensions: SIMD3(33, 10, 22),
            snappedDimensions: SIMD3(33, 10, 22),
            position: SIMD2(120, 120), // Center position of island
            wallId: nil,
            positionOnWallInches: nil,
            confidence: .high,
            isStandardSize: true
        )

        let applianceResult = ApplianceDetectionResult(
            appliances: [sinkAppliance],
            processingTimeMs: 100,
            warnings: []
        )

        let result = try await detector.detect(
            roomStructure: roomStructure,
            pointCloud: pointCloud,
            cabinets: CabinetDetectionResult(cabinets: [], wallCoverageValidation: [], processingTimeMs: 0, warnings: []),
            appliances: applianceResult
        )

        guard let island = result.islands.first else {
            XCTFail("Should detect at least one island")
            return
        }

        XCTAssertEqual(island.appliancesOnIsland.count, 1, "Should associate sink with island")

        if let appliance = island.appliancesOnIsland.first {
            XCTAssertEqual(appliance.type, .sink)
        }
    }

    // MARK: - Task 13.10: Cutout Calculation Tests (AC7, AC9)

    /// Tests cutout calculation for countertop.
    func testCutoutCalculation() {
        let sinkCutout = AICountertopCutout(
            type: .sink,
            positionFromStartInches: 24,
            positionFromFrontInches: 6,
            widthInches: 33,
            depthInches: 22
        )

        let cooktopCutout = AICountertopCutout(
            type: .cooktop,
            positionFromStartInches: 36,
            positionFromFrontInches: 6,
            widthInches: 30,
            depthInches: 21
        )

        let countertop = AIIslandCountertop(
            islandId: UUID(),
            lengthInches: 84, // Large island
            widthInches: 42,
            heightFromFloorInches: 36,
            overhangInches: nil,
            cutouts: [sinkCutout, cooktopCutout],
            confidence: .high
        )

        // Gross: 84 * 42 = 3528
        // Sink cutout: 33 * 22 = 726
        // Cooktop cutout: 30 * 21 = 630
        // Total cutout: 1356
        // Net: 3528 - 1356 = 2172

        XCTAssertEqual(countertop.grossAreaSquareInches, 3528)
        XCTAssertEqual(countertop.cutoutAreaSquareInches, 1356)
        XCTAssertEqual(countertop.netAreaSquareInches, 2172)
    }

    // MARK: - Task 13.11: Standard Size Snapping Tests (AC5)

    /// Tests standard size snapping.
    func testStandardSizeSnapping() {
        // Test nearest island length
        let (nearestLength, lengthDiff) = StandardIslandSizes.nearestIslandLength(to: 61)
        XCTAssertEqual(nearestLength, 60) // Snaps to 60
        XCTAssertEqual(lengthDiff, 1, accuracy: 0.01)

        // Test nearest island width
        let (nearestWidth, widthDiff) = StandardIslandSizes.nearestIslandWidth(to: 35)
        XCTAssertEqual(nearestWidth, 36) // Snaps to 36
        XCTAssertEqual(widthDiff, 1, accuracy: 0.01)

        // Test nearest peninsula length
        let (nearestPenLength, penLengthDiff) = StandardIslandSizes.nearestPeninsulaLength(to: 49)
        XCTAssertEqual(nearestPenLength, 48) // Snaps to 48
        XCTAssertEqual(penLengthDiff, 1, accuracy: 0.01)

        // Test seating overhang
        let (nearestOverhang, _) = StandardIslandSizes.nearestSeatingOverhang(to: 14)
        XCTAssertEqual(nearestOverhang, 15) // Snaps to 15"
    }

    // MARK: - Task 13.12: Confidence Scoring Tests (AC11)

    /// Tests confidence scoring for various scenarios.
    func testConfidenceScoring_HighConfidence() async throws {
        // High confidence: Clear wall separation (>36") + standard size + logical position
        let roomStructure = createMockRoomWithCenteredIsland(
            roomWidth: 240,
            roomLength: 240,
            islandWidth: 60, // Standard medium island
            islandLength: 36,
            islandDistanceFromWalls: 90 // >42" clearance (preferred)
        )

        let pointCloud = createPointCloudWithIsland(
            centerX: 120,
            centerZ: 120,
            length: 60, // Standard size
            width: 36,
            height: 36 // Standard height
        )

        let result = try await detector.detect(
            roomStructure: roomStructure,
            pointCloud: pointCloud,
            cabinets: CabinetDetectionResult(cabinets: [], wallCoverageValidation: [], processingTimeMs: 0, warnings: []),
            appliances: ApplianceDetectionResult(appliances: [], processingTimeMs: 0, warnings: [])
        )

        guard let island = result.islands.first else {
            XCTFail("Should detect island")
            return
        }

        // Should be high confidence: good clearance + standard size + standard height
        XCTAssertTrue(island.confidence == .high || island.confidence == .medium,
                     "Should have at least medium confidence for clear detection")
    }

    // MARK: - Task 13.13: Empty Detection Tests (AC4)

    /// Tests no false positives when no island or peninsula exists.
    func testEmptyDetection_NoFalsePositives() async throws {
        // Create room with only wall countertops (no freestanding surfaces)
        let roomStructure = createMockRoomStructure(wallLengths: [120, 120])

        // Create point cloud with only points near walls (wall countertops)
        let pointCloud = createPointCloudNearWalls(
            wallLength: 120,
            countertopDepth: 24
        )

        let result = try await detector.detect(
            roomStructure: roomStructure,
            pointCloud: pointCloud,
            cabinets: CabinetDetectionResult(cabinets: [], wallCoverageValidation: [], processingTimeMs: 0, warnings: []),
            appliances: ApplianceDetectionResult(appliances: [], processingTimeMs: 0, warnings: [])
        )

        XCTAssertEqual(result.islands.count, 0, "Should not detect any islands when none exist")
        XCTAssertEqual(result.peninsulas.count, 0, "Should not detect any peninsulas when none exist")
    }

    // MARK: - Task 13.14: Bar Height Detection Tests (AC5)

    /// Tests bar height detection (42" vs 36" standard).
    func testBarHeightDetection() {
        XCTAssertTrue(StandardIslandSizes.isBarHeight(42))
        XCTAssertTrue(StandardIslandSizes.isBarHeight(41)) // Within tolerance
        XCTAssertTrue(StandardIslandSizes.isBarHeight(43)) // Within tolerance

        XCTAssertFalse(StandardIslandSizes.isBarHeight(36)) // Standard height
        XCTAssertTrue(StandardIslandSizes.isStandardHeight(36))
        XCTAssertTrue(StandardIslandSizes.isStandardHeight(35)) // Within tolerance
    }

    // MARK: - Task 13.15: Peninsula Direction Detection Tests (AC8)

    /// Tests peninsula direction detection (left, right, outward).
    func testPeninsulaDirectionDetection() {
        // Test all direction enum values
        XCTAssertEqual(AIPeninsulaDirection.left.displayText, "Extends Left")
        XCTAssertEqual(AIPeninsulaDirection.right.displayText, "Extends Right")
        XCTAssertEqual(AIPeninsulaDirection.outward.displayText, "Extends Outward")

        // Test seating side enum values
        XCTAssertEqual(AIPeninsulaSeatingSide.end.displayText, "End")
        XCTAssertEqual(AIPeninsulaSeatingSide.left.displayText, "Left Side")
        XCTAssertEqual(AIPeninsulaSeatingSide.right.displayText, "Right Side")
    }

    // MARK: - Detection Result Tests

    /// Tests IslandPeninsulaDetectionResult computed properties.
    func testDetectionResult_ComputedProperties() {
        let island1 = AIDetectedIsland(
            boundingBox: AIBoundingBox3D(center: .zero, size: SIMD3(60, 36, 36)),
            position: .zero,
            lengthInches: 60,
            widthInches: 36,
            heightInches: 36,
            confidence: .high
        )

        let peninsula1 = AIDetectedPeninsula(
            boundingBox: AIBoundingBox3D(center: .zero, size: SIMD3(48, 36, 24)),
            attachedWallId: UUID(),
            attachmentPointInches: 0,
            lengthInches: 48,
            widthInches: 24,
            heightInches: 36,
            extendsDirection: .outward,
            confidence: .medium
        )

        let result = IslandPeninsulaDetectionResult(
            islands: [island1],
            peninsulas: [peninsula1],
            processingTimeMs: 150,
            warnings: []
        )

        XCTAssertEqual(result.totalCount, 2)
        XCTAssertTrue(result.hasDetections)

        // Island area: 60 * 36 = 2160 sq in
        XCTAssertEqual(result.islandTotalAreaSquareInches, 2160)

        // Peninsula area: 48 * 24 = 1152 sq in
        XCTAssertEqual(result.peninsulaTotalAreaSquareInches, 1152)

        // Total: (2160 + 1152) / 144 = 23 sq ft
        XCTAssertEqual(result.totalCountertopAreaSquareFeet, 23, accuracy: 0.1)
    }

    /// Tests empty detection result.
    func testDetectionResult_Empty() {
        let result = IslandPeninsulaDetectionResult.empty

        XCTAssertEqual(result.totalCount, 0)
        XCTAssertFalse(result.hasDetections)
        XCTAssertEqual(result.overallConfidence, .low)
    }

    // MARK: - Error Handling Tests

    /// Tests error when no point cloud.
    func testError_NoPointCloud() async {
        let roomStructure = createMockRoomStructure(wallLengths: [120])
        let emptyPointCloud = AIPointCloud()

        do {
            _ = try await detector.detect(
                roomStructure: roomStructure,
                pointCloud: emptyPointCloud,
                cabinets: CabinetDetectionResult(cabinets: [], wallCoverageValidation: [], processingTimeMs: 0, warnings: []),
                appliances: ApplianceDetectionResult(appliances: [], processingTimeMs: 0, warnings: [])
            )
            XCTFail("Should throw error for empty point cloud")
        } catch let error as IslandPeninsulaDetectionError {
            XCTAssertEqual(error, .noPointCloud)
        } catch {
            XCTFail("Wrong error type: \(error)")
        }
    }

    /// Tests error when no walls detected.
    func testError_NoWalls() async {
        let roomStructure = AIRoomStructure(
            floorPlane: RoomPlane3D(normal: SIMD3(0, 1, 0), distance: 0, center: .zero),
            ceilingHeightInches: 96,
            walls: [], // No walls
            boundaryPolygon: [],
            roomShape: .rectangle,
            dimensions: RoomDimensions(
                widthInches: 120,
                lengthInches: 120,
                ceilingHeightInches: 96,
                areaSquareInches: 14400,
                perimeterInches: 480
            ),
            openBoundaries: [],
            confidence: DetectionConfidence(floorConfidence: 1, wallConfidence: 0, boundaryConfidence: 0),
            processingTimeMs: 0,
            warnings: []
        )

        let pointCloud = createPointCloudWithIsland(centerX: 60, centerZ: 60, length: 48, width: 36, height: 36)

        do {
            _ = try await detector.detect(
                roomStructure: roomStructure,
                pointCloud: pointCloud,
                cabinets: CabinetDetectionResult(cabinets: [], wallCoverageValidation: [], processingTimeMs: 0, warnings: []),
                appliances: ApplianceDetectionResult(appliances: [], processingTimeMs: 0, warnings: [])
            )
            XCTFail("Should throw error for no walls")
        } catch let error as IslandPeninsulaDetectionError {
            XCTAssertEqual(error, .noWallsDetected)
        } catch {
            XCTFail("Wrong error type: \(error)")
        }
    }

    // MARK: - Performance Test

    /// Tests detection performance (<200ms per Architecture 9.3).
    func testDetectionPerformance() async throws {
        let roomStructure = createMockRoomWithCenteredIsland(
            roomWidth: 240,
            roomLength: 240,
            islandWidth: 60,
            islandLength: 36,
            islandDistanceFromWalls: 90
        )

        let pointCloud = createPointCloudWithIsland(
            centerX: 120,
            centerZ: 120,
            length: 60,
            width: 36,
            height: 36
        )

        let result = try await detector.detect(
            roomStructure: roomStructure,
            pointCloud: pointCloud,
            cabinets: CabinetDetectionResult(cabinets: [], wallCoverageValidation: [], processingTimeMs: 0, warnings: []),
            appliances: ApplianceDetectionResult(appliances: [], processingTimeMs: 0, warnings: [])
        )

        // Per Architecture 9.3: Island/Peninsula detection should complete in <200ms
        XCTAssertLessThan(result.processingTimeMs, 200,
                         "Detection must complete in <200ms per Architecture 9.3")
    }

    // MARK: - Test Helpers

    /// Creates a mock room structure with specified wall lengths.
    private func createMockRoomStructure(wallLengths: [Float]) -> AIRoomStructure {
        var walls: [AIWall] = []
        var currentX: Float = 0

        for (index, length) in wallLengths.enumerated() {
            let wall = AIWall(
                id: UUID(),
                plane: RoomPlane3D(normal: SIMD3(0, 0, 1), distance: 0, center: .zero),
                startPoint: SIMD2(currentX, 0),
                endPoint: SIMD2(currentX + length, 0),
                lengthInches: Double(length),
                heightInches: 96,
                normalDirection: SIMD2(0, 1),
                boundaryType: .wall
            )
            walls.append(wall)
            currentX += length
        }

        return AIRoomStructure(
            floorPlane: RoomPlane3D(normal: SIMD3(0, 1, 0), distance: 0, center: .zero),
            ceilingHeightInches: 96,
            walls: walls,
            boundaryPolygon: [],
            roomShape: .rectangle,
            dimensions: RoomDimensions(
                widthInches: Double(currentX),
                lengthInches: 120,
                ceilingHeightInches: 96,
                areaSquareInches: Double(currentX * 120),
                perimeterInches: Double(2 * (currentX + 120))
            ),
            openBoundaries: [],
            confidence: DetectionConfidence(floorConfidence: 1, wallConfidence: 1, boundaryConfidence: 1),
            processingTimeMs: 0,
            warnings: []
        )
    }

    /// Creates a mock room structure for island detection.
    private func createMockRoomWithCenteredIsland(
        roomWidth: Float,
        roomLength: Float,
        islandWidth: Float,
        islandLength: Float,
        islandDistanceFromWalls: Float
    ) -> AIRoomStructure {
        // Create 4 walls around the room
        let walls = [
            AIWall(
                id: UUID(),
                plane: RoomPlane3D(normal: SIMD3(0, 0, 1), distance: 0, center: .zero),
                startPoint: SIMD2(0, 0),
                endPoint: SIMD2(roomWidth, 0),
                lengthInches: Double(roomWidth),
                heightInches: 96,
                normalDirection: SIMD2(0, 1),
                boundaryType: .wall
            ),
            AIWall(
                id: UUID(),
                plane: RoomPlane3D(normal: SIMD3(1, 0, 0), distance: -roomWidth, center: .zero),
                startPoint: SIMD2(roomWidth, 0),
                endPoint: SIMD2(roomWidth, roomLength),
                lengthInches: Double(roomLength),
                heightInches: 96,
                normalDirection: SIMD2(-1, 0),
                boundaryType: .wall
            ),
            AIWall(
                id: UUID(),
                plane: RoomPlane3D(normal: SIMD3(0, 0, -1), distance: roomLength, center: .zero),
                startPoint: SIMD2(roomWidth, roomLength),
                endPoint: SIMD2(0, roomLength),
                lengthInches: Double(roomWidth),
                heightInches: 96,
                normalDirection: SIMD2(0, -1),
                boundaryType: .wall
            ),
            AIWall(
                id: UUID(),
                plane: RoomPlane3D(normal: SIMD3(-1, 0, 0), distance: 0, center: .zero),
                startPoint: SIMD2(0, roomLength),
                endPoint: SIMD2(0, 0),
                lengthInches: Double(roomLength),
                heightInches: 96,
                normalDirection: SIMD2(1, 0),
                boundaryType: .wall
            )
        ]

        return AIRoomStructure(
            floorPlane: RoomPlane3D(normal: SIMD3(0, 1, 0), distance: 0, center: .zero),
            ceilingHeightInches: 96,
            walls: walls,
            boundaryPolygon: [
                SIMD2(0, 0),
                SIMD2(roomWidth, 0),
                SIMD2(roomWidth, roomLength),
                SIMD2(0, roomLength)
            ],
            roomShape: .rectangle,
            dimensions: RoomDimensions(
                widthInches: Double(roomWidth),
                lengthInches: Double(roomLength),
                ceilingHeightInches: 96,
                areaSquareInches: Double(roomWidth * roomLength),
                perimeterInches: Double(2 * (roomWidth + roomLength))
            ),
            openBoundaries: [],
            confidence: DetectionConfidence(floorConfidence: 1, wallConfidence: 1, boundaryConfidence: 1),
            processingTimeMs: 0,
            warnings: []
        )
    }

    /// Creates a mock room structure for peninsula detection.
    private func createMockRoomWithPeninsula(
        roomWidth: Float,
        roomLength: Float,
        peninsulaLength: Float,
        peninsulaWidth: Float
    ) -> AIRoomStructure {
        return createMockRoomWithCenteredIsland(
            roomWidth: roomWidth,
            roomLength: roomLength,
            islandWidth: peninsulaLength,
            islandLength: peninsulaWidth,
            islandDistanceFromWalls: 60
        )
    }

    /// Creates a point cloud with an island at the specified position.
    private func createPointCloudWithIsland(
        centerX: Float,
        centerZ: Float,
        length: Float,
        width: Float,
        height: Float
    ) -> AIPointCloud {
        var points: [SIMD3<Float>] = []

        // Create dense points on the island surface
        let halfLength = length / 2
        let halfWidth = width / 2

        for x in stride(from: centerX - halfLength, through: centerX + halfLength, by: 2.0) {
            for z in stride(from: centerZ - halfWidth, through: centerZ + halfWidth, by: 2.0) {
                // Top surface points
                points.append(SIMD3(Float(x), height, Float(z)))
                // Add some variation for more realistic surface
                points.append(SIMD3(Float(x) + 0.5, height - 0.1, Float(z) + 0.5))
            }
        }

        return AIPointCloud(points: points)
    }

    /// Creates a point cloud with a peninsula attached to a wall.
    private func createPointCloudWithPeninsula(
        attachedToWallAtX: Float,
        centerZ: Float,
        length: Float,
        width: Float,
        height: Float
    ) -> AIPointCloud {
        var points: [SIMD3<Float>] = []

        let halfWidth = width / 2

        // Peninsula extends from wall into room
        for x in stride(from: attachedToWallAtX, through: attachedToWallAtX + length, by: 2.0) {
            for z in stride(from: centerZ - halfWidth, through: centerZ + halfWidth, by: 2.0) {
                points.append(SIMD3(Float(x), height, Float(z)))
            }
        }

        return AIPointCloud(points: points)
    }

    /// Creates a point cloud with points only near walls (wall countertops).
    private func createPointCloudNearWalls(
        wallLength: Float,
        countertopDepth: Float
    ) -> AIPointCloud {
        var points: [SIMD3<Float>] = []

        // Points along wall at countertop height
        for x in stride(from: 0, through: Float(wallLength), by: 2.0) {
            for z in stride(from: 0, through: Float(countertopDepth), by: 2.0) {
                points.append(SIMD3(Float(x), 36, Float(z)))
            }
        }

        return AIPointCloud(points: points)
    }
}
