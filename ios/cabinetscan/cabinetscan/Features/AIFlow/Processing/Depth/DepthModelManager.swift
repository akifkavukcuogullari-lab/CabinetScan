//
//  DepthModelManager.swift
//  cabinetscan
//
//  Created for Story 3.1: Core ML Model Integration
//

import Foundation
import CoreML
import Combine
import UIKit
import os.log

// MARK: - Model Loading State

/// Represents the current state of model loading
enum ModelLoadingState: Equatable {
    case idle
    case loading
    case retrying(attempt: Int)
    case loaded
    case failed(Error)

    static func == (lhs: ModelLoadingState, rhs: ModelLoadingState) -> Bool {
        switch (lhs, rhs) {
        case (.idle, .idle), (.loading, .loading), (.loaded, .loaded):
            return true
        case (.retrying(let a), .retrying(let b)):
            return a == b
        case (.failed, .failed):
            return true
        default:
            return false
        }
    }
}

// MARK: - Loaded Model Set

/// Tracks which models are currently loaded
struct LoadedModelSet: OptionSet {
    let rawValue: Int

    static let depthAnything = LoadedModelSet(rawValue: 1 << 0)
    static let deepLabV3 = LoadedModelSet(rawValue: 1 << 1)
    static let mobileSAM = LoadedModelSet(rawValue: 1 << 2)

    static let none: LoadedModelSet = []
    static let primary: LoadedModelSet = [.depthAnything, .deepLabV3]
    static let all: LoadedModelSet = [.depthAnything, .deepLabV3, .mobileSAM]
}

// MARK: - Model Errors

/// Errors that can occur during model operations
enum ModelError: LocalizedError {
    case modelNotFound(String)
    case loadingFailed(String, Error)
    case insufficientMemory(available: UInt64, required: UInt64)
    case thermalThrottling
    case invalidInputDescription
    case inputShapeMismatch(expected: [Int], actual: [Int])
    case outputShapeMismatch(expected: [Int], actual: [Int])
    case modelNotLoaded(String)

    var errorDescription: String? {
        switch self {
        case .modelNotFound(let name):
            return "Model '\(name)' not found in app bundle"
        case .loadingFailed(let name, let error):
            return "Failed to load model '\(name)': \(error.localizedDescription)"
        case .insufficientMemory(let available, let required):
            let availableMB = available / (1024 * 1024)
            let requiredMB = required / (1024 * 1024)
            return "Insufficient memory: \(availableMB)MB available, \(requiredMB)MB required"
        case .thermalThrottling:
            return "Device is too hot. Please let it cool down before scanning."
        case .invalidInputDescription:
            return "Model has invalid input description"
        case .inputShapeMismatch(let expected, let actual):
            return "Model input shape mismatch: expected \(expected), got \(actual)"
        case .outputShapeMismatch(let expected, let actual):
            return "Model output shape mismatch: expected \(expected), got \(actual)"
        case .modelNotLoaded(let name):
            return "Model '\(name)' is not loaded"
        }
    }
}

// MARK: - DepthModelManager Actor

