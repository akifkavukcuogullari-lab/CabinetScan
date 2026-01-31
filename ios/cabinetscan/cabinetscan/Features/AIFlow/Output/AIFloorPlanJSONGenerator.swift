//
//  AIFloorPlanJSONGenerator.swift
//  cabinetscan
//
//  Created for Story 5.2: Floor Plan JSON Data Structure
//

import Foundation
import simd

// MARK: - Floor Plan JSON Generator

/// Generates LiDAR-compatible JSON from AI pipeline detection results.
///
/// **Usage:**
/// ```swift
/// let generator = AIFloorPlanJSONGenerator()
/// let json = generator.generate(from: pipelineResult)
/// try generator.export(json, to: outputURL)
/// ```
///
/// **LiDAR Compatibility:**
/// - Uses FEET for all measurements (converts from AI pipeline inches)
/// - Uses `{ "x": 0, "z": 0 }` position objects (not arrays)
/// - Uses `"lower"` for base cabinets (not `"base"`)
/// - Includes formatted dimension strings like `"3' 6\""`
/// - Maintains same structure under `measurements` key as LiDAR format
///
/// **AI Extensions (per ADR-002):**
/// - AI-specific fields prefixed with `ai_`
/// - Confidence as string enum on objects, numeric in `ai_metadata`
/// - Islands/peninsulas as top-level arrays (per ADR-003)
/// - Schema version in `ai_metadata.schema_version` (per ADR-005)
final class AIFloorPlanJSONGenerator {

    // MARK: - Constants

    /// Current schema version (per ADR-005)
    private let schemaVersion = "1.0"

    /// Scan method identifier for AI Flow
    private let scanMethod = "aiFlow"

    // MARK: - Initialization

    init() {}

    // MARK: - Main Generation Method

    /// Generates floor plan JSON from pipeline results.
    ///
    /// - Parameter pipelineResult: The AI pipeline result containing all detection outputs
    /// - Returns: Complete JSON structure ready for export
    /// - Throws: `JSONGenerationError.missingRoomStructure` if room structure is nil
    func generate(from pipelineResult: AIPipelineResult) throws -> FloorPlanJSON {
        let startTime = Date()

        // Room structure is required for JSON generation
        guard let roomStructure = pipelineResult.roomStructure else {
            throw JSONGenerationError.missingRoomStructure
        }

        // Convert room structure
        let room = convertRoom(roomStructure)
        let wallConfidence = AIConfidenceLevel.from(score: roomStructure.confidence.wallConfidence)
        let walls = convertWalls(roomStructure.walls, confidence: wallConfidence)

        // Convert detection results (using correct AIPipelineResult property names)
        let cabinets = convertCabinets(pipelineResult.detectedCabinets)
        let appliances = convertAppliances(pipelineResult.detectedAppliances)
        let (doors, windows) = convertOpenings(pipelineResult.detectedOpenings)
        let islands = convertIslands(pipelineResult.detectedIslandsPeninsulas)
        let peninsulas = convertPeninsulas(pipelineResult.detectedIslandsPeninsulas)
        let countertops = convertCountertops(pipelineResult.detectedCountertops)

        // Generate summary and metadata
        let aiSummary = generateAISummary(from: pipelineResult)
        let processingTimeMs = Int((Date().timeIntervalSince(startTime) * 1000).rounded())
        let aiMetadata = generateAIMetadata(from: pipelineResult, roomStructure: roomStructure, processingTimeMs: processingTimeMs)

        // Calculate totals
        let totalLinearFt = calculateTotalLinearFeet(from: pipelineResult)
        let totalSqFt = Float(roomStructure.dimensions.areaSquareInches) / 144.0  // sq.in to sq.ft (144 = 12²)

        // Build measurements object
        let measurements = MeasurementsJSON(
            room: room,
            walls: walls,
            doors: doors,
            windows: windows,
            cabinets: cabinets,
            appliances: appliances,
            islands: islands,
            peninsulas: peninsulas,
            countertops: countertops,
            scanMethod: scanMethod,
            aiMetadata: aiMetadata,
            aiSummary: aiSummary
        )

        // Build roomplan_data
        let roomplanData = RoomplanDataJSON(
            walls: walls.count,
            doors: doors.count,
            windows: windows.count,
            floors: 1,
            openings: roomStructure.openBoundaries.count
        )

        return FloorPlanJSON(
            roomName: "Kitchen",
            roomType: "kitchen",
            roomplanData: roomplanData,
            totalLinearFt: totalLinearFt,
            totalSqFt: totalSqFt,
            wallCount: walls.count,
            windowCount: windows.count,
            doorCount: doors.count,
            measurements: measurements
        )
    }

