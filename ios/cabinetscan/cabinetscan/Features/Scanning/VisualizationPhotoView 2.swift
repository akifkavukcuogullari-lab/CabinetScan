import SwiftUI
import AVFoundation
import ImageIO
import Combine

public struct VisualizationPhotoView: View {
    let onPhotoTaken: (UIImage) -> Void
    let onSkip: () -> Void

    @StateObject private var camera = CameraController()
    @State private var isPermissionDenied = false

    public init(onPhotoTaken: @escaping (UIImage) -> Void, onSkip: @escaping () -> Void) {
        self.onPhotoTaken = onPhotoTaken
        self.onSkip = onSkip
    }

    public var body: some View {
        VStack(spacing: 20) {
            Text("Take a photo of your space for visualization")
                .font(.headline)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            Group {
                if camera.isSessionRunning {
                    CameraPreviewView(session: camera.session)
                        .aspectRatio(3/4, contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.secondary.opacity(0.5), lineWidth: 1))
                } else if isPermissionDenied {
                    CameraUnavailablePlaceholder()
                        .aspectRatio(3/4, contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.secondary.opacity(0.5), lineWidth: 1))
                } else {
                    ProgressView()
                        .aspectRatio(3/4, contentMode: .fit)
                }
            }
            .padding(.horizontal)

            HStack(spacing: 40) {
                Button(action: {
                    camera.capturePhoto { image in
                        if let img = image {
                            onPhotoTaken(img)
                        }
                    }
                }) {
                    Text("Take Photo")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(camera.isSessionRunning ? Color.blue : Color.gray)
                        .foregroundColor(.white)
                        .cornerRadius(10)
                }
                .disabled(!camera.isSessionRunning)

                Button(action: {
                    onSkip()
                }) {
                    Text("Skip")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.secondary.opacity(0.2))
                        .foregroundColor(.primary)
                        .cornerRadius(10)
                }
            }
            .padding(.horizontal)
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
        switch AVCaptureDevice.authorizationStatus(for: .video) {
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

        // Enable device orientation monitoring for photo capture
        if !UIDevice.current.isGeneratingDeviceOrientationNotifications {
            UIDevice.current.beginGeneratingDeviceOrientationNotifications()
        }

        sessionQueue.async {
            if !self.isConfigured {
                self.configureSession()
            }
            self.session.startRunning()
            DispatchQueue.main.async {
                self.isSessionRunning = self.session.isRunning
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

        // Remove existing inputs if any
        session.inputs.forEach { session.removeInput($0) }

        guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else {
            session.commitConfiguration()
            return
        }

        do {
            let cameraInput = try AVCaptureDeviceInput(device: camera)
            if session.canAddInput(cameraInput) {
                session.addInput(cameraInput)
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
            // Use maxPhotoDimensions for iOS 16+ instead of deprecated isHighResolutionCaptureEnabled
            if #available(iOS 16.0, *) {
                // Setting maxPhotoDimensions to the device's maximum supported dimensions
                // This replaces the deprecated isHighResolutionCaptureEnabled
            } else {
                photoOutput.isHighResolutionCaptureEnabled = true
            }
        } else {
            session.commitConfiguration()
            return
        }

        session.commitConfiguration()
        isConfigured = true
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
