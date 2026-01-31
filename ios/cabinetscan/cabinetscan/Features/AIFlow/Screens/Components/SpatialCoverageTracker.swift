//
//  SpatialCoverageTracker.swift
//  cabinetscan
//
//  Tracks scan coverage in actual 3D room space
//

import SwiftUI
import simd
import Combine

// MARK: - Spatial Coverage Tracker

/// Tracks scan coverage in physical room space using AR camera position.
/// Creates a floor-plan style grid representing the room from above.
/// Marks cells as scanned when the camera has viewed that area.
@MainActor
class SpatialCoverageTracker: ObservableObject {

    // MARK: - Configuration

    /// Size of each grid cell in meters
    static let cellSizeMeters: Float = 0.5 // 50cm per cell

    /// Grid dimensions (centered on starting position)
    static let gridWidth = 20  // 10 meters total width
    static let gridHeight = 20 // 10 meters total depth

    /// Total cells
    static let totalCells = gridWidth * gridHeight

    /// View distance - how far the camera can "scan" in meters
    private let viewDistance: Float = 3.0

    /// Field of view angle (radians) - 60 degrees
    private let fieldOfView: Float = 1.047

    // MARK: - Published Properties

    /// Set of scanned cell indices
    @Published private(set) var scannedCells: Set<Int> = []

    /// Current camera position cell
    @Published private(set) var cameraCell: Int? = nil

    /// Cells currently in view (but not yet scanned)
    @Published private(set) var viewingCells: Set<Int> = []

    /// Starting position (world origin)
    @Published private(set) var originPosition: SIMD3<Float>? = nil

    /// Coverage percentage
    var coveragePercentage: Float {
        Float(scannedCells.count) / Float(Self.totalCells)
    }

    // MARK: - Private State

    /// Whether tracking is active
    private var isTracking = false

    /// Dwell time per cell (for scanning threshold)
    private var cellDwellTime: [Int: TimeInterval] = [:]

    /// Minimum dwell time to mark as scanned
    private let dwellThreshold: TimeInterval = 0.3

    /// Last update time
    private var lastUpdateTime: Date?

    /// AR session manager reference
    private weak var sessionManager: AIARSessionManager?

    /// Pose subscription
    private var poseSubscription: AnyCancellable?

    // MARK: - Initialization

    init() {}

    // MARK: - Public Methods

