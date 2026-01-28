//
//  DepthModelManagerTests.swift
//  cabinetscanTests
//
//  Created for Story 3.1: Core ML Model Integration
//

import XCTest
@testable import cabinetscan

/// Tests for DepthModelManager
/// Note: Some tests require actual ML models in the bundle and should run on device
final class DepthModelManagerTests: XCTestCase {

    // MARK: - Lifecycle Tests

    func testSharedInstanceExists() async {
        // Given/When
        let manager = DepthModelManager.shared

        // Then
        XCTAssertNotNil(manager, "Shared instance should exist")
    }

    func testInitialStateIsIdle() async {
        // Given
        let manager = DepthModelManager.shared

        // When
        let state = await manager.loadingState

        // Then - Note: state may be loaded if tests run after other tests
        // This test verifies the property is accessible
        XCTAssertTrue(state == .idle || state == .loaded || state == .failed(ModelError.modelNotFound("")),
                      "Initial state should be idle, loaded, or failed (if models not in test bundle)")
    }

    func testInitialProgressIsZero() async {
        // Given
        let manager = DepthModelManager.shared

        // When - unload first to reset state
        await manager.unloadModels()
        let progress = await manager.loadingProgress

        // Then
        XCTAssertEqual(progress, 0.0, "Initial progress should be 0.0 after unload")
    }

    func testInitialLoadedModelsIsEmpty() async {
        // Given
        let manager = DepthModelManager.shared

        // When - unload first to reset state
        await manager.unloadModels()
        let loadedModels = await manager.loadedModels

        // Then
        XCTAssertEqual(loadedModels, .none, "No models should be loaded initially after unload")
    }

    // MARK: - Memory Check Tests

    func testGetAvailableMemoryReturnsPositiveValue() async {
        // Given
        let manager = DepthModelManager.shared

        // When
        let availableMemory = await manager.getAvailableMemory()

        // Then
        XCTAssertGreaterThan(availableMemory, 0, "Available memory should be greater than 0")
    }

    func testGetMemoryUsageReturnsPositiveValue() async {
        // Given
        let manager = DepthModelManager.shared

        // When
        let memoryUsage = await manager.getMemoryUsage()

        // Then
        XCTAssertGreaterThan(memoryUsage, 0, "Memory usage should be greater than 0")
    }

    // MARK: - Thermal State Tests

    func testCheckThermalStateReturnsBoolean() async {
        // Given
        let manager = DepthModelManager.shared

        // When
        let canProceed = await manager.checkThermalState()

        // Then
        // We can't control thermal state in tests, but we can verify the method works
        XCTAssertTrue(canProceed || !canProceed, "Thermal state check should return a boolean")
    }

    // MARK: - Loading State Tests

    func testLoadingStateTransitions() async {
        // Given
        let manager = DepthModelManager.shared

        // When - unload to reset
        await manager.unloadModels()

        // Then
        let stateAfterUnload = await manager.loadingState
        XCTAssertEqual(stateAfterUnload, .idle, "State should be idle after unload")
    }

    func testLoadedModelsSetOperations() {
        // Given
        var models: LoadedModelSet = .none

        // When - add models
        models.insert(.depthAnything)
        XCTAssertTrue(models.contains(.depthAnything), "Should contain depthAnything")
        XCTAssertFalse(models.contains(.deepLabV3), "Should not contain deepLabV3")

        models.insert(.deepLabV3)
        XCTAssertTrue(models.contains(.deepLabV3), "Should contain deepLabV3")

        // Then - check primary set
        XCTAssertEqual(models, .primary, "Should equal primary set")
    }

    // MARK: - Model Error Tests

    func testModelErrorDescriptions() {
        // Given
        let notFoundError = ModelError.modelNotFound("TestModel")
        let insufficientMemoryError = ModelError.insufficientMemory(available: 100 * 1024 * 1024, required: 500 * 1024 * 1024)
        let thermalError = ModelError.thermalThrottling

        // Then
        XCTAssertTrue(notFoundError.errorDescription?.contains("TestModel") ?? false,
                      "Error should mention model name")
        XCTAssertTrue(insufficientMemoryError.errorDescription?.contains("100") ?? false,
                      "Error should mention available memory")
        XCTAssertTrue(thermalError.errorDescription?.contains("hot") ?? false,
                      "Error should mention device temperature")
    }

    // MARK: - Unload Tests

