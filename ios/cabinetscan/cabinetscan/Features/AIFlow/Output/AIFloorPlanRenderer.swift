//
//  AIFloorPlanRenderer.swift
//  cabinetscan
//
//  Created for Story 5.1: Floor Plan Image Renderer
//

import Foundation
import UIKit
import simd

// MARK: - Floor Plan Render Result

/// Result of floor plan rendering operation.
///
/// Contains the rendered PNG image data and metadata about what was rendered.
/// Used to generate the preview image for MeasurementData.previewImageUrl.
struct FloorPlanRenderResult {
    /// PNG image data at 300 DPI
    let pngData: Data

    /// Size of the rendered image in points
    let imageSize: CGSize

    /// DPI of the rendered image
    let dpi: Int

    /// Metadata about what was rendered
    let metadata: FloorPlanMetadata

    /// Processing time in milliseconds
    let processingTimeMs: Int
}

// MARK: - Floor Plan Metadata

/// Metadata describing what elements were rendered in the floor plan.
struct FloorPlanMetadata {
    /// Room shape classification
    let roomShape: RoomShape

    /// Elements that were successfully rendered
    let elementsRendered: Set<FloorPlanElement>

    /// Number of walls rendered
    let wallCount: Int

    /// Cabinet counts by type
    let cabinetCounts: [AICabinetType: Int]

    /// Number of appliances rendered
    let applianceCount: Int

    /// Number of windows rendered
    let windowCount: Int

    /// Number of doors rendered
    let doorCount: Int

    /// Number of islands rendered
    let islandCount: Int

    /// Number of peninsulas rendered
    let peninsulaCount: Int

    /// Description of the scale (e.g., "1 inch = 2 feet")
    let scaleDescription: String?

    /// Warnings generated during rendering
    let warnings: [String]

    /// Coverage percentage from capture phase (Story 6.2)
    /// nil means full coverage or unknown
    let coveragePercentage: Float?

    /// Zones that were not captured (Story 6.2)
    let uncapturedZones: Set<AICaptureZone>?
}

// MARK: - Floor Plan Element

/// Elements that can be rendered in a floor plan.
enum FloorPlanElement: String, CaseIterable {
    case roomBoundary
    case wallDimensions
    case baseCabinets
    case upperCabinets
    case tallCabinets
    case cornerCabinets
    case specialCabinets
    case appliances
    case windows
    case doors
    case islands
    case peninsulas
    case countertops
    case scaleIndicator
    case orientationIndicator
    case unscannedAreas  // Story 6.2: Hatched areas for partial capture
}

// MARK: - Floor Plan Transform

/// Coordinate transformation from world coordinates to screen coordinates.
///
/// **World Coordinates (from AIRoomStructure):**
/// - Origin: Room corner (varies)
/// - Units: Inches
/// - X-axis: Horizontal (width)
/// - Z-axis: Horizontal (length) - Used for top-down view
/// - Y-axis: Vertical (height) - Ignored for floor plan
///
/// **Screen Coordinates (Core Graphics):**
/// - Origin: Top-left corner
/// - Units: Points (scaled for DPI)
/// - X-axis: Horizontal (increases right)
/// - Y-axis: Vertical (increases down)
struct FloorPlanTransform {
    /// Scale factor from world inches to screen points
    let scale: CGFloat

    /// Offset to center room in canvas
    let offset: CGPoint

    /// Canvas size in points
    let canvasSize: CGSize

    /// Margin around the floor plan
    let margin: CGFloat

    /// Bounding box of the room in world coordinates
    let worldBounds: CGRect

    /// Initializes transform from room structure and canvas parameters.
    ///
    /// - Parameters:
    ///   - roomStructure: Room structure containing boundary polygon
    ///   - canvasSize: Target canvas size in points
    ///   - margin: Margin around the floor plan in points
    init(roomStructure: AIRoomStructure, canvasSize: CGSize, margin: CGFloat = 50) {
        self.canvasSize = canvasSize
        self.margin = margin

        // Calculate bounding box from boundary polygon
        if roomStructure.boundaryPolygon.isEmpty {
            // Fallback for empty room
            self.worldBounds = CGRect(x: 0, y: 0, width: 144, height: 144)
        } else {
            var minX: Float = .infinity
            var maxX: Float = -.infinity
            var minZ: Float = .infinity
            var maxZ: Float = -.infinity

            for point in roomStructure.boundaryPolygon {
                minX = min(minX, point.x)
                maxX = max(maxX, point.x)
                minZ = min(minZ, point.y)  // .y is Z in SIMD2
                maxZ = max(maxZ, point.y)
            }

            self.worldBounds = CGRect(
                x: CGFloat(minX),
                y: CGFloat(minZ),
                width: CGFloat(maxX - minX),
                height: CGFloat(maxZ - minZ)
            )
        }

        // Calculate scale to fit room in canvas with margins
        let availableWidth = canvasSize.width - 2 * margin
        let availableHeight = canvasSize.height - 2 * margin

        let scaleX = availableWidth / worldBounds.width
        let scaleY = availableHeight / worldBounds.height
        self.scale = min(scaleX, scaleY)

        // Calculate offset to center room in canvas
        let scaledWidth = worldBounds.width * scale
        let scaledHeight = worldBounds.height * scale
        let offsetX = margin + (availableWidth - scaledWidth) / 2 - worldBounds.minX * scale
        let offsetY = margin + (availableHeight - scaledHeight) / 2 - worldBounds.minY * scale
        self.offset = CGPoint(x: offsetX, y: offsetY)
    }

    /// Transforms a world coordinate (X, Z in inches) to screen coordinate.
    ///
    /// - Parameter worldCoordinate: 2D point in world coordinates (X, Z)
    /// - Returns: Point in screen coordinates
    func transformPoint(worldCoordinate: SIMD2<Float>) -> CGPoint {
        // X maps directly, Z maps to Y (with inversion handled by centering)
        let screenX = CGFloat(worldCoordinate.x) * scale + offset.x
        let screenY = CGFloat(worldCoordinate.y) * scale + offset.y
        return CGPoint(x: screenX, y: screenY)
    }

    /// Transforms a CGPoint world coordinate to screen coordinate.
    func transformPoint(_ point: CGPoint) -> CGPoint {
        let screenX = point.x * scale + offset.x
        let screenY = point.y * scale + offset.y
        return CGPoint(x: screenX, y: screenY)
    }

    /// Transforms a size from world inches to screen points.
    func transformSize(widthInches: Float, heightInches: Float) -> CGSize {
        return CGSize(
            width: CGFloat(widthInches) * scale,
            height: CGFloat(heightInches) * scale
        )
    }

    /// Creates a CGRect in screen coordinates from world coordinates.
    func transformRect(origin: SIMD2<Float>, width: Float, height: Float) -> CGRect {
        let screenOrigin = transformPoint(worldCoordinate: origin)
        let screenSize = transformSize(widthInches: width, heightInches: height)
        return CGRect(origin: screenOrigin, size: screenSize)
    }
}

// MARK: - Floor Plan Colors

/// Color scheme for floor plan rendering.
///
/// Matches LiDAR flow aesthetic per AC4.
private enum FloorPlanColors {
    static let wallStroke = UIColor.black
    static let wallFill = UIColor.white
    static let openBoundaryStroke = UIColor.darkGray

    static let baseCabinetFill = UIColor(white: 0.7, alpha: 1.0)
    static let baseCabinetStroke = UIColor(white: 0.4, alpha: 1.0)

    static let upperCabinetStroke = UIColor(white: 0.5, alpha: 1.0)

    static let tallCabinetFill = UIColor(white: 0.6, alpha: 1.0)
    static let tallCabinetStroke = UIColor(white: 0.3, alpha: 1.0)

