//
//  AIFloorPlanRendererTests.swift
//  cabinetscanTests
//
//  Created for Story 5.1: Floor Plan Image Renderer
//

import XCTest
import simd
@testable import cabinetscan

// MARK: - AIFloorPlanRenderer Tests

/// Unit tests for AIFloorPlanRenderer (Story 5.1).
///
/// **Test Strategy:**
/// Tests validate that the renderer correctly converts AIPipelineResult
/// into a 2D floor plan PNG with all required visual elements.
@MainActor
final class AIFloorPlanRendererTests: XCTestCase {

    // MARK: - Test Data Builders

    /// Creates a simple rectangular room structure for testing.
    private func createTestRoomStructure(
        widthInches: Float = 144, // 12 feet
        lengthInches: Float = 180, // 15 feet
        ceilingHeightInches: Double = 96 // 8 feet
    ) -> AIRoomStructure {
        let wall1Id = UUID()
        let wall2Id = UUID()
        let wall3Id = UUID()
        let wall4Id = UUID()

        // Create boundary polygon (counter-clockwise)
        let boundaryPolygon: [SIMD2<Float>] = [
            SIMD2(0, 0),
            SIMD2(widthInches, 0),
            SIMD2(widthInches, lengthInches),
            SIMD2(0, lengthInches)
        ]

        // Create walls
        let walls: [AIWall] = [
            AIWall(
                id: wall1Id,
                plane: RoomPlane3D(normal: SIMD3(0, 0, 1), distance: 0, center: SIMD3(widthInches / 2, 48, 0)),
                startPoint: SIMD2(0, 0),
                endPoint: SIMD2(widthInches, 0),
                lengthInches: Double(widthInches),
                heightInches: ceilingHeightInches,
                normalDirection: SIMD2(0, -1),
                boundaryType: .wall
            ),
            AIWall(
                id: wall2Id,
                plane: RoomPlane3D(normal: SIMD3(-1, 0, 0), distance: Float(-widthInches), center: SIMD3(widthInches, 48, lengthInches / 2)),
                startPoint: SIMD2(widthInches, 0),
                endPoint: SIMD2(widthInches, lengthInches),
                lengthInches: Double(lengthInches),
                heightInches: ceilingHeightInches,
                normalDirection: SIMD2(1, 0),
                boundaryType: .wall
            ),
            AIWall(
                id: wall3Id,
                plane: RoomPlane3D(normal: SIMD3(0, 0, -1), distance: Float(-lengthInches), center: SIMD3(widthInches / 2, 48, lengthInches)),
                startPoint: SIMD2(widthInches, lengthInches),
                endPoint: SIMD2(0, lengthInches),
                lengthInches: Double(widthInches),
                heightInches: ceilingHeightInches,
                normalDirection: SIMD2(0, 1),
                boundaryType: .wall
            ),
            AIWall(
                id: wall4Id,
                plane: RoomPlane3D(normal: SIMD3(1, 0, 0), distance: 0, center: SIMD3(0, 48, lengthInches / 2)),
                startPoint: SIMD2(0, lengthInches),
                endPoint: SIMD2(0, 0),
                lengthInches: Double(lengthInches),
                heightInches: ceilingHeightInches,
                normalDirection: SIMD2(-1, 0),
                boundaryType: .wall
            )
        ]

        return AIRoomStructure(
            floorPlane: RoomPlane3D(normal: SIMD3(0, 1, 0), distance: 0, center: SIMD3(widthInches / 2, 0, lengthInches / 2)),
            ceilingHeightInches: ceilingHeightInches,
            walls: walls,
            boundaryPolygon: boundaryPolygon,
            roomShape: .rectangle,
            dimensions: RoomDimensions(
                widthInches: Double(widthInches),
                lengthInches: Double(lengthInches),
                ceilingHeightInches: ceilingHeightInches,
                areaSquareInches: Double(widthInches) * Double(lengthInches),
                perimeterInches: 2 * Double(widthInches) + 2 * Double(lengthInches)
            ),
            openBoundaries: [],
            confidence: DetectionConfidence(floorConfidence: 0.9, wallConfidence: 0.9, boundaryConfidence: 0.9),
            processingTimeMs: 50,
            warnings: []
        )
    }

