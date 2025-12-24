import SwiftUI
import AVFoundation
import ImageIO
import Combine

// Struct to hold both preview image and compressed photo data
public struct CapturedPhotoData {
    let previewImage: UIImage  // For UI display
    let rawData: Data          // Compressed JPEG data for upload (clear + small file size)
}

public struct VisualizationPhotoView: View {
    let onPhotosCompleted: ([CapturedPhotoData]) -> Void
    let onSkip: () -> Void

    @StateObject private var camera = CameraController()
    @State private var isPermissionDenied = false
    @State private var capturedPhotos: [CapturedPhotoData] = []
    @State private var currentPhotoIndex = 0

    private let totalPhotos = 5

    public init(onPhotosCompleted: @escaping ([CapturedPhotoData]) -> Void, onSkip: @escaping () -> Void) {
        self.onPhotosCompleted = onPhotosCompleted
        self.onSkip = onSkip
    }

    public var body: some View {
        ZStack {
            // Camera preview (full screen)
            Group {
                if camera.isSessionRunning {
                    CameraPreviewView(session: camera.session)
                        .ignoresSafeArea()
                } else if isPermissionDenied {
                    CameraUnavailablePlaceholder(message: "Camera unavailable")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color.black)
                } else {
                    ZStack {
                        Color.black
                        ProgressView()
                            .tint(.white)
                    }
                    .ignoresSafeArea()
                }
            }

            // UI Overlay
            VStack {
                // Top bar with progress and skip
                HStack {
                    Text("Photo \(currentPhotoIndex + 1) of \(totalPhotos)")
                        .font(.headline)
                        .foregroundColor(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(Color.black.opacity(0.6))
                        .clipShape(Capsule())

                    Spacer()

                    Button(action: handleSkip) {
                        Text("Skip")
                            .font(.headline)
                            .foregroundColor(.white)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(Color.black.opacity(0.6))
                            .clipShape(Capsule())
                    }
                }
                .padding()

                Spacer()

                // Instruction text
                Text(instructionText)
                    .font(.title3)
                    .fontWeight(.medium)
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
                    .padding(.vertical, 12)
                    .background(Color.black.opacity(0.6))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .padding(.bottom, 20)

                // Photo indicators
                HStack(spacing: 12) {
                    ForEach(0..<totalPhotos, id: \.self) { index in
                        Circle()
                            .fill(index < capturedPhotos.count ? Color.green : Color.white.opacity(0.3))
                            .frame(width: 12, height: 12)
                            .overlay(
                                Circle()
                                    .stroke(Color.white, lineWidth: index == currentPhotoIndex ? 2 : 0)
                            )
                    }
                }
                .padding(.bottom, 16)

                // Thumbnails of captured photos
                if !capturedPhotos.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(Array(capturedPhotos.enumerated()), id: \.offset) { index, photoData in
                                Image(uiImage: photoData.previewImage)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 60, height: 60)
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8)
                                            .stroke(Color.white, lineWidth: 2)
                                    )
                                    .overlay(
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundColor(.green)
                                            .background(Circle().fill(Color.white))
                                            .offset(x: 20, y: -20)
                                    )
                            }
                        }
                        .padding(.horizontal)
                    }
                    .frame(height: 70)
                    .padding(.bottom, 8)
                }

                // Capture button
                Button(action: capturePhoto) {
                    ZStack {
                        Circle()
                            .strokeBorder(Color.white, lineWidth: 4)
                            .frame(width: 70, height: 70)

                        Circle()
                            .fill(camera.isSessionRunning ? Color.white : Color.gray)
                            .frame(width: 60, height: 60)
                    }
                }
                .disabled(!camera.isSessionRunning)
                .padding(.bottom, 40)
            }
        }
        .onAppear {
            camera.requestPermission { granted in
                DispatchQueue.main.async {
                    if granted {
                        camera.startSession()
                    } else {
                        isPermissionDenied = true
                    }
                }
            }
        }
        .onDisappear {
            camera.stopSession()
            if UIDevice.current.isGeneratingDeviceOrientationNotifications {
                UIDevice.current.endGeneratingDeviceOrientationNotifications()
            }
        }
    }

    private var instructionText: String {
        switch currentPhotoIndex {
        case 0: return "Take the first photo"
        case 1: return "Take the second photo"
        case 2: return "Take the third photo"
        case 3: return "Take the fourth photo"
        case 4: return "Take the final photo"
        default: return "Take photo"
        }
    }

    private func capturePhoto() {
        camera.capturePhoto { photoData in
            guard let data = photoData else { return }

            capturedPhotos.append(data)
            currentPhotoIndex += 1

            if capturedPhotos.count >= totalPhotos {
                // All photos captured, complete the flow
                onPhotosCompleted(capturedPhotos)
            }
        }
    }

    private func handleSkip() {
        // If any photos were captured, save them
        if !capturedPhotos.isEmpty {
            print("📸 [VisualizationPhotoView] Skipped after taking \(capturedPhotos.count) photos - saving them")
            onPhotosCompleted(capturedPhotos)
        } else {
            // No photos taken, skip entirely
            print("📸 [VisualizationPhotoView] Skipped without taking any photos")
            onSkip()
        }
    }
}

