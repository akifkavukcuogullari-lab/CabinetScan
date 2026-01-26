//
//  DeepLabV3Wrapper.swift
//  cabinetscan
//
//  Created for Story 3.1: Core ML Model Integration
//

import Foundation
import CoreML
import CoreVideo
import CoreImage
import os.log

/// Semantic segmentation classes from PASCAL VOC dataset (21 classes)
/// Note: DeepLabV3 trained on PASCAL VOC does NOT include kitchen-specific classes
/// like refrigerator, oven, sink, or cabinet. For kitchen detection, we use
/// proxy classes (diningTable for countertops, tvMonitor for appliances, etc.)
/// or combine with depth estimation for structure detection.
enum SemanticClass: Int, CaseIterable {
    case background = 0
    case aeroplane = 1
    case bicycle = 2
    case bird = 3
    case boat = 4
    case bottle = 5
    case bus = 6
    case car = 7
    case cat = 8
    case chair = 9
    case cow = 10
    case diningTable = 11
    case dog = 12
    case horse = 13
    case motorbike = 14
    case person = 15
    case pottedPlant = 16
    case sheep = 17
    case sofa = 18
    case train = 19
    case tvMonitor = 20

    /// PASCAL VOC classes that may appear in kitchen scenes (proxy detection)
    /// Note: These are NOT kitchen-specific classes - PASCAL VOC doesn't have
    /// refrigerator, oven, sink, or cabinet classes. We use these as proxies:
    /// - diningTable: May detect countertops/tables
    /// - chair: Kitchen seating areas
    /// - bottle: Objects on surfaces
    /// - pottedPlant: Decorative items
    /// - tvMonitor: May detect some appliance screens
    /// For actual appliance detection, use depth-based structure analysis.
    static let kitchenRelevant: Set<SemanticClass> = [
        .diningTable,
        .chair,
        .bottle,
        .pottedPlant,
        .tvMonitor
    ]

    var displayName: String {
        switch self {
        case .background: return "Background"
        case .aeroplane: return "Aeroplane"
        case .bicycle: return "Bicycle"
        case .bird: return "Bird"
        case .boat: return "Boat"
        case .bottle: return "Bottle"
        case .bus: return "Bus"
        case .car: return "Car"
        case .cat: return "Cat"
        case .chair: return "Chair"
        case .cow: return "Cow"
        case .diningTable: return "Dining Table"
        case .dog: return "Dog"
        case .horse: return "Horse"
        case .motorbike: return "Motorbike"
        case .person: return "Person"
        case .pottedPlant: return "Potted Plant"
        case .sheep: return "Sheep"
        case .sofa: return "Sofa"
        case .train: return "Train"
        case .tvMonitor: return "TV/Monitor"
        }
    }
}

/// Wrapper for DeepLabV3 Core ML model for semantic segmentation
final class DeepLabV3Wrapper {

    // MARK: - Constants

    /// Model input dimensions (513x513 RGB)
    static let inputWidth = 513
    static let inputHeight = 513
    static let inputChannels = 3

    /// Number of semantic classes
    static let numClasses = 21

    /// Model name in bundle
    private let modelName = "DeepLabV3"

    // MARK: - Properties

    private var model: MLModel?
    private let logger = Logger(subsystem: "com.cabinetscan", category: "DeepLabV3Wrapper")

    /// Shared CIContext for image processing (static to avoid creating multiple heavyweight instances)
    private static let sharedCIContext = CIContext(options: [.useSoftwareRenderer: false])
    private var ciContext: CIContext { Self.sharedCIContext }

    // MARK: - Loading

    /// Loads the DeepLabV3 model with optimal configuration
    func loadModel() async throws {
        logger.info("Loading \(self.modelName)...")

        // Find model in bundle - try multiple extensions
        guard let modelURL = Bundle.main.url(forResource: modelName, withExtension: "mlmodelc") ??
                            Bundle.main.url(forResource: modelName, withExtension: "mlpackage") ??
                            Bundle.main.url(forResource: modelName, withExtension: "mlmodel") else {
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

        // Validate input exists
        guard let inputDescription = model.modelDescription.inputDescriptionsByName.first?.value else {
            throw ModelError.invalidInputDescription
        }

        logger.debug("Model input: \(inputDescription.name), type: \(String(describing: inputDescription.type))")

        // Validate output exists
        guard let outputDescription = model.modelDescription.outputDescriptionsByName.first?.value else {
            throw ModelError.invalidInputDescription
        }

        logger.debug("Model output: \(outputDescription.name), type: \(String(describing: outputDescription.type))")
    }

    private func logComputeUnitInfo() {
        logger.info("Model configured with computeUnits: .all (Neural Engine + GPU + CPU)")
    }

    // MARK: - Inference

    /// Performs semantic segmentation on an input image
    /// - Parameter pixelBuffer: Input image as CVPixelBuffer (any size, will be resized)
    /// - Returns: Segmentation mask as MLMultiArray (513x513 class indices)
    func predict(image pixelBuffer: CVPixelBuffer) async throws -> MLMultiArray {
        guard let model = model else {
            throw ModelError.modelNotLoaded(modelName)
        }

        // Preprocess: resize to 513x513
        let preprocessedBuffer = try preprocessImage(pixelBuffer)

        // Create model input
        let input = try createModelInput(from: preprocessedBuffer)

        // Run inference
        let output = try await model.prediction(from: input)

        // Extract segmentation mask from output
        let segmentationMask = try extractSegmentationMask(from: output)

        return segmentationMask
    }

    // MARK: - Preprocessing

    /// Preprocesses the input image: resize to 513x513
    private func preprocessImage(_ pixelBuffer: CVPixelBuffer) throws -> CVPixelBuffer {
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)

        // Calculate scale to fit 513x513
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
            throw NSError(domain: "DeepLabV3Wrapper", code: -1,
                         userInfo: [NSLocalizedDescriptionKey: "Failed to create pixel buffer"])
        }

