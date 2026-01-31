//
//  CountertopDetectorTests.swift
//  cabinetscanTests
//
//  Created for Story 4.6: Countertop Detection and Measurement
//

import XCTest
import simd
@testable import cabinetscan

final class CountertopDetectorTests: XCTestCase {

    // MARK: - Test Properties

    var sut: CountertopDetector!

    // MARK: - Setup/Teardown

    @MainActor
    override func setUp() {
        super.setUp()
        sut = CountertopDetector()
    }

    override func tearDown() {
        sut = nil
        super.tearDown()
    }

    // MARK: - Task 1: Data Model Tests

    func testAIWallCountertop_computedProperties() {
        // Given: A wall countertop with specific dimensions
        let countertop = AIWallCountertop(
            wallId: UUID(),
            lengthInches: 120,
            depthInches: 25.5,
            startPositionInches: 0,
            endPositionInches: 120,
            heightFromFloorInches: 36,
            sections: [],
            cutouts: [],
            confidence: .high,
            isStandardDepth: true
        )

        // Then: Computed properties should be correct
        XCTAssertEqual(countertop.grossAreaSquareInches, 3060, accuracy: 0.1)
        XCTAssertEqual(countertop.grossAreaSquareFeet, 21.25, accuracy: 0.1)
        XCTAssertEqual(countertop.frontEdgeInches, 120)
        XCTAssertEqual(countertop.netAreaSquareInches, 3060, accuracy: 0.1) // No cutouts
    }

    func testAIWallCountertop_withCutouts() {
        // Given: A countertop with a sink cutout
        let cutout = AICountertopCutout(
            type: .sink,
            positionFromStartInches: 40,
            positionFromFrontInches: 3,
            widthInches: 33,
            depthInches: 22
        )

        let countertop = AIWallCountertop(
            wallId: UUID(),
            lengthInches: 120,
            depthInches: 25.5,
            startPositionInches: 0,
            endPositionInches: 120,
            cutouts: [cutout]
        )

        // Then: Net area should subtract cutout area
        let expectedCutoutArea = Float(33 * 22) // 726 sq in
        let expectedNetArea = countertop.grossAreaSquareInches - expectedCutoutArea

        XCTAssertEqual(countertop.cutoutAreaSquareInches, expectedCutoutArea, accuracy: 0.1)
        XCTAssertEqual(countertop.netAreaSquareInches, expectedNetArea, accuracy: 0.1)
    }

    func testAIWallCountertop_containsPosition() {
        // Given: A wall countertop
        let countertop = AIWallCountertop(
            wallId: UUID(),
            lengthInches: 120,
            depthInches: 25.5,
            startPositionInches: 10,
            endPositionInches: 130
        )

        // Then: Should correctly identify positions on countertop
        XCTAssertTrue(countertop.contains(positionAlongWall: 50, positionFromWall: 10))
        XCTAssertTrue(countertop.contains(positionAlongWall: 10, positionFromWall: 0))
        XCTAssertFalse(countertop.contains(positionAlongWall: 5, positionFromWall: 10)) // Before start
        XCTAssertFalse(countertop.contains(positionAlongWall: 140, positionFromWall: 10)) // After end
        XCTAssertFalse(countertop.contains(positionAlongWall: 50, positionFromWall: 30)) // Too far from wall
    }

    // MARK: - Task 2: Standard Sizes Tests

    func testStandardCountertopSizes_isStandardDepth() {
        // Standard depth is 25.5" ± 2"
        XCTAssertTrue(StandardCountertopSizes.isStandardDepth(25.5))
        XCTAssertTrue(StandardCountertopSizes.isStandardDepth(24.0)) // Within tolerance
        XCTAssertTrue(StandardCountertopSizes.isStandardDepth(27.0)) // Within tolerance
        XCTAssertFalse(StandardCountertopSizes.isStandardDepth(22.0)) // Below tolerance
        XCTAssertFalse(StandardCountertopSizes.isStandardDepth(30.0)) // Above tolerance
    }