private struct CameraUnavailablePlaceholder: View {
    let message: String

    var body: some View {
        ZStack {
            Color(.systemGray5)
            VStack(spacing: 12) {
                Image(systemName: "camera.slash")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 64, height: 64)
                    .foregroundColor(.secondary)
                Text(message)
                    .foregroundColor(.secondary)
                    .font(.subheadline)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
        }
    }
}

private class CameraController: NSObject, ObservableObject, AVCapturePhotoCaptureDelegate {
    let session = AVCaptureSession()
    private let photoOutput = AVCapturePhotoOutput()
    private let sessionQueue = DispatchQueue(label: "camera.session.queue")
    private var videoDeviceInput: AVCaptureDeviceInput?

    private var permissionGranted = false
    private var isConfigured = false

    @Published private(set) var isSessionRunning = false {
        didSet {
            // CRITICAL: Manually trigger objectWillChange since we have a custom publisher
            DispatchQueue.main.async {
                self.objectWillChange.send()
            }
        }
    }

    private var captureCompletion: ((CapturedPhotoData?) -> Void)?

    // Zoom control
    func setZoom(factor: CGFloat) {
        guard let device = videoDeviceInput?.device else { return }

        sessionQueue.async {
            do {
                try device.lockForConfiguration()
                // Clamp zoom factor between min and max
                let maxZoom = min(device.activeFormat.videoMaxZoomFactor, 5.0) // Cap at 5x
                let clampedZoom = max(1.0, min(factor, maxZoom))
                device.videoZoomFactor = clampedZoom
                device.unlockForConfiguration()
            } catch {
                // Silently fail if unable to set zoom
            }
        }
    }

