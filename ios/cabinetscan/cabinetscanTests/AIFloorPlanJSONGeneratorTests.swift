//
//  AIFloorPlanJSONGeneratorTests.swift
//  cabinetscanTests
//
//  Tests for Story 5.2: Floor Plan JSON Data Structure
//

import XCTest
import simd
@testable import cabinetscan

final class AIFloorPlanJSONGeneratorTests: XCTestCase {

    var sut: AIFloorPlanJSONGenerator!

    override func setUp() {
        super.setUp()
        sut = AIFloorPlanJSONGenerator()
    }

    override func tearDown() {
        sut = nil
        super.tearDown()
    }

    // MARK: - AC1: Schema Compatibility Tests

    /// AC1: JSON schema matches WEBHOOK_FORMAT.md with AI extensions
    func testGeneratedJSONContainsRequiredTopLevelFields() throws {
        // Given
        let pipelineResult = createMinimalPipelineResult()

        // When
        let json = try sut.generate(from: pipelineResult)

        // Then
        XCTAssertEqual(json.roomName, "Kitchen")
        XCTAssertEqual(json.roomType, "kitchen")
        XCTAssertNotNil(json.roomplanData)
        XCTAssertNotNil(json.measurements)
    }

    func testMeasurementsContainsRequiredFields() throws {
        // Given
        let pipelineResult = createMinimalPipelineResult()

        // When
        let json = try sut.generate(from: pipelineResult)
        let measurements = json.measurements

        // Then - Required per WEBHOOK_FORMAT.md
        XCTAssertNotNil(measurements.room)
        XCTAssertNotNil(measurements.walls)
        XCTAssertNotNil(measurements.doors)
        XCTAssertNotNil(measurements.windows)
        XCTAssertNotNil(measurements.cabinets)
        XCTAssertNotNil(measurements.appliances)
        XCTAssertNotNil(measurements.islands)
        XCTAssertNotNil(measurements.peninsulas)
        XCTAssertEqual(measurements.scanMethod, "aiFlow")
        XCTAssertNotNil(measurements.aiMetadata)
        XCTAssertNotNil(measurements.aiSummary)
    }

    func testAIExtensionFieldsArePrefixedWithAI() throws {
        // Given
        let pipelineResult = createPipelineResultWithAllDetections()

        // When
        let json = try sut.generate(from: pipelineResult)

        // Then - AI-specific fields prefixed with "ai_"
        // Check cabinet AI extensions
        if let firstCabinet = json.measurements.cabinets.lower.first {
            XCTAssertNotNil(firstCabinet.aiIsStandardSize)
            XCTAssertNotNil(firstCabinet.aiRawDimensions)
        }

        // Check metadata fields
        XCTAssertNotNil(json.measurements.aiMetadata.schemaVersion)
        XCTAssertNotNil(json.measurements.aiMetadata.overallConfidence)
        XCTAssertNotNil(json.measurements.aiMetadata.calibrationMethod)
    }

    // MARK: - AC2: Confidence Tests

    func testConfidenceAsStringOnObjects() throws {
        // Given
        let pipelineResult = createPipelineResultWithAllDetections()

        // When
        let json = try sut.generate(from: pipelineResult)

        // Then - Confidence as string enum
        XCTAssertTrue(["high", "medium", "low"].contains(json.measurements.room.confidence))

        if let firstCabinet = json.measurements.cabinets.lower.first {
            XCTAssertTrue(["high", "medium", "low"].contains(firstCabinet.confidence ?? ""))
        }
    }

    func testConfidenceAsNumericInMetadata() throws {
        // Given
        let pipelineResult = createPipelineResultWithAllDetections()

        // When
        let json = try sut.generate(from: pipelineResult)

        // Then - Numeric confidence in metadata
        XCTAssertGreaterThanOrEqual(json.measurements.aiMetadata.confidenceScore, 0.0)
        XCTAssertLessThanOrEqual(json.measurements.aiMetadata.confidenceScore, 1.0)
    }

    // MARK: - AC3: Unit Conversion Tests

    func testMeasurementsAreInFeet() throws {
        // Given
        let pipelineResult = createPipelineResultWithKnownDimensions()

        // When
        let json = try sut.generate(from: pipelineResult)

        // Then - Values should be in feet (inches / 12)
        // Room with 120" (10') x 144" (12') dimensions
        let room = json.measurements.room
        XCTAssertEqual(room.maxX - room.minX, 10.0, accuracy: 0.1) // 120 inches = 10 feet
        XCTAssertEqual(room.maxZ - room.minZ, 12.0, accuracy: 0.1) // 144 inches = 12 feet
    }

