import SwiftUI
import RoomPlan
import simd
import ARKit

struct ScanningView: View {
    @EnvironmentObject var appState: AppState
    @State private var isScanning = false
    @State private var isProcessing = false
    @State private var processingStatus = "Processing scan..."
    @State private var capturedRoom: CapturedRoom?
    @State private var rotationAngle: Double = 0
    @State private var videoRecorder: VideoRecorder?
    @State private var recordedVideoURL: URL?
    @State private var recordingDuration: TimeInterval = 0
    @State private var videoRecorderDelegate: VideoRecorderDelegateHandler?
    // Visualization photo state
    @State private var showVisualizationPhoto = false
    @State private var showPhotoIntro = false // Show intro before camera (during 5s wait)
    @State private var pendingMeasurements: MeasurementData?
    @State private var manuallyStopped = false // Track if user clicked Done button
    @State private var scanSessionId = UUID() // Unique ID to force view recreation

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                if showVisualizationPhoto {
                    VisualizationPhotoView(
                        onPhotosCompleted: { images in
                            handleVisualizationPhotos(images)
                        },
                        onSkip: {
                            handleVisualizationPhotoSkipped()
                        }
                    )
                } else if showPhotoIntro {
                    // Photo intro screen (shown during 5s camera release wait)
                    // CRITICAL: RoomCaptureView is NOT rendered at all - completely removed from hierarchy
                    PhotoIntroView(onContinue: {
                        // This won't be called - intro auto-transitions after 5s
                    })
                } else if isScanning && !showVisualizationPhoto && !showPhotoIntro {
                    // CRITICAL: Only show if NOT transitioning to photo views
                    // This ensures complete removal from hierarchy
                    RoomCaptureViewRepresentable(
                        isScanning: $isScanning,
                        capturedRoom: $capturedRoom,
                        videoRecorder: videoRecorder,
                        onComplete: handleScanComplete
                    )
                    .ignoresSafeArea()
                    .id("roomcapture_\(scanSessionId)") // Force complete destruction when ID changes
                    .overlay(alignment: .top) {
                        // Video recording indicator at top
                        if videoRecorder != nil {
                            HStack(spacing: 8) {
                                Circle()
                                    .fill(Color.red)
                                    .frame(width: 12, height: 12)
                                Text(formatDuration(recordingDuration))
                                    .font(.system(.caption, design: .monospaced))
                                    .foregroundColor(.white)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color.black.opacity(0.6))
                            .clipShape(Capsule())
                            .padding(.top, 60)
                        }
                    }
                    .overlay(alignment: .bottomTrailing) {
                        // Done button at bottom right
                        Button {
                            stopScanning()
                        } label: {
                            Text("Done")
                                .font(.headline)
                                .foregroundColor(.white)
                                .padding(.horizontal, 20)
                                .padding(.vertical, 10)
                                .background(Color.black.opacity(0.5))
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                        }
                        .padding(.trailing, 20)
                        .padding(.bottom, 40)
                    }
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
                            startScanning()
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
            .navigationTitle(showVisualizationPhoto ? "Photos" : (isScanning ? "Scanning" : (isProcessing ? "Processing" : "Room Scan")))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    if !isScanning && !isProcessing {
                        Button("Back") {
                            appState.currentScreen = .customerInfo
                        }
                    }
                }
            }
        }
    }

    // MARK: - Video Capture Helpers

    private var isVideoCaptureEnabled: Bool {
        appState.showroomConfig?.subscription?.videoCapture?.enabled ?? false
    }

    private func stopScanning() {
        manuallyStopped = true

        // CRITICAL: Stop video recorder FIRST to prevent race condition
        if let recorder = videoRecorder {
            recorder.stopRecording()
        }

        // CRITICAL: Wait for video to fully release camera before stopping RoomPlan
        // This prevents camera conflicts and ensures clean shutdown
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {

            // Set processing state BEFORE setting isScanning to false
            // This prevents the view from showing "Start Scanning" screen while waiting for delegate callback
            self.isProcessing = true
            self.processingStatus = "Finalizing scan..."

            self.isScanning = false

            // Safety timeout: If delegate doesn't call within 10 seconds, handle it manually
            DispatchQueue.main.asyncAfter(deadline: .now() + 10.0) {
                if self.isProcessing && self.capturedRoom == nil {
                    print("[ScanningView] ⚠️ Timeout waiting for RoomPlan delegate - handling manually")
                    // The delegate never called back, but we need to continue
                    // Check if we have a valid capturedRoom from the delegate
                    if let room = self.capturedRoom {
                        self.handleScanComplete(room: room)
                    } else {
                        // No room data - skip to photo capture anyway
                        print("[ScanningView] ⚠️ No room data available - this might be a very short scan")
                        // Create empty measurements and continue
                        Task { @MainActor in
                            self.isProcessing = false
                            self.showPhotoIntro = true

                            try? await Task.sleep(nanoseconds: 2_000_000_000)

                            self.showPhotoIntro = false
                            self.showVisualizationPhoto = true
                        }
                    }
                }
            }
        }
    }

    private func startScanning() {
        // Reset state for new scan
        manuallyStopped = false
        scanSessionId = UUID() // Generate new session ID for clean state

        // Initialize video recorder if enabled
        print("[ScanningView] isVideoCaptureEnabled: \(isVideoCaptureEnabled)")
        print("[ScanningView] subscription: \(String(describing: appState.showroomConfig?.subscription))")
        print("[ScanningView] videoCapture: \(String(describing: appState.showroomConfig?.subscription?.videoCapture))")

        if isVideoCaptureEnabled {
            // Convert ShowroomVideoCaptureSettings to VideoCaptureSettings
            var captureSettings: VideoCaptureSettings? = nil
            if let showroomSettings = appState.showroomConfig?.subscription?.videoCapture {
                captureSettings = VideoCaptureSettings(
                    maxDurationSeconds: TimeInterval(showroomSettings.maxDurationSeconds),
                    maxSizeMB: Double(showroomSettings.maxSizeMb)
                )
                print("[ScanningView] Created captureSettings: maxDuration=\(showroomSettings.maxDurationSeconds)s, maxSize=\(showroomSettings.maxSizeMb)MB")
            }
            let recorder = VideoRecorder(captureSettings: captureSettings)

            // Create and store delegate to prevent deallocation
            let delegateHandler = VideoRecorderDelegateHandler(
                onDurationUpdate: { duration in
                    DispatchQueue.main.async {
                        self.recordingDuration = duration
                    }
                },
                onRecordingComplete: { url in
                    DispatchQueue.main.async {
                        print("[ScanningView] Recording complete, URL: \(String(describing: url))")
                        self.recordedVideoURL = url
                    }
                }
            )
            recorder.delegate = delegateHandler
            videoRecorderDelegate = delegateHandler

            do {
                try recorder.prepare()
                videoRecorder = recorder
                print("[ScanningView] Video recorder prepared successfully")
            } catch {
                print("[ScanningView] Failed to prepare video recorder: \(error)")
                videoRecorder = nil
                videoRecorderDelegate = nil
            }
        } else {
            print("[ScanningView] Video capture is NOT enabled")
        }

        isScanning = true
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }

    private func handleScanComplete(room: CapturedRoom) {
        capturedRoom = room
        isProcessing = true
        processingStatus = "Analyzing room data..."

        // Check if scan was manually stopped (Done button) - video already stopped
        if manuallyStopped {
            print("[ScanningView] Scan was manually stopped, video already stopped")
            Task {
                // Wait for video file to finish writing
                var waitTime = 0.0
                while recordedVideoURL == nil && waitTime < 5.0 {
                    try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 second
                    waitTime += 0.1
                }
                if recordedVideoURL != nil {
                    print("[ScanningView] Video recording finished, URL: \(recordedVideoURL!)")
                }
                await processScanData(room: room)
            }
            return
        }

        // Scan completed naturally (not via Done button) - need to stop video
        if let recorder = videoRecorder {
            print("[ScanningView] Scan complete naturally - stopping video recording...")
            processingStatus = "Finalizing video..."

            // CRITICAL: Stop recording first
            recorder.stopRecording()
            print("[ScanningView] Video recorder stopped")

            // CRITICAL: Wait for ARSession to stop delivering frames and video to finish writing
            // This prevents race condition between ARSession frame delivery and video recorder shutdown
            Task {
                // First wait 0.5s for ARSession to fully stop delivering frames
                try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 second
                print("[ScanningView] Waited for ARSession to stop frame delivery")

                // Then wait for up to 5 seconds for video file to finish writing
                var waitTime = 0.0
                while recordedVideoURL == nil && waitTime < 5.0 {
                    try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 second
                    waitTime += 0.1
                }

                if recordedVideoURL != nil {
                    print("[ScanningView] Video recording finished, URL: \(recordedVideoURL!)")
                } else {
                    print("[ScanningView] Video recording did not complete in time")
                }

                await processScanData(room: room)
            }
        } else {
            // No video recording, process immediately
            Task {
                await processScanData(room: room)
            }
        }
    }

    private func processScanData(room: CapturedRoom) async {
        guard let showroomCode = appState.showroomConfig?.showroomCode else {
            print("No showroom code available")
            let measurements = extractMeasurements(from: room, floorPlanUrl: nil, usdzUrl: nil, glbUrl: nil, videoData: nil)
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
        let usdzUrl = await exportAndUploadUSDZ(room, showroomCode: showroomCode)

        // Note: GLB conversion now happens server-side after project submission
        // This removes the dependency on iOS's limited Model I/O GLB export

        // Process and upload video if recorded
        var videoData: UploadedVideoData? = nil
        if let recorder = videoRecorder, let videoURL = recordedVideoURL {
            await MainActor.run {
                processingStatus = "Uploading video..."
            }
            print("Processing video capture...")
            videoData = await processAndUploadVideo(recorder: recorder, videoURL: videoURL, showroomCode: showroomCode)
        }

        // Extract measurements with URLs
        // Note: glbUrl is nil here - server converts USDZ to GLB after submission
        await MainActor.run {
            processingStatus = "Finalizing measurements..."
        }
        let measurements = extractMeasurements(from: room, floorPlanUrl: floorPlanUrl, usdzUrl: usdzUrl, glbUrl: nil, videoData: videoData)

        await MainActor.run {
            isProcessing = false
            // Clean up video recorder
            videoRecorder = nil
            videoRecorderDelegate = nil
            recordedVideoURL = nil
            recordingDuration = 0

            // Store measurements
            pendingMeasurements = measurements

            // Show intro screen immediately (hides "Processing" UI)
            showPhotoIntro = true
        }

        // Wait 2 seconds for initial camera release while showing intro
        try? await Task.sleep(nanoseconds: 2_000_000_000)

        await MainActor.run {
            // Change scanSessionId to force complete destruction of RoomCaptureView
            scanSessionId = UUID()
            showPhotoIntro = false
            showVisualizationPhoto = true
        }
    }

    // MARK: - Visualization Photo Handling

    private func handleVisualizationPhotos(_ images: [UIImage]) {
        showVisualizationPhoto = false
        showPhotoIntro = false
        isProcessing = true
        processingStatus = "Uploading photos..."

        Task {
            guard var measurements = pendingMeasurements,
                  let showroomCode = appState.showroomConfig?.showroomCode else {
                await MainActor.run {
                    // Keep processing UI visible until navigation happens
                    if let measurements = pendingMeasurements {
                        appState.setMeasurementData(measurements)
                    }
                }
                return
            }

            // Upload all visualization photos
            let photoUrls = await uploadVisualizationPhotos(images, showroomCode: showroomCode)
            print("📸 [ScanningView] Uploaded \(photoUrls.count) photos: \(photoUrls)")
            if !photoUrls.isEmpty {
                measurements.visualizationPhotoUrls = photoUrls
                print("✅ [ScanningView] Set visualizationPhotoUrls on measurements: \(photoUrls)")
            } else {
                print("⚠️ [ScanningView] No photos were uploaded!")
            }

            await MainActor.run {
                // Don't set isProcessing = false here - keep showing processing UI
                // until AppState navigates to next screen (product selection)
                // This prevents briefly showing "Scan Your Space" screen
                print("📤 [ScanningView] About to call setMeasurementData with \(measurements.visualizationPhotoUrls?.count ?? 0) photos")
                pendingMeasurements = nil
                appState.setMeasurementData(measurements)
            }
        }
    }

    private func handleVisualizationPhotoSkipped() {
        showVisualizationPhoto = false
        showPhotoIntro = false

        if let measurements = pendingMeasurements {
            pendingMeasurements = nil
            appState.setMeasurementData(measurements)
        }
    }

    private func uploadVisualizationPhotos(_ images: [UIImage], showroomCode: String) async -> [String] {
        var uploadedUrls: [String] = []

        for (index, image) in images.enumerated() {
            // Normalize image orientation before saving
            let normalizedImage = normalizeImageOrientation(image)

            // Compress image to reasonable size with high quality (0.85)
            guard let imageData = normalizedImage.jpegData(compressionQuality: 0.85) else {
                print("Failed to convert visualization photo \(index + 1) to JPEG")
                continue
            }

            let timestamp = Int(Date().timeIntervalSince1970)
            let randomId = UUID().uuidString.prefix(8)
            let filename = "visualization_\(timestamp)_\(randomId)_\(index + 1).jpg"
            let storagePath = "\(showroomCode.lowercased())/\(filename)"

            do {
                let uploadedUrl = try await APIService.shared.uploadFile(
                    bucket: "scans",
                    path: storagePath,
                    data: imageData,
                    contentType: "image/jpeg"
                )
                print("Visualization photo \(index + 1) uploaded: \(uploadedUrl)")
                uploadedUrls.append(uploadedUrl)
            } catch {
                print("Failed to upload visualization photo \(index + 1): \(error.localizedDescription)")
            }
        }

        return uploadedUrls
    }

    /// Normalize image orientation by redrawing with correct transform applied
    /// This ensures the image pixels match the visual orientation
    private func normalizeImageOrientation(_ image: UIImage) -> UIImage {
        // If already upright, no need to redraw
        guard image.imageOrientation != .up else {
            return image
        }

        guard let cgImage = image.cgImage else {
            return image
        }

        let width = cgImage.width
        let height = cgImage.height

        var transform = CGAffineTransform.identity
        var outputWidth = width
        var outputHeight = height

        // Determine the transform based on orientation
        switch image.imageOrientation {
        case .down, .downMirrored:
            transform = transform.translatedBy(x: CGFloat(width), y: CGFloat(height))
            transform = transform.rotated(by: .pi)
        case .left, .leftMirrored:
            outputWidth = height
            outputHeight = width
            transform = transform.translatedBy(x: CGFloat(height), y: 0)
            transform = transform.rotated(by: .pi / 2)
        case .right, .rightMirrored:
            outputWidth = height
            outputHeight = width
            transform = transform.translatedBy(x: 0, y: CGFloat(width))
            transform = transform.rotated(by: -.pi / 2)
        case .up, .upMirrored:
            break
        @unknown default:
            break
        }

        // Handle mirrored orientations
        switch image.imageOrientation {
        case .upMirrored, .downMirrored:
            transform = transform.translatedBy(x: CGFloat(width), y: 0)
            transform = transform.scaledBy(x: -1, y: 1)
        case .leftMirrored, .rightMirrored:
            transform = transform.translatedBy(x: CGFloat(height), y: 0)
            transform = transform.scaledBy(x: -1, y: 1)
        default:
            break
        }

        // Create a context with the correct output size
        guard let colorSpace = cgImage.colorSpace,
              let context = CGContext(
                  data: nil,
                  width: outputWidth,
                  height: outputHeight,
                  bitsPerComponent: cgImage.bitsPerComponent,
                  bytesPerRow: 0,
                  space: colorSpace,
                  bitmapInfo: cgImage.bitmapInfo.rawValue
              ) else {
            // Fallback: use UIGraphicsImageRenderer
            let outputSize = CGSize(width: outputWidth, height: outputHeight)
            let format = UIGraphicsImageRendererFormat()
            format.scale = 1.0
            let renderer = UIGraphicsImageRenderer(size: outputSize, format: format)
            return renderer.image { _ in
                image.draw(in: CGRect(origin: .zero, size: outputSize))
            }
        }

        context.concatenate(transform)
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        guard let normalizedCGImage = context.makeImage() else {
            return image
        }

        return UIImage(cgImage: normalizedCGImage, scale: image.scale, orientation: .up)
    }

    // MARK: - Video Processing and Upload

    private struct UploadedVideoData {
        let videoUrl: String
        let thumbnailUrl: String?
        let durationSeconds: Int
        let sizeBytes: Int64
        let resolution: String
    }

    private func processAndUploadVideo(recorder: VideoRecorder, videoURL: URL, showroomCode: String) async -> UploadedVideoData? {
        guard let metadata = recorder.getVideoMetadata() else {
            print("Failed to get video metadata")
            return nil
        }

        print("Video metadata: duration=\(metadata.durationSeconds)s, size=\(String(format: "%.2f", metadata.sizeMB))MB, resolution=\(metadata.resolution)")

        // Upload video file
        let timestamp = Int(Date().timeIntervalSince1970)
        let randomId = UUID().uuidString.prefix(8)
        let videoFilename = "video_\(timestamp)_\(randomId).mp4"
        let videoPath = "\(showroomCode.lowercased())/\(videoFilename)"

        var uploadedVideoUrl: String? = nil
        do {
            let videoData = try Data(contentsOf: videoURL)
            uploadedVideoUrl = try await APIService.shared.uploadFile(
                bucket: "scans",
                path: videoPath,
                data: videoData,
                contentType: "video/mp4"
            )
            print("Video uploaded: \(uploadedVideoUrl ?? "nil")")
        } catch {
            print("Failed to upload video: \(error)")
            return nil
        }

        // Extract and upload thumbnail
        var thumbnailUrl: String? = nil
        if let thumbnail = await recorder.extractThumbnail(at: 1.0) {
            if let thumbnailData = thumbnail.jpegData(compressionQuality: 0.8) {
                let thumbnailFilename = "video_thumb_\(timestamp)_\(randomId).jpg"
                let thumbnailPath = "\(showroomCode.lowercased())/\(thumbnailFilename)"
                do {
                    thumbnailUrl = try await APIService.shared.uploadFile(
                        bucket: "scans",
                        path: thumbnailPath,
                        data: thumbnailData,
                        contentType: "image/jpeg"
                    )
                    print("Video thumbnail uploaded: \(thumbnailUrl ?? "nil")")
                } catch {
                    print("Failed to upload thumbnail: \(error)")
                }
            }
        }

        // Clean up temp video file
        try? FileManager.default.removeItem(at: videoURL)

        guard let finalVideoUrl = uploadedVideoUrl else {
            return nil
        }

        return UploadedVideoData(
            videoUrl: finalVideoUrl,
            thumbnailUrl: thumbnailUrl,
            durationSeconds: metadata.durationSeconds,
            sizeBytes: metadata.sizeBytes,
            resolution: metadata.resolution
        )
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

    private func exportAndUploadUSDZ(_ room: CapturedRoom, showroomCode: String) async -> String? {
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

            // Clean up temp file
            try? FileManager.default.removeItem(at: tempFileURL)

            // Note: GLB conversion now happens server-side after project submission
            return uploadedUrl
        } catch {
            print("Error exporting/uploading USDZ: \(error.localizedDescription)")
            try? FileManager.default.removeItem(at: tempFileURL)
            return nil
        }
    }

    // Note: GLB conversion has been moved to server-side (Supabase Edge Function)
    // This enables reliable USDZ to GLB conversion using CloudConvert API

    private func extractMeasurements(from room: CapturedRoom, floorPlanUrl: String?, usdzUrl: String?, glbUrl: String?, videoData: UploadedVideoData?) -> MeasurementData {
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
            previewImageUrl: floorPlanUrl,
            videoUrl: videoData?.videoUrl,
            videoThumbnailUrl: videoData?.thumbnailUrl,
            videoDurationSeconds: videoData?.durationSeconds,
            videoSizeBytes: videoData?.sizeBytes,
            videoResolution: videoData?.resolution,
            videoFormat: videoData != nil ? "mp4" : nil
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
    var videoRecorder: VideoRecorder?
    let onComplete: (CapturedRoom) -> Void

    func makeUIView(context: Context) -> RoomCaptureView {
        let view = RoomCaptureView(frame: .zero)
        view.captureSession.delegate = context.coordinator

        // Set up ARSession delegate for video frame capture
        view.captureSession.arSession.delegate = context.coordinator

        return view
    }

    func updateUIView(_ uiView: RoomCaptureView, context: Context) {
        context.coordinator.videoRecorder = videoRecorder

        // Directly assign delegate without optional binding
        uiView.captureSession.arSession.delegate = context.coordinator

        if isScanning && !context.coordinator.isSessionRunning {
            let config = RoomCaptureSession.Configuration()
            uiView.captureSession.run(configuration: config)
            context.coordinator.isSessionRunning = true

            // CRITICAL: Delay video recording to let RoomPlan fully initialize ARSession first
            // Even though VideoRecorder uses ARSession frames (not camera), starting too early
            // interferes with RoomPlan's ARSession initialization causing 10s black screen
            if let recorder = videoRecorder {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    do {
                        try recorder.startRecording()
                        print("[RoomCaptureView] Video recording started (delayed 0.5s)")
                    } catch {
                        print("[RoomCaptureView] Failed to start video recording: \(error)")
                    }
                }
            }
        } else if !isScanning && context.coordinator.isSessionRunning {
            // CRITICAL: Stop session but KEEP delegates so RoomPlan can call completion callback
            print("[RoomCaptureView] Stopping RoomPlan - waiting for completion callback")

            // Clear video recorder to stop receiving frames
            context.coordinator.videoRecorder = nil

            // Pause ARSession to halt frame delivery
            uiView.captureSession.arSession.pause()

            // Stop the RoomPlan session - this triggers delegate callback
            uiView.captureSession.stop()

            context.coordinator.isSessionRunning = false
            print("[RoomCaptureView] RoomPlan session stopped - delegate will receive completion callback")

            // NOTE: We do NOT remove delegates here - they're needed for the completion callback
            // Delegates will be removed in dismantleUIView when the view is fully removed
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    // CRITICAL: Clean up when view is removed from hierarchy
    static func dismantleUIView(_ uiView: RoomCaptureView, coordinator: Coordinator) {
        // Remove all delegates
        uiView.captureSession.delegate = nil
        uiView.captureSession.arSession.delegate = nil
        coordinator.videoRecorder = nil

        // Force stop sessions
        uiView.captureSession.arSession.pause()
        uiView.captureSession.stop()
        coordinator.isSessionRunning = false
    }

    class Coordinator: NSObject, RoomCaptureSessionDelegate, ARSessionDelegate {
        let parent: RoomCaptureViewRepresentable
        var isSessionRunning = false
        var videoRecorder: VideoRecorder?
        private var sessionStartTime: TimeInterval?
        private var completionHandled = false // Prevent double-calling onComplete

        init(parent: RoomCaptureViewRepresentable) {
            self.parent = parent
        }

        // MARK: - RoomCaptureSessionDelegate

        func captureSession(_ session: RoomCaptureSession, didEndWith data: CapturedRoomData, error: Error?) {
            guard !completionHandled else {
                print("[RoomCaptureSession] Completion callback already handled, ignoring duplicate")
                return
            }

            if let error = error {
                print("[RoomCaptureSession] Room capture error: \(error.localizedDescription)")
                // Even with error, try to build room from partial data
            }

            print("[RoomCaptureSession] Delegate callback received - building room")
            completionHandled = true

            Task { @MainActor in
                let roomBuilder = RoomBuilder(options: [.beautifyObjects])
                do {
                    let room = try await roomBuilder.capturedRoom(from: data)
                    print("[RoomCaptureSession] Room built successfully")
                    parent.capturedRoom = room
                    parent.onComplete(room)
                } catch {
                    print("[RoomCaptureSession] Failed to build room: \(error.localizedDescription)")
                    // Still call onComplete with nil to unblock UI
                }
            }
        }

        // MARK: - ARSessionDelegate

        func session(_ session: ARSession, didUpdate frame: ARFrame) {
            guard let recorder = videoRecorder, recorder.isCurrentlyRecording else { return }

            // Initialize session start time on first frame
            if sessionStartTime == nil {
                sessionStartTime = frame.timestamp
            }

            // Calculate timestamp relative to session start
            let relativeTimestamp = frame.timestamp - (sessionStartTime ?? 0)

            // Append frame to video recorder
            recorder.appendPixelBuffer(frame.capturedImage, timestamp: relativeTimestamp)
        }
    }
}

// MARK: - Video Recorder Delegate Handler
class VideoRecorderDelegateHandler: VideoRecorderDelegate {
    private let onDurationUpdate: (TimeInterval) -> Void
    private let onRecordingComplete: (URL?) -> Void

    init(onDurationUpdate: @escaping (TimeInterval) -> Void, onRecordingComplete: @escaping (URL?) -> Void) {
        self.onDurationUpdate = onDurationUpdate
        self.onRecordingComplete = onRecordingComplete
    }

    func videoRecorderDidStartRecording(_ recorder: VideoRecorder) {
        print("[VideoRecorderDelegateHandler] Recording started")
    }

    func videoRecorderDidStopRecording(_ recorder: VideoRecorder, outputURL: URL?, error: Error?) {
        if let error = error {
            print("[VideoRecorderDelegateHandler] Recording failed: \(error)")
        }
        onRecordingComplete(outputURL)
    }

    func videoRecorderDidUpdateDuration(_ recorder: VideoRecorder, duration: TimeInterval) {
        onDurationUpdate(duration)
    }
}

// MARK: - Photo Intro View
struct PhotoIntroView: View {
    let onContinue: () -> Void

    var body: some View {
        VStack(spacing: 32) {
            Spacer()

            // Camera icon with animation
            ZStack {
                Circle()
                    .fill(Color.blue.opacity(0.1))
                    .frame(width: 120, height: 120)

                Image(systemName: "camera.fill")
                    .font(.system(size: 50))
                    .foregroundStyle(.blue)
            }

            VStack(spacing: 16) {
                Text("Time for Photos!")
                    .font(.title)
                    .fontWeight(.bold)

                Text("We'll take 5 photos from different angles to help visualize your space")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }

            VStack(alignment: .leading, spacing: 16) {
                InstructionRow(icon: "camera.viewfinder", text: "Capture from multiple angles")
                InstructionRow(icon: "hand.tap", text: "Tap to take each photo")
                InstructionRow(icon: "arrow.clockwise", text: "You can skip if needed")
            }
            .padding()
            .background(Color(.systemGray6))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .padding(.horizontal)

            HStack(spacing: 8) {
                ProgressView()
                    .tint(.blue)
                Text("Preparing camera...")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
    }
}

#Preview {
    ScanningView()
        .environmentObject(AppState.shared)
}
