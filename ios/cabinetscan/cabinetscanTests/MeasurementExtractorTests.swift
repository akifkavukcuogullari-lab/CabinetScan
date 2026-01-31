//
//  MeasurementExtractorTests.swift
//  cabinetscanTests
//
//  Created for Story 4.7: Measurement Extraction and Standard Size Snapping
//

import XCTest
import simd
@testable import cabinetscan

final class MeasurementExtractorTests: XCTestCase {

    var sut: MeasurementExtractor!

    @MainActor
    override func setUp() {
        super.setUp()
        sut = MeasurementExtractor()
    }

    override func tearDown() {
        sut = nil
        super.tearDown()
    }

    // MARK: - Test Helpers

    private func createTestCabinet(
        type: AICabinetType,
        rawWidth: Float,
        snappedWidth: Float,
        isStandard: Bool,
        confidence: AIConfidenceLevel = .high,
        notes: [String] = []
    ) -> AIDetectedCabinet {
        return AIDetectedCabinet(
            id: UUID(),
            boundingBox: AIBoundingBox3D(center: .zero, size: SIMD3(snappedWidth, 34.5, 24.0)),
            type: type,
            wallId: UUID(),
            positionOnWallInches: 0,
            rawDimensions: SIMD3(rawWidth, 34.5, 24.0),
            snappedDimensions: SIMD3(snappedWidth, 34.5, 24.0),
            confidence: confidence,
            isStandardSize: isStandard,
            notes: notes
        )
    }

    private func createCabinetResult(cabinets: [AIDetectedCabinet]) -> CabinetDetectionResult {
        return CabinetDetectionResult(
            cabinets: cabinets,
            wallCoverageValidation: [],
            processingTimeMs: 100,
            warnings: []
        )
    }

    // MARK: - AC1: Raw Dimension Extraction

    @MainActor
    func testExtractRawDimensionsPreservesFullPrecision() async throws {
        // Given: A cabinet with precise raw dimensions
        let cabinet = createTestCabinet(
            type: .base,
            rawWidth: 35.823,
            snappedWidth: 36.0,
            isStandard: true
        )
        let result = createCabinetResult(cabinets: [cabinet])

        // When: Extracting measurements
        let extractionResult = try await sut.extract(
            cabinetResult: result,
            applianceResult: nil,
            islandPeninsulaResult: nil,
            countertopResult: nil
        )

        // Then: Raw value is preserved at full precision
        XCTAssertEqual(extractionResult.cabinetMeasurements.count, 1)
        let measurement = extractionResult.cabinetMeasurements[0]
        XCTAssertEqual(measurement.rawWidthInches, 35.823, accuracy: 0.001)
        XCTAssertEqual(measurement.snappedWidthInches, 36.0, accuracy: 0.001)
    }

    // MARK: - AC2: Standard Size Snapping

    @MainActor
    func testSnappingWithin1_5InchesHighConfidence() async throws {
        // Given: A cabinet with raw width 17.8" (within 1.5" of 18")
        let cabinet = createTestCabinet(
            type: .base,
            rawWidth: 17.8,
            snappedWidth: 18.0,
            isStandard: true,
            confidence: .high
        )
        let result = createCabinetResult(cabinets: [cabinet])

        // When: Extracting measurements
        let extractionResult = try await sut.extract(
            cabinetResult: result,
            applianceResult: nil,
            islandPeninsulaResult: nil,
            countertopResult: nil
        )

        // Then: Snapped to 18" with HIGH confidence
        let measurement = extractionResult.cabinetMeasurements[0]
        XCTAssertEqual(measurement.snappedWidthInches, 18.0, accuracy: 0.01)
        XCTAssertEqual(measurement.confidence, .high)
        XCTAssertTrue(measurement.isStandardSize)
        XCTAssertFalse(measurement.isCustomSize)
    }

    // MARK: - AC3: US Standard Cabinet Widths

