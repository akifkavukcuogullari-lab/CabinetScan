//
//  FlowRouter.swift
//  cabinetscan
//
//  Created by Dev Agent on 2026-01-25.
//

import SwiftUI
import RoomPlan

/// Routes users to appropriate scanning flow based on device capabilities.
/// LiDAR devices use existing RoomPlan flow, non-LiDAR devices use AI flow.
struct FlowRouter {

    // MARK: - Debug/Testing Flags

    /// Set to `true` to force AI Flow even on LiDAR devices (for testing).
    /// TODO: Remove or disable before production release.
    static let forceAIFlow = true

    // MARK: - Device Capability Detection

    /// Check device capability for RoomPlan/LiDAR scanning.
    /// Returns `true` if device supports RoomPlan (has LiDAR), `false` otherwise.
    static var supportsLiDAR: Bool {
        if #available(iOS 17.0, *) {
            return RoomCaptureSession.isSupported
        }
        return false
    }

    /// Determines if the current session should use AI Flow.
    /// Returns `true` if device lacks LiDAR OR if `forceAIFlow` is enabled.
    static var shouldUseAIFlow: Bool {
        forceAIFlow || !supportsLiDAR
    }

    // MARK: - Flow Routing

    /// Route to appropriate scanning flow based on device capabilities.
    /// - Returns: `ScanningView` for LiDAR devices, placeholder for AI flow on non-LiDAR devices.
    @ViewBuilder
    static func scanEntryPoint() -> some View {
        if shouldUseAIFlow {
            // AI flow for non-LiDAR devices (or forced for testing)
            AIFlowEntryPoint()
        } else {
            // Existing LiDAR flow - completely unchanged
            ScanningView()
        }
    }
}