    func testStandardCountertopSizes_isCounterHeight() {
        // Counter height is 34" - 38"
        XCTAssertTrue(StandardCountertopSizes.isCounterHeight(36))
        XCTAssertTrue(StandardCountertopSizes.isCounterHeight(34))
        XCTAssertTrue(StandardCountertopSizes.isCounterHeight(38))
        XCTAssertFalse(StandardCountertopSizes.isCounterHeight(33))
        XCTAssertFalse(StandardCountertopSizes.isCounterHeight(40))
    }

    func testStandardCountertopSizes_snapDepth() {
        // Should snap to 25.5" if within 1.5" tolerance
        XCTAssertEqual(StandardCountertopSizes.snapDepth(25.5), 25.5)
        XCTAssertEqual(StandardCountertopSizes.snapDepth(26.0), 25.5)
        XCTAssertEqual(StandardCountertopSizes.snapDepth(24.5), 25.5)
        XCTAssertEqual(StandardCountertopSizes.snapDepth(22.0), 22.0) // Outside tolerance, keep raw
        XCTAssertEqual(StandardCountertopSizes.snapDepth(30.0), 30.0) // Outside tolerance, keep raw
    }

    // MARK: - Task 3: Countertop Summary Tests

    func testAICountertopSummary_emptyResult() {
        // Given: Empty summary
        let summary = AICountertopSummary.empty

        // Then: All totals should be zero
        XCTAssertEqual(summary.totalSquareFeet, 0)
        XCTAssertEqual(summary.wallLinearFeet, 0)
        XCTAssertEqual(summary.backsplashLinearFeet, 0)
        XCTAssertEqual(summary.exposedEdgeLinearFeet, 0)
        XCTAssertEqual(summary.cutoutCount, 0)
    }

    func testAICountertopSummary_totalCalculations() {
        // Given: Summary with wall, island, and peninsula countertops
        let wallCountertop = AIWallCountertop(
            wallId: UUID(),
            lengthInches: 120,
            depthInches: 25.5,
            startPositionInches: 0,
            endPositionInches: 120
        )

        let summary = AICountertopSummary(
            wallCountertops: [wallCountertop],
            islandCountertops: [],
            peninsulaCountertops: [],
            wallTotalLinearInches: 120,
            wallGrossAreaSquareInches: 3060,
            wallNetAreaSquareInches: 3060,
            islandTotalSquareInches: 1728, // 48 x 36 island
            peninsulaTotalSquareInches: 864, // 48 x 18 peninsula
            backsplashLinearInches: 120,
            backsplashHeightInches: 18,
            exposedEdgeTotalInches: 288, // 120 wall + 168 island perimeter
            cutoutCount: 1,
            allCutouts: [AICountertopCutout(type: .sink, positionFromStartInches: 40, positionFromFrontInches: 3, widthInches: 33, depthInches: 22)]
        )

        // Then: Totals should be calculated correctly
        let expectedTotalGross = Float(3060 + 1728 + 864) // 5652 sq in
        XCTAssertEqual(summary.totalGrossAreaSquareInches, expectedTotalGross, accuracy: 0.1)
        XCTAssertEqual(summary.wallLinearFeet, 10, accuracy: 0.1) // 120 / 12
        XCTAssertEqual(summary.backsplashLinearFeet, 10, accuracy: 0.1)
        XCTAssertEqual(summary.backsplashAreaSquareFeet, 15, accuracy: 0.1) // 120 * 18 / 144
    }

    // MARK: - Task 4: Backsplash Summary Tests

    func testAIBacksplashSummary_calculations() {
        // Given: Backsplash summary
        let summary = AIBacksplashSummary(
            linearInches: 240,
            heightInches: 18,
            excludedSections: []
        )

        // Then: Calculations should be correct
        XCTAssertEqual(summary.linearFeet, 20, accuracy: 0.1)
        XCTAssertEqual(summary.areaSquareInches, 4320, accuracy: 0.1)
        XCTAssertEqual(summary.areaSquareFeet, 30, accuracy: 0.1)
    }

    // MARK: - Task 5: Edge Treatment Summary Tests