    @MainActor
    func testAllStandardWidthsRecognized() async throws {
        // Given: All standard widths for base cabinets
        let standardWidths: [Float] = [9, 12, 15, 18, 21, 24, 27, 30, 33, 36]
        var cabinets: [AIDetectedCabinet] = []

        for width in standardWidths {
            let cabinet = createTestCabinet(
                type: .base,
                rawWidth: width,
                snappedWidth: width,
                isStandard: true
            )
            cabinets.append(cabinet)
        }

        let result = createCabinetResult(cabinets: cabinets)

        // When: Extracting measurements
        let extractionResult = try await sut.extract(
            cabinetResult: result,
            applianceResult: nil,
            islandPeninsulaResult: nil,
            countertopResult: nil
        )

        // Then: All are recognized as standard sizes
        XCTAssertEqual(extractionResult.cabinetMeasurements.count, standardWidths.count)
        for measurement in extractionResult.cabinetMeasurements {
            XCTAssertTrue(measurement.isStandardSize, "Width \(measurement.snappedWidthInches) should be standard")
            XCTAssertFalse(measurement.isCustomSize)
        }
    }

    @MainActor
    func testTallCabinetStandardWidths() async throws {
        // Given: Tall cabinet standard widths
        let tallWidths: [Float] = [18, 24, 30, 36]
        var cabinets: [AIDetectedCabinet] = []

        for width in tallWidths {
            let cabinet = createTestCabinet(
                type: .tall,
                rawWidth: width,
                snappedWidth: width,
                isStandard: true
            )
            cabinets.append(cabinet)
        }

        let result = createCabinetResult(cabinets: cabinets)

        // When: Extracting measurements
        let extractionResult = try await sut.extract(
            cabinetResult: result,
            applianceResult: nil,
            islandPeninsulaResult: nil,
            countertopResult: nil
        )

        // Then: All are recognized as standard sizes
        XCTAssertEqual(extractionResult.cabinetMeasurements.count, tallWidths.count)
        for measurement in extractionResult.cabinetMeasurements {
            XCTAssertTrue(measurement.isStandardSize, "Tall cabinet width \(measurement.snappedWidthInches) should be standard")
        }
    }

    // MARK: - AC4: Non-Standard Handling

    @MainActor
    func testMeasurementOutsideSnapToleranceKeepsRaw() async throws {
        // Given: A cabinet with raw width 45" (not near any standard)
        let cabinet = createTestCabinet(
            type: .base,
            rawWidth: 45.0,
            snappedWidth: 45.0, // Not snapped - kept raw
            isStandard: false,
            confidence: .low
        )
        let result = createCabinetResult(cabinets: [cabinet])

        // When: Extracting measurements
        let extractionResult = try await sut.extract(
            cabinetResult: result,
            applianceResult: nil,
            islandPeninsulaResult: nil,
            countertopResult: nil
        )

        // Then: Raw measurement is kept, not forced to standard
        let measurement = extractionResult.cabinetMeasurements[0]
        XCTAssertEqual(measurement.rawWidthInches, 45.0, accuracy: 0.01)
        XCTAssertEqual(measurement.snappedWidthInches, 45.0, accuracy: 0.01)
        XCTAssertFalse(measurement.isStandardSize)
    }

    // MARK: - AC5: Precision Preservation

    @MainActor
    func testRawValuesNeverDiscarded() async throws {
        // Given: Multiple cabinets with different raw values
        let cabinets = [
            createTestCabinet(type: .base, rawWidth: 35.8, snappedWidth: 36.0, isStandard: true),
            createTestCabinet(type: .base, rawWidth: 23.7, snappedWidth: 24.0, isStandard: true),
            createTestCabinet(type: .base, rawWidth: 17.2, snappedWidth: 18.0, isStandard: true)
        ]
        let result = createCabinetResult(cabinets: cabinets)

        // When: Extracting measurements
        let extractionResult = try await sut.extract(
            cabinetResult: result,
            applianceResult: nil,
            islandPeninsulaResult: nil,
            countertopResult: nil
        )

        // Then: All raw values are preserved
        XCTAssertEqual(extractionResult.cabinetMeasurements[0].rawWidthInches, 35.8, accuracy: 0.01)
        XCTAssertEqual(extractionResult.cabinetMeasurements[1].rawWidthInches, 23.7, accuracy: 0.01)
        XCTAssertEqual(extractionResult.cabinetMeasurements[2].rawWidthInches, 17.2, accuracy: 0.01)
    }