    func testFormattedDimensionStrings() throws {
        // Given
        let pipelineResult = createPipelineResultWithAllDetections()

        // When
        let json = try sut.generate(from: pipelineResult)

        // Then - Formatted strings like "3' 0\""
        if let firstCabinet = json.measurements.cabinets.lower.first {
            // 36" width = 3' 0"
            XCTAssertEqual(firstCabinet.widthInches, "3' 0\"")
        }
    }

    // MARK: - AC4: Islands and Peninsulas Tests

    func testIslandsAsTopLevelArray() throws {
        // Given
        let pipelineResult = createPipelineResultWithIsland()

        // When
        let json = try sut.generate(from: pipelineResult)

        // Then - Islands at top level (per ADR-003)
        XCTAssertEqual(json.measurements.islands.count, 1)
        let island = json.measurements.islands[0]
        XCTAssertEqual(island.id, "island_1")
        XCTAssertGreaterThan(island.countertopAreaSqft, 0)
    }

    func testPeninsulasAsTopLevelArray() throws {
        // Given
        let pipelineResult = createPipelineResultWithPeninsula()

        // When
        let json = try sut.generate(from: pipelineResult)

        // Then - Peninsulas at top level (per ADR-003)
        XCTAssertEqual(json.measurements.peninsulas.count, 1)
        let peninsula = json.measurements.peninsulas[0]
        XCTAssertEqual(peninsula.id, "peninsula_1")
        XCTAssertNotNil(peninsula.attachedWallId)
    }

    // MARK: - AC5: Schema Version Tests

    func testSchemaVersionInMetadata() throws {
        // Given
        let pipelineResult = createMinimalPipelineResult()

        // When
        let json = try sut.generate(from: pipelineResult)

        // Then - Schema version present (per ADR-005)
        XCTAssertEqual(json.measurements.aiMetadata.schemaVersion, "1.0")
    }

    // MARK: - AC6: Cabinet Types Tests

    func testLowerCabinetsUseCorrectNaming() throws {
        // Given - Create result with base cabinets
        let pipelineResult = createPipelineResultWithAllDetections()

        // When
        let json = try sut.generate(from: pipelineResult)

        // Then - Uses "lower" not "base" per LiDAR convention
        XCTAssertFalse(json.measurements.cabinets.lower.isEmpty)
        if let firstLower = json.measurements.cabinets.lower.first {
            XCTAssertEqual(firstLower.type, "lower_cabinet")
        }
    }

    // MARK: - AC7: Position Format Tests

    func testPositionsAreObjects() throws {
        // Given
        let pipelineResult = createPipelineResultWithAllDetections()

        // When
        let json = try sut.generate(from: pipelineResult)

        // Then - Positions as { "x": 0, "z": 0 } not arrays
        if let firstCabinet = json.measurements.cabinets.lower.first {
            XCTAssertNotNil(firstCabinet.position.x)
            XCTAssertNotNil(firstCabinet.position.z)
        }
    }

    // MARK: - AC8: Countertop Summary Tests

    func testCountertopSummaryIncludesAllAreas() throws {
        // Given
        let pipelineResult = createPipelineResultWithCountertops()

        // When
        let json = try sut.generate(from: pipelineResult)

        // Then
        guard let countertops = json.measurements.countertops else {
            XCTFail("Countertops should not be nil")
            return
        }

        XCTAssertGreaterThanOrEqual(countertops.summary.wallCountertopSqft, 0)
        XCTAssertGreaterThanOrEqual(countertops.summary.islandCountertopSqft, 0)
        XCTAssertGreaterThanOrEqual(countertops.summary.peninsulaCountertopSqft, 0)
        XCTAssertGreaterThanOrEqual(countertops.summary.netTotalSqft, 0)
    }

    // MARK: - AC9: Export Tests

    func testJSONExportProducesValidData() throws {
        // Given
        let pipelineResult = createMinimalPipelineResult()
        let json = try sut.generate(from: pipelineResult)

        // When
        let data = try sut.exportData(json)

        // Then - Valid JSON that can be decoded
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let decoded = try decoder.decode(FloorPlanJSON.self, from: data)
        XCTAssertEqual(decoded.roomType, "kitchen")
    }

    // MARK: - Error Handling Tests

    func testMissingRoomStructureThrowsError() {
        // Given - Create result with nil room structure
        let result = createPipelineResultWithoutRoomStructure()

        // When/Then
        XCTAssertThrowsError(try sut.generate(from: result)) { error in
            XCTAssertTrue(error is JSONGenerationError)
        }
    }

