import SwiftUI
import RoomPlan
import simd

struct ScanningView: View {
    @EnvironmentObject var appState: AppState
    @State private var isScanning = false
    @State private var isProcessing = false
    @State private var processingStatus = "Processing scan..."
    @State private var capturedRoom: CapturedRoom?
    @State private var rotationAngle: Double = 0

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                if isScanning {
                    RoomCaptureViewRepresentable(
                        isScanning: $isScanning,
                        capturedRoom: $capturedRoom,
                        onComplete: handleScanComplete
                    )
                    .ignoresSafeArea()
                } else if isProcessing {
                    // Processing view - shown after scan, before navigation
                    VStack(spacing: 32) {
                        Spacer()

                        ZStack {
                            Circle()
                                .stroke(Color.blue.opacity(0.2), lineWidth: 8)
                                .frame(width: 120, height: 120)

                            Circle()
                                .trim(from: 0, to: 0.7)
                                .stroke(Color.blue, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                                .frame(width: 120, height: 120)
                                .rotationEffect(.degrees(rotationAngle))

                            Image(systemName: "cube.transparent")
                                .font(.system(size: 40))
                                .foregroundStyle(.blue)
                        }
                        .onAppear {
                            withAnimation(.linear(duration: 1).repeatForever(autoreverses: false)) {
                                rotationAngle = 360
                            }
                        }

                        VStack(spacing: 12) {
                            Text("Processing Your Scan")
                                .font(.title2)
                                .fontWeight(.bold)

                            Text(processingStatus)
                                .font(.body)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 32)
                                .animation(.easeInOut(duration: 0.3), value: processingStatus)
                        }

                        Text("This may take a moment...")
                            .font(.caption)
                            .foregroundStyle(.tertiary)

                        Spacer()
                    }
                } else {
                    // Pre-scan instructions
                    VStack(spacing: 32) {
                        Spacer()

                        Image(systemName: "camera.viewfinder")
                            .font(.system(size: 80))
                            .foregroundStyle(.blue)

                        VStack(spacing: 12) {
                            Text("Scan Your Space")
                                .font(.title)
                                .fontWeight(.bold)

                            Text("Point your camera at the room and slowly pan around to capture all walls, doors, and windows.")
                                .font(.body)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 32)
                        }

                        VStack(alignment: .leading, spacing: 12) {
                            InstructionRow(icon: "lightbulb", text: "Ensure good lighting")
                            InstructionRow(icon: "arrow.triangle.2.circlepath", text: "Move slowly and steadily")
                            InstructionRow(icon: "square.dashed", text: "Cover all corners")
                        }
                        .padding()
                        .background(Color(.systemGray6))
                        .clipShape(RoundedRectangle(cornerRadius: 12))

                        Spacer()

                        Button {
                            isScanning = true
                        } label: {
                            Label("Start Scanning", systemImage: "camera")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .padding(.horizontal)
                        .padding(.bottom, 32)
                    }
                }
            }
            .navigationTitle(isScanning ? "Scanning" : (isProcessing ? "Processing" : "Room Scan"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    if !isScanning && !isProcessing {
                        Button("Back") {
                            appState.currentScreen = .customerInfo
                        }
                    }
                }

                if isScanning {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("Done") {
                            isScanning = false
                        }
                    }
                }
            }
        }
    }

    private func handleScanComplete(room: CapturedRoom) {
        capturedRoom = room
        isProcessing = true
        processingStatus = "Analyzing room data..."

        // Process scan data asynchronously
        Task {
            await processScanData(room: room)
        }
    }

    private func processScanData(room: CapturedRoom) async {
        guard let showroomCode = appState.showroomConfig?.showroomCode else {
            print("No showroom code available")
            let measurements = extractMeasurements(from: room, floorPlanUrl: nil, usdzUrl: nil, glbUrl: nil)
            await MainActor.run {
                isProcessing = false
            }
            appState.setMeasurementData(measurements)
            return
        }

        // Generate floor plan image
        await MainActor.run {
            processingStatus = "Generating floor plan..."
        }
        print("Generating floor plan image...")
        var floorPlanUrl: String? = nil
        if let floorPlanImage = FloorPlanRenderer.renderFloorPlan(from: room, size: CGSize(width: 1200, height: 1200)) {
            floorPlanUrl = await uploadFloorPlanImage(floorPlanImage, showroomCode: showroomCode)
        }

        // Export and upload USDZ
        await MainActor.run {
            processingStatus = "Creating 3D model..."
        }
        print("Exporting USDZ model...")
        let (usdzUrl, localUsdzUrl) = await exportAndUploadUSDZ(room, showroomCode: showroomCode)

        // Convert USDZ to GLB and upload
        var glbUrl: String? = nil
        if let localUsdzUrl = localUsdzUrl {
            await MainActor.run {
                processingStatus = "Optimizing for web viewing..."
            }
            print("Converting to GLB for web viewing...")
            glbUrl = await convertAndUploadGLB(usdzUrl: localUsdzUrl, showroomCode: showroomCode)
        }

        // Extract measurements with URLs
        await MainActor.run {
            processingStatus = "Finalizing measurements..."
        }
        let measurements = extractMeasurements(from: room, floorPlanUrl: floorPlanUrl, usdzUrl: usdzUrl, glbUrl: glbUrl)

        await MainActor.run {
            isProcessing = false
        }
        appState.setMeasurementData(measurements)
    }

    // MARK: - Floor Plan Image Upload

    private func uploadFloorPlanImage(_ image: UIImage, showroomCode: String) async -> String? {
        guard let imageData = image.pngData() else {
            print("Failed to convert floor plan image to PNG data")
            return nil
        }

        let timestamp = Int(Date().timeIntervalSince1970)
        let randomId = UUID().uuidString.prefix(8)
        let filename = "floor_plan_\(timestamp)_\(randomId).png"
        let storagePath = "\(showroomCode.lowercased())/\(filename)"

        do {
            let uploadedUrl = try await APIService.shared.uploadFile(
                bucket: "scans",
                path: storagePath,
                data: imageData,
                contentType: "image/png"
            )
            print("Floor plan image uploaded: \(uploadedUrl)")
            return uploadedUrl
        } catch {
            print("Failed to upload floor plan image: \(error.localizedDescription)")
            return nil
        }
    }

    // MARK: - USDZ Export and Upload

    private func exportAndUploadUSDZ(_ room: CapturedRoom, showroomCode: String) async -> (uploadedUrl: String?, localUrl: URL?) {
        let tempDir = FileManager.default.temporaryDirectory
        let timestamp = Int(Date().timeIntervalSince1970)
        let randomId = UUID().uuidString.prefix(8)
        let usdzFilename = "scan_\(timestamp)_\(randomId).usdz"
        let tempFileURL = tempDir.appendingPathComponent(usdzFilename)

        do {
            try await room.export(to: tempFileURL)
            let fileData = try Data(contentsOf: tempFileURL)
            let fileSizeMB = Double(fileData.count) / (1024 * 1024)
            print("USDZ file exported: \(String(format: "%.2f", fileSizeMB)) MB")

            let storagePath = "\(showroomCode.lowercased())/\(usdzFilename)"
            let uploadedUrl = try await APIService.shared.uploadFile(
                bucket: "scans",
                path: storagePath,
                data: fileData,
                contentType: "model/vnd.usdz+zip"
            )

            print("USDZ uploaded: \(uploadedUrl)")
            // Return both the uploaded URL and local file URL (for GLB conversion)
            return (uploadedUrl, tempFileURL)
        } catch {
            print("Error exporting/uploading USDZ: \(error.localizedDescription)")
            try? FileManager.default.removeItem(at: tempFileURL)
            return (nil, nil)
        }
    }

    // MARK: - GLB Conversion and Upload

    private func convertAndUploadGLB(usdzUrl: URL, showroomCode: String) async -> String? {
        // Convert USDZ to GLB using GLBExporter
        guard let glbUrl = await GLBExporter.convertUSDZToGLB(usdzURL: usdzUrl) else {
            print("Failed to convert USDZ to GLB")
            // Clean up USDZ temp file
            try? FileManager.default.removeItem(at: usdzUrl)
            return nil
        }

        do {
            let fileData = try Data(contentsOf: glbUrl)
            let fileSizeMB = Double(fileData.count) / (1024 * 1024)
            print("GLB file created: \(String(format: "%.2f", fileSizeMB)) MB")

            let glbFilename = glbUrl.lastPathComponent
            let storagePath = "\(showroomCode.lowercased())/\(glbFilename)"
            let contentType = GLBExporter.contentType(for: glbUrl)

            let uploadedUrl = try await APIService.shared.uploadFile(
                bucket: "scans",
                path: storagePath,
                data: fileData,
                contentType: contentType
            )

            print("GLB uploaded: \(uploadedUrl)")

            // Clean up temp files
            try? FileManager.default.removeItem(at: glbUrl)
            try? FileManager.default.removeItem(at: usdzUrl)

            return uploadedUrl
        } catch {
            print("Error uploading GLB: \(error.localizedDescription)")
            // Clean up temp files
            try? FileManager.default.removeItem(at: glbUrl)
            try? FileManager.default.removeItem(at: usdzUrl)
            return nil
        }
    }

    private func extractMeasurements(from room: CapturedRoom, floorPlanUrl: String?, usdzUrl: String?, glbUrl: String?) -> MeasurementData {
        // Calculate total linear feet from walls
        var totalLinearFt: Double = 0
        var wallCount = 0

        for wall in room.walls {
            let width = wall.dimensions.x
            totalLinearFt += Double(width) * 3.28084 // meters to feet
            wallCount += 1
        }

        // Calculate approximate square footage
        var totalSqFt: Double = 0
        if let floor = room.floors.first {
            let area = floor.dimensions.x * floor.dimensions.z
            totalSqFt = Double(area) * 10.7639 // sq meters to sq feet
        }

        // Convert room data to JSON
        let roomplanData = encodeRoomToJSON(room)

        // Extract detailed measurements
        let detailedMeasurements = extractDetailedMeasurements(from: room)

        return MeasurementData(
            roomName: "Main Room",
            roomType: "kitchen",
            roomplanData: roomplanData,
            totalLinearFt: totalLinearFt,
            totalSqFt: totalSqFt,
            wallCount: wallCount,
            windowCount: room.windows.count,
            doorCount: room.doors.count,
            measurements: detailedMeasurements,
            usdzFileUrl: usdzUrl,
            glbFileUrl: glbUrl,
            previewImageUrl: floorPlanUrl
        )
    }

    private func encodeRoomToJSON(_ room: CapturedRoom) -> [String: AnyCodable] {
        // Simplified encoding - in production, this would be more comprehensive
        return [
            "walls": AnyCodable(room.walls.count),
            "doors": AnyCodable(room.doors.count),
            "windows": AnyCodable(room.windows.count),
            "floors": AnyCodable(room.floors.count),
            "openings": AnyCodable(room.openings.count)
        ]
    }

    // MARK: - Detailed Measurements Extraction

    private func extractDetailedMeasurements(from room: CapturedRoom) -> [String: AnyCodable] {
        var measurements: [String: Any] = [:]

        // Room bounds and ceiling height
        var minX: Float = .infinity, maxX: Float = -.infinity
        var minZ: Float = .infinity, maxZ: Float = -.infinity
        var ceilingHeight: Float = 0

        // Extract ceiling height from wall height (walls go from floor to ceiling)
        if let firstWall = room.walls.first {
            ceilingHeight = firstWall.dimensions.y
        }

        // WALLS - Extract detailed wall data with proper rotation
        var wallsData: [[String: Any]] = []
        for (index, wall) in room.walls.enumerated() {
            let transform = wall.transform
            let dimensions = wall.dimensions

            // Convert meters to feet
            let widthFt = Double(dimensions.x) * 3.28084
            let heightFt = Double(dimensions.y) * 3.28084
            let thicknessFt = Double(dimensions.z) * 3.28084

            // Calculate wall endpoints using the full transform matrix
            // Wall extends along local X axis, so endpoints are at +/- width/2 in local coords
            let halfWidth = dimensions.x / 2.0

            // Local start point (-halfWidth, 0, 0) transformed to world coords
            let startLocal = SIMD4<Float>(-halfWidth, 0, 0, 1)
            let startWorld = simd_mul(transform, startLocal)

            // Local end point (+halfWidth, 0, 0) transformed to world coords
            let endLocal = SIMD4<Float>(halfWidth, 0, 0, 1)
            let endWorld = simd_mul(transform, endLocal)

            // Center position
            let centerX = Double(transform.columns.3.x)
            let centerZ = Double(transform.columns.3.z)

            // Update room bounds using actual wall endpoints
            minX = min(minX, min(startWorld.x, endWorld.x))
            maxX = max(maxX, max(startWorld.x, endWorld.x))
            minZ = min(minZ, min(startWorld.z, endWorld.z))
            maxZ = max(maxZ, max(startWorld.z, endWorld.z))

            let wallData: [String: Any] = [
                "id": "wall_\(index + 1)",
                "position": [
                    "x": centerX * 3.28084,
                    "z": centerZ * 3.28084
                ],
                "start": [
                    "x": Double(startWorld.x) * 3.28084,
                    "z": Double(startWorld.z) * 3.28084
                ],
                "end": [
                    "x": Double(endWorld.x) * 3.28084,
                    "z": Double(endWorld.z) * 3.28084
                ],
                "width_ft": widthFt,
                "height_ft": heightFt,
                "thickness_ft": thicknessFt,
                "linear_ft": widthFt
            ]
            wallsData.append(wallData)
        }

        // DOORS - Extract door data
        var doorsData: [[String: Any]] = []
        for (index, door) in room.doors.enumerated() {
            let position = door.transform.columns.3
            let dimensions = door.dimensions

            let widthFt = Double(dimensions.x) * 3.28084
            let heightFt = Double(dimensions.y) * 3.28084

            let doorData: [String: Any] = [
                "id": "door_\(index + 1)",
                "position": [
                    "x": Double(position.x) * 3.28084,
                    "z": Double(position.z) * 3.28084
                ],
                "width_ft": widthFt,
                "height_ft": heightFt,
                "width_inches": formatFeetInches(widthFt),
                "height_inches": formatFeetInches(heightFt)
            ]
            doorsData.append(doorData)
        }

        // WINDOWS - Extract window data
        var windowsData: [[String: Any]] = []
        for (index, window) in room.windows.enumerated() {
            let position = window.transform.columns.3
            let dimensions = window.dimensions

            let widthFt = Double(dimensions.x) * 3.28084
            let heightFt = Double(dimensions.y) * 3.28084
            let areaSqFt = widthFt * heightFt

            let windowData: [String: Any] = [
                "id": "window_\(index + 1)",
                "position": [
                    "x": Double(position.x) * 3.28084,
                    "z": Double(position.z) * 3.28084
                ],
                "width_ft": widthFt,
                "height_ft": heightFt,
                "width_inches": formatFeetInches(widthFt),
                "height_inches": formatFeetInches(heightFt),
                "area_sqft": areaSqFt
            ]
            windowsData.append(windowData)
        }

        // OBJECTS - Extract cabinet, appliance, and fixture data with rotation
        var upperCabinets: [[String: Any]] = []
        var lowerCabinets: [[String: Any]] = []
        var appliances: [[String: Any]] = []
        var sinks: [[String: Any]] = []

        var upperIndex = 1
        var lowerIndex = 1
        var applianceIndex = 1
        var sinkIndex = 1

        // DEBUG: Print ALL data from RoomPlan
        print("\n========== ROOMPLAN COMPLETE DEBUG ==========")
        print("Walls: \(room.walls.count)")
        print("Doors: \(room.doors.count)")
        print("Windows: \(room.windows.count)")
        print("Objects: \(room.objects.count)")
        print("Sections: \(room.sections.count)")

        // Print all sections
        print("\n--- SECTIONS ---")
        for (idx, section) in room.sections.enumerated() {
            print("Section[\(idx)]: \(section)")
        }

        // Print all objects with details
        print("\n--- ALL OBJECTS ---")
        var storageCount = 0
        var storageAbove09m = 0
        for (idx, obj) in room.objects.enumerated() {
            let pos = obj.transform.columns.3
            let dim = obj.dimensions
            print("Object[\(idx)]: category=\(obj.category)")
            print("  - Position: x=\(String(format: "%.2f", pos.x))m, y=\(String(format: "%.2f", pos.y))m, z=\(String(format: "%.2f", pos.z))m")
            print("  - Dimensions: w=\(String(format: "%.2f", dim.x))m, h=\(String(format: "%.2f", dim.y))m, d=\(String(format: "%.2f", dim.z))m")
            print("  - Y position (height): \(String(format: "%.2f", pos.y))m = \(String(format: "%.1f", pos.y * 3.28084))ft")

            if obj.category == .storage {
                storageCount += 1
                if pos.y >= 0.9 {
                    storageAbove09m += 1
                    print("  *** THIS SHOULD BE UPPER CABINET (y >= 0.9m) ***")
                }
            }
        }
        // Calculate floor level for summary
        let allStorageY = room.objects.filter { $0.category == .storage }.map { $0.transform.columns.3.y }
        let detectedFloorLevel = allStorageY.min() ?? 0
        let upperCabCount = allStorageY.filter { ($0 - detectedFloorLevel) > 1.0 }.count
        let lowerCabCount = allStorageY.filter { ($0 - detectedFloorLevel) <= 1.0 }.count

        print("\n--- STORAGE SUMMARY ---")
        print("Total storage objects: \(storageCount)")
        print("Detected floor level: \(String(format: "%.2f", detectedFloorLevel))m")
        print("Lower cabinets (height above floor <= 1.0m): \(lowerCabCount)")
        print("Upper cabinets (height above floor > 1.0m): \(upperCabCount)")
        print("=============================================\n")

        for object in room.objects {
            let transform = object.transform
            let position = transform.columns.3
            let dimensions = object.dimensions

            let widthFt = Double(dimensions.x) * 3.28084
            let heightFt = Double(dimensions.y) * 3.28084
            let depthFt = Double(dimensions.z) * 3.28084

            // Calculate corner points for accurate 2D rendering
            let halfWidth = dimensions.x / 2.0
            let halfDepth = dimensions.z / 2.0

            // Four corners in local space, transformed to world space
            let corners = [
                SIMD4<Float>(-halfWidth, 0, -halfDepth, 1),
                SIMD4<Float>(halfWidth, 0, -halfDepth, 1),
                SIMD4<Float>(halfWidth, 0, halfDepth, 1),
                SIMD4<Float>(-halfWidth, 0, halfDepth, 1)
            ].map { simd_mul(transform, $0) }

            let cornersData: [[String: Double]] = corners.map { corner in
                [
                    "x": Double(corner.x) * 3.28084,
                    "z": Double(corner.z) * 3.28084
                ]
            }

            let baseObjectData: [String: Any] = [
                "position": [
                    "x": Double(position.x) * 3.28084,
                    "z": Double(position.z) * 3.28084,
                    "y": Double(position.y) * 3.28084
                ],
                "width_ft": widthFt,
                "height_ft": heightFt,
                "depth_ft": depthFt,
                "corners": cornersData,
                "width_inches": formatFeetInches(widthFt),
                "height_inches": formatFeetInches(heightFt),
                "depth_inches": formatFeetInches(depthFt)
            ]

            // Categorize objects based on type and position
            switch object.category {
            case .storage:
                // Determine if upper or lower cabinet based on RELATIVE height
                // RoomPlan Y coordinates are relative to scan origin, NOT floor level
                // We need to find floor level first, then compare

                // Find floor level from all storage objects (minimum Y is floor level)
                let allStorageYPositions = room.objects
                    .filter { $0.category == .storage }
                    .map { $0.transform.columns.3.y }
                let floorLevel = allStorageYPositions.min() ?? -1.0

                // Upper cabinet if its center is more than 1.0m above floor level
                // (Lower cabinet centers are ~0.45m above floor, upper cabinet centers are ~1.5m+ above floor)
                let heightAboveFloor = position.y - floorLevel
                let isUpperCabinet = heightAboveFloor > 1.0

                print("Storage object: y=\(position.y), floorLevel=\(floorLevel), heightAboveFloor=\(heightAboveFloor), isUpper=\(isUpperCabinet)")

                if isUpperCabinet {
                    var cabinetData = baseObjectData
                    cabinetData["id"] = "upper_\(upperIndex)"
                    cabinetData["type"] = "upper_cabinet"
                    upperCabinets.append(cabinetData)
                    upperIndex += 1
                } else {
                    var cabinetData = baseObjectData
                    cabinetData["id"] = "lower_\(lowerIndex)"
                    cabinetData["type"] = "lower_cabinet"
                    lowerCabinets.append(cabinetData)
                    lowerIndex += 1
                }
            case .sink:
                var sinkData = baseObjectData
                sinkData["id"] = "sink_\(sinkIndex)"
                sinkData["type"] = "sink"
                sinks.append(sinkData)
                sinkIndex += 1
            case .refrigerator, .stove, .oven, .washerDryer, .dishwasher:
                var applianceData = baseObjectData
                applianceData["id"] = "appliance_\(applianceIndex)"
                applianceData["type"] = "\(object.category)"
                appliances.append(applianceData)
                applianceIndex += 1
            default:
                break
            }
        }

        // Room dimensions
        let roomBounds: [String: Any] = [
            "min_x": Double(minX) * 3.28084,
            "max_x": Double(maxX) * 3.28084,
            "min_z": Double(minZ) * 3.28084,
            "max_z": Double(maxZ) * 3.28084,
            "ceiling_height_ft": Double(ceilingHeight) * 3.28084
        ]

        // COUNTERTOPS - Calculate based on lower cabinets and objects
        var countertopsData: [[String: Any]] = []
        var totalCountertopArea: Double = 0

        // Method 1: Look for table-like objects at countertop height (2.5-3 feet)
        for object in room.objects {
            let heightFromFloor = Double(object.transform.columns.3.y) * 3.28084 // Convert to feet

            // Countertop height range: 2.5-3 feet (30-36 inches)
            // Check for table category or flat surfaces at appropriate height
            if heightFromFloor > 2.5 && heightFromFloor < 3.5 && object.category == .table {
                let position = object.transform.columns.3
                let dimensions = object.dimensions

                let widthFt = Double(dimensions.x) * 3.28084
                let depthFt = Double(dimensions.z) * 3.28084
                let areaSqFt = widthFt * depthFt

                let countertopData: [String: Any] = [
                    "id": "countertop_\(countertopsData.count + 1)",
                    "position": [
                        "x": Double(position.x) * 3.28084,
                        "z": Double(position.z) * 3.28084,
                        "y": heightFromFloor
                    ],
                    "width_ft": widthFt,
                    "depth_ft": depthFt,
                    "area_sqft": areaSqFt,
                    "linear_ft": widthFt
                ]

                countertopsData.append(countertopData)
                totalCountertopArea += areaSqFt
            }
        }

        // Method 2: If no table objects detected at countertop height, infer from lower cabinets
        if countertopsData.isEmpty && !lowerCabinets.isEmpty {
            // Group adjacent lower cabinets to form countertop runs
            var processedCabinets = Set<Int>()

            for (index, cabinet) in lowerCabinets.enumerated() {
                guard !processedCabinets.contains(index) else { continue }

                // Find all cabinets in the same run (same Z position, adjacent X positions)
                _ = [cabinet]
                processedCabinets.insert(index)

                // Simple approach: assume each lower cabinet has a countertop
                if let position = cabinet["position"] as? [String: Any],
                   let posX = position["x"] as? Double,
                   let posZ = position["z"] as? Double,
                   let widthFt = cabinet["width_ft"] as? Double,
                   let depthFt = cabinet["depth_ft"] as? Double {

                    let areaSqFt = widthFt * depthFt

                    let countertopData: [String: Any] = [
                        "id": "countertop_\(countertopsData.count + 1)",
                        "position": [
                            "x": posX,
                            "z": posZ - depthFt / 2, // Align to front of cabinet
                            "y": 3.0 // Standard 36" height
                        ],
                        "width_ft": widthFt,
                        "depth_ft": depthFt,
                        "area_sqft": areaSqFt,
                        "linear_ft": widthFt,
                        "inferred_from_cabinet": true
                    ]

                    countertopsData.append(countertopData)
                    totalCountertopArea += areaSqFt
                }
            }
        }

        // Assemble complete measurements
        measurements["room"] = roomBounds
        measurements["walls"] = wallsData
        measurements["doors"] = doorsData
        measurements["windows"] = windowsData
        measurements["cabinets"] = [
            "upper": upperCabinets,
            "lower": lowerCabinets
        ]
        measurements["appliances"] = appliances
        measurements["sinks"] = sinks
        measurements["countertops"] = countertopsData
        measurements["countertop_summary"] = [
            "total_area_sqft": totalCountertopArea,
            "total_linear_ft": countertopsData.reduce(0.0) { sum, ct in
                sum + ((ct["linear_ft"] as? Double) ?? 0)
            },
            "count": countertopsData.count
        ]
        measurements["summary"] = [
            "upper_cabinet_count": upperCabinets.count,
            "lower_cabinet_count": lowerCabinets.count,
            "appliance_count": appliances.count,
            "sink_count": sinks.count,
            "door_count": doorsData.count,
            "window_count": windowsData.count,
            "wall_count": wallsData.count
        ]

        // Convert to AnyCodable
        return measurements.mapValues { AnyCodable($0) }
    }

    // Helper function to format feet to feet + inches
    private func formatFeetInches(_ feet: Double) -> String {
        let wholeFeet = Int(feet)
        let inches = Int((feet - Double(wholeFeet)) * 12)
        return "\(wholeFeet)' \(inches)\""
    }
}

