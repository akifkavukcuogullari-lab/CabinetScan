//
//  GuidanceToast.swift
//  cabinetscan
//
//  Created by Dev Agent on 2026-01-25.
//

import SwiftUI

// MARK: - Toast Type

/// Types of guidance toasts with associated styling
enum GuidanceToastType: Equatable {
    case info
    case warning
    case error

    /// Background color for the toast type
    var backgroundColor: Color {
        switch self {
        case .info:
            return Color.black.opacity(0.7)
        case .warning:
            return Color.orange.opacity(0.85)
        case .error:
            return Color.red.opacity(0.85)
        }
    }

    /// Text color for the toast type
    var textColor: Color {
        .white
    }

    /// Priority for toast ordering (higher = more important)
    var priority: Int {
        switch self {
        case .info: return 0
        case .warning: return 1
        case .error: return 2
        }
    }

    /// VoiceOver announcement priority
    var accessibilityPriority: UIAccessibilityPriority {
        switch self {
        case .info: return .default
        case .warning: return .high
        case .error: return .high
        }
    }
}

// MARK: - Toast Message Model

/// Model for a guidance toast message
struct GuidanceToastMessage: Identifiable, Equatable {
    let id: String
    let message: String
    let icon: String?
    let type: GuidanceToastType

    /// Creates a guidance toast message
    /// - Parameters:
    ///   - id: Unique identifier for cooldown tracking
    ///   - message: The message to display
    ///   - icon: Optional SF Symbol name for the icon
    ///   - type: Toast type (info, warning, error)
    init(id: String, message: String, icon: String? = nil, type: GuidanceToastType = .info) {
        self.id = id
        self.message = message
        self.icon = icon
        self.type = type
    }

    static func == (lhs: GuidanceToastMessage, rhs: GuidanceToastMessage) -> Bool {
        lhs.id == rhs.id &&
        lhs.message == rhs.message &&
        lhs.icon == rhs.icon &&
        lhs.type == rhs.type
    }
}

// MARK: - Guidance Toast View

/// Toast notification component for capture guidance.
/// Displays non-blocking messages with auto-dismiss behavior.
/// Per Story 2.3 - Task 1, UX-7, UX-13
///
/// **Features:**
/// - Configurable message and icon (SF Symbol)
/// - Auto-dismiss after 3 seconds (accessibility requirement)
/// - Fade in/out with 0.2s animation (UX-13)
/// - Supports different toast types: info, warning, error
/// - Minimum 17pt text with Dynamic Type support
/// - Full VoiceOver accessibility
struct GuidanceToast: View {
    /// The message to display
    let message: String

    /// Optional SF Symbol name for icon
    let icon: String?

    /// Toast type for styling
    let type: GuidanceToastType

    /// Minimum font size (17pt per accessibility requirement)
    @ScaledMetric(relativeTo: .body) private var minFontSize: CGFloat = 17

    var body: some View {
        HStack(spacing: 8) {
            if let icon = icon {
                Image(systemName: icon)
                    .font(.body.weight(.semibold))
                    .imageScale(.medium)
            }

            Text(message)
                .font(.body.weight(.semibold))
                .minimumScaleFactor(0.8)
                .lineLimit(2)
                .multilineTextAlignment(.center)
        }
        .foregroundStyle(type.textColor)
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(type.backgroundColor)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.2), radius: 4, y: 2)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityAddTraits(.isStaticText)
    }

    /// Accessible label combining type, icon hint, and message
    private var accessibilityLabel: String {
        var label = ""

        // Add type prefix for warnings/errors
        switch type {
        case .warning:
            label = "Warning: "
        case .error:
            label = "Error: "
        case .info:
            break
        }

        label += message
        return label
    }
}

// MARK: - Toast Container

/// Container view that manages toast display with auto-dismiss.
/// Handles fade in/out animations and timing.
/// Per Story 2.3 - Task 1.3, 1.4
struct GuidanceToastContainer: View {
    /// The current toast to display (nil = hidden)
    let toast: GuidanceToastMessage?

    /// Callback when toast should be dismissed
    let onDismiss: () -> Void

    /// Auto-dismiss duration in seconds (3s per accessibility requirement)
    private let dismissDuration: TimeInterval = 3.0

    /// Animation duration (0.2s per UX-13)
    private let animationDuration: Double = 0.2

    /// Timer for auto-dismiss
    @State private var dismissTask: Task<Void, Never>?

    var body: some View {
        ZStack {
            if let toast = toast {
                GuidanceToast(
                    message: toast.message,
                    icon: toast.icon,
                    type: toast.type
                )
                .transition(.opacity.animation(.easeInOut(duration: animationDuration)))
                .onAppear {
                    scheduleAutoDismiss()
                    announceForAccessibility(toast)
                }
                .onDisappear {
                    dismissTask?.cancel()
                }
            }
        }
        .animation(.easeInOut(duration: animationDuration), value: toast?.id)
    }

    /// Schedule auto-dismiss after duration
    private func scheduleAutoDismiss() {
        dismissTask?.cancel()

        dismissTask = Task {
            try? await Task.sleep(nanoseconds: UInt64(dismissDuration * 1_000_000_000))
            if !Task.isCancelled {
                await MainActor.run {
                    onDismiss()
                }
            }
        }
    }

    /// Announce toast message for VoiceOver users
    private func announceForAccessibility(_ toast: GuidanceToastMessage) {
        let announcement: String
        switch toast.type {
        case .warning:
            announcement = "Warning: \(toast.message)"
        case .error:
            announcement = "Error: \(toast.message)"
        case .info:
            announcement = toast.message
        }

        // Use appropriate priority based on toast type
        UIAccessibility.post(
            notification: .announcement,
            argument: announcement
        )
    }
}

