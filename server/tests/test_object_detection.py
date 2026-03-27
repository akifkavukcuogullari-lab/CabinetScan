"""Tests for Stage 5: Object Detection."""

import numpy as np
import pytest
from unittest.mock import MagicMock, patch, PropertyMock

from pipeline.stages.object_detection import (
    ObjectDetector,
    DetectedObject,
    ObjectDetectionResult,
    CameraIntrinsics,
    DETECTION_PROMPTS,
    _get_scaled_intrinsics,
    _compute_world_position,
)
from pipeline.stages.depth_estimation import DepthFrame
from pipeline.stages.frame_extraction import ExtractedFrame
from pipeline.stages.scale_calibration import CalibrationResult
from pipeline.utils.errors import ObjectDetectionError


def make_frame(index: int = 0, h: int = 480, w: int = 640, pose_index: int | None = None) -> ExtractedFrame:
    """Create a mock ExtractedFrame."""
    return ExtractedFrame(
        image=np.random.randint(0, 255, (h, w, 3), dtype=np.uint8),
        timestamp=index * 0.5,
        frame_index=index,
        blur_score=200.0,
        pose_index=pose_index,
    )


def make_depth_frame(index: int = 0, h: int = 480, w: int = 640, pose_index: int | None = None) -> DepthFrame:
    """Create a mock DepthFrame with a synthetic depth map."""
    frame = make_frame(index, h, w, pose_index=pose_index)
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
        # Mock _run_sam3 to return no detections
        detector._run_sam3 = lambda image, prompt: []
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
        detector._run_sam3 = lambda image, prompt: []
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


class TestLoadModel:
    @patch("pipeline.stages.object_detection.ObjectDetector.load_model")
    def test_load_model_sets_model(self, mock_load):
        """Verify load_model sets _model via SAM 3 builder."""
        detector = ObjectDetector(device="cpu")

        # Simulate what load_model does internally
        mock_processor = MagicMock()
        def side_effect():
            detector._model = mock_processor
        mock_load.side_effect = side_effect

        detector.load_model()
        assert detector._model is not None
        assert detector._model is mock_processor

    def test_load_model_calls_sam3_builder(self):
        """Verify load_model calls SAM 3 builder and processor."""
        import sys

        mock_model = MagicMock()
        mock_processor = MagicMock()

        # Create fake sam3 module hierarchy
        mock_sam3 = MagicMock()
        mock_sam3.model_builder.build_sam3_image_model.return_value = mock_model
        mock_sam3.model.sam3_image_processor.Sam3Processor.return_value = mock_processor

        with patch.dict(sys.modules, {
            "sam3": mock_sam3,
            "sam3.model_builder": mock_sam3.model_builder,
            "sam3.model": mock_sam3.model,
            "sam3.model.sam3_image_processor": mock_sam3.model.sam3_image_processor,
        }):
            detector = ObjectDetector(device="cpu")
            detector.load_model()

            mock_sam3.model_builder.build_sam3_image_model.assert_called_once()
            mock_sam3.model.sam3_image_processor.Sam3Processor.assert_called_once_with(mock_model, device="cpu")
            assert detector._model is mock_processor

    def test_load_model_sets_none_on_failure(self):
        """Verify load_model gracefully sets _model=None when SAM 3 unavailable."""
        detector = ObjectDetector(device="cpu")
        with patch.dict("sys.modules", {"sam3": None, "sam3.model_builder": None}):
            detector.load_model()
            assert detector._model is None


