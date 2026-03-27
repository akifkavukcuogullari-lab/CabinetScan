"""Stage 5: Object Detection — SAM 3 text-prompted segmentation.

Uses SAM 3 for text-prompted instance segmentation of cabinets,
appliances, and fixtures. Tracks instances across frames using
3D world-position clustering and extracts dimensions via depth
maps + camera intrinsics.
"""

import numpy as np
import torch
from dataclasses import dataclass
from PIL import Image as PILImage

from .depth_estimation import DepthFrame
from .scale_calibration import CalibrationResult
from ..utils.errors import ObjectDetectionError


def _to_numpy(value) -> np.ndarray:
    """Convert a value to numpy, handling CUDA/CPU tensors."""
    if isinstance(value, torch.Tensor):
        return value.detach().cpu().numpy()
    return np.asarray(value)


@dataclass
class CameraIntrinsics:
    """Scaled camera intrinsics for back-projection."""
    fx: float
    fy: float
    cx: float
    cy: float


def _get_scaled_intrinsics(
    pose: dict,
    frame_width: int,
    frame_height: int,
) -> CameraIntrinsics | None:
    """Extract camera intrinsics from a pose and scale to frame resolution.

    Pose intrinsics are for the original capture resolution (~1920x1440).
    Frames are extracted at a different resolution (e.g. 320x568).
    Scale intrinsics by the ratio frame_size / original_size.
    """
    intrinsics = pose.get("intrinsics")
    if not intrinsics:
        return None

    fx = intrinsics.get("fx")
    fy = intrinsics.get("fy")
    cx = intrinsics.get("cx")
    cy = intrinsics.get("cy")

    if fx is None or fy is None or cx is None or cy is None:
        return None

    # Infer original resolution from principal point (center of sensor)
    orig_width = cx * 2.0
    orig_height = cy * 2.0

    if orig_width <= 0 or orig_height <= 0:
        return None

    scale_x = frame_width / orig_width
    scale_y = frame_height / orig_height

    zoom = pose.get("zoomFactor", 1.0)

    return CameraIntrinsics(
        fx=fx * zoom * scale_x,
        fy=fy * zoom * scale_y,
        cx=cx * scale_x,
        cy=cy * scale_y,
    )


def _compute_world_position(
    bbox: tuple[int, int, int, int],
    depth_map: np.ndarray,
    intrinsics: CameraIntrinsics,
    pose_transform: list,
    mask: np.ndarray | None = None,
    scale_factor: float = 1.0,
) -> tuple[float, float, float] | None:
    """Back-project bbox center to 3D world coordinates.

    1. Get depth at bbox center (mask-weighted median if available)
    2. Scale depth by scale_factor to convert relative depth to meters
    3. Back-project pixel to camera-space 3D point using intrinsics
    4. Transform to world coordinates using the 4x4 pose transform
    """
    x1, y1, x2, y2 = bbox
    h, w = depth_map.shape[:2]

    cx_px = (x1 + x2) // 2
    cy_px = (y1 + y2) // 2
    cx_px = max(0, min(w - 1, cx_px))
    cy_px = max(0, min(h - 1, cy_px))

    # Get depth value
    if mask is not None:
        mask_np = _to_numpy(mask) if isinstance(mask, torch.Tensor) else mask
        bx1, by1 = max(0, x1), max(0, y1)
        bx2, by2 = min(w, x2), min(h, y2)
        if bx2 > bx1 and by2 > by1:
            mask_region = mask_np[by1:by2, bx1:bx2]
            depth_region = depth_map[by1:by2, bx1:bx2]
            valid = (mask_region > 0) & (depth_region > 0)
            if valid.any():
                depth_value = float(np.median(depth_region[valid]))
            else:
                depth_value = 0.0
        else:
            depth_value = 0.0
    else:
        patch_r = 5
        py1 = max(0, cy_px - patch_r)
        py2 = min(h, cy_px + patch_r + 1)
        px1 = max(0, cx_px - patch_r)
        px2 = min(w, cx_px + patch_r + 1)
        patch = depth_map[py1:py2, px1:px2]
        valid_patch = patch[patch > 0]
        depth_value = float(np.median(valid_patch)) if valid_patch.size > 0 else 0.0

    if depth_value <= 0:
        return None

    # Apply scale_factor to depth value.
    # With the metric indoor model, depth is already in meters and
    # scale_factor=1.0, so this is effectively a no-op. Kept for
    # compatibility if a relative depth model is used with a calibrated scale.
    depth_meters = depth_value * scale_factor

    # Back-project to camera space (pinhole model)
    x_cam = (cx_px - intrinsics.cx) * depth_meters / intrinsics.fx
    y_cam = (cy_px - intrinsics.cy) * depth_meters / intrinsics.fy
    z_cam = depth_meters

    # Parse 4x4 column-major transform: transform[col][row]
    # np.array gives [[col0], [col1], [col2], [col3]], transpose to row-major
    T = np.array(pose_transform, dtype=np.float64).T

    cam_point = np.array([x_cam, y_cam, z_cam, 1.0])
    world_point = T @ cam_point

    return (float(world_point[0]), float(world_point[1]), float(world_point[2]))