    static let applianceStroke = UIColor.darkGray
    static let applianceFill = UIColor(white: 0.85, alpha: 1.0)
    static let applianceLabel = UIColor.darkGray

    static let windowStroke = UIColor(red: 0.3, green: 0.5, blue: 0.8, alpha: 1.0)
    static let doorStroke = UIColor(red: 0.6, green: 0.4, blue: 0.2, alpha: 1.0)
    static let doorArcStroke = UIColor(red: 0.6, green: 0.4, blue: 0.2, alpha: 0.5)

    static let islandFill = UIColor(white: 0.75, alpha: 1.0)
    static let islandStroke = UIColor(white: 0.4, alpha: 1.0)

    static let countertopOverlay = UIColor(red: 0.9, green: 0.85, blue: 0.75, alpha: 0.3)

    static let specialCabinetFill = UIColor(red: 0.85, green: 0.9, blue: 0.85, alpha: 1.0)
    static let specialCabinetStroke = UIColor(red: 0.3, green: 0.5, blue: 0.3, alpha: 1.0)

    static let dimensionText = UIColor.darkGray
    static let scaleText = UIColor.darkGray

    // Story 6.2: Unscanned area colors
    static let unscannedHatchStroke = UIColor(white: 0.5, alpha: 0.3)
    static let unscannedLabelText = UIColor(white: 0.4, alpha: 1.0)
}

// MARK: - Floor Plan Renderer

/// Renders a 2D floor plan PNG from AI pipeline detection results.
///
/// **Usage:**
/// ```swift
/// let renderer = AIFloorPlanRenderer()
/// let result = try await renderer.render(
///     roomStructure: pipelineResult.roomStructure,
///     cabinets: pipelineResult.detectedCabinets,
///     appliances: pipelineResult.detectedAppliances,
///     islandsPeninsulas: pipelineResult.detectedIslandsPeninsulas,
///     openings: pipelineResult.detectedOpenings
/// )
/// let pngData = result.pngData
/// ```
///
/// **Performance Budget:** <500ms (Architecture 9.3)
@MainActor
final class AIFloorPlanRenderer {

    // MARK: - Constants

    /// Target DPI for print quality output (AC3)
    private let targetDPI: Int = 300

    /// Default canvas size in points (will be scaled for DPI)
    private let defaultCanvasSize = CGSize(width: 800, height: 600)

    /// Margin around floor plan in points
    private let margin: CGFloat = 50

    /// Wall stroke width in points
    private let wallStrokeWidth: CGFloat = 2.0

    /// Cabinet stroke width in points
    private let cabinetStrokeWidth: CGFloat = 1.0

    /// Maximum PNG file size in bytes (5MB per AC3)
    private let maxPNGSizeBytes: Int = 5 * 1024 * 1024

    // MARK: - Scale Bar Constants (Task 7)

    /// Scale bar thresholds for selecting appropriate scale (in inches)
    private enum ScaleBarThresholds {
        static let fiveFeet: CGFloat = 48
        static let fourFeet: CGFloat = 36
        static let threeFeet: CGFloat = 24
        static let twoFeet: CGFloat = 12
    }

    /// Scale bar values in inches
    private enum ScaleBarValues {
        static let fiveFeetInches: CGFloat = 60
        static let fourFeetInches: CGFloat = 48
        static let threeFeetInches: CGFloat = 36
        static let twoFeetInches: CGFloat = 24
        static let oneFootInches: CGFloat = 12
    }

    /// Dash pattern for upper cabinets
    private let upperCabinetDash: [CGFloat] = [5, 3]

    /// Font for dimension labels
    private lazy var dimensionFont: UIFont = {
        UIFont.systemFont(ofSize: 10, weight: .medium)
    }()

    /// Font for appliance labels
    private lazy var applianceLabelFont: UIFont = {
        UIFont.systemFont(ofSize: 8, weight: .regular)
    }()

    /// Font for scale indicator
    private lazy var scaleFont: UIFont = {
        UIFont.systemFont(ofSize: 9, weight: .medium)
    }()

    // MARK: - Initialization

    init() {}

    // MARK: - Main Render Method