    // MARK: - AC6: Dual Value Quote Output

    @MainActor
    func testQuoteOutputShowsBothValues() async throws {
        // Given: A cabinet where raw differs from snapped
        let cabinet = createTestCabinet(
            type: .base,
            rawWidth: 35.8,
            snappedWidth: 36.0,
            isStandard: true
        )
        let result = createCabinetResult(cabinets: [cabinet])

        // When: Extracting and formatting for quote
        let extractionResult = try await sut.extract(
            cabinetResult: result,
            applianceResult: nil,
            islandPeninsulaResult: nil,
            countertopResult: nil
        )

        // Then: Display string shows both values
        let measurement = extractionResult.cabinetMeasurements[0]
        XCTAssertTrue(measurement.displayString.contains("36"))
        XCTAssertTrue(measurement.displayString.contains("35.8"))
    }

    @MainActor
    func testQuoteOutputForExactMatch() async throws {
        // Given: A cabinet where raw equals snapped
        let cabinet = createTestCabinet(
            type: .base,
            rawWidth: 36.0,
            snappedWidth: 36.0,
            isStandard: true
        )
        let result = createCabinetResult(cabinets: [cabinet])

        // When: Extracting and formatting for quote
        let extractionResult = try await sut.extract(
            cabinetResult: result,
            applianceResult: nil,
            islandPeninsulaResult: nil,
            countertopResult: nil
        )

        // Then: Display string shows only snapped (no need for raw)
        let measurement = extractionResult.cabinetMeasurements[0]
        XCTAssertEqual(measurement.displayString, "36\"")
    }

    // MARK: - AC7: Custom Cabinet Flagging

    @MainActor
    func testCustomSizeFlagged() async throws {
        // Given: A cabinet with non-standard dimensions beyond tolerance
        let cabinet = createTestCabinet(
            type: .base,
            rawWidth: 40.0, // No standard near this
            snappedWidth: 40.0,
            isStandard: false,
            confidence: .low
        )
        let result = createCabinetResult(cabinets: [cabinet])

        // When: Extracting measurements
        let extractionResult = try await sut.extract(
            cabinetResult: result,
            applianceResult: nil,
            islandPeninsulaResult: nil,
            countertopResult: nil
        )

        // Then: Custom size is flagged
        let measurement = extractionResult.cabinetMeasurements[0]
        XCTAssertTrue(measurement.isCustomSize)
        XCTAssertTrue(measurement.displayString.contains("CUSTOM SIZE"))
    }

    @MainActor
    func testCustomSizeUsesRawForDisplay() async throws {
        // Given: A custom-size cabinet
        let cabinet = createTestCabinet(
            type: .base,
            rawWidth: 17.2,
            snappedWidth: 17.2, // Not snapped
            isStandard: false,
            confidence: .low
        )
        let result = createCabinetResult(cabinets: [cabinet])

        // When: Extracting measurements
        let extractionResult = try await sut.extract(
            cabinetResult: result,
            applianceResult: nil,
            islandPeninsulaResult: nil,
            countertopResult: nil
        )

        // Then: Display uses raw value
        let measurement = extractionResult.cabinetMeasurements[0]
        XCTAssertTrue(measurement.displayString.contains("17.2"))
    }

    // MARK: - AC8: Total Discrepancy Validation