/// Manages the lifecycle of Core ML models for depth estimation and segmentation.
/// Uses actor isolation to ensure thread-safe access to model state.
actor DepthModelManager {

    // MARK: - Singleton

    static let shared = DepthModelManager()

    // MARK: - Published State (via AsyncStream)

    private var _loadingProgress: Double = 0.0
    private var _loadingState: ModelLoadingState = .idle
    private var _loadedModels: LoadedModelSet = .none

    private let logger = Logger(subsystem: "com.cabinetscan", category: "DepthModelManager")

    // MARK: - Models

    private var depthAnythingWrapper: DepthAnythingWrapper?
    private var deepLabV3Wrapper: DeepLabV3Wrapper?
    private var mobileSAMWrapper: MobileSAMWrapper?

    // MARK: - Configuration

    private let requiredMemory: UInt64 = 500 * 1024 * 1024  // 500MB
    private let maxRetryAttempts = 3
    private let baseRetryDelay: UInt64 = 1_000_000_000  // 1 second in nanoseconds
    private let unloadDelay: TimeInterval = 30.0

    // MARK: - Timer Management

    private var unloadTask: Task<Void, Never>?
    private var notificationObservers: [NSObjectProtocol] = []

    // MARK: - Initialization

    private init() {
        setupNotificationObservers()
    }

    deinit {
        for observer in notificationObservers {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    // MARK: - Public State Accessors

    var loadingProgress: Double {
        _loadingProgress
    }

    var loadingState: ModelLoadingState {
        _loadingState
    }

    var loadedModels: LoadedModelSet {
        _loadedModels
    }

    var isLoaded: Bool {
        _loadingState == .loaded
    }

    // MARK: - Model Accessors

    func getDepthWrapper() throws -> DepthAnythingWrapper {
        guard let wrapper = depthAnythingWrapper else {
            throw ModelError.modelNotLoaded("DepthAnythingV2")
        }
        return wrapper
    }

    func getSegmentationWrapper() throws -> DeepLabV3Wrapper {
        guard let wrapper = deepLabV3Wrapper else {
            throw ModelError.modelNotLoaded("DeepLabV3")
        }
        return wrapper
    }

    func getMobileSAMWrapper() throws -> MobileSAMWrapper {
        guard let wrapper = mobileSAMWrapper else {
            throw ModelError.modelNotLoaded("MobileSAM")
        }
        return wrapper
    }

    // MARK: - Loading with Retry

    /// Loads models with automatic retry on failure
    func loadModelsWithRetry() async throws {
        var attempts = 0

        while attempts < maxRetryAttempts {
            do {
                _loadingState = attempts > 0 ? .retrying(attempt: attempts + 1) : .loading
                try await loadModels()
                return
            } catch {
                attempts += 1
                logger.error("Model loading attempt \(attempts) failed: \(error.localizedDescription)")

                if attempts >= maxRetryAttempts {
                    _loadingState = .failed(error)
                    throw error
                }

                // Exponential backoff: 1s, 2s, 4s
                let delay = baseRetryDelay * UInt64(1 << (attempts - 1))
                try await Task.sleep(nanoseconds: delay)
            }
        }
    }

    // MARK: - Core Loading

    /// Loads the primary models (DepthAnything and DeepLabV3) sequentially
    func loadModels() async throws {
        logger.info("Starting model loading...")

        // Cancel any pending unload
        cancelScheduledUnload()

        // Pre-flight checks
        try performPreflightChecks()

        _loadingState = .loading
        _loadingProgress = 0.0

        do {
            // Load DepthAnythingV2 first (largest, most critical)
            logger.info("Loading DepthAnythingV2...")
            depthAnythingWrapper = DepthAnythingWrapper()
            try await depthAnythingWrapper?.loadModel()
            _loadedModels.insert(.depthAnything)
            _loadingProgress = 0.5
            logger.info("DepthAnythingV2 loaded successfully")

            // Check for cancellation between loads
            try Task.checkCancellation()

            // Load DeepLabV3 second
            logger.info("Loading DeepLabV3...")
            deepLabV3Wrapper = DeepLabV3Wrapper()
            try await deepLabV3Wrapper?.loadModel()
            _loadedModels.insert(.deepLabV3)
            _loadingProgress = 1.0
            logger.info("DeepLabV3 loaded successfully")

            _loadingState = .loaded
            logger.info("All primary models loaded successfully")

            // Log memory usage
            logMemoryUsage()

        } catch {
            logger.error("Model loading failed: \(error.localizedDescription)")
            _loadingState = .failed(error)
            // Clean up partial loads
            await unloadModels()
            throw error
        }
    }

    /// Loads MobileSAM on demand (for edge refinement)
    func loadMobileSAMIfNeeded() async throws {
        guard mobileSAMWrapper == nil else { return }

        logger.info("Loading MobileSAM on demand...")
        mobileSAMWrapper = MobileSAMWrapper()
        try await mobileSAMWrapper?.loadModel()
        _loadedModels.insert(.mobileSAM)
        logger.info("MobileSAM loaded successfully")
    }

    // MARK: - Unloading

    /// Unloads all models and releases memory
    func unloadModels() {
        logger.info("Unloading all models...")

        depthAnythingWrapper = nil
        deepLabV3Wrapper = nil
        mobileSAMWrapper = nil

        _loadedModels = .none
        _loadingState = .idle
        _loadingProgress = 0.0

        logger.info("All models unloaded")
        logMemoryUsage()
    }

    /// Schedules model unloading after a delay
    func scheduleUnload() {
        cancelScheduledUnload()

        unloadTask = Task {
            do {
                try await Task.sleep(nanoseconds: UInt64(unloadDelay * 1_000_000_000))
                await unloadModels()
            } catch {
                // Task was cancelled, do nothing
            }
        }

        logger.info("Scheduled model unload in \(self.unloadDelay) seconds")
    }

    /// Cancels any scheduled unload
    func cancelScheduledUnload() {
        unloadTask?.cancel()
        unloadTask = nil
    }

    // MARK: - Pre-flight Checks

    private func performPreflightChecks() throws {
        // Check available memory
        let availableMemory = getAvailableMemory()
        if availableMemory < requiredMemory {
            throw ModelError.insufficientMemory(available: availableMemory, required: requiredMemory)
        }
        logger.info("Memory check passed: \(availableMemory / (1024 * 1024))MB available")

        // Check thermal state
        if !checkThermalState() {
            throw ModelError.thermalThrottling
        }
        logger.info("Thermal state check passed")
    }

    // MARK: - Memory Management

    /// Returns available memory in bytes
    func getAvailableMemory() -> UInt64 {
        var pageSize: vm_size_t = 0
        host_page_size(mach_host_self(), &pageSize)

        var vmStats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)

        let result = withUnsafeMutablePointer(to: &vmStats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }

        guard result == KERN_SUCCESS else { return 0 }
        return UInt64(vmStats.free_count + vmStats.inactive_count) * UInt64(pageSize)
    }

    /// Returns current memory usage in bytes
    func getMemoryUsage() -> UInt64 {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size / 4)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        return result == KERN_SUCCESS ? info.resident_size : 0
    }

    private func logMemoryUsage() {
        let usage = getMemoryUsage()
        let usageMB = usage / (1024 * 1024)
        logger.info("Current memory usage: \(usageMB)MB")
    }

    // MARK: - Thermal State

    /// Checks if device thermal state allows Neural Engine usage
    func checkThermalState() -> Bool {
        let state = ProcessInfo.processInfo.thermalState
        if state == .critical {
            logger.warning("Device in critical thermal state - Neural Engine may be unavailable")
            return false
        }
        return true
    }

    // MARK: - Notification Observers

    private func setupNotificationObservers() {
        // Memory warning observer
        let memoryObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task {
                await self?.handleMemoryWarning()
            }
        }
        notificationObservers.append(memoryObserver)

        // Background observer
        let backgroundObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didEnterBackgroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task {
                await self?.handleAppBackground()
            }
        }
        notificationObservers.append(backgroundObserver)

        // Thermal state observer
        let thermalObserver = NotificationCenter.default.addObserver(
            forName: ProcessInfo.thermalStateDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task {
                await self?.handleThermalStateChange()
            }
        }
        notificationObservers.append(thermalObserver)
    }

    private func handleMemoryWarning() {
        logger.warning("Memory warning received - forcing model unload")
        cancelScheduledUnload()
        unloadModels()
    }

    private func handleAppBackground() {
        logger.info("App entering background - unloading models")
        cancelScheduledUnload()
        unloadModels()
    }

    private func handleThermalStateChange() {
        let state = ProcessInfo.processInfo.thermalState
        switch state {
        case .nominal:
            logger.info("Thermal state: nominal")
        case .fair:
            logger.info("Thermal state: fair")
        case .serious:
            logger.warning("Thermal state: serious - performance may be reduced")
        case .critical:
            logger.error("Thermal state: critical - Neural Engine likely unavailable")
        @unknown default:
            logger.info("Thermal state: unknown")
        }
    }
}