    // MARK: - Door/Window JSON Tests (Code Review Fix)

    func testDoorJSONContainsRequiredFields() throws {
        // Given
        let pipelineResult = createPipelineResultWithOpenings()

        // When
        let json = try sut.generate(from: pipelineResult)

        // Then
        XCTAssertEqual(json.measurements.doors.count, 1)
        let door = json.measurements.doors[0]
        XCTAssertEqual(door.id, "door_1")
        XCTAssertNotNil(door.position)
        XCTAssertGreaterThan(door.widthFt, 0)
        XCTAssertGreaterThan(door.heightFt, 0)
        XCTAssertFalse(door.widthInches.isEmpty)
        XCTAssertFalse(door.heightInches.isEmpty)
        XCTAssertNotNil(door.aiSwingDirection)  // AI extension
        XCTAssertNotNil(door.aiRawDimensions)  // AI extension
    }

    func testWindowJSONContainsRequiredFields() throws {
        // Given
        let pipelineResult = createPipelineResultWithOpenings()

        // When
        let json = try sut.generate(from: pipelineResult)

        // Then
        XCTAssertEqual(json.measurements.windows.count, 1)
        let window = json.measurements.windows[0]
        XCTAssertEqual(window.id, "window_1")
        XCTAssertNotNil(window.position)
        XCTAssertGreaterThan(window.widthFt, 0)
        XCTAssertGreaterThan(window.heightFt, 0)
        XCTAssertFalse(window.widthInches.isEmpty)
        XCTAssertFalse(window.heightInches.isEmpty)
        XCTAssertGreaterThan(window.areaSqft, 0)  // area_sqft required
        XCTAssertGreaterThan(window.aiSillHeightFt, 0)  // AI extension
    }

    // MARK: - Appliance JSON Tests (Code Review Fix)

    func testApplianceJSONContainsRequiredFields() throws {
        // Given
        let pipelineResult = createPipelineResultWithAppliances()

        // When
        let json = try sut.generate(from: pipelineResult)

        // Then
        XCTAssertEqual(json.measurements.appliances.count, 1)
        let appliance = json.measurements.appliances[0]
        XCTAssertEqual(appliance.id, "appliance_1")
        XCTAssertEqual(appliance.type, "refrigerator")
        XCTAssertNotNil(appliance.position)
        XCTAssertGreaterThan(appliance.widthFt, 0)
        XCTAssertGreaterThan(appliance.heightFt, 0)
        XCTAssertGreaterThan(appliance.depthFt, 0)
        XCTAssertFalse(appliance.widthInches.isEmpty)
    }

    // MARK: - Cabinet ID Sequencing Tests (Code Review Fix)

    func testCabinetIDsAreSequentialPerType() throws {
        // Given - Multiple cabinets of same type
        let pipelineResult = createPipelineResultWithMultipleCabinets()

        // When
        let json = try sut.generate(from: pipelineResult)

        // Then - IDs should be sequential within each type
        XCTAssertEqual(json.measurements.cabinets.lower.count, 2)
        XCTAssertEqual(json.measurements.cabinets.lower[0].id, "lower_1")
        XCTAssertEqual(json.measurements.cabinets.lower[1].id, "lower_2")

        XCTAssertEqual(json.measurements.cabinets.upper.count, 2)
        XCTAssertEqual(json.measurements.cabinets.upper[0].id, "upper_1")
        XCTAssertEqual(json.measurements.cabinets.upper[1].id, "upper_2")
    }

    // MARK: - Test Helpers

    private func createMinimalPipelineResult() -> AIPipelineResult {
        let roomStructure = createMinimalRoomStructure()
        let calibration = createMinimalCalibration()

        return AIPipelineResult(
            constrainedMesh: .empty,
            walls: [],
            corners: [],
            calibration: calibration,
            roomStructure: roomStructure,
            detectedCabinets: nil,
            detectedAppliances: nil,
            detectedIslandsPeninsulas: nil,
            detectedCountertops: nil,
            detectedOpenings: nil,
            extractedMeasurements: nil,
            confidenceScores: nil,
            processingTimeMs: 1000,
            frameCount: 60,
            photoCount: 5,
            fusionQuality: createMinimalFusionQuality(),
            constraintValidation: createMinimalConstraintValidation(),
            coverageQuality: .good,
            warnings: [],
            coveragePercentage: nil,
            uncapturedZones: nil,
            originalMesh: nil
        )
    }