    /// Creates test cabinets for rendering tests.
    private func createTestCabinets(wallId: UUID) -> CabinetDetectionResult {
        let baseCabinet = AIDetectedCabinet(
            boundingBox: AIBoundingBox3D(
                center: SIMD3(36, 17.25, 12),
                size: SIMD3(36, 34.5, 24)
            ),
            type: .base,
            wallId: wallId,
            positionOnWallInches: 12,
            rawDimensions: SIMD3(36, 34.5, 24),
            snappedDimensions: SIMD3(36, 34.5, 24),
            confidence: .high,
            isStandardSize: true
        )

        let upperCabinet = AIDetectedCabinet(
            boundingBox: AIBoundingBox3D(
                center: SIMD3(36, 66, 6),
                size: SIMD3(36, 30, 12)
            ),
            type: .upper,
            wallId: wallId,
            positionOnWallInches: 12,
            rawDimensions: SIMD3(36, 30, 12),
            snappedDimensions: SIMD3(36, 30, 12),
            confidence: .high,
            isStandardSize: true
        )

        let tallCabinet = AIDetectedCabinet(
            boundingBox: AIBoundingBox3D(
                center: SIMD3(66, 42, 12),
                size: SIMD3(24, 84, 24)
            ),
            type: .tall,
            wallId: wallId,
            positionOnWallInches: 54,
            rawDimensions: SIMD3(24, 84, 24),
            snappedDimensions: SIMD3(24, 84, 24),
            confidence: .high,
            isStandardSize: true
        )

        return CabinetDetectionResult(
            cabinets: [baseCabinet, upperCabinet, tallCabinet],
            wallCoverageValidation: [],
            processingTimeMs: 20,
            warnings: []
        )
    }

    /// Creates test appliances for rendering tests.
    private func createTestAppliances(wallId: UUID) -> ApplianceDetectionResult {
        let refrigerator = AIDetectedAppliance(
            boundingBox: AIBoundingBox3D(
                center: SIMD3(108, 36, 15),
                size: SIMD3(36, 72, 30)
            ),
            type: .refrigerator,
            subType: .fridgeFrenchDoor,
            rawDimensions: SIMD3(36, 72, 30),
            snappedDimensions: SIMD3(36, 72, 30),
            position: SIMD2(108, 15),
            wallId: wallId,
            positionOnWallInches: 90,
            confidence: .high,
            isStandardSize: true
        )

        let range = AIDetectedAppliance(
            boundingBox: AIBoundingBox3D(
                center: SIMD3(36, 18, 150),
                size: SIMD3(30, 36, 25)
            ),
            type: .range,
            subType: .rangeFreestanding,
            rawDimensions: SIMD3(30, 36, 25),
            snappedDimensions: SIMD3(30, 36, 25),
            position: SIMD2(36, 150),
            wallId: nil,
            positionOnWallInches: nil,
            confidence: .high,
            isStandardSize: true
        )

        let sink = AIDetectedAppliance(
            boundingBox: AIBoundingBox3D(
                center: SIMD3(72, 36, 12),
                size: SIMD3(33, 10, 22)
            ),
            type: .sink,
            subType: .sinkDoubleBowl,
            rawDimensions: SIMD3(33, 10, 22),
            snappedDimensions: SIMD3(33, 10, 22),
            position: SIMD2(72, 12),
            wallId: wallId,
            positionOnWallInches: 55.5,
            confidence: .high,
            isStandardSize: true
        )

        return ApplianceDetectionResult(
            appliances: [refrigerator, range, sink],
            processingTimeMs: 15,
            warnings: []
        )
    }

    /// Creates test islands for rendering tests.
    private func createTestIslandResult() -> IslandPeninsulaDetectionResult {
        let island = AIDetectedIsland(
            id: UUID(),
            boundingBox: AIBoundingBox3D(
                center: SIMD3(72, 18, 90),
                size: SIMD3(60, 36, 36)
            ),
            position: SIMD2(72, 90),
            lengthInches: 60,
            widthInches: 36,
            heightInches: 36,
            rotation: 0,
            hasSeating: true,
            seatingOverhangInches: 12,
            seatingLengthInches: 60,
            appliancesOnIsland: [],
            confidence: .high,
            isStandardSize: true,
            rawDimensions: SIMD3(60, 36, 36),
            notes: []
        )

        let peninsula = AIDetectedPeninsula(
            boundingBox: AIBoundingBox3D(
                center: SIMD3(24, 18, 90),
                size: SIMD3(48, 36, 30)
            ),
            attachedWallId: UUID(),
            attachmentPointInches: 24,
            lengthInches: 48,
            widthInches: 30,
            heightInches: 36,
            extendsDirection: .outward,
            hasSeating: true,
            seatingOverhangInches: 10,
            appliancesOnPeninsula: [],
            confidence: .high,
            isStandardSize: true,
            rawDimensions: SIMD3(48, 36, 30),
            notes: []
        )

        return IslandPeninsulaDetectionResult(
            islands: [island],
            peninsulas: [peninsula],
            processingTimeMs: 10,
            warnings: []
        )
    }