    func requestPermission(completion: @escaping (Bool) -> Void) {
        let status = AVCaptureDevice.authorizationStatus(for: .video)

        switch status {
        case .authorized:
            permissionGranted = true
            completion(true)
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                self.permissionGranted = granted
                completion(granted)
            }
        default:
            permissionGranted = false
            completion(false)
        }
    }

    func startSession() {
        guard permissionGranted, !isSessionRunning else { return }

        if !UIDevice.current.isGeneratingDeviceOrientationNotifications {
            UIDevice.current.beginGeneratingDeviceOrientationNotifications()
        }

        sessionQueue.async {
            if !self.isConfigured {
                self.configureSession()
            }

            if self.isConfigured {
                self.session.startRunning()

                // Wait and verify session actually started
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    if self.session.isRunning {
                        self.isSessionRunning = true
                    } else {
                        // Retry after 1 second
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                            self.retryStartSession(attempt: 1)
                        }
                    }
                }
            }
        }
    }

    private func retryStartSession(attempt: Int) {
        sessionQueue.async {
            self.session.startRunning()

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                if self.session.isRunning {
                    self.isSessionRunning = true
                } else if attempt < 8 {
                    // Try up to 8 times with 1 second intervals
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                        self.retryStartSession(attempt: attempt + 1)
                    }
                }
            }
        }
    }

    func stopSession() {
        guard isSessionRunning else { return }
        sessionQueue.async {
            self.session.stopRunning()
            DispatchQueue.main.async {
                self.isSessionRunning = self.session.isRunning
            }
        }
    }

    private func configureSession() {
        session.beginConfiguration()
        session.sessionPreset = .photo
        session.inputs.forEach { session.removeInput($0) }

        guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else {
            session.commitConfiguration()
            return
        }

        // CRITICAL: Configure camera device for sharp, clear photos (like Apple Photos)
        do {
            try camera.lockForConfiguration()

            // Autofocus - continuous for best focus
            if camera.isFocusModeSupported(.continuousAutoFocus) {
                camera.focusMode = .continuousAutoFocus
            } else if camera.isFocusModeSupported(.autoFocus) {
                camera.focusMode = .autoFocus
            }

            // Exposure - continuous auto exposure
            if camera.isExposureModeSupported(.continuousAutoExposure) {
                camera.exposureMode = .continuousAutoExposure
            } else if camera.isExposureModeSupported(.autoExpose) {
                camera.exposureMode = .autoExpose
            }

            // White balance - continuous auto
            if camera.isWhiteBalanceModeSupported(.continuousAutoWhiteBalance) {
                camera.whiteBalanceMode = .continuousAutoWhiteBalance
            } else if camera.isWhiteBalanceModeSupported(.autoWhiteBalance) {
                camera.whiteBalanceMode = .autoWhiteBalance
            }

            // Image stabilization - CRITICAL for sharp photos
            if let videoConnection = camera.activeFormat.isVideoStabilizationModeSupported(.auto) ? camera.activeFormat : nil {
                // Connection-level stabilization will be set on capture
                print("📸 [Camera] Video stabilization available")
            }

            camera.unlockForConfiguration()
            print("📸 [Camera] Device configured: focus=\(camera.focusMode.rawValue), exposure=\(camera.exposureMode.rawValue)")
        } catch {
            print("⚠️ [Camera] Failed to configure device: \(error)")
        }

        do {
            let cameraInput = try AVCaptureDeviceInput(device: camera)
            if session.canAddInput(cameraInput) {
                session.addInput(cameraInput)
                videoDeviceInput = cameraInput // Save reference for zoom control
            } else {
                session.commitConfiguration()
                return
            }
        } catch {
            session.commitConfiguration()
            return
        }

        if session.canAddOutput(photoOutput) {
            session.addOutput(photoOutput)

            // CRITICAL: Configure for CLEAR photos at reasonable file size
            if #available(iOS 16.0, *) {
                // Use "balanced" prioritization - still sharp but not excessive
                // Let the camera choose the best default dimensions for the device
                photoOutput.maxPhotoQualityPrioritization = .balanced
                print("📸 [Camera] Using default photo dimensions with balanced quality")
            } else {
                photoOutput.isHighResolutionCaptureEnabled = false  // Don't need max res
            }
        } else {
            session.commitConfiguration()
            return
        }

        session.commitConfiguration()
        isConfigured = true
    }

    func capturePhoto(completion: @escaping (CapturedPhotoData?) -> Void) {
        guard isSessionRunning else {
            completion(nil)
            return
        }
        captureCompletion = completion

        // Set the correct orientation on the photo output connection
        if let connection = photoOutput.connection(with: .video) {
            // CRITICAL: Enable video stabilization for sharper photos
            if connection.isVideoStabilizationSupported {
                connection.preferredVideoStabilizationMode = .auto
                print("📸 [Capture] Enabled video stabilization")
            }

            // Get current device orientation and convert to video rotation angle
            let deviceOrientation = UIDevice.current.orientation
            let rotationAngle: CGFloat

            switch deviceOrientation {
            case .portrait:
                rotationAngle = 90
            case .portraitUpsideDown:
                rotationAngle = 270
            case .landscapeLeft:
                rotationAngle = 0
            case .landscapeRight:
                rotationAngle = 180
            default:
                // Default to portrait if orientation is unknown/flat
                rotationAngle = 90
            }

            if connection.isVideoRotationAngleSupported(rotationAngle) {
                connection.videoRotationAngle = rotationAngle
            }
        }

        let settings = AVCapturePhotoSettings()
        // JPEG will be used by default for fileDataRepresentation().
        // If needed, you can prefer HEVC/HEIF by initializing with a specific codec type when supported.

        // CRITICAL: Enable all sharpness features (but keep file size small)
        settings.isAutoStillImageStabilizationEnabled = true  // Enable image stabilization

        // Use balanced quality for clear photos with reasonable file size
        if #available(iOS 16.0, *) {
            // Use default dimensions (don't set explicit maxPhotoDimensions)
            settings.photoQualityPrioritization = .balanced  // Balanced: clear but not excessive
            print("📸 [Capture] Using default dimensions with balanced quality, stabilization: \(settings.isAutoStillImageStabilizationEnabled)")
        } else {
            settings.isHighResolutionPhotoEnabled = false
        }

        photoOutput.capturePhoto(with: settings, delegate: self)
    }

    // MARK: - AVCapturePhotoCaptureDelegate

    func photoOutput(_ output: AVCapturePhotoOutput,
                     didFinishProcessingPhoto photo: AVCapturePhoto,
                     error: Error?) {
        guard error == nil else {
            captureCompletion?(nil)
            captureCompletion = nil
            return
        }

        // CRITICAL: Get camera data and compress to reasonable size
        // 1920x1440 + 0.75 JPEG = clear photos at ~400-600KB each (not 3-5MB!)
        guard let rawData = photo.fileDataRepresentation() else {
            captureCompletion?(nil)
            captureCompletion = nil
            return
        }

        // Create UIImage from camera data
        guard let fullImage = UIImage(data: rawData) else {
            captureCompletion?(nil)
            captureCompletion = nil
            return
        }

        // Compress JPEG to reduce file size while keeping it sharp and clear
        // 0.75 quality = great balance between clarity and file size
        guard let compressedData = fullImage.jpegData(compressionQuality: 0.75) else {
            captureCompletion?(nil)
            captureCompletion = nil
            return
        }

        // Create preview from compressed data (for UI display)
        guard let previewImage = UIImage(data: compressedData) else {
            captureCompletion?(nil)
            captureCompletion = nil
            return
        }

        let originalSizeKB = rawData.count / 1024
        let compressedSizeKB = compressedData.count / 1024
        print("📸 [Capture] Photo compressed: \(originalSizeKB)KB → \(compressedSizeKB)KB")

        // Return both: compressed data for upload (clear + small) and preview for UI
        let photoData = CapturedPhotoData(previewImage: previewImage, rawData: compressedData)
        captureCompletion?(photoData)
        captureCompletion = nil
    }

    /// Force normalize image orientation by redrawing - always applies transform
    /// This ensures the image pixels match the visual orientation regardless of metadata
    private func forceNormalizeOrientation(_ image: UIImage) -> UIImage {
        // CRITICAL: Render at ACTUAL PIXEL dimensions, not point dimensions
        // This preserves the full camera resolution
        let pixelSize = CGSize(
            width: image.size.width * image.scale,
            height: image.size.height * image.scale
        )

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1.0 // Always use 1.0 scale to work in pixels, not points
        format.opaque = true

        let renderer = UIGraphicsImageRenderer(size: pixelSize, format: format)
        let normalizedImage = renderer.image { context in
            // Draw the image at full pixel resolution
            image.draw(in: CGRect(origin: .zero, size: pixelSize))
        }

        return normalizedImage
    }
}

// Helper extension to convert CGImagePropertyOrientation to UIImage.Orientation
extension UIImage.Orientation {
    init(_ cgOrientation: CGImagePropertyOrientation) {
        switch cgOrientation {
        case .up: self = .up
        case .upMirrored: self = .upMirrored
        case .down: self = .down
        case .downMirrored: self = .downMirrored
        case .left: self = .left
        case .leftMirrored: self = .leftMirrored
        case .right: self = .right
        case .rightMirrored: self = .rightMirrored
        }
    }
}

private struct CameraPreviewView: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> PreviewUIView {
        let view = PreviewUIView()
        view.videoPreviewLayer.session = session
        view.videoPreviewLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ uiView: PreviewUIView, context: Context) {
        // Nothing to update
    }

    class PreviewUIView: UIView {
        override class var layerClass: AnyClass {
            AVCaptureVideoPreviewLayer.self
        }

        var videoPreviewLayer: AVCaptureVideoPreviewLayer {
            layer as! AVCaptureVideoPreviewLayer
        }
    }
}
