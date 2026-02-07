"""Tests for Stage 5: Object Detection."""

import numpy as np
import pytest
from unittest.mock import MagicMock, patch

from pipeline.stages.object_detection import (
    ObjectDetector,
    DetectedObject,
    ObjectDetectionResult,
    DETECTION_PROMPTS,
)
from pipeline.stages.depth_estimation import DepthFrame
from pipeline.stages.frame_extraction import ExtractedFrame
from pipeline.stages.scale_calibration import CalibrationResult
from pipeline.utils.errors import ObjectDetectionError


def make_frame(index: int = 0, h: int = 480, w: int = 640) -> ExtractedFrame:
    """Create a mock ExtractedFrame."""
    return ExtractedFrame(
        image=np.random.randint(0, 255, (h, w, 3), dtype=np.uint8),
        timestamp=index * 0.5,
        frame_index=index,
        blur_score=200.0,
    )


def make_depth_frame(index: int = 0, h: int = 480, w: int = 640) -> DepthFrame:
    """Create a mock DepthFrame with a synthetic depth map."""
    frame = make_frame(index, h, w)
    depth_map = np.full((h, w), 2.5, dtype=np.float32)
    return DepthFrame(
        frame=frame,
        depth_map=depth_map,
        min_depth=2.0,
        max_depth=3.0,
        median_depth=2.5,
    )


def make_calibration(scale: float = 1.0) -> CalibrationResult:
    """Create a mock CalibrationResult."""
    return CalibrationResult(
        scale_factor=scale,
        confidence="high",
        reference_used="base_cabinet_height",
        cross_validation_score=0.9,
        references_found=["base_cabinet_height"],
    )


def make_detected_object(
    label: str = "base cabinet",
    instance_id: int = 0,
    confidence: float = 0.8,
    frame_index: int = 0,
) -> DetectedObject:
    """Create a mock DetectedObject."""
    return DetectedObject(
        label=label,
        instance_id=instance_id,
        bbox=(100, 100, 300, 400),
        mask=None,
        width_inches=24.0,
        height_inches=34.5,
        depth_inches=98.0,
        confidence=confidence,
        frame_index=frame_index,
    )


@pytest.fixture
def detector():
    return ObjectDetector(device="cpu")


@pytest.fixture
def calibration():
    return make_calibration()


class TestObjectDetectorInit:
    def test_default_device_is_cuda(self):
        det = ObjectDetector()
        assert det.device == "cuda"

    def test_custom_device(self):
        det = ObjectDetector(device="cpu")
        assert det.device == "cpu"

    def test_model_initially_none(self, detector):
        assert detector._model is None


class TestDetectionPrompts:
    def test_prompts_include_base_cabinet(self):
        assert "base cabinet" in DETECTION_PROMPTS

    def test_prompts_include_upper_cabinet(self):
        assert "upper cabinet" in DETECTION_PROMPTS

    def test_prompts_include_appliances(self):
        assert "refrigerator" in DETECTION_PROMPTS
        assert "range" in DETECTION_PROMPTS
        assert "dishwasher" in DETECTION_PROMPTS
        assert "sink" in DETECTION_PROMPTS


class TestObjectDetectorDetect:
    def test_raises_on_empty_frames(self, detector, calibration):
        with pytest.raises(ObjectDetectionError, match="No frames"):
            detector.detect([], calibration)

    def test_no_detections_returns_zero_counts(self, detector, calibration):
        depth_frames = [make_depth_frame()]
        # _run_sam3 returns [] by default (placeholder)
        result = detector.detect(depth_frames, calibration)

        assert isinstance(result, ObjectDetectionResult)
        assert result.total_objects == 0
        assert result.base_cabinet_count == 0
        assert result.upper_cabinet_count == 0
        assert result.appliance_count == 0

    def test_detections_counted_by_type(self, detector, calibration):
        depth_frames = [make_depth_frame()]

        def mock_sam3(image, prompt):
            if prompt == "base cabinet":
                return [{"bbox": [100, 100, 200, 300], "confidence": 0.9}]
            if prompt == "upper cabinet":
                return [{"bbox": [100, 50, 200, 150], "confidence": 0.85}]
            if prompt == "refrigerator":
                return [{"bbox": [400, 50, 500, 400], "confidence": 0.95}]
            return []

        detector._run_sam3 = mock_sam3
        result = detector.detect(depth_frames, calibration)

        assert result.base_cabinet_count == 1
        assert result.upper_cabinet_count == 1
        assert result.appliance_count == 1
        assert result.total_objects == 3

    def test_multiple_frames_aggregated(self, detector, calibration):
        depth_frames = [make_depth_frame(0), make_depth_frame(1)]

        call_count = {"n": 0}

        def mock_sam3(image, prompt):
            if prompt == "base cabinet":
                call_count["n"] += 1
                # Return different bboxes in different spatial regions per frame
                # so they don't get merged by _track_instances
                x_offset = call_count["n"] * 200
                return [{"bbox": [x_offset, 100, x_offset + 100, 300], "confidence": 0.9}]
            return []

        detector._run_sam3 = mock_sam3
        result = detector.detect(depth_frames, calibration)

        # Two base cabinets from separate frames in different spatial regions
        assert result.base_cabinet_count == 2

    def test_result_type(self, detector, calibration):
        depth_frames = [make_depth_frame()]
        result = detector.detect(depth_frames, calibration)
        assert isinstance(result, ObjectDetectionResult)
        assert isinstance(result.objects, list)