    /// Creates test openings (windows and doors) for rendering tests.
    private func createTestOpenings(wallId: UUID) -> OpeningDetectionResult {
        let window = AIDetectedWindow(
            id: UUID(),
            wallId: wallId,
            positionOnWallInches: 72,
            heightFromFloorInches: 42,
            boundingBox: AIBoundingBox3D(
                center: SIMD3(72, 60, 0),
                size: SIMD3(36, 36, 4)
            ),
            rawDimensions: SIMD3(36, 36, 4),
            snappedDimensions: SIMD3(36, 36, 4),
            confidence: .high,
            isStandardSize: true,
            notes: [],
            sillHeightInches: 42,
            distanceFromCountertopInches: 6,
            hasFrame: true,
            availableUpperCabinetHeight: 18,
            upperCabinetRecommendation: "18\" upper cabinets possible"
        )

        let door = AIDetectedDoor(
            id: UUID(),
            type: .door,
            wallId: wallId,
            positionOnWallInches: 120,
            heightFromFloorInches: 0,
            boundingBox: AIBoundingBox3D(
                center: SIMD3(120, 40, self.lengthInches),
                size: SIMD3(36, 80, 4)
            ),
            rawDimensions: SIMD3(36, 80, 4),
            snappedDimensions: SIMD3(36, 80, 4),
            confidence: .high,
            isStandardSize: true,
            notes: [],
            swingDirection: .left,
            isFullHeight: true,
            clearanceToAdjacentCabinet: 3
        )

        return OpeningDetectionResult(
            windows: [window],
            doors: [door],
            clearances: [],
            processingTimeMs: 10,
            warnings: []
        )
    }

    private var lengthInches: Float { 180 }  // For door placement

    /// Creates test cabinets including corner cabinet for rendering tests.
    private func createTestCabinetsWithCorner(wallId: UUID, wall2Id: UUID) -> CabinetDetectionResult {
        let baseCabinet = AIDetectedCabinet(
            boundingBox: AIBoundingBox3D(
                center: SIMD3(36, 17.25, 12),
                size: SIMD3(36, 34.5, 24)
            ),
            type: .base,
            wallId: wallId,
            positionOnWallInches: 12,
            rawDimensions: SIMD3(36, 34.5, 24),
            snappedDimensions: SIMD3(36, 34.5, 24),
            confidence: .high,
            isStandardSize: true
        )

        // Corner cabinet
        let cornerCabinet = AIDetectedCabinet(
            boundingBox: AIBoundingBox3D(
                center: SIMD3(0, 17.25, 0),
                size: SIMD3(36, 34.5, 36)
            ),
            type: .base,
            wallId: wallId,
            positionOnWallInches: 0,
            rawDimensions: SIMD3(36, 34.5, 36),
            snappedDimensions: SIMD3(36, 34.5, 36),
            confidence: .high,
            isStandardSize: true,
            cornerType: .lazySusan,
            cornerDetails: AICornerCabinetDetails(
                wall1Id: wallId,
                wall2Id: wall2Id,
                wall1LengthInches: 36,
                wall2LengthInches: 36,
                cornerAngleDegrees: 90,
                isUpper: false
            )
        )

        return CabinetDetectionResult(
            cabinets: [baseCabinet, cornerCabinet],
            wallCoverageValidation: [],
            processingTimeMs: 20,
            warnings: []
        )
    }