# Text prompts for SAM 3
DETECTION_PROMPTS = [
    "base cabinet",
    "upper cabinet",
    "tall cabinet",
    "refrigerator",
    "range",
    "oven",
    "dishwasher",
    "sink",
    "window",
    "door",
    "microwave",
]


@dataclass
class DetectedObject:
    """A detected kitchen object with measurements."""
    label: str
    instance_id: int  # unique across frames
    bbox: tuple[int, int, int, int]  # x1, y1, x2, y2 in pixels
    mask: np.ndarray | None  # binary mask
    width_inches: float
    height_inches: float
    depth_inches: float  # distance from camera
    confidence: float  # 0-1
    frame_index: int  # which frame it was detected in
    # Snapped to standard size
    standard_width_inches: float | None = None
    deviation_inches: float | None = None
    # 3D world position for cross-frame tracking
    world_position: tuple[float, float, float] | None = None


@dataclass
class ObjectDetectionResult:
    """Result of object detection stage."""
    objects: list[DetectedObject]
    base_cabinet_count: int
    upper_cabinet_count: int
    appliance_count: int
    total_objects: int


class ObjectDetector:
    """Detect kitchen objects using SAM 3."""

    MIN_CONFIDENCE = 0.35  # minimum confidence to keep a detection
    CLUSTER_DISTANCE_M = 1.0  # 3D distance threshold for merging duplicates
    AGGRESSIVE_CLUSTER_M = 1.5  # fallback threshold if too many objects remain
    MAX_OBJECTS_BEFORE_RECLUSTER = 80  # trigger aggressive re-clustering above this
    # Dimension caps (meters) — anything larger is a measurement error
    MAX_WIDTH_M = 6.0   # ~20ft
    MAX_HEIGHT_M = 4.5  # ~15ft

    def __init__(self, device: str = "cuda"):
        self.device = device
        self._model = None

    # BPE tokenizer vocab file — pip-installed sam3 doesn't include assets/
    BPE_PATH = "/app/assets/bpe_simple_vocab_16e6.txt.gz"

    def load_model(self) -> None:
        """Load SAM 3 model into VRAM.

        Fails gracefully — if SAM 3 can't load, object detection
        returns empty results and the pipeline continues.
        """
        try:
            import os
            from sam3.model_builder import build_sam3_image_model
            from sam3.model.sam3_image_processor import Sam3Processor

            bpe_path = self.BPE_PATH if os.path.exists(self.BPE_PATH) else None
            print(f"[ObjectDetector] BPE path: {self.BPE_PATH} exists={os.path.exists(self.BPE_PATH)}", flush=True)
            if bpe_path:
                bpe_size = os.path.getsize(bpe_path)
                print(f"[ObjectDetector] BPE file size: {bpe_size} bytes", flush=True)
            else:
                print(f"[ObjectDetector] WARNING: BPE file not found, using SAM 3 default path", flush=True)

            print(f"[ObjectDetector] Loading SAM 3 model on {self.device}...", flush=True)
            sam3_model = build_sam3_image_model(bpe_path=bpe_path, device=self.device)
            self._model = Sam3Processor(sam3_model, device=self.device)
            print(f"[ObjectDetector] SAM 3 loaded OK", flush=True)
        except Exception as e:
            import traceback
            print(f"[ObjectDetector] SAM 3 unavailable, skipping object detection: {e}", flush=True)
            traceback.print_exc()
            self._model = None

    def detect(
        self,
        depth_frames: list[DepthFrame],
        calibration: CalibrationResult,
        poses: list[dict] | None = None,
    ) -> ObjectDetectionResult:
        """Detect objects in all frames and extract measurements.

        Args:
            depth_frames: Frames with metric depth maps
            calibration: Scale calibration result
            poses: Optional ARKit pose dicts with transform and intrinsics

        Returns:
            ObjectDetectionResult with all detected objects
        """
        if not depth_frames:
            raise ObjectDetectionError("No frames to process")

        print(f"[ObjectDetector] Detecting objects in {len(depth_frames)} frames, model={'loaded' if self._model else 'NONE'}, poses={'yes' if poses else 'no'}", flush=True)

        all_objects: list[DetectedObject] = []
        instance_counter = 0

        for fi, depth_frame in enumerate(depth_frames):
            frame_objects = self._detect_in_frame(
                depth_frame, calibration, instance_counter, poses=poses
            )
            print(f"[ObjectDetector] Frame {fi}: {len(frame_objects)} objects detected", flush=True)
            all_objects.extend(frame_objects)
            instance_counter += len(frame_objects)

        print(f"[ObjectDetector] Total raw detections: {len(all_objects)}", flush=True)

        # Track instances across frames (merge duplicates)
        merged = self._track_instances(all_objects)
        print(f"[ObjectDetector] After merging: {len(merged)} unique objects", flush=True)

        # Count by type
        base_count = sum(1 for o in merged if "base" in o.label.lower())
        upper_count = sum(1 for o in merged if "upper" in o.label.lower())
        appliance_count = sum(
            1 for o in merged
            if any(a in o.label.lower() for a in ["refrigerator", "range", "oven", "dishwasher", "microwave"])
        )

        return ObjectDetectionResult(
            objects=merged,
            base_cabinet_count=base_count,
            upper_cabinet_count=upper_count,
            appliance_count=appliance_count,
            total_objects=len(merged),
        )

    def _detect_in_frame(
        self,
        depth_frame: DepthFrame,
        calibration: CalibrationResult,
        start_id: int,
        poses: list[dict] | None = None,
    ) -> list[DetectedObject]:
        """Detect objects in a single frame."""
        objects: list[DetectedObject] = []
        frame = depth_frame.frame
        h, w = depth_frame.depth_map.shape[:2]

        # Resolve pose and intrinsics for this frame
        pose = None
        intrinsics = None
        pose_transform = None
        if poses and frame.pose_index is not None and frame.pose_index < len(poses):
            pose = poses[frame.pose_index]
            intrinsics = _get_scaled_intrinsics(pose, w, h)
            pt = pose.get("transform")
            if pt and len(pt) == 4 and all(len(col) == 4 for col in pt):
                pose_transform = pt

        # Use actual focal length from intrinsics, or fallback
        focal_length = (intrinsics.fx + intrinsics.fy) / 2.0 if intrinsics else 1000.0

        for prompt in DETECTION_PROMPTS:
            detections = self._run_sam3(depth_frame.frame.image, prompt)

            for i, det in enumerate(detections):
                bbox = det["bbox"]
                mask = det.get("mask")
                confidence = det.get("confidence", 0.5)

                # Extract dimensions using real focal length
                width_m, height_m, depth_m = self._measure_object(
                    depth_frame.depth_map, bbox, calibration.scale_factor,
                    mask=mask, focal_length=focal_length,
                )

                # Compute 3D world position for cross-frame tracking
                world_pos = None
                if intrinsics and pose_transform:
                    world_pos = _compute_world_position(
                        tuple(bbox), depth_frame.depth_map,
                        intrinsics, pose_transform, mask=mask,
                        scale_factor=calibration.scale_factor,
                    )

                objects.append(DetectedObject(
                    label=prompt,
                    instance_id=start_id + len(objects),
                    bbox=tuple(bbox),
                    mask=mask,
                    width_inches=width_m / 0.0254,
                    height_inches=height_m / 0.0254,
                    depth_inches=depth_m / 0.0254,
                    confidence=confidence,
                    frame_index=depth_frame.frame.frame_index,
                    world_position=world_pos,
                ))

        return objects

    def _run_sam3(self, image: np.ndarray, prompt: str) -> list[dict]:
        """Run SAM 3 text-prompted detection.

        Args:
            image: BGR numpy array from OpenCV
            prompt: Text prompt (e.g. "base cabinet")

        Returns:
            List of {"bbox": [x1,y1,x2,y2], "mask": ndarray, "confidence": float}
            Returns empty list if SAM 3 fails (graceful degradation).
        """
        if self._model is None:
            return []

        try:
            # Convert BGR numpy -> RGB PIL (SAM 3 expects PIL)
            rgb = image[:, :, ::-1]
            pil_image = PILImage.fromarray(rgb)

            # Run SAM 3 text-prompted detection
            state = self._model.set_image(pil_image)
            print(f"[ObjectDetector] set_image OK, state keys={list(state.keys()) if isinstance(state, dict) else type(state).__name__}", flush=True)

            output = self._model.set_text_prompt(state=state, prompt=prompt)

            # Log raw output shapes
            raw_masks = output["masks"]
            raw_boxes = output["boxes"]
            raw_scores = output["scores"]

            def _shape_info(t):
                if isinstance(t, torch.Tensor):
                    return f"Tensor {t.shape} {t.dtype} {t.device}"
                elif isinstance(t, np.ndarray):
                    return f"ndarray {t.shape} {t.dtype}"
                elif isinstance(t, list):
                    return f"list len={len(t)}"
                return type(t).__name__

            print(f"[ObjectDetector] prompt='{prompt}': masks={_shape_info(raw_masks)}, boxes={_shape_info(raw_boxes)}, scores={_shape_info(raw_scores)}", flush=True)

            # Filter by confidence threshold, converting CUDA tensors to numpy/python
            detections = []
            for mask, box, score in zip(raw_masks, raw_boxes, raw_scores):
                score_val = float(score.item() if isinstance(score, torch.Tensor) else score)
                if score_val >= self.MIN_CONFIDENCE:
                    box_np = _to_numpy(box) if isinstance(box, torch.Tensor) else box
                    # SAM 3 masks are (1, H, W) — squeeze to (H, W) for depth map compatibility
                    mask_np = _to_numpy(mask)
                    if mask_np.ndim == 3 and mask_np.shape[0] == 1:
                        mask_np = mask_np[0]
                    detections.append({
                        "bbox": [int(b) for b in box_np],
                        "mask": mask_np,
                        "confidence": score_val,
                    })

            print(f"[ObjectDetector] prompt='{prompt}': {len(detections)} detections (threshold={self.MIN_CONFIDENCE})", flush=True)
            return detections

        except Exception as e:
            import traceback
            print(f"[ObjectDetector] SAM 3 failed for prompt '{prompt}': {e}", flush=True)
            traceback.print_exc()
            return []

    def _measure_object(
        self,
        depth_map: np.ndarray,
        bbox: tuple[int, int, int, int],
        scale_factor: float,
        mask: np.ndarray | None = None,
        focal_length: float = 1000.0,
    ) -> tuple[float, float, float]:
        """Measure object dimensions using depth map.

        When a segmentation mask is provided, uses it for more precise
        depth estimation by only sampling pixels within the object silhouette.

        Returns (width_meters, height_meters, depth_meters).
        """
        x1, y1, x2, y2 = [int(v) for v in bbox]

        # Ensure numpy arrays (guard against leaked CUDA tensors)
        depth_map = _to_numpy(depth_map) if isinstance(depth_map, torch.Tensor) else depth_map
        h, w = depth_map.shape[:2]

        # Clamp to image bounds
        x1, y1 = max(0, x1), max(0, y1)
        x2, y2 = min(w, x2), min(h, y2)

        if x2 <= x1 or y2 <= y1:
            return 0.0, 0.0, 0.0

        depth_region = depth_map[y1:y2, x1:x2]
        if depth_region.size == 0:
            return 0.0, 0.0, 0.0

        if mask is not None:
            # Use mask for precise depth: only measure within the object silhouette
            mask = _to_numpy(mask) if isinstance(mask, torch.Tensor) else mask
            mask_region = mask[y1:y2, x1:x2]
            valid = (mask_region > 0) & (depth_region > 0)
            if valid.any():
                median_depth = float(np.median(depth_region[valid]))
            else:
                median_depth = 0
        else:
            # Fallback to bbox-only
            median_depth = float(np.median(depth_region[depth_region > 0])) if np.any(depth_region > 0) else 0

        # Width and height in pixels, converted to meters using depth + scale
        pixel_width = x2 - x1
        pixel_height = y2 - y1

        # Pinhole camera model: real_size = pixel_size * depth / focal_length
        width_meters = (pixel_width * median_depth * scale_factor) / focal_length
        height_meters = (pixel_height * median_depth * scale_factor) / focal_length

        return width_meters, height_meters, median_depth * scale_factor

    def _track_instances(self, objects: list[DetectedObject]) -> list[DetectedObject]:
        """Merge duplicate detections across frames using 3D world position.

        Groups detections by label, then clusters by 3D proximity (within
        CLUSTER_DISTANCE_M). For each cluster, keeps the highest-confidence
        detection and averages measurements across members.

        Falls back to IoU-based merging for detections without world_position.
        If too many objects remain after initial clustering, re-runs with
        a more aggressive distance threshold.
        """
        if not objects:
            return []

        positioned: list[DetectedObject] = []
        unpositioned: list[DetectedObject] = []
        for obj in objects:
            if obj.world_position is not None:
                positioned.append(obj)
            else:
                unpositioned.append(obj)

        merged_positioned = self._cluster_by_world_position(
            positioned, self.CLUSTER_DISTANCE_M
        )

        # Safety net: if still too many objects, re-cluster aggressively
        if len(merged_positioned) > self.MAX_OBJECTS_BEFORE_RECLUSTER:
            print(
                f"[ObjectDetector] Too many objects ({len(merged_positioned)}) after "
                f"{self.CLUSTER_DISTANCE_M}m clustering, re-running at {self.AGGRESSIVE_CLUSTER_M}m",
                flush=True,
            )
            merged_positioned = self._cluster_by_world_position(
                merged_positioned, self.AGGRESSIVE_CLUSTER_M
            )

        merged_unpositioned = self._merge_by_iou(unpositioned)

        result = merged_positioned + merged_unpositioned

        # Clamp absurd dimensions on all results
        result = self._clamp_dimensions(result)

        print(
            f"[ObjectDetector] Tracking: {len(positioned)} positioned -> "
            f"{len(merged_positioned)} clusters, {len(unpositioned)} unpositioned -> "
            f"{len(merged_unpositioned)} by IoU",
            flush=True,
        )
        return result

    def _cluster_by_world_position(
        self, objects: list[DetectedObject], distance_m: float | None = None
    ) -> list[DetectedObject]:
        """Cluster detections by label and 3D world proximity."""
        if not objects:
            return []

        threshold = distance_m if distance_m is not None else self.CLUSTER_DISTANCE_M

        # Group by label
        by_label: dict[str, list[DetectedObject]] = {}
        for obj in objects:
            by_label.setdefault(obj.label, []).append(obj)

        result: list[DetectedObject] = []

        for label, group in by_label.items():
            # Sort by confidence descending — best detections anchor clusters
            group.sort(key=lambda o: o.confidence, reverse=True)

            clusters: list[list[DetectedObject]] = []

            for obj in group:
                obj_pos = np.array(obj.world_position)
                assigned = False

                for cluster in clusters:
                    centroid = np.array(cluster[0].world_position)
                    dist = float(np.linalg.norm(obj_pos - centroid))

                    if dist <= threshold:
                        cluster.append(obj)
                        assigned = True
                        break

                if not assigned:
                    clusters.append([obj])

            for cluster in clusters:
                best = cluster[0]

                if len(cluster) > 1:
                    avg_width = sum(o.width_inches for o in cluster) / len(cluster)
                    avg_height = sum(o.height_inches for o in cluster) / len(cluster)
                    avg_depth = sum(o.depth_inches for o in cluster) / len(cluster)

                    merged = DetectedObject(
                        label=best.label,
                        instance_id=best.instance_id,
                        bbox=best.bbox,
                        mask=best.mask,
                        width_inches=avg_width,
                        height_inches=avg_height,
                        depth_inches=avg_depth,
                        confidence=best.confidence,
                        frame_index=best.frame_index,
                        world_position=best.world_position,
                    )
                    result.append(merged)
                else:
                    result.append(best)

        return result

    def _merge_by_iou(self, objects: list[DetectedObject]) -> list[DetectedObject]:
        """Merge objects with high bounding box overlap, keeping highest confidence."""
        if not objects:
            return []

        objects = sorted(objects, key=lambda o: o.confidence, reverse=True)
        kept: list[DetectedObject] = []

        for obj in objects:
            is_dup = False
            for existing in kept:
                if existing.label == obj.label and self._iou(existing.bbox, obj.bbox) > 0.3:
                    is_dup = True
                    break
            if not is_dup:
                kept.append(obj)

        return kept

    def _clamp_dimensions(self, objects: list[DetectedObject]) -> list[DetectedObject]:
        """Clamp unrealistic object dimensions.

        Any object wider than MAX_WIDTH_M (~20ft) or taller than MAX_HEIGHT_M
        (~15ft) is capped. These thresholds are generous — real kitchen objects
        are always smaller — so clamping indicates a measurement error.
        """
        max_w_in = self.MAX_WIDTH_M / 0.0254  # meters to inches
        max_h_in = self.MAX_HEIGHT_M / 0.0254

        clamped_count = 0
        for obj in objects:
            if obj.width_inches > max_w_in or obj.height_inches > max_h_in:
                clamped_count += 1
                obj.width_inches = min(obj.width_inches, max_w_in)
                obj.height_inches = min(obj.height_inches, max_h_in)

        if clamped_count > 0:
            print(
                f"[ObjectDetector] Clamped {clamped_count} objects with absurd dimensions",
                flush=True,
            )

        return objects

    @staticmethod
    def _iou(box1: tuple, box2: tuple) -> float:
        """Compute Intersection-over-Union between two bounding boxes."""
        x1 = max(box1[0], box2[0])
        y1 = max(box1[1], box2[1])
        x2 = min(box1[2], box2[2])
        y2 = min(box1[3], box2[3])

        inter = max(0, x2 - x1) * max(0, y2 - y1)
        if inter == 0:
            return 0.0

        area1 = (box1[2] - box1[0]) * (box1[3] - box1[1])
        area2 = (box2[2] - box2[0]) * (box2[3] - box2[1])
        union = area1 + area2 - inter
        return inter / union if union > 0 else 0.0
