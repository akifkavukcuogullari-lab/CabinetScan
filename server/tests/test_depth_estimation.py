"""Tests for Stage 2: Depth Estimation."""

import numpy as np
import pytest
from unittest.mock import MagicMock, patch

from pipeline.stages.depth_estimation import DepthEstimator, DepthFrame
from pipeline.stages.frame_extraction import ExtractedFrame
from pipeline.utils.errors import DepthEstimationError


def make_frame(index: int = 0, h: int = 480, w: int = 640) -> ExtractedFrame:
    """Create a mock ExtractedFrame."""
    return ExtractedFrame(
        image=np.random.randint(0, 255, (h, w, 3), dtype=np.uint8),
        timestamp=index * 0.5,
        frame_index=index,
        blur_score=200.0,
    )


def make_depth_map(h: int = 480, w: int = 640, base: float = 2.5) -> np.ndarray:
    """Create a synthetic depth map with realistic values."""
    # Gaussian-ish depth centered around base meters
    depth = np.full((h, w), base, dtype=np.float32)
    depth += np.random.normal(0, 0.1, (h, w)).astype(np.float32)
    depth = np.clip(depth, 0.1, 10.0)
    return depth


@pytest.fixture
def estimator():
    return DepthEstimator(device="cpu")


class TestDepthEstimatorInit:
    def test_default_device_is_cuda(self):
        est = DepthEstimator()
        assert est.device == "cuda"

    def test_custom_device(self):
        est = DepthEstimator(device="cpu")
        assert est.device == "cpu"

    def test_model_initially_none(self, estimator):
        assert estimator._model is None


class TestDepthEstimatorEstimate:
    def test_raises_if_model_not_loaded(self, estimator):
        frames = [make_frame()]
        with pytest.raises(DepthEstimationError, match="Model not loaded"):
            estimator.estimate(frames)

    def test_raises_on_empty_frames(self, estimator):
        estimator._model = MagicMock()
        with pytest.raises(DepthEstimationError, match="No frames"):
            estimator.estimate([])

    def test_single_frame_produces_depth_frame(self, estimator):
        frame = make_frame()
        depth_map = make_depth_map()

        mock_model = MagicMock()
        mock_model.return_value = {"depth": depth_map}
        estimator._model = mock_model

        result = estimator.estimate([frame])

        assert len(result) == 1
        assert isinstance(result[0], DepthFrame)
        assert result[0].frame is frame
        assert result[0].depth_map.shape == depth_map.shape

    def test_multiple_frames(self, estimator):
        frames = [make_frame(i) for i in range(5)]
        depth_map = make_depth_map()

        mock_model = MagicMock()
        mock_model.return_value = {"depth": depth_map}
        estimator._model = mock_model

        result = estimator.estimate(frames)
        assert len(result) == 5
        assert mock_model.call_count == 5

    def test_depth_statistics_computed(self, estimator):
        frame = make_frame()
        depth_map = make_depth_map(base=3.0)

        mock_model = MagicMock()
        mock_model.return_value = {"depth": depth_map}
        estimator._model = mock_model

        result = estimator.estimate([frame])
        df = result[0]

        assert df.min_depth > 0
        assert df.max_depth > df.min_depth
        assert df.min_depth <= df.median_depth <= df.max_depth

    def test_zero_depth_excluded_from_min(self, estimator):
        frame = make_frame(h=10, w=10)
        depth_map = np.zeros((10, 10), dtype=np.float32)
        depth_map[5, 5] = 2.0  # one non-zero pixel

        mock_model = MagicMock()
        mock_model.return_value = {"depth": depth_map}
        estimator._model = mock_model

        result = estimator.estimate([frame])
        df = result[0]

        assert df.min_depth == pytest.approx(2.0)
        assert df.median_depth == pytest.approx(2.0)

    def test_all_zero_depth_gives_zero_stats(self, estimator):
        frame = make_frame(h=10, w=10)
        depth_map = np.zeros((10, 10), dtype=np.float32)

        mock_model = MagicMock()
        mock_model.return_value = {"depth": depth_map}
        estimator._model = mock_model

        result = estimator.estimate([frame])
        df = result[0]

        assert df.min_depth == 0
        assert df.median_depth == 0

    def test_depth_map_resized_if_mismatch(self, estimator):
        frame = make_frame(h=480, w=640)
        # Model returns a different-sized depth map
        depth_map = make_depth_map(h=240, w=320)

        mock_model = MagicMock()
        mock_model.return_value = {"depth": depth_map}
        estimator._model = mock_model

        import cv2
        resized = make_depth_map(h=480, w=640)
        with patch.object(cv2, "resize", return_value=resized) as mock_resize:
            result = estimator.estimate([frame])

            mock_resize.assert_called_once()
            assert result[0].depth_map.shape == (480, 640)

    def test_model_exception_wrapped(self, estimator):
        frame = make_frame()

        mock_model = MagicMock()
        mock_model.side_effect = RuntimeError("GPU OOM")
        estimator._model = mock_model

        with pytest.raises(DepthEstimationError, match="frame 0"):
            estimator.estimate([frame])

    def test_bgr_to_rgb_conversion(self, estimator):
        frame = make_frame()
        depth_map = make_depth_map()

        mock_model = MagicMock()
        mock_model.return_value = {"depth": depth_map}
        estimator._model = mock_model

        estimator.estimate([frame])

        # The model should receive the RGB-flipped image
        call_args = mock_model.call_args[0][0]
        # Verify it was flipped (BGR[:,:,::-1] = RGB)
        np.testing.assert_array_equal(call_args, frame.image[:, :, ::-1])


class TestDepthEstimatorLoadModel:
    def test_load_model_failure_raises(self):
        est = DepthEstimator(device="cpu")
        # The import happens inside load_model(), so mock the transformers module
        mock_transformers = MagicMock()
        mock_transformers.pipeline.side_effect = RuntimeError("model not found")
        with patch.dict("sys.modules", {"transformers": mock_transformers}):
            with pytest.raises(DepthEstimationError, match="Failed to load"):
                est.load_model()