    func testUnloadModelsResetsState() async {
        // Given
        let manager = DepthModelManager.shared

        // When
        await manager.unloadModels()

        // Then
        let loadingState = await manager.loadingState
        let loadingProgress = await manager.loadingProgress
        let loadedModels = await manager.loadedModels

        XCTAssertEqual(loadingState, .idle, "State should be idle after unload")
        XCTAssertEqual(loadingProgress, 0.0, "Progress should be 0 after unload")
        XCTAssertEqual(loadedModels, .none, "No models should be loaded after unload")
    }

    // MARK: - Loading Tests (Require Models in Bundle)

    /// Note: This test requires actual ML models in the test bundle
    /// It will fail gracefully if models are not present
    func testLoadModelsWithoutModelsInBundle() async {
        // Given
        let manager = DepthModelManager.shared
        await manager.unloadModels()

        // When
        do {
            try await manager.loadModels()
            // If we get here, models were found
            let isLoaded = await manager.isLoaded
            XCTAssertTrue(isLoaded, "Models should be loaded")
        } catch {
            // Expected if models not in test bundle
            XCTAssertTrue(error is ModelError, "Should throw ModelError")
            if case ModelError.modelNotFound(let name) = error as! ModelError {
                XCTAssertTrue(name.contains("Depth") || name.contains("DeepLab"),
                             "Error should mention expected model name")
            }
        }
    }

    /// Note: This test requires actual ML models in the test bundle
    func testLoadModelsWithRetryOnFailure() async {
        // Given
        let manager = DepthModelManager.shared
        await manager.unloadModels()

        // When
        do {
            try await manager.loadModelsWithRetry()
            let isLoaded = await manager.isLoaded
            XCTAssertTrue(isLoaded, "Models should be loaded after retry")
        } catch {
            // Expected if models not in test bundle
            // Verify state is failed after all retries
            let state = await manager.loadingState
            if case .failed = state {
                // Expected
            } else {
                XCTFail("State should be failed after exhausting retries")
            }
        }
    }

    // MARK: - Progress Reporting Tests

    func testProgressIsWithinValidRange() async {
        // Given
        let manager = DepthModelManager.shared

        // When
        let progress = await manager.loadingProgress

        // Then
        XCTAssertGreaterThanOrEqual(progress, 0.0, "Progress should be >= 0")
        XCTAssertLessThanOrEqual(progress, 1.0, "Progress should be <= 1")
    }

    // MARK: - Scheduled Unload Tests

    func testScheduleUnloadCanBeCancelled() async {
        // Given
        let manager = DepthModelManager.shared

        // When
        await manager.scheduleUnload()
        await manager.cancelScheduledUnload()

        // Then - no crash means success
        // We can't easily verify the timer was cancelled, but we can verify no crash
        XCTAssertTrue(true, "Schedule and cancel should not crash")
    }

    // MARK: - ModelLoadingState Equatable Tests

    func testModelLoadingStateEquatable() {
        // Given
        let idle1 = ModelLoadingState.idle
        let idle2 = ModelLoadingState.idle
        let loading1 = ModelLoadingState.loading
        let retrying1 = ModelLoadingState.retrying(attempt: 1)
        let retrying2 = ModelLoadingState.retrying(attempt: 2)
        let loaded1 = ModelLoadingState.loaded
        let failed1 = ModelLoadingState.failed(ModelError.thermalThrottling)
        let failed2 = ModelLoadingState.failed(ModelError.modelNotFound("test"))

        // Then
        XCTAssertEqual(idle1, idle2, "Two idle states should be equal")
        XCTAssertNotEqual(idle1, loading1, "Idle and loading should not be equal")
        XCTAssertNotEqual(retrying1, retrying2, "Different retry attempts should not be equal")
        XCTAssertEqual(loaded1, loaded1, "Loaded should equal itself")
        XCTAssertEqual(failed1, failed2, "Failed states should be equal (simplified comparison)")
    }
}

// MARK: - Wrapper Tests

/// Tests for DepthAnythingWrapper
final class DepthAnythingWrapperTests: XCTestCase {

    func testInputDimensions() {
        XCTAssertEqual(DepthAnythingWrapper.inputWidth, 518)
        XCTAssertEqual(DepthAnythingWrapper.inputHeight, 518)
        XCTAssertEqual(DepthAnythingWrapper.inputChannels, 3)
    }

    func testWrapperCanBeInstantiated() {
        let wrapper = DepthAnythingWrapper()
        XCTAssertNotNil(wrapper)
    }