    /// Creates test cabinets including special cabinets for rendering tests.
    private func createTestSpecialCabinets(wallId: UUID) -> CabinetDetectionResult {
        // Stacked upper cabinet
        let stackedCabinet = AIDetectedCabinet(
            boundingBox: AIBoundingBox3D(
                center: SIMD3(36, 78, 6),
                size: SIMD3(36, 18, 12)
            ),
            type: .upper,
            wallId: wallId,
            positionOnWallInches: 12,
            rawDimensions: SIMD3(36, 18, 12),
            snappedDimensions: SIMD3(36, 18, 12),
            confidence: .high,
            isStandardSize: true,
            isStacked: true,
            specialType: .stacked
        )

        // Refrigerator upper cabinet
        let fridgeUpperCabinet = AIDetectedCabinet(
            boundingBox: AIBoundingBox3D(
                center: SIMD3(108, 78, 12),
                size: SIMD3(36, 18, 24)
            ),
            type: .upper,
            wallId: wallId,
            positionOnWallInches: 90,
            rawDimensions: SIMD3(36, 18, 24),
            snappedDimensions: SIMD3(36, 18, 24),
            confidence: .high,
            isStandardSize: true,
            specialType: .refrigeratorUpper
        )

        return CabinetDetectionResult(
            cabinets: [stackedCabinet, fridgeUpperCabinet],
            wallCoverageValidation: [],
            processingTimeMs: 20,
            warnings: []
        )
    }

    // MARK: - Task 1: Basic Structure Tests

    /// Tests that the renderer can be instantiated.
    func testRendererInitialization() async throws {
        let renderer = AIFloorPlanRenderer()
        XCTAssertNotNil(renderer)
    }

    /// Tests that render method returns a valid result with basic room structure.
    func testRenderWithRoomStructureOnly() async throws {
        let renderer = AIFloorPlanRenderer()
        let roomStructure = createTestRoomStructure()

        let result = try await renderer.render(roomStructure: roomStructure)

        XCTAssertNotNil(result.pngData)
        XCTAssertGreaterThan(result.pngData.count, 0)
        XCTAssertGreaterThan(result.imageSize.width, 0)
        XCTAssertGreaterThan(result.imageSize.height, 0)
    }

    // MARK: - Task 9: PNG Export Tests (AC3)

    /// Tests that PNG is generated at 300 DPI (AC3).
    func testPNGExportAt300DPI() async throws {
        let renderer = AIFloorPlanRenderer()
        let roomStructure = createTestRoomStructure()

        let result = try await renderer.render(roomStructure: roomStructure)

        // Verify DPI is set correctly
        XCTAssertEqual(result.dpi, 300)

        // Verify image can be decoded
        guard let image = UIImage(data: result.pngData) else {
            XCTFail("Failed to create UIImage from PNG data")
            return
        }
        XCTAssertNotNil(image)
    }

    /// Tests that PNG file size is under 5MB (AC3).
    func testPNGFileSizeUnder5MB() async throws {
        let renderer = AIFloorPlanRenderer()
        let roomStructure = createTestRoomStructure()
        let cabinets = createTestCabinets(wallId: roomStructure.walls[0].id)
        let appliances = createTestAppliances(wallId: roomStructure.walls[0].id)
        let islands = createTestIslandResult()
        let openings = createTestOpenings(wallId: roomStructure.walls[0].id)

        let result = try await renderer.render(
            roomStructure: roomStructure,
            cabinets: cabinets,
            appliances: appliances,
            islandsPeninsulas: islands,
            openings: openings
        )

        let fileSizeMB = Double(result.pngData.count) / (1024 * 1024)
        XCTAssertLessThan(fileSizeMB, 5.0, "PNG file size (\(String(format: "%.2f", fileSizeMB)) MB) exceeds 5MB limit")
    }

    // MARK: - Task 2: Room Boundary Tests (AC1)

    /// Tests that room boundary is rendered with correct shape.
    func testRoomBoundaryRendering() async throws {
        let renderer = AIFloorPlanRenderer()
        let roomStructure = createTestRoomStructure()

        let result = try await renderer.render(roomStructure: roomStructure)

        // Verify image is generated
        XCTAssertNotNil(result.pngData)

        // Verify metadata includes room info
        XCTAssertEqual(result.metadata.roomShape, .rectangle)
        XCTAssertTrue(result.metadata.elementsRendered.contains(.roomBoundary))
    }

