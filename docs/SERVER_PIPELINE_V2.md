# Kitchen Capture Pipeline V2 — Revised Server Architecture

## Overview

This document supersedes `SERVER_PIPELINE_DESIGN.md` with updated model choices, simplified architecture, and cost-optimized infrastructure based on state-of-the-art tools available as of February 2026.

### What Changed from V1

| Area | V1 Design | V2 Design | Why |
|------|-----------|-----------|-----|
| **Depth** | Depth Pro (per-frame) | Video Depth Anything (metric, temporal) | Temporally consistent depth across entire scan; eliminates per-frame scale drift |
| **Detection** | Grounding DINO + SAM 2 (two-step) | SAM 3 text-prompted segmentation | One model replaces two; finds AND segments by text prompt |
| **3D Recon** | MASt3R-SfM (skipped for 2.5D) | Fast3R (optional, if needed later) | 1000+ frames in single forward pass; 10-100x faster than MASt3R |
| **Validation** | None | VLM sanity check (GPT-4o / Gemini) | Catches gross errors before user sees results |
| **Compute** | Fixed GPU server (~$600/mo) | RunPod / Modal serverless (~$20-30/mo) | Pay-per-scan; 1-2s cold starts |
| **Depth boost** | N/A | Prompt Depth Anything (optional) | Uses sparse iOS 18 Vision depth as guidance for 4K metric depth |

### Technology Stack

| Component | Technology | Why |
|-----------|------------|-----|
| **Depth Estimation** | Video Depth Anything (metric) | Temporal consistency, metric output, streaming mode, 30 FPS |
| **Depth Boost (optional)** | Prompt Depth Anything | 4K metric depth guided by sparse ARKit/Vision depth hints |
| **Object Detection + Segmentation** | SAM 3 (Promptable Concept Segmentation) | Text-prompted instance segmentation; no bounding box step needed |
| **Measurement** | Snap-to-Standards | Matches raw measurements to industry standard cabinet sizes |
| **Validation** | GPT-4o / Gemini 3 spatial reasoning | Sanity-check floor plan before delivery |
| **Compute** | RunPod Serverless (prod) / Modal (dev) | Pay-per-scan, sub-2s cold starts, ~$0.02/scan |

### Expected Accuracy

| Measurement | V1 Estimate | V2 Estimate | Improvement Source |
|-------------|-------------|-------------|-------------------|
| Wall lengths (ARKit planes) | +/-2-3" | +/-2-3" | Same (ARKit is already reliable) |
| Cabinet widths (same plane) | +/-1-2" | +/-0.5-1" | Temporally consistent depth removes jitter |
| Appliance widths | +/-1" | +/-0.5" | SAM 3 masks are more precise than SAM 2 |
| After snapping | Exact SKU match | Exact SKU match | Same |
| Gross error rate | Unknown | <5% | VLM validation catches obvious failures |

---

## Table of Contents