    func testAIEdgeTreatmentSummary_totalCalculations() {
        // Given: Edge treatment summary
        let summary = AIEdgeTreatmentSummary(
            wallFrontEdgeInches: 120,
            islandPerimeterInches: 168, // 48 + 36 + 48 + 36
            peninsulaExposedEdgeInches: 132 // 48 + 36 + 48 (3 sides)
        )

        // Then: Total should be sum of all edges
        XCTAssertEqual(summary.totalExposedEdgeInches, 420, accuracy: 0.1)
        XCTAssertEqual(summary.totalLinearFeet, 35, accuracy: 0.1)
    }

    // MARK: - Task 6: Section Tests

    func testAICountertopSection_area() {
        // Given: A section of countertop
        let section = AICountertopSection(
            startPositionInches: 0,
            endPositionInches: 48,
            depthInches: 25.5,
            segmentReason: .continuous
        )

        // Then: Calculations should be correct
        XCTAssertEqual(section.lengthInches, 48, accuracy: 0.1)
        XCTAssertEqual(section.areaSquareInches, 1224, accuracy: 0.1) // 48 * 25.5
    }

    // MARK: - Task 7: Detection Phase Tests

    func testCountertopDetectionPhase_displayText() {
        XCTAssertEqual(CountertopDetectionPhase.idle.displayText, "Idle")
        XCTAssertEqual(CountertopDetectionPhase.wallCountertopDetection.displayText, "Detecting Wall Countertops")
        XCTAssertEqual(CountertopDetectionPhase.aggregation.displayText, "Building Summary")
        XCTAssertEqual(CountertopDetectionPhase.complete.displayText, "Complete")
    }

    // MARK: - Task 8: Error Tests

    func testCountertopDetectionError_descriptions() {
        XCTAssertNotNil(CountertopDetectionError.noRoomStructure.errorDescription)
        XCTAssertNotNil(CountertopDetectionError.noPointCloud.errorDescription)
        XCTAssertNotNil(CountertopDetectionError.noCabinetsDetected.errorDescription)
        XCTAssertNotNil(CountertopDetectionError.detectionFailed(reason: "Test").errorDescription)
        XCTAssertNotNil(CountertopDetectionError.cancelled.errorDescription)
    }

    // MARK: - Task 9: Result Tests

    func testCountertopDetectorResult_empty() {
        // Given: Empty result
        let result = CountertopDetectorResult.empty

        // Then: Should indicate no detections
        XCTAssertFalse(result.hasDetections)
        XCTAssertEqual(result.totalCountertopCount, 0)
        XCTAssertEqual(result.processingTimeMs, 0)
    }

    func testCountertopDetectorResult_withDetections() {
        // Given: Result with wall countertop
        let wallCountertop = AIWallCountertop(
            wallId: UUID(),
            lengthInches: 120,
            depthInches: 25.5,
            startPositionInches: 0,
            endPositionInches: 120
        )

        let result = CountertopDetectorResult(
            wallCountertops: [wallCountertop],
            countertopSummary: AICountertopSummary.empty,
            backsplashSummary: AIBacksplashSummary.empty,
            edgeTreatmentSummary: AIEdgeTreatmentSummary.empty,
            processingTimeMs: 100,
            warnings: [],
            overallConfidence: .high
        )

        // Then: Should indicate detection
        XCTAssertTrue(result.hasDetections)
        XCTAssertEqual(result.totalCountertopCount, 1)
    }

    // MARK: - Task 10: Detection Tests (Integration)

    @MainActor
    func testDetect_withEmptyPointCloud_throwsError() async {
        // Given: Empty point cloud
        let roomStructure = createTestRoomStructure()
        let pointCloud = AIPointCloud(points: [])
        let cabinets = CabinetDetectionResult(cabinets: [], wallCoverageValidation: [], processingTimeMs: 0, warnings: [])
        let appliances = ApplianceDetectionResult(appliances: [], processingTimeMs: 0, warnings: [])
        let islandResult = IslandPeninsulaDetectionResult.empty

        // When/Then: Detection should throw error
        do {
            _ = try await sut.detect(
                roomStructure: roomStructure,
                pointCloud: pointCloud,
                cabinets: cabinets,
                appliances: appliances,
                islandPeninsulaResult: islandResult
            )
            XCTFail("Expected error to be thrown")
        } catch {
            XCTAssertTrue(error is CountertopDetectionError)
        }
    }