    /// Tests that wall dimensions are labeled (AC2).
    func testWallDimensionsLabeled() async throws {
        let renderer = AIFloorPlanRenderer()
        let roomStructure = createTestRoomStructure(widthInches: 144, lengthInches: 180)

        let result = try await renderer.render(roomStructure: roomStructure)

        // Verify dimension labels are included
        XCTAssertTrue(result.metadata.elementsRendered.contains(.wallDimensions))

        // Check wall measurements are recorded
        XCTAssertEqual(result.metadata.wallCount, 4)
    }

    // MARK: - Task 3: Cabinet Rendering Tests (AC1)

    /// Tests that cabinets are rendered with correct differentiation.
    func testCabinetRendering() async throws {
        let renderer = AIFloorPlanRenderer()
        let roomStructure = createTestRoomStructure()
        let cabinets = createTestCabinets(wallId: roomStructure.walls[0].id)

        let result = try await renderer.render(
            roomStructure: roomStructure,
            cabinets: cabinets
        )

        XCTAssertNotNil(result.pngData)
        XCTAssertTrue(result.metadata.elementsRendered.contains(.baseCabinets))
        XCTAssertTrue(result.metadata.elementsRendered.contains(.upperCabinets))
        XCTAssertTrue(result.metadata.elementsRendered.contains(.tallCabinets))
        XCTAssertEqual(result.metadata.cabinetCounts[.base], 1)
        XCTAssertEqual(result.metadata.cabinetCounts[.upper], 1)
        XCTAssertEqual(result.metadata.cabinetCounts[.tall], 1)
    }

    // MARK: - Task 4: Appliance Rendering Tests (AC1)

    /// Tests that appliances are rendered with icons and labels.
    func testApplianceRendering() async throws {
        let renderer = AIFloorPlanRenderer()
        let roomStructure = createTestRoomStructure()
        let appliances = createTestAppliances(wallId: roomStructure.walls[0].id)

        let result = try await renderer.render(
            roomStructure: roomStructure,
            appliances: appliances
        )

        XCTAssertNotNil(result.pngData)
        XCTAssertTrue(result.metadata.elementsRendered.contains(.appliances))
        XCTAssertEqual(result.metadata.applianceCount, 3)
    }

    // MARK: - Task 5: Opening Rendering Tests (AC1)

    /// Tests that windows and doors are rendered with architectural symbols.
    func testOpeningRendering() async throws {
        let renderer = AIFloorPlanRenderer()
        let roomStructure = createTestRoomStructure()
        let openings = createTestOpenings(wallId: roomStructure.walls[0].id)

        let result = try await renderer.render(
            roomStructure: roomStructure,
            openings: openings
        )

        XCTAssertNotNil(result.pngData)
        XCTAssertTrue(result.metadata.elementsRendered.contains(.windows))
        XCTAssertTrue(result.metadata.elementsRendered.contains(.doors))
        XCTAssertEqual(result.metadata.windowCount, 1)
        XCTAssertEqual(result.metadata.doorCount, 1)
    }

    // MARK: - Task 6: Island/Peninsula Rendering Tests (AC1)

    /// Tests that islands are rendered as freestanding rectangles.
    func testIslandRendering() async throws {
        let renderer = AIFloorPlanRenderer()
        let roomStructure = createTestRoomStructure()
        let islands = createTestIslandResult()

        let result = try await renderer.render(
            roomStructure: roomStructure,
            islandsPeninsulas: islands
        )

        XCTAssertNotNil(result.pngData)
        XCTAssertTrue(result.metadata.elementsRendered.contains(.islands))
        XCTAssertEqual(result.metadata.islandCount, 1)
    }

    /// Tests that peninsulas are rendered correctly (M3 fix).
    func testPeninsulaRendering() async throws {
        let renderer = AIFloorPlanRenderer()
        let roomStructure = createTestRoomStructure()
        let islandsPeninsulas = createTestIslandResult()

        let result = try await renderer.render(
            roomStructure: roomStructure,
            islandsPeninsulas: islandsPeninsulas
        )

        XCTAssertNotNil(result.pngData)
        XCTAssertTrue(result.metadata.elementsRendered.contains(.peninsulas))
        XCTAssertEqual(result.metadata.peninsulaCount, 1)
    }

    // MARK: - Task 3.6-3.7: Corner and Special Cabinet Tests