    /// Start tracking with AR session
    func startTracking(sessionManager: AIARSessionManager) {
        self.sessionManager = sessionManager
        isTracking = true
        scannedCells = []
        viewingCells = []
        cellDwellTime = [:]
        originPosition = nil
        lastUpdateTime = Date()

        // Subscribe to pose updates
        poseSubscription = sessionManager.poseUpdatePublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] (timestamp, pose) in
                self?.processPose(pose, timestamp: timestamp)
            }

        print("[SpatialCoverage] Started tracking")
    }

    /// Stop tracking
    func stopTracking() {
        isTracking = false
        poseSubscription?.cancel()
        poseSubscription = nil
        print("[SpatialCoverage] Stopped - \(scannedCells.count) cells scanned")
    }

    /// Process AR pose update
    func processPose(_ pose: AIPose, timestamp: TimeInterval) {
        guard isTracking else { return }

        let now = Date()
        let deltaTime = lastUpdateTime.map { now.timeIntervalSince($0) } ?? 0
        lastUpdateTime = now

        // Get camera position from transform
        let position = SIMD3<Float>(
            pose.transform.columns.3.x,
            pose.transform.columns.3.y,
            pose.transform.columns.3.z
        )

        // Set origin on first pose
        if originPosition == nil {
            originPosition = position
            print("[SpatialCoverage] Origin set at \(position)")
        }

        guard let origin = originPosition else { return }

        // Get camera facing direction (forward vector)
        let forward = -SIMD3<Float>(
            pose.transform.columns.2.x,
            pose.transform.columns.2.y,
            pose.transform.columns.2.z
        )

        // Calculate relative position from origin
        let relativePos = position - origin

        // Convert position to grid cell
        cameraCell = positionToCell(relativePos)

        // Calculate cells in view cone
        let inViewCells = calculateViewCone(
            from: relativePos,
            direction: forward,
            distance: viewDistance,
            fov: fieldOfView
        )

        viewingCells = inViewCells.subtracting(scannedCells)

        // Accumulate dwell time for cells in view
        for cell in inViewCells {
            cellDwellTime[cell, default: 0] += deltaTime

            // Mark as scanned after dwell threshold
            if cellDwellTime[cell, default: 0] >= dwellThreshold {
                if !scannedCells.contains(cell) {
                    scannedCells.insert(cell)
                }
            }
        }
    }

    /// Mark cells as scanned (for preview/testing only)
    func markCellsScannedForPreview(_ cells: [Int]) {
        for cell in cells where cell >= 0 && cell < Self.totalCells {
            scannedCells.insert(cell)
        }
    }

    /// Manual update for testing without AR
    func simulatePosition(_ position: SIMD3<Float>, direction: SIMD3<Float>) {
        guard isTracking else { return }

        if originPosition == nil {
            originPosition = .zero
        }

        cameraCell = positionToCell(position)

        let inViewCells = calculateViewCone(
            from: position,
            direction: direction,
            distance: viewDistance,
            fov: fieldOfView
        )

        viewingCells = inViewCells.subtracting(scannedCells)

        // Mark all in-view cells as scanned for testing
        for cell in inViewCells {
            scannedCells.insert(cell)
        }
    }

    // MARK: - Private Methods

    /// Convert world position to grid cell index
    private func positionToCell(_ position: SIMD3<Float>) -> Int {
        // Use X and Z for floor plan (Y is up)
        let gridX = Int((position.x / Self.cellSizeMeters) + Float(Self.gridWidth / 2))
        let gridZ = Int((position.z / Self.cellSizeMeters) + Float(Self.gridHeight / 2))

        // Clamp to grid bounds
        let clampedX = max(0, min(Self.gridWidth - 1, gridX))
        let clampedZ = max(0, min(Self.gridHeight - 1, gridZ))

        return clampedZ * Self.gridWidth + clampedX
    }

    /// Calculate cells within the view cone
    private func calculateViewCone(
        from position: SIMD3<Float>,
        direction: SIMD3<Float>,
        distance: Float,
        fov: Float
    ) -> Set<Int> {
        var cells = Set<Int>()

        // Normalize direction (use X and Z for floor plan)
        let dir2D = SIMD2<Float>(direction.x, direction.z)
        let normalizedDir = simd_normalize(dir2D)

        // Sample points in the view cone
        let angleStep: Float = 0.1 // radians
        let distanceStep: Float = Self.cellSizeMeters

        for angleOffset in stride(from: -fov/2, through: fov/2, by: angleStep) {
            // Rotate direction by angle offset
            let cos = cosf(angleOffset)
            let sin = sinf(angleOffset)
            let rotatedDir = SIMD2<Float>(
                normalizedDir.x * cos - normalizedDir.y * sin,
                normalizedDir.x * sin + normalizedDir.y * cos
            )

            // Sample along this ray
            for dist in stride(from: 0, through: distance, by: distanceStep) {
                let samplePos = SIMD3<Float>(
                    position.x + rotatedDir.x * dist,
                    position.y,
                    position.z + rotatedDir.y * dist
                )

                let cell = positionToCell(samplePos)
                cells.insert(cell)
            }
        }

        return cells
    }
}

// MARK: - Spatial Coverage Mini Map View

/// Mini-map showing room coverage from top-down view
struct SpatialCoverageMiniMap: View {
    @ObservedObject var tracker: SpatialCoverageTracker

    /// Size of the mini-map
    var mapSize: CGFloat = 150

    /// Story 6.5: Reduce Motion accessibility preference
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let gridWidth = SpatialCoverageTracker.gridWidth
    private let gridHeight = SpatialCoverageTracker.gridHeight