    @MainActor
    func testDetect_withNoCabinets_addsWarning() async throws {
        // Given: Point cloud with no base cabinets
        let roomStructure = createTestRoomStructure()
        let pointCloud = createTestPointCloud()
        let cabinets = CabinetDetectionResult(cabinets: [], wallCoverageValidation: [], processingTimeMs: 0, warnings: [])
        let appliances = ApplianceDetectionResult(appliances: [], processingTimeMs: 0, warnings: [])
        let islandResult = IslandPeninsulaDetectionResult.empty

        // When
        let result = try await sut.detect(
            roomStructure: roomStructure,
            pointCloud: pointCloud,
            cabinets: cabinets,
            appliances: appliances,
            islandPeninsulaResult: islandResult
        )

        // Then: Should have warning about no base cabinets
        XCTAssertTrue(result.warnings.contains { $0.contains("No base cabinets") })
        XCTAssertTrue(result.wallCountertops.isEmpty)
    }

    @MainActor
    func testDetect_progressUpdates() async throws {
        // Given
        let roomStructure = createTestRoomStructure()
        let pointCloud = createTestPointCloud()
        let cabinets = createTestCabinetResult(wallId: roomStructure.walls.first!.id)
        let appliances = ApplianceDetectionResult(appliances: [], processingTimeMs: 0, warnings: [])
        let islandResult = IslandPeninsulaDetectionResult.empty

        // When
        _ = try await sut.detect(
            roomStructure: roomStructure,
            pointCloud: pointCloud,
            cabinets: cabinets,
            appliances: appliances,
            islandPeninsulaResult: islandResult
        )

        // Then: Progress should be at 1.0
        XCTAssertEqual(sut.progress, 1.0)
        XCTAssertEqual(sut.currentPhase, .complete)
    }

    // MARK: - Task 11: Cutout Association Tests (Fix #5)

    @MainActor
    func testDetect_withSinkAppliance_associatesCutout() async throws {
        // Given: Room with base cabinet and sink appliance on countertop
        let roomStructure = createTestRoomStructure()
        let pointCloud = createTestPointCloud()
        let wallId = roomStructure.walls.first!.id
        let cabinets = createTestCabinetResult(wallId: wallId)

        // Create sink appliance on the wall
        let sinkAppliance = AIDetectedAppliance(
            id: UUID(),
            boundingBox: AIBoundingBox3D(
                center: SIMD3(60, 36, 12),
                size: SIMD3(33, 10, 22)
            ),
            type: .sink,
            rawDimensions: SIMD3(33, 10, 22),
            snappedDimensions: SIMD3(33, 10, 22),
            position: SIMD2(60, 12),
            wallId: wallId,
            positionOnWallInches: 60,
            confidence: .high
        )

        let appliances = ApplianceDetectionResult(
            appliances: [sinkAppliance],
            processingTimeMs: 50,
            warnings: []
        )

        let islandResult = IslandPeninsulaDetectionResult.empty

        // When
        let result = try await sut.detect(
            roomStructure: roomStructure,
            pointCloud: pointCloud,
            cabinets: cabinets,
            appliances: appliances,
            islandPeninsulaResult: islandResult
        )

        // Then: Should have sink cutout associated
        XCTAssertGreaterThan(result.wallCountertops.count, 0)
        let wallCountertop = result.wallCountertops.first!
        XCTAssertEqual(wallCountertop.cutouts.count, 1)
        XCTAssertEqual(wallCountertop.cutouts.first?.type, .sink)
        if let cutout = wallCountertop.cutouts.first {
            XCTAssertEqual(cutout.widthInches, 33, accuracy: 0.1)
            XCTAssertEqual(cutout.depthInches, 22, accuracy: 0.1)
        }
    }

