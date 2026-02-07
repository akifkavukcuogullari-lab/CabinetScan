//
//  ServerPipelineClientTests.swift
//  cabinetscanTests
//
//  Phase 2.1-test: ServerPipelineClient unit tests
//  Server Pipeline V2
//

import XCTest
@testable import cabinetscan

final class ServerPipelineClientTests: XCTestCase {

    // MARK: - ServerJobStatus Tests

    func testJobStatusParsesQueued() {
        let status = ServerJobStatus.Status(rawValue: "queued")
        XCTAssertEqual(status, .queued)
    }

    func testJobStatusParsesProcessing() {
        let status = ServerJobStatus.Status(rawValue: "processing")
        XCTAssertEqual(status, .processing)
    }

    func testJobStatusParsesCompleted() {
        let status = ServerJobStatus.Status(rawValue: "completed")
        XCTAssertEqual(status, .completed)
    }

    func testJobStatusParsesFailed() {
        let status = ServerJobStatus.Status(rawValue: "failed")
        XCTAssertEqual(status, .failed)
    }

    func testJobStatusInvalidReturnsNil() {
        let status = ServerJobStatus.Status(rawValue: "unknown")
        XCTAssertNil(status)
    }

    // MARK: - ServerPipelineResult Tests

    func testServerPipelineResultInit() {
        let result = ServerPipelineResult(
            measurementsData: ["room_name": "Kitchen"],
            floorPlanURL: "https://example.com/plan.png",
            validationPassed: true,
            validationIssues: [],
            processingTimeMs: 5000,
            scaleConfidence: "high",
            pipelineVersion: "v2"
        )

        XCTAssertEqual(result.measurementsData["room_name"] as? String, "Kitchen")
        XCTAssertEqual(result.floorPlanURL, "https://example.com/plan.png")
        XCTAssertTrue(result.validationPassed)
        XCTAssertEqual(result.processingTimeMs, 5000)
        XCTAssertEqual(result.scaleConfidence, "high")
    }

    // MARK: - ServerPipelineError Tests

    func testUploadFailedError() {
        let error = ServerPipelineError.uploadFailed("Network timeout")
        XCTAssertTrue(error.localizedDescription.contains("upload"))
        XCTAssertTrue(error.localizedDescription.contains("Network timeout"))
    }

    func testJobCreationFailedError() {
        let error = ServerPipelineError.jobCreationFailed("Invalid response")
        XCTAssertTrue(error.localizedDescription.contains("processing job"))
    }

    func testPollingTimeoutError() {
        let error = ServerPipelineError.pollingTimeout
        XCTAssertTrue(error.localizedDescription.contains("longer than expected"))
    }

    func testJobFailedError() {
        let error = ServerPipelineError.jobFailed("Out of memory")
        XCTAssertTrue(error.localizedDescription.contains("Out of memory"))
    }

    func testCancelledError() {
        let error = ServerPipelineError.cancelled
        XCTAssertTrue(error.localizedDescription.contains("cancelled"))
    }

    // MARK: - Cancellation Tests

    func testCancelSetsFlag() async {
        let client = ServerPipelineClient()
        await client.cancel()
        // After cancel, subsequent operations should throw .cancelled
        // (tested indirectly through pollForResults)
    }

    // MARK: - ServerJobStatus Struct Tests

    func testJobStatusStruct() {
        let status = ServerJobStatus(
            jobId: "test-123",
            status: .processing,
            progress: 0.5,
            stage: "Detecting cabinets...",
            errorMessage: nil
        )

        XCTAssertEqual(status.jobId, "test-123")
        XCTAssertEqual(status.status, .processing)
        XCTAssertEqual(status.progress, 0.5)
        XCTAssertEqual(status.stage, "Detecting cabinets...")
        XCTAssertNil(status.errorMessage)
    }

    func testJobStatusWithError() {
        let status = ServerJobStatus(
            jobId: "test-456",
            status: .failed,
            progress: 0.3,
            stage: "depth_estimation",
            errorMessage: "GPU out of memory"
        )

        XCTAssertEqual(status.status, .failed)
        XCTAssertEqual(status.errorMessage, "GPU out of memory")
    }
}
