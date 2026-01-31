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
    @State private var isRoomPlanReady = false // Track if RoomPlan camera is ready
    @State private var scanStartTime: Date?
    @State private var keepFullScreenOpen = false // Keep fullScreenCover open until room data received
    @State private var showScanError = false // Show error alert if scan fails
    @State private var scanErrorMessage = "" // Error message to display
    @State private var showPoorScanWarning = false // Show warning for poor quality scan
    @State private var poorScanMessage = "" // Warning message for poor scan
    @State private var pendingPoorScanMeasurements: MeasurementData? // Store measurements when showing poor scan warning

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                if showVisualizationPhoto {
                    VisualizationPhotoView(
                        onPhotosCompleted: { photoData in
                            handleVisualizationPhotos(photoData)
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

                            Image(systemName: processingStatus.contains("photo") ? "photo.fill" : "cube.transparent")
                                .font(.system(size: 40))
                                .foregroundStyle(.blue)
                        }
                        .onAppear {
                            startRotationAnimation()
                        }
                        .onChange(of: processingStatus) { _ in
                            startRotationAnimation()
                        }

                        VStack(spacing: 12) {
                            Text(processingStatus.contains("photo") ? "Uploading Photos" : "Processing Your Scan")
                                .font(.title2)
                                .fontWeight(.bold)

                            Text(processingStatus)
                                .font(.body)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 32)
                        }

                        Text("This may take a moment...")
                            .font(.caption)
                            .foregroundStyle(.tertiary)

                        Spacer()
                    }
                } else if pendingMeasurements != nil {
                    // CRITICAL: If we have pending measurements, show processing - never show start screen
                    // This prevents brief flash of start screen when transitioning from photos
                    VStack(spacing: 32) {
                        Spacer()

                        ProgressView()
                            .scaleEffect(1.5)

                        Text("Processing...")
                            .font(.headline)

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
                            Label("Begin", systemImage: "camera")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .padding(.horizontal)
                        .padding(.bottom, 32)
                    }
                }
            }
            .navigationTitle(showVisualizationPhoto ? "Photos" : (isProcessing ? "Processing" : "Room Scan"))
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
            // CRITICAL: Present RoomPlan as fullScreenCover to completely isolate it from navigation hierarchy
            // This prevents Metal texture conflicts caused by NavigationStack/toolbar
            // IMPORTANT: Keep cover open (keepFullScreenOpen) even after scanning stops to receive delegate callback
            .fullScreenCover(isPresented: .constant((isScanning || keepFullScreenOpen) && !showVisualizationPhoto && !showPhotoIntro && !isProcessing)) {
                FullScreenRoomCaptureView(
                    isScanning: $isScanning,
                    capturedRoom: $capturedRoom,
                    videoRecorder: videoRecorder,
                    isRoomPlanReady: $isRoomPlanReady,
                    recordingDuration: $recordingDuration,
                    onComplete: handleScanComplete,
                    onDone: stopScanning,
                    showProcessing: !isScanning && keepFullScreenOpen
                )
                .id("roomcapture_\(scanSessionId)")
            }
            .onAppear {
                // Reset state when view appears (e.g., starting a new project)
                isProcessing = false
                showVisualizationPhoto = false
                showPhotoIntro = false
                pendingMeasurements = nil
                manuallyStopped = false
                capturedRoom = nil
                recordedVideoURL = nil
                isRoomPlanReady = false
                showScanError = false
            }
        }
        .alert("Scan Failed", isPresented: $showScanError) {
            Button("Retry Scan") {
                // Reset and try again
                isProcessing = false
                capturedRoom = nil
                pendingMeasurements = nil
                keepFullScreenOpen = false
                scanErrorMessage = ""
            }
            Button("Go Back", role: .cancel) {
                appState.currentScreen = .customerInfo
            }
        } message: {
            Text(scanErrorMessage)
        }
        .alert("Poor Scan Quality", isPresented: $showPoorScanWarning) {
            Button("Rescan", role: .destructive) {
                // Reset and allow user to scan again
                isProcessing = false
                capturedRoom = nil
                pendingMeasurements = nil
                pendingPoorScanMeasurements = nil
                keepFullScreenOpen = false
                poorScanMessage = ""
            }
            Button("Continue Anyway", role: .cancel) {
                // User chooses to proceed despite warning
                if let measurements = pendingPoorScanMeasurements {
                    pendingPoorScanMeasurements = nil
                    poorScanMessage = ""
                    appState.setMeasurementData(measurements)
                }
            }
        } message: {
            Text(poorScanMessage)
        }
    }

    // MARK: - Animation Helpers

    private func startRotationAnimation() {
        // Reset rotation angle and start fresh animation
        rotationAngle = 0
        withAnimation(.linear(duration: 1).repeatForever(autoreverses: false)) {
            rotationAngle = 360
        }
    }

    // MARK: - Video Capture Helpers

    private var isVideoCaptureEnabled: Bool {
        appState.showroomConfig?.subscription?.videoCapture?.enabled ?? false
    }

    private func stopScanning() {
        manuallyStopped = true

        // Re-enable screen sleep
        UIApplication.shared.isIdleTimerDisabled = false

        // Check if scan is too short (less than 5 seconds)
        if let startTime = scanStartTime {
            let scanDuration = Date().timeIntervalSince(startTime)
            if scanDuration < 5 {
                print("⚠️ [ScanningView] Very short scan detected (\(Int(scanDuration))s) - room data may be incomplete")
            }
        }

        // CRITICAL: Stop video recorder FIRST to prevent race condition
        if let recorder = videoRecorder {
            recorder.stopRecording()
        }

        // CRITICAL: Keep fullscreen open to receive delegate callback
        // This prevents coordinator from being destroyed before RoomPlan calls back
        keepFullScreenOpen = true
        print("[ScanningView] Keeping fullscreen open to wait for RoomPlan delegate...")

        // CRITICAL: Wait for video to fully release camera before stopping RoomPlan
        // This prevents camera conflicts and ensures clean shutdown
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {

            // Set isScanning = false to stop the session, but keep fullscreen open
            self.isScanning = false
            print("[ScanningView] Stopped scanning, waiting for room data...")

            // Safety timeout: If delegate doesn't call within 15 seconds, show ERROR
            DispatchQueue.main.asyncAfter(deadline: .now() + 15.0) {
                if self.keepFullScreenOpen && self.capturedRoom == nil {
                    print("[ScanningView] ❌ TIMEOUT: RoomPlan failed to provide scan data")
                    // Close the fullscreen
                    self.keepFullScreenOpen = false
                    self.isProcessing = false
                    self.isScanning = false

                    // Show error to user - DO NOT continue without measurements
                    self.scanErrorMessage = """
                    The room scan failed to complete. This could be due to:

                    • Insufficient lighting
                    • Moving too quickly
                    • Device limitations

                    Please try scanning again. Make sure to:
                    • Move slowly and steadily
                    • Scan for at least 10-15 seconds
                    • Cover all walls and corners
                    """
                    self.showScanError = true
                    print("[ScanningView] ❌ Showing error to user - scan must be retried")
                }
            }
        }
    }

    private func startScanning() {
        // Reset state for new scan
        manuallyStopped = false
        isRoomPlanReady = false // Reset ready state
        scanSessionId = UUID() // Generate new session ID for clean state
        recordingDuration = 0 // Reset recording timer
        scanStartTime = Date() // Track scan start time
        keepFullScreenOpen = false // Reset fullscreen state

        // Prevent screen from sleeping during scan
        UIApplication.shared.isIdleTimerDisabled = true

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
        print("[ScanningView] ✅ Received room data from RoomPlan delegate!")
        capturedRoom = room

        // CRITICAL: Close fullscreen now that we have room data
        keepFullScreenOpen = false

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
        // Room data is REQUIRED - this should never be called without it

        guard let showroomCode = appState.showroomConfig?.showroomCode else {
            print("No showroom code available")
            let measurements = extractMeasurements(from: room, floorPlanUrl: nil, usdzUrl: nil, glbUrl: nil, videoData: nil)
            await MainActor.run {
                isProcessing = false
                validateAndProceedWithMeasurements(measurements)
            }
            return
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
        let measurements = extractMeasurements(from: room, floorPlanUrl: nil, usdzUrl: usdzUrl, glbUrl: nil, videoData: videoData)

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

        // CRITICAL: Wait EVEN LONGER for camera to fully release (10 seconds)
        // RoomPlan holds camera resources - must wait for complete cleanup
        // FigCapture errors persist with shorter waits
        print("[ScanningView] Waiting 10 seconds for camera release...")
        try? await Task.sleep(nanoseconds: 10_000_000_000)

        await MainActor.run {
            // Change scanSessionId to force complete destruction of RoomCaptureView
            scanSessionId = UUID()
            showPhotoIntro = false
            print("[ScanningView] Transitioning to photo capture view...")
            showVisualizationPhoto = true
        }
    }

    // MARK: - Visualization Photo Handling

    private func handleVisualizationPhotos(_ photoData: [CapturedPhotoData]) {
        print("📸 [handleVisualizationPhotos] Called with \(photoData.count) photos")
        print("📸 [handleVisualizationPhotos] Photo sizes: \(photoData.map { $0.rawData.count / 1024 })")

        // CRITICAL: Set all flags to prevent showing start screen during transition
        showVisualizationPhoto = false
        showPhotoIntro = false
        isProcessing = true
        processingStatus = "Uploading \(photoData.count) photo\(photoData.count == 1 ? "" : "s")..."

        Task {
            print("📸 [handleVisualizationPhotos] Starting Task...")
            guard var measurements = pendingMeasurements,
                  let showroomCode = appState.showroomConfig?.showroomCode else {
                print("❌ [handleVisualizationPhotos] Missing measurements or showroom code!")
                // Keep processing UI visible until navigation happens
                await MainActor.run {
                    isProcessing = true
                }

                // Give a small delay to ensure UI stays stable
                try? await Task.sleep(nanoseconds: 100_000_000) // 0.1s

                await MainActor.run {
                    if let measurements = pendingMeasurements {
                        pendingMeasurements = nil
                        validateAndProceedWithMeasurements(measurements)
                    }
                }
                return
            }

            // Upload all visualization photos using original camera data
            print("📸 [handleVisualizationPhotos] Calling uploadVisualizationPhotos...")
            let photoUrls = await uploadVisualizationPhotos(photoData, showroomCode: showroomCode)
            print("📸 [handleVisualizationPhotos] Upload complete! Uploaded \(photoUrls.count) photos")
            print("📸 [handleVisualizationPhotos] Photo URLs: \(photoUrls)")

            if !photoUrls.isEmpty {
                measurements.visualizationPhotoUrls = photoUrls
                print("✅ [handleVisualizationPhotos] Set visualizationPhotoUrls on measurements")
            } else {
                print("⚠️ [handleVisualizationPhotos] WARNING: No photos were uploaded!")
            }

            // CRITICAL: Keep isProcessing = true and pendingMeasurements intact
            // until navigation completes. This prevents "Scan Your Space" from appearing
            await MainActor.run {
                processingStatus = "Finalizing..."
                print("📤 [handleVisualizationPhotos] Finalizing with \(measurements.visualizationPhotoUrls?.count ?? 0) photos")
            }

            // Small delay before navigation to ensure UI stability
            try? await Task.sleep(nanoseconds: 100_000_000) // 0.1s

            print("📤 [handleVisualizationPhotos] About to validate and navigate...")
            await MainActor.run {
                pendingMeasurements = nil
                validateAndProceedWithMeasurements(measurements)
                print("✅ [handleVisualizationPhotos] Validation complete - navigation should happen now")
            }
        }
    }

    private func handleVisualizationPhotoSkipped() {
        showVisualizationPhoto = false
        showPhotoIntro = false
        isProcessing = true
        processingStatus = "Finalizing..."

        // Small delay to ensure smooth transition
        Task {
            try? await Task.sleep(nanoseconds: 100_000_000) // 0.1s
            await MainActor.run {
                if let measurements = pendingMeasurements {
                    pendingMeasurements = nil
                    validateAndProceedWithMeasurements(measurements)
                }
            }
        }
    }

    private func uploadVisualizationPhotos(_ photos: [CapturedPhotoData], showroomCode: String) async -> [String] {
        var uploadedUrls: [String] = []

        for (index, photo) in photos.enumerated() {
            // Update progress
            await MainActor.run {
                processingStatus = "Uploading photo \(index + 1) of \(photos.count)..."
            }

            // Use resized + compressed JPEG data (1920px max @ 0.5 quality)
            // Clear photos with small file sizes (~300-500KB each, down from 2MB)
            // Saves storage costs while maintaining visual quality
            let imageData = photo.rawData

            let timestamp = Int(Date().timeIntervalSince1970)
            let randomId = UUID().uuidString.prefix(8)
            let filename = "visualization_\(timestamp)_\(randomId)_\(index + 1).jpg"
            let storagePath = "\(showroomCode.lowercased())/\(filename)"

            do {
                print("📤 [Upload] Starting upload for photo \(index + 1)/\(photos.count) - size: \(imageData.count / 1024)KB")
                let uploadedUrl = try await APIService.shared.uploadFile(
                    bucket: "scans",
                    path: storagePath,
                    data: imageData,
                    contentType: "image/jpeg"
                )
                print("✅ [Upload] Photo \(index + 1) uploaded: \(uploadedUrl)")
                uploadedUrls.append(uploadedUrl)
            } catch {
                print("❌ [Upload] Failed to upload photo \(index + 1): \(error.localizedDescription)")
                print("❌ [Upload] Error details: \(error)")
                // Continue with other photos even if one fails
            }
        }

        print("📦 [Upload] Completed: \(uploadedUrls.count)/\(photos.count) photos uploaded successfully")
        return uploadedUrls
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

        // Compress video for faster upload and lower storage costs
        print("Compressing video for upload...")
        let videoToUpload: URL
        var compressedURL: URL? = nil

        if metadata.sizeMB > 20 {
            // Only compress if file is larger than 20MB
            if let compressed = await recorder.compressVideo() {
                compressedURL = compressed
                videoToUpload = compressed
            } else {
                print("Compression failed, using original video")
                videoToUpload = videoURL
            }
        } else {
            videoToUpload = videoURL
        }

        // Upload video file
        let timestamp = Int(Date().timeIntervalSince1970)
        let randomId = UUID().uuidString.prefix(8)
        let videoFilename = "video_\(timestamp)_\(randomId).mp4"
        let videoPath = "\(showroomCode.lowercased())/\(videoFilename)"

        var uploadedVideoUrl: String? = nil
        do {
            let videoData = try Data(contentsOf: videoToUpload)
            let finalSizeMB = Double(videoData.count) / (1024 * 1024)
            print("Uploading video: \(String(format: "%.2f", finalSizeMB))MB")

            uploadedVideoUrl = try await APIService.shared.uploadFile(
                bucket: "scans",
                path: videoPath,
                data: videoData,
                contentType: "video/mp4"
            )
            print("Video uploaded: \(uploadedVideoUrl ?? "nil")")
        } catch {
            print("Failed to upload video: \(error)")
            // Clean up compressed file if it exists
            if let compressed = compressedURL {
                try? FileManager.default.removeItem(at: compressed)
            }
            return nil
        }

        // Extract and upload thumbnail
        var thumbnailUrl: String? = nil
        if let thumbnail = await recorder.extractThumbnail(at: 1.0) {
            if let thumbnailData = thumbnail.jpegData(compressionQuality: 0.5) {
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

        guard let finalVideoUrl = uploadedVideoUrl else {
            // Clean up on failure
            try? FileManager.default.removeItem(at: videoURL)
            if let compressed = compressedURL {
                try? FileManager.default.removeItem(at: compressed)
            }
            return nil
        }

        // Get actual uploaded file size before cleanup
        let uploadedSizeBytes: Int64
        if let compressed = compressedURL,
           let attrs = try? FileManager.default.attributesOfItem(atPath: compressed.path),
           let size = attrs[.size] as? Int64 {
            uploadedSizeBytes = size
        } else {
            uploadedSizeBytes = metadata.sizeBytes
        }

        // Clean up temp video files
        try? FileManager.default.removeItem(at: videoURL)
        if let compressed = compressedURL {
            try? FileManager.default.removeItem(at: compressed)
        }

        return UploadedVideoData(
            videoUrl: finalVideoUrl,
            thumbnailUrl: thumbnailUrl,
            durationSeconds: metadata.durationSeconds,
            sizeBytes: uploadedSizeBytes,
            resolution: metadata.resolution
        )
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
            videoFormat: videoData != nil ? "mp4" : nil,
            visualizationPhotoUrls: nil,  // LiDAR flow doesn't use visualization photos
            scanMethod: nil,  // LiDAR flow: nil (Story 5.4)
            aiMetadata: nil   // LiDAR flow: nil (Story 5.4)
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
        // Cabinet types detected:
        // 1. Upper Cabinet - standard upper cabinets (30-42" / 0.76-1.07m height)
        // 2. Lower Cabinet - base cabinets
        // 3. Wall Oven Cabinet - tall cabinet with oven between upper and lower sections
        // 4. Pantry Cabinet - tall cabinet without oven (vertically aligned upper+lower)
        // 5. Upper Small Cabinet - shorter cabinets above appliances (fridge, stove, sink) - 12-18" / 0.3-0.46m height

        var upperCabinets: [[String: Any]] = []
        var lowerCabinets: [[String: Any]] = []
        var wallOvenCabinets: [[String: Any]] = []
        var pantryCabinets: [[String: Any]] = []
        var appliances: [[String: Any]] = []
        var sinks: [[String: Any]] = []

        var upperIndex = 1
        var lowerIndex = 1
        var wallOvenIndex = 1
        var pantryIndex = 1
        var applianceIndex = 1
        var sinkIndex = 1

        // First pass: Collect all storage objects and appliances for analysis
        struct StorageInfo {
            let object: CapturedRoom.Object
            let position: SIMD4<Float>
            let dimensions: SIMD3<Float>
            let heightAboveFloor: Float
        }

        // Find floor level from all storage objects (minimum Y is floor level)
        let allStorageYPositions = room.objects
            .filter { $0.category == .storage }
            .map { $0.transform.columns.3.y }
        let floorLevel = allStorageYPositions.min() ?? -1.0

        // Collect storage objects with height classification
        var upperStorageObjects: [StorageInfo] = []
        var lowerStorageObjects: [StorageInfo] = []

        for object in room.objects where object.category == .storage {
            let position = object.transform.columns.3
            let heightAboveFloor = position.y - floorLevel

            let info = StorageInfo(
                object: object,
                position: position,
                dimensions: object.dimensions,
                heightAboveFloor: heightAboveFloor
            )

            if heightAboveFloor > 1.0 {
                upperStorageObjects.append(info)
            } else {
                lowerStorageObjects.append(info)
            }
        }

        // Collect appliance positions and dimensions for cabinet type detection
        struct OvenInfo {
            let position: SIMD4<Float>
            let dimensions: SIMD3<Float>  // width, height, depth
        }
        var ovenInfos: [OvenInfo] = []
        var wallOvenInfos: [OvenInfo] = []  // Stoves/ovens at elevated positions (wall ovens)
        var appliancePositionsForSmallCabinets: [SIMD4<Float>] = []  // Fridge, stove positions
        var sinkPositions: [SIMD4<Float>] = []

        // Height threshold for wall oven detection - wall ovens are typically mounted 27-30" from floor
        let wallOvenMinHeight: Float = 0.6  // ~24 inches from floor level

        for object in room.objects {
            let pos = object.transform.columns.3
            let heightFromFloor = pos.y - floorLevel

            switch object.category {
            case .oven:
                let ovenInfo = OvenInfo(position: pos, dimensions: object.dimensions)
                ovenInfos.append(ovenInfo)
                // Wall ovens are mounted higher than floor level
                if heightFromFloor > wallOvenMinHeight {
                    wallOvenInfos.append(ovenInfo)
                    print("[ScanAnalysis] Wall oven detected at height \(String(format: "%.2f", heightFromFloor))m, dimensions: \(String(format: "%.2f", object.dimensions.x))x\(String(format: "%.2f", object.dimensions.y))x\(String(format: "%.2f", object.dimensions.z))m")
                }
            case .stove:
                // Stoves at elevated positions might be wall ovens (RoomPlan sometimes misclassifies)
                if heightFromFloor > wallOvenMinHeight {
                    let ovenInfo = OvenInfo(position: pos, dimensions: object.dimensions)
                    wallOvenInfos.append(ovenInfo)
                    print("[ScanAnalysis] Elevated stove (possible wall oven) at height \(String(format: "%.2f", heightFromFloor))m, dimensions: \(String(format: "%.2f", object.dimensions.x))x\(String(format: "%.2f", object.dimensions.y))x\(String(format: "%.2f", object.dimensions.z))m")
                } else {
                    appliancePositionsForSmallCabinets.append(pos)
                }
            case .refrigerator:
                appliancePositionsForSmallCabinets.append(pos)
            case .sink:
                sinkPositions.append(pos)
            default:
                break
            }
        }

        // Combine oven infos for wall oven cabinet detection
        let allOvenInfos = ovenInfos + wallOvenInfos
        print("[ScanAnalysis] Found \(ovenInfos.count) ovens, \(wallOvenInfos.count) wall ovens, \(appliancePositionsForSmallCabinets.count) floor appliances")

        // Debug: Print all detected objects by category
        print("[ScanAnalysis] === ALL DETECTED OBJECTS ===")
        for object in room.objects {
            let pos = object.transform.columns.3
            let heightFromFloor = pos.y - floorLevel
            print("[ScanAnalysis] Object: \(object.category) at height \(String(format: "%.2f", heightFromFloor))m, dims: \(String(format: "%.2f", object.dimensions.x))x\(String(format: "%.2f", object.dimensions.y))x\(String(format: "%.2f", object.dimensions.z))m")
        }
        print("[ScanAnalysis] === END OBJECTS ===")

        // Debug: Print storage objects classification
        print("[ScanAnalysis] Upper storage objects: \(upperStorageObjects.count)")
        for (idx, info) in upperStorageObjects.enumerated() {
            print("[ScanAnalysis]   Upper[\(idx)]: height=\(String(format: "%.2f", info.heightAboveFloor))m, dims=\(String(format: "%.2f", info.dimensions.x))x\(String(format: "%.2f", info.dimensions.y))x\(String(format: "%.2f", info.dimensions.z))m, pos.y=\(String(format: "%.2f", info.position.y))")
        }
        print("[ScanAnalysis] Lower storage objects: \(lowerStorageObjects.count)")
        for (idx, info) in lowerStorageObjects.enumerated() {
            print("[ScanAnalysis]   Lower[\(idx)]: height=\(String(format: "%.2f", info.heightAboveFloor))m, dims=\(String(format: "%.2f", info.dimensions.x))x\(String(format: "%.2f", info.dimensions.y))x\(String(format: "%.2f", info.dimensions.z))m, pos.y=\(String(format: "%.2f", info.position.y))")
        }

        // Helper function to check if two objects are horizontally aligned (same X/Z within threshold)
        func areHorizontallyAligned(_ pos1: SIMD4<Float>, _ pos2: SIMD4<Float>, threshold: Float = 0.4) -> Bool {
            let xDiff = abs(pos1.x - pos2.x)
            let zDiff = abs(pos1.z - pos2.z)
            return xDiff < threshold && zDiff < threshold
        }

        // Helper function to find oven between upper and lower cabinet positions
        // Returns the OvenInfo if found, nil otherwise
        func findOvenBetween(upper: SIMD4<Float>, lower: SIMD4<Float>, ovens: [OvenInfo], threshold: Float = 0.4) -> OvenInfo? {
            for ovenInfo in ovens {
                let alignedWithUpper = areHorizontallyAligned(upper, ovenInfo.position, threshold: threshold)
                let alignedWithLower = areHorizontallyAligned(lower, ovenInfo.position, threshold: threshold)
                let ovenBetweenY = ovenInfo.position.y > lower.y && ovenInfo.position.y < upper.y
                if (alignedWithUpper || alignedWithLower) && ovenBetweenY {
                    return ovenInfo
                }
            }
            return nil
        }

        // Helper function to check if a cabinet is above an appliance or sink
        func isAboveApplianceOrSink(_ cabinetPos: SIMD4<Float>, threshold: Float = 0.5) -> (Bool, String?) {
            // Check if above refrigerator or stove
            for appPos in appliancePositionsForSmallCabinets {
                if areHorizontallyAligned(cabinetPos, appPos, threshold: threshold) && cabinetPos.y > appPos.y {
                    return (true, "appliance")
                }
            }
            // Check if above sink
            for sinkPos in sinkPositions {
                if areHorizontallyAligned(cabinetPos, sinkPos, threshold: threshold) && cabinetPos.y > sinkPos.y {
                    return (true, "sink")
                }
            }
            return (false, nil)
        }

        // Helper to create base object data
        func createBaseObjectData(for object: CapturedRoom.Object) -> [String: Any] {
            let transform = object.transform
            let position = transform.columns.3
            let dimensions = object.dimensions

            let widthFt = Double(dimensions.x) * 3.28084
            let heightFt = Double(dimensions.y) * 3.28084
            let depthFt = Double(dimensions.z) * 3.28084

            let halfWidth = dimensions.x / 2.0
            let halfDepth = dimensions.z / 2.0

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

            return [
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
        }

        // Height threshold for small upper cabinets (in meters)
        // Small cabinets above fridge/stove/sink are typically 12-18" (0.3-0.46m) tall
        let smallUpperCabinetMaxHeight: Float = 0.5  // 18 inches

        // PHASE 1: Detect Wall Oven Cabinets and Pantry Cabinets
        // Find vertically aligned upper+lower pairs
        var matchedUpperIndices: Set<Int> = []
        var matchedLowerIndices: Set<Int> = []

        // ===========================================
        // CABINET CLASSIFICATION THRESHOLDS
        // Based on industry standard cabinet dimensions:
        // - Base cabinets: 34.5" tall, on floor
        // - Upper cabinets: 30-42" tall, mounted 54" from floor
        // - Tall/Pantry: 84-96" tall, 12-30" wide, floor to near-ceiling
        // - Wall Oven: 84-96" tall, 30-33" wide (wider for oven cutout)
        // ===========================================

        // Gap thresholds (in meters)
        let maxPantryGap: Float = 0.15  // 6 inches - pantry has minimal/no gap between sections
        let normalKitchenGap: Float = 0.38  // 15 inches - normal gap for backsplash area

        // Height thresholds (in meters)
        let minTallCabinetHeight: Float = 2.0  // 79 inches (~80") - minimum for tall cabinets

        // Width thresholds (in meters)
        let maxPantryWidth: Float = 0.76  // 30 inches - pantry cabinets are narrow
        let minWallOvenWidth: Float = 0.71  // 28 inches - wall oven cabinets are wider (30-33")

        // PHASE 1: WALL OVEN CABINET DETECTION
        // Rule: If oven has a cabinet on top (aligned on X/Z), it's a wall oven cabinet
        // All cabinets on the same vertical axis (X/Z) belong to the wall oven unit
        print("[ScanAnalysis] === WALL OVEN CABINET DETECTION ===")
        print("[ScanAnalysis] Checking \(allOvenInfos.count) ovens for wall oven cabinets")

        for ovenInfo in allOvenInfos {
            let ovenHeightInches = ovenInfo.dimensions.y * 39.37
            let ovenWidthInches = ovenInfo.dimensions.x * 39.37
            print("[ScanAnalysis] Checking oven: height=\(String(format: "%.1f", ovenHeightInches))in, width=\(String(format: "%.1f", ovenWidthInches))in, pos.y=\(String(format: "%.2f", ovenInfo.position.y))")

            // Find the cabinet ABOVE oven (required for wall oven cabinet)
            var cabinetAboveOven: (idx: Int, info: StorageInfo)? = nil
            let smallGapTolerance: Float = 0.05  // 2 inch tolerance

            for (idx, upperInfo) in upperStorageObjects.enumerated() {
                if !matchedUpperIndices.contains(idx) && areHorizontallyAligned(ovenInfo.position, upperInfo.position, threshold: 0.5) {
                    let cabinetBottom = upperInfo.position.y - upperInfo.dimensions.y / 2
                    let ovenTop = ovenInfo.position.y + ovenInfo.dimensions.y / 2
                    if cabinetBottom >= ovenTop - smallGapTolerance {
                        cabinetAboveOven = (idx, upperInfo)
                        print("[ScanAnalysis]   Found cabinet ABOVE oven: height=\(String(format: "%.1f", upperInfo.dimensions.y * 39.37))in")
                        break
                    }
                }
            }

            // WALL OVEN CABINET: Must have at least one cabinet above the oven
            guard let topCabinet = cabinetAboveOven else {
                print("[ScanAnalysis]   No cabinet above oven - not a wall oven cabinet")
                continue
            }

            print("[ScanAnalysis] ✅ WALL OVEN CABINET DETECTED!")

            // Calculate total height: top cabinet's top edge from actual floor
            // Floor is the bottom edge of the lowest storage object (not center)
            let actualFloorLevel = room.objects
                .filter { $0.category == .storage }
                .map { $0.transform.columns.3.y - $0.dimensions.y / 2 }
                .min() ?? 0

            let upperCabinetTopEdge = topCabinet.info.position.y + topCabinet.info.dimensions.y / 2
            let totalHeightFromFloor = upperCabinetTopEdge - actualFloorLevel
            let totalHeightFt = Double(totalHeightFromFloor) * 3.28084

            print("[ScanAnalysis] Floor level (bottom of lowest cabinet): \(String(format: "%.2f", actualFloorLevel))m")
            print("[ScanAnalysis] Top cabinet top edge: \(String(format: "%.2f", upperCabinetTopEdge))m")

            // Get dimensions from upper cabinet (wall oven cabinet is single unit)
            let widthFt = Double(topCabinet.info.dimensions.x) * 3.28084
            let depthFt = Double(topCabinet.info.dimensions.z) * 3.28084
            let ovenHeightFt = Double(ovenInfo.dimensions.y) * 3.28084

            print("[ScanAnalysis] Wall oven height: top edge from floor = \(String(format: "%.1f", totalHeightFt * 12))in")

            // Mark upper cabinet as matched
            matchedUpperIndices.insert(topCabinet.idx)

            // IMPORTANT: Mark ALL cabinets on same vertical axis (X/Z) as matched
            // This prevents any cabinet aligned with the oven from being classified separately
            for (idx, upperInfo) in upperStorageObjects.enumerated() {
                if areHorizontallyAligned(ovenInfo.position, upperInfo.position, threshold: 0.5) {
                    matchedUpperIndices.insert(idx)
                    print("[ScanAnalysis]   Marking upper cabinet \(idx) as part of wall oven (aligned on X/Z)")
                }
            }
            for (idx, lowerInfo) in lowerStorageObjects.enumerated() {
                if areHorizontallyAligned(ovenInfo.position, lowerInfo.position, threshold: 0.5) {
                    matchedLowerIndices.insert(idx)
                    print("[ScanAnalysis]   Marking lower cabinet \(idx) as part of wall oven (aligned on X/Z)")
                }
            }

            // Create wall oven cabinet data
            var cabinetData = createBaseObjectData(for: topCabinet.info.object)
            cabinetData["id"] = "wall_oven_\(wallOvenIndex)"
            cabinetData["type"] = "wall_oven_cabinet"
            cabinetData["total_height_ft"] = totalHeightFt
            cabinetData["total_height_inches"] = formatFeetInches(totalHeightFt)
            cabinetData["oven_height_ft"] = ovenHeightFt
            cabinetData["oven_height_inches"] = formatFeetInches(ovenHeightFt)
            cabinetData["width_ft"] = widthFt
            cabinetData["depth_ft"] = depthFt
            cabinetData["has_oven"] = true

            wallOvenCabinets.append(cabinetData)
            wallOvenIndex += 1
        }

        // PHASE 1B: PANTRY CABINET DETECTION (upper+lower pairs with small gap, no oven)
        print("[ScanAnalysis] === PANTRY CABINET DETECTION ===")
        for (upperIdx, upperInfo) in upperStorageObjects.enumerated() {
            guard !matchedUpperIndices.contains(upperIdx) else { continue }

            for (lowerIdx, lowerInfo) in lowerStorageObjects.enumerated() {
                guard !matchedLowerIndices.contains(lowerIdx) else { continue }

                if areHorizontallyAligned(upperInfo.position, lowerInfo.position) {
                    let gapHeightMeters = upperInfo.position.y - lowerInfo.position.y - upperInfo.dimensions.y/2 - lowerInfo.dimensions.y/2
                    let totalHeightMeters = upperInfo.dimensions.y + lowerInfo.dimensions.y + max(0, gapHeightMeters)
                    let maxWidth = max(upperInfo.dimensions.x, lowerInfo.dimensions.x)

                    // Pantry: tall, narrow, small gap
                    let isPantry = gapHeightMeters < maxPantryGap &&
                                   totalHeightMeters >= minTallCabinetHeight &&
                                   maxWidth <= maxPantryWidth

                    if isPantry {
                        print("[ScanAnalysis] ✅ Pantry cabinet detected")

                        let upperHeightFt = Double(upperInfo.dimensions.y) * 3.28084
                        let lowerHeightFt = Double(lowerInfo.dimensions.y) * 3.28084
                        let gapHeight = Double(gapHeightMeters) * 3.28084
                        let totalHeightFt = upperHeightFt + lowerHeightFt + max(0, gapHeight)
                        let widthFt = Double(maxWidth) * 3.28084
                        let depthFt = max(Double(upperInfo.dimensions.z), Double(lowerInfo.dimensions.z)) * 3.28084

                        var cabinetData = createBaseObjectData(for: lowerInfo.object)
                        cabinetData["id"] = "pantry_\(pantryIndex)"
                        cabinetData["type"] = "pantry_cabinet"
                        cabinetData["total_height_ft"] = totalHeightFt
                        cabinetData["total_height_inches"] = formatFeetInches(totalHeightFt)
                        cabinetData["upper_section_height_ft"] = upperHeightFt
                        cabinetData["lower_section_height_ft"] = lowerHeightFt
                        cabinetData["width_ft"] = widthFt
                        cabinetData["depth_ft"] = depthFt

                        pantryCabinets.append(cabinetData)
                        pantryIndex += 1

                        matchedUpperIndices.insert(upperIdx)
                        matchedLowerIndices.insert(lowerIdx)
                    }
                }
            }
        }

        // PHASE 2: Process remaining upper cabinets - check for small upper cabinets
        for (idx, info) in upperStorageObjects.enumerated() {
            guard !matchedUpperIndices.contains(idx) else { continue }

            var cabinetData = createBaseObjectData(for: info.object)
            let cabinetHeight = info.dimensions.y

            // All upper cabinets are treated as standard upper cabinets
            cabinetData["id"] = "upper_\(upperIndex)"
            cabinetData["type"] = "upper_cabinet"
            upperCabinets.append(cabinetData)
            upperIndex += 1
        }

        // PHASE 3: Process remaining lower cabinets
        for (idx, info) in lowerStorageObjects.enumerated() {
            guard !matchedLowerIndices.contains(idx) else { continue }
            var cabinetData = createBaseObjectData(for: info.object)
            cabinetData["id"] = "lower_\(lowerIndex)"
            cabinetData["type"] = "lower_cabinet"
            lowerCabinets.append(cabinetData)
            lowerIndex += 1
        }

        // PHASE 4: Process non-storage objects (sinks, appliances)
        for object in room.objects {
            switch object.category {
            case .storage:
                break  // Already processed above
            case .sink:
                var sinkData = createBaseObjectData(for: object)
                sinkData["id"] = "sink_\(sinkIndex)"
                sinkData["type"] = "sink"
                sinks.append(sinkData)
                sinkIndex += 1
            case .refrigerator, .stove, .oven, .washerDryer, .dishwasher:
                var applianceData = createBaseObjectData(for: object)
                applianceData["id"] = "appliance_\(applianceIndex)"
                applianceData["type"] = "\(object.category)"
                appliances.append(applianceData)
                applianceIndex += 1
            default:
                break
            }
        }

        print("=== Cabinet Classification Results ===")
        print("Upper cabinets: \(upperCabinets.count)")
        print("Lower cabinets: \(lowerCabinets.count)")
        print("Wall oven cabinets: \(wallOvenCabinets.count)")
        print("Pantry cabinets: \(pantryCabinets.count)")
        print("--- Classification Thresholds (Industry Standard) ---")
        print("Pantry: gap<6\", height>=80\", width<=30\"")
        print("Wall Oven: has oven OR (height>=80\" AND width>=28\")")
        print("Regular: gap>=15\" (normal backsplash area)")
        print("======================================")

        // Room dimensions - handle case where no walls were detected (poor scan)
        // Replace infinity values with 0 to prevent JSON encoding failures
        let safeMinX = minX.isFinite ? Double(minX) * 3.28084 : 0.0
        let safeMaxX = maxX.isFinite ? Double(maxX) * 3.28084 : 0.0
        let safeMinZ = minZ.isFinite ? Double(minZ) * 3.28084 : 0.0
        let safeMaxZ = maxZ.isFinite ? Double(maxZ) * 3.28084 : 0.0

        let roomBounds: [String: Any] = [
            "min_x": safeMinX,
            "max_x": safeMaxX,
            "min_z": safeMinZ,
            "max_z": safeMaxZ,
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
            "lower": lowerCabinets,
            "wall_oven": wallOvenCabinets,
            "pantry": pantryCabinets
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
            "wall_oven_cabinet_count": wallOvenCabinets.count,
            "pantry_cabinet_count": pantryCabinets.count,
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

    // MARK: - Scan Quality Validation

    /// Validates scan quality and either navigates to selection or shows warning
    /// Returns true if scan is acceptable, false if warning was shown
    private func validateAndProceedWithMeasurements(_ measurements: MeasurementData) {
        let wallCount = measurements.wallCount ?? 0
        let hasFloorPlan = measurements.previewImageUrl != nil
        let hasScanFile = measurements.usdzFileUrl != nil

        // Check scan quality indicators
        var issues: [String] = []

        if wallCount == 0 {
            issues.append("No walls were detected")
        }

        if !hasFloorPlan {
            issues.append("Floor plan image could not be generated")
        }

        if !hasScanFile {
            issues.append("3D model could not be created")
        }

        // If multiple issues or critical issues, show warning
        let isCriticallyPoor = wallCount == 0 && !hasFloorPlan && !hasScanFile
        let hasMultipleIssues = issues.count >= 2

        if isCriticallyPoor || hasMultipleIssues {
            // Store measurements and show warning
            pendingPoorScanMeasurements = measurements
            poorScanMessage = """
            The scan quality appears to be poor:

            \(issues.map { "• \($0)" }.joined(separator: "\n"))

            For best results:
            • Ensure good lighting
            • Move slowly and steadily
            • Scan for at least 15-20 seconds
            • Cover all walls and corners

            Would you like to rescan?
            """
            isProcessing = false
            showPoorScanWarning = true
        } else {
            // Scan quality is acceptable, proceed
            appState.setMeasurementData(measurements)
        }
    }
}

// MARK: - Loading Scanner View
struct LoadingScannerView: View {
    @State private var rotation: Double = 0

    var body: some View {
        ZStack {
            Color.black
                .ignoresSafeArea()

            VStack(spacing: 24) {
                // Animated 3D cube icon
                ZStack {
                    Circle()
                        .fill(Color.blue.opacity(0.1))
                        .frame(width: 100, height: 100)

                    Image(systemName: "cube.transparent")
                        .font(.system(size: 40))
                        .foregroundStyle(.blue)
                        .rotationEffect(.degrees(rotation))
                }
                .onAppear {
                    withAnimation(.linear(duration: 2).repeatForever(autoreverses: false)) {
                        rotation = 360
                    }
                }

                VStack(spacing: 12) {
                    Text("Initializing Scanner")
                        .font(.title2)
                        .fontWeight(.semibold)
                        .foregroundColor(.white)

                    Text("Preparing LiDAR and camera systems...")
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.7))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)

                    // Progress indicator dots
                    HStack(spacing: 8) {
                        ForEach(0..<3) { index in
                            Circle()
                                .fill(Color.white.opacity(0.5))
                                .frame(width: 8, height: 8)
                                .scaleEffect(index == Int(rotation / 120) % 3 ? 1.2 : 1.0)
                                .animation(.easeInOut(duration: 0.3).repeatForever(), value: rotation)
                        }
                    }
                    .padding(.top, 8)
                }
            }
        }
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

// Old RoomCaptureViewRepresentable removed - now using pure UIKit implementation in RoomPlanViewController

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

// MARK: - Full Screen Room Capture View (Isolated from Navigation)
// CRITICAL: This view uses UIKit-based overlay to prevent ANY SwiftUI rendering conflicts with RoomPlan
struct FullScreenRoomCaptureView: UIViewControllerRepresentable {
    @Binding var isScanning: Bool
    @Binding var capturedRoom: CapturedRoom?
    var videoRecorder: VideoRecorder?
    @Binding var isRoomPlanReady: Bool
    @Binding var recordingDuration: TimeInterval
    let onComplete: (CapturedRoom) -> Void
    let onDone: () -> Void
    var showProcessing: Bool = false // Show processing overlay when waiting for delegate

    func makeUIViewController(context: Context) -> RoomPlanViewController {
        let controller = RoomPlanViewController()
        controller.coordinator = context.coordinator
        context.coordinator.viewController = controller
        return controller
    }

    func updateUIViewController(_ uiViewController: RoomPlanViewController, context: Context) {
        let previousRecorder = context.coordinator.videoRecorder
        context.coordinator.videoRecorder = videoRecorder
        context.coordinator.onComplete = onComplete
        context.coordinator.onDone = onDone
        context.coordinator.recordingDuration = recordingDuration
        context.coordinator.isRoomPlanReady = isRoomPlanReady
        uiViewController.showProcessing = showProcessing
        uiViewController.updateUI()

        // CRITICAL: Start video recording when videoRecorder becomes available
        // This happens AFTER viewDidLoad, so we start it here instead
        // NOTE: Start immediately - no delay to avoid race condition with Done button
        if let recorder = videoRecorder, previousRecorder == nil, !recorder.isCurrentlyRecording {
            do {
                try recorder.startRecording()
                print("[updateUIViewController] Video recording started")
            } catch {
                print("[updateUIViewController] Failed to start video recording: \(error)")
            }
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(
            isScanning: $isScanning,
            capturedRoom: $capturedRoom,
            isRoomPlanReady: $isRoomPlanReady,
            recordingDuration: $recordingDuration
        )
    }

    class Coordinator: NSObject, RoomCaptureSessionDelegate, ARSessionDelegate {
        @Binding var isScanning: Bool
        @Binding var capturedRoom: CapturedRoom?
        @Binding var isRoomPlanReady: Bool
        @Binding var recordingDuration: TimeInterval
        var videoRecorder: VideoRecorder?
        var onComplete: ((CapturedRoom) -> Void)?
        var onDone: (() -> Void)?
        var sessionStartTime: TimeInterval?
        var hasReceivedFirstFrame = false
        var completionHandled = false
        var isSessionRunning = false
        weak var viewController: RoomPlanViewController?

        init(isScanning: Binding<Bool>, capturedRoom: Binding<CapturedRoom?>, isRoomPlanReady: Binding<Bool>, recordingDuration: Binding<TimeInterval>) {
            _isScanning = isScanning
            _capturedRoom = capturedRoom
            _isRoomPlanReady = isRoomPlanReady
            _recordingDuration = recordingDuration
        }

        func updateUI() {
            // Notify view controller to update UI
            DispatchQueue.main.async {
                self.viewController?.updateUI()
            }
        }

        // MARK: - RoomCaptureSessionDelegate
        func captureSession(_ session: RoomCaptureSession, didStartWith configuration: RoomCaptureSession.Configuration) {
            print("🟢 [Coordinator] captureSession didStartWith called - Session started successfully!")
            print("🟢 [Coordinator] Configuration: \(configuration)")
        }

        func captureSession(_ session: RoomCaptureSession, didUpdate room: CapturedRoom) {
            // Live updates during scanning - called frequently
            if !hasReceivedFirstFrame {
                print("🟢 [Coordinator] First didUpdate received - walls: \(room.walls.count), doors: \(room.doors.count)")
            }
        }

        func captureSession(_ session: RoomCaptureSession, didEndWith data: CapturedRoomData, error: Error?) {
            print("🎯 [Coordinator] captureSession didEndWith called!")
            print("🎯 [Coordinator] Error: \(String(describing: error))")
            print("🎯 [Coordinator] completionHandled: \(completionHandled)")

            guard !completionHandled else {
                print("⚠️ [Coordinator] Already handled completion, ignoring")
                return
            }
            completionHandled = true

            Task { @MainActor in
                print("🎯 [Coordinator] Building room from captured data...")
                let roomBuilder = RoomBuilder(options: [.beautifyObjects])
                do {
                    let room = try await roomBuilder.capturedRoom(from: data)
                    print("✅ [Coordinator] Room built successfully!")
                    capturedRoom = room
                    onComplete?(room)
                    print("✅ [Coordinator] Called onComplete callback")
                } catch {
                    print("❌ [Coordinator] Failed to build room: \(error)")
                }
            }
        }

        // MARK: - ARSessionDelegate
        func session(_ session: ARSession, didUpdate frame: ARFrame) {
            if !hasReceivedFirstFrame {
                hasReceivedFirstFrame = true
                DispatchQueue.main.async {
                    self.isRoomPlanReady = true
                    // Immediately update UI to show Done button
                    self.viewController?.updateUI()
                    print("[Coordinator] First frame received - showing Done button")
                }
            }

            guard let recorder = videoRecorder, recorder.isCurrentlyRecording else { return }

            if sessionStartTime == nil {
                sessionStartTime = frame.timestamp
            }

            let relativeTimestamp = frame.timestamp - (sessionStartTime ?? 0)
            recorder.appendPixelBuffer(frame.capturedImage, timestamp: relativeTimestamp)
        }
    }
}

// MARK: - UIKit-based RoomPlan View Controller
// CRITICAL: Pure UIKit implementation - ZERO SwiftUI rendering conflicts
class RoomPlanViewController: UIViewController {
    weak var coordinator: FullScreenRoomCaptureView.Coordinator?
    private var roomCaptureView: RoomCaptureView!
    private var doneButton: UIButton!
    private var controlsContainer: UIView!
    private var updateTimer: Timer?
    private var processingOverlay: UIView!
    private var processingLabel: UILabel!
    var showProcessing = false

    override func viewDidLoad() {
        super.viewDidLoad()

        print("🟢 [RoomPlanViewController] viewDidLoad - setting up RoomPlan")

        // Log device info for debugging
        let device = UIDevice.current
        print("🟢 [RoomPlanViewController] Device: \(device.model), iOS \(device.systemVersion)")
        print("🟢 [RoomPlanViewController] Device name: \(device.name)")

        // Check RoomPlan support BEFORE attempting to use it
        let isSupported = RoomCaptureSession.isSupported
        print("🟢 [RoomPlanViewController] RoomCaptureSession.isSupported: \(isSupported)")

        guard isSupported else {
            print("❌ [RoomPlanViewController] RoomPlan NOT SUPPORTED on this device!")
            // Show error to user
            DispatchQueue.main.async {
                self.showUnsupportedDeviceError()
            }
            return
        }

        // CRITICAL: RoomPlan view - completely alone at the root
        roomCaptureView = RoomCaptureView(frame: view.bounds)
        roomCaptureView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(roomCaptureView)
        print("🟢 [RoomPlanViewController] RoomCaptureView created and added to view")

        // Set up delegates
        print("🟢 [RoomPlanViewController] Setting coordinator as delegate")
        print("🟢 [RoomPlanViewController] Coordinator: \(String(describing: coordinator))")
        roomCaptureView.captureSession.delegate = coordinator
        roomCaptureView.captureSession.arSession.delegate = coordinator
        print("🟢 [RoomPlanViewController] Delegate set to: \(String(describing: roomCaptureView.captureSession.delegate))")

        // Log ARSession state
        let arSession = roomCaptureView.captureSession.arSession
        print("🟢 [RoomPlanViewController] ARSession state - identifier: \(arSession.identifier)")

        // CRITICAL: UIKit-based controls overlay (no SwiftUI rendering)
        setupControls()

        // Start UI update timer
        updateTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            self?.updateUI()
        }

        // FIX: Delay session start to allow view hierarchy to fully set up
        // This helps prevent race conditions on faster processors (A17 Pro / iPhone 15+)
        // The delay gives the RoomCaptureView time to properly initialize its Metal rendering pipeline
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            guard let self = self else { return }
            let config = RoomCaptureSession.Configuration()
            print("🟢 [RoomPlanViewController] Starting RoomPlan session with config (after delay)...")
            self.roomCaptureView.captureSession.run(configuration: config)
            self.coordinator?.isSessionRunning = true
            print("🟢 [RoomPlanViewController] Session run() called - waiting for didStartWith delegate callback")
        }
    }

    private func showUnsupportedDeviceError() {
        view.backgroundColor = .black

        let errorLabel = UILabel()
        errorLabel.translatesAutoresizingMaskIntoConstraints = false
        errorLabel.text = "RoomPlan is not supported on this device.\n\nThis feature requires a device with LiDAR sensor (iPhone 12 Pro or newer Pro models)."
        errorLabel.textColor = .white
        errorLabel.textAlignment = .center
        errorLabel.numberOfLines = 0
        errorLabel.font = .systemFont(ofSize: 16)
        view.addSubview(errorLabel)

        let closeButton = UIButton(type: .system)
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        closeButton.setTitle("Close", for: .normal)
        closeButton.setTitleColor(.white, for: .normal)
        closeButton.backgroundColor = .systemRed
        closeButton.layer.cornerRadius = 12
        closeButton.addTarget(self, action: #selector(closeErrorTapped), for: .touchUpInside)
        view.addSubview(closeButton)

        NSLayoutConstraint.activate([
            errorLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            errorLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor, constant: -40),
            errorLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 40),
            errorLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -40),
            closeButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            closeButton.topAnchor.constraint(equalTo: errorLabel.bottomAnchor, constant: 30),
            closeButton.widthAnchor.constraint(equalToConstant: 120),
            closeButton.heightAnchor.constraint(equalToConstant: 44)
        ])
    }

    @objc private func closeErrorTapped() {
        coordinator?.onDone?()
    }

    private func setupControls() {
        // Container for controls
        controlsContainer = UIView()
        controlsContainer.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(controlsContainer)

        // Done button only (removed recording indicator)
        doneButton = UIButton(type: .system)
        doneButton.translatesAutoresizingMaskIntoConstraints = false
        doneButton.setTitle("Done", for: .normal)
        doneButton.setTitleColor(.white, for: .normal)
        doneButton.titleLabel?.font = UIFont.systemFont(ofSize: 17, weight: .semibold)
        doneButton.backgroundColor = .systemBlue
        doneButton.layer.cornerRadius = 20
        doneButton.contentEdgeInsets = UIEdgeInsets(top: 8, left: 16, bottom: 8, right: 16)
        doneButton.addTarget(self, action: #selector(doneButtonTapped), for: .touchUpInside)
        doneButton.isHidden = true // Initially hidden
        controlsContainer.addSubview(doneButton)

        // Layout constraints
        NSLayoutConstraint.activate([
            controlsContainer.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            controlsContainer.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            controlsContainer.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            controlsContainer.heightAnchor.constraint(equalToConstant: 60),

            doneButton.trailingAnchor.constraint(equalTo: controlsContainer.trailingAnchor, constant: -16),
            doneButton.centerYAnchor.constraint(equalTo: controlsContainer.centerYAnchor),
            doneButton.heightAnchor.constraint(equalToConstant: 40)
        ])
    }

    @objc private func doneButtonTapped() {
        // Disable button immediately to prevent multiple taps
        doneButton.isEnabled = false
        doneButton.alpha = 0.5
        print("🔴 [RoomPlanViewController] Done button tapped - stopping RoomPlan session")
        print("🔴 [RoomPlanViewController] Coordinator: \(String(describing: coordinator))")
        print("🔴 [RoomPlanViewController] Session delegate: \(String(describing: roomCaptureView.captureSession.delegate))")

        // CRITICAL: Actually STOP the RoomPlan session to trigger delegate callback
        // This was the missing piece - we need to call stop() to get room data!
        coordinator?.videoRecorder = nil // Stop video first
        print("🔴 [RoomPlanViewController] Pausing ARSession...")
        roomCaptureView.captureSession.arSession.pause()
        print("🔴 [RoomPlanViewController] Stopping RoomPlan session...")
        roomCaptureView.captureSession.stop()
        coordinator?.isSessionRunning = false
        print("🔴 [RoomPlanViewController] Session stopped - waiting for delegate callback...")
        print("🔴 [RoomPlanViewController] Delegate is: \(String(describing: roomCaptureView.captureSession.delegate))")

        coordinator?.onDone?()
    }

    func updateUI() {
        guard let coordinator = coordinator else { return }

        // Show/hide Done button based on ready state
        let showControls = coordinator.isRoomPlanReady
        doneButton.isHidden = !showControls
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)

        // Stop UI update timer
        updateTimer?.invalidate()
        updateTimer = nil

        // Re-enable screen sleep (safety)
        UIApplication.shared.isIdleTimerDisabled = false

        // CRITICAL: Aggressive camera cleanup to prevent FigCapture errors
        print("[RoomPlanViewController] View disappearing - cleaning up camera resources...")

        // Stop sessions ONLY if still running (might have been stopped by Done button)
        if coordinator?.isSessionRunning == true {
            print("[RoomPlanViewController] Session still running - stopping now")
            roomCaptureView.captureSession.arSession.pause()
            roomCaptureView.captureSession.stop()
            coordinator?.isSessionRunning = false
        } else {
            print("[RoomPlanViewController] Session already stopped (Done button pressed)")
        }

        // Remove delegates AFTER stopping to allow final callback
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.roomCaptureView.captureSession.delegate = nil
            self.roomCaptureView.captureSession.arSession.delegate = nil

            // Force nil the capture view to release resources
            self.roomCaptureView.removeFromSuperview()
            print("[RoomPlanViewController] Camera cleanup complete")
        }
    }
}

#Preview {
    ScanningView()
        .environmentObject(AppState.shared)
}