1. [Architecture Overview](#1-architecture-overview)
2. [Model Stack Deep Dive](#2-model-stack-deep-dive)
3. [Pipeline Stages](#3-pipeline-stages)
4. [iOS Client Changes](#4-ios-client-changes)
5. [Server Infrastructure](#5-server-infrastructure)
6. [API Specification](#6-api-specification)
7. [Data Models](#7-data-models)
8. [Error Handling](#8-error-handling)
9. [Performance & Cost](#9-performance--cost)
10. [Implementation Plan](#10-implementation-plan)
11. [Verification & Testing](#11-verification--testing)
12. [Alternative: CubiCasa Hybrid](#12-alternative-cubicasa-hybrid)

---

## 1. Architecture Overview

### High-Level Flow

```
+---------------------------------------------------------------------------+
|                              iOS CLIENT                                    |
+---------------------------------------------------------------------------|
|                                                                            |
|  +----------------+    +----------------+    +------------------+          |
|  | Video Capture  |--->| ARKit Poses +  |--->| iOS 18 Vision    |          |
|  |  (45-90 sec)   |    | Plane Anchors  |    | Sparse Depth     |          |
|  +----------------+    +----------------+    +------------------+          |
|         |                     |                      |                     |
|         v                     v                      v                     |
|  +------------------------------------------------------------------+     |
|  |                    Capture Package                                |     |
|  |  * video.mp4 (1080p, 30fps)                                      |     |
|  |  * poses.json (camera transforms + intrinsics, 60 Hz)            |     |
|  |  * planes.json (ARKit vertical + horizontal plane anchors)       |     |
|  |  * sparse_depth.json (iOS 18 Vision depth samples, optional)     |     |
|  |  * metadata.json (device info, timestamps)                       |     |
|  +------------------------------------------------------------------+     |
|                              |                                             |
+------------------------------+---------------------------------------------+
                               | HTTPS Upload (chunked)
                               v
+---------------------------------------------------------------------------+
|                     SERVERLESS GPU (RunPod / Modal)                         |
+---------------------------------------------------------------------------|
|                                                                            |
|  +-------------+   +-----------+   +-------+   +-----------+   +--------+ |
|  |   Frame     |-->| Video     |-->| Scale |-->|   SAM 3   |-->| Snap   | |
|  | Extraction  |   | Depth     |   | Calib |   | Text-     |   | to     | |
|  |             |   | Anything  |   |       |   | Prompted  |   | Stds   | |
|  +-------------+   +-----------+   +-------+   +-----------+   +--------+ |
|         |                |              |             |              |      |
|         v                v              v             v              v      |
|  +------------------------------------------------------------------+     |
|  |                    Pipeline Orchestrator                          |     |
|  |  * Coordinates all processing stages                             |     |
|  |  * Single container, all models preloaded                        |     |
|  |  * Manages GPU memory (sequential inference)                     |     |
|  +------------------------------------------------------------------+     |
|                              |                                             |
|                              v                                             |
|  +---------+   +-----------+   +----------+   +-------------+             |
|  | Wall    |-->| Floor Plan|-->|  VLM     |-->| Upload      |             |
|  | Detect  |   | Generator |   | Sanity   |   | Results     |             |
|  | (ARKit) |   |           |   | Check    |   |             |             |
|  +---------+   +-----------+   +----------+   +-------------+             |
|                                                                            |
+---------------------------------------------------------------------------+
```

### Key Design Principles

1. **Temporal depth over per-frame depth** — Video Depth Anything maintains scale consistency across the entire scan, eliminating the primary failure mode of V1
2. **One model for detect+segment** — SAM 3's text-prompted PCS replaces the Grounding DINO + SAM 2 handoff
3. **ARKit planes as ground truth for walls** — No point cloud RANSAC; planes are already metric and reliable
4. **VLM as error filter** — Cheap API call catches gross failures before the user sees them
5. **Serverless GPU** — Pay per scan, not per month. Cold starts under 2 seconds

---

## 2. Model Stack Deep Dive

### 2.1 Video Depth Anything (Primary Depth)

**Paper:** CVPR 2025 Highlight
**Repo:** https://github.com/DepthAnything/Video-Depth-Anything

| Property | Value |
|----------|-------|
| Output | Metric depth maps in meters |
| Temporal consistency | Yes (key-frame propagation) |
| Video length | Arbitrarily long (streaming mode) |
| Speed | 30 FPS (smallest model) |
| VRAM | ~4-6 GB |
| Trained on | Virtual KITTI, IRS (indoor) |

**Why this over Depth Pro per-frame:**
- Depth Pro gives excellent single-frame metric depth, but each frame is independent
- Video Depth Anything propagates scale and structure across frames
- For a 90-second scan, this means wall depths at frame 1 and frame 2700 are consistent
- Streaming metric mode added September 2025

**Usage pattern:**
```python
from video_depth_anything import VideoDepthAnything

model = VideoDepthAnything.from_pretrained("metric_indoor")
depth_maps = model.predict_video(
    video_path="kitchen_scan.mp4",
    mode="streaming_metric",
    target_fps=2.0  # Process at 2 FPS (same as frame extraction)
)
# depth_maps: List[np.ndarray] — metric depth in meters, temporally consistent
```

### 2.2 Prompt Depth Anything (Optional Depth Boost)

**Paper:** CVPR 2025
**Repo:** https://github.com/DepthAnything/PromptDA

Uses sparse depth "prompts" (from LiDAR, stereo, or in our case iOS 18 Vision framework) to guide the depth model. Achieves SOTA on ARKitScenes and ScanNet++ indoor benchmarks.

| Property | Value |
|----------|-------|
| Output | 4K resolution metric depth |
| Input | RGB image + sparse depth samples |
| VRAM | ~4 GB |
| Resolution | Up to 4K |

**When to use:** Only if the device provides sparse depth via iOS 18 Vision framework (`VNGenerateDepthRequest`). This is available on A12+ chips (iPhone XS and later) and provides monocular depth estimates — not LiDAR quality but enough to serve as prompts.

**Fallback:** If no sparse depth available, skip this stage and use Video Depth Anything output directly.

### 2.3 SAM 3 (Promptable Concept Segmentation)

**Release:** Meta, November 2025
**Repo:** https://github.com/facebookresearch/sam3

| Property | Value |
|----------|-------|
| Input | Image + text prompt (e.g., "base cabinet") |
| Output | Instance masks + class labels + tracking IDs |
| VRAM | ~4-6 GB |
| Key feature | Finds ALL instances of a concept — no bounding box needed |
| Video support | Yes, with instance tracking across frames |

**Why this over Grounding DINO + SAM 2:**
- Eliminates the detection→segmentation handoff (one model, one call)
- Instance tracking across video frames is built-in
- Handles partial occlusion better (concept-level understanding)
- ~30% faster pipeline (one inference instead of two)

**Usage pattern:**
```python
from sam3 import SAM3Predictor

predictor = SAM3Predictor.from_pretrained("sam3_hiera_large")

# Single call finds AND segments all instances
results = predictor.predict_concepts(
    image=frame_rgb,
    text_prompts=[
        "base cabinet",
        "upper cabinet",
        "refrigerator",
        "range",
        "dishwasher",
        "microwave",
        "range hood",
        "sink",
        "window",
        "door"
    ]
)
# results: List[ConceptResult] with .masks, .labels, .confidence, .tracking_id
```

### 2.4 Fast3R (Optional 3D Reconstruction)

**Paper:** CVPR 2025, Facebook Research
**Repo:** https://github.com/facebookresearch/fast3r

Not needed for the 2.5D pipeline, but if you ever need full 3D reconstruction:

| Property | Value |
|----------|-------|
| Speed | 251 FPS on 108 views |
| Capacity | 1000+ images in single forward pass |
| VRAM | Fits on single A100 for up to 1500 views |
| Output | Point cloud + camera poses |

This replaces MASt3R-SfM if 3D is needed later. The key advantage is single-pass processing — no iterative pair matching.

### 2.5 VLM Sanity Check (GPT-4o / Gemini 3)

Not a vision model for measurement — used purely as an error filter.

**Purpose:** After generating the floor plan, send the plan image + one photo of the kitchen to a VLM and ask: "Does this floor plan reasonably match this kitchen photo? Flag any obvious errors."

**Cost:** ~$0.01-0.03 per call (image + short text response)

**What it catches:**
- Floor plan shows 10 walls when the kitchen clearly has 2-3
- Detected a refrigerator where there clearly isn't one
- Room shape doesn't match the photo at all
- Missing major appliances visible in the photo

**What it can NOT do:**
- Verify precise measurements (VLMs can't measure)
- Replace any pipeline stage
- Guarantee correctness

### 2.6 VRAM Budget

| Model | VRAM | Loaded When |
|-------|------|-------------|
| Video Depth Anything (metric) | ~5 GB | Stage 2 |
| Prompt Depth Anything (optional) | ~4 GB | Stage 2 (alt) |
| SAM 3 | ~5 GB | Stage 5 |
| **Peak (sequential)** | **~5 GB** | One model at a time |
| **Peak (if parallel)** | **~10 GB** | Two models overlapping |

All models fit comfortably on an L4 (24 GB) or A10G (24 GB). Sequential loading means peak VRAM is only ~5 GB — much lower than V1's ~16 GB peak.

---

## 3. Pipeline Stages

### Stage Overview

```
+------------------------------------------------------------------+
|                       PIPELINE STAGES (V2)                        |
+------------------------------------------------------------------+
|                                                                    |
|  Stage 1: Frame Extraction (5%)                                   |
|  |-- Extract keyframes at 2 FPS                                   |
|  |-- Remove blurry frames (Laplacian variance < 100)              |
|  |-- Remove duplicates (SSIM > 0.95)                              |
|  +-- Output: 60-120 high-quality frames + timestamps              |
|                                                                    |
|  Stage 2: Depth Estimation (25%)                                  |
|  |-- Run Video Depth Anything in streaming metric mode            |
|  |-- Temporally consistent metric depth for all frames            |
|  |-- (Optional) Refine with Prompt Depth Anything if sparse       |
|  |   depth available from iOS 18 Vision                           |
|  +-- Output: depth_maps[] (meters, consistent scale)              |
|                                                                    |
|  Stage 3: Scale Calibration (35%)                                 |
|  |-- PRIMARY: Base cabinet height detection (34.5")               |
|  |-- FALLBACK 1: Countertop surface (36")                         |
|  |-- FALLBACK 2: Door height (80")                                |
|  |-- FALLBACK 3: Dishwasher width (24")                           |
|  |-- Multi-reference cross-validation                             |
|  +-- Output: validated_scale, confidence, method                  |
|                                                                    |
|  Stage 4: Wall Detection (50%)                                    |
|  |-- Use ARKit vertical planes (already metric)                   |
|  |-- Convert plane anchors to wall segments                       |
|  |-- Snap to 90-degree grid                                       |
|  |-- Find corners at intersections                                |
|  +-- Output: walls[], corners[], room_polygon                     |
|                                                                    |
|  Stage 5: Object Detection + Segmentation (70%)                   |
|  |-- SAM 3 with kitchen text prompts                              |
|  |-- Process keyframes with instance tracking                     |
|  |-- Extract dimensions: mask pixels x depth x scale              |
|  |-- Merge detections across frames by tracking ID                |
|  +-- Output: detections[] with masks, positions, dimensions       |
|                                                                    |
|  Stage 6: Snap to Standards (80%)                                 |
|  |-- Match raw dimensions to standard cabinet sizes               |
|  |-- Calculate confidence scores                                  |
|  |-- Flag items outside tolerance                                 |
|  +-- Output: snapped_dimensions[], flags[]                        |
|                                                                    |
|  Stage 7: Floor Plan Generation (90%)                             |
|  |-- Generate PNG floor plan (300 DPI)                            |
|  |-- Generate measurements JSON (MeasurementData format, FEET)    |
|  +-- Output: floor_plan.png, measurements.json                    |
|                                                                    |
|  Stage 8: VLM Validation (95%)                                    |
|  |-- Send floor plan + kitchen photo to GPT-4o/Gemini             |
|  |-- "Does this match? Flag obvious errors."                      |
|  |-- If FAIL: flag for human review, still return results         |
|  +-- Output: validation_result, flags[]                           |
|                                                                    |
|  Stage 9: Upload Results (100%)                                   |
|  |-- Upload all outputs to Supabase Storage                       |
|  |-- Update job status to completed                               |
|  +-- Notify client                                                |
|                                                                    |
+------------------------------------------------------------------+
```

### 3.1 Stage 1: Frame Extraction

Unchanged from V1. Extract keyframes at 2 FPS, filter blurry and duplicate frames.

```python
# pipeline/stages/frame_extraction.py

import cv2
import numpy as np
from dataclasses import dataclass
from pathlib import Path
from typing import Optional, List

@dataclass
class ExtractedFrame:
    index: int
    timestamp: float
    image: np.ndarray       # RGB, HxWx3
    quality_score: float
    pose: Optional[dict]    # Camera transform from poses.json

class FrameExtractor:
    def __init__(
        self,
        target_fps: float = 2.0,
        blur_threshold: float = 100.0,
        similarity_threshold: float = 0.95,
        min_frames: int = 30,
        max_frames: int = 150
    ):
        self.target_fps = target_fps
        self.blur_threshold = blur_threshold
        self.similarity_threshold = similarity_threshold
        self.min_frames = min_frames
        self.max_frames = max_frames

    def extract(
        self,
        video_path: Path,
        poses: List[dict]
    ) -> List[ExtractedFrame]:
        cap = cv2.VideoCapture(str(video_path))
        fps = cap.get(cv2.CAP_PROP_FPS)
        frame_interval = max(1, int(fps / self.target_fps))

        frames = []
        prev_gray = None
        frame_idx = 0

        while True:
            ret, frame = cap.read()
            if not ret:
                break

            if frame_idx % frame_interval != 0:
                frame_idx += 1
                continue

            gray = cv2.cvtColor(frame, cv2.COLOR_BGR2GRAY)
            blur_score = cv2.Laplacian(gray, cv2.CV_64F).var()

            if blur_score < self.blur_threshold:
                frame_idx += 1
                continue

            if prev_gray is not None:
                similarity = self._fast_similarity(prev_gray, gray)
                if similarity > self.similarity_threshold:
                    frame_idx += 1
                    continue

            timestamp = frame_idx / fps
            pose = self._find_nearest_pose(timestamp, poses)
            rgb = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)

            frames.append(ExtractedFrame(
                index=len(frames),
                timestamp=timestamp,
                image=rgb,
                quality_score=blur_score,
                pose=pose
            ))

            prev_gray = gray
            frame_idx += 1

            if len(frames) >= self.max_frames:
                break

        cap.release()

        if len(frames) < self.min_frames:
            raise PipelineError(
                f"Insufficient frames: {len(frames)} < {self.min_frames}. "
                "Record a longer scan (60+ seconds) with steady movement."
            )

        return frames

    def _fast_similarity(self, gray1: np.ndarray, gray2: np.ndarray) -> float:
        small1 = cv2.resize(gray1, (64, 64))
        small2 = cv2.resize(gray2, (64, 64))
        return 1.0 - (np.mean(np.abs(small1.astype(float) - small2.astype(float))) / 255.0)

    def _find_nearest_pose(self, timestamp: float, poses: List[dict]) -> Optional[dict]:
        if not poses:
            return None
        return min(poses, key=lambda p: abs(p["timestamp"] - timestamp))
```

### 3.2 Stage 2: Depth Estimation (Video Depth Anything)

The biggest change from V1. Instead of running Depth Pro on each frame independently, we process the entire video with temporal consistency.

```python
# pipeline/stages/depth_estimation.py

import torch
import numpy as np
from dataclasses import dataclass
from typing import Optional, Callable, List

@dataclass
class DepthResult:
    frame_index: int
    depth_map: np.ndarray       # Metric depth in meters (H x W)
    timestamp: float

class VideoDepthEstimator:
    """
    Temporally consistent metric depth using Video Depth Anything.

    Key advantage over per-frame Depth Pro:
    - Frame 1 and frame 2700 share the same scale
    - No per-frame scale jitter
    - Indoor metric model trained on Virtual KITTI + IRS
    """

    def __init__(self, device: str = "cuda"):
        self.device = device
        self.model = None

    def load_model(self):
        from video_depth_anything import VideoDepthAnything
        self.model = VideoDepthAnything.from_pretrained(
            "video-depth-anything-metric-indoor",
            device=self.device,
            dtype=torch.float16
        )

    def unload_model(self):
        del self.model
        self.model = None
        torch.cuda.empty_cache()

    @torch.inference_mode()
    def estimate_from_video(
        self,
        video_path: str,
        target_fps: float = 2.0,
        progress_callback: Optional[Callable] = None
    ) -> List[DepthResult]:
        """
        Process entire video with temporally consistent metric depth.
        Uses streaming mode for memory efficiency on long videos.
        """
        results = self.model.predict_video(
            video_path=video_path,
            mode="streaming_metric",
            target_fps=target_fps,
            progress_callback=progress_callback
        )

        return [
            DepthResult(
                frame_index=i,
                depth_map=r["depth"].cpu().numpy(),
                timestamp=r["timestamp"]
            )
            for i, r in enumerate(results)
        ]

    @torch.inference_mode()
    def estimate_from_frames(
        self,
        frames: List[np.ndarray],
        progress_callback: Optional[Callable] = None
    ) -> List[DepthResult]:
        """
        Fallback: process pre-extracted frames.
        Still maintains temporal consistency via key-frame propagation.
        """
        results = self.model.predict_frames(
            frames=frames,
            mode="metric",
            progress_callback=progress_callback
        )

        return [
            DepthResult(
                frame_index=i,
                depth_map=r["depth"].cpu().numpy(),
                timestamp=0.0
            )
            for i, r in enumerate(results)
        ]


class PromptDepthBooster:
    """
    Optional: Uses sparse depth from iOS 18 Vision framework
    as guidance for 4K metric depth via Prompt Depth Anything.

    Only used when sparse_depth.json is provided in capture package.
    """

    def __init__(self, device: str = "cuda"):
        self.device = device
        self.model = None

    def load_model(self):
        from prompt_depth_anything import PromptDA
        self.model = PromptDA.from_pretrained(
            "promptda-metric",
            device=self.device,
            dtype=torch.float16
        )

    def unload_model(self):
        del self.model
        self.model = None
        torch.cuda.empty_cache()

    @torch.inference_mode()
    def refine(
        self,
        frame: np.ndarray,
        sparse_depth: np.ndarray,  # Sparse depth samples from iOS Vision
        base_depth: np.ndarray     # Video Depth Anything output
    ) -> np.ndarray:
        """Refine depth using sparse samples as prompts."""
        result = self.model.predict(
            image=frame,
            sparse_depth=sparse_depth,
            prior_depth=base_depth
        )
        return result["depth"].cpu().numpy()
```

### 3.3 Stage 3: Scale Calibration (Multi-Reference)

Largely unchanged from V1, but now operates on temporally consistent depth maps, making calibration significantly more reliable.

```python
# pipeline/stages/scale_calibration.py

import numpy as np
from dataclasses import dataclass
from enum import Enum
from typing import List, Optional

class CalibrationMethod(Enum):
    BASE_CABINET_HEIGHT = "base_cabinet_height"   # 34.5" (without countertop)
    COUNTERTOP_HEIGHT = "countertop_height"        # 36" (floor to countertop)
    DOOR_HEIGHT = "door_height"                     # 80"
    DISHWASHER_WIDTH = "dishwasher_width"          # 24"

REFERENCE_DIMENSIONS_INCHES = {
    CalibrationMethod.BASE_CABINET_HEIGHT: 34.5,
    CalibrationMethod.COUNTERTOP_HEIGHT: 36.0,
    CalibrationMethod.DOOR_HEIGHT: 80.0,
    CalibrationMethod.DISHWASHER_WIDTH: 24.0,
}

@dataclass
class ScaleEstimate:
    method: CalibrationMethod
    scale: float          # multiplier to correct depth → real-world
    confidence: float
    detected_size: float  # size in current depth units
    reference_inches: float

@dataclass
class CalibrationResult:
    final_scale: float
    confidence: str                        # HIGH, MEDIUM, LOW
    primary_method: CalibrationMethod
    supporting_methods: List[CalibrationMethod]
    cross_validation_error_pct: float

class MultiReferenceCalibrator:
    """
    Multi-reference scale calibration with cross-validation.

    With Video Depth Anything's metric output, depths are already
    approximately metric (meters). This stage validates and fine-tunes
    the scale using detected reference objects.

    If multiple references agree within 3%, confidence is HIGH.
    """

    async def calibrate(
        self,
        frames: list,
        depth_maps: list,
        detections: list
    ) -> CalibrationResult:
        estimates = []

        for method, detector in [
            (CalibrationMethod.BASE_CABINET_HEIGHT, self._detect_base_cabinet_height),
            (CalibrationMethod.COUNTERTOP_HEIGHT, self._detect_countertop_height),
            (CalibrationMethod.DOOR_HEIGHT, self._detect_door_height),
            (CalibrationMethod.DISHWASHER_WIDTH, self._detect_dishwasher_width),
        ]:
            try:
                result = await detector(frames, depth_maps, detections)
                estimates.extend(result)
            except Exception:
                pass

        if not estimates:
            # No reference objects found — use depth model's native scale
            return CalibrationResult(
                final_scale=1.0,  # Trust Video Depth Anything metric output
                confidence="LOW",
                primary_method=CalibrationMethod.BASE_CABINET_HEIGHT,
                supporting_methods=[],
                cross_validation_error_pct=100.0
            )

        return self._cross_validate(estimates)

    def _cross_validate(self, estimates: List[ScaleEstimate]) -> CalibrationResult:
        scales = [e.scale for e in estimates]
        weights = [e.confidence for e in estimates]

        weighted_scale = float(np.average(scales, weights=weights))
        variance = float(np.std(scales) / weighted_scale) if weighted_scale > 0 else 1.0

        if variance < 0.03:
            confidence = "HIGH"
        elif variance < 0.08:
            confidence = "MEDIUM"
        else:
            confidence = "LOW"

        primary = max(estimates, key=lambda e: e.confidence)

        return CalibrationResult(
            final_scale=weighted_scale,
            confidence=confidence,
            primary_method=primary.method,
            supporting_methods=[e.method for e in estimates if e.method != primary.method],
            cross_validation_error_pct=round(variance * 100, 2)
        )

    async def _detect_base_cabinet_height(self, frames, depth_maps, detections):
        """Find base cabinets, measure height in depth map, compare to 34.5"."""
        estimates = []
        base_cabs = [d for d in detections if d.category == "base_cabinet"]

        for cab in base_cabs:
            mask = cab.mask
            depth = depth_maps[cab.frame_index].depth_map

            # Measure vertical extent of mask in depth-corrected space
            rows = np.any(mask, axis=1)
            y_min, y_max = np.where(rows)[0][[0, -1]]
            center_x = mask.shape[1] // 2
            center_depth_m = float(depth[int((y_min + y_max) / 2), center_x])

            height_pixels = y_max - y_min
            # Approximate: pixels * depth / focal_length = real size
            # We'll refine with actual focal length from poses
            estimated_height_m = height_pixels * center_depth_m / 1000  # Rough

            reference_m = REFERENCE_DIMENSIONS_INCHES[CalibrationMethod.BASE_CABINET_HEIGHT] * 0.0254
            scale = reference_m / estimated_height_m if estimated_height_m > 0 else 1.0

            estimates.append(ScaleEstimate(
                method=CalibrationMethod.BASE_CABINET_HEIGHT,
                scale=scale,
                confidence=cab.confidence * 0.9,
                detected_size=estimated_height_m,
                reference_inches=34.5
            ))

        return estimates

    # Similar implementations for countertop, door, dishwasher...
    async def _detect_countertop_height(self, frames, depth_maps, detections):
        return []

    async def _detect_door_height(self, frames, depth_maps, detections):
        return []

    async def _detect_dishwasher_width(self, frames, depth_maps, detections):
        return []
```

### 3.4 Stage 4: Wall Detection (ARKit Planes)

Unchanged from V1. Uses ARKit vertical plane anchors as the primary wall source.

```python
# pipeline/stages/wall_detection.py

import numpy as np
from dataclasses import dataclass
from typing import List, Tuple, Optional

@dataclass
class Wall:
    start: Tuple[float, float]   # (x, z) in inches, floor plane
    end: Tuple[float, float]
    length: float                 # inches
    angle: float                  # degrees
    confidence: float

@dataclass
class WallDetectionResult:
    walls: List[Wall]
    corners: List[Tuple[float, float]]
    room_polygon: Optional[List[Tuple[float, float]]]

class WallDetector:
    """
    Wall detection using ARKit vertical planes as PRIMARY source.
    ARKit planes are already in meters — no depth estimation needed.
    """

    def __init__(
        self,
        min_wall_length: float = 24.0,   # inches
        angle_snap_threshold: float = 5.0  # degrees
    ):
        self.min_wall_length = min_wall_length
        self.angle_snap_threshold = angle_snap_threshold

    def detect(self, arkit_planes: List[dict]) -> WallDetectionResult:
        walls = []

        for plane in arkit_planes:
            if plane.get("alignment") != "vertical":
                continue

            center = np.array([plane["center"][0], plane["center"][2]])
            extent_x = plane["extent"][0]

            transform = np.array(plane["transform"])
            normal = transform[:3, 2]
            wall_dir = np.array([-normal[2], normal[0]])
            norm = np.linalg.norm(wall_dir)
            if norm < 1e-6:
                continue
            wall_dir = wall_dir / norm

            half_extent_inches = extent_x / 2 * 39.3701
            center_inches = center * 39.3701

            start = center_inches - wall_dir * half_extent_inches
            end = center_inches + wall_dir * half_extent_inches

            length = float(np.linalg.norm(end - start))
            angle = float(np.arctan2(end[1] - start[1], end[0] - start[0]) * 180 / np.pi)

            if length >= self.min_wall_length:
                walls.append(Wall(
                    start=tuple(start),
                    end=tuple(end),
                    length=length,
                    angle=angle,
                    confidence=0.9
                ))

        walls = self._snap_angles(walls)
        walls = self._merge_collinear(walls)
        corners = self._find_corners(walls)
        polygon = self._build_polygon(corners) if len(corners) >= 3 else None

        return WallDetectionResult(
            walls=walls,
            corners=corners,
            room_polygon=polygon
        )

    def _snap_angles(self, walls: List[Wall]) -> List[Wall]:
        snapped = []
        for wall in walls:
            cardinal = round(wall.angle / 90) * 90
            if abs(wall.angle - cardinal) <= self.angle_snap_threshold:
                wall = Wall(
                    start=wall.start, end=wall.end,
                    length=wall.length, angle=cardinal % 360,
                    confidence=wall.confidence
                )
            snapped.append(wall)
        return snapped

    def _merge_collinear(self, walls: List[Wall]) -> List[Wall]:
        # Merge wall segments that are collinear and overlapping
        # Group by snapped angle, then merge overlapping segments
        return walls  # TODO: implement merging

    def _find_corners(self, walls: List[Wall]) -> List[Tuple[float, float]]:
        # Find intersections of adjacent walls
        corners = []
        for i in range(len(walls)):
            for j in range(i + 1, len(walls)):
                corner = self._line_intersection(walls[i], walls[j])
                if corner is not None:
                    corners.append(corner)
        return corners

    def _line_intersection(
        self, w1: Wall, w2: Wall
    ) -> Optional[Tuple[float, float]]:
        # Standard line-line intersection
        x1, y1 = w1.start
        x2, y2 = w1.end
        x3, y3 = w2.start
        x4, y4 = w2.end

        denom = (x1 - x2) * (y3 - y4) - (y1 - y2) * (x3 - x4)
        if abs(denom) < 1e-6:
            return None

        t = ((x1 - x3) * (y3 - y4) - (y1 - y3) * (x3 - x4)) / denom
        px = x1 + t * (x2 - x1)
        py = y1 + t * (y2 - y1)

        return (float(px), float(py))

    def _build_polygon(
        self, corners: List[Tuple[float, float]]
    ) -> List[Tuple[float, float]]:
        # Order corners to form a valid polygon (convex hull as fallback)
        from scipy.spatial import ConvexHull
        if len(corners) < 3:
            return corners
        points = np.array(corners)
        try:
            hull = ConvexHull(points)
            return [tuple(points[i]) for i in hull.vertices]
        except Exception:
            return corners
```

### 3.5 Stage 5: Object Detection + Segmentation (SAM 3)

The biggest pipeline simplification. One model call replaces Grounding DINO + SAM 2.

```python
# pipeline/stages/object_detection.py

import torch
import numpy as np
from dataclasses import dataclass, field
from typing import Optional, Callable, List, Dict

@dataclass
class Detection:
    id: str
    category: str
    confidence: float
    frame_index: int
    mask: np.ndarray                                    # Binary mask (H x W)
    tracking_id: Optional[int] = None                   # SAM 3 tracking ID
    position: Optional[tuple] = None                    # (x, z) in inches, floor plane
    dimensions: Optional[Dict[str, float]] = None       # width, height in inches
    snapped_width: Optional[float] = None               # After snap-to-standards
    snap_deviation: Optional[float] = None
    is_standard_size: bool = False
    needs_review: bool = False
    confidence_level: str = "medium"

KITCHEN_PROMPTS = [
    "base cabinet",
    "upper cabinet",
    "tall cabinet",
    "pantry cabinet",
    "refrigerator",
    "range",
    "cooktop",
    "oven",
    "dishwasher",
    "microwave",
    "range hood",
    "sink",
    "window",
    "door",
    "island",
    "countertop",
]

class SAM3Detector:
    """
    Kitchen object detection using SAM 3 Promptable Concept Segmentation.

    SAM 3 finds AND segments all instances of a concept via text prompt.
    No bounding box detection step needed (unlike Grounding DINO + SAM 2).
    Built-in instance tracking across video frames.
    """

    def __init__(self, device: str = "cuda"):
        self.device = device
        self.predictor = None

    def load_model(self):
        from sam3 import SAM3Predictor
        self.predictor = SAM3Predictor.from_pretrained(
            "sam3_hiera_large",
            device=self.device
        )

    def unload_model(self):
        del self.predictor
        self.predictor = None
        torch.cuda.empty_cache()

    def detect(
        self,
        frames: list,
        depth_maps: list,
        scale: float,
        focal_lengths: Optional[List[float]] = None,
        progress_callback: Optional[Callable] = None
    ) -> List[Detection]:
        all_detections = []
        det_id = 0

        for i, frame in enumerate(frames):
            results = self.predictor.predict_concepts(
                image=frame.image,
                text_prompts=KITCHEN_PROMPTS
            )

            for result in results:
                for instance_idx, mask in enumerate(result.masks):
                    dimensions = self._extract_dimensions(
                        mask=mask,
                        depth_map=depth_maps[i].depth_map,
                        scale=scale,
                        focal_length=focal_lengths[i] if focal_lengths else None,
                        image_shape=frame.image.shape
                    )

                    detection = Detection(
                        id=f"det_{det_id}",
                        category=self._normalize_category(result.label),
                        confidence=float(result.confidence[instance_idx]),
                        frame_index=i,
                        mask=mask,
                        tracking_id=result.tracking_ids[instance_idx] if hasattr(result, 'tracking_ids') else None,
                        dimensions=dimensions
                    )
                    all_detections.append(detection)
                    det_id += 1

            if progress_callback:
                progress_callback(i + 1, len(frames))

        merged = self._merge_across_frames(all_detections)
        return merged

    def _extract_dimensions(
        self,
        mask: np.ndarray,
        depth_map: np.ndarray,
        scale: float,
        focal_length: Optional[float],
        image_shape: tuple
    ) -> Dict[str, float]:
        """
        Extract real-world dimensions from mask + metric depth.

        Method:
        1. Get mask bounding box in pixels
        2. Get depth at mask center (meters, from Video Depth Anything)
        3. Convert pixel dimensions to real-world using:
           real_size = pixel_size * depth / focal_length
        4. Apply scale calibration factor
        5. Convert meters to inches
        """
        rows = np.any(mask, axis=1)
        cols = np.any(mask, axis=0)
        if not rows.any() or not cols.any():
            return {"width": 0, "height": 0, "depth_meters": 0}

        y_min, y_max = np.where(rows)[0][[0, -1]]
        x_min, x_max = np.where(cols)[0][[0, -1]]

        width_pixels = x_max - x_min
        height_pixels = y_max - y_min

        # Get depth at mask center
        center_y = (y_min + y_max) // 2
        center_x = (x_min + x_max) // 2

        # Use median depth in mask region for robustness
        mask_depths = depth_map[mask > 0]
        if len(mask_depths) == 0:
            return {"width": 0, "height": 0, "depth_meters": 0}

        depth_meters = float(np.median(mask_depths))

        if depth_meters <= 0:
            return {"width": 0, "height": 0, "depth_meters": 0}

        # Convert pixels to real-world size
        if focal_length and focal_length > 0:
            width_meters = width_pixels * depth_meters / focal_length
            height_meters = height_pixels * depth_meters / focal_length
        else:
            # Estimate focal length from image width (typical iPhone ~28mm equiv)
            estimated_focal_px = image_shape[1] * 0.85  # ~85% of image width
            width_meters = width_pixels * depth_meters / estimated_focal_px
            height_meters = height_pixels * depth_meters / estimated_focal_px

        # Apply scale calibration and convert to inches
        width_inches = width_meters * scale * 39.3701
        height_inches = height_meters * scale * 39.3701

        return {
            "width": round(width_inches, 1),
            "height": round(height_inches, 1),
            "depth_meters": round(depth_meters, 3)
        }

    def _normalize_category(self, label: str) -> str:
        label = label.lower().strip()
        mapping = {
            "refrigerator": "refrigerator", "fridge": "refrigerator",
            "range": "range", "stove": "range",
            "oven": "oven", "cooktop": "cooktop",
            "dishwasher": "dishwasher", "microwave": "microwave",
            "range hood": "hood", "hood": "hood",
            "sink": "sink",
            "base cabinet": "base_cabinet",
            "upper cabinet": "upper_cabinet", "wall cabinet": "upper_cabinet",
            "tall cabinet": "tall_cabinet", "pantry cabinet": "tall_cabinet",
            "pantry": "tall_cabinet",
            "window": "window", "door": "door",
            "island": "island", "countertop": "countertop",
        }
        for key, value in mapping.items():
            if key in label:
                return value
        return label.replace(" ", "_")

    def _merge_across_frames(self, detections: List[Detection]) -> List[Detection]:
        """
        Merge detections of the same object across frames.
        Uses SAM 3 tracking IDs when available, falls back to IoU matching.
        """
        if not detections:
            return []

        # Group by tracking ID
        by_tracking = {}
        untracked = []

        for det in detections:
            if det.tracking_id is not None:
                key = (det.category, det.tracking_id)
                by_tracking.setdefault(key, []).append(det)
            else:
                untracked.append(det)

        merged = []
        for key, group in by_tracking.items():
            # Take the detection with highest confidence
            best = max(group, key=lambda d: d.confidence)
            # Average dimensions across frames for stability
            widths = [d.dimensions["width"] for d in group if d.dimensions and d.dimensions["width"] > 0]
            heights = [d.dimensions["height"] for d in group if d.dimensions and d.dimensions["height"] > 0]

            if widths:
                best.dimensions["width"] = round(float(np.median(widths)), 1)
            if heights:
                best.dimensions["height"] = round(float(np.median(heights)), 1)

            best.confidence = float(np.mean([d.confidence for d in group]))
            merged.append(best)

        # Add untracked detections (deduplicate by category + position proximity)
        merged.extend(untracked)  # TODO: IoU-based dedup for untracked

        return merged
```

### 3.6 Stage 6: Snap to Standards

Unchanged from V1.

```python
# pipeline/stages/snap_to_standards.py

from dataclasses import dataclass
from typing import List, Tuple

STANDARD_WIDTHS_INCHES = {
    "range": [30, 36, 48, 60],
    "refrigerator": [30, 33, 36, 42, 48],
    "dishwasher": [18, 24],
    "hood": [30, 36, 42, 48],
    "sink": [30, 33, 36, 42],
    "base_cabinet": [9, 12, 15, 18, 21, 24, 27, 30, 33, 36, 42],
    "upper_cabinet": [9, 12, 15, 18, 24, 30, 33, 36, 42],
    "tall_cabinet": [18, 24, 30, 36],
    "window": [24, 30, 36, 42, 48, 60, 72],
    "door": [24, 28, 30, 32, 34, 36],
}

class StandardSnapper:
    def __init__(
        self,
        high_threshold: float = 2.0,    # inches
        medium_threshold: float = 4.0,  # inches
    ):
        self.high_threshold = high_threshold
        self.medium_threshold = medium_threshold

    def snap_all(self, detections: list) -> list:
        for det in detections:
            if det.dimensions is None or det.dimensions["width"] <= 0:
                det.needs_review = True
                det.confidence_level = "low"
                continue

            width = det.dimensions["width"]
            category = det.category

            if category not in STANDARD_WIDTHS_INCHES:
                det.snapped_width = width
                det.snap_deviation = 0
                det.needs_review = True
                det.confidence_level = "low"
                continue

            standards = STANDARD_WIDTHS_INCHES[category]
            nearest = min(standards, key=lambda x: abs(x - width))
            deviation = abs(nearest - width)

            det.snapped_width = nearest
            det.snap_deviation = deviation
            det.is_standard_size = deviation <= self.high_threshold

            if deviation <= self.high_threshold and det.confidence > 0.7:
                det.confidence_level = "high"
                det.needs_review = False
            elif deviation <= self.medium_threshold and det.confidence > 0.5:
                det.confidence_level = "medium"
                det.needs_review = False
            else:
                det.confidence_level = "low"
                det.needs_review = True

        return detections
```

### 3.7 Stage 7: Floor Plan Generation

```python
# pipeline/stages/floor_plan_generation.py

from typing import Dict, List
from PIL import Image, ImageDraw, ImageFont
import io

class FloorPlanGenerator:
    """Generate PNG floor plan and MeasurementData JSON."""

    def __init__(
        self,
        dpi: int = 300,
        scale: float = 4.0,   # pixels per inch of room
        padding: int = 100,
    ):
        self.dpi = dpi
        self.scale = scale
        self.padding = padding

    def generate_png(self, walls, detections) -> bytes:
        """Generate floor plan PNG image."""
        # Calculate bounds
        all_x = []
        all_y = []
        for w in walls.walls:
            all_x.extend([w.start[0], w.end[0]])
            all_y.extend([w.start[1], w.end[1]])

        if not all_x:
            return b""

        min_x, max_x = min(all_x), max(all_x)
        min_y, max_y = min(all_y), max(all_y)

        width = int((max_x - min_x) * self.scale) + 2 * self.padding
        height = int((max_y - min_y) * self.scale) + 2 * self.padding

        img = Image.new("RGB", (width, height), "white")
        draw = ImageDraw.Draw(img)

        def to_px(x, y):
            px = int((x - min_x) * self.scale + self.padding)
            py = int((y - min_y) * self.scale + self.padding)
            return px, py

        # Draw walls
        for wall in walls.walls:
            start = to_px(*wall.start)
            end = to_px(*wall.end)
            draw.line([start, end], fill="#333333", width=4)

        # Draw detections
        for det in detections:
            if det.position:
                px, py = to_px(det.position[0], det.position[1])
                color = self._category_color(det.category)
                w = int((det.snapped_width or det.dimensions["width"]) * self.scale / 2)
                draw.rectangle([px - w, py - 10, px + w, py + 10], fill=color, outline="#333")

        buf = io.BytesIO()
        img.save(buf, format="PNG", dpi=(self.dpi, self.dpi))
        return buf.getvalue()

    def generate_measurements_json(
        self,
        walls,
        detections: list,
        calibration
    ) -> Dict:
        """
        Generate JSON in MeasurementData format.
        CRITICAL: Dashboard expects values in FEET, not inches.
        """
        return {
            "room_name": "Kitchen",
            "room_type": "kitchen",
            "total_linear_ft": sum(
                (d.snapped_width or d.dimensions["width"])
                for d in detections
                if d.category in ["base_cabinet", "upper_cabinet"]
                and d.dimensions
            ) / 12,
            "total_sq_ft": self._calculate_room_area(walls) / 144,
            "wall_count": len(walls.walls),
            "window_count": len([d for d in detections if d.category == "window"]),
            "door_count": len([d for d in detections if d.category == "door"]),

            "measurements": {
                "scan_method": "ai_flow_server_v2",

                "ai_metadata": {
                    "schema_version": "2.1",
                    "pipeline_version": "v2",
                    "depth_model": "video_depth_anything_metric",
                    "detection_model": "sam3_pcs",
                    "calibration_method": calibration.primary_method.value,
                    "calibration_confidence": calibration.confidence,
                    "cross_validation_error_pct": calibration.cross_validation_error_pct,
                    "needs_verification": calibration.confidence == "LOW",
                },

                "walls": [
                    {
                        "id": f"wall_{i}",
                        "start": {"x": w.start[0] / 12, "z": w.start[1] / 12},
                        "end": {"x": w.end[0] / 12, "z": w.end[1] / 12},
                        "length_ft": w.length / 12,
                        "height_ft": 8.0,
                        "confidence": "high" if w.confidence > 0.8 else "medium"
                    }
                    for i, w in enumerate(walls.walls)
                ],

                "cabinets": {
                    "lower": [
                        self._format_cabinet(d) for d in detections
                        if d.category == "base_cabinet"
                    ],
                    "upper": [
                        self._format_cabinet(d) for d in detections
                        if d.category == "upper_cabinet"
                    ],
                    "pantry": [
                        self._format_cabinet(d) for d in detections
                        if d.category == "tall_cabinet"
                    ],
                },

                "appliances": [
                    self._format_appliance(d) for d in detections
                    if d.category in ["refrigerator", "range", "cooktop", "oven",
                                       "dishwasher", "microwave", "hood", "sink"]
                ],

                "doors": [self._format_opening(d) for d in detections if d.category == "door"],
                "windows": [self._format_opening(d) for d in detections if d.category == "window"],

                "flags": [
                    {
                        "object_id": d.id,
                        "category": d.category,
                        "issue": f"Measurement deviation: {d.snap_deviation:.1f} inches",
                        "raw_value": d.dimensions["width"],
                        "snapped_value": d.snapped_width
                    }
                    for d in detections if d.needs_review
                ]
            }
        }

    def _format_cabinet(self, d) -> Dict:
        return {
            "id": d.id,
            "position": {"x": d.position[0] / 12, "z": d.position[1] / 12} if d.position else None,
            "width_ft": (d.snapped_width or d.dimensions["width"]) / 12,
            "height_ft": d.dimensions["height"] / 12 if d.dimensions else 2.875,
            "depth_ft": 2.0,
            "width_raw_inches": d.dimensions["width"] if d.dimensions else 0,
            "width_snapped_inches": d.snapped_width or 0,
            "confidence": d.confidence_level,
            "ai_is_standard_size": d.is_standard_size
        }

    def _format_appliance(self, d) -> Dict:
        return {
            "id": d.id,
            "type": d.category,
            "position": {"x": d.position[0] / 12, "z": d.position[1] / 12} if d.position else None,
            "width_ft": (d.snapped_width or d.dimensions["width"]) / 12,
            "width_raw_inches": d.dimensions["width"] if d.dimensions else 0,
            "width_snapped_inches": d.snapped_width or 0,
            "confidence": d.confidence_level,
        }

    def _format_opening(self, d) -> Dict:
        return {
            "id": d.id,
            "type": d.category,
            "width_ft": (d.snapped_width or d.dimensions["width"]) / 12,
            "width_raw_inches": d.dimensions["width"] if d.dimensions else 0,
            "confidence": d.confidence_level,
        }

    def _calculate_room_area(self, walls) -> float:
        if walls.room_polygon and len(walls.room_polygon) >= 3:
            # Shoelace formula
            pts = walls.room_polygon
            n = len(pts)
            area = 0
            for i in range(n):
                j = (i + 1) % n
                area += pts[i][0] * pts[j][1]
                area -= pts[j][0] * pts[i][1]
            return abs(area) / 2
        return 0

    def _category_color(self, category: str) -> str:
        colors = {
            "base_cabinet": "#8B4513",
            "upper_cabinet": "#A0522D",
            "tall_cabinet": "#6B3410",
            "refrigerator": "#4682B4",
            "range": "#CD853F",
            "dishwasher": "#5F9EA0",
            "sink": "#6495ED",
            "hood": "#708090",
            "window": "#87CEEB",
            "door": "#DEB887",
        }
        return colors.get(category, "#999999")
```

### 3.8 Stage 8: VLM Validation (New)

```python
# pipeline/stages/vlm_validation.py

import base64
from dataclasses import dataclass
from typing import Optional
import httpx

@dataclass
class ValidationResult:
    passed: bool
    confidence: float          # 0-1
    issues: list               # List of flagged issues
    suggestion: Optional[str]  # User-facing suggestion if failed

class VLMValidator:
    """
    Uses GPT-4o or Gemini 3 to sanity-check the generated floor plan.

    NOT for measurement verification — VLMs cannot measure.
    This catches gross structural errors:
    - Floor plan shows 10 walls when kitchen has 2
    - Missing major appliances visible in photo
    - Room shape wildly inconsistent with photo
    """

    def __init__(self, api_key: str, provider: str = "openai"):
        self.api_key = api_key
        self.provider = provider

    async def validate(
        self,
        floor_plan_png: bytes,
        kitchen_photo: bytes,
        detection_summary: dict
    ) -> ValidationResult:
        plan_b64 = base64.b64encode(floor_plan_png).decode()
        photo_b64 = base64.b64encode(kitchen_photo).decode()

        prompt = f"""You are validating a computer-generated kitchen floor plan.

Compare the floor plan image with the actual kitchen photo.

Detection summary:
- Walls: {detection_summary.get('wall_count', 0)}
- Base cabinets: {detection_summary.get('base_cabinet_count', 0)}
- Upper cabinets: {detection_summary.get('upper_cabinet_count', 0)}
- Appliances: {detection_summary.get('appliance_count', 0)}
- Windows: {detection_summary.get('window_count', 0)}
- Doors: {detection_summary.get('door_count', 0)}

Check for OBVIOUS errors only:
1. Does the room shape roughly match?
2. Are major visible appliances present in the floor plan?
3. Is the wall count reasonable for what you see?
4. Are there any clearly wrong detections?

Respond with JSON:
{{
    "passed": true/false,
    "confidence": 0.0-1.0,
    "issues": ["issue1", "issue2"],
    "suggestion": "optional user-facing suggestion"
}}

Only fail if there are OBVIOUS gross errors. Minor inaccuracies are acceptable."""

        if self.provider == "openai":
            return await self._call_openai(prompt, plan_b64, photo_b64)
        else:
            return await self._call_gemini(prompt, plan_b64, photo_b64)

    async def _call_openai(self, prompt, plan_b64, photo_b64) -> ValidationResult:
        async with httpx.AsyncClient() as client:
            response = await client.post(
                "https://api.openai.com/v1/chat/completions",
                headers={"Authorization": f"Bearer {self.api_key}"},
                json={
                    "model": "gpt-4o",
                    "messages": [{
                        "role": "user",
                        "content": [
                            {"type": "text", "text": prompt},
                            {"type": "image_url", "image_url": {"url": f"data:image/png;base64,{plan_b64}"}},
                            {"type": "image_url", "image_url": {"url": f"data:image/jpeg;base64,{photo_b64}"}},
                        ]
                    }],
                    "max_tokens": 500,
                    "response_format": {"type": "json_object"}
                },
                timeout=30.0
            )
            result = response.json()["choices"][0]["message"]["content"]
            import json
            data = json.loads(result)

            return ValidationResult(
                passed=data.get("passed", True),
                confidence=data.get("confidence", 0.5),
                issues=data.get("issues", []),
                suggestion=data.get("suggestion")
            )

    async def _call_gemini(self, prompt, plan_b64, photo_b64) -> ValidationResult:
        # Similar implementation for Gemini API
        return ValidationResult(passed=True, confidence=0.5, issues=[], suggestion=None)
```

### 3.9 Pipeline Orchestrator

```python
# pipeline/orchestrator.py

import time
import torch
from dataclasses import dataclass
from typing import Optional, Callable
from pathlib import Path

@dataclass
class PipelineInput:
    video_path: Path
    poses: list                     # Camera transforms from ARKit
    planes: list                    # ARKit plane anchors
    sparse_depth: Optional[list]    # iOS 18 Vision depth (optional)
    metadata: dict

@dataclass
class PipelineOutput:
    floor_plan_png: bytes
    measurements_json: dict
    validation_result: dict
    processing_time_ms: int
    stage_timings: dict

class PipelineOrchestrator:
    """
    Coordinates all pipeline stages.
    Models are loaded once at worker startup and reused across jobs.
    Sequential inference to minimize VRAM usage (~5 GB peak).
    """

    def __init__(self, device: str = "cuda"):
        self.device = device
        self.depth_estimator = None
        self.depth_booster = None
        self.detector = None
        self.wall_detector = None
        self.calibrator = None
        self.snapper = None
        self.floor_plan_gen = None
        self.vlm_validator = None

    def load_all_models(self):
        """Called once at worker startup."""
        from .stages.depth_estimation import VideoDepthEstimator, PromptDepthBooster
        from .stages.object_detection import SAM3Detector
        from .stages.wall_detection import WallDetector
        from .stages.scale_calibration import MultiReferenceCalibrator
        from .stages.snap_to_standards import StandardSnapper
        from .stages.floor_plan_generation import FloorPlanGenerator
        from .stages.vlm_validation import VLMValidator

        self.depth_estimator = VideoDepthEstimator(self.device)
        self.depth_estimator.load_model()

        self.detector = SAM3Detector(self.device)
        self.detector.load_model()

        self.wall_detector = WallDetector()
        self.calibrator = MultiReferenceCalibrator()
        self.snapper = StandardSnapper()
        self.floor_plan_gen = FloorPlanGenerator()

        # VLM validator uses external API — no GPU needed
        import os
        self.vlm_validator = VLMValidator(
            api_key=os.environ.get("OPENAI_API_KEY", ""),
            provider="openai"
        )

    async def process(
        self,
        input: PipelineInput,
        progress_callback: Optional[Callable] = None
    ) -> PipelineOutput:
        start_time = time.time()
        timings = {}

        def report(stage: str, progress: float):
            if progress_callback:
                progress_callback(progress, stage)

        # Stage 1: Frame Extraction
        report("Analyzing video...", 0.05)
        t = time.time()
        from .stages.frame_extraction import FrameExtractor
        extractor = FrameExtractor()
        frames = extractor.extract(input.video_path, input.poses)
        timings["frame_extraction"] = time.time() - t

        # Stage 2: Depth Estimation
        report("Creating depth maps...", 0.25)
        t = time.time()
        depth_maps = self.depth_estimator.estimate_from_frames(
            [f.image for f in frames],
            progress_callback=lambda i, n: report("Creating depth maps...", 0.05 + 0.20 * i / n)
        )
        timings["depth_estimation"] = time.time() - t

        # Stage 5 (run early for calibration): Object Detection
        report("Finding cabinets and appliances...", 0.50)
        t = time.time()
        detections = self.detector.detect(
            frames=frames,
            depth_maps=depth_maps,
            scale=1.0,  # Pre-calibration, will re-extract after
            progress_callback=lambda i, n: report("Finding cabinets...", 0.35 + 0.35 * i / n)
        )
        timings["object_detection"] = time.time() - t

        # Stage 3: Scale Calibration
        report("Calibrating measurements...", 0.75)
        t = time.time()
        calibration = await self.calibrator.calibrate(frames, depth_maps, detections)
        timings["scale_calibration"] = time.time() - t

        # Re-extract dimensions with calibrated scale
        if abs(calibration.final_scale - 1.0) > 0.01:
            detections = self.detector.detect(
                frames=frames,
                depth_maps=depth_maps,
                scale=calibration.final_scale
            )

        # Stage 4: Wall Detection
        report("Detecting walls...", 0.80)
        t = time.time()
        walls = self.wall_detector.detect(input.planes)
        timings["wall_detection"] = time.time() - t

        # Stage 6: Snap to Standards
        report("Matching to standard sizes...", 0.85)
        t = time.time()
        detections = self.snapper.snap_all(detections)
        timings["snap_to_standards"] = time.time() - t

        # Stage 7: Floor Plan Generation
        report("Creating floor plan...", 0.90)
        t = time.time()
        floor_plan_png = self.floor_plan_gen.generate_png(walls, detections)
        measurements_json = self.floor_plan_gen.generate_measurements_json(
            walls, detections, calibration
        )
        timings["floor_plan_generation"] = time.time() - t

        # Stage 8: VLM Validation
        report("Validating results...", 0.95)
        t = time.time()
        validation = ValidationResult(passed=True, confidence=1.0, issues=[], suggestion=None)
        if self.vlm_validator and self.vlm_validator.api_key:
            try:
                # Use the first frame as the kitchen photo
                import cv2
                _, photo_bytes = cv2.imencode(".jpg", frames[0].image)
                validation = await self.vlm_validator.validate(
                    floor_plan_png=floor_plan_png,
                    kitchen_photo=photo_bytes.tobytes(),
                    detection_summary={
                        "wall_count": len(walls.walls),
                        "base_cabinet_count": len([d for d in detections if d.category == "base_cabinet"]),
                        "upper_cabinet_count": len([d for d in detections if d.category == "upper_cabinet"]),
                        "appliance_count": len([d for d in detections if d.category in ["refrigerator", "range", "dishwasher"]]),
                        "window_count": len([d for d in detections if d.category == "window"]),
                        "door_count": len([d for d in detections if d.category == "door"]),
                    }
                )
            except Exception:
                pass  # VLM validation is best-effort
        timings["vlm_validation"] = time.time() - t

        processing_time_ms = int((time.time() - start_time) * 1000)

        # Add processing time to metadata
        measurements_json["measurements"]["ai_metadata"]["processing_time_ms"] = processing_time_ms

        # Add VLM validation flags
        if not validation.passed:
            measurements_json["measurements"]["ai_metadata"]["vlm_validation"] = "FAILED"
            measurements_json["measurements"]["ai_metadata"]["vlm_issues"] = validation.issues
            measurements_json["measurements"]["ai_metadata"]["needs_verification"] = True

        report("Complete!", 1.0)

        return PipelineOutput(
            floor_plan_png=floor_plan_png,
            measurements_json=measurements_json,
            validation_result={
                "passed": validation.passed,
                "confidence": validation.confidence,
                "issues": validation.issues,
                "suggestion": validation.suggestion,
            },
            processing_time_ms=processing_time_ms,
            stage_timings=timings
        )
```

---

## 4. iOS Client Changes

### 4.1 Enable ARKit Plane Detection

```swift
// AIARSessionManager.swift — CRITICAL CHANGE

// Enable plane detection (currently disabled)
configuration.planeDetection = [.horizontal, .vertical]

// Store detected planes
private var detectedPlanes: [UUID: ARPlaneAnchor] = [:]

func session(_ session: ARSession, didAdd anchors: [ARAnchor]) {
    for anchor in anchors {
        if let planeAnchor = anchor as? ARPlaneAnchor {
            detectedPlanes[planeAnchor.identifier] = planeAnchor
        }
    }
}

func session(_ session: ARSession, didUpdate anchors: [ARAnchor]) {
    for anchor in anchors {
        if let planeAnchor = anchor as? ARPlaneAnchor {
            detectedPlanes[planeAnchor.identifier] = planeAnchor
        }
    }
}

func exportPlanesJSON() -> Data {
    let planes = detectedPlanes.values.map { anchor -> [String: Any] in
        [
            "identifier": anchor.identifier.uuidString,
            "alignment": anchor.alignment == .horizontal ? "horizontal" : "vertical",
            "center": [anchor.center.x, anchor.center.y, anchor.center.z],
            "extent": [anchor.extent.x, anchor.extent.y, anchor.extent.z],
            "transform": [
                [anchor.transform.columns.0.x, anchor.transform.columns.0.y,
                 anchor.transform.columns.0.z, anchor.transform.columns.0.w],
                [anchor.transform.columns.1.x, anchor.transform.columns.1.y,
                 anchor.transform.columns.1.z, anchor.transform.columns.1.w],
                [anchor.transform.columns.2.x, anchor.transform.columns.2.y,
                 anchor.transform.columns.2.z, anchor.transform.columns.2.w],
                [anchor.transform.columns.3.x, anchor.transform.columns.3.y,
                 anchor.transform.columns.3.z, anchor.transform.columns.3.w],
            ]
        ]
    }
    return try! JSONSerialization.data(withJSONObject: planes, options: .prettyPrinted)
}
```

### 4.2 Optional: iOS 18 Vision Sparse Depth

```swift
// SparseDepthExtractor.swift — NEW FILE (optional)

import Vision
import ARKit

class SparseDepthExtractor {
    /// Extract sparse depth samples from iOS 18 Vision framework.
    /// Available on A12+ (iPhone XS and later).
    /// Returns sparse depth grid that Prompt Depth Anything can use.

    func extractSparseDepth(from frame: ARFrame) async -> [[Float]]? {
        guard #available(iOS 18.0, *) else { return nil }

        let request = VNGenerateDepthRequest()
        let handler = VNImageRequestHandler(
            cvPixelBuffer: frame.capturedImage,
            orientation: .up
        )

        do {
            try handler.perform([request])
            guard let result = request.results?.first as? VNPixelBufferObservation else {
                return nil
            }

            // Convert to sparse depth grid (sample every 32 pixels)
            let depthMap = result.pixelBuffer
            return self.sampleSparseDepth(from: depthMap, stride: 32)
        } catch {
            return nil
        }
    }

    private func sampleSparseDepth(from buffer: CVPixelBuffer, stride: Int) -> [[Float]] {
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }

        let width = CVPixelBufferGetWidth(buffer)
        let height = CVPixelBufferGetHeight(buffer)
        let baseAddress = CVPixelBufferGetBaseAddress(buffer)!
        let floatBuffer = baseAddress.assumingMemoryBound(to: Float32.self)

        var samples: [[Float]] = []
        for y in stride(from: 0, to: height, by: stride) {
            for x in stride(from: 0, to: width, by: stride) {
                let depth = floatBuffer[y * width + x]
                if depth > 0 && depth < 10 {
                    samples.append([Float(x), Float(y), depth])
                }
            }
        }
        return samples
    }
}
```

### 4.3 CapturePackage Builder

```swift
// CapturePackageBuilder.swift — NEW FILE

import Foundation
import ARKit

struct CapturePackage {
    let videoURL: URL
    let posesData: Data        // JSON array of camera poses
    let planesData: Data       // JSON array of ARKit plane anchors
    let sparseDepthData: Data? // Optional iOS 18 Vision sparse depth
    let metadata: CaptureMetadata

    struct CaptureMetadata: Codable {
        let deviceModel: String
        let osVersion: String
        let captureDate: Date
        let duration: TimeInterval
        let frameCount: Int
        let showroomId: UUID
        let projectId: UUID?
        let hasLiDAR: Bool
        let hasSparseDepth: Bool
        let planeCount: Int
    }
}

class CapturePackageBuilder {
    private let sessionManager: AIARSessionManager

    init(sessionManager: AIARSessionManager) {
        self.sessionManager = sessionManager
    }

    func build(
        videoURL: URL,
        showroomId: UUID,
        projectId: UUID?
    ) -> CapturePackage {
        let poses = sessionManager.exportPosesJSON()
        let planes = sessionManager.exportPlanesJSON()

        let metadata = CapturePackage.CaptureMetadata(
            deviceModel: UIDevice.current.modelName,
            osVersion: UIDevice.current.systemVersion,
            captureDate: Date(),
            duration: sessionManager.capturedDuration,
            frameCount: sessionManager.capturedFrameCount,
            showroomId: showroomId,
            projectId: projectId,
            hasLiDAR: ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh),
            hasSparseDepth: false, // Set true if sparse depth extracted
            planeCount: sessionManager.detectedPlanes.count
        )

        return CapturePackage(
            videoURL: videoURL,
            posesData: poses,
            planesData: planes,
            sparseDepthData: nil,
            metadata: metadata
        )
    }
}
```

### 4.4 ServerPipelineClient

```swift
// ServerPipelineClient.swift — NEW FILE

import Foundation

actor ServerPipelineClient {
    private let baseURL: URL
    private let apiKey: String

    init(baseURL: URL, apiKey: String) {
        self.baseURL = baseURL
        self.apiKey = apiKey
    }

    // MARK: - Upload

    func uploadCapture(_ package: CapturePackage) async throws -> String {
        // 1. Upload video (chunked for large files)
        let videoURL = try await uploadFile(
            package.videoURL,
            path: "captures/\(UUID().uuidString)/video.mp4"
        )

        // 2. Upload poses JSON
        let posesURL = try await uploadData(
            package.posesData,
            path: "captures/\(UUID().uuidString)/poses.json"
        )

        // 3. Upload planes JSON
        let planesURL = try await uploadData(
            package.planesData,
            path: "captures/\(UUID().uuidString)/planes.json"
        )

        // 4. Upload sparse depth if available
        var sparseDepthURL: String? = nil
        if let sparseData = package.sparseDepthData {
            sparseDepthURL = try await uploadData(
                sparseData,
                path: "captures/\(UUID().uuidString)/sparse_depth.json"
            )
        }

        // 5. Create processing job
        let metadata = try JSONEncoder().encode(package.metadata)
        let jobId = try await createJob(
            videoURL: videoURL,
            posesURL: posesURL,
            planesURL: planesURL,
            sparseDepthURL: sparseDepthURL,
            metadata: metadata
        )

        return jobId
    }

    // MARK: - Polling

    func pollForResults(
        jobId: String,
        onProgress: @MainActor (Double, String) -> Void
    ) async throws -> PipelineResult {
        let maxAttempts = 300  // 5 minutes max
        let pollInterval: UInt64 = 1_000_000_000  // 1 second

        for _ in 0..<maxAttempts {
            let status = try await getJobStatus(jobId)

            switch status.state {
            case "completed":
                return try await downloadResults(jobId: jobId)
            case "failed":
                throw PipelineError.processingFailed(status.error ?? "Unknown error")
            case "processing":
                await onProgress(status.progress, status.stageMessage)
            default:
                break
            }

            try await Task.sleep(nanoseconds: pollInterval)
        }

        throw PipelineError.timeout
    }

    // MARK: - Private

    private func uploadFile(_ fileURL: URL, path: String) async throws -> String {
        // Chunked upload to Supabase Storage
        // Returns public URL
        return ""
    }

    private func uploadData(_ data: Data, path: String) async throws -> String {
        return ""
    }

    private func createJob(
        videoURL: String,
        posesURL: String,
        planesURL: String,
        sparseDepthURL: String?,
        metadata: Data
    ) async throws -> String {
        return ""
    }

    private func getJobStatus(_ jobId: String) async throws -> JobStatus {
        return JobStatus(state: "queued", progress: 0, stageMessage: "", error: nil)
    }

    private func downloadResults(jobId: String) async throws -> PipelineResult {
        return PipelineResult()
    }
}

struct JobStatus {
    let state: String
    let progress: Double
    let stageMessage: String
    let error: String?
}

struct PipelineResult {
    var floorPlanPNG: Data?
    var measurementsJSON: Data?
    var validationPassed: Bool = true
}

enum PipelineError: Error {
    case processingFailed(String)
    case timeout
    case uploadFailed(String)
}
```

---

## 5. Server Infrastructure

### 5.1 Platform: RunPod Serverless (Production) / Modal (Development)

| | RunPod (Prod) | Modal (Dev) |
|---|---|---|
| **Cold start** | 1-2s (FlashBoot) | ~10s (GPU snapshots) |
| **GPU** | L4 24GB | L4 24GB |
| **Cost per scan** | ~$0.02 (2 min) | ~$0.03 (2 min) |
| **Warm workers** | Active Workers (40% off) | min_containers |
| **Max timeout** | 7 days | 24 hours |
| **Free tier** | None | $30/mo |

### 5.2 RunPod Worker

```python
# server/runpod_handler.py

import runpod
import json
import tempfile
from pathlib import Path

# Models loaded once at worker startup
orchestrator = None

def init():
    """Called once when worker starts."""
    global orchestrator
    from pipeline.orchestrator import PipelineOrchestrator
    orchestrator = PipelineOrchestrator(device="cuda")
    orchestrator.load_all_models()

async def handler(job):
    """Process a single kitchen scan job."""
    job_input = job["input"]

    # Download input files to temp directory
    with tempfile.TemporaryDirectory() as tmpdir:
        video_path = Path(tmpdir) / "video.mp4"
        await download_file(job_input["video_url"], video_path)

        poses = json.loads(await download_text(job_input["poses_url"]))
        planes = json.loads(await download_text(job_input["planes_url"]))

        sparse_depth = None
        if job_input.get("sparse_depth_url"):
            sparse_depth = json.loads(await download_text(job_input["sparse_depth_url"]))

        from pipeline.orchestrator import PipelineInput
        pipeline_input = PipelineInput(
            video_path=video_path,
            poses=poses,
            planes=planes,
            sparse_depth=sparse_depth,
            metadata=job_input.get("metadata", {})
        )

        def progress_callback(progress, stage):
            runpod.serverless.progress_update(job, {
                "progress": progress,
                "stage": stage
            })

        result = await orchestrator.process(
            pipeline_input,
            progress_callback=progress_callback
        )

        # Upload results to Supabase Storage
        floor_plan_url = await upload_to_supabase(
            result.floor_plan_png,
            f"results/{job['id']}/floor_plan.png"
        )
        measurements_url = await upload_to_supabase(
            json.dumps(result.measurements_json).encode(),
            f"results/{job['id']}/measurements.json"
        )

        return {
            "floor_plan_url": floor_plan_url,
            "measurements_url": measurements_url,
            "validation": result.validation_result,
            "processing_time_ms": result.processing_time_ms,
            "stage_timings": result.stage_timings,
        }

# Initialize models at import time
init()

runpod.serverless.start({"handler": handler})
```

### 5.3 Modal Worker (Development)

```python
# server/modal_app.py

import modal

app = modal.App("cabinetscan-pipeline-v2")

# Docker image with all dependencies
image = (
    modal.Image.debian_slim(python_version="3.11")
    .pip_install(
        "torch==2.4.0",
        "torchvision",
        "opencv-python-headless",
        "numpy",
        "scipy",
        "pillow",
        "httpx",
    )
    .pip_install("video-depth-anything")
    .pip_install("sam3")
)

@app.cls(
    gpu="L4",
    image=image,
    container_idle_timeout=300,  # Keep warm for 5 min after last request
    timeout=600,                  # 10 min max per job
)
class Pipeline:
    @modal.enter()
    def load_models(self):
        from pipeline.orchestrator import PipelineOrchestrator
        self.orchestrator = PipelineOrchestrator(device="cuda")
        self.orchestrator.load_all_models()

    @modal.method()
    async def process(self, job_input: dict) -> dict:
        # Same logic as RunPod handler
        pass
```

### 5.4 VRAM Budget (L4 24GB)

| Model | VRAM | Loaded |
|-------|------|--------|
| Video Depth Anything | ~5 GB | Persistent |
| SAM 3 | ~5 GB | Persistent |
| PyTorch + CUDA overhead | ~2 GB | Always |
| Working memory (frames, depth maps) | ~3 GB | Per job |
| **Total** | **~15 GB** | Fits comfortably on L4 |

Both models stay loaded in VRAM. Sequential inference means they don't compete for memory.

---

## 6. API Specification

### 6.1 Create Job

```
POST /api/v1/jobs
Authorization: Bearer <supabase_anon_key>
Content-Type: application/json

Request:
{
    "video_url": "https://storage.supabase.co/.../video.mp4",
    "poses_url": "https://storage.supabase.co/.../poses.json",
    "planes_url": "https://storage.supabase.co/.../planes.json",
    "sparse_depth_url": "https://storage.supabase.co/.../sparse_depth.json",  // optional
    "metadata": {
        "device_model": "iPhone 14",
        "showroom_id": "uuid",
        "project_id": "uuid",
        "has_lidar": false,
        "has_sparse_depth": true
    }
}

Response:
{
    "job_id": "uuid",
    "status": "queued",
    "created_at": "2026-02-06T10:00:00Z"
}
```

### 6.2 Get Job Status

```
GET /api/v1/jobs/{job_id}

Response:
{
    "job_id": "uuid",
    "status": "processing",
    "progress": 0.65,
    "stage": "Finding cabinets and appliances...",
    "created_at": "2026-02-06T10:00:00Z",
    "started_at": "2026-02-06T10:00:02Z"
}
```

### 6.3 Get Results

```
GET /api/v1/jobs/{job_id}/results

Response:
{
    "job_id": "uuid",
    "status": "completed",
    "results": {
        "floor_plan_png_url": "https://...",
        "measurements_json_url": "https://...",
        "validation_passed": true,
        "validation_issues": [],
        "objects_count": 12,
        "flags_count": 1
    },
    "processing_time_ms": 95000,
    "completed_at": "2026-02-06T10:01:37Z"
}
```

---

## 7. Data Models

### 7.1 Database Schema

```sql
CREATE TABLE processing_jobs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    showroom_id UUID REFERENCES showrooms(id),
    project_id UUID REFERENCES projects(id),

    -- Input
    video_url TEXT NOT NULL,
    poses_url TEXT,
    planes_url TEXT,
    sparse_depth_url TEXT,
    metadata JSONB DEFAULT '{}',

    -- Status
    status TEXT DEFAULT 'queued'
        CHECK (status IN ('queued', 'processing', 'completed', 'failed')),
    progress FLOAT DEFAULT 0,
    stage TEXT,
    error_message TEXT,

    -- Results
    floor_plan_png_url TEXT,
    measurements_json_url TEXT,
    scale_confidence TEXT,
    validation_passed BOOLEAN,
    validation_issues JSONB DEFAULT '[]',
    flags_count INT DEFAULT 0,

    -- Pipeline metadata
    pipeline_version TEXT DEFAULT 'v2',
    depth_model TEXT DEFAULT 'video_depth_anything_metric',
    detection_model TEXT DEFAULT 'sam3_pcs',

    -- Timing
    created_at TIMESTAMPTZ DEFAULT NOW(),
    started_at TIMESTAMPTZ,
    completed_at TIMESTAMPTZ,
    processing_time_ms INT,
    stage_timings JSONB DEFAULT '{}',

    -- Retry
    worker_id TEXT,
    retry_count INT DEFAULT 0
);

CREATE INDEX idx_jobs_status ON processing_jobs(status, created_at);
CREATE INDEX idx_jobs_showroom ON processing_jobs(showroom_id);

ALTER TABLE processing_jobs ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Showroom owners can view their jobs"
ON processing_jobs FOR SELECT
USING (showroom_id IN (
    SELECT id FROM showrooms WHERE owner_id = auth.uid()
));
```

---

## 8. Error Handling

### 8.1 Error Categories

| Error | HTTP | Retry | User Message |
|-------|------|-------|-------------|
| `insufficient_frames` | 400 | No | "Please record a longer scan (60+ seconds) with steady movement" |
| `no_planes_detected` | 400 | No | "No walls detected. Please scan slowly, pointing at walls" |
| `no_reference_objects` | 400 | No | "No cabinets or appliances found for scale calibration" |
| `vlm_validation_failed` | 200 | No | Results returned with warning flag |
| `processing_timeout` | 504 | Yes | "Processing took too long. Retrying..." |
| `model_error` | 500 | Yes | "Processing error. Retrying..." |
| `gpu_oom` | 500 | Yes | Retry with fewer frames |

### 8.2 Retry Config

```python
RETRY_CONFIG = {
    "max_retries": 2,
    "initial_delay_seconds": 5,
    "backoff_multiplier": 2,
    "retryable_errors": ["processing_timeout", "model_error", "gpu_oom"],
    "gpu_oom_strategy": "reduce_frames",  # Retry with max_frames/2
}
```

---

## 9. Performance & Cost

### 9.1 Target Latency

| Stage | Target | Notes |
|-------|--------|-------|
| Frame extraction | <5s | CPU only |
| Video Depth Anything | <15s | 120 frames on L4 |
| Scale calibration | <2s | CPU |
| Wall detection (ARKit) | <1s | CPU, no RANSAC |
| SAM 3 detection | <15s | 120 frames on L4 |
| Snap to standards | <1s | CPU |
| Floor plan generation | <3s | CPU + PIL |
| VLM validation | <5s | External API call |
| **Total** | **<60s** | |

### 9.2 Cost Per Scan

| Platform | GPU | Duration | Cost/Scan |
|----------|-----|----------|-----------|
| RunPod Active Worker | L4 | 2 min | $0.016 |
| RunPod Flex | L4 | 2 min | $0.023 |
| Modal | L4 | 2 min | $0.027 |
| VLM validation (GPT-4o) | — | 1 call | $0.01-0.03 |
| **Total** | | | **~$0.03-0.06** |

### 9.3 Monthly Cost Estimates

| Volume | Scans/mo | RunPod | Modal | VLM | Storage | **Total** |
|--------|----------|--------|-------|-----|---------|-----------|
| Light | 100 | $2 | $3 | $2 | $5 | **~$10** |
| Medium | 1,000 | $16 | $27 | $20 | $20 | **~$60** |
| Heavy | 10,000 | $160 | $270 | $200 | $100 | **~$500** |

This is 10-60x cheaper than V1's $600/month fixed GPU server estimate.

---

## 10. Implementation Plan

### Phase 1: iOS Client (Week 1)
- [ ] Enable ARKit plane detection in `AIARSessionManager.swift`
- [ ] Create `CapturePackageBuilder.swift`
- [ ] Create `ServerPipelineClient.swift`
- [ ] Update `AIFlowCoordinator.swift` for server flow
- [ ] Add upload progress + processing status UI
- [ ] (Optional) Add iOS 18 Vision sparse depth extraction

### Phase 2: Server Scaffold (Week 1-2)
- [ ] Set up Modal project for development
- [ ] Create pipeline package structure
- [ ] Implement frame extraction stage
- [ ] Install and test Video Depth Anything (metric mode)
- [ ] Install and test SAM 3

### Phase 3: Core Pipeline (Week 2-3)
- [ ] Implement depth estimation stage (Video Depth Anything)
- [ ] Implement multi-reference scale calibration
- [ ] Implement wall detection from ARKit planes
- [ ] Implement SAM 3 object detection + dimension extraction
- [ ] Implement snap-to-standards

### Phase 4: Output + Validation (Week 3-4)
- [ ] Implement floor plan PNG generation
- [ ] Implement MeasurementData JSON output (FEET!)
- [ ] Implement VLM validation stage
- [ ] End-to-end integration on Modal

### Phase 5: Production Deploy (Week 4-5)
- [ ] Port to RunPod Serverless worker
- [ ] Set up Supabase Edge Function for job creation
- [ ] Database migration for `processing_jobs` table
- [ ] iOS app integration testing
- [ ] Accuracy validation against known kitchens

### Phase 6: Polish (Week 5-6)
- [ ] Error handling and retry logic
- [ ] Monitoring and logging
- [ ] Performance optimization (batch inference, memory)
- [ ] User acceptance testing

---

## 11. Verification & Testing

### 11.1 Accuracy Test

```python
def test_measurement_accuracy():
    ground_truth = {
        "wall_1_length": 144,      # 12 feet
        "refrigerator_width": 36,
        "range_width": 30,
        "base_cabinet_1_width": 24
    }

    result = run_pipeline("tests/fixtures/measured_kitchen.mp4")

    for key, expected in ground_truth.items():
        actual = result.get_measurement(key)
        error = abs(actual - expected)
        assert error <= 2, f"{key}: expected {expected}, got {actual} (error: {error})"
```

### 11.2 Regression Test

```python
def test_no_chaos():
    """Ensure we never return chaotic results like the V1 pipeline."""
    result = run_pipeline("tests/fixtures/simple_kitchen.mp4")

    # V1 returned 10 walls, 15 cabinets, 0 windows
    assert len(result.walls) <= 6, f"Too many walls: {len(result.walls)}"
    assert len(result.base_cabinets) <= 10, f"Too many cabinets: {len(result.base_cabinets)}"

    # VLM validation should pass
    assert result.validation_passed, f"VLM flagged issues: {result.validation_issues}"
```

### 11.3 End-to-End Test Procedure

1. Record 60-second kitchen scan on iPhone (non-LiDAR)
2. Verify capture package includes video + poses + planes
3. Upload to server, monitor job progress through all stages
4. Verify floor plan PNG is reasonable
5. Verify measurements JSON has correct structure (FEET)
6. Verify VLM validation passes
7. Compare measurements against tape measure ground truth

---

## 12. Alternative: CubiCasa Hybrid

If building the full pipeline proves too complex or slow, consider a hybrid approach:

| Component | Provider | Why |
|-----------|----------|-----|
| Room layout + walls | CubiCasa SDK | They have a mature room scanning SDK |
| Cabinet detection + measurement | Custom pipeline (SAM 3 + depth) | CubiCasa doesn't do cabinet-specific measurement |
| Snap to standards | Custom | Our competitive advantage |

**CubiCasa SDK:**
- iOS SDK for scanning (drops into your app)
- Server-side processing, returns floor plans
- 1-5% measurement accuracy for room dimensions
- Contact: developer.support@cubicasa.com

This reduces your custom work to: cabinet detection, dimension extraction, and snap-to-standards — while CubiCasa handles the room geometry problem.

---

## References

### Models
- Video Depth Anything: https://github.com/DepthAnything/Video-Depth-Anything
- Prompt Depth Anything: https://github.com/DepthAnything/PromptDA
- SAM 3: https://ai.meta.com/blog/segment-anything-model-3/
- Fast3R: https://github.com/facebookresearch/fast3r
- DINO-X: https://github.com/IDEA-Research/DINO-X-API

### Compute
- RunPod Serverless: https://docs.runpod.io/serverless/
- Modal: https://modal.com/docs
- Google Cloud Run GPU: https://cloud.google.com/run/docs/configuring/services/gpu

### Commercial
- CubiCasa SDK: https://www.cubi.casa/developers/
- magicplan API: https://apidocs.magicplan.app/

---

*Document created: February 2026*
*Supersedes: SERVER_PIPELINE_DESIGN.md (V1)*
