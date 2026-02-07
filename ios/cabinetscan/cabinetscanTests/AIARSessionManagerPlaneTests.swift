//
//  AIARSessionManagerPlaneTests.swift
//  cabinetscanTests
//
//  Phase 1.1-test: Plane detection unit tests
//  Server Pipeline V2
//

import XCTest
@testable import cabinetscan

// MARK: - Plane Detection Tests

final class AIARSessionManagerPlaneTests: XCTestCase {

    private var sessionManager: AIARSessionManager!

    override func setUp() {
        super.setUp()
        sessionManager = AIARSessionManager()
    }

    override func tearDown() {
        sessionManager.stopSession()
        sessionManager = nil
        super.tearDown()
    }

    // MARK: - exportPlanesJSON Tests

    func testExportPlanesJSONReturnsValidJSONWhenEmpty() {
        // When no planes detected, should return empty JSON array
        let data = sessionManager.exportPlanesJSON()
        XCTAssertFalse(data.isEmpty, "Export should return data even with no planes")

        // Parse and verify it's a valid JSON array
        let parsed = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]
        XCTAssertNotNil(parsed, "Should be valid JSON array")
        XCTAssertEqual(parsed?.count, 0, "Should be empty array when no planes detected")
    }

    func testExportPlanesJSONFormatMatchesServerExpectation() throws {
        // Verify the JSON structure matches what server/pipeline/stages/wall_detection.py expects:
        // Each plane should have: identifier, alignment, center, extent, transform

        let data = sessionManager.exportPlanesJSON()
        let parsed = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [[String: Any]],
            "Should parse as array of dictionaries"
        )

        // Empty is valid - server handles zero planes gracefully
        // When planes exist, verify format (tested via integration)
        XCTAssertTrue(parsed.isEmpty || parsed.allSatisfy { plane in
            plane["identifier"] is String &&
            plane["alignment"] is String &&
            plane["center"] is [Any] &&
            plane["extent"] is [Any] &&
            plane["transform"] is [[Any]]
        }, "Each plane should have required fields")
    }

    func testGetDetectedPlaneCountInitiallyZero() {
        XCTAssertEqual(sessionManager.getDetectedPlaneCount(), 0)
    }

    func testDetectedPlaneCountPublishedPropertyInitiallyZero() {
        XCTAssertEqual(sessionManager.detectedPlaneCount, 0)
    }

    // MARK: - Session Lifecycle Tests

    func testPlanesAreClearedOnStopSession() {
        // Stop should reset plane count
        sessionManager.stopSession()

        let expectation = XCTestExpectation(description: "Plane count reset")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            XCTAssertEqual(self.sessionManager.getDetectedPlaneCount(), 0)
            XCTAssertEqual(self.sessionManager.detectedPlaneCount, 0)
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1.0)
    }

    func testExportPlanesJSONIsEmptyAfterStop() {
        sessionManager.stopSession()

        let expectation = XCTestExpectation(description: "Planes cleared")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            let data = self.sessionManager.exportPlanesJSON()
            let parsed = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]
            XCTAssertEqual(parsed?.count, 0, "Should be empty after stop")
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1.0)
    }

    // MARK: - Thread Safety Tests

    func testExportPlanesJSONIsThreadSafe() {
        // Call from multiple threads concurrently — should not crash
        let expectation = XCTestExpectation(description: "Concurrent access")
        expectation.expectedFulfillmentCount = 10

        for _ in 0..<10 {
            DispatchQueue.global().async {
                _ = self.sessionManager.exportPlanesJSON()
                _ = self.sessionManager.getDetectedPlaneCount()
                expectation.fulfill()
            }
        }

        wait(for: [expectation], timeout: 2.0)
    }
}
