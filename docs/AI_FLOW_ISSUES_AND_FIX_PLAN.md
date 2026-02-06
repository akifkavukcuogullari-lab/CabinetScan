# AI Flow Pipeline Issues and Fix Plan

## Document Purpose
This document provides a comprehensive analysis of the AI flow pipeline issues discovered during floor plan creation and the planned fixes. Use this as context for implementing the solutions.

**Last Updated:** 2026-02-01

---

## Executive Summary

The AI Flow pipeline has **fundamental architectural issues** that prevent accurate room reconstruction:

| Issue | Severity | Status | User Impact |
|-------|----------|--------|-------------|
| Video Recording Truncation | 🔴 CRITICAL | ✅ FIXED | 1-minute scan recorded as 0.17 seconds |
| Missing Database Storage | 🔴 CRITICAL | ✅ FIXED | Video/photos not visible in dashboard |
| Cabinet Validation Crash | 🟠 HIGH | ✅ FIXED | App crashes with empty cabinet arrays |
| **Depth Estimation Architecture** | 🔴 CRITICAL | ❌ UNFIXABLE | Chaotic floor plans (10 walls instead of 2) |

### Current Output Quality
Based on testing (2026-02-01):
- **Expected:** 2 walls, 1 window, ~4-6 cabinets
- **Actual:** 10 walls, 0 windows, 15 lower cabinets, 5 upper cabinets
- **Floor plan:** Chaotic, unrecognizable shape (see screenshot below)

```
LAYERS               COUNT
─────────────────────────
WALLS                  10   ← Should be 2-4
CABINETS LOWER         15   ← Way too many
CABINETS UPPER          5
CABINETS WALL_OVEN      0
CABINETS PANTRY         0
APPLIANCES              0
DOORS                   0
WINDOWS                 0   ← Should be 1
```

---

## Critical Issue: Monocular Depth Estimation Limitations

### The Fundamental Problem

**DepthAnythingV2 outputs RELATIVE depth, not METRIC depth.**

| What Model Outputs | What 3D Reconstruction Needs |
|--------------------|------------------------------|
| Relative ordering ("A closer than B") | Absolute distance ("A is 2.3m away") |
| Normalized 0-1 values | Metric depth in meters |
| Per-frame independent estimates | Consistent scale across frames |
| Smooth gradients | Sharp depth discontinuities at edges |

### Why This Breaks Everything

```
Pipeline Flow:

Frame 1 ──→ DepthAnythingV2 ──→ Normalized depth (0-1)
                                     │
                                     ▼
                              Linear conversion (0.5m - 6.0m)
                                     │
                                     ▼
                              Point Cloud (DISTORTED GEOMETRY)
                                     │
Frame 2 ──→ Same process ──→ Point Cloud (DIFFERENTLY DISTORTED)
                                     │
                                     ▼
                              TSDF Fusion ──→ Chaotic Mesh
                                     │
                                     ▼
                    ┌────────────────┴────────────────┐
                    ▼                                 ▼
            RoomDetector                      CabinetDetector
            (finds noise patterns)            (finds noise patterns)
                    │                                 │
                    ▼                                 ▼
              10 "walls"                       15 "cabinets"
```

### Technical Deep Dive

#### 1. Depth Model Output Characteristics

DepthAnythingV2 is trained for:
- **Ordinal depth ranking** - knows A is closer than B
- **Monocular cues** - texture gradients, perspective, occlusion
- **NOT trained for** - absolute metric depth

The model outputs **disparity-like** values:
```
High value (0.9-1.0) = CLOSE objects
Low value (0.0-0.1) = FAR objects
```

#### 2. Current Conversion (Linear - WRONG)

**File:** `PointCloudGenerator.swift`, `PointCloudMetalPipeline.swift`

```swift
// Current approach (linear mapping)
let adjustedDepth = 1.0 - normalizedDepth  // Invert (high=close → low=close)
let metricDepth = 0.5 + adjustedDepth * 5.5  // Map to 0.5m - 6.0m

// Problem: Linear mapping preserves relative order but DISTORTS geometry
// A wall 3m away and a wall 4m away might become 2m and 5m
```

#### 3. Correct Conversion (Disparity-based)