    /// Renders a floor plan from detection results.
    ///
    /// - Parameters:
    ///   - roomStructure: Room structure containing walls and boundary
    ///   - cabinets: Optional cabinet detection result
    ///   - appliances: Optional appliance detection result
    ///   - islandsPeninsulas: Optional island/peninsula detection result
    ///   - openings: Optional window/door detection result
    ///   - countertops: Optional countertop detection result
    ///   - uncapturedZones: Zones not captured during scanning (Story 6.2)
    ///   - coveragePercentage: Coverage percentage from capture phase (Story 6.2)
    /// - Returns: Render result with PNG data and metadata
    /// - Throws: Never throws; generates partial result on missing data
    func render(
        roomStructure: AIRoomStructure,
        cabinets: CabinetDetectionResult? = nil,
        appliances: ApplianceDetectionResult? = nil,
        islandsPeninsulas: IslandPeninsulaDetectionResult? = nil,
        openings: OpeningDetectionResult? = nil,
        countertops: CountertopDetectorResult? = nil,
        uncapturedZones: Set<AICaptureZone>? = nil,
        coveragePercentage: Float? = nil
    ) async throws -> FloorPlanRenderResult {
        let startTime = Date()
        var warnings: [String] = []
        var elementsRendered: Set<FloorPlanElement> = []

        // Calculate canvas size based on room aspect ratio
        let canvasSize = calculateCanvasSize(for: roomStructure)

        // Create coordinate transform
        let transform = FloorPlanTransform(
            roomStructure: roomStructure,
            canvasSize: canvasSize,
            margin: margin
        )

        // Set up high-DPI renderer
        let format = UIGraphicsImageRendererFormat()
        format.scale = CGFloat(targetDPI) / 72.0  // 300 DPI / 72 points per inch

        let renderer = UIGraphicsImageRenderer(size: canvasSize, format: format)

        // Render floor plan
        let image = renderer.image { context in
            let cgContext = context.cgContext

            // Fill background
            UIColor.white.setFill()
            cgContext.fill(CGRect(origin: .zero, size: canvasSize))

            // Draw room boundary (Task 2)
            if !roomStructure.boundaryPolygon.isEmpty {
                drawRoomBoundary(context: cgContext, roomStructure: roomStructure, transform: transform)
                elementsRendered.insert(.roomBoundary)

                // Story 6.2: Draw unscanned areas with hatched pattern
                if let zones = uncapturedZones, !zones.isEmpty {
                    drawUnscannedAreas(context: cgContext, uncapturedZones: zones, transform: transform)
                    elementsRendered.insert(.unscannedAreas)
                }

                // Draw wall dimensions (Task 8)
                drawWallDimensions(context: cgContext, roomStructure: roomStructure, transform: transform)
                elementsRendered.insert(.wallDimensions)
            } else {
                warnings.append("Room boundary is empty - walls not rendered")
            }

            // Draw islands and peninsulas (Task 6) - draw before cabinets so cabinets appear on top
            if let islandResult = islandsPeninsulas {
                if !islandResult.islands.isEmpty {
                    drawIslands(context: cgContext, islands: islandResult.islands, transform: transform)
                    elementsRendered.insert(.islands)
                }
                if !islandResult.peninsulas.isEmpty {
                    drawPeninsulas(context: cgContext, peninsulas: islandResult.peninsulas, roomStructure: roomStructure, transform: transform)
                    elementsRendered.insert(.peninsulas)
                }
            }

            // Draw countertops (Task 6.4) - draw before cabinets for layering
            if let countertopResult = countertops {
                drawCountertops(context: cgContext, countertops: countertopResult, roomStructure: roomStructure, transform: transform)
                elementsRendered.insert(.countertops)
            }

            // Draw cabinets (Task 3)
            if let cabinetResult = cabinets {
                drawCabinets(context: cgContext, cabinets: cabinetResult, roomStructure: roomStructure, transform: transform, elementsRendered: &elementsRendered)
            }

            // Draw openings (Task 5) - draw after walls
            if let openingResult = openings {
                if !openingResult.windows.isEmpty {
                    drawWindows(context: cgContext, windows: openingResult.windows, roomStructure: roomStructure, transform: transform)
                    elementsRendered.insert(.windows)
                }
                if !openingResult.doors.isEmpty {
                    drawDoors(context: cgContext, doors: openingResult.doors, roomStructure: roomStructure, transform: transform)
                    elementsRendered.insert(.doors)
                }
            }

            // Draw appliances (Task 4)
            if let applianceResult = appliances {
                if !applianceResult.appliances.isEmpty {
                    drawAppliances(context: cgContext, appliances: applianceResult.appliances, transform: transform)
                    elementsRendered.insert(.appliances)
                }
            }

            // Draw scale indicator (Task 7)
            drawScaleIndicator(context: cgContext, transform: transform, canvasSize: canvasSize)
            elementsRendered.insert(.scaleIndicator)

            // Draw orientation indicator (Task 7)
            drawOrientationIndicator(context: cgContext, canvasSize: canvasSize)
            elementsRendered.insert(.orientationIndicator)
        }

        // Export to PNG with size check and compression (Task 9.4 - AC3)
        var pngData = image.pngData()
        var actualDPI = targetDPI

        // If PNG exceeds max size, re-render at lower resolution
        if let data = pngData, data.count > maxPNGSizeBytes {
            warnings.append("Initial PNG exceeded 5MB (\(data.count / (1024 * 1024))MB), re-rendering at lower resolution")

            // Re-render at 150 DPI (half resolution)
            let reducedDPI = 150
            let reducedFormat = UIGraphicsImageRendererFormat()
            reducedFormat.scale = CGFloat(reducedDPI) / 72.0

            let reducedRenderer = UIGraphicsImageRenderer(size: canvasSize, format: reducedFormat)
            let reducedImage = reducedRenderer.image { context in
                let cgContext = context.cgContext

                // Fill background
                UIColor.white.setFill()
                cgContext.fill(CGRect(origin: .zero, size: canvasSize))

                // Re-draw all elements at reduced resolution
                if !roomStructure.boundaryPolygon.isEmpty {
                    drawRoomBoundary(context: cgContext, roomStructure: roomStructure, transform: transform)
                    drawWallDimensions(context: cgContext, roomStructure: roomStructure, transform: transform)
                }

                if let islandResult = islandsPeninsulas {
                    if !islandResult.islands.isEmpty {
                        drawIslands(context: cgContext, islands: islandResult.islands, transform: transform)
                    }
                    if !islandResult.peninsulas.isEmpty {
                        drawPeninsulas(context: cgContext, peninsulas: islandResult.peninsulas, roomStructure: roomStructure, transform: transform)
                    }
                }

                if let cabinetResult = cabinets {
                    var tempElementsRendered = elementsRendered
                    drawCabinets(context: cgContext, cabinets: cabinetResult, roomStructure: roomStructure, transform: transform, elementsRendered: &tempElementsRendered)
                }

                if let countertopResult = countertops {
                    drawCountertops(context: cgContext, countertops: countertopResult, roomStructure: roomStructure, transform: transform)
                }

                if let openingResult = openings {
                    if !openingResult.windows.isEmpty {
                        drawWindows(context: cgContext, windows: openingResult.windows, roomStructure: roomStructure, transform: transform)
                    }
                    if !openingResult.doors.isEmpty {
                        drawDoors(context: cgContext, doors: openingResult.doors, roomStructure: roomStructure, transform: transform)
                    }
                }

                if let applianceResult = appliances {
                    if !applianceResult.appliances.isEmpty {
                        drawAppliances(context: cgContext, appliances: applianceResult.appliances, transform: transform)
                    }
                }

                drawScaleIndicator(context: cgContext, transform: transform, canvasSize: canvasSize)
                drawOrientationIndicator(context: cgContext, canvasSize: canvasSize)
            }

            pngData = reducedImage.pngData()
            actualDPI = reducedDPI
        }

        guard let finalPngData = pngData else {
            // Fallback: create minimal PNG
            warnings.append("Failed to generate PNG data")
            let fallbackData = Data()
            return FloorPlanRenderResult(
                pngData: fallbackData,
                imageSize: canvasSize,
                dpi: actualDPI,
                metadata: FloorPlanMetadata(
                    roomShape: roomStructure.roomShape,
                    elementsRendered: elementsRendered,
                    wallCount: roomStructure.walls.count,
                    cabinetCounts: [:],
                    applianceCount: 0,
                    windowCount: 0,
                    doorCount: 0,
                    islandCount: 0,
                    peninsulaCount: 0,
                    scaleDescription: nil,
                    warnings: warnings,
                    coveragePercentage: coveragePercentage,
                    uncapturedZones: uncapturedZones
                ),
                processingTimeMs: 0
            )
        }

        // Build metadata
        var cabinetCounts: [AICabinetType: Int] = [:]
        if let cabinetResult = cabinets {
            cabinetCounts = cabinetResult.countByType
        }

        let processingTimeMs = Int((Date().timeIntervalSince(startTime) * 1000).rounded())

        // Calculate scale description
        let scaleDescription = calculateScaleDescription(transform: transform)

        return FloorPlanRenderResult(
            pngData: finalPngData,
            imageSize: canvasSize,
            dpi: actualDPI,
            metadata: FloorPlanMetadata(
                roomShape: roomStructure.roomShape,
                elementsRendered: elementsRendered,
                wallCount: roomStructure.walls.count,
                cabinetCounts: cabinetCounts,
                applianceCount: appliances?.appliances.count ?? 0,
                windowCount: openings?.windows.count ?? 0,
                doorCount: openings?.doors.count ?? 0,
                islandCount: islandsPeninsulas?.islands.count ?? 0,
                peninsulaCount: islandsPeninsulas?.peninsulas.count ?? 0,
                scaleDescription: scaleDescription,
                warnings: warnings,
                coveragePercentage: coveragePercentage,
                uncapturedZones: uncapturedZones
            ),
            processingTimeMs: processingTimeMs
        )
    }

    // MARK: - Canvas Size Calculation

    /// Calculates optimal canvas size based on room aspect ratio.
    private func calculateCanvasSize(for roomStructure: AIRoomStructure) -> CGSize {
        guard !roomStructure.boundaryPolygon.isEmpty else {
            return defaultCanvasSize
        }

        let width = roomStructure.dimensions.widthInches
        let length = roomStructure.dimensions.lengthInches

        guard width > 0 && length > 0 else {
            return defaultCanvasSize
        }

        let aspectRatio = width / length

        // Target area in points (for reasonable file size)
        let targetArea: CGFloat = 800 * 600

        let canvasWidth = sqrt(targetArea * CGFloat(aspectRatio))
        let canvasHeight = targetArea / canvasWidth

        return CGSize(width: canvasWidth, height: canvasHeight)
    }

    // MARK: - Task 2: Room Boundary Rendering

