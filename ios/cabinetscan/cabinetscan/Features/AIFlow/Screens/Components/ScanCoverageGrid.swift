//
//  ScanCoverageGrid.swift
//  cabinetscan
//
//  Created for scan coverage visualization
//

import SwiftUI
import Combine

// MARK: - Scan Coverage Grid Manager

/// Manages the grid-based coverage tracking for the camera view.
/// Tracks which cells of the view have been scanned based on captured zones.
@MainActor
class ScanCoverageGridManager: ObservableObject {

    // MARK: - Configuration

    /// Number of columns in the grid
    static let columns = 4

    /// Number of rows in the grid
    static let rows = 5

    /// Total number of cells
    static let totalCells = columns * rows

    // MARK: - Published Properties

    /// Set of scanned cell indices (0 to totalCells-1)
    @Published private(set) var scannedCells: Set<Int> = []

    /// Currently active cell (where camera is pointing)
    @Published private(set) var activeCell: Int? = nil

    /// Coverage percentage (0.0 to 1.0)
    var coveragePercentage: Float {
        Float(scannedCells.count) / Float(Self.totalCells)
    }

    /// Whether coverage is complete (all cells scanned)
    var isComplete: Bool {
        scannedCells.count >= Self.totalCells
    }

    // MARK: - Private State

    /// Whether tracking is active
    private var isTracking = false

    /// Timer for progressive cell scanning
    private var scanTimer: Timer?

    /// Current scan progress within active zone
    private var zoneScanProgress: [AICaptureZone: Int] = [:]

    /// Current zone being scanned
    private var currentZone: AICaptureZone = .front

    // MARK: - Zone to Cell Mapping

    /// Maps each zone to specific grid cells
    /// Grid layout (4 cols x 5 rows = 20 cells):
    /// Row 0: [0,  1,  2,  3 ] - Top
    /// Row 1: [4,  5,  6,  7 ]
    /// Row 2: [8,  9,  10, 11] - Center
    /// Row 3: [12, 13, 14, 15]
    /// Row 4: [16, 17, 18, 19] - Bottom

    private func cellsForZone(_ zone: AICaptureZone) -> [Int] {
        switch zone {
        case .front:
            // Front zone - top portion of screen
            return [0, 1, 2, 3, 4, 5]
        case .right:
            // Right zone - right side of screen
            return [3, 7, 11, 15, 19, 6, 10]
        case .back:
            // Back zone - bottom portion of screen
            return [14, 15, 16, 17, 18, 19, 12, 13]
        case .left:
            // Left zone - left side of screen
            return [0, 4, 8, 12, 16, 1, 5, 9]
        }
    }

    // MARK: - Initialization

    init() {}

    deinit {
        scanTimer?.invalidate()
    }

    // MARK: - Public Methods

    /// Start tracking coverage
    func startTracking() {
        isTracking = true
        scannedCells = []
        zoneScanProgress = [:]
        activeCell = 10 // Center cell

        // Start progressive scanning timer
        scanTimer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.progressiveScan()
            }
        }

        print("[ScanCoverageGrid] Started tracking")
    }

    /// Stop tracking coverage
    func stopTracking() {
        isTracking = false
        scanTimer?.invalidate()
        scanTimer = nil
        print("[ScanCoverageGrid] Stopped tracking - \(scannedCells.count)/\(Self.totalCells) cells scanned")
    }

    /// Update grid based on captured zones from guidance system
    func updateFromCapturedZones(_ zones: Set<AICaptureZone>) {
        guard isTracking else { return }

        // Update current zone to the first uncaptured zone or stay on current
        if let nextUncaptured = AICaptureZone.allCases.first(where: { !zones.contains($0) }) {
            currentZone = nextUncaptured
        }

        // Mark cells for captured zones
        for zone in zones {
            let cells = cellsForZone(zone)
            for cell in cells {
                if !scannedCells.contains(cell) {
                    scannedCells.insert(cell)
                }
            }
        }
    }

    /// Update active cell based on guidance direction
    func updateActiveFromDirection(_ direction: AIGuidanceDirection?) {
        guard isTracking else { return }

        // Move active cell toward the suggested direction
        guard let direction = direction else {
            activeCell = 10 // Center
            return
        }

        switch direction {
        case .forward:
            activeCell = 1 // Top center
        case .right:
            activeCell = 11 // Right center
        case .backward:
            activeCell = 17 // Bottom center
        case .left:
            activeCell = 8 // Left center
        }
    }

    /// Manually mark a cell as scanned (for testing)
    func markCellScanned(_ index: Int) {
        guard index >= 0 && index < Self.totalCells else { return }
        scannedCells.insert(index)
    }

    /// Reset all coverage
    func reset() {
        scannedCells = []
        zoneScanProgress = [:]
        activeCell = nil
    }

    // MARK: - Private Methods

    /// Progressive scanning - gradually fills in cells as user scans
    private func progressiveScan() {
        guard isTracking else { return }

        // Get cells for current zone
        let zoneCells = cellsForZone(currentZone)
        let progress = zoneScanProgress[currentZone, default: 0]

        // Mark next cell in zone as scanned
        if progress < zoneCells.count {
            let cellToScan = zoneCells[progress]
            activeCell = cellToScan

            // Mark as scanned after dwelling
            if !scannedCells.contains(cellToScan) {
                scannedCells.insert(cellToScan)
            }

            zoneScanProgress[currentZone] = progress + 1
        } else {
            // Move to next zone if current is done
            if let nextZone = AICaptureZone.allCases.first(where: { zoneScanProgress[$0, default: 0] < cellsForZone($0).count }) {
                currentZone = nextZone
            }
        }
    }
}

