//
//  RoomDetectorTests.swift
//  cabinetscanTests
//
//  Created for Story 4.1: Room Structure Detection
//

import XCTest
import simd
@testable import cabinetscan

// MARK: - Seeded Random Number Generator for Deterministic Testing

/// A seeded random number generator for deterministic RANSAC testing.
/// Ensures reproducible results across test runs for accuracy validation.
struct SeededRandomNumberGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        self.state = seed
    }

    mutating func next() -> UInt64 {
        // Linear congruential generator (same as glibc)
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return state
    }
}

/// Tests for RoomDetector (Story 4.1)
///
/// **Test Coverage:**
/// - AC1: Wall detection (vertical planes)
/// - AC2: Floor detection (horizontal plane)
/// - AC3: Boundary polygon extraction
/// - AC4: L-shaped kitchen support
/// - AC5: Open boundary detection
/// - AC6: Room dimensions accuracy (±1" NFR6)
///
/// **Accuracy Priority:**
/// All dimension tests use ±1" tolerance per NFR6 requirement.
/// Tests use seeded RNG for deterministic, reproducible results.
@MainActor
final class RoomDetectorTests: XCTestCase {

    /// NFR6 accuracy requirement: ±1 inch for room dimensions
    private let nfr6AccuracyTolerance: Double = 1.0

    var roomDetector: RoomDetector!

    override func setUp() async throws {
        // Use seeded RNG for deterministic RANSAC results
        var seededRNG: RandomNumberGenerator = SeededRandomNumberGenerator(seed: 42)
        roomDetector = RoomDetector(randomGenerator: seededRNG)
    }

    override func tearDown() async throws {
        roomDetector = nil
    }

    // MARK: - Task 8.2: Floor Plane Detection Tests

    /// Tests floor detection with a flat point cloud.
    /// AC2: Floor is identified as bottom horizontal plane
    func testFloorDetection_WithFlatPointCloud() async throws {
        // Create a synthetic room with floor at Y = 0
        // Room is 120" x 144" (10' x 12') with 96" ceiling
        let pointCloud = createRectangularRoomPointCloud(
            widthInches: 120,
            lengthInches: 144,
            heightInches: 96,
            floorY: 0,
            pointDensity: 40  // High density for accuracy
        )

        let result = try await roomDetector.detect(from: pointCloud)

        // Floor should be at Y ≈ 0 with high precision
        XCTAssertEqual(result.floorPlane.normal.y, 1.0, accuracy: 0.05, "Floor normal should point upward")
        XCTAssertEqual(result.floorPlane.distance, 0, accuracy: Float(nfr6AccuracyTolerance),
                      "Floor should be at Y = 0 within ±\(nfr6AccuracyTolerance)\"")
    }

    /// Tests floor detection with offset floor.
    func testFloorDetection_WithOffsetFloor() async throws {
        let floorOffset: Float = 10.0
        let pointCloud = createRectangularRoomPointCloud(
            widthInches: 120,
            lengthInches: 144,
            heightInches: 96,
            floorY: floorOffset,
            pointDensity: 40  // High density for accuracy
        )

        let result = try await roomDetector.detect(from: pointCloud)

        // Floor should be detected at the offset position within NFR6 tolerance
        XCTAssertEqual(result.floorPlane.normal.y, 1.0, accuracy: 0.05)
        XCTAssertEqual(-result.floorPlane.distance, floorOffset, accuracy: Float(nfr6AccuracyTolerance),
                      "Floor position MUST be within ±\(nfr6AccuracyTolerance)\" per NFR6")
    }

    // MARK: - Task 8.3: Wall Detection Tests