    /// Draws the room boundary polygon.
    private func drawRoomBoundary(
        context: CGContext,
        roomStructure: AIRoomStructure,
        transform: FloorPlanTransform
    ) {
        guard !roomStructure.boundaryPolygon.isEmpty else { return }

        let path = CGMutablePath()

        // Transform all points
        let screenPoints = roomStructure.boundaryPolygon.map { transform.transformPoint(worldCoordinate: $0) }

        // Draw polygon
        path.move(to: screenPoints[0])
        for point in screenPoints.dropFirst() {
            path.addLine(to: point)
        }
        path.closeSubpath()

        // Fill with white
        context.setFillColor(FloorPlanColors.wallFill.cgColor)
        context.addPath(path)
        context.fillPath()

        // Stroke walls
        context.setStrokeColor(FloorPlanColors.wallStroke.cgColor)
        context.setLineWidth(wallStrokeWidth)
        context.setLineDash(phase: 0, lengths: [])  // Solid line

        // Draw each wall segment
        for wall in roomStructure.walls {
            let start = transform.transformPoint(worldCoordinate: wall.startPoint)
            let end = transform.transformPoint(worldCoordinate: wall.endPoint)

            if wall.boundaryType == .open {
                // Dashed line for open boundaries
                context.setLineDash(phase: 0, lengths: [5, 5])
                context.setStrokeColor(FloorPlanColors.openBoundaryStroke.cgColor)
            } else {
                context.setLineDash(phase: 0, lengths: [])
                context.setStrokeColor(FloorPlanColors.wallStroke.cgColor)
            }

            context.move(to: start)
            context.addLine(to: end)
            context.strokePath()
        }
    }

    // MARK: - Task 8: Dimension Labels

    /// Draws wall dimension labels at wall midpoints.
    private func drawWallDimensions(
        context: CGContext,
        roomStructure: AIRoomStructure,
        transform: FloorPlanTransform
    ) {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: dimensionFont,
            .foregroundColor: FloorPlanColors.dimensionText
        ]