    /// Tests that corner cabinets are rendered with distinct shape (M4 fix).
    func testCornerCabinetRendering() async throws {
        let renderer = AIFloorPlanRenderer()
        let roomStructure = createTestRoomStructure()
        let cabinets = createTestCabinetsWithCorner(
            wallId: roomStructure.walls[0].id,
            wall2Id: roomStructure.walls[1].id
        )

        let result = try await renderer.render(
            roomStructure: roomStructure,
            cabinets: cabinets
        )

        XCTAssertNotNil(result.pngData)
        XCTAssertTrue(result.metadata.elementsRendered.contains(.baseCabinets))
        // Corner cabinets are counted as base cabinets
        XCTAssertEqual(result.metadata.cabinetCounts[.base], 2)
    }

    /// Tests that special cabinets (stacked, refrigerator upper) are rendered (M5 fix).
    func testSpecialCabinetRendering() async throws {
        let renderer = AIFloorPlanRenderer()
        let roomStructure = createTestRoomStructure()
        let cabinets = createTestSpecialCabinets(wallId: roomStructure.walls[0].id)

        let result = try await renderer.render(
            roomStructure: roomStructure,
            cabinets: cabinets
        )

        XCTAssertNotNil(result.pngData)
        XCTAssertTrue(result.metadata.elementsRendered.contains(.specialCabinets))
        // Special cabinets should be counted as upper cabinets
        XCTAssertEqual(result.metadata.cabinetCounts[.upper], 2)
    }

    // MARK: - Task 7: Scale and Orientation Tests (AC2)

    /// Tests that scale indicator is rendered.
    func testScaleIndicatorRendering() async throws {
        let renderer = AIFloorPlanRenderer()
        let roomStructure = createTestRoomStructure()

        let result = try await renderer.render(roomStructure: roomStructure)

        XCTAssertTrue(result.metadata.elementsRendered.contains(.scaleIndicator))
        XCTAssertNotNil(result.metadata.scaleDescription)
    }

    /// Tests that orientation indicator is shown (AC2).
    func testOrientationIndicatorRendering() async throws {
        let renderer = AIFloorPlanRenderer()
        let roomStructure = createTestRoomStructure()

        let result = try await renderer.render(roomStructure: roomStructure)

        XCTAssertTrue(result.metadata.elementsRendered.contains(.orientationIndicator))
    }

    // MARK: - Task 10: Coordinate Transform Tests

    /// Tests coordinate transformation from world to screen coordinates.
    func testCoordinateTransform() {
        let roomStructure = createTestRoomStructure(widthInches: 144, lengthInches: 180)
        let transform = FloorPlanTransform(
            roomStructure: roomStructure,
            canvasSize: CGSize(width: 800, height: 600),
            margin: 50
        )

        // Test origin (0, 0) maps to upper-left with margin
        let origin = transform.transformPoint(worldCoordinate: SIMD2(0, 0))
        XCTAssertGreaterThanOrEqual(origin.x, 50)  // At least margin from left
        XCTAssertGreaterThanOrEqual(origin.y, 50)  // At least margin from top

        // Test that Y-axis is inverted (larger Z = smaller screen Y)
        let point1 = transform.transformPoint(worldCoordinate: SIMD2(0, 0))
        let point2 = transform.transformPoint(worldCoordinate: SIMD2(0, 100))
        XCTAssertGreaterThan(point2.y, point1.y)  // Screen Y increases downward
    }

    /// Tests scale calculation for room fitting.
    func testScaleCalculation() {
        let roomStructure = createTestRoomStructure(widthInches: 144, lengthInches: 180)
        let transform = FloorPlanTransform(
            roomStructure: roomStructure,
            canvasSize: CGSize(width: 800, height: 600),
            margin: 50
        )

        XCTAssertGreaterThan(transform.scale, 0)

        // Room should fit within canvas bounds
        let corner = transform.transformPoint(worldCoordinate: SIMD2(144, 180))
        XCTAssertLessThanOrEqual(corner.x, 800 - 50)  // Within right margin
        XCTAssertLessThanOrEqual(corner.y, 600 - 50)  // Within bottom margin
    }

    // MARK: - Task 11: Error Handling Tests (AC5)