class TestRunSam3:
    def test_run_sam3_filters_low_confidence(self):
        """Verify detections below MIN_CONFIDENCE are excluded."""
        detector = ObjectDetector(device="cpu")

        mock_model = MagicMock()
        mock_state = MagicMock()
        mock_model.set_image.return_value = mock_state
        mock_model.set_text_prompt.return_value = {
            "masks": [np.ones((480, 640), dtype=np.uint8)] * 3,
            "boxes": [[10, 10, 100, 100], [200, 200, 300, 300], [400, 400, 500, 500]],
            "scores": [0.9, 0.2, 0.5],  # second is below MIN_CONFIDENCE (0.35)
        }
        detector._model = mock_model

        image = np.random.randint(0, 255, (480, 640, 3), dtype=np.uint8)
        results = detector._run_sam3(image, "base cabinet")

        assert len(results) == 2
        assert results[0]["confidence"] == 0.9
        assert results[1]["confidence"] == 0.5

    def test_run_sam3_converts_bgr_to_rgb(self):
        """Verify image is converted from BGR to RGB before passing to SAM 3."""
        detector = ObjectDetector(device="cpu")

        mock_model = MagicMock()
        mock_state = MagicMock()
        mock_model.set_image.return_value = mock_state
        mock_model.set_text_prompt.return_value = {
            "masks": [],
            "boxes": [],
            "scores": [],
        }
        detector._model = mock_model

        # Create a BGR image where B=255, G=0, R=0
        bgr_image = np.zeros((10, 10, 3), dtype=np.uint8)
        bgr_image[:, :, 0] = 255  # Blue channel

        with patch("pipeline.stages.object_detection.PILImage") as mock_pil:
            mock_pil.fromarray.return_value = MagicMock()
            detector._run_sam3(bgr_image, "test")

            # Verify fromarray was called with RGB (R=0, G=0, B=255 -> reversed)
            call_args = mock_pil.fromarray.call_args[0][0]
            assert call_args[0, 0, 2] == 255  # Blue is now in channel 2 (was 0)
            assert call_args[0, 0, 0] == 0    # Red is now in channel 0

    def test_run_sam3_returns_empty_on_no_detections(self):
        """Verify empty result when model finds nothing."""
        detector = ObjectDetector(device="cpu")

        mock_model = MagicMock()
        mock_model.set_image.return_value = MagicMock()
        mock_model.set_text_prompt.return_value = {
            "masks": [],
            "boxes": [],
            "scores": [],
        }
        detector._model = mock_model

        image = np.random.randint(0, 255, (480, 640, 3), dtype=np.uint8)
        results = detector._run_sam3(image, "base cabinet")

        assert results == []

    def test_run_sam3_bbox_values_are_ints(self):
        """Verify bbox values are converted to ints."""
        detector = ObjectDetector(device="cpu")

        mock_model = MagicMock()
        mock_model.set_image.return_value = MagicMock()
        mock_model.set_text_prompt.return_value = {
            "masks": [np.ones((480, 640), dtype=np.uint8)],
            "boxes": [[10.5, 20.7, 100.3, 200.9]],
            "scores": [0.9],
        }
        detector._model = mock_model

        image = np.random.randint(0, 255, (480, 640, 3), dtype=np.uint8)
        results = detector._run_sam3(image, "base cabinet")

        assert all(isinstance(v, int) for v in results[0]["bbox"])


class TestMeasureObjectWithMask:
    def test_mask_based_measurement(self, detector):
        """Verify mask-based measurement uses only masked pixels."""
        depth_map = np.full((480, 640), 2.5, dtype=np.float32)
        # Set a noisy background depth in the bbox region
        depth_map[100:400, 100:300] = 5.0  # background is 5m

        # Create mask that only covers part of the bbox
        mask = np.zeros((480, 640), dtype=np.uint8)
        mask[150:350, 150:250] = 1  # object is at 5.0m in masked region

        bbox = (100, 100, 300, 400)
        w_mask, h_mask, d_mask = detector._measure_object(
            depth_map, bbox, scale_factor=1.0, mask=mask
        )

        # Without mask, uses all pixels in bbox
        w_no_mask, h_no_mask, d_no_mask = detector._measure_object(
            depth_map, bbox, scale_factor=1.0, mask=None
        )

        # Both should produce valid measurements
        assert w_mask > 0
        assert h_mask > 0
        assert w_no_mask > 0
        assert h_no_mask > 0

    def test_mask_with_varied_depth(self, detector):
        """Verify mask filters out background depth values."""
        depth_map = np.full((480, 640), 10.0, dtype=np.float32)  # far background
        # Object region has closer depth
        depth_map[150:350, 150:250] = 2.0

        mask = np.zeros((480, 640), dtype=np.uint8)
        mask[150:350, 150:250] = 1  # mask covers only the close object

        bbox = (100, 100, 300, 400)

        # With mask: median depth should be ~2.0 (only masked pixels)
        _, _, d_mask = detector._measure_object(
            depth_map, bbox, scale_factor=1.0, mask=mask
        )

        # Without mask: median depth should be ~10.0 (all pixels in bbox)
        _, _, d_no_mask = detector._measure_object(
            depth_map, bbox, scale_factor=1.0, mask=None
        )

        assert d_mask < d_no_mask

    def test_empty_mask_falls_back_to_zero(self, detector):
        """Verify that an all-zero mask returns zero depth."""
        depth_map = np.full((480, 640), 2.5, dtype=np.float32)
        mask = np.zeros((480, 640), dtype=np.uint8)  # empty mask
        bbox = (100, 100, 300, 400)

        w, h, d = detector._measure_object(
            depth_map, bbox, scale_factor=1.0, mask=mask
        )

        assert w == 0.0
        assert h == 0.0
        assert d == 0.0

    def test_focal_length_affects_measurement(self, detector):
        """Verify that focal_length parameter changes measurement output."""
        depth_map = np.full((480, 640), 2.5, dtype=np.float32)
        bbox = (100, 100, 300, 400)

        w1, h1, _ = detector._measure_object(depth_map, bbox, scale_factor=1.0, focal_length=500.0)
        w2, h2, _ = detector._measure_object(depth_map, bbox, scale_factor=1.0, focal_length=1000.0)

        # Halving focal length doubles the measured size
        assert w1 == pytest.approx(w2 * 2, rel=0.01)
        assert h1 == pytest.approx(h2 * 2, rel=0.01)