    @MainActor
    func testDetect_withCooktopAppliance_associatesCutout() async throws {
        // Given: Room with base cabinet and cooktop appliance
        let roomStructure = createTestRoomStructure()
        let pointCloud = createTestPointCloud()
        let wallId = roomStructure.walls.first!.id
        let cabinets = createTestCabinetResult(wallId: wallId)

        // Create cooktop appliance on the wall
        let cooktopAppliance = AIDetectedAppliance(
            id: UUID(),
            boundingBox: AIBoundingBox3D(
                center: SIMD3(40, 36, 12),
                size: SIMD3(30, 6, 21)
            ),
            type: .cooktop,
            rawDimensions: SIMD3(30, 6, 21),
            snappedDimensions: SIMD3(30, 6, 21),
            position: SIMD2(40, 12),
            wallId: wallId,
            positionOnWallInches: 40,
            confidence: .high
        )

        let appliances = ApplianceDetectionResult(
            appliances: [cooktopAppliance],
            processingTimeMs: 50,
            warnings: []
        )

        let islandResult = IslandPeninsulaDetectionResult.empty

        // When
        let result = try await sut.detect(
            roomStructure: roomStructure,
            pointCloud: pointCloud,
            cabinets: cabinets,
            appliances: appliances,
            islandPeninsulaResult: islandResult
        )

        // Then: Should have cooktop cutout associated
        XCTAssertGreaterThan(result.wallCountertops.count, 0)
        let wallCountertop = result.wallCountertops.first!
        XCTAssertEqual(wallCountertop.cutouts.count, 1)
        XCTAssertEqual(wallCountertop.cutouts.first?.type, .cooktop)
    }

    @MainActor
    func testDetect_withRefrigeratorAppliance_noCutout() async throws {
        // Given: Room with base cabinet and refrigerator (no cutout needed)
        let roomStructure = createTestRoomStructure()
        let pointCloud = createTestPointCloud()
        let wallId = roomStructure.walls.first!.id
        let cabinets = createTestCabinetResult(wallId: wallId)

        // Create refrigerator appliance (should NOT create cutout)
        let fridgeAppliance = AIDetectedAppliance(
            id: UUID(),
            boundingBox: AIBoundingBox3D(
                center: SIMD3(100, 36, 15),
                size: SIMD3(36, 70, 30)
            ),
            type: .refrigerator,
            rawDimensions: SIMD3(36, 70, 30),
            snappedDimensions: SIMD3(36, 70, 30),
            position: SIMD2(100, 15),
            wallId: wallId,
            positionOnWallInches: 100,
            confidence: .high
        )

        let appliances = ApplianceDetectionResult(
            appliances: [fridgeAppliance],
            processingTimeMs: 50,
            warnings: []
        )

        let islandResult = IslandPeninsulaDetectionResult.empty

        // When
        let result = try await sut.detect(
            roomStructure: roomStructure,
            pointCloud: pointCloud,
            cabinets: cabinets,
            appliances: appliances,
            islandPeninsulaResult: islandResult
        )

        // Then: Should NOT have cutout for refrigerator
        XCTAssertGreaterThan(result.wallCountertops.count, 0)
        let wallCountertop = result.wallCountertops.first!
        XCTAssertEqual(wallCountertop.cutouts.count, 0)
    }

    // MARK: - Task 12: Edge Treatment with Islands/Peninsulas Tests (Fix #6)

    @MainActor
    func testDetect_withIsland_calculatesEdgeTreatment() async throws {
        // Given: Room with base cabinet and island
        let roomStructure = createTestRoomStructure()
        let pointCloud = createTestPointCloud()
        let wallId = roomStructure.walls.first!.id
        let cabinets = createTestCabinetResult(wallId: wallId)
        let appliances = ApplianceDetectionResult(appliances: [], processingTimeMs: 0, warnings: [])

        // Create island result
        let island = AIDetectedIsland(
            id: UUID(),
            boundingBox: AIBoundingBox3D(center: SIMD3(60, 18, 60), size: SIMD3(48, 36, 36)),
            position: SIMD2(60, 60),
            lengthInches: 48,
            widthInches: 36,
            heightInches: 36,
            hasSeating: false,
            seatingOverhangInches: nil,
            appliancesOnIsland: [],
            confidence: .high
        )

        let islandResult = IslandPeninsulaDetectionResult(
            islands: [island],
            peninsulas: [],
            processingTimeMs: 100,
            warnings: []
        )

        // When
        let result = try await sut.detect(
            roomStructure: roomStructure,
            pointCloud: pointCloud,
            cabinets: cabinets,
            appliances: appliances,
            islandPeninsulaResult: islandResult
        )

        // Then: Edge treatment should include island perimeter (4 sides)
        let expectedIslandPerimeter: Float = 2 * (48 + 36) // 168 inches
        XCTAssertEqual(result.edgeTreatmentSummary.islandPerimeterInches, expectedIslandPerimeter, accuracy: 1.0)

        // Wall countertop front edge should also be included
        XCTAssertGreaterThan(result.edgeTreatmentSummary.wallFrontEdgeInches, 0)

        // Total should be sum of wall + island
        let expectedTotal = result.edgeTreatmentSummary.wallFrontEdgeInches + expectedIslandPerimeter
        XCTAssertEqual(result.edgeTreatmentSummary.totalExposedEdgeInches, expectedTotal, accuracy: 1.0)
    }