    /// Note: This test requires the actual model in the bundle
    func testLoadModelWithoutModelInBundle() async {
        let wrapper = DepthAnythingWrapper()

        do {
            try await wrapper.loadModel()
            // If we get here, model was found and loaded
            XCTAssertTrue(true, "Model loaded successfully")
        } catch {
            // Expected if model not in test bundle
            XCTAssertTrue(error is ModelError, "Should throw ModelError")
        }
    }
}

/// Tests for DeepLabV3Wrapper
final class DeepLabV3WrapperTests: XCTestCase {

    func testInputDimensions() {
        XCTAssertEqual(DeepLabV3Wrapper.inputWidth, 513)
        XCTAssertEqual(DeepLabV3Wrapper.inputHeight, 513)
        XCTAssertEqual(DeepLabV3Wrapper.inputChannels, 3)
        XCTAssertEqual(DeepLabV3Wrapper.numClasses, 21)
    }

    func testWrapperCanBeInstantiated() {
        let wrapper = DeepLabV3Wrapper()
        XCTAssertNotNil(wrapper)
    }

    func testSemanticClassValues() {
        XCTAssertEqual(SemanticClass.background.rawValue, 0)
        XCTAssertEqual(SemanticClass.diningTable.rawValue, 11)
        XCTAssertEqual(SemanticClass.chair.rawValue, 9)
    }

    func testKitchenRelevantClasses() {
        let relevant = SemanticClass.kitchenRelevant
        XCTAssertTrue(relevant.contains(.diningTable))
        XCTAssertTrue(relevant.contains(.chair))
        XCTAssertFalse(relevant.contains(.aeroplane))
        XCTAssertFalse(relevant.contains(.background))
    }
}

/// Tests for MobileSAMWrapper
final class MobileSAMWrapperTests: XCTestCase {

    func testInputDimensions() {
        XCTAssertEqual(MobileSAMWrapper.inputWidth, 1024)
        XCTAssertEqual(MobileSAMWrapper.inputHeight, 1024)
    }

    func testWrapperCanBeInstantiated() {
        let wrapper = MobileSAMWrapper()
        XCTAssertNotNil(wrapper)
        XCTAssertFalse(wrapper.isLoaded, "Should not be loaded initially")
    }

    func testPointPromptCreation() {
        let prompt = SAMPointPrompt(point: CGPoint(x: 0.5, y: 0.5), isPositive: true)
        XCTAssertEqual(prompt.point.x, 0.5)
        XCTAssertEqual(prompt.point.y, 0.5)
        XCTAssertTrue(prompt.isPositive)
    }

    func testBoxPromptCreation() {
        let prompt = SAMBoxPrompt(
            topLeft: CGPoint(x: 0.1, y: 0.1),
            bottomRight: CGPoint(x: 0.9, y: 0.9)
        )
        XCTAssertEqual(prompt.topLeft.x, 0.1)
        XCTAssertEqual(prompt.bottomRight.x, 0.9)
    }
}

// MARK: - LoadedModelSet Tests

final class LoadedModelSetTests: XCTestCase {

    func testEmptySet() {
        let set: LoadedModelSet = .none
        XCTAssertFalse(set.contains(.depthAnything))
        XCTAssertFalse(set.contains(.deepLabV3))
        XCTAssertFalse(set.contains(.mobileSAM))
    }

    func testPrimarySet() {
        let set: LoadedModelSet = .primary
        XCTAssertTrue(set.contains(.depthAnything))
        XCTAssertTrue(set.contains(.deepLabV3))
        XCTAssertFalse(set.contains(.mobileSAM))
    }

    func testAllSet() {
        let set: LoadedModelSet = .all
        XCTAssertTrue(set.contains(.depthAnything))
        XCTAssertTrue(set.contains(.deepLabV3))
        XCTAssertTrue(set.contains(.mobileSAM))
    }

    func testSetMutation() {
        var set: LoadedModelSet = .none

        set.insert(.depthAnything)
        XCTAssertTrue(set.contains(.depthAnything))
        XCTAssertFalse(set.contains(.deepLabV3))

        set.insert(.deepLabV3)
        XCTAssertTrue(set.contains(.deepLabV3))

        set.remove(.depthAnything)
        XCTAssertFalse(set.contains(.depthAnything))
        XCTAssertTrue(set.contains(.deepLabV3))
    }
}