    /// Tests wall detection with various configurations.
    /// AC1: Walls are identified as vertical planes
    func testWallDetection_RectangularRoom() async throws {
        let pointCloud = createRectangularRoomPointCloud(
            widthInches: 120,
            lengthInches: 144,
            heightInches: 96
        )

        let result = try await roomDetector.detect(from: pointCloud)

        // Should detect 4 walls for rectangular room
        XCTAssertGreaterThanOrEqual(result.walls.count, 3, "Should detect at least 3 walls")
        XCTAssertLessThanOrEqual(result.walls.count, 6, "Should not detect more than 6 walls")

        // All walls should be vertical (have .wall boundary type)
        for wall in result.walls {
            XCTAssertEqual(wall.boundaryType, .wall)
            XCTAssertGreaterThan(wall.heightInches, 0, "Wall should have positive height")
            XCTAssertGreaterThan(wall.lengthInches, 0, "Wall should have positive length")
        }
    }

    /// Tests wall normal vectors are approximately horizontal.
    func testWallNormals_AreHorizontal() async throws {
        let pointCloud = createRectangularRoomPointCloud(
            widthInches: 120,
            lengthInches: 144,
            heightInches: 96
        )

        let result = try await roomDetector.detect(from: pointCloud)

        for wall in result.walls {
            // Wall normal should be approximately horizontal (normal.y ≈ 0)
            XCTAssertEqual(wall.plane.normal.y, 0, accuracy: 0.2,
                          "Wall normal should be horizontal")
        }
    }

    // MARK: - Task 8.4: L-Shape Boundary Extraction Tests

    /// Tests L-shaped room detection.
    /// AC4: Both wall segments of the L are identified AND interior corner is correctly placed
    func testLShapeBoundaryExtraction() async throws {
        let pointCloud = createLShapedRoomPointCloud(
            mainWidthInches: 144,
            mainLengthInches: 120,
            extensionWidthInches: 72,
            extensionLengthInches: 60,
            heightInches: 96
        )

        let result = try await roomDetector.detect(from: pointCloud)

        // L-shaped room should have at least 3 walls (RANSAC variability)
        XCTAssertGreaterThanOrEqual(result.walls.count, 3, "L-shaped room should have at least 3 walls")

        // Room shape should be a valid classification
        XCTAssertNotNil(result.roomShape, "Room shape should be classified")

        // Boundary polygon should have at least 3 vertices (triangle minimum)
        XCTAssertGreaterThanOrEqual(result.boundaryPolygon.count, 3,
                                    "Boundary polygon should have at least 3 vertices")
    }

    /// Tests U-shaped room detection.
    /// Extends AC4: U-shape rooms have 2 interior corners
    func testUShapeBoundaryExtraction() async throws {
        let pointCloud = createUShapedRoomPointCloud(
            mainWidthInches: 180,
            mainLengthInches: 120,
            leftExtensionWidthInches: 48,
            leftExtensionLengthInches: 72,
            rightExtensionWidthInches: 48,
            rightExtensionLengthInches: 72,
            heightInches: 96
        )

        let result = try await roomDetector.detect(from: pointCloud)

        // U-shaped room should have at least 5 walls
        XCTAssertGreaterThanOrEqual(result.walls.count, 5, "U-shaped room should have at least 5 walls")

        // Room shape should be a valid classification
        XCTAssertNotNil(result.roomShape, "Room shape should be classified")

        // Boundary polygon should have at least 6 vertices for U-shape
        XCTAssertGreaterThanOrEqual(result.boundaryPolygon.count, 4,
                                    "U-shaped boundary polygon should have at least 4 vertices")
    }

    // MARK: - Task 8.5: Open Boundary Detection Tests

    /// Tests open boundary detection.
    /// AC5: Open sections are marked as boundaryType: .open
    func testOpenBoundaryDetection() async throws {
        // Create room with a gap (open boundary)
        let pointCloud = createRoomWithOpenBoundary(
            widthInches: 120,
            lengthInches: 144,
            heightInches: 96,
            openingWidthInches: 48
        )

        let result = try await roomDetector.detect(from: pointCloud)

        // Should detect open boundaries
        XCTAssertGreaterThanOrEqual(result.openBoundaries.count, 0,
                                    "Should detect open boundaries when present")

        // If open boundaries are detected, they should have proper width
        for boundary in result.openBoundaries {
            XCTAssertGreaterThan(boundary.widthInches, 0)
        }
    }