    @MainActor
    func testDiscrepancyFlaggedWhenOver2Inches() async throws {
        // Given: Cabinets where snapped totals differ from raw by >2"
        let cabinets = [
            createTestCabinet(type: .base, rawWidth: 35.0, snappedWidth: 36.0, isStandard: true),
            createTestCabinet(type: .base, rawWidth: 23.0, snappedWidth: 24.0, isStandard: true),
            createTestCabinet(type: .base, rawWidth: 17.5, snappedWidth: 18.0, isStandard: true)
            // Total raw: 75.5", Total snapped: 78" = 2.5" discrepancy
        ]
        let result = createCabinetResult(cabinets: cabinets)

        // When: Extracting measurements
        let extractionResult = try await sut.extract(
            cabinetResult: result,
            applianceResult: nil,
            islandPeninsulaResult: nil,
            countertopResult: nil
        )

        // Then: Discrepancy is flagged
        XCTAssertTrue(extractionResult.baseLinearFootage.hasSignificantDiscrepancy)
        XCTAssertGreaterThan(extractionResult.baseLinearFootage.discrepancyInches, 2.0)
    }

    @MainActor
    func testBothRawAndSnappedTotalsReported() async throws {
        // Given: Multiple cabinets
        let cabinets = [
            createTestCabinet(type: .base, rawWidth: 35.8, snappedWidth: 36.0, isStandard: true),
            createTestCabinet(type: .base, rawWidth: 23.7, snappedWidth: 24.0, isStandard: true)
        ]
        let result = createCabinetResult(cabinets: cabinets)

        // When: Extracting measurements
        let extractionResult = try await sut.extract(
            cabinetResult: result,
            applianceResult: nil,
            islandPeninsulaResult: nil,
            countertopResult: nil
        )

        // Then: Both totals are reported
        XCTAssertEqual(extractionResult.baseLinearFootage.rawTotalInches, 59.5, accuracy: 0.1)
        XCTAssertEqual(extractionResult.baseLinearFootage.snappedTotalInches, 60.0, accuracy: 0.1)
    }

    // MARK: - AC9: Measurement Sum Validation

    @MainActor
    func testLinearTotalsCalculatedCorrectly() async throws {
        // Given: Multiple base cabinets
        let cabinets = [
            createTestCabinet(type: .base, rawWidth: 36.0, snappedWidth: 36.0, isStandard: true),
            createTestCabinet(type: .base, rawWidth: 24.0, snappedWidth: 24.0, isStandard: true),
            createTestCabinet(type: .base, rawWidth: 18.0, snappedWidth: 18.0, isStandard: true)
        ]
        let result = createCabinetResult(cabinets: cabinets)

        // When: Extracting measurements
        let extractionResult = try await sut.extract(
            cabinetResult: result,
            applianceResult: nil,
            islandPeninsulaResult: nil,
            countertopResult: nil
        )

        // Then: Total is 78" (6.5 linear feet)
        XCTAssertEqual(extractionResult.baseLinearFootage.snappedTotalInches, 78.0, accuracy: 0.01)
        XCTAssertEqual(extractionResult.baseLinearFootage.snappedTotalLinearFeet, 6.5, accuracy: 0.01)
    }

    // MARK: - Medium Confidence Range Tests

    @MainActor
    func testSnapping1_5To3InchMediumConfidence() async throws {
        // Given: A cabinet with raw width 22" (2" from nearest 24")
        let cabinet = createTestCabinet(
            type: .base,
            rawWidth: 22.0,
            snappedWidth: 22.0, // Kept raw due to medium confidence
            isStandard: false,
            confidence: .medium
        )
        let result = createCabinetResult(cabinets: [cabinet])

        // When: Extracting measurements
        let extractionResult = try await sut.extract(
            cabinetResult: result,
            applianceResult: nil,
            islandPeninsulaResult: nil,
            countertopResult: nil
        )

        // Then: Has MEDIUM confidence
        let measurement = extractionResult.cabinetMeasurements[0]
        XCTAssertEqual(measurement.confidence, .medium)
        XCTAssertFalse(measurement.isStandardSize)
    }

