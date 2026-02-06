# Achieving +/-2 Inch Accuracy for Non-LiDAR Cabinet Scanning

## Executive Summary

**Target:** +/-2 inch (~5cm) accuracy for FULLY AUTOMATIC scanning on non-LiDAR devices.

**Bottom Line:** Achieving +/-2 inch accuracy with FULLY AUTOMATIC, ZERO USER INTERACTION scanning using only monocular depth estimation is **NOT ACHIEVABLE with current technology** (as of January 2026). The fundamental physics of monocular depth creates scale ambiguity that cannot be resolved without some form of reference.

**However,** +/-2 inch accuracy IS achievable with:
1. **Minimal user interaction** (placing a printed reference marker OR confirming a detected reference)
2. **Server-side processing** with multi-view stereo reconstruction
3. **Hybrid approaches** combining multiple techniques

This document provides a comprehensive analysis of all available options.

---

## Table of Contents

1. [Current Implementation Analysis](#1-current-implementation-analysis)
2. [State-of-the-Art Depth Estimation Models](#2-state-of-the-art-depth-estimation-models)
3. [Multi-View 3D Reconstruction](#3-multi-view-3d-reconstruction)
4. [Segmentation and Detection](#4-segmentation-and-detection)
5. [Scale Calibration Improvements](#5-scale-calibration-improvements)
6. [Sensor Fusion Strategies](#6-sensor-fusion-strategies)
7. [On-Device vs Server Trade-offs](#7-on-device-vs-server-trade-offs)
8. [Realistic Accuracy Expectations](#8-realistic-accuracy-expectations)
9. [Recommended Implementation Path](#9-recommended-implementation-path)

---

## 1. Current Implementation Analysis

### What We Have

| Component | Implementation | Issue |
|-----------|---------------|-------|
| Depth Model | DepthAnythingV2 Small (518x392) | **RELATIVE depth, not metric** |
| Depth Conversion | Linear mapping (0.5m - 6.0m) | Geometrically incorrect |
| Point Cloud | Metal GPU pipeline | Receives distorted depth |
| Scale Calibration | Floor/countertop detection | Fails on noisy mesh |
| Room Detection | RANSAC plane fitting | Finds noise patterns |

### The Fundamental Problem

DepthAnythingV2 outputs **relative/ordinal depth**:
- HIGH values = close objects
- LOW values = far objects
- But the **absolute distance is unknown**

The current linear conversion:
```swift
let metricDepth = 0.5 + adjustedDepth * 5.5  // Map to 0.5m - 6.0m
```

This is **geometrically wrong**. Monocular depth models output disparity-like values, which have an **inverse/hyperbolic** relationship to actual depth:
```
true_depth = 1.0 / (a * disparity + b)
```

Without knowing the calibration constants (a, b), we cannot recover true depth.

### Why Scale Calibration Fails

The ScaleCalibrator tries to find countertops at "36 inches" height. But:
1. The mesh geometry is distorted
2. Finding planes in noise produces more noise
3. The 25-50% height ratio heuristic is unreliable

---

## 2. State-of-the-Art Depth Estimation Models

### 2.1 Apple Depth Pro (October 2024)

**Paper:** [Depth Pro: Sharp Monocular Metric Depth in Less Than a Second](https://arxiv.org/abs/2410.02073)

**Key Claims:**
- Produces **metric depth with absolute scale**
- No camera intrinsics required
- 2.25-megapixel depth map in 0.3 seconds on GPU
- Best-in-class boundary accuracy (F1 score)

**Actual Performance:**
- Outperforms all existing monocular models in zero-shot metric accuracy
- Sharp edges (1-2 orders of magnitude better than previous SOTA)
- Works across indoor AND outdoor without domain-specific models

**Limitations:**
- Struggles with translucent/reflective surfaces
- Model size: ~300M+ parameters
- No official CoreML version yet (community conversion in progress)
- iPhone inference speed unknown (likely 1-3 seconds per frame)

**Accuracy:** Not specified in cm/inches, but "best average accuracy" on benchmarks.

**iPhone Deployment:** Challenging. Recommended to use DepthAnythingV2 for now.

---

### 2.2 Metric3D v2 (April 2024)

**Paper:** [Metric3D v2: A Versatile Monocular Geometric Foundation Model](https://arxiv.org/abs/2404.15506)

**Key Claims:**
- Zero-shot metric depth + surface normals
- Canonical camera space transformation (handles different cameras)
- Trained on 16M+ images from thousands of camera models

**Actual Performance:**
- Ranks #1 on KITTI and NYU benchmarks
- In wildlife benchmark: MAE of 0.454m (Depth Anything V2) vs 0.974 correlation (Metric3D)
- Processing time: ~0.56 seconds per image

**Accuracy:**
- Mean Absolute Error: ~0.32m to 0.66m in indoor environments
- This translates to **12-26 inches error** - NOT acceptable for our use case

**iPhone Deployment:** Not available. Would need custom CoreML conversion.

---

### 2.3 Depth Anything V2 (June 2024, NeurIPS 2024)

**Paper:** [Depth Anything V2](https://arxiv.org/abs/2406.09414)

**Current Status:** Already integrated (relative depth version)

**Metric Depth Version Available:**
- Fine-tuned on synthetic Hypersim (indoor) / Virtual KITTI (outdoor)
- Separate indoor and outdoor models
- Models available: Small, Base, Large

**Performance on Indoor Benchmarks:**
- ScanNet: AbsRel 0.135, delta1 0.822
- DA-2K: 95.3% accuracy (ViT-S), 97.1% (Large)

**Critical Issue:**
A 2024 study comparing Depth Anything V2 to LiDAR found:
- **Mean errors: 0.32m to 0.66m** (12-26 inches)
- For objects within 2m: 89.1% of errors within +/-0.5m (20 inches)
- For objects within 4m: 77.0% of errors within +/-0.5m
- For objects within 6m: 70.8% of errors within +/-0.5m

**Conclusion:** Even the metric-fine-tuned version cannot achieve +/-2 inch accuracy.

---

### 2.4 UniDepth (CVPR 2024)

**Paper:** [UniDepth: Universal Monocular Metric Depth Estimation](https://arxiv.org/abs/2403.18913)

**Key Innovation:**
- Self-promptable camera module (predicts camera intrinsics)
- Works without any camera information
- Pseudo-spherical output representation

**Performance:**
- Improves over Metric3D by 5.8% on NYU, 1.1% on KITTI
- If everything runs correctly: ARel ~7.45%

**iPhone Deployment:** Not available. PyTorch only.

---

### 2.5 ZoeDepth (2023)

**Paper:** [ZoeDepth: Zero-shot Transfer by Combining Relative and Metric Depth](https://arxiv.org/abs/2302.12288)

**Approach:**
- Combines MiDAS backbone with adaptive metric binning
- Automatic scene classification (indoor/outdoor routing)

**Performance:**
- 21% improvement in REL on NYU Depth v2
- Now superseded by UniDepth and Depth Anything

**Status:** Outdated - newer models are better.

---

### 2.6 Marigold (CVPR 2024 - Best Paper Candidate)

**Paper:** [Marigold: Repurposing Diffusion-Based Image Generators for Monocular Depth Estimation](https://arxiv.org/abs/2312.02145)

**Key Innovation:**
- Diffusion-based depth (from Stable Diffusion)
- Superior edge sharpness and structural consistency
- Fine-tuned with synthetic data only

**Performance:**
- **Excellent boundary accuracy** - best for detecting cabinet edges
- Works at 768x768 resolution (Stable Diffusion's sweet spot)

**Critical Limitation:**
- **RELATIVE DEPTH ONLY** - no metric scale
- Very slow: 5.2 seconds per image (vs 213ms for Depth Anything V2)
- Not suitable for real-time or metric applications

**Use Case:** Could be used for edge detection overlay, not 3D reconstruction.

---

### 2.7 Summary: Depth Model Accuracy

| Model | Type | Indoor MAE | iPhone Ready | Notes |
|-------|------|------------|--------------|-------|
| Depth Anything V2 (metric) | Metric | 0.32-0.66m (12-26") | Partial (mlmodel) | Best current option |
| Depth Pro | Metric | Unknown (claims SOTA) | No | Promising but not mobile-ready |
| Metric3D v2 | Metric | ~0.45m (18") | No | Good correlation, slow |
| UniDepth | Metric | ~7.45% ARel | No | Needs intrinsics |
| Marigold | Relative | N/A | No | Great edges, slow |
| ZoeDepth | Metric | Outdated | No | Superseded |

**Key Takeaway:** No monocular model achieves +/-2 inch accuracy automatically.

---

## 3. Multi-View 3D Reconstruction

### 3.1 DUSt3R (CVPR 2024)

**Paper:** [DUSt3R: Geometric 3D Vision Made Easy](https://arxiv.org/abs/2312.14132)

**What It Does:**
- Dense 3D reconstruction from arbitrary image collections
- No camera calibration or pose information required
- Outputs pointmaps (depth + poses) simultaneously

**Performance:**
- DTU benchmark: Chamfer distance 1.741mm (sub-millimeter!)
- 50% improvement over COLMAP on sparse inputs

**Critical Limitations:**
- **Regression-based** - lacks precision for fine measurements
- Not designed for high-resolution imagery
- Accuracy degrades with more images and geometric complexity
- **GPU server required** - cannot run on iPhone

---

### 3.2 MASt3R (ECCV 2024)

**Paper:** [MASt3R: Matching And Stereo 3D Reconstruction](https://www.ecva.net/papers/eccv_2024/papers_ECCV/papers/09080.pdf)

**Improvements over DUSt3R:**
- **Metric 3D reconstruction** (with scale)
- Dense local feature maps
- Handles thousands of images

**Performance:**
- Real-time SLAM at 15 FPS (MASt3R-SLAM)
- Works with mobile phone images
- More robust than DUSt3R

**Limitations:**
- Still requires GPU server
- 5-10 images minimum
- Indoor textureless surfaces remain challenging

**Potential Use:** Upload video to server, process with MASt3R, return results.

---

### 3.3 GLOMAP (ECCV 2024)

**Paper:** [Global Structure-from-Motion Revisited](https://arxiv.org/abs/2407.20219)

**What It Does:**
- Modern replacement for COLMAP
- 10-100x faster than COLMAP
- Same or better accuracy

**Performance:**
- ETH3D SLAM: 8% higher recall, 9-11 points higher AUC at 0.1m/0.5m
- ETH3D MVS (rig): Millimeter-accurate ground truth matched
- Successfully reconstructs all test scenes

**Use Case:** Server-side reconstruction pipeline.

---

### 3.4 Gaussian Splatting (3DGS)

**Mobile Status:**
- **MetalSplatter**: Swift/Metal library for iOS/macOS/visionOS rendering
- **Scaniverse**: On-device splat processing (subscription required)
- **KIRI Engine**: iOS app with Gaussian splatting ($17.99/month)
- **Polycam**: Gaussian splatting export

**Limitation:** These are for **RENDERING**, not measurement. The splat creation still needs server-side GPU processing for quality results.

**Apple Research (SHARP):**
- Single image to 3D Gaussians in <1 second
- Novel view synthesis, not measurement

---

### 3.5 Multi-View Stereo (MVS) - Best Accuracy

**IndoCAFE-Net (2024):**
- Specifically designed for indoor reconstruction
- **Accuracy: 4.70mm, Completeness: 5.20mm**
- This is sub-centimeter accuracy - meets our requirements!

**BUT:** This requires:
- Controlled capture setup
- Known camera intrinsics
- Server-side GPU processing
- Multiple registered images

---

## 4. Segmentation and Detection

### 4.1 SAM 2 (Meta, August 2024)

**Features:**
- Segment anything in images and videos
- Real-time (44 FPS)
- Object tracking across frames

**Mobile Status:**
- Not directly available for iOS
- MobileSAM and EfficientSAM are lighter variants
- YOLO11 is 860x faster than SAM2 for similar tasks

**Use Case:** Detect cabinet boundaries accurately for edge-based measurement.

---

### 4.2 Grounding DINO / YOLO-World

**Capabilities:**
- Open-vocabulary object detection
- "Find all cabinets" without training

**YOLO11 on iOS:**
- CoreML export: 85 FPS (from 21 FPS PyTorch)
- Real-time cabinet detection feasible

**Use Case:** Detect cabinet bounding boxes, then measure using reference objects.

---

### 4.3 Florence-2 (Microsoft)

**Capabilities:**
- Vision foundation model
- Multiple tasks: detection, segmentation, captioning
- Could identify "door", "countertop", etc.

**Mobile Status:** Not available for iOS.

---

## 5. Scale Calibration Improvements

This is the **most promising path** to achieving accuracy.

### 5.1 Automatic Reference Object Detection

| Object | Standard Size | Detectability | Reliability |
|--------|--------------|---------------|-------------|
| Interior door | 80" height, 30-36" width | High (YOLO) | Very High |
| Countertop | 36" height | Medium | High |
| Base cabinet | 34.5" height | Medium | High |
| Ceiling | 96-108" | Medium | Medium |
| Standard outlet | 4.5" x 2.75" | Low | Very High if visible |
| Light switch | 4.5" x 2.75" | Low | Very High if visible |
| Standard door knob height | 36" from floor | Medium | High |

### 5.2 Multi-Reference Validation

**Approach:**
1. Detect multiple reference objects automatically
2. Calculate scale from each independently
3. Cross-validate: if scales agree within tolerance, use average
4. If scales disagree, flag for user verification

**Implementation:**
```
detected_references = [
    (door_height, calculated_scale_1),
    (countertop_height, calculated_scale_2),
    (ceiling_height, calculated_scale_3)
]

scale_variance = variance([s for _, s in detected_references])

if scale_variance < threshold:
    final_scale = weighted_average(detected_references)
    confidence = HIGH
else:
    # Scales disagree - need user input
    show_calibration_prompt()
    confidence = MEDIUM
```

### 5.3 ArUco Marker Calibration (Most Accurate)

**If user is willing to place a marker:**
- Print a known-size ArUco marker (e.g., 10cm x 10cm)
- Place on countertop or floor
- Automatic detection provides **absolute scale**
- OpenCV ArUco detection works on iOS

**Accuracy:** Sub-centimeter possible with good marker visibility.

**Limitation:** Motion blur at >8 cm/s camera movement.

### 5.4 Hybrid Approach: AI Detection + User Confirmation

**Flow:**
1. AI detects "door" with bounding box
2. Show user: "Is this a standard door? (tap to confirm or adjust)"
3. If confirmed, use 80" height for scale
4. If not a door, prompt for ceiling height

**This is NOT fully automatic but requires only 1-2 taps.**

---

## 6. Sensor Fusion Strategies

### 6.1 ARKit Poses + AI Depth

**What we can combine:**
1. **ARKit camera poses** - very accurate (6DOF)
2. **ARKit plane detection** - floor, walls (approximate)
3. **AI monocular depth** - relative depth, good edges
4. **AI object detection** - cabinet boundaries

**Fusion Strategy:**
```
Final_Measurement = weighted_fusion(
    arkit_plane_measurement * 0.3,
    ai_depth_measurement * 0.3,
    reference_object_scale * 0.4
)

Confidence = agreement_score(all_methods)
```

### 6.2 Temporal Consistency (Video)

**Problem:** Per-frame depth is noisy and inconsistent.

**Solutions:**
- **Rolling Depth (CVPR 2025)**: Temporal consistency for video depth
- **DEVA / XMem**: Video object segmentation with tracking
- **MASt3R-SLAM**: Multi-view fusion with tracking

**Implementation:**
1. Track cabinet across frames
2. Aggregate depth estimates
3. Filter outliers
4. Use median or robust mean

### 6.3 Edge Detection for Cabinet Boundaries

**Best Models:**
- **DexiNed**: Dense extreme inception network for edges
- **EDTER**: Edge detection transformer
- **PidiNet**: Pixel difference networks

**Use Case:**
- Get precise cabinet edge pixels
- Use depth at edges (more reliable than interior)
- Fit geometric primitives to edges

---

## 7. On-Device vs Server Trade-offs

### 7.1 What Can Run on iPhone (A12+)

| Component | Model | Inference Time | Memory |
|-----------|-------|----------------|--------|
| Depth Estimation | DepthAnythingV2 Small | ~30-50ms | ~200MB |
| Object Detection | YOLO11n | ~12ms | ~50MB |
| Segmentation | MobileSAM | ~100-200ms | ~40MB |
| Edge Detection | PidiNet (tiny) | ~20ms | ~10MB |

**Total On-Device Pipeline:** ~200-400ms per frame, ~300MB RAM

### 7.2 What Needs Server (GPU)

| Component | Processing Time | Notes |
|-----------|-----------------|-------|
| Depth Pro | 0.3s per frame | A100 GPU |
| MASt3R | ~1-2s for 5-10 images | Full 3D reconstruction |
| GLOMAP | ~30-60s per scan | Structure from Motion |
| Marigold | 5.2s per frame | Diffusion-based |
| Gaussian Splatting | Minutes | For rendering |

### 7.3 Hybrid Architecture (Recommended)

```
┌─────────────────────────────────────────────────────────────┐
│                     ON-DEVICE (iPhone)                       │
├─────────────────────────────────────────────────────────────┤
│  ┌─────────────┐   ┌─────────────┐   ┌─────────────┐       │
│  │ ARKit Poses │   │ YOLO11      │   │ Depth       │       │
│  │ (6DOF)      │   │ (Cabinets)  │   │ Anything V2 │       │
│  └──────┬──────┘   └──────┬──────┘   └──────┬──────┘       │
│         │                 │                 │               │
│         └────────────┬────┴─────────────────┘               │
│                      ▼                                      │
│              ┌──────────────────┐                           │
│              │ Quick Estimate   │ → Show to user immediately│
│              │ (±6-12" accuracy)│                           │
│              └────────┬─────────┘                           │
│                       │                                     │
│         Upload video + poses + detections                   │
└─────────────────────────┬───────────────────────────────────┘
                          │
                          ▼
┌─────────────────────────────────────────────────────────────┐
│                     SERVER (GPU)                             │
├─────────────────────────────────────────────────────────────┤
│  ┌─────────────┐   ┌─────────────┐   ┌─────────────┐       │
│  │ MASt3R      │   │ Depth Pro   │   │ MVS         │       │
│  │ (3D Recon)  │   │ (Metric)    │   │ (Dense)     │       │
│  └──────┬──────┘   └──────┬──────┘   └──────┬──────┘       │
│         │                 │                 │               │
│         └────────────┬────┴─────────────────┘               │
│                      ▼                                      │
│              ┌──────────────────┐                           │
│              │ Refined Result   │ → Push to app             │
│              │ (±2-4" accuracy) │                           │
│              └──────────────────┘                           │
└─────────────────────────────────────────────────────────────┘
```

---

## 8. Realistic Accuracy Expectations

### 8.1 Accuracy by Approach

| Approach | Expected Accuracy | Achievable? | User Interaction |
|----------|------------------|-------------|------------------|
| **Fully Automatic (current)** | ±12-26" | YES (but unusable) | None |
| **Fully Automatic + Multi-ref** | ±6-12" | MAYBE | None |
| **ArUco Marker** | ±0.5-2" | YES | Place marker |
| **User Confirms Door** | ±2-4" | YES | 1-2 taps |
| **Server MVS** | ±0.5-2" | YES | Upload wait |
| **LiDAR (reference)** | ±0.5" | YES | None |

### 8.2 Why +/-2" is Hard Without Reference

The fundamental issue is **scale ambiguity**:

```
Scene A: Small room, camera 2m from wall
Scene B: Large room, camera 4m from wall

If monocular depth gives same relative depth map for both,
there is NO WAY to distinguish them without:
1. Known object size (door, person, marker)
2. Known camera intrinsics + baseline (stereo)
3. Physical measurement (LiDAR, time-of-flight)
```

No amount of AI improvement changes this physics limitation.

### 8.3 What Could Change (Future)

1. **Apple releases Depth Pro for CoreML** with sub-5cm accuracy claims
2. **MASt3R-Lite** for mobile devices
3. **iPhone 16+ with better depth sensors**
4. **Real-time MVS on Neural Engine** (unlikely soon)

---

## 9. Recommended Implementation Path

### Option A: "Nearly Automatic" (Recommended for +/-2-4")

**User Experience:**
1. User starts scan (video capture)
2. AI detects doors, countertops during scan
3. After scan: "We detected a door. Is this correct?" [Yes/Adjust]
4. If Yes: Use 80" height for scale
5. If No: "What's your ceiling height?" [8'/9'/10']
6. Show final measurements with confidence

**Implementation:**
1. Keep current video capture + ARKit poses
2. Add YOLO11 for door/countertop detection during capture
3. Keep Depth Anything V2 for relative depth
4. New multi-reference scale calibrator
5. Confidence scoring based on reference agreement

**Expected Accuracy:** +/-2-4" when door detected, +/-4-6" with ceiling only

---

### Option B: "Marker-Assisted" (Most Accurate)

**User Experience:**
1. User prints 10x10cm ArUco marker (QR-code-like)
2. Places marker on countertop or floor
3. Scans room normally
4. App automatically detects marker and calibrates

**Implementation:**
1. Add OpenCV ArUco detection
2. Calculate scale from marker
3. Apply to entire reconstruction

**Expected Accuracy:** +/-0.5-2"

---

### Option C: "Server-Enhanced" (Best Quality)

**User Experience:**
1. User scans room (video capture)
2. Quick on-device preview shown (+/-8-12")
3. "Uploading for enhanced processing..."
4. Push notification: "Your scan is ready" (2-5 minutes)
5. View refined results (+/-2-4")

**Implementation:**
1. Upload video + ARKit poses to server
2. Run MASt3R or GLOMAP + MVS
3. Return refined 3D model
4. Display in app

**Expected Accuracy:** +/-2-4" (potentially +/-1-2" with tuning)

---

### Comparison Matrix

| Option | Accuracy | User Effort | Processing Time | Development Effort |
|--------|----------|-------------|-----------------|-------------------|
| A: Nearly Automatic | +/-2-4" | 1-2 taps | Real-time | Medium |
| B: Marker-Assisted | +/-0.5-2" | Print + place marker | Real-time | Low |
| C: Server-Enhanced | +/-2-4" | Upload + wait | 2-5 minutes | High |

---

## 10. Conclusion

### The Hard Truth

**Achieving +/-2 inch accuracy with FULLY AUTOMATIC, ZERO USER INTERACTION scanning is NOT possible with current monocular depth technology.**

The best monocular models (Depth Anything V2 metric, Metric3D v2) achieve:
- Mean errors of 0.32-0.66m (12-26 inches)
- Only 70-89% of measurements within +/-0.5m (20 inches)

This is a **physics limitation**, not a software limitation. Without some reference for absolute scale, monocular vision cannot determine true distances.

### The Path Forward

To achieve +/-2 inch accuracy, choose ONE of:

1. **Minimal User Interaction** (Option A)
   - 1-2 tap confirmation of detected reference objects
   - No physical markers required
   - +/-2-4" accuracy achievable

2. **Physical Reference Marker** (Option B)
   - User prints and places a marker
   - Most accurate (+/-0.5-2")
   - Most friction

3. **Server Processing** (Option C)
   - Upload video for MVS reconstruction
   - +/-2-4" accuracy
   - Adds latency and server costs

### Recommendation

**Implement Option A first** with fallback to Option C:

1. Add YOLO11 door/countertop detection
2. Implement multi-reference scale calibration
3. Show user confirmation prompt (1 tap)
4. If confidence is low, offer server upload for enhanced processing

This provides the best balance of accuracy, user experience, and development effort.

---

## Sources

### Depth Estimation
- [Depth Pro - Apple ML Research](https://machinelearning.apple.com/research/depth-pro)
- [Depth Anything V2 - GitHub](https://github.com/DepthAnything/Depth-Anything-V2)
- [Metric3D v2 - arXiv](https://arxiv.org/abs/2404.15506)
- [UniDepth - CVPR 2024](https://openaccess.thecvf.com/content/CVPR2024/papers/Piccinelli_UniDepth_Universal_Monocular_Metric_Depth_Estimation_CVPR_2024_paper.pdf)
- [ZoeDepth - arXiv](https://arxiv.org/abs/2302.12288)
- [Marigold - GitHub](https://github.com/prs-eth/Marigold)
- [Survey on Monocular Metric Depth Estimation](https://www.mdpi.com/2073-431X/14/11/502)

### 3D Reconstruction
- [DUSt3R - arXiv](https://arxiv.org/abs/2312.14132)
- [MASt3R - Naver Labs](https://europe.naverlabs.com/blog/mast3r-matching-and-stereo-3d-reconstruction/)
- [GLOMAP - GitHub](https://github.com/colmap/glomap)
- [MetalSplatter - GitHub](https://github.com/scier/MetalSplatter)

### Segmentation and Detection
- [SAM 2 - Meta AI](https://ai.meta.com/sam2/)
- [Ultralytics YOLO11](https://docs.ultralytics.com/models/yolo11/)

### Benchmarks
- [Depth Anything V2 as LiDAR Alternative](https://www.matec-conferences.org/articles/matecconf/abs/2025/11/matecconf_rapdasa2025_04002/matecconf_rapdasa2025_04002.html)
- [IndoCAFE-Net Indoor MVS](https://www.sciencedirect.com/science/article/abs/pii/S0926580524003364)
- [CVPR 2024 Monocular Depth Estimation Challenge](https://openaccess.thecvf.com/content/CVPR2024W/MDEC/papers/Spencer_The_Third_Monocular_Depth_Estimation_Challenge_CVPRW_2024_paper.pdf)

### ARKit and iOS
- [ARKit sceneDepth Documentation](https://developer.apple.com/documentation/arkit/arframe/scenedepth)
- [Core ML Performance Benchmark](https://www.photoroom.com/inside-photoroom/core-ml-performance-benchmark-2023-edition)

---

*Document prepared: 2026-02-01*
*For: CabinetScan Non-LiDAR Accuracy Research*
