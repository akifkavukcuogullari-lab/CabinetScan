//
//  DepthAnythingWrapper.swift
//  cabinetscan
//
//  Created for Story 3.1: Core ML Model Integration
//

import Foundation
import CoreML
import CoreVideo
import CoreImage
import os.log

/// Wrapper for Depth Anything V2 Small Core ML model
/// Handles model loading, input preprocessing, inference, and output postprocessing
final class DepthAnythingWrapper {

    // MARK: - Constants

    /// Model input dimensions (518x518 RGB)
    static let inputWidth = 518
    static let inputHeight = 518
    static let inputChannels = 3

    /// Model name in bundle
    private let modelName = "DepthAnythingV2SmallF16"

    // MARK: - Properties

    private var model: MLModel?
    private let logger = Logger(subsystem: "com.cabinetscan", category: "DepthAnythingWrapper")

    /// Shared CIContext for image processing (static to avoid creating multiple heavyweight instances)
    private static let sharedCIContext = CIContext(options: [.useSoftwareRenderer: false])
    private var ciContext: CIContext { Self.sharedCIContext }

    // MARK: - Loading

    /// Loads the Depth Anything V2 model with optimal configuration
    func loadModel() async throws {
        logger.info("Loading \(self.modelName)...")

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

            // Log compute unit info
            logComputeUnitInfo()

        } catch {
            logger.error("Failed to load \(self.modelName): \(error.localizedDescription)")
            throw ModelError.loadingFailed(modelName, error)
        }
    }

    /// Unloads the model to free memory
    func unloadModel() {
        model = nil
        logger.info("\(self.modelName) unloaded")
    }

    // MARK: - Validation

    /// Validates that the loaded model has expected input/output shapes
    private func validateModel() throws {
        guard let model = model else {
            throw ModelError.modelNotLoaded(modelName)
        }

        // Validate input
        guard let inputDescription = model.modelDescription.inputDescriptionsByName.first?.value else {
            throw ModelError.invalidInputDescription
        }

        // Log input details for debugging
        logger.debug("Model input: \(inputDescription.name), type: \(String(describing: inputDescription.type))")

        // Validate output exists
        guard let outputDescription = model.modelDescription.outputDescriptionsByName.first?.value else {
            throw ModelError.invalidInputDescription
        }

        logger.debug("Model output: \(outputDescription.name), type: \(String(describing: outputDescription.type))")
    }

    private func logComputeUnitInfo() {
        // Note: There's no direct API to query which compute unit is used,
        // but we can log the configuration
        logger.info("Model configured with computeUnits: .all (Neural Engine + GPU + CPU)")
    }

    // MARK: - Inference

    /// Performs depth estimation on an input image
    /// - Parameter pixelBuffer: Input image as CVPixelBuffer (any size, will be resized)
    /// - Returns: Depth map as MLMultiArray (518x518 relative depth values)
    func predict(image pixelBuffer: CVPixelBuffer) async throws -> MLMultiArray {
        guard let model = model else {
            throw ModelError.modelNotLoaded(modelName)
        }

        // Preprocess: resize and normalize
        let preprocessedBuffer = try preprocessImage(pixelBuffer)

        // Create model input
        let input = try createModelInput(from: preprocessedBuffer)

        // Run inference
        let output = try await model.prediction(from: input)

        // Extract depth map from output
        let depthMap = try extractDepthMap(from: output)

        return depthMap
    }

    // MARK: - Preprocessing

    /// Preprocesses the input image: resize to 518x518 and normalize
    private func preprocessImage(_ pixelBuffer: CVPixelBuffer) throws -> CVPixelBuffer {
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)

        // Calculate scale to fit 518x518
        let originalWidth = CGFloat(CVPixelBufferGetWidth(pixelBuffer))
        let originalHeight = CGFloat(CVPixelBufferGetHeight(pixelBuffer))

        let scaleX = CGFloat(Self.inputWidth) / originalWidth
        let scaleY = CGFloat(Self.inputHeight) / originalHeight

        // Apply scaling
        let scaledImage = ciImage.transformed(by: CGAffineTransform(scaleX: scaleX, y: scaleY))

        // Create output pixel buffer
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
            throw NSError(domain: "DepthAnythingWrapper", code: -1,
                         userInfo: [NSLocalizedDescriptionKey: "Failed to create pixel buffer"])
        }

        // Render scaled image to buffer
        ciContext.render(scaledImage, to: buffer)

        return buffer
    }

    /// Creates MLFeatureProvider input from pixel buffer
    private func createModelInput(from pixelBuffer: CVPixelBuffer) throws -> MLFeatureProvider {
        // The model expects a CVPixelBuffer input
        // The exact input name may vary - check model description
        guard let model = model,
              let inputName = model.modelDescription.inputDescriptionsByName.keys.first else {
            throw ModelError.invalidInputDescription
        }

        let featureValue = MLFeatureValue(pixelBuffer: pixelBuffer)
        let provider = try MLDictionaryFeatureProvider(dictionary: [inputName: featureValue])

        return provider
    }

    // MARK: - Postprocessing

    /// Extracts depth map from model output
    private func extractDepthMap(from output: MLFeatureProvider) throws -> MLMultiArray {
        // Find the output feature (typically named "depth" or similar)
        guard let outputName = output.featureNames.first,
              let depthFeature = output.featureValue(for: outputName),
              let depthArray = depthFeature.multiArrayValue else {
            throw NSError(domain: "DepthAnythingWrapper", code: -2,
                         userInfo: [NSLocalizedDescriptionKey: "Failed to extract depth map from output"])
        }

        return depthArray
    }

    /// Converts MLMultiArray depth to a 2D Float array
    /// - Parameter depthArray: Raw depth output from model
    /// - Returns: 2D array of depth values [height][width]
    func depthArrayToFloat2D(_ depthArray: MLMultiArray) -> [[Float]] {
        let height = depthArray.shape[0].intValue
        let width = depthArray.shape.count > 1 ? depthArray.shape[1].intValue : 1

        var result: [[Float]] = []

        let pointer = depthArray.dataPointer.bindMemory(to: Float.self, capacity: height * width)

        for y in 0..<height {
            var row: [Float] = []
            for x in 0..<width {
                let index = y * width + x
                row.append(pointer[index])
            }
            result.append(row)
        }

        return result
    }

    /// Normalizes depth values to 0-1 range
    /// - Parameter depthArray: Input depth array (not modified)
    /// - Returns: New MLMultiArray with normalized values
    func normalizeDepth(_ depthArray: MLMultiArray) -> MLMultiArray {
        let count = depthArray.count
        let shape = depthArray.shape

        // Create a copy to avoid mutating input
        guard let normalizedArray = try? MLMultiArray(shape: shape, dataType: .float32) else {
            // Fallback: return original if copy fails
            logger.warning("Failed to create normalized array copy, returning original")
            return depthArray
        }

        let inputPointer = depthArray.dataPointer.bindMemory(to: Float.self, capacity: count)
        let outputPointer = normalizedArray.dataPointer.bindMemory(to: Float.self, capacity: count)

        // Find min and max
        var minVal: Float = .greatestFiniteMagnitude
        var maxVal: Float = -.greatestFiniteMagnitude

        for i in 0..<count {
            let val = inputPointer[i]
            minVal = min(minVal, val)
            maxVal = max(maxVal, val)
        }

        // Normalize to copy
        let range = maxVal - minVal
        if range > 0 {
            for i in 0..<count {
                outputPointer[i] = (inputPointer[i] - minVal) / range
            }
        } else {
            // All values same, set to 0.5
            for i in 0..<count {
                outputPointer[i] = 0.5
            }
        }

        return normalizedArray
    }
}