        // Render scaled image to buffer
        ciContext.render(scaledImage, to: buffer)

        return buffer
    }

    /// Creates MLFeatureProvider input from pixel buffer
    private func createModelInput(from pixelBuffer: CVPixelBuffer) throws -> MLFeatureProvider {
        guard let model = model,
              let inputName = model.modelDescription.inputDescriptionsByName.keys.first else {
            throw ModelError.invalidInputDescription
        }

        let featureValue = MLFeatureValue(pixelBuffer: pixelBuffer)
        let provider = try MLDictionaryFeatureProvider(dictionary: [inputName: featureValue])

        return provider
    }

    // MARK: - Postprocessing

    /// Extracts segmentation mask from model output
    private func extractSegmentationMask(from output: MLFeatureProvider) throws -> MLMultiArray {
        // Find the output feature
        guard let outputName = output.featureNames.first,
              let maskFeature = output.featureValue(for: outputName),
              let maskArray = maskFeature.multiArrayValue else {
            throw NSError(domain: "DeepLabV3Wrapper", code: -2,
                         userInfo: [NSLocalizedDescriptionKey: "Failed to extract segmentation mask from output"])
        }

        return maskArray
    }

    /// Converts MLMultiArray segmentation mask to a 2D array of class indices
    /// - Parameter maskArray: Raw segmentation output from model
    /// - Returns: 2D array of class indices [height][width]
    func maskToClassIndices(_ maskArray: MLMultiArray) -> [[Int]] {
        // Output shape depends on model variant
        // Could be [1, height, width] or [height, width, numClasses]

        let shape = maskArray.shape.map { $0.intValue }

        // Handle different output formats
        if shape.count == 3 && shape[0] == 1 {
            // Shape: [1, height, width] - class indices directly
            let height = shape[1]
            let width = shape[2]

            var result: [[Int]] = []
            let pointer = maskArray.dataPointer.bindMemory(to: Int32.self, capacity: height * width)

            for y in 0..<height {
                var row: [Int] = []
                for x in 0..<width {
                    let index = y * width + x
                    row.append(Int(pointer[index]))
                }
                result.append(row)
            }

            return result

        } else if shape.count == 3 {
            // Shape: [height, width, numClasses] - need argmax
            let height = shape[0]
            let width = shape[1]
            let numClasses = shape[2]

            var result: [[Int]] = []
            let pointer = maskArray.dataPointer.bindMemory(to: Float.self, capacity: height * width * numClasses)

            for y in 0..<height {
                var row: [Int] = []
                for x in 0..<width {
                    var maxClass = 0
                    var maxVal: Float = -.greatestFiniteMagnitude

                    for c in 0..<numClasses {
                        let index = (y * width + x) * numClasses + c
                        let val = pointer[index]
                        if val > maxVal {
                            maxVal = val
                            maxClass = c
                        }
                    }

                    row.append(maxClass)
                }
                result.append(row)
            }

            return result

        } else {
            // Fallback: assume [height, width]
            let height = shape[0]
            let width = shape.count > 1 ? shape[1] : 1

            var result: [[Int]] = []
            let pointer = maskArray.dataPointer.bindMemory(to: Int32.self, capacity: height * width)

            for y in 0..<height {
                var row: [Int] = []
                for x in 0..<width {
                    let index = y * width + x
                    row.append(Int(pointer[index]))
                }
                result.append(row)
            }

            return result
        }
    }

    /// Filters segmentation mask to only include kitchen-relevant classes
    /// - Parameter classIndices: 2D array of class indices
    /// - Returns: Binary mask where 1 = kitchen-relevant, 0 = other
    func filterKitchenRelevant(_ classIndices: [[Int]]) -> [[Int]] {
        let relevantRawValues = Set(SemanticClass.kitchenRelevant.map { $0.rawValue })

        return classIndices.map { row in
            row.map { classIndex in
                relevantRawValues.contains(classIndex) ? 1 : 0
            }
        }
    }
}
