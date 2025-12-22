import SwiftUI
import AVFoundation
import ImageIO
import Combine

public struct VisualizationPhotoView: View {
    let onPhotosCompleted: ([UIImage]) -> Void
    let onSkip: () -> Void

    @StateObject private var camera = CameraController()
    @State private var isPermissionDenied = false
    @State private var capturedPhotos: [UIImage] = []
    @State private var currentPhotoIndex = 0

    private let totalPhotos = 5

    public init(onPhotosCompleted: @escaping ([UIImage]) -> Void, onSkip: @escaping () -> Void) {
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
                    CameraUnavailablePlaceholder()
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

                    Button(action: onSkip) {
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
                            ForEach(Array(capturedPhotos.enumerated()), id: \.offset) { index, image in
                                Image(uiImage: image)
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
        camera.capturePhoto { image in
            guard let img = image else { return }

            capturedPhotos.append(img)
            currentPhotoIndex += 1

            if capturedPhotos.count >= totalPhotos {
                // All photos captured, complete the flow
                onPhotosCompleted(capturedPhotos)
            }
        }
    }
}

private struct CameraUnavailablePlaceholder: View {
    var body: some View {
        ZStack {
            Color(.systemGray5)
            VStack(spacing: 12) {
                Image(systemName: "camera.slash")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 64, height: 64)
                    .foregroundColor(.secondary)
                Text("Camera unavailable")
                    .foregroundColor(.secondary)
                    .font(.subheadline)
            }
        }
    }
}

private class CameraController: NSObject, ObservableObject, AVCapturePhotoCaptureDelegate {
    let session = AVCaptureSession()
    private let photoOutput = AVCapturePhotoOutput()
    private let sessionQueue = DispatchQueue(label: "camera.session.queue")

    private var permissionGranted = false
    private var isConfigured = false

    @Published private(set) var isSessionRunning = false

    private var captureCompletion: ((UIImage?) -> Void)?

    let objectWillChange = ObservableObjectPublisher()

    func requestPermission(completion: @escaping (Bool) -> Void) {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        print("📸 VisualizationPhoto: Camera permission status: \(status.rawValue)")

        switch status {
        case .authorized:
            print("✅ VisualizationPhoto: Camera permission already granted")
            permissionGranted = true
            completion(true)
        case .notDetermined:
            print("⏳ VisualizationPhoto: Requesting camera permission")
            AVCaptureDevice.requestAccess(for: .video) { granted in
                print(granted ? "✅ VisualizationPhoto: Camera permission granted" : "❌ VisualizationPhoto: Camera permission denied")
                self.permissionGranted = granted
                completion(granted)
            }
        default:
            print("❌ VisualizationPhoto: Camera permission not available")
            permissionGranted = false
            completion(false)
        }
    }

    func startSession() {
        print("📸 VisualizationPhoto: startSession called - permissionGranted: \(permissionGranted), isSessionRunning: \(isSessionRunning)")
        guard permissionGranted, !isSessionRunning else {
            print("⚠️ VisualizationPhoto: Cannot start session - permission: \(permissionGranted), running: \(isSessionRunning)")
            return
        }

        // Enable device orientation monitoring for photo capture
        if !UIDevice.current.isGeneratingDeviceOrientationNotifications {
            UIDevice.current.beginGeneratingDeviceOrientationNotifications()
        }

        sessionQueue.async {
            if !self.isConfigured {
                print("📸 VisualizationPhoto: Session not configured, configuring now")
                self.configureSession()
            }

            if self.isConfigured {
                print("📸 VisualizationPhoto: Starting session")
                self.session.startRunning()
                DispatchQueue.main.async {
                    self.isSessionRunning = self.session.isRunning
                    print(self.isSessionRunning ? "✅ VisualizationPhoto: Session running" : "❌ VisualizationPhoto: Session failed to start")
                }
            } else {
                print("❌ VisualizationPhoto: Session configuration failed, cannot start")
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
        print("📸 VisualizationPhoto: Starting session configuration")
        session.beginConfiguration()
        session.sessionPreset = .photo

        // Remove existing inputs if any
        session.inputs.forEach { session.removeInput($0) }

        guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else {
            print("❌ VisualizationPhoto: Failed to get camera device")
            session.commitConfiguration()
            return
        }
        print("✅ VisualizationPhoto: Camera device obtained")

        do {
            let cameraInput = try AVCaptureDeviceInput(device: camera)
            if session.canAddInput(cameraInput) {
                session.addInput(cameraInput)
                print("✅ VisualizationPhoto: Camera input added")
            } else {
                print("❌ VisualizationPhoto: Cannot add camera input")
                session.commitConfiguration()
                return
            }
        } catch {
            print("❌ VisualizationPhoto: Error creating camera input: \(error.localizedDescription)")
            session.commitConfiguration()
            return
        }

        if session.canAddOutput(photoOutput) {
            session.addOutput(photoOutput)
            print("✅ VisualizationPhoto: Photo output added")
            // Use maxPhotoDimensions for iOS 16+ instead of deprecated isHighResolutionCaptureEnabled
            if #available(iOS 16.0, *) {
                // Setting maxPhotoDimensions to the device's maximum supported dimensions
                // This replaces the deprecated isHighResolutionCaptureEnabled
            } else {
                photoOutput.isHighResolutionCaptureEnabled = true
            }
        } else {
            print("❌ VisualizationPhoto: Cannot add photo output")
            session.commitConfiguration()
            return
        }

        session.commitConfiguration()
        isConfigured = true
        print("✅ VisualizationPhoto: Session configuration complete")
    }

    func capturePhoto(completion: @escaping (UIImage?) -> Void) {
        guard isSessionRunning else {
            completion(nil)
            return
        }
        captureCompletion = completion

        // Set the correct orientation on the photo output connection
        if let connection = photoOutput.connection(with: .video) {
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

        // Use maxPhotoDimensions for iOS 16+ instead of deprecated isHighResolutionPhotoEnabled
        if #available(iOS 16.0, *) {
            // maxPhotoDimensions is set on the settings to request maximum resolution
            settings.maxPhotoDimensions = photoOutput.maxPhotoDimensions
        } else {
            settings.isHighResolutionPhotoEnabled = true
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

        // Get the CGImage orientation from photo metadata
        let cgImageOrientation: CGImagePropertyOrientation
        if let orientationValue = photo.metadata[String(kCGImagePropertyOrientation)] as? UInt32,
           let orientation = CGImagePropertyOrientation(rawValue: orientationValue) {
            cgImageOrientation = orientation
        } else {
            cgImageOrientation = .up
        }

        guard let cgImage = photo.cgImageRepresentation() else {
            captureCompletion?(nil)
            captureCompletion = nil
            return
        }

        // Create UIImage with correct orientation from metadata
        let uiOrientation = UIImage.Orientation(cgImageOrientation)
        let image = UIImage(cgImage: cgImage, scale: 1.0, orientation: uiOrientation)

        // Always normalize to ensure pixels match visual orientation
        let normalizedImage = forceNormalizeOrientation(image)
        captureCompletion?(normalizedImage)
        captureCompletion = nil
    }

    /// Force normalize image orientation by redrawing - always applies transform
    /// This ensures the image pixels match the visual orientation regardless of metadata
    private func forceNormalizeOrientation(_ image: UIImage) -> UIImage {
        // Use UIGraphicsImageRenderer which properly handles orientation
        let size = CGSize(width: image.size.width, height: image.size.height)

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1.0
        format.opaque = true

        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        let normalizedImage = renderer.image { context in
            image.draw(at: .zero)
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