    private func createPipelineResultWithoutRoomStructure() -> AIPipelineResult {
        let calibration = createMinimalCalibration()

        return AIPipelineResult(
            constrainedMesh: .empty,
            walls: [],
            corners: [],
            calibration: calibration,
            roomStructure: nil,
            detectedCabinets: nil,
            detectedAppliances: nil,
            detectedIslandsPeninsulas: nil,
            detectedCountertops: nil,
            detectedOpenings: nil,
            extractedMeasurements: nil,
            confidenceScores: nil,
            processingTimeMs: 1000,
            frameCount: 60,
            photoCount: 5,
            fusionQuality: createMinimalFusionQuality(),
            constraintValidation: createMinimalConstraintValidation(),
            coverageQuality: .good,
            warnings: [],
            coveragePercentage: nil,
            uncapturedZones: nil,
            originalMesh: nil
        )
    }

    private func createPipelineResultWithAllDetections() -> AIPipelineResult {
        let roomStructure = createMinimalRoomStructure()
        let calibration = createMinimalCalibration()
        let cabinetResult = createCabinetDetectionResult()

        return AIPipelineResult(
            constrainedMesh: .empty,
            walls: [],
            corners: [],
            calibration: calibration,
            roomStructure: roomStructure,
            detectedCabinets: cabinetResult,
            detectedAppliances: nil,
            detectedIslandsPeninsulas: nil,
            detectedCountertops: nil,
            detectedOpenings: nil,
            extractedMeasurements: nil,
            confidenceScores: nil,
            processingTimeMs: 1000,
            frameCount: 60,
            photoCount: 5,
            fusionQuality: createMinimalFusionQuality(),
            constraintValidation: createMinimalConstraintValidation(),
            coverageQuality: .good,
            warnings: [],
            coveragePercentage: nil,
            uncapturedZones: nil,
            originalMesh: nil
        )
    }

    private func createPipelineResultWithKnownDimensions() -> AIPipelineResult {
        // Create room with 120" x 144" dimensions (10' x 12')
        let walls = [
            createTestWall(
                start: SIMD2<Float>(0, 0),
                end: SIMD2<Float>(120, 0),
                length: 120,
                height: 96
            ),
            createTestWall(
                start: SIMD2<Float>(120, 0),
                end: SIMD2<Float>(120, 144),
                length: 144,
                height: 96
            ),
            createTestWall(
                start: SIMD2<Float>(120, 144),
                end: SIMD2<Float>(0, 144),
                length: 120,
                height: 96
            ),
            createTestWall(
                start: SIMD2<Float>(0, 144),
                end: SIMD2<Float>(0, 0),
                length: 144,
                height: 96
            )
        ]

        let boundaryPolygon: [SIMD2<Float>] = [
            SIMD2(0, 0),
            SIMD2(120, 0),
            SIMD2(120, 144),
            SIMD2(0, 144)
        ]

        let dimensions = RoomDimensions(
            widthInches: 120,
            lengthInches: 144,
            ceilingHeightInches: 96,
            areaSquareInches: 120 * 144,
            perimeterInches: 2 * 120 + 2 * 144
        )

        let roomStructure = AIRoomStructure(
            floorPlane: RoomPlane3D(
                normal: SIMD3<Float>(0, 1, 0),
                distance: 0,
                center: SIMD3<Float>(60, 0, 72)
            ),
            ceilingHeightInches: 96,
            walls: walls,
            boundaryPolygon: boundaryPolygon,
            roomShape: .rectangle,
            dimensions: dimensions,
            openBoundaries: [],
            confidence: DetectionConfidence(
                floorConfidence: 0.9,
                wallConfidence: 0.85,
                boundaryConfidence: 0.88
            ),
            processingTimeMs: 100,
            warnings: []
        )

        let calibration = createMinimalCalibration()

        return AIPipelineResult(
            constrainedMesh: .empty,
            walls: [],
            corners: [],
            calibration: calibration,
            roomStructure: roomStructure,
            detectedCabinets: nil,
            detectedAppliances: nil,
            detectedIslandsPeninsulas: nil,
            detectedCountertops: nil,
            detectedOpenings: nil,
            extractedMeasurements: nil,
            confidenceScores: nil,
            processingTimeMs: 1000,
            frameCount: 60,
            photoCount: 5,
            fusionQuality: createMinimalFusionQuality(),
            constraintValidation: createMinimalConstraintValidation(),
            coverageQuality: .good,
            warnings: [],
            coveragePercentage: nil,
            uncapturedZones: nil,
            originalMesh: nil
        )
    }

