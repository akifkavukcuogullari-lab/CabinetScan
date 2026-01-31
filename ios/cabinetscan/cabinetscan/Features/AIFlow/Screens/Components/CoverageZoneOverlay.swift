//
//  CoverageZoneOverlay.swift
//  cabinetscan
//
//  Created for coverage visualization feature
//

import SwiftUI

// MARK: - Coverage Zone Overlay

/// A mini-map style overlay showing scan coverage for the 4 directional zones.
/// Displays which areas (front, right, back, left) have been captured during scanning.
///
/// **Features:**
/// - Radar/compass style visualization
/// - Green zones for captured areas
/// - Gray zones for uncaptured areas
/// - Pulsing indicator for current facing direction
/// - Real-time updates as user scans
struct CoverageZoneOverlay: View {
    /// Set of captured zones
    let capturedZones: Set<AICaptureZone>

    /// Current guidance direction (where user should scan next)
    let guidanceDirection: AIGuidanceDirection?

    /// Size of the overlay
    private let overlaySize: CGFloat = 120

    /// Story 6.5: Reduce Motion accessibility preference
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Animation state for pulsing effect
    @State private var isPulsing = false

    var body: some View {
        ZStack {
            // Background circle
            Circle()
                .fill(Color.black.opacity(0.6))
                .frame(width: overlaySize, height: overlaySize)

            // Zone segments
            ZStack {
                // Front zone (top)
                ZoneSegment(
                    zone: .front,
                    isCaptured: capturedZones.contains(.front),
                    isTarget: guidanceDirection == .forward,
                    startAngle: -135,
                    endAngle: -45
                )

                // Right zone
                ZoneSegment(
                    zone: .right,
                    isCaptured: capturedZones.contains(.right),
                    isTarget: guidanceDirection == .right,
                    startAngle: -45,
                    endAngle: 45
                )

                // Back zone (bottom)
                ZoneSegment(
                    zone: .back,
                    isCaptured: capturedZones.contains(.back),
                    isTarget: guidanceDirection == .backward,
                    startAngle: 45,
                    endAngle: 135
                )

                // Left zone
                ZoneSegment(
                    zone: .left,
                    isCaptured: capturedZones.contains(.left),
                    isTarget: guidanceDirection == .left,
                    startAngle: 135,
                    endAngle: 225
                )
            }
            .frame(width: overlaySize - 20, height: overlaySize - 20)

            // Center dot (represents camera/user position)
            Circle()
                .fill(Color.white)
                .frame(width: 12, height: 12)
                .shadow(color: .black.opacity(0.3), radius: 2)

            // Camera direction indicator (small triangle pointing up)
            Triangle()
                .fill(Color.white)
                .frame(width: 8, height: 10)
                .offset(y: -18)

            // Coverage percentage text
            VStack {
                Spacer()
                Text("\(coveragePercentage)%")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .padding(.bottom, 8)
            }
            .frame(width: overlaySize, height: overlaySize)
        }
        .overlay(
            // Pulsing ring for target zone
            Circle()
                .stroke(Color.orange.opacity(isPulsing ? 0.6 : 0), lineWidth: 2)
                .frame(width: overlaySize + 4, height: overlaySize + 4)
                .scaleEffect(isPulsing ? 1.1 : 1.0)
        )
        .onAppear {
            if !reduceMotion && guidanceDirection != nil {
                withAnimation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true)) {
                    isPulsing = true
                }
            }
        }
        .onChange(of: guidanceDirection) { _, newDirection in
            if !reduceMotion && newDirection != nil {
                withAnimation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true)) {
                    isPulsing = true
                }
            } else {
                isPulsing = false
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Coverage map")
        .accessibilityValue("\(capturedZones.count) of 4 areas scanned, \(coveragePercentage) percent complete")
    }

    private var coveragePercentage: Int {
        Int((Float(capturedZones.count) / 4.0) * 100)
    }
}

// MARK: - Zone Segment

/// Individual zone segment in the coverage overlay
private struct ZoneSegment: View {
    let zone: AICaptureZone
    let isCaptured: Bool
    let isTarget: Bool
    let startAngle: Double
    let endAngle: Double