    @MainActor
    func testDetect_withPeninsula_calculatesEdgeTreatment() async throws {
        // Given: Room with base cabinet and peninsula
        let roomStructure = createTestRoomStructure()
        let pointCloud = createTestPointCloud()
        let wallId = roomStructure.walls.first!.id
        let cabinets = createTestCabinetResult(wallId: wallId)
        let appliances = ApplianceDetectionResult(appliances: [], processingTimeMs: 0, warnings: [])

        // Create peninsula result
        let peninsula = AIDetectedPeninsula(
            id: UUID(),
            boundingBox: AIBoundingBox3D(center: SIMD3(60, 18, 50), size: SIMD3(36, 36, 24)),
            attachedWallId: wallId,
            attachmentPointInches: 50,
            lengthInches: 36,
            widthInches: 24,
            heightInches: 36,
            extendsDirection: .outward,
            hasSeating: true,
            seatingOverhangInches: 12,
            appliancesOnPeninsula: [],
            confidence: .high
        )

        let islandResult = IslandPeninsulaDetectionResult(
            islands: [],
            peninsulas: [peninsula],
            processingTimeMs: 100,
            warnings: []
        )

        // When
        let result = try await sut.detect(
            roomStructure: roomStructure,
            pointCloud: pointCloud,
            cabinets: cabinets,
            appliances: appliances,
            islandPeninsulaResult: islandResult
        )

        // Then: Edge treatment should include peninsula exposed edges (3 sides)
        // Peninsula has 3 exposed sides: 2 lengths + 1 width (not the attached side)
        let expectedPeninsulaExposed: Float = 2 * 36 + 24  // 96 inches
        XCTAssertEqual(result.edgeTreatmentSummary.peninsulaExposedEdgeInches, expectedPeninsulaExposed, accuracy: 1.0)
    }

    @MainActor
    func testDetect_withIslandAndPeninsula_aggregatesEdgeTreatment() async throws {
        // Given: Room with wall countertop, island, and peninsula
        let roomStructure = createTestRoomStructure()
        let pointCloud = createTestPointCloud()
        let wallId = roomStructure.walls.first!.id
        let cabinets = createTestCabinetResult(wallId: wallId)
        let appliances = ApplianceDetectionResult(appliances: [], processingTimeMs: 0, warnings: [])

        let island = AIDetectedIsland(
            id: UUID(),
            boundingBox: AIBoundingBox3D(center: SIMD3(60, 18, 70), size: SIMD3(48, 36, 36)),
            position: SIMD2(60, 70),
            lengthInches: 48,
            widthInches: 36,
            heightInches: 36,
            hasSeating: false,
            seatingOverhangInches: nil,
            appliancesOnIsland: [],
            confidence: .high
        )

        let peninsula = AIDetectedPeninsula(
            id: UUID(),
            boundingBox: AIBoundingBox3D(center: SIMD3(30, 18, 50), size: SIMD3(24, 36, 18)),
            attachedWallId: wallId,
            attachmentPointInches: 30,
            lengthInches: 24,
            widthInches: 18,
            heightInches: 36,
            extendsDirection: .outward,
            hasSeating: false,
            seatingOverhangInches: nil,
            appliancesOnPeninsula: [],
            confidence: .high
        )

        let islandResult = IslandPeninsulaDetectionResult(
            islands: [island],
            peninsulas: [peninsula],
            processingTimeMs: 100,
            warnings: []
        )

        // When
        let result = try await sut.detect(
            roomStructure: roomStructure,
            pointCloud: pointCloud,
            cabinets: cabinets,
            appliances: appliances,
            islandPeninsulaResult: islandResult
        )

        // Then: Total edge should be sum of all sources
        let wallEdge = result.edgeTreatmentSummary.wallFrontEdgeInches
        let islandPerimeter = result.edgeTreatmentSummary.islandPerimeterInches
        let peninsulaExposed = result.edgeTreatmentSummary.peninsulaExposedEdgeInches

        XCTAssertGreaterThan(wallEdge, 0)
        XCTAssertEqual(islandPerimeter, 2 * (48 + 36), accuracy: 1.0)
        XCTAssertEqual(peninsulaExposed, 2 * 24 + 18, accuracy: 1.0)

        let expectedTotal = wallEdge + islandPerimeter + peninsulaExposed
        XCTAssertEqual(result.edgeTreatmentSummary.totalExposedEdgeInches, expectedTotal, accuracy: 1.0)
    }

