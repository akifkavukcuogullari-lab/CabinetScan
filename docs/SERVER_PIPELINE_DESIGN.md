# Kitchen Capture Pipeline - Upgraded Server Architecture

## Overview

This document provides the detailed design for implementing the Upgraded Server Pipeline for non-LiDAR kitchen measurement capture. This replaces the broken on-device AI flow with a server-side approach using state-of-the-art AI models.

### Key Technology Stack

| Component | Technology | Why |
|-----------|------------|-----|
| **Depth Estimation** | Apple Depth Pro | Metric depth (not relative), sharp edges, no camera intrinsics needed |
| **3D Reconstruction** | MASt3R-SfM | 10-50x faster than COLMAP, metric output, works with sparse views |
| **Object Detection** | Grounding DINO + SAM 2 | Zero-shot detection via text prompts, pixel-perfect masks |
| **Measurement** | Snap-to-Standards | Reduces noise by matching to industry standard cabinet sizes |

### Expected Accuracy

| Measurement | Before (On-Device) | After (Server) |
|-------------|-------------------|----------------|
| Wall lengths | ❌ Unusable | ±1-2 inches |
| Cabinet widths | ❌ Unusable | ±0.5-1 inch (before snap) |
| After snapping | N/A | **Exact SKU match** |

---

## Table of Contents

