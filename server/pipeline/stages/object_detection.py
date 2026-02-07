"""Stage 5: Object Detection — SAM 3 text-prompted segmentation.

Uses SAM 3 for text-prompted instance segmentation of cabinets,
appliances, and fixtures. Tracks instances across frames and
extracts dimensions via depth maps + scale factor.
"""

import numpy as np
from dataclasses import dataclass

from .depth_estimation import DepthFrame
from .scale_calibration import CalibrationResult
from ..utils.errors import ObjectDetectionError


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

    def __init__(self, device: str = "cuda"):
        self.device = device
        self._model = None

    def load_model(self) -> None:
        """Load SAM 3 model into VRAM."""
        try:
            # Placeholder for SAM 3 model loading
            # Actual implementation depends on SAM 3 release API
            pass
        except Exception as e:
            raise ObjectDetectionError(f"Failed to load SAM 3 model: {e}")

    def detect(
        self,
        depth_frames: list[DepthFrame],
        calibration: CalibrationResult,
    ) -> ObjectDetectionResult:
        """Detect objects in all frames and extract measurements.

        Args:
            depth_frames: Frames with metric depth maps
            calibration: Scale calibration result

        Returns:
            ObjectDetectionResult with all detected objects
        """
        if not depth_frames:
            raise ObjectDetectionError("No frames to process")

        all_objects: list[DetectedObject] = []
        instance_counter = 0

        for depth_frame in depth_frames:
            frame_objects = self._detect_in_frame(
                depth_frame, calibration, instance_counter
            )
            all_objects.extend(frame_objects)
            instance_counter += len(frame_objects)

        # Track instances across frames (merge duplicates)
        merged = self._track_instances(all_objects)

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
    ) -> list[DetectedObject]:
        """Detect objects in a single frame."""
        objects: list[DetectedObject] = []

        for prompt in DETECTION_PROMPTS:
            # Placeholder for SAM 3 text-prompted detection
            # In production: call SAM 3 with text prompt, get masks + bboxes
            detections = self._run_sam3(depth_frame.frame.image, prompt)

            for i, det in enumerate(detections):
                bbox = det["bbox"]
                mask = det.get("mask")
                confidence = det.get("confidence", 0.5)

                # Extract dimensions from depth map
                width_m, height_m, depth_m = self._measure_object(
                    depth_frame.depth_map, bbox, calibration.scale_factor
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
                ))

        return objects

    def _run_sam3(self, image: np.ndarray, prompt: str) -> list[dict]:
        """Run SAM 3 text-prompted detection. Placeholder."""
        # In production, this calls the SAM 3 API/model
        # Returns list of {"bbox": [x1,y1,x2,y2], "mask": ndarray, "confidence": float}
        return []

    def _measure_object(
        self,
        depth_map: np.ndarray,
        bbox: tuple[int, int, int, int],
        scale_factor: float,
    ) -> tuple[float, float, float]:
        """Measure object dimensions using depth map.

        Returns (width_meters, height_meters, depth_meters).
        """
        x1, y1, x2, y2 = [int(v) for v in bbox]
        h, w = depth_map.shape[:2]

        # Clamp to image bounds
        x1, y1 = max(0, x1), max(0, y1)
        x2, y2 = min(w, x2), min(h, y2)

        if x2 <= x1 or y2 <= y1:
            return 0.0, 0.0, 0.0

        region = depth_map[y1:y2, x1:x2]
        if region.size == 0:
            return 0.0, 0.0, 0.0

        # Object depth = median depth in region
        median_depth = float(np.median(region[region > 0])) if np.any(region > 0) else 0

        # Width and height in pixels, converted to meters using depth + scale
        pixel_width = x2 - x1
        pixel_height = y2 - y1

        # Approximate real-world size from pixel size and depth
        # Using pinhole camera model: real_size = pixel_size * depth / focal_length
        # Assuming ~1000 pixel focal length (typical phone camera)
        focal_length = 1000.0
        width_meters = (pixel_width * median_depth * scale_factor) / focal_length
        height_meters = (pixel_height * median_depth * scale_factor) / focal_length

        return width_meters, height_meters, median_depth * scale_factor

    def _track_instances(self, objects: list[DetectedObject]) -> list[DetectedObject]:
        """Merge duplicate detections across frames.

        Uses bbox overlap and label matching to identify same instance.
        Keeps the detection with highest confidence.
        """
        if not objects:
            return []

        # Simple merge: group by label, keep best per group
        # In production, use proper IoU tracking across frames
        merged: dict[str, DetectedObject] = {}
        for obj in objects:
            key = f"{obj.label}_{obj.bbox[0] // 100}_{obj.bbox[1] // 100}"
            if key not in merged or obj.confidence > merged[key].confidence:
                merged[key] = obj

        return list(merged.values())