True disparity-to-depth relationship is **inverse/hyperbolic**:
```
metric_depth = 1.0 / (a * disparity + b)

where:
- a, b are calibration constants
- disparity = model output
- This is non-linear!
```

**BUT:** We don't have the calibration constants for DepthAnythingV2.

#### 4. Scale Calibration Failure

**File:** `ScaleCalibrator.swift`

The scale calibrator tries to find:
1. Floor plane (RANSAC on lowest points)
2. Countertop surface (horizontal plane at ~36")
3. Scale factor = 36" / countertop_height_in_mesh_units

**Problem:** If the mesh geometry is garbage, finding planes is finding noise patterns.

#### 5. Room Detection Cascade Failure

**File:** `RoomDetector.swift`

```swift
// RANSAC wall detection (line 356-416)
// Tries to find vertical planes in point cloud
// With noisy point cloud, finds noise patterns as "walls"

private static let ransacIterations: Int = 100
private static let ransacThreshold: Float = 0.5  // inches
private static let minWallPoints: Int = 20

// With thousands of noisy points, RANSAC easily finds
// 20+ points that fit a plane by chance
```

---

## Alternative Approaches to Consider

### Option A: Use ARKit Depth (Recommended for Non-LiDAR)

**Pros:**
- ARKit provides depth estimation on non-LiDAR devices via motion/stereo
- Integrated with pose tracking (no synchronization issues)
- Apple-maintained, hardware-optimized

**Cons:**
- Lower resolution than LiDAR
- Less accurate than LiDAR
- May not work well in all lighting conditions

**Implementation:**
```swift
// ARKit configuration for depth without LiDAR
let config = ARWorldTrackingConfiguration()
config.frameSemantics = [.sceneDepth]  // Requires A12+ chip

// Access depth in frame update
func session(_ session: ARSession, didUpdate frame: ARFrame) {
    if let depthMap = frame.sceneDepth?.depthMap {
        // This is METRIC depth in meters!
        // No conversion needed
    }
}
```

**Devices Supported:**
- iPhone XS and later (A12 chip+)
- Not all devices support `.sceneDepth` without LiDAR
- Need runtime capability check

### Option B: Skip 3D Reconstruction, Use 2D Detection Only

**Concept:** Don't try to reconstruct 3D geometry. Instead:
1. Take photos from specific angles
2. Run YOLO/object detection for cabinets
3. Use reference objects for scale (door = 80", countertop = 36")
4. Generate simplified floor plan from 2D detections

**Pros:**
- Avoids all depth estimation issues
- Faster processing
- More reliable object detection
- Works on any device

**Cons:**
- Less accurate measurements
- Requires user to take specific photos
- Can't generate true 3D model

**Implementation Concept:**
```
User Flow:
1. "Stand at doorway, take photo of full room"
2. "Walk to opposite wall, take photo back"
3. "Take close-up of each cabinet run"

Processing:
1. Detect cabinets in each photo (YOLO)
2. Detect reference objects (doors, countertops)
3. Use photogrammetry for rough dimensions
4. Generate 2D floor plan layout
```

### Option C: Hybrid Approach - ARKit Poses + AI Depth Refinement

**Concept:**
1. Use ARKit for camera poses (reliable)
2. Use ARKit's basic depth (if available) as foundation
3. Use DepthAnythingV2 only for edge refinement, not geometry
4. Heavy filtering to reject inconsistent depths

**Pros:**
- Better than pure AI depth
- Still works on devices without full ARKit depth

**Cons:**
- Complex implementation
- Still limited accuracy

### Option D: Guided Scanning with Known References

**Concept:**
1. User places reference marker (printed card with known size)
2. Scan includes the reference marker
3. Use marker for absolute scale calibration
4. Proceed with current pipeline but with calibrated scale

**Pros:**
- Solves scale ambiguity
- Works with current architecture
- Cheap to implement

**Cons:**
- Requires physical marker
- User friction (extra step)
- Marker must be visible in scan

### Option E: Server-Side Processing with Better Models

**Concept:**
1. Upload video/photos to server
2. Use more powerful depth models (Metric3D, UniDepth)
3. Use Structure from Motion (COLMAP, etc.)
4. Return processed floor plan

**Pros:**
- Can use state-of-the-art models
- No device limitations
- Can use GPU clusters

**Cons:**
- Requires server infrastructure
- Upload time for large videos
- Privacy concerns (uploading home videos)
- Ongoing compute costs

---

## Business Decision Matrix

| Approach | Accuracy | Dev Effort | User Experience | Device Support |
|----------|----------|------------|-----------------|----------------|
| **Current (broken)** | ❌ Unusable | Done | Poor (chaotic results) | All |
| **A: ARKit Depth** | ⭐⭐⭐ Good | Medium | Good | iPhone XS+ |
| **B: 2D Detection Only** | ⭐⭐ Fair | High | Different UX | All |
| **C: Hybrid** | ⭐⭐⭐ Good | High | Good | All |
| **D: Reference Marker** | ⭐⭐⭐ Good | Low | Extra step | All |
| **E: Server Processing** | ⭐⭐⭐⭐ Best | Very High | Slow (upload) | All |

### Recommended Path Forward

**For MVP/Quick Fix:**
1. ✅ Keep video/photo fixes (already done)
2. ✅ Keep cabinet crash fix (already done)
3. **Disable AI flow 3D reconstruction** - show honest "Processing..." then fail gracefully
4. **Fallback to manual measurement input** - user enters dimensions

**For Proper Solution (requires research):**
1. Investigate ARKit `.sceneDepth` on non-LiDAR devices
2. If ARKit depth works, integrate it
3. If not, consider Option B (2D detection approach)

---

## Already Fixed Issues (Reference)

### Issue 1: Video Recording Truncation ✅ FIXED

**Root Cause:** Dual video outputs competing for resources + race condition in delegate callback

**Fix Applied:**
- Disabled `videoDataOutput` during recording
- Fixed race condition by setting continuation BEFORE dispatch
- Added video configuration (maxDuration, minDiskSpace)
- Added file size validation

**File:** `AIVideoCapture.swift`

### Issue 2: Missing Database Storage ✅ FIXED

**Root Cause:** AI flow used local file URLs instead of uploading to Supabase

**Fix Applied:**
- Created `AIFlowUploader.swift` for Supabase uploads
- Updated `AIFlowCoordinator.swift` to upload before submission
- Updated `AIMeasurementDataBuilder.swift` to accept uploaded URLs

### Issue 3: Cabinet Validation Crash ✅ FIXED

**Root Cause:** Loop created invalid range when cabinet count is 0

**Fix Applied:**
- Added guards for `count >= 2` before loops

**File:** `CabinetDetector.swift` lines 888-910

---

## Technical Reference

### Current AI Flow Pipeline Architecture

```
┌─────────────────────────────────────────────────────────────────────┐
│                         AI FLOW PIPELINE                             │
├─────────────────────────────────────────────────────────────────────┤
│                                                                      │
│  ┌──────────────┐    ┌──────────────┐    ┌──────────────┐          │
│  │ AIVideoCapture│───▶│FrameExtractor│───▶│DepthAnything │          │
│  │   (record)    │    │ (30fps→2fps) │    │   V2 Model   │          │
│  └──────────────┘    └──────────────┘    └──────────────┘          │
│         │                                        │                   │
│         │                                        ▼                   │
│         │                              ┌──────────────────┐         │
│         │                              │ PointCloudGenerator│        │
│         │                              │ (depth → 3D points)│        │
│         │                              └──────────────────┘         │
│         │                                        │                   │
│         │                                        ▼                   │
│         │                              ┌──────────────────┐         │
│         │                              │  TSDF Fusion     │         │
│         │                              │ (points → mesh)  │         │
│         │                              └──────────────────┘         │
│         │                                        │                   │
│         │                                        ▼                   │
│         │                              ┌──────────────────┐         │
│         │                              │ ScaleCalibrator  │         │
│         │                              │ (find countertop)│         │
│         │                              └──────────────────┘         │
│         │                                        │                   │
│         │                     ┌──────────────────┼──────────────┐   │
│         │                     ▼                  ▼              ▼   │
│         │            ┌─────────────┐    ┌─────────────┐  ┌─────────┐│
│         │            │RoomDetector │    │CabinetDetect│  │WindowDet││
│         │            │(find walls) │    │(find cabinets│  │(windows)││
│         │            └─────────────┘    └─────────────┘  └─────────┘│
│         │                     │                  │              │   │
│         │                     └──────────────────┼──────────────┘   │
│         │                                        ▼                   │
│         │                              ┌──────────────────┐         │
│         │                              │2DFloorPlanRenderer│         │
│         │                              │ (generate image) │         │
│         │                              └──────────────────┘         │
│         │                                        │                   │
│         ▼                                        ▼                   │
│  ┌──────────────┐                      ┌──────────────────┐         │
│  │AIFlowUploader│                      │MeasurementData   │         │
│  │(→ Supabase)  │                      │   Builder        │         │
│  └──────────────┘                      └──────────────────┘         │
│         │                                        │                   │
│         └────────────────────┬───────────────────┘                  │
│                              ▼                                       │
│                    ┌──────────────────┐                             │
│                    │  Submit Project  │                             │
│                    │  (to dashboard)  │                             │
│                    └──────────────────┘                             │
│                                                                      │
└─────────────────────────────────────────────────────────────────────┘

PROBLEM AREA: DepthAnythingV2 → PointCloudGenerator
              The depth values are RELATIVE, not METRIC
              All downstream processing fails because of this
```

### Key Files

| File | Purpose | Status |
|------|---------|--------|
| `AIVideoCapture.swift` | Video recording | ✅ Fixed |
| `DepthEstimator.swift` | Coordinates depth estimation | Working |
| `DepthAnythingWrapper.swift` | ML model inference | Working |
| `PointCloudGenerator.swift` | Depth → 3D points | ❌ Broken (scale) |
| `PointCloudMetalPipeline.swift` | GPU point cloud | ❌ Broken (scale) |
| `TSDFMetalPipeline.swift` | Point cloud fusion | Receives bad data |
| `ScaleCalibrator.swift` | Scale detection | Fails on bad mesh |
| `RoomDetector.swift` | Wall detection | Finds noise |
| `CabinetDetector.swift` | Cabinet detection | ✅ Crash fixed, still noisy |
| `AIFlowUploader.swift` | Upload to Supabase | ✅ Created |
| `AIMeasurementDataBuilder.swift` | Build submission | ✅ Fixed |

### DepthAnythingV2 Model Details

```
Model: depth_anything_v2_vits_518x392.mlpackage
Input: 518 x 392 RGB image
Output: 518 x 392 depth map (Float32)
Output Range: 0.0 - 1.0 (normalized, relative depth)
Inference Time: ~30-40ms on iPhone 12

Note: Model outputs RELATIVE depth (ordinal ranking)
      NOT metric depth (actual distances)
```

---

## Next Steps

### Immediate (This Week)
1. [ ] Discuss business direction with stakeholders
2. [ ] Decide: Fix AI flow properly OR pivot to alternative approach
3. [ ] If pivot: Design new user flow for Option B (2D detection)

### Short-term (If Fixing AI Flow)
1. [ ] Research ARKit `.sceneDepth` on non-LiDAR devices
2. [ ] Test ARKit depth quality on iPhone XS/11/12 (non-Pro)
3. [ ] If viable, implement ARKit depth integration
4. [ ] If not viable, implement reference marker approach

### Long-term
1. [ ] Consider server-side processing for best accuracy
2. [ ] Evaluate trade-offs: accuracy vs. privacy vs. cost

---

## Appendix: Testing Results

### Test Environment
- **Device:** iPhone (non-LiDAR)
- **Room:** Kitchen with 2 walls visible, 1 window
- **Scan Duration:** ~1 minute
- **Scan Pattern:** 45-60° angles, full coverage

### Results (2026-02-01)
| Metric | Expected | Actual | Status |
|--------|----------|--------|--------|
| Walls detected | 2-4 | 10 | ❌ |
| Windows detected | 1 | 0 | ❌ |
| Lower cabinets | 4-6 | 15 | ❌ |
| Upper cabinets | 2-4 | 5 | ❌ |
| Floor plan shape | Rectangular | Chaotic | ❌ |
| Video recording | Working | Working | ✅ |
| Photo upload | Working | Working | ✅ |

---

## References

- DepthAnythingV2 Paper: https://arxiv.org/abs/2406.09414
- ARKit Documentation: https://developer.apple.com/documentation/arkit
- LiDAR upload implementation: `ScanningView.swift` lines 584-755
- Backend handler: `supabase/functions/submit-project/index.ts`