    @MainActor
    func testSnappingBeyond3InchLowConfidence() async throws {
        // Given: A cabinet with raw width 40" (4" from nearest 36")
        let cabinet = createTestCabinet(
            type: .base,
            rawWidth: 40.0,
            snappedWidth: 40.0, // Kept raw due to low confidence
            isStandard: false,
            confidence: .low
        )
        let result = createCabinetResult(cabinets: [cabinet])

        // When: Extracting measurements
        let extractionResult = try await sut.extract(
            cabinetResult: result,
            applianceResult: nil,
            islandPeninsulaResult: nil,
            countertopResult: nil
        )

        // Then: Has LOW confidence, marked custom
        let measurement = extractionResult.cabinetMeasurements[0]
        XCTAssertEqual(measurement.confidence, .low)
        XCTAssertTrue(measurement.isCustomSize)
    }

    // MARK: - Empty Input Tests

    @MainActor
    func testEmptyInputReturnsEmptyResult() async throws {
        // Given: No detection results
        // When: Extracting measurements
        let extractionResult = try await sut.extract(
            cabinetResult: nil,
            applianceResult: nil,
            islandPeninsulaResult: nil,
            countertopResult: nil
        )

        // Then: Empty result with warning
        XCTAssertTrue(extractionResult.allMeasurements.isEmpty)
        XCTAssertFalse(extractionResult.warnings.isEmpty)
    }

    // MARK: - Quote Output Tests

    @MainActor
    func testGenerateQuoteOutputs() async throws {
        // Given: Cabinets with various dimensions
        let cabinets = [
            createTestCabinet(type: .base, rawWidth: 35.8, snappedWidth: 36.0, isStandard: true),
            createTestCabinet(type: .base, rawWidth: 24.0, snappedWidth: 24.0, isStandard: true)
        ]
        let result = createCabinetResult(cabinets: cabinets)

        // When: Extracting and generating quote outputs
        let extractionResult = try await sut.extract(
            cabinetResult: result,
            applianceResult: nil,
            islandPeninsulaResult: nil,
            countertopResult: nil
        )
        let quoteOutputs = extractionResult.generateQuoteOutputs()

        // Then: Quote outputs are generated for all measurements
        XCTAssertEqual(quoteOutputs.count, 2)

        // First has difference
        XCTAssertNotNil(quoteOutputs[0].differenceDisplay)
        XCTAssertEqual(quoteOutputs[0].snappedValueDisplay, "36\"")

        // Second is exact match
        XCTAssertNil(quoteOutputs[1].differenceDisplay)
        XCTAssertEqual(quoteOutputs[1].snappedValueDisplay, "24\"")
    }

    // MARK: - Object Type Classification Tests

    @MainActor
    func testCabinetTypesClassifiedCorrectly() async throws {
        // Given: Different cabinet types
        let cabinets = [
            createTestCabinet(type: .base, rawWidth: 36.0, snappedWidth: 36.0, isStandard: true),
            createTestCabinet(type: .upper, rawWidth: 30.0, snappedWidth: 30.0, isStandard: true),
            createTestCabinet(type: .tall, rawWidth: 24.0, snappedWidth: 24.0, isStandard: true)
        ]
        let result = createCabinetResult(cabinets: cabinets)

        // When: Extracting measurements
        let extractionResult = try await sut.extract(
            cabinetResult: result,
            applianceResult: nil,
            islandPeninsulaResult: nil,
            countertopResult: nil
        )

        // Then: Types are classified correctly
        let measurements = extractionResult.cabinetMeasurements
        XCTAssertEqual(measurements[0].objectType, .baseCabinet)
        XCTAssertEqual(measurements[1].objectType, .upperCabinet)
        XCTAssertEqual(measurements[2].objectType, .tallCabinet)
    }

