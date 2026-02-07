"""Tests for Stage 4: Wall Detection."""

import math
import pytest

from pipeline.stages.wall_detection import WallDetector, WallSegment, WallDetectionResult


@pytest.fixture
def detector():
    return WallDetector()


def make_plane(
    identifier: str = "test",
    alignment: str = "vertical",
    center: list | None = None,
    extent: list | None = None,
    transform: list | None = None,
) -> dict:
    """Create a mock ARKit plane dictionary."""
    if center is None:
        center = [0, 0, 0]
    if extent is None:
        extent = [2.0, 0, 0.1]  # 2 meter wide wall
    if transform is None:
        # Identity-ish 4x4 matrix
        transform = [
            [1, 0, 0, 0],
            [0, 1, 0, 0],
            [0, 0, 1, 0],
            [0, 0, 0, 1],
        ]
    return {
        "identifier": identifier,
        "alignment": alignment,
        "center": center,
        "extent": extent,
        "transform": transform,
    }


class TestWallDetector:
    def test_empty_planes_returns_empty_result(self, detector):
        result = detector.detect([])
        assert result.wall_count == 0
        assert result.walls == []
        assert result.total_linear_feet == 0

    def test_horizontal_planes_ignored(self, detector):
        planes = [make_plane(alignment="horizontal")]
        result = detector.detect(planes)
        assert result.wall_count == 0

    def test_single_vertical_plane_produces_wall(self, detector):
        planes = [make_plane(extent=[3.0, 0, 0.1])]  # 3 meter wall
        result = detector.detect(planes)
        assert result.wall_count == 1
        assert result.walls[0].length_meters == pytest.approx(3.0, abs=0.5)

    def test_wall_length_in_inches(self, detector):
        # 1 meter wall = ~39.37 inches
        planes = [make_plane(extent=[1.0, 0, 0.1])]
        result = detector.detect(planes)
        assert result.wall_count == 1
        wall = result.walls[0]
        assert wall.length_inches == pytest.approx(wall.length_meters / 0.0254, rel=0.01)

    def test_total_linear_feet(self, detector):
        planes = [
            make_plane(identifier="w1", extent=[3.048, 0, 0.1]),  # ~10 feet
            make_plane(
                identifier="w2",
                extent=[1.524, 0, 0.1],  # ~5 feet
                transform=[[1, 0, 0, 5], [0, 1, 0, 0], [0, 0, 1, 0], [0, 0, 0, 1]],
            ),
        ]
        result = detector.detect(planes)
        # Total should be around 15 feet
        assert result.total_linear_feet > 0

    def test_short_walls_filtered(self, detector):
        planes = [make_plane(extent=[0.1, 0, 0.1])]  # 10 cm = too short
        result = detector.detect(planes)
        assert result.wall_count == 0

    def test_snap_to_grid_snaps_near_90(self, detector):
        walls = [
            WallSegment(
                start=(0, 0), end=(1, 0),
                length_meters=1.0, length_inches=39.37,
                orientation=3.0,  # 3 degrees from 0 — should snap to 0
                source="arkit_plane",
            )
        ]
        snapped = detector._snap_to_grid(walls)
        assert snapped[0].orientation == 0.0

    def test_snap_to_grid_keeps_far_from_90(self, detector):
        walls = [
            WallSegment(
                start=(0, 0), end=(1, 0),
                length_meters=1.0, length_inches=39.37,
                orientation=45.0,  # 45 degrees — too far from any 90° snap
                source="arkit_plane",
            )
        ]
        snapped = detector._snap_to_grid(walls)
        assert snapped[0].orientation == 45.0

    def test_merge_collinear_combines_close_walls(self, detector):
        walls = [
            WallSegment(
                start=(0, 0), end=(1, 0),
                length_meters=1.0, length_inches=39.37,
                orientation=0.0, source="arkit_plane",
            ),
            WallSegment(
                start=(1.1, 0), end=(2.0, 0),
                length_meters=0.9, length_inches=35.43,
                orientation=0.0, source="arkit_plane",
            ),
        ]
        merged = detector._merge_collinear(walls)
        assert len(merged) == 1
        assert merged[0].length_meters > 1.5

    def test_merge_collinear_keeps_separate_walls(self, detector):
        walls = [
            WallSegment(
                start=(0, 0), end=(1, 0),
                length_meters=1.0, length_inches=39.37,
                orientation=0.0, source="arkit_plane",
            ),
            WallSegment(
                start=(5, 0), end=(6, 0),
                length_meters=1.0, length_inches=39.37,
                orientation=0.0, source="arkit_plane",
            ),
        ]
        merged = detector._merge_collinear(walls)
        assert len(merged) == 2

    def test_find_corners_perpendicular_walls(self, detector):
        walls = [
            WallSegment(
                start=(0, 0), end=(3, 0),
                length_meters=3.0, length_inches=118.0,
                orientation=0.0, source="arkit_plane",
            ),
            WallSegment(
                start=(3, 0), end=(3, 2),
                length_meters=2.0, length_inches=78.7,
                orientation=90.0, source="arkit_plane",
            ),
        ]
        corners = detector._find_corners(walls)
        assert len(corners) >= 1

    def test_result_type(self, detector):
        planes = [make_plane()]
        result = detector.detect(planes)
        assert isinstance(result, WallDetectionResult)
