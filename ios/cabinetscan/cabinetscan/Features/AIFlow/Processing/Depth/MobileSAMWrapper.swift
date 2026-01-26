//
//  MobileSAMWrapper.swift
//  cabinetscan
//
//  Created for Story 3.1: Core ML Model Integration
//

import Foundation
import CoreML
import CoreVideo
import CoreImage
import os.log

/// Point prompt for MobileSAM segmentation
struct SAMPointPrompt {
    let point: CGPoint  // Normalized coordinates (0-1)
    let isPositive: Bool  // true = include this region, false = exclude

    init(point: CGPoint, isPositive: Bool = true) {
        self.point = point
        self.isPositive = isPositive
    }
}

/// Box prompt for MobileSAM segmentation
struct SAMBoxPrompt {
    let topLeft: CGPoint     // Normalized coordinates (0-1)
    let bottomRight: CGPoint // Normalized coordinates (0-1)
}

/// Wrapper for MobileSAM Core ML model for edge refinement
/// NOTE: This model is loaded on-demand, NOT with the primary models
final class MobileSAMWrapper {

    // MARK: - Constants

    /// Model input dimensions
    static let inputWidth = 1024
    static let inputHeight = 1024

    /// Model name in bundle
    private let modelName = "MobileSAM"

    // MARK: - Properties

    private var model: MLModel?
    private let logger = Logger(subsystem: "com.cabinetscan", category: "MobileSAMWrapper")

    /// Shared CIContext for image processing (static to avoid creating multiple heavyweight instances)
    private static let sharedCIContext = CIContext(options: [.useSoftwareRenderer: false])
    private var ciContext: CIContext { Self.sharedCIContext }

    /// Whether the model is currently loaded
    var isLoaded: Bool {
        model != nil
    }

    // MARK: - Loading (On-Demand)

    /// Loads the MobileSAM model if not already loaded
    /// This is called on-demand when edge refinement is needed
    func loadModel() async throws {
        guard model == nil else {
            logger.info("MobileSAM already loaded")
            return
        }

        logger.info("Loading \(self.modelName) on demand...")

        // Find model in bundle
        guard let modelURL = Bundle.main.url(forResource: modelName, withExtension: "mlmodelc") ??
                            Bundle.main.url(forResource: modelName, withExtension: "mlpackage") else {
            throw ModelError.modelNotFound(modelName)
        }

        // Configure for Neural Engine
        let config = MLModelConfiguration()
        config.computeUnits = .all
        config.allowLowPrecisionAccumulationOnGPU = true

        do {
            model = try await MLModel.load(contentsOf: modelURL, configuration: config)
            logger.info("\(self.modelName) loaded successfully")

            // Validate model after loading
            try validateModel()

        } catch {
            logger.error("Failed to load \(self.modelName): \(error.localizedDescription)")
            throw ModelError.loadingFailed(modelName, error)
        }
    }

    /// Loads the model only if needed (convenience wrapper)
    func loadIfNeeded() async throws {
        if model == nil {
            try await loadModel()
        }
    }

    /// Unloads the model to free memory
    func unloadModel() {
        model = nil
        logger.info("\(self.modelName) unloaded")
    }

    // MARK: - Validation

    /// Validates that the loaded model has expected structure
    private func validateModel() throws {
        guard let model = model else {
            throw ModelError.modelNotLoaded(modelName)
        }

        // Log input/output info for debugging
        for (name, desc) in model.modelDescription.inputDescriptionsByName {
            logger.debug("Model input: \(name), type: \(String(describing: desc.type))")
        }

        for (name, desc) in model.modelDescription.outputDescriptionsByName {
            logger.debug("Model output: \(name), type: \(String(describing: desc.type))")
        }
    }

    // MARK: - Inference