// MARK: - Scan Coverage Grid View

/// Grid overlay showing scanned vs unscanned areas of the camera view
struct ScanCoverageGrid: View {

    /// The grid manager tracking coverage
    @ObservedObject var gridManager: ScanCoverageGridManager

    /// Opacity of the grid overlay
    var gridOpacity: Double = 0.6

    /// Story 6.5: Reduce Motion accessibility preference
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let columns = ScanCoverageGridManager.columns
    private let rows = ScanCoverageGridManager.rows

    var body: some View {
        GeometryReader { geometry in
            let cellWidth = geometry.size.width / CGFloat(columns)
            let cellHeight = geometry.size.height / CGFloat(rows)

            ZStack {
                // Grid cells
                ForEach(0..<rows, id: \.self) { row in
                    ForEach(0..<columns, id: \.self) { col in
                        let cellIndex = row * columns + col
                        let isScanned = gridManager.scannedCells.contains(cellIndex)
                        let isActive = gridManager.activeCell == cellIndex

                        GridCell(
                            isScanned: isScanned,
                            isActive: isActive,
                            reduceMotion: reduceMotion
                        )
                        .frame(width: cellWidth, height: cellHeight)
                        .position(
                            x: CGFloat(col) * cellWidth + cellWidth / 2,
                            y: CGFloat(row) * cellHeight + cellHeight / 2
                        )
                    }
                }

                // Coverage progress indicator at top
                VStack {
                    CoverageProgressIndicator(
                        scannedCount: gridManager.scannedCells.count,
                        totalCount: ScanCoverageGridManager.totalCells,
                        isComplete: gridManager.isComplete
                    )
                    .padding(.top, 70)
                    .padding(.horizontal, 60)

                    Spacer()
                }
            }
        }
        .allowsHitTesting(false) // Don't interfere with camera gestures
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Scan coverage grid")
        .accessibilityValue("\(gridManager.scannedCells.count) of \(ScanCoverageGridManager.totalCells) areas scanned")
    }
}

// MARK: - Grid Cell View

/// Individual cell in the coverage grid
private struct GridCell: View {
    let isScanned: Bool
    let isActive: Bool
    let reduceMotion: Bool

    var body: some View {
        ZStack {
            // Cell background
            Rectangle()
                .fill(cellFillColor)

            // Cell border
            Rectangle()
                .stroke(cellBorderColor, lineWidth: isActive ? 2 : 1)

            // Checkmark for scanned cells
            if isScanned {
                Image(systemName: "checkmark")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(Color.white.opacity(0.8))
            }
        }
        .animation(reduceMotion ? .none : .easeInOut(duration: 0.2), value: isScanned)
        .animation(reduceMotion ? .none : .easeInOut(duration: 0.1), value: isActive)
    }

    private var cellFillColor: Color {
        if isScanned {
            return Color.green.opacity(0.35)
        } else if isActive {
            return Color.orange.opacity(0.25)
        } else {
            return Color.clear
        }
    }

    private var cellBorderColor: Color {
        if isScanned {
            return Color.green.opacity(0.7)
        } else if isActive {
            return Color.orange.opacity(0.8)
        } else {
            return Color.white.opacity(0.3)
        }
    }
}

// MARK: - Coverage Progress Indicator

/// Shows overall scan coverage progress
private struct CoverageProgressIndicator: View {
    let scannedCount: Int
    let totalCount: Int
    let isComplete: Bool

    private var percentage: Int {
        guard totalCount > 0 else { return 0 }
        return Int((Float(scannedCount) / Float(totalCount)) * 100)
    }

    var body: some View {
        HStack(spacing: 12) {
            // Progress bar
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    // Background
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.black.opacity(0.5))

                    // Progress fill
                    RoundedRectangle(cornerRadius: 4)
                        .fill(isComplete ? Color.green : Color.blue)
                        .frame(width: geometry.size.width * CGFloat(scannedCount) / CGFloat(totalCount))
                }
            }
            .frame(height: 8)

            // Percentage text
            Text("\(percentage)%")
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .frame(width: 45, alignment: .trailing)

            // Completion checkmark
            if isComplete {
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

#Preview("Grid - Empty") {
    ZStack {
        Color.gray

        ScanCoverageGrid(gridManager: {
            let manager = ScanCoverageGridManager()
            return manager
        }())
    }
    .ignoresSafeArea()
}

#Preview("Grid - Partial") {
    ZStack {
        Color.gray

        ScanCoverageGrid(gridManager: {
            let manager = ScanCoverageGridManager()
            manager.markCellScanned(0)
            manager.markCellScanned(1)
            manager.markCellScanned(4)
            manager.markCellScanned(5)
            manager.markCellScanned(8)
            return manager
        }())
    }
    .ignoresSafeArea()
}

#Preview("Grid - Complete") {
    ZStack {
        Color.gray

        ScanCoverageGrid(gridManager: {
            let manager = ScanCoverageGridManager()
            for i in 0..<ScanCoverageGridManager.totalCells {
                manager.markCellScanned(i)
            }
            return manager
        }())
    }
    .ignoresSafeArea()
}