// MARK: - Instruction Row
struct InstructionRow: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(.blue)
                .frame(width: 24)
            Text(text)
                .font(.subheadline)
        }
    }
}

// MARK: - RoomPlan View Representable
struct RoomCaptureViewRepresentable: UIViewRepresentable {
    @Binding var isScanning: Bool
    @Binding var capturedRoom: CapturedRoom?
    let onComplete: (CapturedRoom) -> Void

    func makeUIView(context: Context) -> RoomCaptureView {
        let view = RoomCaptureView(frame: .zero)
        view.captureSession.delegate = context.coordinator
        return view
    }

    func updateUIView(_ uiView: RoomCaptureView, context: Context) {
        if isScanning && !context.coordinator.isSessionRunning {
            let config = RoomCaptureSession.Configuration()
            uiView.captureSession.run(configuration: config)
            context.coordinator.isSessionRunning = true
        } else if !isScanning && context.coordinator.isSessionRunning {
            uiView.captureSession.stop()
            context.coordinator.isSessionRunning = false
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    class Coordinator: NSObject, RoomCaptureSessionDelegate {
        let parent: RoomCaptureViewRepresentable
        var isSessionRunning = false

        init(parent: RoomCaptureViewRepresentable) {
            self.parent = parent
        }

        func captureSession(_ session: RoomCaptureSession, didEndWith data: CapturedRoomData, error: Error?) {
            guard error == nil else {
                print("Room capture error: \(error!.localizedDescription)")
                return
            }

            Task { @MainActor in
                let roomBuilder = RoomBuilder(options: [.beautifyObjects])
                if let room = try? await roomBuilder.capturedRoom(from: data) {
                    parent.capturedRoom = room
                    parent.onComplete(room)
                }
            }
        }
    }
}

#Preview {
    ScanningView()
        .environmentObject(AppState.shared)
}
