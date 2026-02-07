"""Tests for Stage 1: Frame Extraction."""

import cv2
import numpy as np
import pytest
import tempfile
from pathlib import Path

from pipeline.stages.frame_extraction import FrameExtractor, ExtractedFrame
from pipeline.utils.errors import FrameExtractionError


@pytest.fixture
def extractor():
    return FrameExtractor()


@pytest.fixture
def sample_video(tmp_path):
    """Create a minimal test video (3 seconds at 30 FPS)."""
    video_path = tmp_path / "test_video.mp4"
    fps = 30
    duration = 3  # seconds
    width, height = 320, 240

    fourcc = cv2.VideoWriter_fourcc(*"mp4v")
    writer = cv2.VideoWriter(str(video_path), fourcc, fps, (width, height))

    for i in range(fps * duration):
        # Create frames with varying content to avoid dedup
        frame = np.zeros((height, width, 3), dtype=np.uint8)
        # Add moving rectangle for visual variation
        x = int((i / (fps * duration)) * width)
        cv2.rectangle(frame, (x, 50), (x + 60, 190), (255, 255, 255), -1)
        # Add text/detail to increase blur score
        cv2.putText(frame, f"Frame {i}", (10, 30), cv2.FONT_HERSHEY_SIMPLEX, 0.5, (200, 200, 200), 1)
        writer.write(frame)

    writer.release()
    return video_path


@pytest.fixture
def blurry_video(tmp_path):
    """Create a video with only blurry frames."""
    video_path = tmp_path / "blurry_video.mp4"
    fps = 30
    duration = 3
    width, height = 320, 240

    fourcc = cv2.VideoWriter_fourcc(*"mp4v")
    writer = cv2.VideoWriter(str(video_path), fourcc, fps, (width, height))

    for _ in range(fps * duration):
        # Solid gray frame = very low Laplacian variance
        frame = np.full((height, width, 3), 128, dtype=np.uint8)
        writer.write(frame)

    writer.release()
    return video_path


class TestFrameExtractor:
    def test_extract_produces_frames(self, extractor, sample_video):
        # Lower min frames for short test video
        extractor.MIN_FRAMES = 1
        frames = extractor.extract(sample_video)
        assert len(frames) > 0
        assert all(isinstance(f, ExtractedFrame) for f in frames)

    def test_extract_raises_on_missing_file(self, extractor):
        with pytest.raises(FrameExtractionError, match="not found"):
            extractor.extract("/nonexistent/video.mp4")

    def test_extract_raises_on_invalid_video(self, extractor, tmp_path):
        bad_file = tmp_path / "bad.mp4"
        bad_file.write_text("not a video")
        with pytest.raises(FrameExtractionError):
            extractor.extract(bad_file)

    def test_frames_have_timestamps(self, extractor, sample_video):
        extractor.MIN_FRAMES = 1
        frames = extractor.extract(sample_video)
        timestamps = [f.timestamp for f in frames]
        # Timestamps should be monotonically increasing
        assert timestamps == sorted(timestamps)
        assert all(t >= 0 for t in timestamps)

    def test_frames_have_blur_scores(self, extractor, sample_video):
        extractor.MIN_FRAMES = 1
        frames = extractor.extract(sample_video)
        assert all(f.blur_score >= extractor.MIN_BLUR_SCORE for f in frames)

    def test_blurry_video_raises_insufficient_frames(self, extractor, blurry_video):
        with pytest.raises(FrameExtractionError, match="usable frames"):
            extractor.extract(blurry_video)

    def test_max_frames_limit(self, extractor, sample_video):
        extractor.MIN_FRAMES = 1
        extractor.MAX_FRAMES = 3
        frames = extractor.extract(sample_video)
        assert len(frames) <= 3

    def test_pose_matching(self, extractor, sample_video):
        extractor.MIN_FRAMES = 1
        poses = [
            {"timestamp": 0.0},
            {"timestamp": 0.5},
            {"timestamp": 1.0},
            {"timestamp": 1.5},
            {"timestamp": 2.0},
        ]
        frames = extractor.extract(sample_video, poses=poses)
        # Frames should have pose indices assigned
        assert any(f.pose_index is not None for f in frames)

    def test_compute_blur_score(self, extractor):
        # Sharp image (edges) should have high score
        sharp = np.zeros((100, 100, 3), dtype=np.uint8)
        cv2.rectangle(sharp, (20, 20), (80, 80), (255, 255, 255), -1)
        score = extractor._compute_blur_score(sharp)
        assert score > 0

        # Solid image should have ~0 score
        solid = np.full((100, 100, 3), 128, dtype=np.uint8)
        score_solid = extractor._compute_blur_score(solid)
        assert score_solid < score

    def test_deduplication_removes_identical(self, extractor):
        frame_img = np.zeros((100, 100, 3), dtype=np.uint8)
        frames = [
            ExtractedFrame(image=frame_img.copy(), timestamp=0, frame_index=0, blur_score=200),
            ExtractedFrame(image=frame_img.copy(), timestamp=0.5, frame_index=15, blur_score=200),
            ExtractedFrame(image=frame_img.copy(), timestamp=1.0, frame_index=30, blur_score=200),
        ]
        deduped = extractor._deduplicate(frames)
        # Identical frames should be reduced
        assert len(deduped) < len(frames)

    def test_pose_match_returns_nearest(self, extractor):
        poses = [
            {"timestamp": 0.0},
            {"timestamp": 1.0},
            {"timestamp": 2.0},
        ]
        # Timestamp 0.8 should match pose at 1.0 (index 1)
        idx = extractor._match_pose(0.8, poses)
        assert idx == 1

        # Timestamp 0.0 should match pose at 0.0 (index 0)
        idx = extractor._match_pose(0.0, poses)
        assert idx == 0
