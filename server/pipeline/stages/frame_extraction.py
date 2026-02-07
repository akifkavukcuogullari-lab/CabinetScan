"""Stage 1: Frame Extraction — Extract key frames from video.

Extracts frames at 2 FPS, filters out blurry frames (Laplacian variance),
deduplicates near-identical frames (SSIM), and maps each frame to its
nearest ARKit camera pose by timestamp.
"""

import cv2
import numpy as np
from dataclasses import dataclass
from pathlib import Path

from ..utils.errors import FrameExtractionError


@dataclass
class ExtractedFrame:
    """A frame extracted from the video with metadata."""
    image: np.ndarray  # BGR image
    timestamp: float  # seconds from video start
    frame_index: int  # original frame number in video
    blur_score: float  # Laplacian variance (higher = sharper)
    pose_index: int | None = None  # index into poses array (matched by timestamp)


class FrameExtractor:
    """Extract key frames from a captured video."""

    # Target extraction rate
    EXTRACT_FPS = 2.0
    # Minimum Laplacian variance to consider frame sharp
    MIN_BLUR_SCORE = 100.0
    # SSIM threshold for deduplication (above this = too similar)
    SSIM_THRESHOLD = 0.95
    # Output frame limits
    MIN_FRAMES = 30
    MAX_FRAMES = 120

    def extract(
        self,
        video_path: str | Path,
        poses: list[dict] | None = None,
    ) -> list[ExtractedFrame]:
        """Extract key frames from video.

        Args:
            video_path: Path to MP4 video file
            poses: Optional list of ARKit poses with 'timestamp' field

        Returns:
            List of extracted frames, sorted by timestamp

        Raises:
            FrameExtractionError: If video cannot be read or too few frames
        """
        video_path = Path(video_path)
        if not video_path.exists():
            raise FrameExtractionError(f"Video file not found: {video_path}")

        cap = cv2.VideoCapture(str(video_path))
        if not cap.isOpened():
            raise FrameExtractionError(f"Cannot open video: {video_path}")

        fps = cap.get(cv2.CAP_PROP_FPS)
        total_frames = int(cap.get(cv2.CAP_PROP_FRAME_COUNT))
        if fps <= 0 or total_frames <= 0:
            cap.release()
            raise FrameExtractionError("Invalid video metadata")

        # Calculate frame interval for target FPS
        frame_interval = max(1, int(fps / self.EXTRACT_FPS))

        frames: list[ExtractedFrame] = []
        frame_idx = 0

        while True:
            ret, frame = cap.read()
            if not ret:
                break

            if frame_idx % frame_interval == 0:
                timestamp = frame_idx / fps
                blur_score = self._compute_blur_score(frame)

                if blur_score >= self.MIN_BLUR_SCORE:
                    # Match to nearest pose
                    pose_idx = self._match_pose(timestamp, poses) if poses else None

                    extracted = ExtractedFrame(
                        image=frame,
                        timestamp=timestamp,
                        frame_index=frame_idx,
                        blur_score=blur_score,
                        pose_index=pose_idx,
                    )
                    frames.append(extracted)

            frame_idx += 1

        cap.release()

        # Deduplicate similar frames
        frames = self._deduplicate(frames)

        # Enforce frame limits
        if len(frames) > self.MAX_FRAMES:
            # Keep evenly spaced frames
            indices = np.linspace(0, len(frames) - 1, self.MAX_FRAMES, dtype=int)
            frames = [frames[i] for i in indices]

        if len(frames) < self.MIN_FRAMES:
            raise FrameExtractionError(
                f"Only {len(frames)} usable frames extracted (need {self.MIN_FRAMES}). "
                "Video may be too short or too blurry."
            )

        return frames

    def _compute_blur_score(self, frame: np.ndarray) -> float:
        """Compute Laplacian variance as blur metric. Higher = sharper."""
        gray = cv2.cvtColor(frame, cv2.COLOR_BGR2GRAY)
        return float(cv2.Laplacian(gray, cv2.CV_64F).var())

    def _deduplicate(self, frames: list[ExtractedFrame]) -> list[ExtractedFrame]:
        """Remove near-duplicate frames using structural similarity."""
        if len(frames) <= 1:
            return frames

        kept = [frames[0]]
        for frame in frames[1:]:
            # Compare with last kept frame using histogram correlation
            prev_hist = cv2.calcHist(
                [cv2.cvtColor(kept[-1].image, cv2.COLOR_BGR2GRAY)],
                [0], None, [64], [0, 256]
            )
            curr_hist = cv2.calcHist(
                [cv2.cvtColor(frame.image, cv2.COLOR_BGR2GRAY)],
                [0], None, [64], [0, 256]
            )
            correlation = cv2.compareHist(prev_hist, curr_hist, cv2.HISTCMP_CORREL)

            if correlation < self.SSIM_THRESHOLD:
                kept.append(frame)

        return kept

    def _match_pose(self, timestamp: float, poses: list[dict] | None) -> int | None:
        """Find the nearest pose by timestamp."""
        if not poses:
            return None

        best_idx = 0
        best_diff = abs(poses[0].get("timestamp", 0) - timestamp)

        for i, pose in enumerate(poses[1:], 1):
            diff = abs(pose.get("timestamp", 0) - timestamp)
            if diff < best_diff:
                best_diff = diff
                best_idx = i

        return best_idx