class TestMeasureObject:
    def test_valid_bbox_returns_measurements(self, detector):
        depth_map = np.full((480, 640), 2.5, dtype=np.float32)
        bbox = (100, 100, 300, 400)

        w, h, d = detector._measure_object(depth_map, bbox, scale_factor=1.0)

        assert w > 0
        assert h > 0
        assert d > 0

    def test_zero_area_bbox_returns_zeros(self, detector):
        depth_map = np.full((480, 640), 2.5, dtype=np.float32)
        bbox = (100, 100, 100, 100)  # zero-area

        w, h, d = detector._measure_object(depth_map, bbox, scale_factor=1.0)

        assert w == 0.0
        assert h == 0.0
        assert d == 0.0

    def test_bbox_clamped_to_image_bounds(self, detector):
        depth_map = np.full((480, 640), 2.5, dtype=np.float32)
        bbox = (-10, -10, 700, 500)  # exceeds image

        w, h, d = detector._measure_object(depth_map, bbox, scale_factor=1.0)

        # Should still produce valid measurements from clamped region
        assert w > 0
        assert h > 0

    def test_scale_factor_affects_result(self, detector):
        depth_map = np.full((480, 640), 2.5, dtype=np.float32)
        bbox = (100, 100, 300, 400)

        w1, h1, d1 = detector._measure_object(depth_map, bbox, scale_factor=1.0)
        w2, h2, d2 = detector._measure_object(depth_map, bbox, scale_factor=2.0)

        assert w2 == pytest.approx(w1 * 2, rel=0.01)
        assert h2 == pytest.approx(h1 * 2, rel=0.01)

    def test_all_zero_depth_returns_zeros(self, detector):
        depth_map = np.zeros((480, 640), dtype=np.float32)
        bbox = (100, 100, 300, 400)

        w, h, d = detector._measure_object(depth_map, bbox, scale_factor=1.0)

        assert w == 0.0
        assert h == 0.0
        assert d == 0.0


class TestTrackInstances:
    def test_empty_list(self, detector):
        assert detector._track_instances([]) == []

    def test_single_object_kept(self, detector):
        obj = make_detected_object()
        result = detector._track_instances([obj])
        assert len(result) == 1

    def test_duplicate_same_region_merged(self, detector):
        # Two detections in the same spatial bucket (bbox[0]//100 and bbox[1]//100 match)
        obj1 = make_detected_object(confidence=0.7, frame_index=0)
        obj2 = make_detected_object(confidence=0.9, frame_index=1)

        result = detector._track_instances([obj1, obj2])

        # Should keep the higher-confidence one
        assert len(result) == 1
        assert result[0].confidence == 0.9

    def test_different_labels_kept_separate(self, detector):
        obj1 = make_detected_object(label="base cabinet")
        obj2 = make_detected_object(label="upper cabinet")

        result = detector._track_instances([obj1, obj2])
        assert len(result) == 2

    def test_different_regions_kept_separate(self, detector):
        obj1 = DetectedObject(
            label="base cabinet", instance_id=0,
            bbox=(50, 50, 150, 200), mask=None,
            width_inches=24.0, height_inches=34.5, depth_inches=98.0,
            confidence=0.9, frame_index=0,
        )
        obj2 = DetectedObject(
            label="base cabinet", instance_id=1,
            bbox=(350, 50, 450, 200), mask=None,
            width_inches=24.0, height_inches=34.5, depth_inches=98.0,
            confidence=0.9, frame_index=0,
        )

        result = detector._track_instances([obj1, obj2])
        assert len(result) == 2


class TestDetectedObjectDataclass:
    def test_standard_width_defaults_to_none(self):
        obj = make_detected_object()
        assert obj.standard_width_inches is None
        assert obj.deviation_inches is None

    def test_fields_stored_correctly(self):
        obj = DetectedObject(
            label="sink",
            instance_id=5,
            bbox=(10, 20, 30, 40),
            mask=None,
            width_inches=33.0,
            height_inches=22.0,
            depth_inches=60.0,
            confidence=0.75,
            frame_index=2,
            standard_width_inches=33.0,
            deviation_inches=0.0,
        )
        assert obj.label == "sink"
        assert obj.instance_id == 5
        assert obj.standard_width_inches == 33.0
        assert obj.deviation_inches == 0.0