    private func createPipelineResultWithIsland() -> AIPipelineResult {
        let roomStructure = createMinimalRoomStructure()
        let calibration = createMinimalCalibration()

        let island = AIDetectedIsland(
            id: UUID(),
            boundingBox: AIBoundingBox3D(
                center: SIMD3<Float>(60, 18, 72),
                size: SIMD3<Float>(60, 36, 36)
            ),
            position: SIMD2<Float>(60, 72),
            lengthInches: 60,
            widthInches: 36,
            heightInches: 36,
            rotation: 0,
            hasSeating: true,
            seatingOverhangInches: 12,
            seatingLengthInches: 48,
            appliancesOnIsland: [],
            confidence: .high,
            isStandardSize: true,
            rawDimensions: SIMD3<Float>(60, 36, 36),
            notes: []
        )

        let islandResult = IslandPeninsulaDetectionResult(
            islands: [island],
            peninsulas: [],
            processingTimeMs: 100,
            warnings: []
        )

        return AIPipelineResult(
            constrainedMesh: .empty,
            walls: [],
            corners: [],
            calibration: calibration,
            roomStructure: roomStructure,
            detectedCabinets: nil,
            detectedAppliances: nil,
            detectedIslandsPeninsulas: islandResult,
            detectedCountertops: nil,
            detectedOpenings: nil,
            extractedMeasurements: nil,
            confidenceScores: nil,
            processingTimeMs: 1000,
            frameCount: 60,
            photoCount: 5,
            fusionQuality: createMinimalFusionQuality(),
            constraintValidation: createMinimalConstraintValidation(),
            coverageQuality: .good,
            warnings: [],
            coveragePercentage: nil,
            uncapturedZones: nil,
            originalMesh: nil
        )
    }

    private func createPipelineResultWithPeninsula() -> AIPipelineResult {
        let roomStructure = createMinimalRoomStructure()
        let calibration = createMinimalCalibration()
        let wallId = roomStructure.walls.first?.id ?? UUID()

        let peninsula = AIDetectedPeninsula(
            id: UUID(),
            boundingBox: AIBoundingBox3D(
                center: SIMD3<Float>(60, 18, 24),
                size: SIMD3<Float>(48, 36, 24)
            ),
            attachedWallId: wallId,
            attachmentPointInches: 36,
            lengthInches: 48,
            widthInches: 24,
            heightInches: 36,
            extendsDirection: .outward,
            hasSeating: false,
            seatingOverhangInches: nil,
            seatingOnSide: nil,
            appliancesOnPeninsula: [],
            confidence: .medium,
            isStandardSize: true,
            rawDimensions: SIMD3<Float>(48, 36, 24),
            notes: []
        )

        let peninsulaResult = IslandPeninsulaDetectionResult(
            islands: [],
            peninsulas: [peninsula],
            processingTimeMs: 100,
            warnings: []
        )

        return AIPipelineResult(
            constrainedMesh: .empty,
            walls: [],
            corners: [],
            calibration: calibration,
            roomStructure: roomStructure,
            detectedCabinets: nil,
            detectedAppliances: nil,
            detectedIslandsPeninsulas: peninsulaResult,
            detectedCountertops: nil,
            detectedOpenings: nil,
            extractedMeasurements: nil,
            confidenceScores: nil,
            processingTimeMs: 1000,
            frameCount: 60,
            photoCount: 5,
            fusionQuality: createMinimalFusionQuality(),
            constraintValidation: createMinimalConstraintValidation(),
            coverageQuality: .good,
            warnings: [],
            coveragePercentage: nil,
            uncapturedZones: nil,
            originalMesh: nil
        )
    }