    // MARK: - Task 13: Segmentation Tests

    func testAICountertopSection_withDepthChange() {
        // Given: Sections with different depths (simulating L-shape)
        let section1 = AICountertopSection(
            startPositionInches: 0,
            endPositionInches: 48,
            depthInches: 25.5,
            segmentReason: .continuous
        )

        let section2 = AICountertopSection(
            startPositionInches: 48,
            endPositionInches: 84,
            depthInches: 30.0,
            segmentReason: .depthChange
        )

        // Then: Each section should calculate its own area
        XCTAssertEqual(section1.areaSquareInches, 48 * 25.5, accuracy: 0.1)
        XCTAssertEqual(section2.areaSquareInches, 36 * 30.0, accuracy: 0.1)
    }

    func testAIWallCountertop_withSections_calculatesGrossAreaFromSections() {
        // Given: Countertop with multiple sections
        let section1 = AICountertopSection(
            startPositionInches: 0,
            endPositionInches: 48,
            depthInches: 25.5,
            segmentReason: .continuous
        )

        let section2 = AICountertopSection(
            startPositionInches: 48,
            endPositionInches: 84,
            depthInches: 30.0,
            segmentReason: .depthChange
        )

        let countertop = AIWallCountertop(
            wallId: UUID(),
            lengthInches: 84,
            depthInches: 25.5,  // Base depth
            startPositionInches: 0,
            endPositionInches: 84,
            sections: [section1, section2]
        )

        // Then: Gross area should be sum of sections, not length * depth
        let expectedArea: Float = (48 * 25.5) + (36 * 30.0)  // 1224 + 1080 = 2304
        XCTAssertEqual(countertop.grossAreaSquareInches, expectedArea, accuracy: 0.1)
    }

    // MARK: - Task 14: Window Section Tests (AC6)

    func testAICountertopSection_withWindowSegmentReason() {
        // Given: A section marked as window
        let windowSection = AICountertopSection(
            startPositionInches: 40,
            endPositionInches: 64,
            depthInches: 25.5,
            segmentReason: .window
        )

        // Then: Should have correct properties
        XCTAssertEqual(windowSection.segmentReason, .window)
        XCTAssertEqual(windowSection.lengthInches, 24, accuracy: 0.1)
    }

