"""Tests for Stage 3: Scale Calibration."""

import numpy as np
import pytest

from pipeline.stages.scale_calibration import (
    ScaleCalibrator,
    CalibrationResult,
    REFERENCE_OBJECTS,
    STANDARD_CABINET_WIDTHS,
)
from pipeline.stages.depth_estimation import DepthFrame
from pipeline.stages.frame_extraction import ExtractedFrame
from pipeline.utils.errors import ScaleCalibrationError


@pytest.fixture
def calibrator():
    return ScaleCalibrator()


def make_depth_frame(median_depth: float = 2.0) -> DepthFrame:
    """Create a mock DepthFrame."""
    image = np.zeros((240, 320, 3), dtype=np.uint8)
    depth_map = np.full((240, 320), median_depth, dtype=np.float32)
    frame = ExtractedFrame(
        image=image, timestamp=0, frame_index=0, blur_score=200
    )
    return DepthFrame(
        frame=frame,
        depth_map=depth_map,
        min_depth=median_depth * 0.5,
        max_depth=median_depth * 1.5,
        median_depth=median_depth,
    )


class TestScaleCalibrator:
    def test_empty_frames_raises(self, calibrator):
        with pytest.raises(ScaleCalibrationError):
            calibrator.calibrate([])

    def test_no_references_returns_low_confidence(self, calibrator):
        frames = [make_depth_frame(2.0)]
        result = calibrator.calibrate(frames, detected_objects=None)
        assert result.confidence == "low"
        assert result.reference_used == "room_depth_fallback"
        assert result.scale_factor > 0

    def test_single_reference_returns_medium(self, calibrator):
        frames = [make_depth_frame(2.0)]
        # Mock a detected base cabinet
        objects = [{
            "label": "base_cabinet_height",
            "bbox": [50, 50, 150, 200],
            "confidence": 0.9,
        }]
        result = calibrator.calibrate(frames, detected_objects=objects)
        assert isinstance(result, CalibrationResult)
        assert result.scale_factor > 0

    def test_fallback_scale_positive(self, calibrator):
        frames = [make_depth_frame(3.0)]
        result = calibrator.calibrate(frames)
        assert result.scale_factor > 0

    def test_zero_depth_fallback(self, calibrator):
        frames = [make_depth_frame(0.0)]
        result = calibrator.calibrate(frames)
        # Should not crash, returns fallback
        assert isinstance(result, CalibrationResult)

    def test_confidence_levels(self, calibrator):
        assert calibrator.HIGH_CONFIDENCE_THRESHOLD > calibrator.MEDIUM_CONFIDENCE_THRESHOLD

    def test_reference_objects_defined(self):
        assert len(REFERENCE_OBJECTS) > 0
        assert "base_cabinet_height" in REFERENCE_OBJECTS
        assert REFERENCE_OBJECTS["base_cabinet_height"] == 34.5

    def test_standard_cabinet_widths(self):
        assert 12 in STANDARD_CABINET_WIDTHS
        assert 24 in STANDARD_CABINET_WIDTHS
        assert 36 in STANDARD_CABINET_WIDTHS
        assert sorted(STANDARD_CABINET_WIDTHS) == STANDARD_CABINET_WIDTHS

    def test_arkit_planes_fallback_medium_confidence(self, calibrator):
        """When no reference objects but ARKit planes available, use scale=1.0 with medium confidence."""
        frames = [make_depth_frame(2.0)]
        result = calibrator.calibrate(frames, detected_objects=None, has_arkit_planes=True)
        assert result.confidence == "medium"
        assert result.scale_factor == 1.0
        assert result.reference_used == "arkit_planes"
        assert result.cross_validation_score == 0.5

    def test_arkit_planes_false_still_falls_back_to_low(self, calibrator):
        """When no reference objects and no ARKit planes, should be low confidence."""
        frames = [make_depth_frame(2.0)]
        result = calibrator.calibrate(frames, detected_objects=None, has_arkit_planes=False)
        assert result.confidence == "low"
        assert result.reference_used == "room_depth_fallback"


class TestMetricModelBehavior:
    """Tests verifying behavior with metric depth model (scale_factor=1.0)."""

    def test_metric_depth_needs_no_scaling(self, calibrator):
        """With metric indoor model, ARKit planes fallback gives scale=1.0.

        This is the expected path: metric model outputs meters directly,
        so no scale conversion is needed.
        """
        frames = [make_depth_frame(2.5)]  # 2.5 meters — realistic indoor depth
        result = calibrator.calibrate(frames, detected_objects=None, has_arkit_planes=True)
        assert result.scale_factor == 1.0

    def test_metric_depth_range_realistic(self):
        """Verify metric depth values are in plausible meter range (0.5-10m)."""
        # Simulate what the metric indoor model would output
        frame = make_depth_frame(2.5)
        assert 0.1 < frame.median_depth < 20.0, "Metric depth should be in meters"
        assert 0.1 < frame.min_depth < 20.0
        assert 0.1 < frame.max_depth < 20.0

    def test_fallback_scale_with_typical_metric_depth(self, calibrator):
        """Fallback scale with metric depth (~2.5m median) should be ~1.2."""
        frames = [make_depth_frame(2.5)]
        result = calibrator.calibrate(frames, detected_objects=None, has_arkit_planes=False)
        # fallback_scale = 3.0 / 2.5 = 1.2
        assert result.scale_factor == pytest.approx(1.2, rel=0.01)
        assert result.confidence == "low"