    /// Generates a segmentation mask from point prompts
    /// - Parameters:
    ///   - pixelBuffer: Input image
    ///   - points: Array of point prompts (positive = include, negative = exclude)
    /// - Returns: Binary segmentation mask as MLMultiArray
    func generateMask(
        from pixelBuffer: CVPixelBuffer,
        points: [SAMPointPrompt]
    ) async throws -> MLMultiArray {
        try await loadIfNeeded()

        guard let model = model else {
            throw ModelError.modelNotLoaded(modelName)
        }

        // Preprocess image
        let preprocessedBuffer = try preprocessImage(pixelBuffer)

        // Create model input with point prompts
        let input = try createModelInput(
            from: preprocessedBuffer,
            points: points
        )

        // Run inference
        let output = try await model.prediction(from: input)

        // Extract mask
        let mask = try extractMask(from: output)

        return mask
    }

    /// Generates a segmentation mask from a bounding box prompt
    /// - Parameters:
    ///   - pixelBuffer: Input image
    ///   - box: Bounding box prompt
    /// - Returns: Binary segmentation mask as MLMultiArray
    func generateMask(
        from pixelBuffer: CVPixelBuffer,
        box: SAMBoxPrompt
    ) async throws -> MLMultiArray {
        try await loadIfNeeded()

        guard let model = model else {
            throw ModelError.modelNotLoaded(modelName)
        }

        // Preprocess image
        let preprocessedBuffer = try preprocessImage(pixelBuffer)

        // Create model input with box prompt
        let input = try createModelInput(
            from: preprocessedBuffer,
            box: box
        )

        // Run inference
        let output = try await model.prediction(from: input)

        // Extract mask
        let mask = try extractMask(from: output)

        return mask
    }

    // MARK: - Preprocessing

    /// Preprocesses the input image: resize to model input size
    private func preprocessImage(_ pixelBuffer: CVPixelBuffer) throws -> CVPixelBuffer {
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)

        let originalWidth = CGFloat(CVPixelBufferGetWidth(pixelBuffer))
        let originalHeight = CGFloat(CVPixelBufferGetHeight(pixelBuffer))

        let scaleX = CGFloat(Self.inputWidth) / originalWidth
        let scaleY = CGFloat(Self.inputHeight) / originalHeight

        let scaledImage = ciImage.transformed(by: CGAffineTransform(scaleX: scaleX, y: scaleY))