    private func createPipelineResultWithCountertops() -> AIPipelineResult {
        let roomStructure = createMinimalRoomStructure()
        let calibration = createMinimalCalibration()
        let wallId = roomStructure.walls.first?.id ?? UUID()

        let wallCountertop = AIWallCountertop(
            id: UUID(),
            wallId: wallId,
            lengthInches: 60,
            depthInches: 25.5,
            startPositionInches: 0,
            endPositionInches: 60,
            heightFromFloorInches: 36,
            sections: [],
            cutouts: [],
            confidence: .high,
            rawDimensions: SIMD2<Float>(60, 25.5),
            isStandardDepth: true,
            notes: []
        )

        let countertopSummary = AICountertopSummary(
            wallCountertops: [wallCountertop],
            islandCountertops: [],
            peninsulaCountertops: [],
            wallTotalLinearInches: 60,
            wallGrossAreaSquareInches: 60 * 25.5,
            wallNetAreaSquareInches: 60 * 25.5,
            islandTotalSquareInches: 0,
            peninsulaTotalSquareInches: 0,
            backsplashLinearInches: 60,
            backsplashHeightInches: 18,
            exposedEdgeTotalInches: 60,
            cutoutCount: 0,
            allCutouts: []
        )

        let countertopResult = CountertopDetectorResult(
            wallCountertops: [wallCountertop],
            countertopSummary: countertopSummary,
            backsplashSummary: AIBacksplashSummary.empty,
            edgeTreatmentSummary: AIEdgeTreatmentSummary.empty,
            processingTimeMs: 100,
            warnings: [],
            overallConfidence: .high
        )

        return AIPipelineResult(
            constrainedMesh: .empty,
            walls: [],
            corners: [],
            calibration: calibration,
            roomStructure: roomStructure,
            detectedCabinets: nil,
            detectedAppliances: nil,
            detectedIslandsPeninsulas: nil,
            detectedCountertops: countertopResult,
            detectedOpenings: nil,
            extractedMeasurements: nil,
            confidenceScores: nil,
            processingTimeMs: 1000,
            frameCount: 60,
            photoCount: 5,
            fusionQuality: createMinimalFusionQuality(),
            constraintValidation: createMinimalConstraintValidation(),
            coverageQuality: .good,
            warnings: [],
            coveragePercentage: nil,
            uncapturedZones: nil,
            originalMesh: nil
        )
    }

    private func createMinimalRoomStructure() -> AIRoomStructure {
        let walls = [
            createTestWall(
                start: SIMD2<Float>(0, 0),
                end: SIMD2<Float>(120, 0),
                length: 120,
                height: 96
            )
        ]

        let boundaryPolygon: [SIMD2<Float>] = [
            SIMD2(0, 0),
            SIMD2(120, 0),
            SIMD2(120, 96),
            SIMD2(0, 96)
        ]

        let dimensions = RoomDimensions(
            widthInches: 120,
            lengthInches: 96,
            ceilingHeightInches: 96,
            areaSquareInches: 120 * 96,
            perimeterInches: 2 * 120 + 2 * 96
        )

        return AIRoomStructure(
            floorPlane: RoomPlane3D(
                normal: SIMD3<Float>(0, 1, 0),
                distance: 0,
                center: SIMD3<Float>(60, 0, 48)
            ),
            ceilingHeightInches: 96,
            walls: walls,
            boundaryPolygon: boundaryPolygon,
            roomShape: .rectangle,
            dimensions: dimensions,
            openBoundaries: [],
            confidence: DetectionConfidence(
                floorConfidence: 0.9,
                wallConfidence: 0.85,
                boundaryConfidence: 0.88
            ),
            processingTimeMs: 100,
            warnings: []
        )
    }

    private func createTestWall(
        start: SIMD2<Float>,
        end: SIMD2<Float>,
        length: Double,
        height: Double
    ) -> AIWall {
        // Calculate normal direction (perpendicular to wall direction)
        let direction = end - start
        let wallLength = simd_length(direction)
        let normalizedDir = direction / wallLength
        // Rotate 90 degrees for outward normal
        let normalDirection = SIMD2<Float>(-normalizedDir.y, normalizedDir.x)

        return AIWall(
            id: UUID(),
            plane: RoomPlane3D(
                normal: SIMD3<Float>(normalDirection.x, 0, normalDirection.y),
                distance: 0,
                center: SIMD3<Float>((start.x + end.x) / 2, Float(height) / 2, (start.y + end.y) / 2)
            ),
            startPoint: start,
            endPoint: end,
            lengthInches: length,
            heightInches: height,
            normalDirection: normalDirection,
            boundaryType: .wall
        )
    }

    private func createMinimalCalibration() -> ScaleCalibrationResult {
        return ScaleCalibrationResult(
            scaleFactor: 1.0,
            calibrationMethod: .autoCountertop,
            confidenceLevel: .high,
            countertopHeightInches: 36,
            ceilingHeightInches: 96,
            floorPlane: AIPlane(
                normal: SIMD3<Float>(0, 1, 0),
                distance: 0
            ),
            validationResults: CalibrationValidation(
                upperCabinetHeightValid: true,
                upperCabinetHeightInches: 54,
                ceilingHeightValid: true,
                ceilingHeightInches: 96
            ),
            processingTimeMs: 100
        )
    }

    private func createMinimalFusionQuality() -> TSDFQualityMetrics {
        return TSDFQualityMetrics(
            coveragePercentage: 35.0,
            averageVoxelWeight: 5.0,
            totalVoxelCount: 10000,
            isMeshManifold: true
        )
    }