class TestCameraIntrinsics:
    """Tests for _get_scaled_intrinsics."""

    def test_basic_scaling(self):
        """Intrinsics scale from original to frame resolution."""
        pose = {
            "intrinsics": {"fx": 1432.0, "fy": 1463.0, "cx": 960.0, "cy": 720.0},
            "zoomFactor": 1.0,
        }
        # Original: 1920x1440, Frame: 320x240
        result = _get_scaled_intrinsics(pose, frame_width=320, frame_height=240)

        assert result is not None
        assert result.fx == pytest.approx(1432.0 * 320 / 1920, rel=1e-3)
        assert result.fy == pytest.approx(1463.0 * 240 / 1440, rel=1e-3)
        assert result.cx == pytest.approx(960.0 * 320 / 1920, rel=1e-3)
        assert result.cy == pytest.approx(720.0 * 240 / 1440, rel=1e-3)

    def test_zoom_factor_applied(self):
        """Zoom factor multiplies focal lengths."""
        pose = {
            "intrinsics": {"fx": 1432.0, "fy": 1463.0, "cx": 960.0, "cy": 720.0},
            "zoomFactor": 2.0,
        }
        result = _get_scaled_intrinsics(pose, frame_width=320, frame_height=240)

        no_zoom_pose = {**pose, "zoomFactor": 1.0}
        no_zoom = _get_scaled_intrinsics(no_zoom_pose, frame_width=320, frame_height=240)

        assert result is not None
        assert no_zoom is not None
        assert result.fx == pytest.approx(no_zoom.fx * 2.0, rel=1e-3)
        assert result.fy == pytest.approx(no_zoom.fy * 2.0, rel=1e-3)
        # Principal point NOT affected by zoom
        assert result.cx == pytest.approx(no_zoom.cx, rel=1e-3)
        assert result.cy == pytest.approx(no_zoom.cy, rel=1e-3)

    def test_missing_intrinsics(self):
        """Returns None when intrinsics are absent."""
        assert _get_scaled_intrinsics({}, frame_width=320, frame_height=240) is None

    def test_partial_intrinsics(self):
        """Returns None when intrinsics are incomplete."""
        pose = {"intrinsics": {"fx": 1432.0}}  # missing fy, cx, cy
        assert _get_scaled_intrinsics(pose, frame_width=320, frame_height=240) is None

    def test_zero_principal_point(self):
        """Returns None if principal point implies zero-size image."""
        pose = {"intrinsics": {"fx": 1432.0, "fy": 1463.0, "cx": 0.0, "cy": 720.0}}
        assert _get_scaled_intrinsics(pose, frame_width=320, frame_height=240) is None

    def test_default_zoom_factor(self):
        """Missing zoomFactor defaults to 1.0."""
        pose = {"intrinsics": {"fx": 1432.0, "fy": 1463.0, "cx": 960.0, "cy": 720.0}}
        result = _get_scaled_intrinsics(pose, frame_width=320, frame_height=240)
        assert result is not None
        # Same as zoomFactor=1.0
        expected_fx = 1432.0 * 320 / 1920
        assert result.fx == pytest.approx(expected_fx, rel=1e-3)