    // MARK: - Export Method

    /// Exports JSON to a file.
    ///
    /// - Parameters:
    ///   - json: The floor plan JSON to export
    ///   - url: The destination URL
    /// - Throws: Encoding or file write errors
    func export(_ json: FloorPlanJSON, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.keyEncodingStrategy = .convertToSnakeCase

        let data = try encoder.encode(json)
        try data.write(to: url)
    }

    /// Exports JSON and returns the data without writing to file.
    ///
    /// - Parameter json: The floor plan JSON to export
    /// - Returns: Encoded JSON data
    /// - Throws: Encoding errors
    func exportData(_ json: FloorPlanJSON) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.keyEncodingStrategy = .convertToSnakeCase

        return try encoder.encode(json)
    }

    // MARK: - Unit Conversion (ADR-001)

    /// Converts inches to feet.
    ///
    /// - Parameter inches: Measurement in inches
    /// - Returns: Measurement in feet
    private func inchesToFeet(_ inches: Float) -> Float {
        inches / 12.0
    }

    /// Formats inches as feet and inches string (e.g., "3' 6\"").
    ///
    /// - Parameter totalInches: Total measurement in inches
    /// - Returns: Formatted string in feet and inches
    private func formatAsFeetInches(_ totalInches: Float) -> String {
        let feet = Int(totalInches / 12)
        let inches = totalInches.truncatingRemainder(dividingBy: 12)
        let roundedInches = (inches * 2).rounded() / 2  // Round to nearest 0.5"

        if roundedInches == 0 || roundedInches >= 12 {
            return "\(feet)' 0\""
        } else if roundedInches == roundedInches.rounded() {
            return "\(feet)' \(Int(roundedInches))\""
        } else {
            return "\(feet)' \(String(format: "%.1f", roundedInches))\""
        }
    }

    /// Converts a 2D point from inches to feet and creates a position object.
    ///
    /// - Parameters:
    ///   - point: 2D point in inches (x, z in world space)
    ///   - heightInches: Optional Y height in inches
    /// - Returns: Position JSON object in feet
    private func toPositionJSON(_ point: SIMD2<Float>, heightInches: Float? = nil) -> PositionJSON {
        PositionJSON(
            x: inchesToFeet(point.x),
            z: inchesToFeet(point.y),  // .y in SIMD2 is Z in world space
            y: heightInches.map { inchesToFeet($0) }
        )
    }

    /// Converts a 3D point from inches to feet and creates a position object.
    ///
    /// - Parameter point: 3D point in inches (x, y, z)
    /// - Returns: Position JSON object in feet
    private func toPositionJSON3D(_ point: SIMD3<Float>) -> PositionJSON {
        PositionJSON(
            x: inchesToFeet(point.x),
            z: inchesToFeet(point.z),
            y: inchesToFeet(point.y)
        )
    }

    // MARK: - Room Conversion

    /// Converts room structure to JSON.
    private func convertRoom(_ roomStructure: AIRoomStructure) -> RoomJSON {
        // Calculate bounds from boundary polygon
        let bounds = calculateBounds(from: roomStructure.boundaryPolygon)

        return RoomJSON(
            minX: inchesToFeet(bounds.minX),
            maxX: inchesToFeet(bounds.maxX),
            minZ: inchesToFeet(bounds.minZ),
            maxZ: inchesToFeet(bounds.maxZ),
            ceilingHeightFt: inchesToFeet(Float(roomStructure.ceilingHeightInches)),
            shape: roomStructure.roomShape.rawValue,
            confidence: roomStructure.confidence.level.jsonString
        )
    }

    /// Calculates bounding box from polygon points.
    private func calculateBounds(from polygon: [SIMD2<Float>]) -> (minX: Float, maxX: Float, minZ: Float, maxZ: Float) {
        guard !polygon.isEmpty else {
            return (0, 0, 0, 0)
        }

        var minX: Float = .infinity
        var maxX: Float = -.infinity
        var minZ: Float = .infinity
        var maxZ: Float = -.infinity

        for point in polygon {
            minX = min(minX, point.x)
            maxX = max(maxX, point.x)
            minZ = min(minZ, point.y)  // .y is Z in SIMD2
            maxZ = max(maxZ, point.y)
        }

        return (minX, maxX, minZ, maxZ)
    }

    // MARK: - Wall Conversion

    /// Converts walls to JSON array.
    /// - Parameters:
    ///   - walls: Array of walls to convert
    ///   - confidence: Overall wall detection confidence from room structure
    private func convertWalls(_ walls: [AIWall], confidence: AIConfidenceLevel) -> [WallJSON] {
        walls.enumerated().map { index, wall in
            // Calculate midpoint for position
            let midpoint = SIMD2<Float>(
                (wall.startPoint.x + wall.endPoint.x) / 2,
                (wall.startPoint.y + wall.endPoint.y) / 2
            )

            return WallJSON(
                id: "wall_\(index + 1)",
                position: toPositionJSON(midpoint),
                start: toPositionJSON(wall.startPoint),
                end: toPositionJSON(wall.endPoint),
                widthFt: inchesToFeet(Float(wall.lengthInches)),
                heightFt: inchesToFeet(Float(wall.heightInches)),
                thicknessFt: 0.5,  // Standard wall thickness
                linearFt: inchesToFeet(Float(wall.lengthInches)),
                aiBoundaryType: wall.boundaryType.rawValue,  // AI extension per ADR-002
                confidence: confidence.jsonString  // Derived from room structure wall confidence
            )
        }
    }

    // MARK: - Cabinet Conversion

    /// Converts cabinet detection result to JSON.
    private func convertCabinets(_ result: CabinetDetectionResult?) -> CabinetsJSON {
        guard let result = result else {
            return CabinetsJSON(upper: [], lower: [], tall: [])
        }

        var upperCabinets: [CabinetJSON] = []
        var lowerCabinets: [CabinetJSON] = []
        var tallCabinets: [CabinetJSON] = []

        // Use per-type indices for sequential IDs (lower_1, lower_2, etc.)
        var upperIndex = 0
        var lowerIndex = 0
        var tallIndex = 0

        for cabinet in result.cabinets {
            switch cabinet.type {
            case .upper:
                let cabinetJSON = convertCabinet(cabinet, typeIndex: upperIndex)
                upperCabinets.append(cabinetJSON)
                upperIndex += 1
            case .base:
                let cabinetJSON = convertCabinet(cabinet, typeIndex: lowerIndex)
                lowerCabinets.append(cabinetJSON)  // Use "lower" per LiDAR convention
                lowerIndex += 1
            case .tall:
                let cabinetJSON = convertCabinet(cabinet, typeIndex: tallIndex)
                tallCabinets.append(cabinetJSON)
                tallIndex += 1
            }
        }

        return CabinetsJSON(
            upper: upperCabinets,
            lower: lowerCabinets,
            tall: tallCabinets.isEmpty ? nil : tallCabinets
        )
    }

    /// Converts a single cabinet to JSON.
    /// - Parameters:
    ///   - cabinet: The cabinet to convert
    ///   - typeIndex: The index within the cabinet's type (0-based, for sequential IDs)
    private func convertCabinet(_ cabinet: AIDetectedCabinet, typeIndex: Int) -> CabinetJSON {
        // Calculate Y position (height from floor to center of cabinet)
        let heightFromFloor: Float
        switch cabinet.type {
        case .base:
            heightFromFloor = cabinet.heightInches / 2  // Center of base cabinet
        case .upper:
            heightFromFloor = 54 + cabinet.heightInches / 2  // Standard 54" AFF + half height
        case .tall:
            heightFromFloor = cabinet.heightInches / 2  // Center of tall cabinet from floor
        }

        // Get position from bounding box center
        let position = PositionJSON(
            x: inchesToFeet(cabinet.boundingBox.center.x),
            z: inchesToFeet(cabinet.boundingBox.center.z),
            y: inchesToFeet(heightFromFloor)
        )

        // Determine type string and ID prefix
        let typeString: String
        let idPrefix: String
        switch cabinet.type {
        case .base:
            typeString = "lower_cabinet"  // Use "lower" per LiDAR convention
            idPrefix = "lower"
        case .upper:
            typeString = "upper_cabinet"
            idPrefix = "upper"
        case .tall:
            typeString = "tall_cabinet"
            idPrefix = "tall"
        }

        // Raw dimensions for AI extension
        let rawDimensions = DimensionsJSON(
            widthFt: inchesToFeet(cabinet.rawWidthInches),
            heightFt: inchesToFeet(cabinet.rawHeightInches),
            depthFt: inchesToFeet(cabinet.rawDepthInches)
        )

        return CabinetJSON(
            id: "\(idPrefix)_\(typeIndex + 1)",  // Sequential per-type: lower_1, lower_2, etc.
            type: typeString,
            position: position,
            widthFt: inchesToFeet(cabinet.widthInches),
            heightFt: inchesToFeet(cabinet.heightInches),
            depthFt: inchesToFeet(cabinet.depthInches),
            widthInches: formatAsFeetInches(cabinet.widthInches),
            heightInches: formatAsFeetInches(cabinet.heightInches),
            depthInches: formatAsFeetInches(cabinet.depthInches),
            confidence: cabinet.confidence.jsonString,
            aiIsStandardSize: cabinet.isStandardSize,
            aiCornerType: cabinet.cornerType?.rawValue,
            aiSpecialType: cabinet.specialType?.rawValue,
            aiRawDimensions: rawDimensions
        )
    }

    // MARK: - Appliance Conversion

    /// Converts appliance detection result to JSON array.
    private func convertAppliances(_ result: ApplianceDetectionResult?) -> [ApplianceJSON] {
        guard let result = result else { return [] }

        return result.appliances.enumerated().map { index, appliance in
            let position = PositionJSON(
                x: inchesToFeet(appliance.boundingBox.center.x),
                z: inchesToFeet(appliance.boundingBox.center.z),
                y: inchesToFeet(appliance.boundingBox.center.y)
            )

            return ApplianceJSON(
                id: "appliance_\(index + 1)",
                type: appliance.type.rawValue,
                subType: appliance.subType?.rawValue,
                position: position,
                widthFt: inchesToFeet(appliance.widthInches),
                heightFt: inchesToFeet(appliance.heightInches),
                depthFt: inchesToFeet(appliance.depthInches),
                widthInches: formatAsFeetInches(appliance.widthInches),
                heightInches: formatAsFeetInches(appliance.heightInches),
                depthInches: formatAsFeetInches(appliance.depthInches),
                confidence: appliance.confidence.jsonString,
                aiIsBuiltIn: appliance.isBuiltIn,
                aiIsCounterDepth: appliance.isCounterDepth
            )
        }
    }

    // MARK: - Opening Conversion

    /// Converts opening detection result to doors and windows JSON arrays.
    private func convertOpenings(_ result: OpeningDetectionResult?) -> (doors: [DoorJSON], windows: [WindowJSON]) {
        guard let result = result else { return ([], []) }

        let doors = result.doors.enumerated().map { index, door in
            let position = PositionJSON(
                x: inchesToFeet(door.boundingBox.center.x),
                z: inchesToFeet(door.boundingBox.center.z),
                y: nil
            )

            // Raw dimensions for AI extension (from rawDimensions SIMD3)
            let rawDimensions = DimensionsJSON(
                widthFt: inchesToFeet(door.rawDimensions.x),
                heightFt: inchesToFeet(door.rawDimensions.y),
                depthFt: nil
            )

            return DoorJSON(
                id: "door_\(index + 1)",
                position: position,
                widthFt: inchesToFeet(door.widthInches),
                heightFt: inchesToFeet(door.heightInches),
                widthInches: formatAsFeetInches(door.widthInches),
                heightInches: formatAsFeetInches(door.heightInches),
                aiSwingDirection: door.swingDirection?.rawValue,
                confidence: door.confidence.jsonString,
                aiRawDimensions: rawDimensions
            )
        }

        let windows = result.windows.enumerated().map { index, window in
            let position = PositionJSON(
                x: inchesToFeet(window.boundingBox.center.x),
                z: inchesToFeet(window.boundingBox.center.z),
                y: nil
            )

            // Calculate area
            let areaFt = inchesToFeet(window.widthInches) * inchesToFeet(window.heightInches)

            // Raw dimensions for AI extension (from rawDimensions SIMD3)
            let rawDimensions = DimensionsJSON(
                widthFt: inchesToFeet(window.rawDimensions.x),
                heightFt: inchesToFeet(window.rawDimensions.y),
                depthFt: nil
            )

            return WindowJSON(
                id: "window_\(index + 1)",
                position: position,
                widthFt: inchesToFeet(window.widthInches),
                heightFt: inchesToFeet(window.heightInches),
                widthInches: formatAsFeetInches(window.widthInches),
                heightInches: formatAsFeetInches(window.heightInches),
                areaSqft: areaFt,
                aiSillHeightFt: inchesToFeet(window.sillHeightInches),
                confidence: window.confidence.jsonString,
                aiRawDimensions: rawDimensions
            )
        }

        return (doors, windows)
    }

    // MARK: - Island/Peninsula Conversion (ADR-003)

    /// Converts islands to JSON array.
    private func convertIslands(_ result: IslandPeninsulaDetectionResult?) -> [IslandJSON] {
        guard let result = result else { return [] }

        return result.islands.enumerated().map { index, island in
            let position = toPositionJSON(island.position)

            return IslandJSON(
                id: "island_\(index + 1)",
                position: position,
                lengthFt: inchesToFeet(island.lengthInches),
                widthFt: inchesToFeet(island.widthInches),
                heightFt: inchesToFeet(island.heightInches),
                rotation: island.rotation,
                hasSeating: island.hasSeating,
                seatingOverhangFt: island.seatingOverhangInches.map { inchesToFeet($0) },
                countertopAreaSqft: island.countertopAreaSquareFeet,
                confidence: island.confidence.jsonString
            )
        }
    }

    /// Converts peninsulas to JSON array.
    private func convertPeninsulas(_ result: IslandPeninsulaDetectionResult?) -> [PeninsulaJSON] {
        guard let result = result else { return [] }

        return result.peninsulas.enumerated().map { index, peninsula in
            let position = PositionJSON(
                x: inchesToFeet(peninsula.boundingBox.center.x),
                z: inchesToFeet(peninsula.boundingBox.center.z),
                y: nil
            )

            return PeninsulaJSON(
                id: "peninsula_\(index + 1)",
                position: position,
                attachedWallId: peninsula.attachedWallId.uuidString,
                lengthFt: inchesToFeet(peninsula.lengthInches),
                widthFt: inchesToFeet(peninsula.widthInches),
                heightFt: inchesToFeet(peninsula.heightInches),
                extendsDirection: peninsula.extendsDirection.rawValue,
                hasSeating: peninsula.hasSeating,
                seatingOverhangFt: peninsula.seatingOverhangInches.map { inchesToFeet($0) },
                countertopAreaSqft: peninsula.countertopAreaSquareFeet,
                confidence: peninsula.confidence.jsonString
            )
        }
    }

    // MARK: - Countertop Conversion

    /// Converts countertop detection result to JSON.
    private func convertCountertops(_ result: CountertopDetectorResult?) -> CountertopsJSON? {
        guard let result = result else { return nil }

        let wallCountertops = result.wallCountertops.map { countertop in
            WallCountertopJSON(
                wallId: countertop.wallId.uuidString,
                startPositionFt: inchesToFeet(countertop.startPositionInches),
                endPositionFt: inchesToFeet(countertop.endPositionInches),
                depthFt: inchesToFeet(countertop.depthInches),
                areaSqft: countertop.netAreaSquareInches / 144.0,
                confidence: countertop.confidence.jsonString
            )
        }

        // Use values from countertopSummary
        let ctSummary = result.countertopSummary
        let wallCountertopSqft = ctSummary.wallNetAreaSquareInches / 144.0
        let islandCountertopSqft = ctSummary.islandTotalSquareInches / 144.0
        let peninsulaCountertopSqft = ctSummary.peninsulaTotalSquareInches / 144.0

        // Calculate cutout area
        let cutoutSqft = ctSummary.allCutouts.reduce(0.0) { $0 + $1.areaSquareInches / 144.0 }
        let netTotalSqft = wallCountertopSqft + islandCountertopSqft + peninsulaCountertopSqft

        let summary = CountertopSummaryJSON(
            wallCountertopSqft: Float(wallCountertopSqft),
            islandCountertopSqft: Float(islandCountertopSqft),
            peninsulaCountertopSqft: Float(peninsulaCountertopSqft),
            cutoutSqft: Float(cutoutSqft),
            netTotalSqft: Float(netTotalSqft)
        )

        return CountertopsJSON(
            wallCountertops: wallCountertops,
            summary: summary
        )
    }

    // MARK: - Summary and Metadata Generation (ADR-004, ADR-005)

    /// Generates AI summary with cabinet counts and linear feet.
    private func generateAISummary(from result: AIPipelineResult) -> AISummaryJSON {
        let cabinetResult = result.detectedCabinets

        // Cabinet counts
        let upperCount = cabinetResult?.upperCabinets.count ?? 0
        let lowerCount = cabinetResult?.baseCabinets.count ?? 0
        let tallCount = cabinetResult?.tallCabinets.count ?? 0
        let cornerCount = cabinetResult?.cornerCabinets.count ?? 0

        let cabinetCounts = CabinetCountsJSON(
            upper: upperCount,
            lower: lowerCount,
            tall: tallCount,
            corner: cornerCount
        )

        // Linear feet
        let upperLinearFt = cabinetResult?.upperLinearFeetTotal ?? 0
        let lowerLinearFt = cabinetResult?.baseLinearFeetTotal ?? 0
        let tallLinearFt = cabinetResult?.tallCabinets.reduce(0.0) { $0 + Double($1.widthInches) / 12.0 } ?? 0

        let linearFeet = LinearFeetJSON(
            upper: upperLinearFt,
            lower: lowerLinearFt,
            tall: tallLinearFt
        )

        return AISummaryJSON(
            cabinetCounts: cabinetCounts,
            linearFeet: linearFeet
        )
    }

    /// Generates AI metadata with schema version, confidence scores, and calibration info.
    private func generateAIMetadata(
        from result: AIPipelineResult,
        roomStructure: AIRoomStructure,
        processingTimeMs: Int
    ) -> AIMetadataJSON {
        // Calculate confidence scores
        let roomConfidence = roomStructure.confidence.overall
        let cabinetConfidenceLevel = result.detectedCabinets?.overallConfidence ?? .low
        let cabinetConfidence = cabinetConfidenceLevel.numericScore
        let applianceConfidence = result.detectedAppliances?.appliances.map { $0.confidence.numericScore }.average ?? 0.0

        let overallScore = (roomConfidence + cabinetConfidence + Float(applianceConfidence)) / 3.0
        let overallConfidence = AIConfidenceLevel.from(score: overallScore)

        // Get calibration method from ScaleCalibrationResult
        let calibrationMethod: String
        switch result.calibration.calibrationMethod {
        case .autoCountertop:
            calibrationMethod = "autoCountertop"
        case .autoCeiling:
            calibrationMethod = "autoCeiling"
        case .manualDoor:
            calibrationMethod = "manualDoor"
        case .manualCeiling:
            calibrationMethod = "manualCeiling"
        case .failed:
            calibrationMethod = "failed"
        }

        return AIMetadataJSON(
            schemaVersion: schemaVersion,
            overallConfidence: overallConfidence.jsonString,
            confidenceScore: overallScore,
            roomConfidenceScore: roomConfidence,
            cabinetConfidenceScore: cabinetConfidence,
            applianceConfidenceScore: Float(applianceConfidence),
            calibrationMethod: calibrationMethod,
            processingTimeMs: processingTimeMs
        )
    }

    /// Calculates total linear feet from cabinet detection.
    private func calculateTotalLinearFeet(from result: AIPipelineResult) -> Float {
        guard let cabinetResult = result.detectedCabinets else { return 0 }
        return Float(cabinetResult.baseLinearFeetTotal + cabinetResult.upperLinearFeetTotal)
    }
}