    var body: some View {
        ZStack {
            // Background
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.black.opacity(0.7))
                .frame(width: mapSize + 20, height: mapSize + 40)

            VStack(spacing: 4) {
                // Title
                Text("Room Coverage")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.white)

                // Grid
                Canvas { context, size in
                    let cellWidth = size.width / CGFloat(gridWidth)
                    let cellHeight = size.height / CGFloat(gridHeight)

                    // Draw cells
                    for row in 0..<gridHeight {
                        for col in 0..<gridWidth {
                            let cellIndex = row * gridWidth + col
                            let rect = CGRect(
                                x: CGFloat(col) * cellWidth,
                                y: CGFloat(row) * cellHeight,
                                width: cellWidth,
                                height: cellHeight
                            )

                            // Cell color based on state
                            let color: Color
                            if tracker.scannedCells.contains(cellIndex) {
                                color = .green.opacity(0.6)
                            } else if tracker.viewingCells.contains(cellIndex) {
                                color = .orange.opacity(0.5)
                            } else {
                                color = .gray.opacity(0.2)
                            }

                            context.fill(
                                Path(rect),
                                with: .color(color)
                            )

                            // Cell border
                            context.stroke(
                                Path(rect),
                                with: .color(.white.opacity(0.1)),
                                lineWidth: 0.5
                            )
                        }
                    }

                    // Draw camera position
                    if let cameraCell = tracker.cameraCell {
                        let row = cameraCell / gridWidth
                        let col = cameraCell % gridWidth
                        let centerX = CGFloat(col) * cellWidth + cellWidth / 2
                        let centerY = CGFloat(row) * cellHeight + cellHeight / 2

                        // Camera dot
                        let dotSize: CGFloat = 6
                        let dotRect = CGRect(
                            x: centerX - dotSize / 2,
                            y: centerY - dotSize / 2,
                            width: dotSize,
                            height: dotSize
                        )
                        context.fill(
                            Path(ellipseIn: dotRect),
                            with: .color(.blue)
                        )
                    }
                }
                .frame(width: mapSize, height: mapSize)
                .clipShape(RoundedRectangle(cornerRadius: 8))

                // Coverage percentage
                HStack(spacing: 4) {
                    Text("\(Int(tracker.coveragePercentage * 100))%")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)

                    Text("scanned")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.7))
                }
            }
            .padding(10)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Room coverage map")
        .accessibilityValue("\(Int(tracker.coveragePercentage * 100)) percent of room scanned")
    }
}

// MARK: - Spatial Coverage Screen Overlay

/// Full-screen overlay showing spatial coverage projected onto camera view
struct SpatialCoverageScreenOverlay: View {
    @ObservedObject var tracker: SpatialCoverageTracker

    /// Story 6.5: Reduce Motion accessibility preference
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Coverage progress at top
                VStack {
                    CoverageStatusBar(
                        percentage: tracker.coveragePercentage,
                        scannedCount: tracker.scannedCells.count
                    )
                    .padding(.top, 70)
                    .padding(.horizontal, 40)

                    Spacer()
                }

                // Mini-map in corner
                VStack {
                    HStack {
                        Spacer()
                        SpatialCoverageMiniMap(tracker: tracker)
                            .padding(.trailing, 16)
                            .padding(.top, 120)
                    }
                    Spacer()
                }

                // Visual indicator for unscanned area
                if !tracker.viewingCells.isEmpty && tracker.viewingCells.count > 5 {
                    VStack {
                        Spacer()

                        HStack(spacing: 8) {
                            Image(systemName: "viewfinder")
                                .font(.body.weight(.semibold))

                            Text("New area detected - keep scanning")
                                .font(.subheadline.weight(.medium))
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(Color.orange.opacity(0.9))
                        .clipShape(Capsule())
                        .padding(.bottom, 200)
                    }
                    .transition(.opacity)
                    .animation(reduceMotion ? .none : .easeInOut, value: tracker.viewingCells.count)
                }
            }
        }
        .allowsHitTesting(false)
    }
}

// MARK: - Coverage Status Bar

private struct CoverageStatusBar: View {
    let percentage: Float
    let scannedCount: Int

    var body: some View {
        HStack(spacing: 12) {
            // Progress bar
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.black.opacity(0.5))

                    RoundedRectangle(cornerRadius: 4)
                        .fill(percentage >= 0.8 ? Color.green : Color.blue)
                        .frame(width: geometry.size.width * CGFloat(percentage))
                }
            }
            .frame(height: 8)

            // Percentage
            Text("\(Int(percentage * 100))%")
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .frame(width: 45, alignment: .trailing)

            // Completion indicator
            if percentage >= 0.8 {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(.green)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.black.opacity(0.6))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Preview

#Preview("Mini Map") {
    ZStack {
        Color.gray

        SpatialCoverageMiniMap(tracker: {
            let tracker = SpatialCoverageTracker()
            // Simulate some scanned cells using internal method
            tracker.markCellsScannedForPreview([45, 46, 47, 65, 66, 67, 85, 86, 87, 105, 106, 107])
            return tracker
        }())
    }
}

#Preview("Screen Overlay") {
    ZStack {
        Color.gray

        SpatialCoverageScreenOverlay(tracker: {
            let tracker = SpatialCoverageTracker()
            tracker.markCellsScannedForPreview(Array(stride(from: 0, to: 200, by: 4)))
            return tracker
        }())
    }
    .ignoresSafeArea()
}