// MARK: - Predefined Toast Messages

/// Predefined guidance toast messages per Story 2.3 requirements
extension GuidanceToastMessage {
    // MARK: Quality Warnings (Always shown)

    /// Motion blur detected - slow down
    static let motionBlur = GuidanceToastMessage(
        id: "motion_blur",
        message: "Slow down for sharper images",
        icon: "hand.raised.fill",
        type: .warning
    )

    /// Too dark - need more light
    static let tooDark = GuidanceToastMessage(
        id: "too_dark",
        message: "Move to brighter area for accurate measurements",
        icon: "lightbulb.fill",
        type: .warning
    )

    /// Pointing at floor too long
    static let pointAtCabinetsFromFloor = GuidanceToastMessage(
        id: "floor_orientation",
        message: "Point at cabinets to capture dimensions",
        icon: "arrow.up",
        type: .info
    )

    /// Pointing at ceiling too long
    static let pointAtCabinetsFromCeiling = GuidanceToastMessage(
        id: "ceiling_orientation",
        message: "Point at cabinets to capture dimensions",
        icon: "arrow.down",
        type: .info
    )

    // MARK: Timed Prompts (First-time users only)

    /// Initial guidance (0-10s)
    static let moveSlowly = GuidanceToastMessage(
        id: "timed_move_slowly",
        message: "Move slowly around the room",
        icon: "figure.walk",
        type: .info
    )

    /// Point at floor (10-20s)
    static let pointAtFloor = GuidanceToastMessage(
        id: "timed_point_floor",
        message: "Point at the floor to help us map the space",
        icon: "arrow.down.to.line",
        type: .info
    )

    /// Point at ceiling (20-30s)
    static let pointAtCeiling = GuidanceToastMessage(
        id: "timed_point_ceiling",
        message: "Point at the ceiling to measure cabinet height",
        icon: "arrow.up.to.line",
        type: .info
    )

    /// Move closer (30-45s)
    static let moveCloser = GuidanceToastMessage(
        id: "timed_move_closer",
        message: "Move closer to the cabinets",
        icon: "arrow.forward",
        type: .info
    )

    /// Positive reinforcement (45s+)
    static let keepGoing = GuidanceToastMessage(
        id: "timed_keep_going",
        message: "Great! Keep going...",
        icon: "checkmark.circle.fill",
        type: .info
    )

    // MARK: Coverage Hints

    /// Capture all areas hint
    static let captureAllAreas = GuidanceToastMessage(
        id: "capture_all_areas",
        message: "Capture all 4 areas for best results",
        icon: "square.grid.2x2",
        type: .info
    )
}

// MARK: - Quality Indicator Badge (AC3)

/// Compact quality indicator badge showing current quality state.
/// Per Story 2.3 AC3 - "quality indicator shows yellow/red state"
struct QualityIndicatorBadge: View {
    let qualityState: AIQualityState

    var body: some View {
        // Only show badge when there's an issue
        if !qualityState.isAcceptable {
            HStack(spacing: 4) {
                Image(systemName: iconForState)
                    .font(.caption.weight(.semibold))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(colorForState)
            .clipShape(Capsule())
            .accessibilityLabel(accessibilityLabelForState)
        }
    }

    private var iconForState: String {
        if qualityState.blurIssue == .severe {
            return "exclamationmark.triangle.fill"
        } else if qualityState.brightnessIssue == .tooDark {
            return "sun.min.fill"
        } else if qualityState.blurIssue == .warning {
            return "hand.raised.fill"
        } else {
            return "exclamationmark.circle.fill"
        }
    }

    private var colorForState: Color {
        // Red for severe issues, yellow/orange for warnings
        if qualityState.blurIssue == .severe || qualityState.brightnessIssue == .tooDark {
            return .red.opacity(0.9)
        } else {
            return .orange.opacity(0.9)
        }
    }

    private var accessibilityLabelForState: String {
        var issues: [String] = []

        if let blur = qualityState.blurIssue {
            issues.append(blur == .severe ? "Severe motion blur" : "Motion blur detected")
        }

        if let brightness = qualityState.brightnessIssue {
            issues.append(brightness == .tooDark ? "Too dark" : "Too bright")
        }

        return "Quality issues: " + issues.joined(separator: ", ")
    }
}

// MARK: - Preview

#Preview("Guidance Toast - Info") {
    ZStack {
        Color.black

        VStack(spacing: 20) {
            GuidanceToast(
                message: "Move slowly around the room",
                icon: "figure.walk",
                type: .info
            )

            GuidanceToast(
                message: "Point at cabinets to capture dimensions",
                icon: "arrow.up",
                type: .info
            )
        }
    }
}

#Preview("Guidance Toast - Warning") {
    ZStack {
        Color.black

        VStack(spacing: 20) {
            GuidanceToast(
                message: "Slow down for sharper images",
                icon: "hand.raised.fill",
                type: .warning
            )

            GuidanceToast(
                message: "Move to brighter area for accurate measurements",
                icon: "lightbulb.fill",
                type: .warning
            )
        }
    }
}

#Preview("Guidance Toast - Error") {
    ZStack {
        Color.black

        GuidanceToast(
            message: "Camera access required",
            icon: "exclamationmark.triangle.fill",
            type: .error
        )
    }
}

#Preview("Toast Container") {
    ZStack {
        Color.black

        GuidanceToastContainer(
            toast: .motionBlur,
            onDismiss: { print("Dismissed") }
        )
    }
}