// MARK: - JSON Generation Error

/// Errors that can occur during JSON generation.
enum JSONGenerationError: LocalizedError {
    /// Room structure is required but was nil
    case missingRoomStructure

    var errorDescription: String? {
        switch self {
        case .missingRoomStructure:
            return "Room structure is required for JSON generation"
        }
    }
}

// MARK: - JSON Data Structures

/// Root floor plan JSON structure.
struct FloorPlanJSON: Codable {
    let roomName: String
    let roomType: String
    let roomplanData: RoomplanDataJSON
    let totalLinearFt: Float
    let totalSqFt: Float
    let wallCount: Int
    let windowCount: Int
    let doorCount: Int
    let measurements: MeasurementsJSON
}

/// RoomPlan data summary.
struct RoomplanDataJSON: Codable {
    let walls: Int
    let doors: Int
    let windows: Int
    let floors: Int
    let openings: Int
}

/// Main measurements container matching LiDAR structure.
struct MeasurementsJSON: Codable {
    let room: RoomJSON
    let walls: [WallJSON]
    let doors: [DoorJSON]
    let windows: [WindowJSON]
    let cabinets: CabinetsJSON
    let appliances: [ApplianceJSON]
    let islands: [IslandJSON]
    let peninsulas: [PeninsulaJSON]
    let countertops: CountertopsJSON?
    let scanMethod: String
    let aiMetadata: AIMetadataJSON
    let aiSummary: AISummaryJSON
}

