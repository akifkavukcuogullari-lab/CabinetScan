//
//  PhotoCaptureViewModel.swift
//  cabinetscan
//
//  Created by Dev Agent on 2026-01-26.
//

import SwiftUI
import Combine
import AVFoundation

// MARK: - Captured Photo Item

/// Internal model for a captured photo with all associated data
/// Note: Full image is NOT stored in memory - only thumbnail for strip display.
/// Full image is loaded on-demand from URL when preview is shown.
struct CapturedPhotoItem: Identifiable {
    let id: UUID
    let url: URL
    let thumbnail: UIImage
    let pose: AIPose?
    let timestamp: TimeInterval
    let isBlurry: Bool
    let blurScore: Float

    /// Load full image from disk on-demand
    func loadFullImage() -> UIImage? {
        guard let data = try? Data(contentsOf: url),
              let image = UIImage(data: data) else {
            return nil
        }
        return image
    }
}

// MARK: - Photo Capture ViewModel

/// ViewModel for photo capture screen.
/// Manages photo capture state, quality analysis, and angle guidance.
/// Per Story 2.5 - Task 2
@MainActor
class PhotoCaptureViewModel: ObservableObject {

    // MARK: - Published Properties (Task 2.2 - 2.6)

    /// Array of captured photos
    @Published private(set) var capturedPhotos: [CapturedPhotoItem] = []

    /// Number of photos captured (0-5)
    @Published private(set) var photoCount: Int = 0

    /// Whether user can proceed to next step (5 photos captured)
    @Published private(set) var canContinue: Bool = false

    /// Current photo being previewed (nil = no preview)
    @Published var currentPreviewPhoto: PreviewPhoto?

    /// Whether to show blur warning toast
    @Published private(set) var showBlurWarning: Bool = false

    /// Whether to show angle similarity warning
    @Published private(set) var showAngleSuggestion: Bool = false

    /// Text for angle suggestion
    @Published private(set) var angleSuggestionText: String = ""

    /// Whether capture is in progress
    @Published private(set) var isCapturing: Bool = false

    /// Whether to show completion celebration
    @Published private(set) var showCompletionCelebration: Bool = false

    /// Error message to display
    @Published var errorMessage: String?

    // MARK: - Constants

    /// Required number of photos
    static let requiredPhotoCount = 5

    /// Toast display duration
    private let toastDuration: TimeInterval = 3.0

    // MARK: - Dependencies (Task 2.10)

    /// Photo capture service
    private var photoCapture: AIPhotoCapture?

    /// AR session manager for pose data
    private let sessionManager: AIARSessionManager

    /// Quality analyzer for blur detection
    private let qualityAnalyzer: AIQualityAnalyzer

    /// Angle tracker for diversity guidance
    private let angleTracker: AIAngleTracker

    /// Capture session for camera
    private var captureSession: AVCaptureSession?

    /// Capture data manager for persistence (Story 2.6)
    private var dataManager: AICaptureDataManager?

    // MARK: - Subscriptions

    private var cancellables = Set<AnyCancellable>()

    // MARK: - Initialization

    /// Initialize with required dependencies
    /// - Parameters:
    ///   - sessionManager: AR session manager for pose tracking
    ///   - captureSession: AVCaptureSession from video capture (optional, will create if nil)
    ///   - dataManager: Capture data manager for persistence (Story 2.6)
    init(sessionManager: AIARSessionManager, captureSession: AVCaptureSession? = nil, dataManager: AICaptureDataManager? = nil) {
        self.sessionManager = sessionManager
        self.captureSession = captureSession
        self.dataManager = dataManager
        self.qualityAnalyzer = AIQualityAnalyzer()
        self.angleTracker = AIAngleTracker()

        print("[PhotoCaptureViewModel] Initialized with dataManager: \(dataManager != nil)")
    }

    /// Set the data manager (for dependency injection after init)
    func setDataManager(_ manager: AICaptureDataManager) {
        self.dataManager = manager
    }

    // MARK: - Setup

    /// Setup photo capture with capture session
    /// - Parameter session: The AVCaptureSession to use
    func setupPhotoCapture(with session: AVCaptureSession) {
        self.captureSession = session
        self.photoCapture = AIPhotoCapture(captureSession: session, sessionManager: sessionManager)
        print("[PhotoCaptureViewModel] Photo capture setup complete")
    }

    // MARK: - Public Methods (Task 2.7 - 2.9)