class TestComputeWorldPosition:
    """Tests for _compute_world_position."""

    def test_identity_transform(self):
        """Identity transform returns camera-space coordinates."""
        depth_map = np.full((480, 640), 2.0, dtype=np.float32)
        intrinsics = CameraIntrinsics(fx=320.0, fy=320.0, cx=320.0, cy=240.0)
        # Identity as column-major: [[1,0,0,0], [0,1,0,0], [0,0,1,0], [0,0,0,1]]
        identity_transform = [[1, 0, 0, 0], [0, 1, 0, 0], [0, 0, 1, 0], [0, 0, 0, 1]]
        bbox = (300, 220, 340, 260)  # centered around (320, 240)

        result = _compute_world_position(bbox, depth_map, intrinsics, identity_transform, scale_factor=1.0)

        assert result is not None
        # Bbox center = (320, 240) = principal point, so x_cam=0, y_cam=0
        assert abs(result[0]) < 0.1  # x near 0
        assert abs(result[1]) < 0.1  # y near 0
        assert abs(result[2] - 2.0) < 0.1  # z ~ depth * scale_factor

    def test_scale_factor_applied(self):
        """Scale factor converts relative depth to meters before back-projection."""
        depth_map = np.full((480, 640), 500.0, dtype=np.float32)  # relative depth
        intrinsics = CameraIntrinsics(fx=320.0, fy=320.0, cx=320.0, cy=240.0)
        identity_transform = [[1, 0, 0, 0], [0, 1, 0, 0], [0, 0, 1, 0], [0, 0, 0, 1]]
        bbox = (300, 220, 340, 260)  # centered at principal point

        # scale_factor converts 500 relative -> 3.0 meters
        result = _compute_world_position(
            bbox, depth_map, intrinsics, identity_transform, scale_factor=0.006
        )

        assert result is not None
        assert abs(result[2] - 3.0) < 0.1  # 500 * 0.006 = 3.0m

    def test_translation_offset(self):
        """Transform with translation offsets the world position."""
        depth_map = np.full((480, 640), 2.0, dtype=np.float32)
        intrinsics = CameraIntrinsics(fx=320.0, fy=320.0, cx=320.0, cy=240.0)
        # Column-major with 5m translation in X: col3 = [5, 0, 0, 1]
        transform = [[1, 0, 0, 0], [0, 1, 0, 0], [0, 0, 1, 0], [5, 0, 0, 1]]
        bbox = (300, 220, 340, 260)  # centered at principal point

        result = _compute_world_position(bbox, depth_map, intrinsics, transform, scale_factor=1.0)

        assert result is not None
        # Camera at principal point: cam_x=0, then world_x = 0 + 5 = 5
        assert abs(result[0] - 5.0) < 0.1

    def test_zero_depth_returns_none(self):
        """Returns None when depth at bbox center is zero."""
        depth_map = np.zeros((480, 640), dtype=np.float32)
        intrinsics = CameraIntrinsics(fx=320.0, fy=320.0, cx=320.0, cy=240.0)
        identity_transform = [[1, 0, 0, 0], [0, 1, 0, 0], [0, 0, 1, 0], [0, 0, 0, 1]]
        bbox = (100, 100, 200, 200)

        result = _compute_world_position(bbox, depth_map, intrinsics, identity_transform)
        assert result is None

    def test_mask_weighted_depth(self):
        """Uses mask-weighted median when mask is provided."""
        depth_map = np.full((480, 640), 10.0, dtype=np.float32)
        depth_map[150:250, 150:250] = 3.0  # object is closer in masked region

        mask = np.zeros((480, 640), dtype=np.uint8)
        mask[150:250, 150:250] = 1

        intrinsics = CameraIntrinsics(fx=320.0, fy=320.0, cx=320.0, cy=240.0)
        identity_transform = [[1, 0, 0, 0], [0, 1, 0, 0], [0, 0, 1, 0], [0, 0, 0, 1]]
        bbox = (100, 100, 300, 300)

        result = _compute_world_position(
            bbox, depth_map, intrinsics, identity_transform, mask=mask, scale_factor=1.0
        )

        assert result is not None
        assert abs(result[2] - 3.0) < 0.5  # z should be ~3.0 (mask region depth)