/// Room bounds and shape.
struct RoomJSON: Codable {
    let minX: Float
    let maxX: Float
    let minZ: Float
    let maxZ: Float
    let ceilingHeightFt: Float
    let shape: String
    let confidence: String
}

/// Wall data.
struct WallJSON: Codable {
    let id: String
    let position: PositionJSON
    let start: PositionJSON
    let end: PositionJSON
    let widthFt: Float
    let heightFt: Float
    let thicknessFt: Float
    let linearFt: Float
    let aiBoundaryType: String  // AI extension per ADR-002 (not in LiDAR format)
    let confidence: String
}

/// 2D or 3D position object (NOT array format).
struct PositionJSON: Codable {
    let x: Float
    let z: Float
    let y: Float?
}

/// Door data.
struct DoorJSON: Codable {
    let id: String
    let position: PositionJSON
    let widthFt: Float
    let heightFt: Float
    let widthInches: String
    let heightInches: String
    let aiSwingDirection: String?
    let confidence: String
    let aiRawDimensions: DimensionsJSON?
}

/// Window data.
struct WindowJSON: Codable {
    let id: String
    let position: PositionJSON
    let widthFt: Float
    let heightFt: Float
    let widthInches: String
    let heightInches: String
    let areaSqft: Float
    let aiSillHeightFt: Float
    let confidence: String
    let aiRawDimensions: DimensionsJSON?
}

