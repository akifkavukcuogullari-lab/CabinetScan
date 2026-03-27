"""Stage 2: Depth Estimation — Video Depth Anything.

Uses Video Depth Anything in streaming metric mode for temporally
consistent depth maps across all frames.
"""

import numpy as np
import torch
from dataclasses import dataclass
from PIL import Image

from .frame_extraction import ExtractedFrame
from ..utils.errors import DepthEstimationError


def _to_numpy(value) -> np.ndarray:
    """Convert a depth result to a numpy ndarray.

    Handles torch.Tensor (CUDA or CPU), PIL.Image, and plain arrays.
    """
    if isinstance(value, torch.Tensor):
        return value.detach().cpu().numpy()
    if isinstance(value, Image.Image):
        return np.array(value)
    return np.array(value)


@dataclass
class DepthFrame:
    """A frame with its metric depth map."""
    frame: ExtractedFrame
    depth_map: np.ndarray  # depth in meters (metric indoor model), same HxW as frame
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
            from transformers import pipeline as hf_pipeline

            model_id = "depth-anything/Depth-Anything-V2-Metric-Indoor-Large-hf"
            print(f"[DepthEstimator] Loading {model_id} on {self.device}...", flush=True)
            self._model = hf_pipeline(
                "depth-estimation",
                model=model_id,
                device=self.device,
            )
            print(f"[DepthEstimator] Model loaded OK", flush=True)
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
        print(f"[DepthEstimator] Processing {len(frames)} frames...", flush=True)

        for i, frame in enumerate(frames):
            try:
                # Convert BGR numpy array to RGB PIL Image (required by HF pipeline)
                rgb = frame.image[:, :, ::-1]
                pil_image = Image.fromarray(rgb)
                print(f"[DepthEstimator] Frame {i}/{len(frames)}: input shape={frame.image.shape}, PIL size={pil_image.size}", flush=True)

                # Run depth estimation
                result = self._model(pil_image)

                # Log what the model returned
                result_keys = list(result.keys()) if isinstance(result, dict) else type(result).__name__
                print(f"[DepthEstimator] Frame {i}: result keys={result_keys}", flush=True)
                for key in (result if isinstance(result, dict) else {}):
                    val = result[key]
                    if isinstance(val, torch.Tensor):
                        print(f"[DepthEstimator]   '{key}': Tensor shape={val.shape}, dtype={val.dtype}, device={val.device}", flush=True)
                    elif isinstance(val, Image.Image):
                        print(f"[DepthEstimator]   '{key}': PIL.Image size={val.size}, mode={val.mode}", flush=True)
                    elif isinstance(val, np.ndarray):
                        print(f"[DepthEstimator]   '{key}': ndarray shape={val.shape}, dtype={val.dtype}", flush=True)
                    else:
                        print(f"[DepthEstimator]   '{key}': {type(val).__name__}", flush=True)

                # Try predicted_depth (raw metric tensor) first, but validate
                # it's a proper 2D depth map. Fall back to depth (PIL Image).
                depth_map = None
                source_key = None
                if "predicted_depth" in result:
                    raw = _to_numpy(result["predicted_depth"])
                    print(f"[DepthEstimator] Frame {i}: predicted_depth raw shape={raw.shape}, dtype={raw.dtype}", flush=True)
                    # Only squeeze batch dim (axis 0) if shape is (1, H, W)
                    if raw.ndim == 3 and raw.shape[0] == 1:
                        raw = raw[0]
                        print(f"[DepthEstimator] Frame {i}: squeezed to shape={raw.shape}", flush=True)
                    # Use only if it's a proper 2D (H, W) depth map
                    if raw.ndim == 2:
                        depth_map = raw
                        source_key = "predicted_depth"
                    else:
                        print(f"[DepthEstimator] Frame {i}: predicted_depth not 2D (ndim={raw.ndim}), falling back to 'depth'", flush=True)

                if depth_map is None:
                    raw = _to_numpy(result["depth"])
                    print(f"[DepthEstimator] Frame {i}: depth raw shape={raw.shape}, dtype={raw.dtype}", flush=True)
                    # PIL Image may be (H, W, 3) RGB — take single channel
                    if raw.ndim == 3:
                        raw = raw[:, :, 0]
                        print(f"[DepthEstimator] Frame {i}: took channel 0, shape={raw.shape}", flush=True)
                    depth_map = raw
                    source_key = "depth"

                # Ensure float32 for downstream numpy operations
                depth_map = depth_map.astype(np.float32)

                # Ensure depth map matches frame dimensions
                if depth_map.shape[:2] != frame.image.shape[:2]:
                    import cv2
                    print(f"[DepthEstimator] Frame {i}: resizing depth {depth_map.shape} -> {frame.image.shape[:2]}", flush=True)
                    depth_map = cv2.resize(
                        depth_map,
                        (frame.image.shape[1], frame.image.shape[0]),
                        interpolation=cv2.INTER_LINEAR,
                    )

                min_d = float(np.min(depth_map[depth_map > 0])) if np.any(depth_map > 0) else 0
                max_d = float(np.max(depth_map))
                med_d = float(np.median(depth_map[depth_map > 0])) if np.any(depth_map > 0) else 0
                print(f"[DepthEstimator] Frame {i}: OK source='{source_key}' shape={depth_map.shape} depth=[{min_d:.3f}, {med_d:.3f}, {max_d:.3f}]", flush=True)

                depth_frames.append(DepthFrame(
                    frame=frame,
                    depth_map=depth_map,
                    min_depth=min_d,
                    max_depth=max_d,
                    median_depth=med_d,
                ))
            except Exception as e:
                raise DepthEstimationError(f"Depth estimation failed on frame {frame.frame_index}: {e}")

        print(f"[DepthEstimator] Done: {len(depth_frames)} depth frames produced", flush=True)

        return depth_frames