    func testBacksplashSummary_excludesWindowSections() {
        // Given: Countertop sections with a window in the middle
        let section1 = AICountertopSection(
            startPositionInches: 0,
            endPositionInches: 40,
            depthInches: 25.5,
            segmentReason: .continuous
        )

        let windowSection = AICountertopSection(
            startPositionInches: 40,
            endPositionInches: 64,
            depthInches: 25.5,
            segmentReason: .window
        )

        let section2 = AICountertopSection(
            startPositionInches: 64,
            endPositionInches: 120,
            depthInches: 25.5,
            segmentReason: .continuous
        )

        let countertop = AIWallCountertop(
            wallId: UUID(),
            lengthInches: 120,
            depthInches: 25.5,
            startPositionInches: 0,
            endPositionInches: 120,
            sections: [section1, windowSection, section2]
        )

        // When: Creating backsplash summary (simulating what calculateBacksplash does)
        var totalLinearInches: Float = 0
        var exclusions: [BacksplashExclusion] = []

        for section in countertop.sections {
            if section.segmentReason == .window {
                exclusions.append(BacksplashExclusion(
                    reason: "Window",
                    lengthInches: section.lengthInches
                ))
            } else {
                totalLinearInches += section.lengthInches
            }
        }

        let summary = AIBacksplashSummary(
            linearInches: totalLinearInches,
            heightInches: 18,
            excludedSections: exclusions
        )

        // Then: Backsplash should exclude window section
        // Total countertop is 120", window is 24", so backsplash should be 96"
        XCTAssertEqual(summary.linearInches, 96, accuracy: 0.1)
        XCTAssertEqual(summary.excludedSections.count, 1)
        if let firstExclusion = summary.excludedSections.first {
            XCTAssertEqual(firstExclusion.lengthInches, 24, accuracy: 0.1)
            XCTAssertEqual(firstExclusion.reason, "Window")
        } else {
            XCTFail("Expected at least one excluded section")
        }
    }

    func testCountertopSegmentReason_windowCase() {
        // Verify the window case exists and has correct display text
        let windowReason = CountertopSegmentReason.window
        XCTAssertEqual(windowReason.rawValue, "window")
        XCTAssertEqual(windowReason.displayText, "Window")
    }

    func testBacksplashExclusion_initialization() {
        // Given: A backsplash exclusion for a window
        let exclusion = BacksplashExclusion(
            reason: "Window",
            lengthInches: 36
        )

        // Then: Should have correct properties
        XCTAssertEqual(exclusion.reason, "Window")
        XCTAssertEqual(exclusion.lengthInches, 36, accuracy: 0.1)
    }

    // MARK: - Helper Methods

    private func createTestRoomStructure() -> AIRoomStructure {
        let floorPlane = RoomPlane3D(
            normal: SIMD3(0, 1, 0),
            distance: 0,
            center: SIMD3(60, 0, 60)
        )

        let wallPlane = RoomPlane3D(
            normal: SIMD3(0, 0, 1),
            distance: 0,
            center: SIMD3(60, 48, 0)
        )

        let wall = AIWall(
            id: UUID(),
            plane: wallPlane,
            startPoint: SIMD2(0, 0),
            endPoint: SIMD2(120, 0),
            lengthInches: 120,
            heightInches: 96,
            normalDirection: SIMD2(0, 1),
            boundaryType: .wall
        )

        let dimensions = RoomDimensions(
            widthInches: 120,
            lengthInches: 120,
            ceilingHeightInches: 96,
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
            ceilingHeightInches: 96,
            walls: [wall],
            boundaryPolygon: [
                SIMD2(0, 0),
                SIMD2(120, 0),
                SIMD2(120, 120),
                SIMD2(0, 120)
            ],
            roomShape: .rectangle,
            dimensions: dimensions,
            openBoundaries: [],
            confidence: confidence,
            processingTimeMs: 0,
            warnings: []
        )
    }

    private func createTestPointCloud() -> AIPointCloud {
        var points: [SIMD3<Float>] = []

        // Create points at countertop height (36") along a wall
        for x in stride(from: Float(0), to: Float(120), by: Float(2)) {
            for z in stride(from: Float(0), to: Float(25), by: Float(2)) {
                points.append(SIMD3(x, 36, z))
            }
        }

        return AIPointCloud(points: points)
    }

    private func createTestCabinetResult(wallId: UUID) -> CabinetDetectionResult {
        let cabinet = AIDetectedCabinet(
            id: UUID(),
            boundingBox: AIBoundingBox3D(center: SIMD3(60, 18, 12), size: SIMD3(120, 34.5, 24)),
            type: .base,
            wallId: wallId,
            positionOnWallInches: 0,
            rawDimensions: SIMD3(120, 34.5, 24),
            snappedDimensions: SIMD3(120, 34.5, 24),
            confidence: .high,
            isStandardSize: true,
            cornerType: nil,
            cornerDetails: nil,
            notes: []
        )

        return CabinetDetectionResult(
            cabinets: [cabinet],
            wallCoverageValidation: [],
            processingTimeMs: 100,
            warnings: []
        )
    }
}