        for wall in roomStructure.walls {
            let lengthInches = wall.lengthInches
            let formattedDimension = formatDimension(inches: Float(lengthInches))

            // Calculate midpoint
            let midWorld = SIMD2<Float>(
                (wall.startPoint.x + wall.endPoint.x) / 2,
                (wall.startPoint.y + wall.endPoint.y) / 2
            )
            let midScreen = transform.transformPoint(worldCoordinate: midWorld)

            // Calculate text rotation angle
            let dx = wall.endPoint.x - wall.startPoint.x
            let dy = wall.endPoint.y - wall.startPoint.y
            var angle = atan2(CGFloat(dy), CGFloat(dx))

            // Keep text readable (not upside down)
            if angle > .pi / 2 || angle < -.pi / 2 {
                angle += .pi
            }

            // Offset label outside the room (using wall normal)
            let offsetDistance: CGFloat = 15
            let normalX = CGFloat(wall.normalDirection.x)
            let normalY = CGFloat(wall.normalDirection.y)
            let labelPosition = CGPoint(
                x: midScreen.x + normalX * offsetDistance,
                y: midScreen.y + normalY * offsetDistance
            )

            // Draw rotated text
            context.saveGState()
            context.translateBy(x: labelPosition.x, y: labelPosition.y)
            context.rotate(by: angle)

            let text = formattedDimension as NSString
            let textSize = text.size(withAttributes: attributes)
            text.draw(at: CGPoint(x: -textSize.width / 2, y: -textSize.height / 2), withAttributes: attributes)

            context.restoreGState()
        }
    }

    // MARK: - Task 3: Cabinet Rendering

    /// Draws all cabinets with type differentiation.
    private func drawCabinets(
        context: CGContext,
        cabinets: CabinetDetectionResult,
        roomStructure: AIRoomStructure,
        transform: FloorPlanTransform,
        elementsRendered: inout Set<FloorPlanElement>
    ) {
        for cabinet in cabinets.cabinets {
            // Check for special cabinet types first (Task 3.7)
            if cabinet.isSpecialCabinet {
                drawSpecialCabinet(context: context, cabinet: cabinet, roomStructure: roomStructure, transform: transform)
                elementsRendered.insert(.specialCabinets)
                continue
            }

            switch cabinet.type {
            case .base:
                drawBaseCabinet(context: context, cabinet: cabinet, roomStructure: roomStructure, transform: transform)
                elementsRendered.insert(.baseCabinets)

            case .upper:
                drawUpperCabinet(context: context, cabinet: cabinet, roomStructure: roomStructure, transform: transform)
                elementsRendered.insert(.upperCabinets)

            case .tall:
                drawTallCabinet(context: context, cabinet: cabinet, roomStructure: roomStructure, transform: transform)
                elementsRendered.insert(.tallCabinets)
            }
        }
    }

    /// Draws a special cabinet (stacked, refrigerator upper, appliance housing).
    /// Task 3.7 - Handle special cabinets with distinct visual indicators.
    private func drawSpecialCabinet(
        context: CGContext,
        cabinet: AIDetectedCabinet,
        roomStructure: AIRoomStructure,
        transform: FloorPlanTransform
    ) {
        guard let rect = calculateCabinetRect(cabinet: cabinet, roomStructure: roomStructure, transform: transform) else { return }

        // Fill with special cabinet color
        context.setFillColor(FloorPlanColors.specialCabinetFill.cgColor)
        context.fill(rect)

        // Add diagonal stripe pattern to indicate special cabinet
        context.saveGState()
        context.clip(to: rect)

        context.setStrokeColor(FloorPlanColors.specialCabinetStroke.cgColor)
        context.setLineWidth(0.5)

        let spacing: CGFloat = 8
        var x = rect.minX - rect.height
        while x < rect.maxX {
            context.move(to: CGPoint(x: x, y: rect.maxY))
            context.addLine(to: CGPoint(x: x + rect.height, y: rect.minY))
            x += spacing
        }
        context.strokePath()

        context.restoreGState()

        // Stroke outline
        context.setStrokeColor(FloorPlanColors.specialCabinetStroke.cgColor)
        context.setLineWidth(cabinetStrokeWidth)
        context.stroke(rect)

        // Add special label based on type
        let label: String
        if cabinet.isStacked {
            label = "ST"  // Stacked
        } else if cabinet.isRefrigeratorCabinet {
            label = "RF"  // Refrigerator upper
        } else if cabinet.isMicrowaveCabinet {
            label = "MW"  // Microwave housing
        } else if cabinet.isOvenCabinet {
            label = "OV"  // Oven housing
        } else {
            label = "SP"  // Generic special
        }

        drawCabinetLabel(context: context, rect: rect, label: label)
    }

    /// Draws a base cabinet as filled rectangle.
    private func drawBaseCabinet(
        context: CGContext,
        cabinet: AIDetectedCabinet,
        roomStructure: AIRoomStructure,
        transform: FloorPlanTransform
    ) {
        guard let rect = calculateCabinetRect(cabinet: cabinet, roomStructure: roomStructure, transform: transform) else { return }

        // Handle corner cabinets differently
        if let cornerType = cabinet.cornerType {
            drawCornerCabinet(context: context, cabinet: cabinet, cornerType: cornerType, roomStructure: roomStructure, transform: transform)
            return
        }

        // Filled gray rectangle for base cabinets
        context.setFillColor(FloorPlanColors.baseCabinetFill.cgColor)
        context.fill(rect)

        context.setStrokeColor(FloorPlanColors.baseCabinetStroke.cgColor)
        context.setLineWidth(cabinetStrokeWidth)
        context.setLineDash(phase: 0, lengths: [])
        context.stroke(rect)

        // Add label
        drawCabinetLabel(context: context, rect: rect, label: "B")
    }

    /// Draws an upper cabinet as dashed outline.
    private func drawUpperCabinet(
        context: CGContext,
        cabinet: AIDetectedCabinet,
        roomStructure: AIRoomStructure,
        transform: FloorPlanTransform
    ) {
        guard let rect = calculateCabinetRect(cabinet: cabinet, roomStructure: roomStructure, transform: transform, depth: 12) else { return }

        // Dashed outline for upper cabinets
        context.setStrokeColor(FloorPlanColors.upperCabinetStroke.cgColor)
        context.setLineWidth(cabinetStrokeWidth)
        context.setLineDash(phase: 0, lengths: upperCabinetDash)
        context.stroke(rect)

        // Reset dash
        context.setLineDash(phase: 0, lengths: [])

        // Add label
        drawCabinetLabel(context: context, rect: rect, label: "U")
    }

    /// Draws a tall cabinet with cross-hatch pattern.
    private func drawTallCabinet(
        context: CGContext,
        cabinet: AIDetectedCabinet,
        roomStructure: AIRoomStructure,
        transform: FloorPlanTransform
    ) {
        guard let rect = calculateCabinetRect(cabinet: cabinet, roomStructure: roomStructure, transform: transform) else { return }

        // Fill with lighter shade
        context.setFillColor(FloorPlanColors.tallCabinetFill.cgColor)
        context.fill(rect)

        // Add cross-hatch pattern
        context.saveGState()
        context.clip(to: rect)

        context.setStrokeColor(FloorPlanColors.tallCabinetStroke.cgColor)
        context.setLineWidth(0.5)

        let spacing: CGFloat = 6
        // Diagonal lines from bottom-left to top-right
        var x = rect.minX - rect.height
        while x < rect.maxX {
            context.move(to: CGPoint(x: x, y: rect.maxY))
            context.addLine(to: CGPoint(x: x + rect.height, y: rect.minY))
            x += spacing
        }
        context.strokePath()

        context.restoreGState()

        // Stroke outline
        context.setStrokeColor(FloorPlanColors.tallCabinetStroke.cgColor)
        context.setLineWidth(cabinetStrokeWidth)
        context.stroke(rect)

        // Add label
        drawCabinetLabel(context: context, rect: rect, label: "T")
    }

    /// Draws a corner cabinet (L-shape or diagonal).
    private func drawCornerCabinet(
        context: CGContext,
        cabinet: AIDetectedCabinet,
        cornerType: AICornerCabinetType,
        roomStructure: AIRoomStructure,
        transform: FloorPlanTransform
    ) {
        guard let wall = roomStructure.walls.first(where: { $0.id == cabinet.wallId }) else { return }

        let position = cabinet.positionOnWallInches
        let width = cabinet.widthInches
        let depth = cabinet.depthInches

        // Calculate corner position
        let wallDir = simd_normalize(wall.endPoint - wall.startPoint)
        let startWorld = wall.startPoint + wallDir * position

        // For diagonal corners, draw a triangle
        if cornerType == .diagonal {
            let p1 = transform.transformPoint(worldCoordinate: startWorld)
            let p2 = transform.transformPoint(worldCoordinate: startWorld + wallDir * width)
            let normalDir = SIMD2<Float>(-wallDir.y, wallDir.x)
            let p3 = transform.transformPoint(worldCoordinate: startWorld + normalDir * depth)

            let path = CGMutablePath()
            path.move(to: p1)
            path.addLine(to: p2)
            path.addLine(to: p3)
            path.closeSubpath()

            context.setFillColor(FloorPlanColors.baseCabinetFill.cgColor)
            context.addPath(path)
            context.fillPath()

            context.setStrokeColor(FloorPlanColors.baseCabinetStroke.cgColor)
            context.setLineWidth(cabinetStrokeWidth)
            context.addPath(path)
            context.strokePath()
        } else {
            // L-shape - draw as regular rectangle for simplicity
            if let rect = calculateCabinetRect(cabinet: cabinet, roomStructure: roomStructure, transform: transform) {
                context.setFillColor(FloorPlanColors.baseCabinetFill.cgColor)
                context.fill(rect)
                context.setStrokeColor(FloorPlanColors.baseCabinetStroke.cgColor)
                context.setLineWidth(cabinetStrokeWidth)
                context.stroke(rect)
            }
        }
    }

    /// Calculates cabinet rectangle in screen coordinates.
    private func calculateCabinetRect(
        cabinet: AIDetectedCabinet,
        roomStructure: AIRoomStructure,
        transform: FloorPlanTransform,
        depth: Float? = nil
    ) -> CGRect? {
        guard let wall = roomStructure.walls.first(where: { $0.id == cabinet.wallId }) else { return nil }

        let position = cabinet.positionOnWallInches
        let width = cabinet.widthInches
        let cabinetDepth = depth ?? cabinet.depthInches

        // Calculate world position along wall
        let wallDir = simd_normalize(wall.endPoint - wall.startPoint)
        let wallNormal = SIMD2<Float>(-wallDir.y, wallDir.x)

        let cornerWorld = wall.startPoint + wallDir * position
        let screenCorner = transform.transformPoint(worldCoordinate: cornerWorld)

        // Calculate screen dimensions
        let screenWidth = CGFloat(width) * transform.scale
        let screenDepth = CGFloat(cabinetDepth) * transform.scale

        // For simplicity, approximate with axis-aligned rectangle based on wall direction
        // (A more accurate implementation would rotate the rectangle)
        if abs(wallDir.x) > abs(wallDir.y) {
            // Horizontal wall - cabinet extends in Y direction
            return CGRect(
                x: screenCorner.x,
                y: screenCorner.y,
                width: screenWidth,
                height: screenDepth
            )
        } else {
            // Vertical wall - cabinet extends in X direction
            return CGRect(
                x: screenCorner.x - screenDepth,
                y: screenCorner.y,
                width: screenDepth,
                height: screenWidth
            )
        }
    }

    /// Draws a label in the center of a cabinet rectangle.
    private func drawCabinetLabel(context: CGContext, rect: CGRect, label: String) {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 8, weight: .medium),
            .foregroundColor: UIColor.darkGray
        ]

        let text = label as NSString
        let textSize = text.size(withAttributes: attributes)
        let center = CGPoint(
            x: rect.midX - textSize.width / 2,
            y: rect.midY - textSize.height / 2
        )
        text.draw(at: center, withAttributes: attributes)
    }

    // MARK: - Task 4: Appliance Rendering

    /// Draws all appliances with icons and labels.
    private func drawAppliances(
        context: CGContext,
        appliances: [AIDetectedAppliance],
        transform: FloorPlanTransform
    ) {
        for appliance in appliances {
            drawAppliance(context: context, appliance: appliance, transform: transform)
        }
    }

    /// Draws a single appliance with type-specific icon.
    private func drawAppliance(
        context: CGContext,
        appliance: AIDetectedAppliance,
        transform: FloorPlanTransform
    ) {
        let center = SIMD2<Float>(appliance.boundingBox.center.x, appliance.boundingBox.center.z)
        let screenCenter = transform.transformPoint(worldCoordinate: center)
        let width = CGFloat(appliance.widthInches) * transform.scale
        let depth = CGFloat(appliance.depthInches) * transform.scale

        let rect = CGRect(
            x: screenCenter.x - width / 2,
            y: screenCenter.y - depth / 2,
            width: width,
            height: depth
        )

        // Draw base rectangle
        context.setFillColor(FloorPlanColors.applianceFill.cgColor)
        context.fill(rect)
        context.setStrokeColor(FloorPlanColors.applianceStroke.cgColor)
        context.setLineWidth(1.0)
        context.stroke(rect)

        // Draw type-specific icon
        switch appliance.type {
        case .refrigerator:
            drawRefrigeratorIcon(context: context, rect: rect)

        case .range, .cooktop:
            drawRangeIcon(context: context, rect: rect)

        case .dishwasher:
            drawDishwasherIcon(context: context, rect: rect)

        case .sink:
            drawSinkIcon(context: context, rect: rect)

        case .microwave:
            drawMicrowaveIcon(context: context, rect: rect)

        case .wallOven:
            drawWallOvenIcon(context: context, rect: rect)

        case .hood:
            drawHoodIcon(context: context, rect: rect)

        case .other:
            // Draw generic appliance box with "?" label
            break
        }

        // Draw label below
        let label = appliance.type.shortLabel
        drawApplianceLabel(context: context, rect: rect, label: label)
    }

    private func drawRefrigeratorIcon(context: CGContext, rect: CGRect) {
        // Draw "R" in center
        let attributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.boldSystemFont(ofSize: max(10, rect.width * 0.4)),
            .foregroundColor: FloorPlanColors.applianceStroke
        ]
        let text = "R" as NSString
        let textSize = text.size(withAttributes: attributes)
        text.draw(
            at: CGPoint(x: rect.midX - textSize.width / 2, y: rect.midY - textSize.height / 2),
            withAttributes: attributes
        )
    }

    private func drawRangeIcon(context: CGContext, rect: CGRect) {
        // Draw 4 burner circles
        let burnerRadius = min(rect.width, rect.height) * 0.12
        let padding = rect.width * 0.2

        let positions = [
            CGPoint(x: rect.minX + padding, y: rect.minY + padding),
            CGPoint(x: rect.maxX - padding, y: rect.minY + padding),
            CGPoint(x: rect.minX + padding, y: rect.maxY - padding),
            CGPoint(x: rect.maxX - padding, y: rect.maxY - padding)
        ]

        context.setStrokeColor(FloorPlanColors.applianceStroke.cgColor)
        context.setLineWidth(1.0)

        for pos in positions {
            context.strokeEllipse(in: CGRect(
                x: pos.x - burnerRadius,
                y: pos.y - burnerRadius,
                width: burnerRadius * 2,
                height: burnerRadius * 2
            ))
        }
    }

    private func drawDishwasherIcon(context: CGContext, rect: CGRect) {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: max(8, rect.width * 0.25)),
            .foregroundColor: FloorPlanColors.applianceStroke
        ]
        let text = "DW" as NSString
        let textSize = text.size(withAttributes: attributes)
        text.draw(
            at: CGPoint(x: rect.midX - textSize.width / 2, y: rect.midY - textSize.height / 2),
            withAttributes: attributes
        )
    }

    private func drawSinkIcon(context: CGContext, rect: CGRect) {
        // Draw oval shape for sink
        let inset = rect.width * 0.15
        let ovalRect = rect.insetBy(dx: inset, dy: inset)
        context.setStrokeColor(FloorPlanColors.applianceStroke.cgColor)
        context.setLineWidth(1.0)
        context.strokeEllipse(in: ovalRect)
    }

    private func drawMicrowaveIcon(context: CGContext, rect: CGRect) {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: max(6, rect.width * 0.3)),
            .foregroundColor: FloorPlanColors.applianceStroke
        ]
        let text = "MW" as NSString
        let textSize = text.size(withAttributes: attributes)
        text.draw(
            at: CGPoint(x: rect.midX - textSize.width / 2, y: rect.midY - textSize.height / 2),
            withAttributes: attributes
        )
    }

    private func drawWallOvenIcon(context: CGContext, rect: CGRect) {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: max(6, rect.width * 0.3)),
            .foregroundColor: FloorPlanColors.applianceStroke
        ]
        let text = "WO" as NSString
        let textSize = text.size(withAttributes: attributes)
        text.draw(
            at: CGPoint(x: rect.midX - textSize.width / 2, y: rect.midY - textSize.height / 2),
            withAttributes: attributes
        )
    }

    private func drawHoodIcon(context: CGContext, rect: CGRect) {
        // Draw trapezoid shape for hood
        let path = CGMutablePath()
        let inset = rect.width * 0.2
        path.move(to: CGPoint(x: rect.minX + inset, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - inset, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()

        context.setStrokeColor(FloorPlanColors.applianceStroke.cgColor)
        context.setLineWidth(1.0)
        context.addPath(path)
        context.strokePath()
    }

    private func drawApplianceLabel(context: CGContext, rect: CGRect, label: String) {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: applianceLabelFont,
            .foregroundColor: FloorPlanColors.applianceLabel
        ]
        let text = label as NSString
        let textSize = text.size(withAttributes: attributes)
        text.draw(
            at: CGPoint(x: rect.midX - textSize.width / 2, y: rect.maxY + 2),
            withAttributes: attributes
        )
    }

    // MARK: - Task 5: Opening Rendering

    /// Draws windows as breaks in wall with perpendicular lines.
    private func drawWindows(
        context: CGContext,
        windows: [AIDetectedWindow],
        roomStructure: AIRoomStructure,
        transform: FloorPlanTransform
    ) {
        for window in windows {
            guard let wall = roomStructure.walls.first(where: { $0.id == window.wallId }) else { continue }

            let position = window.positionOnWallInches
            let width = window.widthInches

            // Calculate window position on wall
            let wallDir = simd_normalize(wall.endPoint - wall.startPoint)
            let windowStart = wall.startPoint + wallDir * position
            let windowEnd = wall.startPoint + wallDir * (position + width)

            let screenStart = transform.transformPoint(worldCoordinate: windowStart)
            let screenEnd = transform.transformPoint(worldCoordinate: windowEnd)

            // Draw window symbol (break in wall with perpendicular lines)
            context.setStrokeColor(FloorPlanColors.windowStroke.cgColor)
            context.setLineWidth(1.5)

            // Main window line
            context.move(to: screenStart)
            context.addLine(to: screenEnd)
            context.strokePath()

            // Perpendicular tick marks at ends
            let wallNormal = SIMD2<Float>(-wallDir.y, wallDir.x)
            let tickLength: CGFloat = 4

            let normalScreen = CGPoint(
                x: CGFloat(wallNormal.x) * tickLength,
                y: CGFloat(wallNormal.y) * tickLength
            )

            // Start tick
            context.move(to: CGPoint(x: screenStart.x - normalScreen.x, y: screenStart.y - normalScreen.y))
            context.addLine(to: CGPoint(x: screenStart.x + normalScreen.x, y: screenStart.y + normalScreen.y))
            context.strokePath()

            // End tick
            context.move(to: CGPoint(x: screenEnd.x - normalScreen.x, y: screenEnd.y - normalScreen.y))
            context.addLine(to: CGPoint(x: screenEnd.x + normalScreen.x, y: screenEnd.y + normalScreen.y))
            context.strokePath()
        }
    }

    /// Draws doors with swing arc.
    private func drawDoors(
        context: CGContext,
        doors: [AIDetectedDoor],
        roomStructure: AIRoomStructure,
        transform: FloorPlanTransform
    ) {
        for door in doors {
            guard let wall = roomStructure.walls.first(where: { $0.id == door.wallId }) else { continue }

            let position = door.positionOnWallInches
            let width = door.widthInches

            // Calculate door position on wall
            let wallDir = simd_normalize(wall.endPoint - wall.startPoint)
            let doorStart = wall.startPoint + wallDir * position
            let doorEnd = wall.startPoint + wallDir * (position + width)

            let screenStart = transform.transformPoint(worldCoordinate: doorStart)
            let screenEnd = transform.transformPoint(worldCoordinate: doorEnd)

            // Draw door opening (gap in wall - white fill)
            context.setFillColor(UIColor.white.cgColor)
            let gapRect = CGRect(
                x: min(screenStart.x, screenEnd.x) - 1,
                y: min(screenStart.y, screenEnd.y) - 1,
                width: abs(screenEnd.x - screenStart.x) + 2,
                height: abs(screenEnd.y - screenStart.y) + 2
            )
            context.fill(gapRect)

            // Draw door swing arc
            context.setStrokeColor(FloorPlanColors.doorArcStroke.cgColor)
            context.setLineWidth(1.0)
            context.setLineDash(phase: 0, lengths: [3, 2])

            let wallNormal = SIMD2<Float>(-wallDir.y, wallDir.x)
            let arcRadius = CGFloat(width) * transform.scale

            // Determine swing direction
            let swingDirection = door.swingDirection ?? .right
            let hingePoint: CGPoint
            let startAngle: CGFloat
            let endAngle: CGFloat

            if swingDirection == .left {
                hingePoint = screenEnd
                startAngle = atan2(screenStart.y - screenEnd.y, screenStart.x - screenEnd.x)
                endAngle = startAngle + .pi / 2
            } else {
                hingePoint = screenStart
                startAngle = atan2(screenEnd.y - screenStart.y, screenEnd.x - screenStart.x)
                endAngle = startAngle - .pi / 2
            }

            context.addArc(
                center: hingePoint,
                radius: arcRadius,
                startAngle: startAngle,
                endAngle: endAngle,
                clockwise: swingDirection == .left
            )
            context.strokePath()

            // Reset dash pattern
            context.setLineDash(phase: 0, lengths: [])

            // Draw door line
            context.setStrokeColor(FloorPlanColors.doorStroke.cgColor)
            context.setLineWidth(1.5)
            context.move(to: screenStart)
            context.addLine(to: screenEnd)
            context.strokePath()
        }
    }

    // MARK: - Task 6: Island/Peninsula Rendering

    /// Draws islands as freestanding rectangles.
    private func drawIslands(
        context: CGContext,
        islands: [AIDetectedIsland],
        transform: FloorPlanTransform
    ) {
        for island in islands {
            let screenCenter = transform.transformPoint(worldCoordinate: island.position)
            let width = CGFloat(island.lengthInches) * transform.scale
            let depth = CGFloat(island.widthInches) * transform.scale

            // Create rotated rectangle
            let rect = CGRect(
                x: screenCenter.x - width / 2,
                y: screenCenter.y - depth / 2,
                width: width,
                height: depth
            )

            // Fill
            context.setFillColor(FloorPlanColors.islandFill.cgColor)
            context.fill(rect)

            // Stroke
            context.setStrokeColor(FloorPlanColors.islandStroke.cgColor)
            context.setLineWidth(cabinetStrokeWidth)
            context.stroke(rect)

            // Add "ISLAND" label
            let attributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 8, weight: .medium),
                .foregroundColor: UIColor.darkGray
            ]
            let text = "ISLAND" as NSString
            let textSize = text.size(withAttributes: attributes)
            text.draw(
                at: CGPoint(x: screenCenter.x - textSize.width / 2, y: screenCenter.y - textSize.height / 2),
                withAttributes: attributes
            )
        }
    }

    /// Draws peninsulas attached to walls.
    private func drawPeninsulas(
        context: CGContext,
        peninsulas: [AIDetectedPeninsula],
        roomStructure: AIRoomStructure,
        transform: FloorPlanTransform
    ) {
        for peninsula in peninsulas {
            let center = SIMD2<Float>(peninsula.boundingBox.center.x, peninsula.boundingBox.center.z)
            let screenCenter = transform.transformPoint(worldCoordinate: center)
            let length = CGFloat(peninsula.lengthInches) * transform.scale
            let width = CGFloat(peninsula.widthInches) * transform.scale

            let rect = CGRect(
                x: screenCenter.x - length / 2,
                y: screenCenter.y - width / 2,
                width: length,
                height: width
            )

            // Fill
            context.setFillColor(FloorPlanColors.islandFill.cgColor)
            context.fill(rect)

            // Stroke
            context.setStrokeColor(FloorPlanColors.islandStroke.cgColor)
            context.setLineWidth(cabinetStrokeWidth)
            context.stroke(rect)

            // Add "PENINSULA" label
            let attributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 7, weight: .medium),
                .foregroundColor: UIColor.darkGray
            ]
            let text = "PENINSULA" as NSString
            let textSize = text.size(withAttributes: attributes)
            text.draw(
                at: CGPoint(x: screenCenter.x - textSize.width / 2, y: screenCenter.y - textSize.height / 2),
                withAttributes: attributes
            )
        }
    }

    // MARK: - Task 6.4: Countertop Overlay Shading

    /// Draws countertop overlay shading on wall countertops.
    private func drawCountertops(
        context: CGContext,
        countertops: CountertopDetectorResult,
        roomStructure: AIRoomStructure,
        transform: FloorPlanTransform
    ) {
        for wallCountertop in countertops.wallCountertops {
            guard let wall = roomStructure.walls.first(where: { $0.id == wallCountertop.wallId }) else { continue }

            let startPosition = wallCountertop.startPositionInches
            let endPosition = wallCountertop.endPositionInches
            let depth = wallCountertop.depthInches

            // Calculate countertop position along wall
            let wallDir = simd_normalize(wall.endPoint - wall.startPoint)
            let wallNormal = SIMD2<Float>(-wallDir.y, wallDir.x)

            let startWorld = wall.startPoint + wallDir * startPosition
            let endWorld = wall.startPoint + wallDir * endPosition

            // Create countertop rectangle (extends from wall into room)
            let p1 = transform.transformPoint(worldCoordinate: startWorld)
            let p2 = transform.transformPoint(worldCoordinate: endWorld)
            let p3 = transform.transformPoint(worldCoordinate: endWorld + wallNormal * depth)
            let p4 = transform.transformPoint(worldCoordinate: startWorld + wallNormal * depth)

            // Draw as polygon with semi-transparent overlay
            let path = CGMutablePath()
            path.move(to: p1)
            path.addLine(to: p2)
            path.addLine(to: p3)
            path.addLine(to: p4)
            path.closeSubpath()

            context.setFillColor(FloorPlanColors.countertopOverlay.cgColor)
            context.addPath(path)
            context.fillPath()
        }
    }

    // MARK: - Task 7: Scale and Orientation

    /// Draws scale indicator in lower-right corner.
    private func drawScaleIndicator(
        context: CGContext,
        transform: FloorPlanTransform,
        canvasSize: CGSize
    ) {
        // Calculate scale bar length (use nice round number)
        let targetScaleBarPoints: CGFloat = 80
        let targetScaleBarInches = targetScaleBarPoints / transform.scale

        // Round to nice number (12, 24, 36, 48, 60 inches = 1, 2, 3, 4, 5 feet)
        let scaleBarInches: CGFloat
        if targetScaleBarInches >= ScaleBarThresholds.fiveFeet {
            scaleBarInches = ScaleBarValues.fiveFeetInches  // 5 feet
        } else if targetScaleBarInches >= ScaleBarThresholds.fourFeet {
            scaleBarInches = ScaleBarValues.fourFeetInches  // 4 feet
        } else if targetScaleBarInches >= ScaleBarThresholds.threeFeet {
            scaleBarInches = ScaleBarValues.threeFeetInches  // 3 feet
        } else if targetScaleBarInches >= ScaleBarThresholds.twoFeet {
            scaleBarInches = ScaleBarValues.twoFeetInches  // 2 feet
        } else {
            scaleBarInches = ScaleBarValues.oneFootInches  // 1 foot
        }

        let scaleBarPoints = scaleBarInches * transform.scale
        let scaleBarFeet = Int(scaleBarInches / 12)

        // Position in lower-right corner
        let barX = canvasSize.width - margin - scaleBarPoints
        let barY = canvasSize.height - margin + 20

        // Draw scale bar
        context.setStrokeColor(FloorPlanColors.scaleText.cgColor)
        context.setLineWidth(1.5)

        // Main bar
        context.move(to: CGPoint(x: barX, y: barY))
        context.addLine(to: CGPoint(x: barX + scaleBarPoints, y: barY))
        context.strokePath()

        // End ticks
        let tickHeight: CGFloat = 5
        context.move(to: CGPoint(x: barX, y: barY - tickHeight))
        context.addLine(to: CGPoint(x: barX, y: barY + tickHeight))
        context.strokePath()

        context.move(to: CGPoint(x: barX + scaleBarPoints, y: barY - tickHeight))
        context.addLine(to: CGPoint(x: barX + scaleBarPoints, y: barY + tickHeight))
        context.strokePath()

        // Label
        let attributes: [NSAttributedString.Key: Any] = [
            .font: scaleFont,
            .foregroundColor: FloorPlanColors.scaleText
        ]
        let text = "\(scaleBarFeet) ft" as NSString
        let textSize = text.size(withAttributes: attributes)
        text.draw(
            at: CGPoint(x: barX + scaleBarPoints / 2 - textSize.width / 2, y: barY + 5),
            withAttributes: attributes
        )
    }

    /// Draws orientation indicator (North arrow) in upper-right corner.
    private func drawOrientationIndicator(
        context: CGContext,
        canvasSize: CGSize
    ) {
        let centerX = canvasSize.width - margin
        let centerY = margin
        let arrowLength: CGFloat = 20
        let arrowWidth: CGFloat = 8

        // Draw arrow pointing up (North)
        context.setFillColor(FloorPlanColors.scaleText.cgColor)

        let path = CGMutablePath()
        path.move(to: CGPoint(x: centerX, y: centerY - arrowLength / 2))  // Top point
        path.addLine(to: CGPoint(x: centerX - arrowWidth / 2, y: centerY + arrowLength / 2))  // Bottom left
        path.addLine(to: CGPoint(x: centerX + arrowWidth / 2, y: centerY + arrowLength / 2))  // Bottom right
        path.closeSubpath()

        context.addPath(path)
        context.fillPath()

        // Draw "N" label
        let attributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.boldSystemFont(ofSize: 10),
            .foregroundColor: FloorPlanColors.scaleText
        ]
        let text = "N" as NSString
        let textSize = text.size(withAttributes: attributes)
        text.draw(
            at: CGPoint(x: centerX - textSize.width / 2, y: centerY - arrowLength / 2 - textSize.height - 2),
            withAttributes: attributes
        )
    }

    // MARK: - Helper Methods

    /// Formats dimension in feet and inches (e.g., "12' 6\"").
    private func formatDimension(inches: Float) -> String {
        let totalInches = Int(inches.rounded())
        let feet = totalInches / 12
        let remainingInches = totalInches % 12

        if remainingInches == 0 {
            return "\(feet)'"
        } else {
            return "\(feet)' \(remainingInches)\""
        }
    }

    /// Calculates scale description for metadata.
    private func calculateScaleDescription(transform: FloorPlanTransform) -> String {
        // Calculate what 1 inch on paper represents
        let inchesPerPoint = 1.0 / transform.scale
        let inchesPerPrintInch = inchesPerPoint * 72  // 72 points per inch

        if inchesPerPrintInch >= 24 {
            let feet = Int((inchesPerPrintInch / 12).rounded())
            return "1\" = \(feet)'"
        } else {
            return "1\" = \(Int(inchesPerPrintInch.rounded()))\""
        }
    }

    // MARK: - Story 6.2: Unscanned Areas

    /// Draws hatched pattern for unscanned areas.
    ///
    /// Per ADR-6.2.2, uses diagonal hatched pattern to indicate uncertainty.
    /// Divides room into 4 quadrants corresponding to capture zones.
    ///
    /// - Parameters:
    ///   - context: Core Graphics context
    ///   - uncapturedZones: Set of zones that were not captured
    ///   - transform: Coordinate transform for world to screen
    private func drawUnscannedAreas(
        context: CGContext,
        uncapturedZones: Set<AICaptureZone>,
        transform: FloorPlanTransform
    ) {
        // Get room bounds in screen coordinates
        let worldBounds = transform.worldBounds
        let screenMinX = worldBounds.minX * transform.scale + transform.offset.x
        let screenMaxX = worldBounds.maxX * transform.scale + transform.offset.x
        let screenMinY = worldBounds.minY * transform.scale + transform.offset.y
        let screenMaxY = worldBounds.maxY * transform.scale + transform.offset.y

        let centerX = (screenMinX + screenMaxX) / 2
        let centerY = (screenMinY + screenMaxY) / 2

        // Map zones to directional halves of the room
        // Per ADR-004, zones are direction-based from initial camera heading.
        // We divide the room into overlapping halves (not quadrants).
        // Front = bottom half (toward camera initial position)
        // Back = top half
        // Left = left half
        // Right = right half
        // Note: Zones intentionally overlap at corners - if "front" is uncaptured,
        // the bottom-left and bottom-right corners are also uncertain.
        let zoneRects: [(zone: AICaptureZone, rect: CGRect)] = [
            (.front, CGRect(x: screenMinX,
                           y: centerY,
                           width: screenMaxX - screenMinX,
                           height: screenMaxY - centerY)),
            (.back, CGRect(x: screenMinX,
                          y: screenMinY,
                          width: screenMaxX - screenMinX,
                          height: centerY - screenMinY)),
            (.left, CGRect(x: screenMinX,
                          y: screenMinY,
                          width: centerX - screenMinX,
                          height: screenMaxY - screenMinY)),
            (.right, CGRect(x: centerX,
                           y: screenMinY,
                           width: screenMaxX - centerX,
                           height: screenMaxY - screenMinY))
        ]

        // Draw hatched pattern for each uncaptured zone
        for (zone, rect) in zoneRects {
            if uncapturedZones.contains(zone) {
                drawHatchedPattern(context: context, rect: rect)
            }
        }

        // Add legend for unscanned areas if any zones are uncaptured
        if !uncapturedZones.isEmpty {
            drawUnscannedLegend(context: context, transform: transform)
        }
    }

    /// Draws diagonal hatched pattern within a rectangle.
    private func drawHatchedPattern(context: CGContext, rect: CGRect) {
        context.saveGState()
        context.clip(to: rect)

        context.setStrokeColor(FloorPlanColors.unscannedHatchStroke.cgColor)
        context.setLineWidth(1.0)

        let spacing: CGFloat = 10.0
        let diagonal = sqrt(rect.width * rect.width + rect.height * rect.height)

        // Draw diagonal lines from bottom-left to top-right
        var offset: CGFloat = -diagonal
        while offset < diagonal {
            let startX = rect.minX + offset
            let startY = rect.maxY
            let endX = startX + rect.height
            let endY = rect.minY

            context.move(to: CGPoint(x: startX, y: startY))
            context.addLine(to: CGPoint(x: endX, y: endY))
            offset += spacing
        }
        context.strokePath()

        context.restoreGState()
    }

    /// Draws legend entry for unscanned areas.
    private func drawUnscannedLegend(context: CGContext, transform: FloorPlanTransform) {
        let legendX = transform.offset.x
        let legendY = transform.canvasSize.height - margin + 10

        // Draw small hatched sample
        let sampleRect = CGRect(x: legendX, y: legendY, width: 15, height: 15)
        drawHatchedPattern(context: context, rect: sampleRect)

        // Draw border around sample
        context.setStrokeColor(FloorPlanColors.unscannedLabelText.cgColor)
        context.setLineWidth(0.5)
        context.stroke(sampleRect)

        // Draw label
        let attributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 8, weight: .regular),
            .foregroundColor: FloorPlanColors.unscannedLabelText
        ]
        let text = "Unscanned Area" as NSString
        text.draw(
            at: CGPoint(x: legendX + 20, y: legendY + 2),
            withAttributes: attributes
        )
    }
}

// MARK: - Appliance Type Extension

extension AIApplianceType {
    /// Short label for floor plan rendering.
    var shortLabel: String {
        switch self {
        case .refrigerator: return "Ref"
        case .range: return "Range"
        case .cooktop: return "Cooktop"
        case .wallOven: return "Oven"
        case .dishwasher: return "DW"
        case .microwave: return "MW"
        case .hood: return "Hood"
        case .sink: return "Sink"
        case .other: return "?"
        }
    }
}
