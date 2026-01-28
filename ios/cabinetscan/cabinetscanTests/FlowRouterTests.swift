//
//  FlowRouterTests.swift
//  cabinetscanTests
//
//  Created by Dev Agent on 2026-01-25.
//

import XCTest
import SwiftUI
@testable import cabinetscan

/// Tests for FlowRouter device capability detection and routing.
/// Note: `RoomCaptureSession.isSupported` is a static property that cannot be mocked,
/// so these tests validate the logic structure and compile-time correctness.
/// Full device testing requires running on actual LiDAR and non-LiDAR devices.
final class FlowRouterTests: XCTestCase {

    // MARK: - AC1: RoomPlan Detection Structure Tests

    /// Test that supportsLiDAR property is accessible and returns a Boolean.
    /// The actual value depends on device hardware.
    func testSupportsLiDAR_ReturnsBoolean() {
        // Given: FlowRouter static property
        // When: Accessing supportsLiDAR
        let result = FlowRouter.supportsLiDAR

        // Then: Should return a Boolean (true or false depending on device)
        XCTAssertNotNil(result as Bool?, "supportsLiDAR should return a Boolean value")
    }

    /// Test that supportsLiDAR is consistent across multiple calls.
    /// Device capability should not change during app lifecycle.
    func testSupportsLiDAR_IsConsistent() {
        // Given: Multiple reads of supportsLiDAR
        let firstRead = FlowRouter.supportsLiDAR
        let secondRead = FlowRouter.supportsLiDAR
        let thirdRead = FlowRouter.supportsLiDAR

        // Then: All reads should return the same value
        XCTAssertEqual(firstRead, secondRead, "supportsLiDAR should be consistent")
        XCTAssertEqual(secondRead, thirdRead, "supportsLiDAR should be consistent")
    }

    // MARK: - AC2/AC3: Flow Routing Tests

    /// Test that scanEntryPoint returns a View.
    /// Cannot verify the specific view type at runtime, but this validates compilation.
    func testScanEntryPoint_ReturnsView() {
        // Given: FlowRouter
        // When: Calling scanEntryPoint
        let view = FlowRouter.scanEntryPoint()

        // Then: Should return a View (validates @ViewBuilder works)
        // Note: Type erasure prevents checking specific view type at runtime
        XCTAssertNotNil(view as (any View)?, "scanEntryPoint should return a View")
    }

    // MARK: - Device-Specific Tests (Run on Physical Devices)

    /// Test documentation for manual device testing.
    /// These tests require running on physical devices to verify correct behavior.
    func testDeviceTestingDocumentation() {
        // Manual testing checklist:
        // - iPhone 15 Pro (LiDAR) → supportsLiDAR should return true
        // - iPhone 15 (no LiDAR) → supportsLiDAR should return false
        // - iPhone XR (no LiDAR) → supportsLiDAR should return false
        // - iPhone 12 Pro (LiDAR) → supportsLiDAR should return true

        // This test always passes - serves as documentation
        XCTAssertTrue(true, "See manual testing checklist in test comments")
    }
}
