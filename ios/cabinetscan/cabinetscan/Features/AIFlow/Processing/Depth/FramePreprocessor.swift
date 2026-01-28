//
//  FramePreprocessor.swift
//  cabinetscan
//
//  Created for Story 3.2: Frame Extraction and Depth Estimation
//

import Foundation
import CoreVideo
import CoreImage
import os.log

// MARK: - Preprocessing Errors

enum FramePreprocessingError: LocalizedError {
    case pixelBufferCreationFailed
    case renderingFailed
    case invalidInputBuffer

    var errorDescription: String? {
        switch self {
        case .pixelBufferCreationFailed:
            return "Failed to create preprocessed pixel buffer"
        case .renderingFailed:
            return "Failed to render preprocessed image"
        case .invalidInputBuffer:
            return "Invalid input pixel buffer"
        }
    }
}

// MARK: - Frame Preprocessor

/// Preprocesses video frames for depth estimation model input.
/// Handles resizing to model input dimensions (518x518) with center-crop.
///
/// **Critical:** Uses static shared CIContext to avoid memory overhead
/// (~100-200MB per instance). See Story 3.1 learnings.
///
/// **Usage:**
/// ```swift
/// let preprocessor = FramePreprocessor()
/// let processedBuffer = try preprocessor.preprocess(frame.pixelBuffer)
/// ```
final class FramePreprocessor {

    // MARK: - Constants

    /// Target width for model input (DepthAnything V2)
    static let targetWidth = 518

    /// Target height for model input (DepthAnything V2)
    static let targetHeight = 518

    // MARK: - Properties

    /// Shared CIContext for efficient image processing.
    /// Static to avoid creating multiple heavyweight instances (~100-200MB each).
    /// Uses hardware acceleration when available.
    private static let sharedCIContext = CIContext(options: [
        .useSoftwareRenderer: false,
        .cacheIntermediates: false  // Reduce memory usage
    ])

    private var ciContext: CIContext { Self.sharedCIContext }

    private let logger = Logger(subsystem: "com.cabinetscan", category: "FramePreprocessor")

    // MARK: - Preprocessing

    /// Preprocesses a pixel buffer by resizing to model input dimensions.
    /// Uses center-crop to preserve aspect ratio.
    ///
    /// - Parameter pixelBuffer: Source pixel buffer (any size)
    /// - Returns: Preprocessed pixel buffer (518x518)
    /// - Throws: FramePreprocessingError if preprocessing fails
    func preprocess(_ pixelBuffer: CVPixelBuffer) throws -> CVPixelBuffer {
        let inputWidth = CVPixelBufferGetWidth(pixelBuffer)
        let inputHeight = CVPixelBufferGetHeight(pixelBuffer)

        // Create CIImage from input
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)

        // Calculate center-crop region to get square aspect ratio
        let croppedImage = centerCrop(ciImage, width: inputWidth, height: inputHeight)

        // Scale to target dimensions
        let scaledImage = scale(croppedImage, to: CGSize(width: Self.targetWidth, height: Self.targetHeight))

        // Create output pixel buffer
        let outputBuffer = try createOutputBuffer()

        // Render to output buffer
        ciContext.render(scaledImage, to: outputBuffer)

        return outputBuffer
    }

    /// Preprocesses a pixel buffer with optional custom target size.
    /// Used for photo processing at higher resolution.
    ///
    /// - Parameters:
    ///   - pixelBuffer: Source pixel buffer
    ///   - targetSize: Custom target size (default: 518x518)
    /// - Returns: Preprocessed pixel buffer
    func preprocess(_ pixelBuffer: CVPixelBuffer, targetSize: CGSize) throws -> CVPixelBuffer {
        let inputWidth = CVPixelBufferGetWidth(pixelBuffer)
        let inputHeight = CVPixelBufferGetHeight(pixelBuffer)

        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        let croppedImage = centerCrop(ciImage, width: inputWidth, height: inputHeight)
        let scaledImage = scale(croppedImage, to: targetSize)

        let outputBuffer = try createOutputBuffer(width: Int(targetSize.width), height: Int(targetSize.height))
        ciContext.render(scaledImage, to: outputBuffer)

        return outputBuffer
    }

    // MARK: - Image Transformations

    /// Applies center-crop to make the image square.
    /// Takes the largest centered square from the input image.
    ///
    /// - Parameters:
    ///   - image: Source CIImage
    ///   - width: Source width
    ///   - height: Source height
    /// - Returns: Center-cropped CIImage (square)
    private func centerCrop(_ image: CIImage, width: Int, height: Int) -> CIImage {
        let size = min(width, height)
        let offsetX = (width - size) / 2
        let offsetY = (height - size) / 2

        let cropRect = CGRect(x: offsetX, y: offsetY, width: size, height: size)
        return image.cropped(to: cropRect)
    }

    /// Scales image to target size.
    ///
    /// - Parameters:
    ///   - image: Source CIImage
    ///   - size: Target size
    /// - Returns: Scaled CIImage
    private func scale(_ image: CIImage, to size: CGSize) -> CIImage {
        let scaleX = size.width / image.extent.width
        let scaleY = size.height / image.extent.height

        // Apply scaling and translate to origin
        return image
            .transformed(by: CGAffineTransform(scaleX: scaleX, y: scaleY))
            .transformed(by: CGAffineTransform(translationX: -image.extent.origin.x * scaleX,
                                                y: -image.extent.origin.y * scaleY))
    }

    // MARK: - Buffer Creation

    /// Creates an output pixel buffer for preprocessed image.
    ///
    /// - Parameters:
    ///   - width: Buffer width (default: 518)
    ///   - height: Buffer height (default: 518)
    /// - Returns: Empty CVPixelBuffer ready for rendering
    private func createOutputBuffer(
        width: Int = FramePreprocessor.targetWidth,
        height: Int = FramePreprocessor.targetHeight
    ) throws -> CVPixelBuffer {
        var pixelBuffer: CVPixelBuffer?

        let attributes: [String: Any] = [
            kCVPixelBufferCGImageCompatibilityKey as String: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey as String: true,
            kCVPixelBufferMetalCompatibilityKey as String: true
        ]

        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            width,
            height,
            kCVPixelFormatType_32BGRA,
            attributes as CFDictionary,
            &pixelBuffer
        )

        guard status == kCVReturnSuccess, let buffer = pixelBuffer else {
            throw FramePreprocessingError.pixelBufferCreationFailed
        }

        return buffer
    }
}