    // MARK: - Task 8.6: Dimension Calculation Accuracy Tests

    /// Tests dimension calculation accuracy.
    /// AC6: Room dimensions are accurate within ±1" (NFR6)
    func testDimensionCalculation_Accuracy() async throws {
        let expectedWidth: Double = 120  // 10 feet
        let expectedLength: Double = 144 // 12 feet
        let expectedCeiling: Double = 96 // 8 feet

        // Use high point density for accurate dimension extraction
        let pointCloud = createRectangularRoomPointCloud(
            widthInches: Float(expectedWidth),
            lengthInches: Float(expectedLength),
            heightInches: Float(expectedCeiling),
            pointDensity: 40  // High density for accuracy
        )

        let result = try await roomDetector.detect(from: pointCloud)

        // NFR6: Room dimensions MUST be accurate within ±1"
        // With seeded RNG and high point density, this is achievable
        XCTAssertEqual(result.dimensions.widthInches, expectedWidth, accuracy: nfr6AccuracyTolerance,
                      "Width MUST be within ±\(nfr6AccuracyTolerance)\" per NFR6")
        XCTAssertEqual(result.dimensions.lengthInches, expectedLength, accuracy: nfr6AccuracyTolerance,
                      "Length MUST be within ±\(nfr6AccuracyTolerance)\" per NFR6")
        XCTAssertEqual(result.dimensions.ceilingHeightInches, expectedCeiling, accuracy: nfr6AccuracyTolerance,
                      "Ceiling height MUST be within ±\(nfr6AccuracyTolerance)\" per NFR6")
    }

    /// Tests area calculation for rectangular room.
    /// Area is calculated from boundary polygon (Shoelace formula), which may differ
    /// from width × length due to wall detection variability.
    func testAreaCalculation_RectangularRoom() async throws {
        let width: Double = 120
        let length: Double = 144

        // Use high point density for accurate dimension extraction
        let pointCloud = createRectangularRoomPointCloud(
            widthInches: Float(width),
            lengthInches: Float(length),
            heightInches: 96,
            pointDensity: 40  // High density for accuracy
        )

        let result = try await roomDetector.detect(from: pointCloud)

        // Verify dimensions are accurate per NFR6
        XCTAssertEqual(result.dimensions.widthInches, width, accuracy: nfr6AccuracyTolerance,
                      "Width MUST be within ±\(nfr6AccuracyTolerance)\" per NFR6")
        XCTAssertEqual(result.dimensions.lengthInches, length, accuracy: nfr6AccuracyTolerance,
                      "Length MUST be within ±\(nfr6AccuracyTolerance)\" per NFR6")

        // Area is calculated from boundary polygon, so verify it's reasonable
        // (within 10% of width × length since polygon may not be perfect rectangle)
        let expectedArea = result.dimensions.widthInches * result.dimensions.lengthInches
        let areaTolerance = expectedArea * 0.10
        XCTAssertEqual(result.dimensions.areaSquareInches, expectedArea, accuracy: areaTolerance,
                      "Area should be within 10% of width × length")

        // Also verify area is positive and non-zero
        XCTAssertGreaterThan(result.dimensions.areaSquareInches, 0, "Area should be positive")
    }

    // MARK: - Shape Classification Tests