1. [Architecture Overview](#1-architecture-overview)
2. [iOS Client Changes](#2-ios-client-changes)
3. [Server Infrastructure](#3-server-infrastructure)
4. [Pipeline Stages](#4-pipeline-stages)
5. [API Specification](#5-api-specification)
6. [Data Models](#6-data-models)
7. [Error Handling](#7-error-handling)
8. [Performance Requirements](#8-performance-requirements)
9. [Implementation Plan](#9-implementation-plan)
10. [Verification & Testing](#10-verification--testing)

---

## 1. Architecture Overview

### High-Level Flow

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                              iOS CLIENT                                      │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│  ┌──────────────┐    ┌──────────────┐    ┌──────────────┐                   │
│  │ Video Capture │───▶│ ARKit Poses  │───▶│   Upload     │                   │
│  │  (45-90 sec)  │    │  (60 Hz)     │    │  Manager     │                   │
│  └──────────────┘    └──────────────┘    └──────────────┘                   │
│         │                   │                   │                            │
│         │                   │                   │                            │
│         ▼                   ▼                   ▼                            │
│  ┌─────────────────────────────────────────────────────────────┐            │
│  │                    Capture Session Data                      │            │
│  │  • video.mp4 (1080p, 30fps)                                 │            │
│  │  • poses.json (camera transforms + intrinsics)              │            │
│  │  • metadata.json (device info, timestamps)                  │            │
│  └─────────────────────────────────────────────────────────────┘            │
│                                    │                                         │
└────────────────────────────────────┼─────────────────────────────────────────┘
                                     │ HTTPS Upload
                                     ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                              SERVER                                          │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│  ┌─────────────┐    ┌─────────────┐    ┌─────────────┐    ┌─────────────┐   │
│  │   Frame     │───▶│  Depth Pro  │───▶│  MASt3R-SfM │───▶│  Grounding  │   │
│  │ Extraction  │    │  (Metric)   │    │    (3D)     │    │  DINO+SAM2  │   │
│  └─────────────┘    └─────────────┘    └─────────────┘    └─────────────┘   │
│         │                  │                  │                  │          │
│         ▼                  ▼                  ▼                  ▼          │
│  ┌─────────────────────────────────────────────────────────────────────┐    │
│  │                     Pipeline Orchestrator                            │    │
│  │  • Coordinates all processing stages                                │    │
│  │  • Manages GPU resources                                            │    │
│  │  • Handles errors and retries                                       │    │
│  └─────────────────────────────────────────────────────────────────────┘    │
│                                    │                                         │
│                                    ▼                                         │
│  ┌─────────────────────────────────────────────────────────────────────┐    │
│  │                      Output Generation                               │    │
│  │  • 2D Floor Plan (SVG + PNG)                                        │    │
│  │  • Measurements JSON                                                 │    │
│  │  • Confidence Scores                                                 │    │
│  │  • Flagged Items for Review                                         │    │
│  └─────────────────────────────────────────────────────────────────────┘    │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

### Technology Stack

| Layer | Technology | Purpose |
|-------|------------|---------|
| iOS Client | SwiftUI + ARKit | Video capture, pose tracking, upload |
| Upload | Supabase Storage | Video/metadata storage |
| API Gateway | Supabase Edge Functions | Request routing, auth |
| Processing Server | Python + FastAPI | ML pipeline orchestration |
| GPU Compute | NVIDIA A10G / L4 | Model inference |
| Queue | Redis / Bull | Job queue for processing |
| Storage | Supabase Storage | Results storage |

---

## 2. iOS Client Changes

### 2.1 Modified Components

#### AIFlowCoordinator.swift
Replace on-device processing with server upload flow:

```swift
// Current (broken):
func processCapture() async throws -> MeasurementData {
    // On-device DepthAnythingV2 → TSDF → Detection
    throw AIFlowError.notImplemented
}

// New:
func processCapture() async throws -> MeasurementData {
    // 1. Package capture data
    let capturePackage = try await packageCaptureData()

    // 2. Upload to server
    let jobId = try await uploadForProcessing(capturePackage)

    // 3. Poll for results
    let result = try await pollForResults(jobId: jobId)

    // 4. Convert to MeasurementData
    return try convertToMeasurementData(result)
}
```

#### New: ServerPipelineClient.swift
```swift
import Foundation

actor ServerPipelineClient {
    private let baseURL: URL
    private let supabaseClient: SupabaseClient

    // MARK: - Upload

    func uploadCapture(_ package: CapturePackage) async throws -> String {
        // 1. Upload video to Supabase Storage
        let videoURL = try await uploadVideo(package.videoURL)

        // 2. Upload poses JSON
        let posesURL = try await uploadPoses(package.poses)

        // 3. Create processing job
        let jobId = try await createProcessingJob(
            videoURL: videoURL,
            posesURL: posesURL,
            metadata: package.metadata
        )

        return jobId
    }

    // MARK: - Polling

    func pollForResults(jobId: String) async throws -> PipelineResult {
        let maxAttempts = 120  // 2 minutes max
        let pollInterval: UInt64 = 1_000_000_000  // 1 second

        for attempt in 0..<maxAttempts {
            let status = try await getJobStatus(jobId)

            switch status.state {
            case .completed:
                return try await downloadResults(jobId: jobId)
            case .failed:
                throw PipelineError.processingFailed(status.error ?? "Unknown error")
            case .processing:
                // Update UI with progress
                await MainActor.run {
                    self.delegate?.pipelineProgress(status.progress, status.stage)
                }
            default:
                break
            }

            try await Task.sleep(nanoseconds: pollInterval)
        }

        throw PipelineError.timeout
    }
}
```

#### New: CapturePackage.swift
```swift
struct CapturePackage {
    let videoURL: URL
    let poses: [CameraPose]
    let metadata: CaptureMetadata

    struct CameraPose: Codable {
        let timestamp: Double
        let transform: simd_float4x4
        let intrinsics: simd_float3x3
        let exposureDuration: Double
        let exposureISO: Float
    }

    struct CaptureMetadata: Codable {
        let deviceModel: String
        let osVersion: String
        let captureDate: Date
        let duration: TimeInterval
        let frameCount: Int
        let showroomId: UUID
        let projectId: UUID?
    }
}
```

### 2.2 UI Changes

#### ProcessingView Updates
```swift
struct ServerProcessingView: View {
    @ObservedObject var viewModel: ProcessingViewModel

    var body: some View {
        VStack(spacing: 24) {
            // Stage indicator
            ProcessingStageView(stage: viewModel.currentStage)

            // Progress bar
            ProgressView(value: viewModel.progress)
                .progressViewStyle(LinearProgressViewStyle())

            // Stage-specific message
            Text(viewModel.stageMessage)
                .font(.subheadline)
                .foregroundColor(.secondary)

            // Estimated time
            if let eta = viewModel.estimatedTimeRemaining {
                Text("About \(eta) remaining")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
    }
}

enum ProcessingStage: String, CaseIterable {
    case uploading = "Uploading scan..."
    case queued = "In queue..."
    case extractingFrames = "Analyzing video..."
    case estimatingDepth = "Creating depth map..."
    case reconstructing3D = "Building 3D model..."
    case detectingObjects = "Finding cabinets..."
    case generatingFloorPlan = "Creating floor plan..."
    case complete = "Complete!"
}
```

---

## 3. Server Infrastructure

### 3.1 Architecture Diagram

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                           SUPABASE                                           │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│  ┌─────────────┐    ┌─────────────┐    ┌─────────────┐                      │
│  │  Storage    │    │  Database   │    │   Edge      │                      │
│  │  (Videos)   │    │ (Jobs/Results)│   │  Functions  │                      │
│  └─────────────┘    └─────────────┘    └─────────────┘                      │
│         │                  │                  │                              │
└─────────┼──────────────────┼──────────────────┼──────────────────────────────┘
          │                  │                  │
          ▼                  ▼                  ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                        GPU PROCESSING SERVER                                 │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│  ┌─────────────────────────────────────────────────────────────────────┐    │
│  │                         FastAPI Application                          │    │
│  │                                                                      │    │
│  │  ┌───────────┐  ┌───────────┐  ┌───────────┐  ┌───────────┐        │    │
│  │  │  /jobs    │  │ /status   │  │ /results  │  │ /health   │        │    │
│  │  └───────────┘  └───────────┘  └───────────┘  └───────────┘        │    │
│  └─────────────────────────────────────────────────────────────────────┘    │
│                                    │                                         │
│                                    ▼                                         │
│  ┌─────────────────────────────────────────────────────────────────────┐    │
│  │                         Job Queue (Redis)                            │    │
│  │                                                                      │    │
│  │  pending: [...] │ processing: [...] │ completed: [...] │ failed: [...]   │
│  └─────────────────────────────────────────────────────────────────────┘    │
│                                    │                                         │
│                                    ▼                                         │
│  ┌─────────────────────────────────────────────────────────────────────┐    │
│  │                       Pipeline Workers (x2-4)                        │    │
│  │                                                                      │    │
│  │  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐                  │    │
│  │  │ Depth Pro   │  │  MASt3R-SfM │  │ Grounded    │                  │    │
│  │  │   Model     │  │    Model    │  │  SAM 2      │                  │    │
│  │  │  (GPU 0)    │  │   (GPU 0)   │  │  (GPU 0)    │                  │    │
│  │  └─────────────┘  └─────────────┘  └─────────────┘                  │    │
│  └─────────────────────────────────────────────────────────────────────┘    │
│                                                                              │
│  GPU: NVIDIA A10G (24GB) or L4 (24GB)                                       │
│  RAM: 64GB                                                                   │
│  Storage: 500GB NVMe SSD                                                    │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

### 3.2 Server Requirements

| Component | Specification | Notes |
|-----------|---------------|-------|
| GPU | NVIDIA A10G or L4 (24GB VRAM) | Required for all models |
| CPU | 16+ cores | Frame extraction, I/O |
| RAM | 64GB | Model loading, batch processing |
| Storage | 500GB NVMe SSD | Temp files, model weights |
| Network | 1Gbps+ | Video download/upload |

### 3.3 Model Memory Requirements

| Model | VRAM Usage | Load Time |
|-------|------------|-----------|
| Depth Pro | ~4GB | ~10s |
| MASt3R-SfM | ~8GB | ~15s |
| Grounding DINO 1.6 | ~4GB | ~8s |
| SAM 2.1 | ~4GB | ~8s |
| **Total Peak** | **~16GB** | - |

Models are loaded once at worker startup and kept in memory.

---

## 4. Pipeline Stages

### 4.1 Stage Overview

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                          PIPELINE STAGES                                     │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│  Stage 1: Frame Extraction (5%)                                             │
│  ├─ Extract keyframes at 2 fps                                              │
│  ├─ Remove blurry frames (Laplacian variance < 100)                         │
│  ├─ Remove duplicate frames (SSIM > 0.95)                                   │
│  └─ Output: 60-120 high-quality frames                                      │
│                                                                              │
│  Stage 2: Depth Estimation (25%)                                            │
│  ├─ Run Depth Pro on each frame                                             │
│  ├─ Get metric depth maps (meters)                                          │
│  ├─ Get estimated focal lengths                                             │
│  └─ Output: depth_maps[], focal_lengths[]                                   │
│                                                                              │
│  Stage 3: 3D Reconstruction (35%)                                           │
│  ├─ Run MASt3R-SfM on frame pairs                                           │
│  ├─ Build sparse point cloud                                                │
│  ├─ Refine camera poses                                                     │
│  ├─ Dense reconstruction with depth guidance                                │
│  └─ Output: point_cloud, camera_poses                                       │
│                                                                              │
│  Stage 4: Scale Validation (40%)                                            │
│  ├─ Depth Pro provides metric scale                                         │
│  ├─ Detect base cabinet for validation                                      │
│  ├─ Cross-check: cabinet height should be ~36"                              │
│  └─ Output: validated_scale_factor, confidence                              │
│                                                                              │
│  Stage 5: Wall Detection (50%)                                              │
│  ├─ Project point cloud to bird's eye view                                  │
│  ├─ RANSAC line detection for walls                                         │
│  ├─ Snap to 90° angles                                                      │
│  ├─ Extract corners and wall lengths                                        │
│  └─ Output: walls[], corners[]                                              │
│                                                                              │
│  Stage 6: Object Detection (70%)                                            │
│  ├─ Run Grounding DINO with kitchen prompts                                 │
│  ├─ Run SAM 2.1 for segmentation masks                                      │
│  ├─ Project detections to 3D positions                                      │
│  ├─ Extract raw dimensions from masks                                       │
│  └─ Output: detections[] with 3D positions and dimensions                   │
│                                                                              │
│  Stage 7: Snap to Standards (85%)                                           │
│  ├─ Match raw dimensions to standard sizes                                  │
│  ├─ Calculate confidence scores                                             │
│  ├─ Flag items outside tolerance                                            │
│  └─ Output: snapped_dimensions[], flags[]                                   │
│                                                                              │
│  Stage 8: Floor Plan Generation (95%)                                       │
│  ├─ Generate 2D floor plan SVG                                              │
│  ├─ Generate preview PNG                                                    │
│  ├─ Generate measurements JSON                                              │
│  └─ Output: floor_plan.svg, preview.png, measurements.json                  │
│                                                                              │
│  Stage 9: Upload Results (100%)                                             │
│  ├─ Upload all outputs to Supabase Storage                                  │
│  ├─ Update job status to completed                                          │
│  └─ Notify client via webhook (optional)                                    │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

### 4.2 Stage 1: Frame Extraction

```python
# pipeline/stages/frame_extraction.py

import cv2
import numpy as np
from dataclasses import dataclass
from pathlib import Path

@dataclass
class ExtractedFrame:
    index: int
    timestamp: float
    image: np.ndarray
    quality_score: float
    pose: Optional[CameraPose]

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
        poses: list[CameraPose]
    ) -> list[ExtractedFrame]:
        """Extract high-quality keyframes from video."""

        cap = cv2.VideoCapture(str(video_path))
        fps = cap.get(cv2.CAP_PROP_FPS)
        frame_interval = int(fps / self.target_fps)

        frames = []
        prev_frame = None
        frame_idx = 0

        while True:
            ret, frame = cap.read()
            if not ret:
                break

            # Sample at target FPS
            if frame_idx % frame_interval != 0:
                frame_idx += 1
                continue

            # Check blur
            blur_score = self._calculate_blur(frame)
            if blur_score < self.blur_threshold:
                frame_idx += 1
                continue

            # Check similarity to previous frame
            if prev_frame is not None:
                similarity = self._calculate_ssim(prev_frame, frame)
                if similarity > self.similarity_threshold:
                    frame_idx += 1
                    continue

            # Get corresponding pose
            timestamp = frame_idx / fps
            pose = self._find_nearest_pose(timestamp, poses)

            frames.append(ExtractedFrame(
                index=len(frames),
                timestamp=timestamp,
                image=frame,
                quality_score=blur_score,
                pose=pose
            ))

            prev_frame = frame
            frame_idx += 1

            if len(frames) >= self.max_frames:
                break

        cap.release()

        if len(frames) < self.min_frames:
            raise PipelineError(
                f"Insufficient frames: {len(frames)} < {self.min_frames}"
            )

        return frames

    def _calculate_blur(self, image: np.ndarray) -> float:
        """Calculate Laplacian variance as blur metric."""
        gray = cv2.cvtColor(image, cv2.COLOR_BGR2GRAY)
        return cv2.Laplacian(gray, cv2.CV_64F).var()

    def _calculate_ssim(
        self,
        img1: np.ndarray,
        img2: np.ndarray
    ) -> float:
        """Calculate structural similarity index."""
        from skimage.metrics import structural_similarity
        gray1 = cv2.cvtColor(img1, cv2.COLOR_BGR2GRAY)
        gray2 = cv2.cvtColor(img2, cv2.COLOR_BGR2GRAY)
        # Resize for faster comparison
        gray1 = cv2.resize(gray1, (256, 256))
        gray2 = cv2.resize(gray2, (256, 256))
        return structural_similarity(gray1, gray2)

    def _find_nearest_pose(
        self,
        timestamp: float,
        poses: list[CameraPose]
    ) -> Optional[CameraPose]:
        """Find pose closest to given timestamp."""
        if not poses:
            return None
        return min(poses, key=lambda p: abs(p.timestamp - timestamp))
```

### 4.3 Stage 2: Depth Estimation (Depth Pro)

```python
# pipeline/stages/depth_estimation.py

import torch
import numpy as np
from dataclasses import dataclass
from depth_pro import create_model_and_transforms, load_rgb

@dataclass
class DepthResult:
    frame_index: int
    depth_map: np.ndarray      # Metric depth in meters
    focal_length_px: float     # Estimated focal length
    confidence_map: np.ndarray # Per-pixel confidence

class DepthProEstimator:
    def __init__(self, device: str = "cuda"):
        self.device = device
        self.model = None
        self.transform = None

    def load_model(self):
        """Load Depth Pro model (call once at worker startup)."""
        self.model, self.transform = create_model_and_transforms(
            device=self.device,
            precision=torch.float16  # Use FP16 for speed
        )
        self.model.eval()

    @torch.inference_mode()
    def estimate(
        self,
        frames: list[ExtractedFrame],
        progress_callback: Optional[Callable] = None
    ) -> list[DepthResult]:
        """Estimate metric depth for all frames."""

        results = []

        for i, frame in enumerate(frames):
            # Convert BGR to RGB
            rgb = cv2.cvtColor(frame.image, cv2.COLOR_BGR2RGB)

            # Transform for model
            image_tensor = self.transform(rgb).to(self.device)

            # Run inference
            prediction = self.model.infer(image_tensor)

            results.append(DepthResult(
                frame_index=frame.index,
                depth_map=prediction["depth"].cpu().numpy(),
                focal_length_px=prediction["focallength_px"].item(),
                confidence_map=prediction.get("confidence", np.ones_like(prediction["depth"].cpu().numpy()))
            ))

            if progress_callback:
                progress_callback(i + 1, len(frames))

        return results
```

### 4.4 Stage 3: 3D Reconstruction (MASt3R-SfM)

```python
# pipeline/stages/reconstruction.py

import torch
import numpy as np
from dataclasses import dataclass
from mast3r.model import AsymmetricMASt3R
from mast3r.fast_nn import fast_reciprocal_NNs
from mast3r.cloud_opt import global_aligner, GlobalAlignerMode

@dataclass
class ReconstructionResult:
    point_cloud: np.ndarray        # (N, 3) XYZ points in meters
    point_colors: np.ndarray       # (N, 3) RGB colors
    point_confidence: np.ndarray   # (N,) confidence scores
    camera_poses: list[np.ndarray] # 4x4 transform matrices
    scale_factor: float            # Metric scale

class MASt3RReconstructor:
    def __init__(self, device: str = "cuda"):
        self.device = device
        self.model = None

    def load_model(self):
        """Load MASt3R model."""
        self.model = AsymmetricMASt3R.from_pretrained(
            "naver/MASt3R_ViTLarge_BaseDecoder_512_catmlpdpt_metric"
        ).to(self.device)
        self.model.eval()

    @torch.inference_mode()
    def reconstruct(
        self,
        frames: list[ExtractedFrame],
        depth_results: list[DepthResult],
        progress_callback: Optional[Callable] = None
    ) -> ReconstructionResult:
        """Reconstruct 3D scene from frames."""

        # Prepare image pairs for MASt3R
        images = [f.image for f in frames]

        # Run MASt3R on overlapping pairs
        pairs = self._generate_pairs(len(images))

        all_pts3d = []
        all_conf = []

        for i, (idx1, idx2) in enumerate(pairs):
            img1 = self._prepare_image(images[idx1])
            img2 = self._prepare_image(images[idx2])

            # MASt3R inference
            output = self.model({"img0": img1, "img1": img2})

            pts3d_1 = output["pts3d"][0]  # 3D points from view 1
            pts3d_2 = output["pts3d"][1]  # 3D points from view 2
            conf_1 = output["conf"][0]
            conf_2 = output["conf"][1]

            all_pts3d.extend([pts3d_1, pts3d_2])
            all_conf.extend([conf_1, conf_2])

            if progress_callback:
                progress_callback(i + 1, len(pairs))

        # Global alignment
        scene = global_aligner(
            all_pts3d,
            all_conf,
            mode=GlobalAlignerMode.PointCloudOptimizer
        )

        # Extract aligned point cloud
        pts3d, colors, confidence = scene.get_dense_pts3d()
        poses = scene.get_im_poses()

        # Apply metric scale from Depth Pro
        scale = self._compute_metric_scale(depth_results, pts3d, frames)
        pts3d_metric = pts3d * scale

        return ReconstructionResult(
            point_cloud=pts3d_metric.cpu().numpy(),
            point_colors=colors.cpu().numpy(),
            point_confidence=confidence.cpu().numpy(),
            camera_poses=[p.cpu().numpy() for p in poses],
            scale_factor=scale
        )

    def _generate_pairs(self, n_images: int) -> list[tuple[int, int]]:
        """Generate overlapping image pairs."""
        pairs = []
        # Sequential pairs
        for i in range(n_images - 1):
            pairs.append((i, i + 1))
        # Skip-1 pairs for better connectivity
        for i in range(n_images - 2):
            pairs.append((i, i + 2))
        return pairs

    def _compute_metric_scale(
        self,
        depth_results: list[DepthResult],
        pts3d: torch.Tensor,
        frames: list[ExtractedFrame]
    ) -> float:
        """Compute scale factor using Depth Pro metric depths."""
        # Use median depth from Depth Pro as reference
        depth_pro_depths = []
        mast3r_depths = []

        for i, (depth_result, frame) in enumerate(zip(depth_results, frames)):
            # Sample center region depths
            h, w = depth_result.depth_map.shape
            center_depth = depth_result.depth_map[h//3:2*h//3, w//3:2*w//3]
            depth_pro_depths.append(np.median(center_depth))

            # Get corresponding MASt3R depth
            # (simplified - actual implementation would use camera projection)
            mast3r_depth = np.median(np.linalg.norm(pts3d[i].cpu().numpy(), axis=-1))
            mast3r_depths.append(mast3r_depth)

        # Compute scale as ratio of medians
        scale = np.median(depth_pro_depths) / np.median(mast3r_depths)
        return float(scale)
```

### 4.5 Stage 4: Scale Validation

```python
# pipeline/stages/scale_validation.py

from dataclasses import dataclass

@dataclass
class ScaleValidationResult:
    validated_scale: float
    confidence: str  # "high", "medium", "low"
    reference_object: str
    measured_height_inches: float
    expected_height_inches: float
    deviation_inches: float

class ScaleValidator:
    # Standard heights in inches
    REFERENCE_HEIGHTS = {
        "base_cabinet": 36.0,
        "countertop": 36.0,
        "upper_cabinet_bottom": 54.0,  # 18" above countertop
        "standard_door": 80.0,
        "standard_window_sill": 36.0
    }

    def validate(
        self,
        reconstruction: ReconstructionResult,
        detections: list[Detection]
    ) -> ScaleValidationResult:
        """Validate and refine scale using detected objects."""

        # Find base cabinet detections
        base_cabinets = [d for d in detections if d.category == "base_cabinet"]

        if not base_cabinets:
            # Fall back to countertop or other references
            return self._fallback_validation(reconstruction, detections)

        # Measure cabinet heights in point cloud
        measured_heights = []
        for cabinet in base_cabinets:
            height = self._measure_object_height(
                reconstruction.point_cloud,
                cabinet.bbox_3d
            )
            measured_heights.append(height)

        median_height = np.median(measured_heights)
        expected_height = self.REFERENCE_HEIGHTS["base_cabinet"]

        # Calculate deviation
        deviation = abs(median_height - expected_height)

        # Determine confidence
        if deviation <= 1.0:  # Within 1 inch
            confidence = "high"
            scale_adjustment = 1.0
        elif deviation <= 3.0:  # Within 3 inches
            confidence = "medium"
            scale_adjustment = expected_height / median_height
        else:
            confidence = "low"
            scale_adjustment = expected_height / median_height

        # Apply adjustment if needed
        final_scale = reconstruction.scale_factor * scale_adjustment

        return ScaleValidationResult(
            validated_scale=final_scale,
            confidence=confidence,
            reference_object="base_cabinet",
            measured_height_inches=median_height,
            expected_height_inches=expected_height,
            deviation_inches=deviation
        )
```

### 4.6 Stage 5: Wall Detection

```python
# pipeline/stages/wall_detection.py

import numpy as np
from sklearn.linear_model import RANSACRegressor
from dataclasses import dataclass

@dataclass
class Wall:
    start: tuple[float, float]  # (x, y) in inches
    end: tuple[float, float]
    length: float
    angle: float  # degrees
    confidence: float

@dataclass
class WallDetectionResult:
    walls: list[Wall]
    corners: list[tuple[float, float]]
    room_bounds: tuple[float, float, float, float]  # (min_x, min_y, max_x, max_y)

class WallDetector:
    def __init__(
        self,
        grid_resolution: float = 1.0,  # inches
        ransac_threshold: float = 2.0,  # inches
        min_wall_length: float = 24.0,  # inches
        angle_snap_threshold: float = 5.0  # degrees
    ):
        self.grid_resolution = grid_resolution
        self.ransac_threshold = ransac_threshold
        self.min_wall_length = min_wall_length
        self.angle_snap_threshold = angle_snap_threshold

    def detect(
        self,
        point_cloud: np.ndarray,
        scale_factor: float
    ) -> WallDetectionResult:
        """Detect walls from bird's eye view of point cloud."""

        # Convert to inches
        points_inches = point_cloud * 39.3701 * scale_factor

        # Project to bird's eye view (X-Z plane, Y is up)
        bev_points = points_inches[:, [0, 2]]  # X, Z

        # Create occupancy grid
        grid = self._create_occupancy_grid(bev_points)

        # Extract wall points (high density regions)
        wall_points = self._extract_wall_points(grid)

        # RANSAC line detection
        lines = self._detect_lines_ransac(wall_points)

        # Snap to 90-degree angles
        snapped_lines = self._snap_angles(lines)

        # Merge collinear segments
        merged_lines = self._merge_collinear(snapped_lines)

        # Find corners (line intersections)
        corners = self._find_corners(merged_lines)

        # Convert to Wall objects
        walls = []
        for line in merged_lines:
            walls.append(Wall(
                start=line["start"],
                end=line["end"],
                length=line["length"],
                angle=line["angle"],
                confidence=line["confidence"]
            ))

        # Calculate room bounds
        all_points = [(w.start[0], w.start[1]) for w in walls]
        all_points += [(w.end[0], w.end[1]) for w in walls]
        xs = [p[0] for p in all_points]
        ys = [p[1] for p in all_points]

        return WallDetectionResult(
            walls=walls,
            corners=corners,
            room_bounds=(min(xs), min(ys), max(xs), max(ys))
        )

    def _detect_lines_ransac(
        self,
        points: np.ndarray
    ) -> list[dict]:
        """Detect lines using iterative RANSAC."""
        lines = []
        remaining_points = points.copy()

        while len(remaining_points) > 20:
            # Fit line with RANSAC
            ransac = RANSACRegressor(
                residual_threshold=self.ransac_threshold,
                min_samples=10
            )

            try:
                X = remaining_points[:, 0].reshape(-1, 1)
                y = remaining_points[:, 1]
                ransac.fit(X, y)

                inlier_mask = ransac.inlier_mask_
                inliers = remaining_points[inlier_mask]

                if len(inliers) < 10:
                    break

                # Extract line segment
                line = self._extract_line_segment(inliers)

                if line["length"] >= self.min_wall_length:
                    lines.append(line)

                # Remove inliers
                remaining_points = remaining_points[~inlier_mask]

            except Exception:
                break

        return lines

    def _snap_angles(self, lines: list[dict]) -> list[dict]:
        """Snap line angles to 0, 90, 180, 270 degrees."""
        snapped = []
        for line in lines:
            angle = line["angle"]

            # Find nearest cardinal direction
            cardinal = round(angle / 90) * 90
            if abs(angle - cardinal) <= self.angle_snap_threshold:
                line["angle"] = cardinal % 360
                line["snapped"] = True
            else:
                line["snapped"] = False

            snapped.append(line)

        return snapped
```

### 4.7 Stage 6: Object Detection (Grounded SAM 2)

```python
# pipeline/stages/object_detection.py

import torch
import numpy as np
from dataclasses import dataclass
from groundingdino.util.inference import load_model, predict
from sam2.build_sam import build_sam2
from sam2.sam2_image_predictor import SAM2ImagePredictor

@dataclass
class Detection:
    category: str
    confidence: float
    bbox_2d: tuple[int, int, int, int]  # x1, y1, x2, y2
    mask: np.ndarray                     # Binary mask
    bbox_3d: Optional[np.ndarray]        # 3D bounding box
    position_3d: Optional[tuple[float, float, float]]
    dimensions: Optional[tuple[float, float, float]]  # width, height, depth in inches

KITCHEN_PROMPTS = {
    "appliances": "refrigerator. range. cooktop. oven. microwave. dishwasher. range hood. sink.",
    "cabinets": "base cabinet. upper cabinet. tall cabinet. pantry cabinet. corner cabinet.",
    "openings": "window. door. doorway.",
    "other": "island. peninsula. countertop."
}

class GroundedSAMDetector:
    def __init__(self, device: str = "cuda"):
        self.device = device
        self.grounding_model = None
        self.sam_predictor = None

    def load_models(self):
        """Load Grounding DINO and SAM 2 models."""
        # Grounding DINO
        self.grounding_model = load_model(
            "groundingdino/config/GroundingDINO_SwinT_OGC.py",
            "weights/groundingdino_swint_ogc.pth",
            device=self.device
        )

        # SAM 2
        sam2_model = build_sam2("sam2_hiera_l.yaml", "weights/sam2_hiera_large.pt")
        self.sam_predictor = SAM2ImagePredictor(sam2_model)

    def detect(
        self,
        frames: list[ExtractedFrame],
        reconstruction: ReconstructionResult,
        progress_callback: Optional[Callable] = None
    ) -> list[Detection]:
        """Detect kitchen objects in all frames."""

        all_detections = []

        # Combine all prompts
        full_prompt = " ".join(KITCHEN_PROMPTS.values())

        for i, frame in enumerate(frames):
            # Convert BGR to RGB
            image = cv2.cvtColor(frame.image, cv2.COLOR_BGR2RGB)

            # Grounding DINO detection
            boxes, logits, phrases = predict(
                model=self.grounding_model,
                image=image,
                caption=full_prompt,
                box_threshold=0.35,
                text_threshold=0.25
            )

            # SAM 2 segmentation
            self.sam_predictor.set_image(image)

            for box, logit, phrase in zip(boxes, logits, phrases):
                # Get SAM mask
                masks, scores, _ = self.sam_predictor.predict(
                    box=box.cpu().numpy(),
                    multimask_output=False
                )
                mask = masks[0]

                # Project to 3D
                position_3d, dimensions = self._project_to_3d(
                    mask=mask,
                    frame=frame,
                    reconstruction=reconstruction
                )

                detection = Detection(
                    category=self._normalize_category(phrase),
                    confidence=logit.item(),
                    bbox_2d=tuple(box.int().tolist()),
                    mask=mask,
                    bbox_3d=None,  # Computed later
                    position_3d=position_3d,
                    dimensions=dimensions
                )

                all_detections.append(detection)

            if progress_callback:
                progress_callback(i + 1, len(frames))

        # Merge duplicate detections across frames
        merged = self._merge_detections(all_detections)

        return merged

    def _normalize_category(self, phrase: str) -> str:
        """Normalize detected phrase to standard category."""
        phrase = phrase.lower().strip()

        category_mapping = {
            "refrigerator": "refrigerator",
            "fridge": "refrigerator",
            "range": "range",
            "stove": "range",
            "oven": "oven",
            "cooktop": "cooktop",
            "dishwasher": "dishwasher",
            "microwave": "microwave",
            "range hood": "hood",
            "hood": "hood",
            "sink": "sink",
            "base cabinet": "base_cabinet",
            "upper cabinet": "upper_cabinet",
            "wall cabinet": "upper_cabinet",
            "tall cabinet": "tall_cabinet",
            "pantry": "pantry",
            "window": "window",
            "door": "door",
            "island": "island",
            "peninsula": "peninsula",
            "countertop": "countertop"
        }

        for key, value in category_mapping.items():
            if key in phrase:
                return value

        return phrase.replace(" ", "_")

    def _project_to_3d(
        self,
        mask: np.ndarray,
        frame: ExtractedFrame,
        reconstruction: ReconstructionResult
    ) -> tuple[Optional[tuple], Optional[tuple]]:
        """Project 2D detection to 3D position and dimensions."""
        # Implementation would use depth maps and camera poses
        # to back-project mask pixels to 3D
        pass
```

### 4.8 Stage 7: Snap to Standards

```python
# pipeline/stages/snap_to_standards.py

from dataclasses import dataclass
from typing import Optional

@dataclass
class SnappedMeasurement:
    raw_value: float
    snapped_value: float
    confidence: str  # "high", "medium", "low"
    deviation: float
    needs_review: bool

# Standard sizes in inches
STANDARD_SIZES = {
    "range": [30, 36, 48, 60],
    "refrigerator": [30, 33, 36, 42, 48],
    "dishwasher": [18, 24],
    "hood": [30, 36, 42, 48],
    "sink_base": [30, 33, 36, 42],
    "base_cabinet": [9, 12, 15, 18, 21, 24, 27, 30, 33, 36, 42],
    "upper_cabinet": [9, 12, 15, 18, 24, 30, 33, 36, 42],
    "tall_cabinet": [18, 24, 30, 36],
    "pantry": [18, 24, 30, 36],
    "window": [24, 30, 36, 42, 48, 60, 72],
    "door": [24, 28, 30, 32, 34, 36],
}

class StandardSnapper:
    def __init__(
        self,
        high_confidence_threshold: float = 2.0,  # inches
        medium_confidence_threshold: float = 4.0,  # inches
        detection_confidence_weight: float = 0.5
    ):
        self.high_threshold = high_confidence_threshold
        self.medium_threshold = medium_confidence_threshold
        self.det_conf_weight = detection_confidence_weight

    def snap(
        self,
        detections: list[Detection]
    ) -> list[tuple[Detection, SnappedMeasurement]]:
        """Snap all detection dimensions to standard sizes."""

        results = []

        for detection in detections:
            if detection.dimensions is None:
                continue

            width = detection.dimensions[0]  # Primary dimension to snap
            category = detection.category

            if category not in STANDARD_SIZES:
                # Unknown category - keep raw measurement
                results.append((detection, SnappedMeasurement(
                    raw_value=width,
                    snapped_value=width,
                    confidence="low",
                    deviation=0,
                    needs_review=True
                )))
                continue

            # Find nearest standard size
            standards = STANDARD_SIZES[category]
            nearest = min(standards, key=lambda x: abs(x - width))
            deviation = abs(nearest - width)

            # Calculate confidence
            if deviation <= self.high_threshold and detection.confidence > 0.8:
                confidence = "high"
                needs_review = False
            elif deviation <= self.medium_threshold and detection.confidence > 0.6:
                confidence = "medium"
                needs_review = False
            else:
                confidence = "low"
                needs_review = True

            results.append((detection, SnappedMeasurement(
                raw_value=width,
                snapped_value=nearest,
                confidence=confidence,
                deviation=deviation,
                needs_review=needs_review
            )))

        return results
```

### 4.9 Stage 8: Floor Plan Generation

```python
# pipeline/stages/floor_plan.py

import svgwrite
from dataclasses import dataclass
from PIL import Image
import io

@dataclass
class FloorPlanOutput:
    svg_content: str
    png_bytes: bytes
    json_data: dict

class FloorPlanGenerator:
    def __init__(
        self,
        scale: float = 0.5,  # inches to pixels
        padding: int = 50,
        wall_thickness: int = 4,
        cabinet_color: str = "#8B4513",
        appliance_color: str = "#4682B4",
        wall_color: str = "#333333"
    ):
        self.scale = scale
        self.padding = padding
        self.wall_thickness = wall_thickness
        self.cabinet_color = cabinet_color
        self.appliance_color = appliance_color
        self.wall_color = wall_color

    def generate(
        self,
        walls: WallDetectionResult,
        detections: list[tuple[Detection, SnappedMeasurement]],
        scale_validation: ScaleValidationResult
    ) -> FloorPlanOutput:
        """Generate floor plan in SVG, PNG, and JSON formats."""

        # Calculate canvas size
        bounds = walls.room_bounds
        width = (bounds[2] - bounds[0]) * self.scale + 2 * self.padding
        height = (bounds[3] - bounds[1]) * self.scale + 2 * self.padding

        # Create SVG
        dwg = svgwrite.Drawing(size=(width, height))

        # Add walls
        for wall in walls.walls:
            self._draw_wall(dwg, wall, bounds)

        # Add detections
        for detection, measurement in detections:
            self._draw_detection(dwg, detection, measurement, bounds)

        # Add dimensions
        self._add_dimensions(dwg, walls, detections, bounds)

        # Add legend
        self._add_legend(dwg, width, height)

        # Generate outputs
        svg_content = dwg.tostring()
        png_bytes = self._svg_to_png(svg_content)
        json_data = self._generate_json(walls, detections, scale_validation)

        return FloorPlanOutput(
            svg_content=svg_content,
            png_bytes=png_bytes,
            json_data=json_data
        )

    def _generate_json(
        self,
        walls: WallDetectionResult,
        detections: list[tuple[Detection, SnappedMeasurement]],
        scale_validation: ScaleValidationResult
    ) -> dict:
        """Generate JSON representation of floor plan."""
        return {
            "version": "1.0",
            "scale_confidence": scale_validation.confidence,
            "room": {
                "bounds": {
                    "min_x": walls.room_bounds[0],
                    "min_y": walls.room_bounds[1],
                    "max_x": walls.room_bounds[2],
                    "max_y": walls.room_bounds[3]
                },
                "walls": [
                    {
                        "start": {"x": w.start[0], "y": w.start[1]},
                        "end": {"x": w.end[0], "y": w.end[1]},
                        "length_inches": w.length,
                        "confidence": w.confidence
                    }
                    for w in walls.walls
                ],
                "corners": [
                    {"x": c[0], "y": c[1]}
                    for c in walls.corners
                ]
            },
            "objects": [
                {
                    "category": det.category,
                    "position": {
                        "x": det.position_3d[0] if det.position_3d else None,
                        "y": det.position_3d[1] if det.position_3d else None
                    },
                    "dimensions": {
                        "width_raw": meas.raw_value,
                        "width_snapped": meas.snapped_value,
                        "unit": "inches"
                    },
                    "confidence": meas.confidence,
                    "needs_review": meas.needs_review,
                    "detection_confidence": det.confidence
                }
                for det, meas in detections
            ],
            "flags": [
                {
                    "category": det.category,
                    "issue": f"Measurement deviation: {meas.deviation:.1f} inches",
                    "raw_value": meas.raw_value,
                    "snapped_value": meas.snapped_value
                }
                for det, meas in detections
                if meas.needs_review
            ]
        }
```

---

## 5. API Specification

### 5.1 Endpoints

#### Create Processing Job

```
POST /api/v1/jobs
Authorization: Bearer <supabase_anon_key>
Content-Type: application/json

Request:
{
    "video_url": "https://storage.supabase.co/.../video.mp4",
    "poses_url": "https://storage.supabase.co/.../poses.json",
    "metadata": {
        "device_model": "iPhone 14",
        "showroom_id": "uuid",
        "project_id": "uuid"
    }
}

Response:
{
    "job_id": "uuid",
    "status": "queued",
    "created_at": "2025-02-05T10:00:00Z",
    "estimated_duration_seconds": 45
}
```

#### Get Job Status

```
GET /api/v1/jobs/{job_id}
Authorization: Bearer <supabase_anon_key>

Response:
{
    "job_id": "uuid",
    "status": "processing",  // queued | processing | completed | failed
    "progress": 0.65,
    "stage": "detecting_objects",
    "stage_message": "Finding cabinets and appliances...",
    "created_at": "2025-02-05T10:00:00Z",
    "started_at": "2025-02-05T10:00:05Z",
    "estimated_completion": "2025-02-05T10:00:50Z"
}
```

#### Get Job Results

```
GET /api/v1/jobs/{job_id}/results
Authorization: Bearer <supabase_anon_key>

Response:
{
    "job_id": "uuid",
    "status": "completed",
    "results": {
        "floor_plan_svg_url": "https://storage.supabase.co/.../floor_plan.svg",
        "floor_plan_png_url": "https://storage.supabase.co/.../floor_plan.png",
        "measurements_json_url": "https://storage.supabase.co/.../measurements.json",
        "scale_confidence": "high",
        "flags_count": 2,
        "objects_count": 15
    },
    "processing_time_seconds": 42,
    "completed_at": "2025-02-05T10:00:47Z"
}
```

### 5.2 Webhook (Optional)

```
POST <client_webhook_url>
Content-Type: application/json

{
    "event": "job.completed",
    "job_id": "uuid",
    "status": "completed",
    "results_url": "/api/v1/jobs/{job_id}/results"
}
```

---

## 6. Data Models

### 6.1 Database Schema (Supabase)

```sql
-- Processing jobs table
CREATE TABLE processing_jobs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    showroom_id UUID REFERENCES showrooms(id),
    project_id UUID REFERENCES projects(id),

    -- Input
    video_url TEXT NOT NULL,
    poses_url TEXT,
    metadata JSONB DEFAULT '{}',

    -- Status
    status TEXT DEFAULT 'queued' CHECK (status IN ('queued', 'processing', 'completed', 'failed')),
    progress FLOAT DEFAULT 0,
    stage TEXT,
    error_message TEXT,

    -- Results
    floor_plan_svg_url TEXT,
    floor_plan_png_url TEXT,
    measurements_json_url TEXT,
    scale_confidence TEXT,
    flags_count INT DEFAULT 0,

    -- Timing
    created_at TIMESTAMPTZ DEFAULT NOW(),
    started_at TIMESTAMPTZ,
    completed_at TIMESTAMPTZ,
    processing_time_ms INT,

    -- Metadata
    worker_id TEXT,
    retry_count INT DEFAULT 0
);

-- Index for status queries
CREATE INDEX idx_jobs_status ON processing_jobs(status, created_at);

-- RLS policies
ALTER TABLE processing_jobs ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Showroom owners can view their jobs"
ON processing_jobs FOR SELECT
USING (showroom_id IN (
    SELECT id FROM showrooms WHERE owner_id = auth.uid()
));
```

### 6.2 Measurements JSON Schema

```json
{
    "$schema": "http://json-schema.org/draft-07/schema#",
    "type": "object",
    "properties": {
        "version": {"type": "string"},
        "scale_confidence": {"enum": ["high", "medium", "low"]},
        "room": {
            "type": "object",
            "properties": {
                "bounds": {
                    "type": "object",
                    "properties": {
                        "min_x": {"type": "number"},
                        "min_y": {"type": "number"},
                        "max_x": {"type": "number"},
                        "max_y": {"type": "number"}
                    }
                },
                "walls": {
                    "type": "array",
                    "items": {
                        "type": "object",
                        "properties": {
                            "start": {"type": "object"},
                            "end": {"type": "object"},
                            "length_inches": {"type": "number"},
                            "confidence": {"type": "number"}
                        }
                    }
                }
            }
        },
        "objects": {
            "type": "array",
            "items": {
                "type": "object",
                "properties": {
                    "category": {"type": "string"},
                    "position": {"type": "object"},
                    "dimensions": {
                        "type": "object",
                        "properties": {
                            "width_raw": {"type": "number"},
                            "width_snapped": {"type": "number"},
                            "unit": {"const": "inches"}
                        }
                    },
                    "confidence": {"enum": ["high", "medium", "low"]},
                    "needs_review": {"type": "boolean"}
                }
            }
        },
        "flags": {"type": "array"}
    }
}
```

---

## 7. Error Handling

### 7.1 Error Categories

| Category | HTTP Code | Retry | User Action |
|----------|-----------|-------|-------------|
| `invalid_video` | 400 | No | Re-record scan |
| `insufficient_frames` | 400 | No | Longer/steadier scan |
| `processing_timeout` | 504 | Yes (auto) | Wait for retry |
| `model_error` | 500 | Yes (auto) | Contact support |
| `storage_error` | 500 | Yes (auto) | Wait for retry |

### 7.2 Error Response Format

```json
{
    "error": {
        "code": "insufficient_frames",
        "message": "Could not extract enough high-quality frames from video",
        "details": {
            "frames_extracted": 15,
            "frames_required": 30,
            "suggestion": "Please record a longer scan (at least 60 seconds) with steady movement"
        },
        "retry_possible": false
    }
}
```

### 7.3 Retry Strategy

```python
RETRY_CONFIG = {
    "max_retries": 3,
    "initial_delay_seconds": 5,
    "backoff_multiplier": 2,
    "max_delay_seconds": 60,
    "retryable_errors": [
        "processing_timeout",
        "model_error",
        "storage_error",
        "gpu_oom"  # Out of memory - retry with lower batch size
    ]
}
```

---

## 8. Performance Requirements

### 8.1 Target Metrics

| Metric | Target | Notes |
|--------|--------|-------|
| End-to-end latency | < 60 seconds | From upload complete to results ready |
| Frame extraction | < 5 seconds | For 90-second video |
| Depth estimation | < 15 seconds | 100 frames on A10G |
| 3D reconstruction | < 20 seconds | MASt3R-SfM |
| Object detection | < 10 seconds | Grounding DINO + SAM2 |
| Floor plan generation | < 5 seconds | SVG + PNG + JSON |

### 8.2 Scaling Strategy

```
Load Level          Workers    GPU Type    Est. Capacity
────────────────────────────────────────────────────────
Light (MVP)         1          A10G        ~50 jobs/hour
Medium              2          A10G        ~100 jobs/hour
High                4          L4          ~200 jobs/hour
Enterprise          8+         L4          ~400+ jobs/hour
```

### 8.3 Cost Estimates

| Component | Cost/Month (Light) | Cost/Month (Medium) |
|-----------|-------------------|---------------------|
| GPU Server (A10G) | ~$500 | ~$1,000 |
| Storage (500GB) | ~$50 | ~$100 |
| Bandwidth | ~$50 | ~$100 |
| **Total** | **~$600** | **~$1,200** |

Cost per scan: ~$0.05-0.10 (depending on volume)

---

## 9. Implementation Plan

### Phase 1: iOS Client Updates (Week 1)
- [ ] Create `ServerPipelineClient.swift`
- [ ] Create `CapturePackage.swift` model
- [ ] Update `AIFlowCoordinator.swift` to use server pipeline
- [ ] Update `ProcessingView` for server status polling
- [ ] Add upload progress UI

### Phase 2: Server Infrastructure (Week 1-2)
- [ ] Set up GPU server (AWS/GCP/RunPod)
- [ ] Install Python environment with all models
- [ ] Create FastAPI application structure
- [ ] Set up Redis job queue
- [ ] Create Supabase Edge Function for job creation

### Phase 3: Pipeline Stages (Week 2-3)
- [ ] Implement frame extraction stage
- [ ] Implement Depth Pro integration
- [ ] Implement MASt3R-SfM integration
- [ ] Implement scale validation
- [ ] Implement wall detection
- [ ] Implement Grounded SAM 2 integration
- [ ] Implement snap-to-standards
- [ ] Implement floor plan generation

### Phase 4: Integration & Testing (Week 3-4)
- [ ] End-to-end integration testing
- [ ] Accuracy validation against ground truth
- [ ] Performance optimization
- [ ] Error handling and retry logic
- [ ] Monitoring and logging

### Phase 5: Deployment (Week 4)
- [ ] Deploy to production GPU server
- [ ] Configure auto-scaling (if needed)
- [ ] Set up monitoring dashboards
- [ ] Deploy iOS app update
- [ ] User acceptance testing

---

## 10. Verification & Testing

### 10.1 Unit Tests

```python
# tests/test_frame_extraction.py
def test_blur_detection():
    extractor = FrameExtractor()
    blurry_frame = create_blurry_image()
    sharp_frame = create_sharp_image()

    assert extractor._calculate_blur(blurry_frame) < 100
    assert extractor._calculate_blur(sharp_frame) > 100

# tests/test_snap_to_standards.py
def test_cabinet_snapping():
    snapper = StandardSnapper()

    # 23.7" should snap to 24"
    result = snapper._snap_single(23.7, "base_cabinet", 0.9)
    assert result.snapped_value == 24
    assert result.confidence == "high"

    # 28" should flag for review (not standard)
    result = snapper._snap_single(28, "base_cabinet", 0.9)
    assert result.needs_review == True
```

### 10.2 Integration Tests

```python
# tests/test_pipeline_integration.py
async def test_full_pipeline():
    # Use sample kitchen video
    video_path = "tests/fixtures/sample_kitchen.mp4"
    poses_path = "tests/fixtures/sample_poses.json"

    pipeline = KitchenPipeline()
    result = await pipeline.process(video_path, poses_path)

    # Verify outputs exist
    assert result.floor_plan_svg is not None
    assert result.measurements_json is not None

    # Verify reasonable detection counts
    assert 2 <= len(result.walls) <= 6
    assert len(result.detections) > 0
```

### 10.3 Accuracy Validation

```python
# tests/test_accuracy.py
def test_measurement_accuracy():
    """Compare against ground truth measurements."""

    ground_truth = {
        "wall_1_length": 144,  # 12 feet
        "refrigerator_width": 36,
        "range_width": 30,
        "base_cabinet_1_width": 24
    }

    result = run_pipeline("tests/fixtures/measured_kitchen.mp4")

    for key, expected in ground_truth.items():
        actual = result.get_measurement(key)
        error = abs(actual - expected)
        assert error <= 2, f"{key}: expected {expected}, got {actual}"
```

### 10.4 End-to-End Test Procedure

1. **Capture Test**: Record 60-second kitchen scan on iPhone
2. **Upload Test**: Verify video uploads successfully
3. **Processing Test**: Monitor job progress through all stages
4. **Results Test**: Download and verify floor plan accuracy
5. **Review Test**: Check flagged items UI in dashboard

---

## Files to Create/Modify

### iOS (Create)
- `ios/cabinetscan/cabinetscan/Features/AIFlow/Server/ServerPipelineClient.swift`
- `ios/cabinetscan/cabinetscan/Features/AIFlow/Server/CapturePackage.swift`
- `ios/cabinetscan/cabinetscan/Features/AIFlow/Server/PipelineModels.swift`

### iOS (Modify)
- `ios/cabinetscan/cabinetscan/Features/AIFlow/Entry/AIFlowCoordinator.swift`
- `ios/cabinetscan/cabinetscan/Features/AIFlow/Screens/ProcessingView.swift`

### Server (Create)
- `server/pipeline/main.py` - FastAPI app
- `server/pipeline/stages/frame_extraction.py`
- `server/pipeline/stages/depth_estimation.py`
- `server/pipeline/stages/reconstruction.py`
- `server/pipeline/stages/scale_validation.py`
- `server/pipeline/stages/wall_detection.py`
- `server/pipeline/stages/object_detection.py`
- `server/pipeline/stages/snap_to_standards.py`
- `server/pipeline/stages/floor_plan.py`
- `server/pipeline/worker.py` - Job worker
- `server/pipeline/models.py` - Data models
- `server/requirements.txt`
- `server/Dockerfile`

### Supabase (Create)
- `supabase/migrations/xxx_add_processing_jobs.sql`
- `supabase/functions/create-processing-job/index.ts`
- `supabase/functions/get-job-status/index.ts`

---

## 11. Refined 2.5D Floor Plan Approach (February 2026)

### Key Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| **Server Hosting** | RunPod/Modal | Pay-per-use, easy setup, cost-effective for initial volume |
| **Depth Model** | Depth Pro | Metric depth (not relative like DepthAnythingV2) |
| **Processing Time** | 2-5 minutes | Allows full pipeline with maximum accuracy |
| **Skip MASt3R** | Yes | 2.5D doesn't need full 3D reconstruction |

### Simplified Architecture for 2.5D

The original design included MASt3R-SfM for full 3D reconstruction. For 2.5D floor plans, we can simplify:

```
┌─────────────────────────────────────────────────────────────────┐
│                    SIMPLIFIED 2.5D PIPELINE                      │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  Stage 1: Frame Extraction (5%)                                  │
│  └─ Same as before                                               │
│                                                                  │
│  Stage 2: Depth Pro Estimation (25%)                             │
│  └─ Metric depth maps for dimension extraction                   │
│                                                                  │
│  Stage 3: Auto-Scale Calibration (35%) ← ENHANCED                │
│  ├─ PRIMARY: Base cabinet height (34.5")                         │
│  ├─ FALLBACK 1: Countertop surface (36")                         │
│  ├─ FALLBACK 2: Door height (80")                                │
│  ├─ FALLBACK 3: Dishwasher width (24")                           │
│  └─ Multi-reference cross-validation                             │
│                                                                  │
│  Stage 4: Wall Detection (50%) ← FROM ARKIT                      │
│  ├─ Use ARKit vertical planes (already in meters)                │
│  ├─ Refine with image edge detection                             │
│  ├─ Snap to 90° angles                                           │
│  └─ Find corners at intersections                                │
│                                                                  │
│  Stage 5: Object Detection (75%)                                 │
│  ├─ Grounding DINO with kitchen prompts                          │
│  ├─ SAM 2.1 for precise masks                                    │
│  ├─ Extract dimensions using Depth Pro + scale                   │
│  └─ Track same object across frames                              │
│                                                                  │
│  Stage 6: Snap to Standards (90%)                                │
│  └─ Same as before                                               │
│                                                                  │
│  Stage 7: Floor Plan Generation (100%)                           │
│  ├─ PNG floor plan (300 DPI)                                     │
│  ├─ JSON in MeasurementData format (FEET not inches!)            │
│  └─ Flags for items needing review                               │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

### Enhanced Scale Calibration (Multi-Reference)

```python
# pipeline/stages/scale_calibration.py

from dataclasses import dataclass
from enum import Enum
from typing import List

class CalibrationMethod(Enum):
    BASE_CABINET_HEIGHT = "base_cabinet_height"  # 34.5" (without countertop)
    COUNTERTOP_HEIGHT = "countertop_height"      # 36" (floor to countertop)
    DOOR_HEIGHT = "door_height"                   # 80"
    DISHWASHER_WIDTH = "dishwasher_width"        # 24"

REFERENCE_DIMENSIONS = {
    CalibrationMethod.BASE_CABINET_HEIGHT: 34.5,
    CalibrationMethod.COUNTERTOP_HEIGHT: 36.0,
    CalibrationMethod.DOOR_HEIGHT: 80.0,
    CalibrationMethod.DISHWASHER_WIDTH: 24.0,
}

@dataclass
class ScaleEstimate:
    method: CalibrationMethod
    scale: float  # inches per pixel
    confidence: float
    detected_pixels: float
    reference_inches: float

@dataclass
class CalibrationResult:
    final_scale: float
    confidence: str  # HIGH, MEDIUM, LOW
    primary_method: CalibrationMethod
    supporting_methods: List[CalibrationMethod]
    cross_validation_error: float

class MultiReferenceCalibrator:
    """
    Multi-reference scale calibration with cross-validation.

    Key insight: Multiple references increase confidence.
    If they agree within 5%, confidence is HIGH.
    """

    async def calibrate(self, keyframes, detections) -> CalibrationResult:
        estimates = []

        # Try all methods
        for method, detector in [
            (CalibrationMethod.BASE_CABINET_HEIGHT, self._detect_base_cabinet_height),
            (CalibrationMethod.DOOR_HEIGHT, self._detect_door_height),
            (CalibrationMethod.DISHWASHER_WIDTH, self._detect_dishwasher_width),
        ]:
            try:
                result = await detector(keyframes, detections)
                estimates.extend(result)
            except Exception:
                pass

        if not estimates:
            raise CalibrationError("No reference objects detected")

        # Cross-validate
        return self._cross_validate(estimates)

    def _cross_validate(self, estimates: List[ScaleEstimate]) -> CalibrationResult:
        scales = [e.scale for e in estimates]
        weights = [e.confidence for e in estimates]

        weighted_scale = np.average(scales, weights=weights)
        variance = np.std(scales) / weighted_scale if weighted_scale > 0 else 1.0

        if variance < 0.03:  # 3% agreement
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
            cross_validation_error=variance * 100
        )
```

### ARKit Planes Integration (iOS Side)

```swift
// AIARSessionManager.swift - CRITICAL CHANGE

// Line 188: Enable plane detection
configuration.planeDetection = [.horizontal, .vertical]  // Was: []

// Add plane storage
private var detectedPlanes: [UUID: ARPlaneAnchor] = [:]

func session(_ session: ARSession, didAdd anchors: [ARAnchor]) {
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
            "transform": anchor.transform.columns.map { [$0.x, $0.y, $0.z, $0.w] }
        ]
    }
    return try! JSONSerialization.data(withJSONObject: planes)
}
```

### Server Wall Detection from ARKit Planes

```python
# pipeline/stages/wall_detection.py

class WallDetector:
    """
    Wall detection using ARKit planes as PRIMARY source.
    """

    async def detect(
        self,
        arkit_planes: List[ARKitPlane],
        keyframes: List[Keyframe],
        scale: float
    ) -> WallDetectionResult:
        """
        Priority:
        1. ARKit vertical planes (already in meters, very reliable)
        2. Image edge detection (fills gaps)
        """
        walls = []

        # 1. Extract walls from ARKit vertical planes
        for plane in arkit_planes:
            if plane.alignment != "vertical":
                continue

            # Convert plane center + extent to wall segment
            center = np.array([plane.center[0], plane.center[2]])  # X, Z in floor plane
            extent_x = plane.extent[0]  # Width of plane in meters

            # Calculate wall direction from transform
            transform = np.array(plane.transform)
            normal = transform[:3, 2]  # Z column is normal
            wall_dir = np.array([-normal[2], normal[0]])  # Perpendicular in floor plane
            wall_dir = wall_dir / np.linalg.norm(wall_dir)

            # Wall endpoints in inches
            half_extent = extent_x / 2 * 39.37
            start = center * 39.37 - wall_dir * half_extent
            end = center * 39.37 + wall_dir * half_extent

            length = np.linalg.norm(end - start)
            angle = np.arctan2(end[1] - start[1], end[0] - start[0]) * 180 / np.pi

            if length >= 24:  # Minimum 2 feet
                walls.append(Wall(
                    start=tuple(start),
                    end=tuple(end),
                    length=length,
                    angle=angle,
                    confidence=0.9  # ARKit planes are reliable
                ))

        # 2. Snap angles to 90-degree grid
        walls = self._snap_wall_angles(walls)

        # 3. Find corners
        corners = self._find_corners(walls)

        return WallDetectionResult(
            walls=walls,
            corners=corners,
            room_polygon=self._build_polygon(corners)
        )
```

### Enhanced Object Detection Pipeline

```python
# pipeline/stages/object_detection.py

class KitchenObjectDetector:
    """
    Hierarchical detection for kitchens.
    """

    DETECTION_HIERARCHY = {
        "cabinets": {
            "prompt": "base cabinet. upper cabinet. tall cabinet. pantry.",
            "subcategories": ["base_cabinet", "upper_cabinet", "tall_cabinet"]
        },
        "appliances": {
            "prompt": "refrigerator. range. dishwasher. microwave. hood. sink.",
            "subcategories": ["refrigerator", "range", "dishwasher", "microwave", "hood", "sink"]
        },
        "openings": {
            "prompt": "door. window. doorway.",
            "subcategories": ["door", "window"]
        }
    }

    async def detect(
        self,
        frames: List[Keyframe],
        depth_maps: List[np.ndarray],
        scale: float
    ) -> List[Detection]:
        all_detections = []

        for frame, depth_map in zip(frames, depth_maps):
            for category, config in self.DETECTION_HIERARCHY.items():
                # Grounding DINO detection
                boxes = self.dino.detect(frame.image, config["prompt"])

                for box in boxes:
                    # SAM2 segmentation
                    mask = self.sam2.segment(frame.image, box=box.box)

                    # Extract dimensions using depth + scale
                    dimensions = self._extract_dimensions(mask, depth_map, scale)

                    # Classify subcategory
                    subcategory = self._classify(box, config["subcategories"])

                    all_detections.append(Detection(
                        category=subcategory,
                        bbox_2d=box.box,
                        mask=mask,
                        confidence=box.confidence,
                        dimensions=dimensions
                    ))

        # Merge duplicates across frames
        return self._merge_across_frames(all_detections)

    def _extract_dimensions(
        self,
        mask: np.ndarray,
        depth_map: np.ndarray,
        scale: float
    ) -> Dict[str, float]:
        """
        Extract dimensions using mask + depth + scale.

        Key insight: Use Depth Pro depth at mask center for distance,
        then apply scale factor for pixel-to-inch conversion.
        """
        # Get mask bounding box
        rows = np.any(mask, axis=1)
        cols = np.any(mask, axis=0)
        y_min, y_max = np.where(rows)[0][[0, -1]]
        x_min, x_max = np.where(cols)[0][[0, -1]]

        width_pixels = x_max - x_min
        height_pixels = y_max - y_min

        # Get depth at mask center
        center_y = (y_min + y_max) // 2
        center_x = (x_min + x_max) // 2
        depth_meters = depth_map[center_y, center_x]

        # Scale is calibrated at reference object depth
        # For objects at similar depth, direct conversion works
        # For objects at different depth, need perspective correction
        width_inches = width_pixels * scale
        height_inches = height_pixels * scale

        return {
            "width": round(width_inches, 1),
            "height": round(height_inches, 1),
            "depth_meters": float(depth_meters)
        }
```

### Dashboard-Compatible Output Format

```python
# pipeline/stages/floor_plan_generation.py

def generate_measurements_json(
    walls: WallDetectionResult,
    detections: List[Detection],
    calibration: CalibrationResult
) -> Dict:
    """
    Generate JSON in MeasurementData format.

    CRITICAL: Dashboard expects values in FEET, not inches!
    """
    return {
        "room_name": "Kitchen",
        "room_type": "kitchen",
        "total_linear_ft": sum(
            d.dimensions["width"] for d in detections
            if d.category in ["base_cabinet", "upper_cabinet"]
        ) / 12,  # Convert inches to feet
        "total_sq_ft": calculate_room_area(walls) / 144,  # sq inches to sq feet
        "wall_count": len(walls.walls),
        "window_count": len([d for d in detections if d.category == "window"]),
        "door_count": len([d for d in detections if d.category == "door"]),

        "measurements": {
            "scan_method": "ai_flow_server",

            "ai_metadata": {
                "schema_version": "2.0",
                "calibration_method": calibration.primary_method.value,
                "calibration_confidence": calibration.confidence,
                "overall_confidence": calculate_overall_confidence(detections),
                "cross_validation_error_pct": calibration.cross_validation_error,
                "processing_time_ms": 0,  # Filled later
                "needs_verification": calibration.confidence == "LOW"
            },

            "walls": [
                {
                    "id": f"wall_{i}",
                    "start": {"x": w.start[0] / 12, "z": w.start[1] / 12},
                    "end": {"x": w.end[0] / 12, "z": w.end[1] / 12},
                    "length_ft": w.length / 12,
                    "height_ft": 8.0,  # Default ceiling height
                    "confidence": "high" if w.confidence > 0.8 else "medium"
                }
                for i, w in enumerate(walls.walls)
            ],

            "cabinets": {
                "lower": [
                    format_cabinet(d) for d in detections
                    if d.category == "base_cabinet"
                ],
                "upper": [
                    format_cabinet(d) for d in detections
                    if d.category == "upper_cabinet"
                ],
                "pantry": [
                    format_cabinet(d) for d in detections
                    if d.category == "tall_cabinet"
                ]
            },

            "appliances": [
                format_appliance(d) for d in detections
                if d.category in ["refrigerator", "range", "dishwasher", "microwave", "hood", "sink"]
            ],

            "doors": [format_opening(d) for d in detections if d.category == "door"],
            "windows": [format_opening(d) for d in detections if d.category == "window"],

            "countertop_totals": calculate_countertop_totals(detections, walls),

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

def format_cabinet(d: Detection) -> Dict:
    """Format cabinet for dashboard (values in FEET)."""
    return {
        "id": d.id,
        "position": {"x": d.position[0] / 12, "z": d.position[1] / 12},
        "width_ft": d.snapped_width / 12,
        "height_ft": d.dimensions["height"] / 12,
        "depth_ft": 2.0,  # Standard 24" depth
        "width_raw_inches": d.dimensions["width"],
        "width_snapped_inches": d.snapped_width,
        "confidence": d.confidence_level,
        "ai_is_standard_size": d.is_standard_size
    }
```

### Implementation Timeline (Updated)

| Week | Deliverable |
|------|-------------|
| **Week 1** | iOS: Enable ARKit planes, create ServerPipelineClient, CapturePackageBuilder |
| **Week 2** | Server: Set up RunPod, implement frame extraction, Depth Pro integration |
| **Week 3** | Server: Multi-reference scale calibration, wall detection from ARKit planes |
| **Week 4** | Server: Object detection (DINO + SAM2), dimension extraction |
| **Week 5** | Server: Snap-to-standards, floor plan generation, MeasurementData format |
| **Week 6** | Integration testing, accuracy validation, deploy to production |

### Expected Accuracy

| Measurement | Accuracy | Confidence |
|-------------|----------|------------|
| Cabinet widths (same plane as reference) | ±1-2" | HIGH |
| Wall lengths (from ARKit planes) | ±2-3" | HIGH |
| Appliance widths | ±1" | HIGH (standard sizes) |
| Door/window widths | ±2-3" | MEDIUM |
| Room area | ±3% | HIGH |

---

*Document updated: February 2026*
*Added: Multi-reference calibration, ARKit plane integration, 2.5D simplification*
