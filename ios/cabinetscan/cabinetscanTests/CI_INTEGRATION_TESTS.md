# CI Integration Test Documentation

## Story 6.10: Final Integration Testing - CI Configuration

This document describes the CI integration test configuration for the CabinetScan iOS app, specifically for the AI Flow feature integration tests.

## Test Suites Overview

### Story 6.10 Integration Test Suites

| Test Suite | Test Count | Purpose | Acceptance Criteria |
|------------|------------|---------|---------------------|
| LiDARFlowRegressionTests | 15 | Verify LiDAR flow has no regressions | AC1 |
| DownstreamIntegrationTests | 16 | Verify AI output integrates with downstream | AC2 |
| ArchitectureDeletionTests | 10 | Document ARCH-7 deletion procedure | AC3 |
| ArchitectureVerificationTests | 16 | Verify ARCH-1 through ARCH-7 | AC4 |
| EndToEndFlowTests | 12 | Full flow integration validation | AC1, AC2, AC3, AC4 |

**Total: 69 tests**

## CI Test Execution Commands

### Run All Integration Tests

```bash
cd ios/cabinetscan
xcodebuild test \
  -project cabinetscan.xcodeproj \
  -scheme cabinetscan \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:cabinetscanTests/LiDARFlowRegressionTests \
  -only-testing:cabinetscanTests/DownstreamIntegrationTests \
  -only-testing:cabinetscanTests/ArchitectureDeletionTests \
  -only-testing:cabinetscanTests/ArchitectureVerificationTests \
  -only-testing:cabinetscanTests/EndToEndFlowTests
```

### Run Individual Test Suites

**LiDAR Flow Regression (AC1):**
```bash
xcodebuild test \
  -project cabinetscan.xcodeproj \
  -scheme cabinetscan \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:cabinetscanTests/LiDARFlowRegressionTests
```

**Downstream Integration (AC2):**
```bash
xcodebuild test \
  -project cabinetscan.xcodeproj \
  -scheme cabinetscan \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:cabinetscanTests/DownstreamIntegrationTests
```

**Architecture Verification (AC3, AC4):**
```bash
xcodebuild test \
  -project cabinetscan.xcodeproj \
  -scheme cabinetscan \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:cabinetscanTests/ArchitectureDeletionTests \
  -only-testing:cabinetscanTests/ArchitectureVerificationTests
```

**End-to-End Flow (All ACs):**
```bash
xcodebuild test \
  -project cabinetscan.xcodeproj \
  -scheme cabinetscan \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:cabinetscanTests/EndToEndFlowTests
```

### Run All Tests (Full Test Suite)

```bash
xcodebuild test \
  -project cabinetscan.xcodeproj \
  -scheme cabinetscan \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```

## Test Result Interpretation

### Expected Results

All 69 tests should pass:
- `LiDARFlowRegressionTests`: 15/15 PASS
- `DownstreamIntegrationTests`: 16/16 PASS
- `ArchitectureDeletionTests`: 10/10 PASS
- `ArchitectureVerificationTests`: 16/16 PASS
- `EndToEndFlowTests`: 12/12 PASS

### Failure Analysis

| Test Suite | Failure Indicates |
|------------|-------------------|
| LiDARFlowRegressionTests | Regression in existing LiDAR scanning flow |
| DownstreamIntegrationTests | AI output incompatible with downstream screens |
| ArchitectureDeletionTests | Module isolation broken (ARCH-7 violation) |
| ArchitectureVerificationTests | Architecture principle violated (ARCH-1 to ARCH-7) |
| EndToEndFlowTests | Full flow integration issue |

## Performance Test Baselines

From Story 6.9 End-to-End Performance Validation:

| Metric | Target | Warning Threshold |
|--------|--------|-------------------|
| Total Pipeline Time | <15s | >12s |
| Peak Memory Usage | <1.5GB | >1.2GB |
| Model Loading | 500-1000ms | >2000ms |
| Depth Inference | 1500-2500ms | >5000ms |
| Point Cloud Generation | 800-1200ms | >2400ms |
| TSDF Fusion | 1500-2500ms | >5000ms |

Performance tests are covered by `EndToEndPerformanceValidationTests.swift` from Story 6.9.

## CI Pipeline Integration

### GitHub Actions Example

```yaml
name: iOS Integration Tests

on:
  push:
    branches: [develop, main]
  pull_request:
    branches: [main]

jobs:
  integration-tests:
    runs-on: macos-latest

    steps:
    - uses: actions/checkout@v4

    - name: Select Xcode
      run: sudo xcode-select -s /Applications/Xcode.app/Contents/Developer

    - name: Run Integration Tests
      run: |
        cd ios/cabinetscan
        xcodebuild test \
          -project cabinetscan.xcodeproj \
          -scheme cabinetscan \
          -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
          -only-testing:cabinetscanTests/LiDARFlowRegressionTests \
          -only-testing:cabinetscanTests/DownstreamIntegrationTests \
          -only-testing:cabinetscanTests/ArchitectureDeletionTests \
          -only-testing:cabinetscanTests/ArchitectureVerificationTests \
          -only-testing:cabinetscanTests/EndToEndFlowTests \
          -resultBundlePath TestResults.xcresult

    - name: Upload Test Results
      uses: actions/upload-artifact@v4
      if: always()
      with:
        name: test-results
        path: ios/cabinetscan/TestResults.xcresult
```

## Manual Testing Checklist (Physical Devices)

### LiDAR Device Testing

**Prerequisites:**
- iPhone 12 Pro or later with LiDAR
- Set `FlowRouter.forceAIFlow = false`

**Test Cases:**
- [ ] App launches successfully
- [ ] FlowRouter detects LiDAR (supportsLiDAR = true)
- [ ] ScanningView is displayed (not AI flow)
- [ ] RoomPlan scanning works correctly
- [ ] Video recording captures during scan
- [ ] Photo capture works after scan
- [ ] MeasurementData has scanMethod = .lidar
- [ ] Downstream flow works (Selection → Review → Submission)

### Non-LiDAR Device Testing

**Prerequisites:**
- iPhone without LiDAR (or iPhone with `forceAIFlow = true`)

**Test Cases:**
- [ ] App launches successfully
- [ ] FlowRouter routes to AI flow
- [ ] AIFlowEntryPoint is displayed
- [ ] Video capture works
- [ ] Photo capture works
- [ ] Processing completes successfully
- [ ] MeasurementData has scanMethod = .aiFlow
- [ ] Downstream flow works with AI data

## Test File Locations

```
ios/cabinetscan/cabinetscanTests/
├── LiDARFlowRegressionTests.swift      # AC1: LiDAR regression tests
├── DownstreamIntegrationTests.swift    # AC2: Downstream integration
├── ArchitectureDeletionTests.swift     # AC3: ARCH-7 deletion test
├── ArchitectureVerificationTests.swift # AC4: ARCH-1 to ARCH-7
├── EndToEndFlowTests.swift             # All ACs: Full flow tests
└── CI_INTEGRATION_TESTS.md             # This documentation
```

## Version History

| Date | Version | Changes |
|------|---------|---------|
| 2026-01-31 | 1.0 | Initial CI integration test configuration for Story 6.10 |
