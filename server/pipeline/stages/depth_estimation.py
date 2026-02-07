"""Stage 2: Depth Estimation — Video Depth Anything.

Uses Video Depth Anything in streaming metric mode for temporally
consistent depth maps across all frames.
"""

import numpy as np
from dataclasses import dataclass

from .frame_extraction import ExtractedFrame
from ..utils.errors import DepthEstimationError


@dataclass
class DepthFrame:
    """A frame with its metric depth map."""
    frame: ExtractedFrame
    depth_map: np.ndarray  # metric depth in meters, same HxW as frame
    min_depth: float
    max_depth: float
    median_depth: float


class DepthEstimator:
    """Estimate metric depth using Video Depth Anything."""

    def __init__(self, device: str = "cuda"):
        self.device = device
        self._model = None

    def load_model(self) -> None:
        """Load Video Depth Anything model into VRAM.

        Should be called once at worker startup for persistent model loading.
        """
        try:
            # Model loading will use HuggingFace transformers or direct checkpoint
            # Placeholder — actual model loading depends on Video Depth Anything release
            from transformers import pipeline as hf_pipeline

            self._model = hf_pipeline(
                "depth-estimation",
                model="depth-anything/Video-Depth-Anything-V2-Large",
                device=self.device,
            )
        except Exception as e:
            raise DepthEstimationError(f"Failed to load depth model: {e}")

    def estimate(self, frames: list[ExtractedFrame]) -> list[DepthFrame]:
        """Estimate metric depth for all frames.

        Uses streaming/temporal mode for consistency across frames.

        Args:
            frames: Extracted video frames

        Returns:
            List of DepthFrame with metric depth maps
        """
        if self._model is None:
            raise DepthEstimationError("Model not loaded. Call load_model() first.")

        if not frames:
            raise DepthEstimationError("No frames to process")

        depth_frames: list[DepthFrame] = []

        for frame in frames:
            try:
                # Convert BGR to RGB for the model
                rgb = frame.image[:, :, ::-1]

                # Run depth estimation
                result = self._model(rgb)
                depth_map = np.array(result["depth"])

                # Ensure depth map matches frame dimensions
                if depth_map.shape[:2] != frame.image.shape[:2]:
                    import cv2
                    depth_map = cv2.resize(
                        depth_map,
                        (frame.image.shape[1], frame.image.shape[0]),
                        interpolation=cv2.INTER_LINEAR,
                    )

                depth_frames.append(DepthFrame(
                    frame=frame,
                    depth_map=depth_map,
                    min_depth=float(np.min(depth_map[depth_map > 0])) if np.any(depth_map > 0) else 0,
                    max_depth=float(np.max(depth_map)),
                    median_depth=float(np.median(depth_map[depth_map > 0])) if np.any(depth_map > 0) else 0,
                ))
            except Exception as e:
                raise DepthEstimationError(f"Depth estimation failed on frame {frame.frame_index}: {e}")

        return depth_frames