    private func createMinimalConstraintValidation() -> ConstraintValidation {
        return ConstraintValidation(
            perimeterConsistent: true,
            areaConsistent: true,
            maxWallChangeInches: 0.5,
            wallsExceedingThreshold: []
        )
    }

    private func createCabinetDetectionResult() -> CabinetDetectionResult {
        let wallId = UUID()
        let cabinet = AIDetectedCabinet(
            boundingBox: AIBoundingBox3D(
                center: SIMD3<Float>(18, 17.5, 12),
                size: SIMD3<Float>(36, 35, 24)
            ),
            type: .base,
            wallId: wallId,
            positionOnWallInches: 0,
            rawDimensions: SIMD3<Float>(36, 35, 24),
            snappedDimensions: SIMD3<Float>(36, 35, 24),
            confidence: .high,
            isStandardSize: true,
            cornerType: nil,
            specialType: nil,
            notes: []
        )

        let wallCoverage = WallCoverageValidation(
            wallId: wallId,
            wallLengthInches: 120,
            baseCabinetTotalInches: 36,
            upperCabinetTotalInches: 0,
            baseGaps: [],
            upperGaps: []
        )

        return CabinetDetectionResult(
            cabinets: [cabinet],
            wallCoverageValidation: [wallCoverage],
            processingTimeMs: 100,
            warnings: []
        )
    }

    // MARK: - Code Review Fix Helpers

    private func createPipelineResultWithOpenings() -> AIPipelineResult {
        let roomStructure = createMinimalRoomStructure()
        let calibration = createMinimalCalibration()
        let wallId = roomStructure.walls.first?.id ?? UUID()

        let door = AIDetectedDoor(
            id: UUID(),
            type: .door,
            wallId: wallId,
            positionOnWallInches: 36,
            heightFromFloorInches: 0,
            boundingBox: AIBoundingBox3D(
                center: SIMD3<Float>(36, 40, 0),
                size: SIMD3<Float>(36, 80, 4)
            ),
            rawDimensions: SIMD3<Float>(35, 79, 4),
            snappedDimensions: SIMD3<Float>(36, 80, 4),
            confidence: .high,
            isStandardSize: true,
            notes: [],
            swingDirection: .left,
            isFullHeight: true,
            clearanceToAdjacentCabinet: 3
        )

        let window = AIDetectedWindow(
            id: UUID(),
            wallId: wallId,
            positionOnWallInches: 72,
            heightFromFloorInches: 42,
            boundingBox: AIBoundingBox3D(
                center: SIMD3<Float>(72, 60, 0),
                size: SIMD3<Float>(36, 36, 4)
            ),
            rawDimensions: SIMD3<Float>(35, 35, 4),
            snappedDimensions: SIMD3<Float>(36, 36, 4),
            confidence: .high,
            isStandardSize: true,
            notes: [],
            sillHeightInches: 42,
            distanceFromCountertopInches: 6,
            hasFrame: true,
            availableUpperCabinetHeight: 18,
            upperCabinetRecommendation: nil
        )

        let openingResult = OpeningDetectionResult(
            windows: [window],
            doors: [door],
            clearances: [],
            processingTimeMs: 50,
            warnings: []
        )

        return AIPipelineResult(
            constrainedMesh: .empty,
            walls: [],
            corners: [],
            calibration: calibration,
            roomStructure: roomStructure,
            detectedCabinets: nil,
            detectedAppliances: nil,
            detectedIslandsPeninsulas: nil,
            detectedCountertops: nil,
            detectedOpenings: openingResult,
            extractedMeasurements: nil,
            confidenceScores: nil,
            processingTimeMs: 1000,
            frameCount: 60,
            photoCount: 5,
            fusionQuality: createMinimalFusionQuality(),
            constraintValidation: createMinimalConstraintValidation(),
            coverageQuality: .good,
            warnings: [],
            coveragePercentage: nil,
            uncapturedZones: nil,
            originalMesh: nil
        )
    }