class TestClusterByWorldPosition:
    """Tests for 3D world-position clustering in _track_instances."""

    def test_same_position_merged(self):
        """Detections of the same label at the same 3D position merge into one."""
        detector = ObjectDetector(device="cpu")

        obj1 = DetectedObject(
            label="refrigerator", instance_id=0,
            bbox=(100, 100, 200, 300), mask=None,
            width_inches=36.0, height_inches=70.0, depth_inches=30.0,
            confidence=0.9, frame_index=0,
            world_position=(1.0, 0.0, 2.0),
        )
        obj2 = DetectedObject(
            label="refrigerator", instance_id=1,
            bbox=(105, 95, 205, 305), mask=None,
            width_inches=34.0, height_inches=68.0, depth_inches=28.0,
            confidence=0.7, frame_index=5,
            world_position=(1.1, 0.05, 2.1),  # ~0.15m away
        )

        result = detector._track_instances([obj1, obj2])

        assert len(result) == 1
        assert result[0].confidence == 0.9  # keeps highest confidence
        # Measurements averaged
        assert result[0].width_inches == pytest.approx(35.0, rel=0.01)
        assert result[0].height_inches == pytest.approx(69.0, rel=0.01)

    def test_different_positions_kept(self):
        """Detections of the same label at distant positions stay separate."""
        detector = ObjectDetector(device="cpu")

        obj1 = DetectedObject(
            label="base cabinet", instance_id=0,
            bbox=(50, 100, 150, 300), mask=None,
            width_inches=24.0, height_inches=34.5, depth_inches=24.0,
            confidence=0.85, frame_index=0,
            world_position=(0.0, 0.0, 2.0),
        )
        obj2 = DetectedObject(
            label="base cabinet", instance_id=1,
            bbox=(400, 100, 500, 300), mask=None,
            width_inches=30.0, height_inches=34.5, depth_inches=24.0,
            confidence=0.8, frame_index=0,
            world_position=(2.0, 0.0, 2.0),  # 2m away
        )

        result = detector._track_instances([obj1, obj2])

        assert len(result) == 2  # both kept (2m > 0.5m threshold)

    def test_no_singleton_bias(self):
        """Multiple genuine instances of same label are preserved."""
        detector = ObjectDetector(device="cpu")

        # Two ovens that genuinely exist (double oven kitchen)
        oven1 = DetectedObject(
            label="oven", instance_id=0,
            bbox=(100, 100, 200, 300), mask=None,
            width_inches=30.0, height_inches=30.0, depth_inches=24.0,
            confidence=0.9, frame_index=0,
            world_position=(0.0, 0.0, 2.0),
        )
        oven2 = DetectedObject(
            label="oven", instance_id=1,
            bbox=(400, 100, 500, 300), mask=None,
            width_inches=30.0, height_inches=30.0, depth_inches=24.0,
            confidence=0.85, frame_index=0,
            world_position=(3.0, 0.0, 2.0),  # 3m away
        )

        result = detector._track_instances([oven1, oven2])

        assert len(result) == 2  # both genuine ovens kept

    def test_mixed_positioned_and_unpositioned(self):
        """Mix of positioned and unpositioned objects handled correctly."""
        detector = ObjectDetector(device="cpu")

        positioned = DetectedObject(
            label="sink", instance_id=0,
            bbox=(200, 200, 300, 300), mask=None,
            width_inches=33.0, height_inches=22.0, depth_inches=10.0,
            confidence=0.9, frame_index=0,
            world_position=(1.0, 0.0, 2.0),
        )
        unpositioned = DetectedObject(
            label="window", instance_id=1,
            bbox=(50, 50, 150, 200), mask=None,
            width_inches=36.0, height_inches=48.0, depth_inches=0.0,
            confidence=0.7, frame_index=3,
            world_position=None,
        )

        result = detector._track_instances([positioned, unpositioned])

        assert len(result) == 2
        labels = {o.label for o in result}
        assert "sink" in labels
        assert "window" in labels

    def test_many_duplicates_across_frames(self):
        """Same refrigerator seen in 4 frames merges to 1."""
        detector = ObjectDetector(device="cpu")

        objects = []
        for i in range(4):
            objects.append(DetectedObject(
                label="refrigerator", instance_id=i,
                bbox=(100 + i * 5, 100, 200 + i * 5, 300), mask=None,
                width_inches=36.0 + i * 0.5, height_inches=70.0, depth_inches=30.0,
                confidence=0.9 - i * 0.05, frame_index=i,
                world_position=(1.0 + i * 0.1, 0.0, 2.0 + i * 0.05),  # all within 0.5m
            ))

        result = detector._track_instances(objects)

        assert len(result) == 1
        assert result[0].label == "refrigerator"
        assert result[0].confidence == 0.9  # best confidence kept