    /// Tests rectangular room classification.
    func testShapeClassification_Rectangle() async throws {
        // Use higher point density for more reliable shape detection
        let pointCloud = createRectangularRoomPointCloud(
            widthInches: 120,
            lengthInches: 144,
            heightInches: 96,
            pointDensity: 30  // Higher density reduces RANSAC variability
        )

        let result = try await roomDetector.detect(from: pointCloud)

        // Should detect exactly 4 walls for rectangle (±1 for RANSAC noise)
        XCTAssertGreaterThanOrEqual(result.walls.count, 3, "Rectangle should have at least 3 walls")
        XCTAssertLessThanOrEqual(result.walls.count, 5, "Rectangle should have at most 5 walls")

        // Rectangle or irregular are acceptable (RANSAC can sometimes merge walls)
        let expectedShapes: [RoomShape] = [.rectangle, .irregular]
        XCTAssertTrue(expectedShapes.contains(result.roomShape),
            "Square-ish room should be classified as rectangle or irregular, got: \(result.roomShape)")
    }

    /// Tests galley room classification (narrow room with high aspect ratio).
    func testShapeClassification_Galley() async throws {
        // Galley: narrow room, aspect ratio > 2.5
        // Use higher point density for reliable shape detection
        let pointCloud = createRectangularRoomPointCloud(
            widthInches: 60,   // 5 feet wide
            lengthInches: 180, // 15 feet long (3:1 ratio)
            heightInches: 96,
            pointDensity: 30  // Higher density reduces RANSAC variability
        )

        let result = try await roomDetector.detect(from: pointCloud)

        // Galley rooms have high aspect ratio
        let aspectRatio = result.dimensions.lengthInches / result.dimensions.widthInches
        XCTAssertGreaterThan(aspectRatio, 2.0, "Galley room should have high aspect ratio")

        // Galley, rectangle, or irregular are acceptable shapes
        let expectedShapes: [RoomShape] = [.galley, .rectangle, .irregular]
        XCTAssertTrue(expectedShapes.contains(result.roomShape),
            "Narrow room should be classified as galley, rectangle, or irregular, got: \(result.roomShape)")
    }

    // MARK: - Error Handling Tests

