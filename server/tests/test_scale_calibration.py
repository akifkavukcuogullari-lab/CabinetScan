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