/// Cabinet container with upper/lower/tall arrays.
/// Note: Uses "lower" NOT "base" to match LiDAR convention.
struct CabinetsJSON: Codable {
    let upper: [CabinetJSON]
    let lower: [CabinetJSON]
    let tall: [CabinetJSON]?
}

/// Individual cabinet data.
struct CabinetJSON: Codable {
    let id: String
    let type: String
    let position: PositionJSON
    let widthFt: Float
    let heightFt: Float
    let depthFt: Float
    let widthInches: String
    let heightInches: String
    let depthInches: String
    let confidence: String?
    let aiIsStandardSize: Bool?
    let aiCornerType: String?
    let aiSpecialType: String?
    let aiRawDimensions: DimensionsJSON?
}

/// Appliance data.
struct ApplianceJSON: Codable {
    let id: String
    let type: String
    let subType: String?
    let position: PositionJSON
    let widthFt: Float
    let heightFt: Float
    let depthFt: Float
    let widthInches: String
    let heightInches: String
    let depthInches: String
    let confidence: String?
    let aiIsBuiltIn: Bool?
    let aiIsCounterDepth: Bool?
}

/// Island data (AI Flow exclusive - per ADR-003).
struct IslandJSON: Codable {
    let id: String
    let position: PositionJSON
    let lengthFt: Float
    let widthFt: Float
    let heightFt: Float
    let rotation: Float
    let hasSeating: Bool
    let seatingOverhangFt: Float?
    let countertopAreaSqft: Float
    let confidence: String
}