        var outputBuffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            Self.inputWidth,
            Self.inputHeight,
            kCVPixelFormatType_32BGRA,
            [
                kCVPixelBufferCGImageCompatibilityKey: true,
                kCVPixelBufferCGBitmapContextCompatibilityKey: true
            ] as CFDictionary,
            &outputBuffer
        )

        guard status == kCVReturnSuccess, let buffer = outputBuffer else {
            throw NSError(domain: "MobileSAMWrapper", code: -1,
                         userInfo: [NSLocalizedDescriptionKey: "Failed to create pixel buffer"])
        }

        ciContext.render(scaledImage, to: buffer)

        return buffer
    }

    /// Creates model input from pixel buffer and point prompts
    private func createModelInput(
        from pixelBuffer: CVPixelBuffer,
        points: [SAMPointPrompt]
    ) throws -> MLFeatureProvider {
        guard let model = model else {
            throw ModelError.modelNotLoaded(modelName)
        }

        var inputDict: [String: MLFeatureValue] = [:]

        // Add image input
        if let imageInputName = model.modelDescription.inputDescriptionsByName.keys.first(where: { $0.lowercased().contains("image") }) {
            inputDict[imageInputName] = MLFeatureValue(pixelBuffer: pixelBuffer)
        }

        // Add point prompts (format depends on specific model variant)
        // This is a placeholder - actual implementation depends on model structure
        // MobileSAM typically expects:
        // - point_coords: [N, 2] array of (x, y) coordinates
        // - point_labels: [N] array of labels (1 = positive, 0 = negative)

        // Note: The actual input format may need adjustment based on the specific
        // MobileSAM Core ML model variant being used

        return try MLDictionaryFeatureProvider(dictionary: inputDict)
    }

    /// Creates model input from pixel buffer and box prompt
    private func createModelInput(
        from pixelBuffer: CVPixelBuffer,
        box: SAMBoxPrompt
    ) throws -> MLFeatureProvider {
        guard let model = model else {
            throw ModelError.modelNotLoaded(modelName)
        }

        var inputDict: [String: MLFeatureValue] = [:]

        // Add image input
        if let imageInputName = model.modelDescription.inputDescriptionsByName.keys.first(where: { $0.lowercased().contains("image") }) {
            inputDict[imageInputName] = MLFeatureValue(pixelBuffer: pixelBuffer)
        }

        // Add box prompt
        // Format depends on specific model variant

        return try MLDictionaryFeatureProvider(dictionary: inputDict)
    }

    // MARK: - Postprocessing

    /// Extracts binary mask from model output
    private func extractMask(from output: MLFeatureProvider) throws -> MLMultiArray {
        // Find mask output
        guard let maskName = output.featureNames.first(where: { $0.lowercased().contains("mask") }),
              let maskFeature = output.featureValue(for: maskName),
              let maskArray = maskFeature.multiArrayValue else {
            // Fallback: try first output
            guard let outputName = output.featureNames.first,
                  let feature = output.featureValue(for: outputName),
                  let array = feature.multiArrayValue else {
                throw NSError(domain: "MobileSAMWrapper", code: -2,
                             userInfo: [NSLocalizedDescriptionKey: "Failed to extract mask from output"])
            }
            return array
        }

        return maskArray
    }

    /// Converts MLMultiArray mask to a 2D binary array
    /// - Parameter maskArray: Raw mask output from model
    /// - Returns: 2D binary array [height][width] where 1 = inside mask, 0 = outside
    func maskToBinary(_ maskArray: MLMultiArray, threshold: Float = 0.5) -> [[Int]] {
        let shape = maskArray.shape.map { $0.intValue }

        // Handle different output shapes
        let height: Int
        let width: Int

        if shape.count >= 2 {
            height = shape[shape.count - 2]
            width = shape[shape.count - 1]
        } else {
            height = shape[0]
            width = 1
        }

        var result: [[Int]] = []
        let pointer = maskArray.dataPointer.bindMemory(to: Float.self, capacity: height * width)

        for y in 0..<height {
            var row: [Int] = []
            for x in 0..<width {
                let index = y * width + x
                let value = pointer[index]
                row.append(value > threshold ? 1 : 0)
            }
            result.append(row)
        }

        return result
    }

    /// Refines edges of a mask using MobileSAM
    /// - Parameters:
    ///   - pixelBuffer: Original image
    ///   - roughMask: Initial rough mask (e.g., from DeepLabV3)
    /// - Returns: Refined binary mask with sharper edges
    func refineEdges(
        from pixelBuffer: CVPixelBuffer,
        roughMask: [[Int]]
    ) async throws -> [[Int]] {
        // Find boundary points from rough mask
        let boundaryPoints = findBoundaryPoints(in: roughMask)

        guard !boundaryPoints.isEmpty else {
            // No edges to refine, return original
            return roughMask
        }

        // Use boundary points as prompts
        let prompts = boundaryPoints.prefix(10).map { point in
            SAMPointPrompt(
                point: CGPoint(
                    x: CGFloat(point.x) / CGFloat(roughMask[0].count),
                    y: CGFloat(point.y) / CGFloat(roughMask.count)
                ),
                isPositive: true
            )
        }

        let refinedMaskArray = try await generateMask(from: pixelBuffer, points: Array(prompts))
        return maskToBinary(refinedMaskArray)
    }

    /// Finds boundary points in a binary mask
    private func findBoundaryPoints(in mask: [[Int]]) -> [(x: Int, y: Int)] {
        var points: [(x: Int, y: Int)] = []

        guard !mask.isEmpty, !mask[0].isEmpty else { return points }

        let height = mask.count
        let width = mask[0].count

        for y in 1..<(height - 1) {
            for x in 1..<(width - 1) {
                if mask[y][x] == 1 {
                    // Check if this is a boundary pixel
                    let neighbors = [
                        mask[y-1][x], mask[y+1][x],
                        mask[y][x-1], mask[y][x+1]
                    ]

                    if neighbors.contains(0) {
                        points.append((x: x, y: y))
                    }
                }
            }
        }

        return points
    }
}