    /// Capture a photo
    /// Handles quality analysis, angle checking, and saving
    func capturePhoto() {
        guard !isCapturing else { return }
        guard photoCount < Self.requiredPhotoCount else { return }

        isCapturing = true

        Task {
            do {
                // Capture photo
                guard let result = try await photoCapture?.capturePhoto() else {
                    throw PhotoCaptureError.sessionNotRunning
                }

                // Analyze quality
                let qualityResult = qualityAnalyzer.analyzePhoto(result.image)

                // Check angle similarity (if we have a pose)
                var angleSuggestion: String?
                if let pose = result.pose {
                    let similarityResult = angleTracker.isAngleTooSimilar(currentPose: pose)
                    if similarityResult.isSimilar {
                        angleSuggestion = similarityResult.suggestion
                    }
                }

                // Determine photo index
                let photoIndex = capturedPhotos.count

                // Persist photo and pose to session directory (Story 2.6)
                var persistedURL = result.url
                if let manager = dataManager {
                    do {
                        // Copy photo to session directory with standardized name
                        persistedURL = try manager.copyPhotoToSession(from: result.url, index: photoIndex)

                        // Save pose data alongside photo
                        if let pose = result.pose {
                            try manager.savePhotoPose(for: persistedURL, pose: pose, index: photoIndex, timestamp: result.timestamp)
                        }

                        // Issue #3 fix: Clean up original temp file after successful copy
                        if persistedURL != result.url {
                            try? FileManager.default.removeItem(at: result.url)
                        }
                    } catch {
                        print("[PhotoCaptureViewModel] Warning: Failed to persist photo to session: \(error)")
                        // Continue with original URL - photo is still captured
                    }
                }

                // Create captured photo item (full image not stored - loaded on-demand)
                let item = CapturedPhotoItem(
                    id: UUID(),
                    url: persistedURL,
                    thumbnail: result.thumbnail,
                    pose: result.pose,
                    timestamp: result.timestamp,
                    isBlurry: !qualityResult.isAcceptable && qualityResult.issues.contains(where: {
                        if case .tooBlurry = $0 { return true }
                        return false
                    }),
                    blurScore: qualityResult.blurScore
                )

                // Add to captures
                capturedPhotos.append(item)
                photoCount = capturedPhotos.count
                canContinue = photoCount >= Self.requiredPhotoCount

                // Record angle for future comparisons (if pose available)
                if let pose = result.pose {
                    angleTracker.recordCapture(pose: pose)
                }

                // Show warnings if needed
                if item.isBlurry {
                    showBlurWarningToast()
                }

                if let suggestion = angleSuggestion {
                    showAngleSuggestionToast(suggestion)
                }

                // Check for completion
                if canContinue {
                    showCompletionAnimation()
                }

                print("[PhotoCaptureViewModel] Photo captured - count: \(photoCount), blurry: \(item.isBlurry)")

            } catch {
                print("[PhotoCaptureViewModel] Capture failed: \(error.localizedDescription)")
                errorMessage = error.localizedDescription
            }

            isCapturing = false
        }
    }

    /// Delete photo at index
    /// - Parameter index: Index of photo to delete
    func deletePhoto(at index: Int) {
        guard index >= 0 && index < capturedPhotos.count else { return }

        // Get the photo before removing
        let photo = capturedPhotos[index]

        // Remove from arrays
        capturedPhotos.remove(at: index)
        angleTracker.removeCapture(at: index)

        // Update counts
        photoCount = capturedPhotos.count
        canContinue = photoCount >= Self.requiredPhotoCount
        showCompletionCelebration = false

        // Delete file from disk
        try? FileManager.default.removeItem(at: photo.url)

        print("[PhotoCaptureViewModel] Photo deleted at index \(index) - count: \(photoCount)")
    }

    /// Show preview for a photo
    /// - Parameter index: Index of photo to preview
    func showPreview(for index: Int) {
        guard index >= 0 && index < capturedPhotos.count else { return }

        let photo = capturedPhotos[index]
        // Load full image on-demand from disk (not stored in memory)
        let fullImage = photo.loadFullImage()
        currentPreviewPhoto = PreviewPhoto(
            id: photo.id,
            index: index,
            image: fullImage,
            isBlurry: photo.isBlurry
        )
    }

    /// Dismiss the current preview
    func dismissPreview() {
        currentPreviewPhoto = nil
    }

    // MARK: - Constants

    /// Default camera intrinsics for iPhone (typical values for 1080p)
    /// Used as fallback when pose is unavailable (Issue #6 fix)
    private static let defaultIntrinsics = AICameraIntrinsics(
        fx: 1080,  // Typical focal length in pixels
        fy: 1080,
        cx: 540,   // Principal point at image center
        cy: 960
    )

    /// Get photos for session data (for coordinator)
    func getPhotosForSession() -> [AICapturedPhoto] {
        return capturedPhotos.map { item in
            AICapturedPhoto(
                url: item.url,
                // Issue #6 fix: Use realistic default intrinsics instead of zeros
                pose: item.pose ?? AIPose(
                    transform: matrix_identity_float4x4,
                    intrinsics: Self.defaultIntrinsics,
                    trackingState: .notAvailable,
                    zoomFactor: 1.0
                ),
                timestamp: item.timestamp
            )
        }
    }

    /// Get thumbnails for the strip
    func getThumbnailItems() -> [PhotoThumbnailItem] {
        return capturedPhotos.map { item in
            PhotoThumbnailItem(
                id: item.id,
                thumbnail: item.thumbnail,
                isBlurry: item.isBlurry
            )
        }
    }

    /// Cleanup resources
    func cleanup() {
        photoCapture?.cleanup()
        print("[PhotoCaptureViewModel] Cleanup complete")
    }

    // MARK: - Private Methods

    /// Show blur warning toast
    private func showBlurWarningToast() {
        showBlurWarning = true

        // Auto-dismiss after duration
        Task {
            try? await Task.sleep(nanoseconds: UInt64(toastDuration * 1_000_000_000))
            await MainActor.run {
                self.showBlurWarning = false
            }
        }
    }

    /// Show angle suggestion toast
    private func showAngleSuggestionToast(_ suggestion: String) {
        angleSuggestionText = suggestion
        showAngleSuggestion = true

        // Auto-dismiss after duration
        Task {
            try? await Task.sleep(nanoseconds: UInt64(toastDuration * 1_000_000_000))
            await MainActor.run {
                self.showAngleSuggestion = false
            }
        }
    }

    /// Show completion animation
    private func showCompletionAnimation() {
        showCompletionCelebration = true
    }
}