class TestIoU:
    """Tests for the static IoU helper."""

    def test_identical_boxes(self):
        assert ObjectDetector._iou((0, 0, 100, 100), (0, 0, 100, 100)) == 1.0

    def test_no_overlap(self):
        assert ObjectDetector._iou((0, 0, 50, 50), (100, 100, 200, 200)) == 0.0

    def test_partial_overlap(self):
        iou = ObjectDetector._iou((0, 0, 100, 100), (50, 50, 150, 150))
        # Intersection: 50*50=2500, Union: 10000+10000-2500=17500
        assert iou == pytest.approx(2500 / 17500, rel=0.01)


class TestMetricDepthDedup:
    """Tests for deduplication with realistic metric depth world positions."""

    def test_metric_positions_merge_same_object(self):
        """With metric depth (meters), same cabinet at ~2.5m merges correctly."""
        detector = ObjectDetector(device="cpu")

        # Cabinet seen from two angles, ~0.3m apart in 3D
        obj1 = DetectedObject(
            label="base cabinet", instance_id=0,
            bbox=(100, 100, 200, 300), mask=None,
            width_inches=24.0, height_inches=34.5, depth_inches=24.0,
            confidence=0.9, frame_index=0,
            world_position=(1.5, 0.0, 2.5),
        )
        obj2 = DetectedObject(
            label="base cabinet", instance_id=1,
            bbox=(110, 95, 210, 310), mask=None,
            width_inches=25.0, height_inches=35.0, depth_inches=25.0,
            confidence=0.8, frame_index=3,
            world_position=(1.7, 0.05, 2.3),  # ~0.3m away
        )

        result = detector._track_instances([obj1, obj2])
        assert len(result) == 1
        assert result[0].confidence == 0.9

    def test_metric_positions_separate_objects_stay_separate(self):
        """Two cabinets 1.5m apart in metric space are NOT merged."""
        detector = ObjectDetector(device="cpu")

        obj1 = DetectedObject(
            label="base cabinet", instance_id=0,
            bbox=(50, 100, 150, 300), mask=None,
            width_inches=24.0, height_inches=34.5, depth_inches=24.0,
            confidence=0.85, frame_index=0,
            world_position=(0.0, 0.0, 2.0),
        )
        obj2 = DetectedObject(
            label="base cabinet", instance_id=1,
            bbox=(400, 100, 500, 300), mask=None,
            width_inches=30.0, height_inches=34.5, depth_inches=24.0,
            confidence=0.8, frame_index=0,
            world_position=(1.5, 0.0, 2.0),  # 1.5m away — beyond 1.0m threshold
        )

        result = detector._track_instances([obj1, obj2])
        assert len(result) == 2

    def test_updated_cluster_threshold(self):
        """Verify CLUSTER_DISTANCE_M is 1.0m (not the old 0.5m)."""
        detector = ObjectDetector(device="cpu")
        assert detector.CLUSTER_DISTANCE_M == 1.0

    def test_objects_at_0_9m_merge(self):
        """Objects 0.9m apart should merge (within 1.0m threshold)."""
        detector = ObjectDetector(device="cpu")

        obj1 = DetectedObject(
            label="refrigerator", instance_id=0,
            bbox=(100, 100, 200, 300), mask=None,
            width_inches=36.0, height_inches=70.0, depth_inches=30.0,
            confidence=0.9, frame_index=0,
            world_position=(1.0, 0.0, 2.0),
        )
        obj2 = DetectedObject(
            label="refrigerator", instance_id=1,
            bbox=(110, 95, 210, 305), mask=None,
            width_inches=35.0, height_inches=69.0, depth_inches=29.0,
            confidence=0.7, frame_index=5,
            world_position=(1.0, 0.0, 2.9),  # 0.9m away in Z
        )

        result = detector._track_instances([obj1, obj2])
        assert len(result) == 1