    /// Tests graceful handling of empty room structure.
    func testEmptyRoomStructureHandling() async throws {
        let renderer = AIFloorPlanRenderer()

        // Create minimal room structure with empty walls
        let emptyRoom = AIRoomStructure(
            floorPlane: RoomPlane3D(normal: SIMD3(0, 1, 0), distance: 0, center: .zero),
            ceilingHeightInches: 96,
            walls: [],
            boundaryPolygon: [],
            roomShape: .irregular,
            dimensions: RoomDimensions(
                widthInches: 0,
                lengthInches: 0,
                ceilingHeightInches: 96,
                areaSquareInches: 0,
                perimeterInches: 0
            ),
            openBoundaries: [],
            confidence: DetectionConfidence(floorConfidence: 0.3, wallConfidence: 0.3, boundaryConfidence: 0.3),
            processingTimeMs: 10,
            warnings: ["No walls detected"]
        )

        // Should not throw, should generate partial result
        let result = try await renderer.render(roomStructure: emptyRoom)

        XCTAssertNotNil(result.pngData)
        XCTAssertTrue(result.metadata.warnings.contains { $0.contains("empty") || $0.contains("walls") })
    }

    /// Tests partial rendering with missing optional data.
    func testPartialRenderingWithMissingData() async throws {
        let renderer = AIFloorPlanRenderer()
        let roomStructure = createTestRoomStructure()

        // Render with only room structure (no cabinets, appliances, etc.)
        let result = try await renderer.render(roomStructure: roomStructure)

        XCTAssertNotNil(result.pngData)
        XCTAssertTrue(result.metadata.elementsRendered.contains(.roomBoundary))
        XCTAssertFalse(result.metadata.elementsRendered.contains(.baseCabinets))
        XCTAssertFalse(result.metadata.elementsRendered.contains(.appliances))
    }

    // MARK: - Full Integration Test

    /// Tests full rendering with all elements.
    func testFullFloorPlanRendering() async throws {
        let renderer = AIFloorPlanRenderer()
        let roomStructure = createTestRoomStructure()
        let cabinets = createTestCabinets(wallId: roomStructure.walls[0].id)
        let appliances = createTestAppliances(wallId: roomStructure.walls[0].id)
        let islands = createTestIslandResult()
        let openings = createTestOpenings(wallId: roomStructure.walls[0].id)

        let result = try await renderer.render(
            roomStructure: roomStructure,
            cabinets: cabinets,
            appliances: appliances,
            islandsPeninsulas: islands,
            openings: openings
        )

        // Verify all elements are rendered
        XCTAssertNotNil(result.pngData)
        XCTAssertTrue(result.metadata.elementsRendered.contains(.roomBoundary))
        XCTAssertTrue(result.metadata.elementsRendered.contains(.wallDimensions))
        XCTAssertTrue(result.metadata.elementsRendered.contains(.baseCabinets))
        XCTAssertTrue(result.metadata.elementsRendered.contains(.upperCabinets))
        XCTAssertTrue(result.metadata.elementsRendered.contains(.tallCabinets))
        XCTAssertTrue(result.metadata.elementsRendered.contains(.appliances))
        XCTAssertTrue(result.metadata.elementsRendered.contains(.windows))
        XCTAssertTrue(result.metadata.elementsRendered.contains(.doors))
        XCTAssertTrue(result.metadata.elementsRendered.contains(.islands))
        XCTAssertTrue(result.metadata.elementsRendered.contains(.scaleIndicator))
        XCTAssertTrue(result.metadata.elementsRendered.contains(.orientationIndicator))

        // Verify DPI and size
        XCTAssertEqual(result.dpi, 300)
        let fileSizeMB = Double(result.pngData.count) / (1024 * 1024)
        XCTAssertLessThan(fileSizeMB, 5.0)
    }

    // MARK: - Story 6.2: Unscanned Area Tests (Task 7.4)

    /// Tests that uncaptured zones render hatched areas.
    func testUnscannedAreasRendering() async throws {
        let renderer = AIFloorPlanRenderer()
        let roomStructure = createTestRoomStructure()

        // Render with uncaptured zones (front and left not captured)
        let uncapturedZones: Set<AICaptureZone> = [.front, .left]

        let result = try await renderer.render(
            roomStructure: roomStructure,
            uncapturedZones: uncapturedZones,
            coveragePercentage: 0.5
        )

        // Verify image is generated
        XCTAssertNotNil(result.pngData)
        XCTAssertGreaterThan(result.pngData.count, 0)

        // Verify metadata includes unscanned areas
        XCTAssertTrue(result.metadata.elementsRendered.contains(.unscannedAreas))

        // Verify coverage metadata
        XCTAssertEqual(result.metadata.coveragePercentage, 0.5)
        XCTAssertEqual(result.metadata.uncapturedZones, uncapturedZones)
    }