    private func createPipelineResultWithAppliances() -> AIPipelineResult {
        let roomStructure = createMinimalRoomStructure()
        let calibration = createMinimalCalibration()
        let wallId = roomStructure.walls.first?.id ?? UUID()

        let appliance = AIDetectedAppliance(
            boundingBox: AIBoundingBox3D(
                center: SIMD3<Float>(90, 36, 12),
                size: SIMD3<Float>(36, 72, 30)
            ),
            type: .refrigerator,
            subType: .fridgeFrenchDoor,
            rawDimensions: SIMD3<Float>(35, 71, 29),
            snappedDimensions: SIMD3<Float>(36, 72, 30),
            position: SIMD2<Float>(90, 12),
            wallId: wallId,
            positionOnWallInches: 72,
            confidence: .high,
            isStandardSize: true
        )

        let applianceResult = ApplianceDetectionResult(
            appliances: [appliance],
            processingTimeMs: 50,
            warnings: []
        )

        return AIPipelineResult(
            constrainedMesh: .empty,
            walls: [],
            corners: [],
            calibration: calibration,
            roomStructure: roomStructure,
            detectedCabinets: nil,
            detectedAppliances: applianceResult,
            detectedIslandsPeninsulas: nil,
            detectedCountertops: nil,
            detectedOpenings: nil,
            extractedMeasurements: nil,
            confidenceScores: nil,
            processingTimeMs: 1000,
            frameCount: 60,
            photoCount: 5,
            fusionQuality: createMinimalFusionQuality(),
            constraintValidation: createMinimalConstraintValidation(),
            coverageQuality: .good,
            warnings: [],
            coveragePercentage: nil,
            uncapturedZones: nil,
            originalMesh: nil
        )
    }

    private func createPipelineResultWithMultipleCabinets() -> AIPipelineResult {
        let roomStructure = createMinimalRoomStructure()
        let calibration = createMinimalCalibration()
        let wallId = roomStructure.walls.first?.id ?? UUID()

        // Create multiple base cabinets
        let baseCabinet1 = AIDetectedCabinet(
            boundingBox: AIBoundingBox3D(
                center: SIMD3<Float>(18, 17.5, 12),
                size: SIMD3<Float>(36, 35, 24)
            ),
            type: .base,
            wallId: wallId,
            positionOnWallInches: 0,
            rawDimensions: SIMD3<Float>(36, 35, 24),
            snappedDimensions: SIMD3<Float>(36, 35, 24),
            confidence: .high,
            isStandardSize: true
        )

        let baseCabinet2 = AIDetectedCabinet(
            boundingBox: AIBoundingBox3D(
                center: SIMD3<Float>(54, 17.5, 12),
                size: SIMD3<Float>(36, 35, 24)
            ),
            type: .base,
            wallId: wallId,
            positionOnWallInches: 36,
            rawDimensions: SIMD3<Float>(36, 35, 24),
            snappedDimensions: SIMD3<Float>(36, 35, 24),
            confidence: .high,
            isStandardSize: true
        )

        // Create multiple upper cabinets
        let upperCabinet1 = AIDetectedCabinet(
            boundingBox: AIBoundingBox3D(
                center: SIMD3<Float>(18, 66, 6),
                size: SIMD3<Float>(36, 30, 12)
            ),
            type: .upper,
            wallId: wallId,
            positionOnWallInches: 0,
            rawDimensions: SIMD3<Float>(36, 30, 12),
            snappedDimensions: SIMD3<Float>(36, 30, 12),
            confidence: .high,
            isStandardSize: true
        )

        let upperCabinet2 = AIDetectedCabinet(
            boundingBox: AIBoundingBox3D(
                center: SIMD3<Float>(54, 66, 6),
                size: SIMD3<Float>(36, 30, 12)
            ),
            type: .upper,
            wallId: wallId,
            positionOnWallInches: 36,
            rawDimensions: SIMD3<Float>(36, 30, 12),
            snappedDimensions: SIMD3<Float>(36, 30, 12),
            confidence: .high,
            isStandardSize: true
        )

        let cabinetResult = CabinetDetectionResult(
            cabinets: [baseCabinet1, upperCabinet1, baseCabinet2, upperCabinet2],  // Interleaved to test sequencing
            wallCoverageValidation: [],
            processingTimeMs: 100,
            warnings: []
        )

        return AIPipelineResult(
            constrainedMesh: .empty,
            walls: [],
            corners: [],
            calibration: calibration,
            roomStructure: roomStructure,
            detectedCabinets: cabinetResult,
            detectedAppliances: nil,
            detectedIslandsPeninsulas: nil,
            detectedCountertops: nil,
            detectedOpenings: nil,
            extractedMeasurements: nil,
            confidenceScores: nil,
            processingTimeMs: 1000,
            frameCount: 60,
            photoCount: 5,
            fusionQuality: createMinimalFusionQuality(),
            constraintValidation: createMinimalConstraintValidation(),
            coverageQuality: .good,
            warnings: [],
            coveragePercentage: nil,
            uncapturedZones: nil,
            originalMesh: nil
        )
    }
}