/// Peninsula data (AI Flow exclusive - per ADR-003).
struct PeninsulaJSON: Codable {
    let id: String
    let position: PositionJSON
    let attachedWallId: String
    let lengthFt: Float
    let widthFt: Float
    let heightFt: Float
    let extendsDirection: String
    let hasSeating: Bool
    let seatingOverhangFt: Float?
    let countertopAreaSqft: Float
    let confidence: String
}

/// Countertops container.
struct CountertopsJSON: Codable {
    let wallCountertops: [WallCountertopJSON]
    let summary: CountertopSummaryJSON
}

/// Wall countertop segment.
struct WallCountertopJSON: Codable {
    let wallId: String
    let startPositionFt: Float
    let endPositionFt: Float
    let depthFt: Float
    let areaSqft: Float
    let confidence: String
}

/// Countertop summary with area calculations.
struct CountertopSummaryJSON: Codable {
    let wallCountertopSqft: Float
    let islandCountertopSqft: Float
    let peninsulaCountertopSqft: Float
    let cutoutSqft: Float
    let netTotalSqft: Float
}

/// Raw dimensions before snapping (AI extension).
struct DimensionsJSON: Codable {
    let widthFt: Float
    let heightFt: Float
    let depthFt: Float?
}

/// AI metadata (per ADR-004, ADR-005).
struct AIMetadataJSON: Codable {
    let schemaVersion: String
    let overallConfidence: String
    let confidenceScore: Float
    let roomConfidenceScore: Float
    let cabinetConfidenceScore: Float
    let applianceConfidenceScore: Float
    let calibrationMethod: String
    let processingTimeMs: Int
}

