import SwiftUI
import RoomPlan

struct ScanningView: View {
    @EnvironmentObject var appState: AppState
    @State private var isScanning = false
    @State private var scanComplete = false
    @State private var capturedRoom: CapturedRoom?

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
            .navigationTitle(isScanning ? "Scanning" : "Room Scan")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    if !isScanning {
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

        // Extract measurements from RoomPlan data
        let measurements = extractMeasurements(from: room)

        appState.setMeasurementData(measurements)
    }

    private func extractMeasurements(from room: CapturedRoom) -> MeasurementData {
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
            usdzFileUrl: nil,
            previewImageUrl: nil
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

        // Extract ceiling height
        if let ceiling = room.surfaces.first(where: { $0.category == .ceiling }) {
            ceilingHeight = ceiling.transform.columns.3.y
        }

        // WALLS - Extract detailed wall data
        var wallsData: [[String: Any]] = []
        for (index, wall) in room.walls.enumerated() {
            let position = wall.transform.columns.3
            let dimensions = wall.dimensions

            // Convert meters to feet
            let widthFt = Double(dimensions.x) * 3.28084
            let heightFt = Double(dimensions.y) * 3.28084
            let thicknessFt = Double(dimensions.z) * 3.28084

            // Calculate wall endpoints for 2D view
            let centerX = Double(position.x)
            let centerZ = Double(position.z)
            let halfWidth = Double(dimensions.x) / 2.0

            // Update room bounds
            minX = min(minX, position.x - dimensions.x / 2)
            maxX = max(maxX, position.x + dimensions.x / 2)
            minZ = min(minZ, position.z - dimensions.z / 2)
            maxZ = max(maxZ, position.z + dimensions.z / 2)

            let wallData: [String: Any] = [
                "id": "wall_\(index + 1)",
                "position": [
                    "x": centerX * 3.28084,
                    "z": centerZ * 3.28084
                ],
                "start": [
                    "x": (centerX - halfWidth) * 3.28084,
                    "z": centerZ * 3.28084
                ],
                "end": [
                    "x": (centerX + halfWidth) * 3.28084,
                    "z": centerZ * 3.28084
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

        // OBJECTS - Extract cabinet and appliance data
        var upperCabinets: [[String: Any]] = []
        var lowerCabinets: [[String: Any]] = []
        var appliances: [[String: Any]] = []

        var upperIndex = 1
        var lowerIndex = 1
        var applianceIndex = 1

        for object in room.objects {
            let position = object.transform.columns.3
            let dimensions = object.dimensions

            let widthFt = Double(dimensions.x) * 3.28084
            let heightFt = Double(dimensions.y) * 3.28084
            let depthFt = Double(dimensions.z) * 3.28084

            let baseObjectData: [String: Any] = [
                "position": [
                    "x": Double(position.x) * 3.28084,
                    "z": Double(position.z) * 3.28084,
                    "y": Double(position.y) * 3.28084
                ],
                "width_ft": widthFt,
                "height_ft": heightFt,
                "depth_ft": depthFt,
                "width_inches": formatFeetInches(widthFt),
                "height_inches": formatFeetInches(heightFt),
                "depth_inches": formatFeetInches(depthFt)
            ]

            // Categorize objects based on type and position
            switch object.category {
            case .storage:
                // Determine if upper or lower cabinet based on height from floor
                if position.y > 1.2 { // Upper cabinets typically > 4 feet from floor
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

        // COUNTERTOPS - Calculate based on lower cabinets and surfaces
        var countertopsData: [[String: Any]] = []
        var totalCountertopArea: Double = 0

        // Method 1: Use detected surfaces at countertop height (2.5-3 feet)
        for surface in room.surfaces {
            let heightFromFloor = Double(surface.transform.columns.3.y) * 3.28084 // Convert to feet

            // Countertop height range: 2.5-3 feet (30-36 inches)
            if heightFromFloor > 2.5 && heightFromFloor < 3.5 && surface.category == .table {
                let position = surface.transform.columns.3
                let dimensions = surface.dimensions

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

        // Method 2: If no surfaces detected, infer from lower cabinets
        if countertopsData.isEmpty && !lowerCabinets.isEmpty {
            // Group adjacent lower cabinets to form countertop runs
            var processedCabinets = Set<Int>()

            for (index, cabinet) in lowerCabinets.enumerated() {
                guard !processedCabinets.contains(index) else { continue }

                // Find all cabinets in the same run (same Z position, adjacent X positions)
                var cabinetRun = [cabinet]
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
        measurements["countertops"] = countertopsData
        measurements["countertop_summary"] = [
            "total_area_sqft": totalCountertopArea,
            "total_linear_ft": countertopsData.reduce(0.0) { sum, ct in
                sum + ((ct["linear_ft"] as? Double) ?? 0)
            },
            "count": countertopsData.count
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