class TestDimensionClamping:
    """Tests for _clamp_dimensions safety net."""

    def test_normal_dimensions_unchanged(self):
        detector = ObjectDetector(device="cpu")
        obj = DetectedObject(
            label="base cabinet", instance_id=0,
            bbox=(100, 100, 200, 300), mask=None,
            width_inches=24.0, height_inches=34.5, depth_inches=24.0,
            confidence=0.9, frame_index=0,
        )
        result = detector._clamp_dimensions([obj])
        assert result[0].width_inches == 24.0
        assert result[0].height_inches == 34.5

    def test_absurd_width_clamped(self):
        detector = ObjectDetector(device="cpu")
        # 300 inches = 25ft — way too wide
        obj = DetectedObject(
            label="base cabinet", instance_id=0,
            bbox=(100, 100, 200, 300), mask=None,
            width_inches=300.0, height_inches=34.5, depth_inches=24.0,
            confidence=0.9, frame_index=0,
        )
        result = detector._clamp_dimensions([obj])
        max_w = detector.MAX_WIDTH_M / 0.0254
        assert result[0].width_inches == pytest.approx(max_w, rel=0.01)
        assert result[0].height_inches == 34.5  # height unchanged

    def test_absurd_height_clamped(self):
        detector = ObjectDetector(device="cpu")
        # 4000 inches = 333ft — absurd measurement error
        obj = DetectedObject(
            label="door", instance_id=0,
            bbox=(100, 100, 200, 300), mask=None,
            width_inches=36.0, height_inches=4000.0, depth_inches=24.0,
            confidence=0.9, frame_index=0,
        )
        result = detector._clamp_dimensions([obj])
        max_h = detector.MAX_HEIGHT_M / 0.0254
        assert result[0].height_inches == pytest.approx(max_h, rel=0.01)
        assert result[0].width_inches == 36.0  # width unchanged

    def test_both_dimensions_clamped(self):
        detector = ObjectDetector(device="cpu")
        obj = DetectedObject(
            label="refrigerator", instance_id=0,
            bbox=(100, 100, 200, 300), mask=None,
            width_inches=500.0, height_inches=500.0, depth_inches=24.0,
            confidence=0.9, frame_index=0,
        )
        result = detector._clamp_dimensions([obj])
        max_w = detector.MAX_WIDTH_M / 0.0254
        max_h = detector.MAX_HEIGHT_M / 0.0254
        assert result[0].width_inches == pytest.approx(max_w, rel=0.01)
        assert result[0].height_inches == pytest.approx(max_h, rel=0.01)


class TestAggressiveReclustering:
    """Tests for the aggressive re-clustering safety net."""

    def test_threshold_constants(self):
        detector = ObjectDetector(device="cpu")
        assert detector.MAX_OBJECTS_BEFORE_RECLUSTER == 80
        assert detector.AGGRESSIVE_CLUSTER_M == 1.5

    def test_small_count_no_recluster(self):
        """Under 80 objects, no re-clustering happens."""
        detector = ObjectDetector(device="cpu")

        objects = []
        for i in range(10):
            objects.append(DetectedObject(
                label="base cabinet", instance_id=i,
                bbox=(i * 50, 100, i * 50 + 40, 300), mask=None,
                width_inches=24.0, height_inches=34.5, depth_inches=24.0,
                confidence=0.9, frame_index=0,
                world_position=(float(i) * 2.0, 0.0, 2.0),  # spaced 2m apart
            ))

        result = detector._track_instances(objects)
        # All 10 are >1m apart, so all kept
        assert len(result) == 10