    /// Story 6.5: Reduce Motion accessibility preference
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geometry in
            let center = CGPoint(x: geometry.size.width / 2, y: geometry.size.height / 2)
            let radius = min(geometry.size.width, geometry.size.height) / 2

            Path { path in
                path.move(to: center)
                path.addArc(
                    center: center,
                    radius: radius,
                    startAngle: .degrees(startAngle),
                    endAngle: .degrees(endAngle),
                    clockwise: false
                )
                path.closeSubpath()
            }
            .fill(segmentColor)
            .overlay(
                Path { path in
                    path.move(to: center)
                    path.addArc(
                        center: center,
                        radius: radius,
                        startAngle: .degrees(startAngle),
                        endAngle: .degrees(endAngle),
                        clockwise: false
                    )
                    path.closeSubpath()
                }
                .stroke(borderColor, lineWidth: 1)
            )
        }
        .animation(reduceMotion ? .none : .easeInOut(duration: 0.3), value: isCaptured)
    }

    private var segmentColor: Color {
        if isCaptured {
            return Color.green.opacity(0.7)
        } else if isTarget {
            return Color.orange.opacity(0.5)
        } else {
            return Color.gray.opacity(0.3)
        }
    }

    private var borderColor: Color {
        if isCaptured {
            return Color.green.opacity(0.9)
        } else if isTarget {
            return Color.orange.opacity(0.8)
        } else {
            return Color.white.opacity(0.3)
        }
    }
}

// MARK: - Triangle Shape

/// Simple triangle shape for direction indicator
private struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

// MARK: - Coverage Zone Container

/// Container for positioning the coverage zone overlay on screen
struct CoverageZoneContainer: View {
    let capturedZones: Set<AICaptureZone>
    let guidanceDirection: AIGuidanceDirection?

    /// Whether the overlay is expanded (shows zone labels)
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .trailing, spacing: 8) {
            CoverageZoneOverlay(
                capturedZones: capturedZones,
                guidanceDirection: guidanceDirection
            )
            .onTapGesture {
                withAnimation(.spring(response: 0.3)) {
                    isExpanded.toggle()
                }
            }

            // Expanded legend (shown on tap)
            if isExpanded {
                VStack(alignment: .leading, spacing: 4) {
                    legendRow(zone: .front, label: "Front")
                    legendRow(zone: .right, label: "Right")
                    legendRow(zone: .back, label: "Back")
                    legendRow(zone: .left, label: "Left")
                }
                .padding(8)
                .background(Color.black.opacity(0.7))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .transition(.opacity.combined(with: .scale(scale: 0.8, anchor: .topTrailing)))
            }
        }
    }

    @ViewBuilder
    private func legendRow(zone: AICaptureZone, label: String) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(capturedZones.contains(zone) ? Color.green : Color.gray.opacity(0.5))
                .frame(width: 10, height: 10)

            Text(label)
                .font(.caption2)
                .foregroundStyle(.white)

            if capturedZones.contains(zone) {
                Image(systemName: "checkmark")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.green)
            }
        }
    }
}

// MARK: - Preview

#Preview("Coverage Overlay - Empty") {
    ZStack {
        Color.black
        CoverageZoneOverlay(
            capturedZones: [],
            guidanceDirection: .forward
        )
    }
}

#Preview("Coverage Overlay - Partial") {
    ZStack {
        Color.black
        CoverageZoneOverlay(
            capturedZones: [.front, .right],
            guidanceDirection: .backward
        )
    }
}

#Preview("Coverage Overlay - Complete") {
    ZStack {
        Color.black
        CoverageZoneOverlay(
            capturedZones: Set(AICaptureZone.allCases),
            guidanceDirection: nil
        )
    }
}

#Preview("Coverage Container") {
    ZStack {
        Color.black

        VStack {
            HStack {
                Spacer()
                CoverageZoneContainer(
                    capturedZones: [.front],
                    guidanceDirection: .right
                )
                .padding()
            }
            Spacer()
        }
    }
}