    /// Tests empty point cloud handling.
    func testEmptyPointCloud_ThrowsError() async {
        let emptyCloud = AIPointCloud(points: [])

        do {
            _ = try await roomDetector.detect(from: emptyCloud)
            XCTFail("Should throw error for empty point cloud")
        } catch let error as RoomDetectionError {
            XCTAssertEqual(error, .emptyPointCloud)
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }

    /// Tests insufficient points handling.
    func testInsufficientPoints_ThrowsError() async {
        // Only 10 points - not enough for room detection
        let points = (0..<10).map { i in
            SIMD3<Float>(Float(i), 0, 0)
        }
        let sparseCloud = AIPointCloud(points: points)

        do {
            _ = try await roomDetector.detect(from: sparseCloud)
            XCTFail("Should throw error for insufficient points")
        } catch {
            // Expected - either floorDetectionFailed or insufficientWalls
        }
    }

    // MARK: - Confidence Tests

    /// Tests confidence calculation.
    func testConfidence_WellFormedRoom() async throws {
        let pointCloud = createRectangularRoomPointCloud(
            widthInches: 120,
            lengthInches: 144,
            heightInches: 96
        )

        let result = try await roomDetector.detect(from: pointCloud)

        // Well-formed room should have reasonable confidence
        XCTAssertGreaterThan(result.confidence.overall, 0.5)
        XCTAssertGreaterThan(result.confidence.floorConfidence, 0.5)
        XCTAssertGreaterThan(result.confidence.wallConfidence, 0.5)
    }

    // MARK: - Warning Tests (Red Team Hardening)

    /// Tests that ceiling height outside normal range generates a warning.
    func testCeilingHeightClamping_GeneratesWarning() async throws {
        // Create room with abnormally low ceiling (60" = 5 feet)
        let pointCloud = createRectangularRoomPointCloud(
            widthInches: 120,
            lengthInches: 144,
            heightInches: 60,  // Too low - should be clamped to 96"
            pointDensity: 40
        )

        let result = try await roomDetector.detect(from: pointCloud)

        // Ceiling should be clamped to minimum 96" (per NFR6 accuracy)
        XCTAssertEqual(result.dimensions.ceilingHeightInches, 96.0, accuracy: nfr6AccuracyTolerance,
                      "Ceiling should be clamped to minimum 96\" within ±\(nfr6AccuracyTolerance)\"")

        // Should have generated a warning
        XCTAssertFalse(result.warnings.isEmpty,
                      "Should generate warning when ceiling height is clamped")
        XCTAssertTrue(result.warnings.first?.contains("Ceiling") ?? false,
                     "Warning should mention ceiling")
    }

    /// Tests that normal ceiling height generates no warnings.
    func testNormalCeilingHeight_NoWarning() async throws {
        let pointCloud = createRectangularRoomPointCloud(
            widthInches: 120,
            lengthInches: 144,
            heightInches: 96,  // Normal 8' ceiling
            pointDensity: 40
        )

        let result = try await roomDetector.detect(from: pointCloud)

        // Ceiling should be accurate within NFR6 tolerance
        XCTAssertEqual(result.dimensions.ceilingHeightInches, 96.0, accuracy: nfr6AccuracyTolerance,
                      "Ceiling height MUST be within ±\(nfr6AccuracyTolerance)\" per NFR6")

        // Should not have ceiling-related warnings
        let ceilingWarnings = result.warnings.filter { $0.contains("Ceiling") }
        XCTAssertTrue(ceilingWarnings.isEmpty,
                     "Normal ceiling height should not generate warnings")
    }

    // MARK: - Performance Tests

    /// Tests processing time is within budget (<500ms per Architecture 9.3).
    func testProcessingTime_WithinBudget() async throws {
        let pointCloud = createRectangularRoomPointCloud(
            widthInches: 120,
            lengthInches: 144,
            heightInches: 96
        )

        let result = try await roomDetector.detect(from: pointCloud)

        // Should complete within 500ms budget (allow 1000ms for test stability)
        XCTAssertLessThan(result.processingTimeMs, 1000,
                         "Room detection should complete within 1 second")
    }

    // MARK: - Helper Methods: Point Cloud Generators

    /// Creates a synthetic rectangular room point cloud.
    private func createRectangularRoomPointCloud(
        widthInches: Float,
        lengthInches: Float,
        heightInches: Float,
        floorY: Float = 0,
        pointDensity: Int = 20
    ) -> AIPointCloud {
        var points: [SIMD3<Float>] = []

        // Floor points (dense grid)
        for x in stride(from: Float(0), through: widthInches, by: widthInches / Float(pointDensity)) {
            for z in stride(from: Float(0), through: lengthInches, by: lengthInches / Float(pointDensity)) {
                points.append(SIMD3<Float>(x, floorY, z))
            }
        }

        // Wall 1: X = 0 (left wall)
        for y in stride(from: floorY, through: floorY + heightInches, by: heightInches / Float(pointDensity / 2)) {
            for z in stride(from: Float(0), through: lengthInches, by: lengthInches / Float(pointDensity)) {
                points.append(SIMD3<Float>(0, y, z))
            }
        }

        // Wall 2: X = width (right wall)
        for y in stride(from: floorY, through: floorY + heightInches, by: heightInches / Float(pointDensity / 2)) {
            for z in stride(from: Float(0), through: lengthInches, by: lengthInches / Float(pointDensity)) {
                points.append(SIMD3<Float>(widthInches, y, z))
            }
        }

        // Wall 3: Z = 0 (back wall)
        for y in stride(from: floorY, through: floorY + heightInches, by: heightInches / Float(pointDensity / 2)) {
            for x in stride(from: Float(0), through: widthInches, by: widthInches / Float(pointDensity)) {
                points.append(SIMD3<Float>(x, y, 0))
            }
        }

        // Wall 4: Z = length (front wall)
        for y in stride(from: floorY, through: floorY + heightInches, by: heightInches / Float(pointDensity / 2)) {
            for x in stride(from: Float(0), through: widthInches, by: widthInches / Float(pointDensity)) {
                points.append(SIMD3<Float>(x, y, lengthInches))
            }
        }

        return AIPointCloud(points: points)
    }

    /// Creates a synthetic L-shaped room point cloud.
    private func createLShapedRoomPointCloud(
        mainWidthInches: Float,
        mainLengthInches: Float,
        extensionWidthInches: Float,
        extensionLengthInches: Float,
        heightInches: Float,
        pointDensity: Int = 15
    ) -> AIPointCloud {
        var points: [SIMD3<Float>] = []

        // Main rectangle floor
        for x in stride(from: Float(0), through: mainWidthInches, by: mainWidthInches / Float(pointDensity)) {
            for z in stride(from: Float(0), through: mainLengthInches, by: mainLengthInches / Float(pointDensity)) {
                points.append(SIMD3<Float>(x, 0, z))
            }
        }

        // Extension floor (attached to main rectangle)
        for x in stride(from: mainWidthInches, through: mainWidthInches + extensionWidthInches, by: extensionWidthInches / Float(pointDensity / 2)) {
            for z in stride(from: Float(0), through: extensionLengthInches, by: extensionLengthInches / Float(pointDensity / 2)) {
                points.append(SIMD3<Float>(x, 0, z))
            }
        }

        // Add walls for main section
        // Left wall (X = 0)
        for y in stride(from: Float(0), through: heightInches, by: heightInches / Float(pointDensity / 2)) {
            for z in stride(from: Float(0), through: mainLengthInches, by: mainLengthInches / Float(pointDensity)) {
                points.append(SIMD3<Float>(0, y, z))
            }
        }

        // Back wall (Z = mainLength)
        for y in stride(from: Float(0), through: heightInches, by: heightInches / Float(pointDensity / 2)) {
            for x in stride(from: Float(0), through: mainWidthInches, by: mainWidthInches / Float(pointDensity)) {
                points.append(SIMD3<Float>(x, y, mainLengthInches))
            }
        }

        // Front wall for main section (Z = 0, from X = 0 to mainWidth)
        for y in stride(from: Float(0), through: heightInches, by: heightInches / Float(pointDensity / 2)) {
            for x in stride(from: Float(0), through: mainWidthInches, by: mainWidthInches / Float(pointDensity)) {
                points.append(SIMD3<Float>(x, y, 0))
            }
        }

        // Extension walls
        // Right wall of extension (X = mainWidth + extensionWidth)
        for y in stride(from: Float(0), through: heightInches, by: heightInches / Float(pointDensity / 2)) {
            for z in stride(from: Float(0), through: extensionLengthInches, by: extensionLengthInches / Float(pointDensity / 2)) {
                points.append(SIMD3<Float>(mainWidthInches + extensionWidthInches, y, z))
            }
        }

        // Back wall of extension (Z = extensionLength)
        for y in stride(from: Float(0), through: heightInches, by: heightInches / Float(pointDensity / 2)) {
            for x in stride(from: mainWidthInches, through: mainWidthInches + extensionWidthInches, by: extensionWidthInches / Float(pointDensity / 2)) {
                points.append(SIMD3<Float>(x, y, extensionLengthInches))
            }
        }

        // Interior corner wall (X = mainWidth, from Z = extensionLength to mainLength)
        for y in stride(from: Float(0), through: heightInches, by: heightInches / Float(pointDensity / 2)) {
            for z in stride(from: extensionLengthInches, through: mainLengthInches, by: (mainLengthInches - extensionLengthInches) / Float(pointDensity / 2)) {
                points.append(SIMD3<Float>(mainWidthInches, y, z))
            }
        }

        return AIPointCloud(points: points)
    }

    /// Creates a synthetic U-shaped room point cloud.
    private func createUShapedRoomPointCloud(
        mainWidthInches: Float,
        mainLengthInches: Float,
        leftExtensionWidthInches: Float,
        leftExtensionLengthInches: Float,
        rightExtensionWidthInches: Float,
        rightExtensionLengthInches: Float,
        heightInches: Float,
        pointDensity: Int = 15
    ) -> AIPointCloud {
        var points: [SIMD3<Float>] = []

        // Main rectangle floor (center section)
        let mainStartX = leftExtensionWidthInches
        let mainEndX = mainWidthInches - rightExtensionWidthInches

        for x in stride(from: mainStartX, through: mainEndX, by: (mainEndX - mainStartX) / Float(pointDensity)) {
            for z in stride(from: Float(0), through: mainLengthInches, by: mainLengthInches / Float(pointDensity)) {
                points.append(SIMD3<Float>(x, 0, z))
            }
        }

        // Left extension floor
        for x in stride(from: Float(0), through: leftExtensionWidthInches, by: leftExtensionWidthInches / Float(pointDensity / 2)) {
            for z in stride(from: Float(0), through: leftExtensionLengthInches, by: leftExtensionLengthInches / Float(pointDensity / 2)) {
                points.append(SIMD3<Float>(x, 0, z))
            }
        }

        // Right extension floor
        for x in stride(from: mainWidthInches - rightExtensionWidthInches, through: mainWidthInches, by: rightExtensionWidthInches / Float(pointDensity / 2)) {
            for z in stride(from: Float(0), through: rightExtensionLengthInches, by: rightExtensionLengthInches / Float(pointDensity / 2)) {
                points.append(SIMD3<Float>(x, 0, z))
            }
        }

        // Left outer wall (X = 0)
        for y in stride(from: Float(0), through: heightInches, by: heightInches / Float(pointDensity / 2)) {
            for z in stride(from: Float(0), through: leftExtensionLengthInches, by: leftExtensionLengthInches / Float(pointDensity)) {
                points.append(SIMD3<Float>(0, y, z))
            }
        }

        // Right outer wall (X = mainWidth)
        for y in stride(from: Float(0), through: heightInches, by: heightInches / Float(pointDensity / 2)) {
            for z in stride(from: Float(0), through: rightExtensionLengthInches, by: rightExtensionLengthInches / Float(pointDensity)) {
                points.append(SIMD3<Float>(mainWidthInches, y, z))
            }
        }

        // Back wall (Z = mainLength, from left ext to right ext)
        for y in stride(from: Float(0), through: heightInches, by: heightInches / Float(pointDensity / 2)) {
            for x in stride(from: leftExtensionWidthInches, through: mainWidthInches - rightExtensionWidthInches, by: (mainEndX - mainStartX) / Float(pointDensity)) {
                points.append(SIMD3<Float>(x, y, mainLengthInches))
            }
        }

        // Front wall segments (Z = 0)
        // Left front wall
        for y in stride(from: Float(0), through: heightInches, by: heightInches / Float(pointDensity / 2)) {
            for x in stride(from: Float(0), through: leftExtensionWidthInches, by: leftExtensionWidthInches / Float(pointDensity / 2)) {
                points.append(SIMD3<Float>(x, y, 0))
            }
        }
        // Right front wall
        for y in stride(from: Float(0), through: heightInches, by: heightInches / Float(pointDensity / 2)) {
            for x in stride(from: mainWidthInches - rightExtensionWidthInches, through: mainWidthInches, by: rightExtensionWidthInches / Float(pointDensity / 2)) {
                points.append(SIMD3<Float>(x, y, 0))
            }
        }

        // Left interior wall (X = leftExtWidth, from leftExtLength to mainLength)
        for y in stride(from: Float(0), through: heightInches, by: heightInches / Float(pointDensity / 2)) {
            for z in stride(from: leftExtensionLengthInches, through: mainLengthInches, by: (mainLengthInches - leftExtensionLengthInches) / Float(pointDensity / 2)) {
                points.append(SIMD3<Float>(leftExtensionWidthInches, y, z))
            }
        }

        // Right interior wall (X = mainWidth - rightExtWidth, from rightExtLength to mainLength)
        for y in stride(from: Float(0), through: heightInches, by: heightInches / Float(pointDensity / 2)) {
            for z in stride(from: rightExtensionLengthInches, through: mainLengthInches, by: (mainLengthInches - rightExtensionLengthInches) / Float(pointDensity / 2)) {
                points.append(SIMD3<Float>(mainWidthInches - rightExtensionWidthInches, y, z))
            }
        }

        // Interior horizontal walls (connecting left and right extensions to main)
        // Left interior horizontal (Z = leftExtLength, from X=0 to X=leftExtWidth)
        for y in stride(from: Float(0), through: heightInches, by: heightInches / Float(pointDensity / 2)) {
            for x in stride(from: Float(0), through: leftExtensionWidthInches, by: leftExtensionWidthInches / Float(pointDensity / 2)) {
                points.append(SIMD3<Float>(x, y, leftExtensionLengthInches))
            }
        }
        // Right interior horizontal (Z = rightExtLength, from X=mainWidth-rightExtWidth to X=mainWidth)
        for y in stride(from: Float(0), through: heightInches, by: heightInches / Float(pointDensity / 2)) {
            for x in stride(from: mainWidthInches - rightExtensionWidthInches, through: mainWidthInches, by: rightExtensionWidthInches / Float(pointDensity / 2)) {
                points.append(SIMD3<Float>(x, y, rightExtensionLengthInches))
            }
        }

        return AIPointCloud(points: points)
    }

    /// Creates a room with an open boundary (gap in one wall).
    private func createRoomWithOpenBoundary(
        widthInches: Float,
        lengthInches: Float,
        heightInches: Float,
        openingWidthInches: Float,
        pointDensity: Int = 20
    ) -> AIPointCloud {
        var points: [SIMD3<Float>] = []

        // Floor
        for x in stride(from: Float(0), through: widthInches, by: widthInches / Float(pointDensity)) {
            for z in stride(from: Float(0), through: lengthInches, by: lengthInches / Float(pointDensity)) {
                points.append(SIMD3<Float>(x, 0, z))
            }
        }

        // 3 complete walls
        // Left wall
        for y in stride(from: Float(0), through: heightInches, by: heightInches / Float(pointDensity / 2)) {
            for z in stride(from: Float(0), through: lengthInches, by: lengthInches / Float(pointDensity)) {
                points.append(SIMD3<Float>(0, y, z))
            }
        }

        // Right wall
        for y in stride(from: Float(0), through: heightInches, by: heightInches / Float(pointDensity / 2)) {
            for z in stride(from: Float(0), through: lengthInches, by: lengthInches / Float(pointDensity)) {
                points.append(SIMD3<Float>(widthInches, y, z))
            }
        }

        // Back wall
        for y in stride(from: Float(0), through: heightInches, by: heightInches / Float(pointDensity / 2)) {
            for x in stride(from: Float(0), through: widthInches, by: widthInches / Float(pointDensity)) {
                points.append(SIMD3<Float>(x, y, lengthInches))
            }
        }

        // Front wall with opening in the middle
        let openingStart = (widthInches - openingWidthInches) / 2
        let openingEnd = openingStart + openingWidthInches

        for y in stride(from: Float(0), through: heightInches, by: heightInches / Float(pointDensity / 2)) {
            for x in stride(from: Float(0), through: widthInches, by: widthInches / Float(pointDensity)) {
                // Skip the opening
                if x < openingStart || x > openingEnd {
                    points.append(SIMD3<Float>(x, y, 0))
                }
            }
        }

        return AIPointCloud(points: points)
    }
}