    // MARK: - Linear Footage Separation Tests

    @MainActor
    func testSeparateLinearFootageForBaseUpperTall() async throws {
        // Given: Mix of cabinet types
        let cabinets = [
            createTestCabinet(type: .base, rawWidth: 36.0, snappedWidth: 36.0, isStandard: true),
            createTestCabinet(type: .base, rawWidth: 24.0, snappedWidth: 24.0, isStandard: true),
            createTestCabinet(type: .upper, rawWidth: 30.0, snappedWidth: 30.0, isStandard: true),
            createTestCabinet(type: .tall, rawWidth: 18.0, snappedWidth: 18.0, isStandard: true)
        ]
        let result = createCabinetResult(cabinets: cabinets)

        // When: Extracting measurements
        let extractionResult = try await sut.extract(
            cabinetResult: result,
            applianceResult: nil,
            islandPeninsulaResult: nil,
            countertopResult: nil
        )

        // Then: Separate totals for each type
        XCTAssertEqual(extractionResult.baseLinearFootage.snappedTotalInches, 60.0, accuracy: 0.01) // 36 + 24
        XCTAssertEqual(extractionResult.upperLinearFootage.snappedTotalInches, 30.0, accuracy: 0.01)
        XCTAssertEqual(extractionResult.tallLinearFootage.snappedTotalInches, 18.0, accuracy: 0.01)
    }

    // MARK: - Standard Cabinet Sizes Extension Tests

    func testIsCustomSizeReturnsTrueForNonStandard() {
        // Given: Non-standard widths (more than 1.5" from any standard size)
        // Standard widths: 9, 12, 15, 18, 21, 24, 27, 30, 33, 36, 42, 48
        // Widths >1.5" from any standard: 5, 40, 50, 53, 60
        let nonStandardWidths: [Float] = [5, 40, 50, 53, 60]

        for width in nonStandardWidths {
            // Then: Marked as custom size
            XCTAssertTrue(
                StandardCabinetSizes.isCustomSize(width: width, type: .base),
                "Width \(width) should be custom size (>1.5\" from any standard)"
            )
        }
    }

    func testIsCustomSizeReturnsFalseForStandard() {
        // Given: All standard widths
        let standardWidths: [Float] = [9, 12, 15, 18, 21, 24, 27, 30, 33, 36, 42, 48]

        for width in standardWidths {
            // Then: Not marked as custom size
            XCTAssertFalse(
                StandardCabinetSizes.isCustomSize(width: width, type: .base),
                "Width \(width) should not be custom size"
            )
        }
    }

    func testSnapDifferenceDescription() {
        // Given: Various raw/snapped pairs
        // Exact match
        XCTAssertNil(StandardCabinetSizes.snapDifferenceDescription(raw: 36.0, snapped: 36.0))

        // Small difference
        let desc = StandardCabinetSizes.snapDifferenceDescription(raw: 35.8, snapped: 36.0)
        XCTAssertNotNil(desc)
        XCTAssertTrue(desc!.contains("0.2"))
    }

    // MARK: - Processing Time Tests

    @MainActor
    func testExtractionCompletesWithinBudget() async throws {
        // Given: A reasonable number of cabinets
        var cabinets: [AIDetectedCabinet] = []
        for i in 0..<20 {
            let width: Float = Float([9, 12, 15, 18, 21, 24, 27, 30, 33, 36][i % 10])
            cabinets.append(createTestCabinet(
                type: .base,
                rawWidth: width,
                snappedWidth: width,
                isStandard: true
            ))
        }
        let result = createCabinetResult(cabinets: cabinets)

        // When: Extracting measurements
        let extractionResult = try await sut.extract(
            cabinetResult: result,
            applianceResult: nil,
            islandPeninsulaResult: nil,
            countertopResult: nil
        )

        // Then: Completes within 100ms budget per Architecture 9.3
        XCTAssertLessThan(extractionResult.processingTimeMs, 100)
    }
}