/// AI summary with cabinet counts and linear feet.
struct AISummaryJSON: Codable {
    let cabinetCounts: CabinetCountsJSON
    let linearFeet: LinearFeetJSON
}

/// Cabinet counts by type.
struct CabinetCountsJSON: Codable {
    let upper: Int
    let lower: Int
    let tall: Int
    let corner: Int
}

/// Linear feet by cabinet type.
struct LinearFeetJSON: Codable {
    let upper: Double
    let lower: Double
    let tall: Double
}

// MARK: - AIConfidenceLevel Extension

extension AIConfidenceLevel {
    /// JSON string representation (for floor plan JSON output).
    var jsonString: String {
        switch self {
        case .high: return "high"
        case .medium: return "medium"
        case .low: return "low"
        }
    }

    /// Numeric score for JSON metadata output (floor plan specific).
    /// Returns the midpoint of each confidence range.
    fileprivate var numericScore: Float {
        switch self {
        case .high: return 0.9   // 80-100%, midpoint ~90%
        case .medium: return 0.7 // 60-79%, midpoint ~70%
        case .low: return 0.4    // 0-59%, midpoint ~40%
        }
    }
}

// MARK: - Array Extension

private extension Array where Element == Float {
    var average: Double {
        guard !isEmpty else { return 0 }
        return Double(reduce(0, +)) / Double(count)
    }
}
