"""Stage 3: Scale Calibration — Multi-reference cross-validation.

Uses known cabinet dimensions to calibrate relative depth into metric scale.
Cross-validates across multiple references for confidence scoring.
"""

import numpy as np
import torch
from dataclasses import dataclass

from .depth_estimation import DepthFrame
from ..utils.errors import ScaleCalibrationError


def _ensure_numpy(arr) -> np.ndarray:
    """Ensure a value is a numpy ndarray (defensive against leaked CUDA tensors)."""
    if isinstance(arr, torch.Tensor):
        return arr.detach().cpu().numpy()
    return np.asarray(arr)


# Standard kitchen references (in inches)
REFERENCE_OBJECTS = {
    "base_cabinet_height": 34.5,
    "countertop_height": 36.0,
    "standard_door_height": 80.0,
    "dishwasher_width": 24.0,
    "refrigerator_width": 36.0,
    "range_width": 30.0,
}

# Standard cabinet widths (in inches)
STANDARD_CABINET_WIDTHS = [9, 12, 15, 18, 21, 24, 27, 30, 33, 36, 42, 48]


@dataclass
class CalibrationResult:
    """Result of scale calibration."""
    scale_factor: float  # multiply depth values by this to get real-world meters
    confidence: str  # "high", "medium", "low"
    reference_used: str  # primary reference object
    cross_validation_score: float  # 0-1, how well references agree
    references_found: list[str]  # which references were detected


class ScaleCalibrator:
    """Calibrate depth scale using known reference objects."""

    # Minimum cross-validation score for "high" confidence
    HIGH_CONFIDENCE_THRESHOLD = 0.85
    MEDIUM_CONFIDENCE_THRESHOLD = 0.6

    def calibrate(
        self,
        depth_frames: list[DepthFrame],
        detected_objects: list[dict] | None = None,
        has_arkit_planes: bool = False,
    ) -> CalibrationResult:
        """Calibrate scale using detected reference objects.

        Args:
            depth_frames: Frames with metric depth maps
            detected_objects: Optional pre-detected objects with bounding boxes
            has_arkit_planes: Whether ARKit plane data is available (already metric)

        Returns:
            CalibrationResult with scale factor and confidence
        """
        if not depth_frames:
            raise ScaleCalibrationError("No depth frames provided")

        print(f"[ScaleCalibrator] {len(depth_frames)} depth frames, detected_objects={'yes' if detected_objects else 'no'}, has_arkit_planes={has_arkit_planes}", flush=True)

        # Collect scale estimates from multiple references
        scale_estimates: list[tuple[float, str]] = []

        # Try each reference object
        for ref_name, ref_size_inches in REFERENCE_OBJECTS.items():
            scale = self._estimate_from_reference(
                depth_frames, ref_name, ref_size_inches, detected_objects
            )
            if scale is not None:
                scale_estimates.append((scale, ref_name))

        if not scale_estimates:
            # If ARKit planes are available, they're already in metric space —
            # use scale_factor=1.0 with medium confidence
            if has_arkit_planes:
                print(f"[ScaleCalibrator] No reference objects, using ARKit planes (scale=1.0, confidence=medium)", flush=True)
                return CalibrationResult(
                    scale_factor=1.0,
                    confidence="medium",
                    reference_used="arkit_planes",
                    cross_validation_score=0.5,
                    references_found=[],
                )

            # Fallback: use median room depth as rough scale
            # Assumes typical kitchen depth of ~10 feet
            median_depth = np.median([df.median_depth for df in depth_frames])
            fallback_scale = 3.0 / median_depth if median_depth > 0 else 1.0  # ~10ft room
            return CalibrationResult(
                scale_factor=float(fallback_scale),
                confidence="low",
                reference_used="room_depth_fallback",
                cross_validation_score=0.0,
                references_found=[],
            )

        # Cross-validate: compute agreement between scale estimates
        scales = [s for s, _ in scale_estimates]
        median_scale = float(np.median(scales))

        # Score = how close all estimates are to each other
        if len(scales) > 1:
            deviations = [abs(s - median_scale) / median_scale for s in scales]
            cross_val_score = max(0, 1.0 - np.mean(deviations))
        else:
            cross_val_score = 0.5  # single reference = medium confidence

        # Determine confidence level
        if cross_val_score >= self.HIGH_CONFIDENCE_THRESHOLD and len(scales) >= 2:
            confidence = "high"
        elif cross_val_score >= self.MEDIUM_CONFIDENCE_THRESHOLD:
            confidence = "medium"
        else:
            confidence = "low"

        return CalibrationResult(
            scale_factor=median_scale,
            confidence=confidence,
            reference_used=scale_estimates[0][1],
            cross_validation_score=float(cross_val_score),
            references_found=[name for _, name in scale_estimates],
        )

    def _estimate_from_reference(
        self,
        depth_frames: list[DepthFrame],
        ref_name: str,
        ref_size_inches: float,
        detected_objects: list[dict] | None,
    ) -> float | None:
        """Estimate scale from a single reference object.

        Returns scale factor or None if reference not found.
        """
        # This would use detected_objects bounding boxes + depth maps
        # to compute real-world size vs. expected size.
        # Placeholder for actual implementation with SAM 3 detections.

        if detected_objects is None:
            return None

        ref_size_meters = ref_size_inches * 0.0254  # inches to meters

        for obj in detected_objects:
            if obj.get("label", "").lower().replace(" ", "_") == ref_name:
                bbox = obj.get("bbox")  # [x1, y1, x2, y2]
                if bbox and len(depth_frames) > 0:
                    # Get depth in the bbox region (defensive against CUDA tensors)
                    depth_map = _ensure_numpy(depth_frames[0].depth_map)
                    x1, y1, x2, y2 = [int(v) for v in bbox]
                    region = depth_map[y1:y2, x1:x2]
                    if region.size > 0:
                        measured_depth_range = float(np.percentile(region, 90) - np.percentile(region, 10))
                        if measured_depth_range > 0:
                            return ref_size_meters / measured_depth_range

        return None