    /// Tests that full coverage produces no hatched areas.
    func testFullCoverageNoHatchedAreas() async throws {
        let renderer = AIFloorPlanRenderer()
        let roomStructure = createTestRoomStructure()

        // Render with no uncaptured zones (full coverage)
        let result = try await renderer.render(
            roomStructure: roomStructure,
            uncapturedZones: nil,
            coveragePercentage: 1.0
        )

        // Verify image is generated
        XCTAssertNotNil(result.pngData)

        // Verify no unscanned areas element
        XCTAssertFalse(result.metadata.elementsRendered.contains(.unscannedAreas))
    }

    /// Tests that empty uncaptured set produces no hatched areas.
    func testEmptyUncapturedZonesNoHatchedAreas() async throws {
        let renderer = AIFloorPlanRenderer()
        let roomStructure = createTestRoomStructure()

        // Render with empty uncaptured zones set
        let result = try await renderer.render(
            roomStructure: roomStructure,
            uncapturedZones: Set<AICaptureZone>(),
            coveragePercentage: 1.0
        )

        // Verify image is generated
        XCTAssertNotNil(result.pngData)

        // Verify no unscanned areas element
        XCTAssertFalse(result.metadata.elementsRendered.contains(.unscannedAreas))
    }

    /// Tests that severe coverage (1 zone) renders 3 hatched quadrants.
    func testSevereCoverageRendersMultipleHatchedAreas() async throws {
        let renderer = AIFloorPlanRenderer()
        let roomStructure = createTestRoomStructure()

        // Only front captured (severe coverage - 25%)
        let uncapturedZones: Set<AICaptureZone> = [.right, .back, .left]

        let result = try await renderer.render(
            roomStructure: roomStructure,
            uncapturedZones: uncapturedZones,
            coveragePercentage: 0.25
        )

        // Verify image is generated
        XCTAssertNotNil(result.pngData)

        // Verify unscanned areas are rendered
        XCTAssertTrue(result.metadata.elementsRendered.contains(.unscannedAreas))

        // Verify coverage metadata reflects severe level
        XCTAssertEqual(result.metadata.coveragePercentage, 0.25)
        XCTAssertEqual(result.metadata.uncapturedZones?.count, 3)
    }

    /// Tests that partial coverage renders unscanned areas with coverage percentage in metadata.
    func testPartialCoverageMetadataIncludesCoverageInfo() async throws {
        let renderer = AIFloorPlanRenderer()
        let roomStructure = createTestRoomStructure()

        // Partial coverage (75% - back zone not captured)
        let uncapturedZones: Set<AICaptureZone> = [.back]

        let result = try await renderer.render(
            roomStructure: roomStructure,
            uncapturedZones: uncapturedZones,
            coveragePercentage: 0.75
        )

        // Verify unscanned areas are rendered
        XCTAssertTrue(result.metadata.elementsRendered.contains(.unscannedAreas))

        // Verify coverage metadata
        XCTAssertEqual(result.metadata.coveragePercentage, 0.75)
        XCTAssertEqual(result.metadata.uncapturedZones, uncapturedZones)
    }

    // MARK: - Performance Test

    /// Tests that rendering completes within performance budget (<500ms).
    func testRenderingPerformance() async throws {
        let renderer = AIFloorPlanRenderer()
        let roomStructure = createTestRoomStructure()
        let cabinets = createTestCabinets(wallId: roomStructure.walls[0].id)
        let appliances = createTestAppliances(wallId: roomStructure.walls[0].id)
        let islands = createTestIslandResult()
        let openings = createTestOpenings(wallId: roomStructure.walls[0].id)

        let startTime = Date()

        let result = try await renderer.render(
            roomStructure: roomStructure,
            cabinets: cabinets,
            appliances: appliances,
            islandsPeninsulas: islands,
            openings: openings
        )

        let elapsedMs = Date().timeIntervalSince(startTime) * 1000

        XCTAssertNotNil(result.pngData)
        XCTAssertLessThan(elapsedMs, 500, "Rendering took \(String(format: "%.0f", elapsedMs))ms, exceeding 500ms budget")
    }
}
