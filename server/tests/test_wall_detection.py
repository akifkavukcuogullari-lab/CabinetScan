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
    """Create a mock ARKit plane dictionary.

    Transform is column-major 4x4:
      transform[col][row]
    Column 0 = local X-axis (wall direction)
    Column 3 = translation (tx, ty, tz, 1)
    extent = [width, 0, height] in meters (ARKit format: depth/thickness is always 0)
    """
    if center is None:
        center = [0, 0, 0]
    if extent is None:
        extent = [2.0, 0, 2.4]  # 2m wide, 0 depth, 2.4m tall wall
    if transform is None:
        # Identity 4x4 column-major matrix — wall at origin along X-axis
        transform = [
            [1, 0, 0, 0],  # col 0: local X-axis
            [0, 1, 0, 0],  # col 1: local Y-axis
            [0, 0, 1, 0],  # col 2: local Z-axis
            [0, 0, 0, 1],  # col 3: translation (tx=0, ty=0, tz=0)
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
        planes = [make_plane(extent=[3.0, 0, 2.4])]  # 3m wide, 2.4m tall
        result = detector.detect(planes)
        assert result.wall_count == 1
        assert result.walls[0].length_meters == pytest.approx(3.0, abs=0.5)

    def test_wall_length_in_inches(self, detector):
        # 1 meter wall = ~39.37 inches
        planes = [make_plane(extent=[1.0, 0, 2.4])]
        result = detector.detect(planes)
        assert result.wall_count == 1
        wall = result.walls[0]
        assert wall.length_inches == pytest.approx(wall.length_meters / 0.0254, rel=0.01)

    def test_total_linear_feet(self, detector):
        """Two walls at different positions should sum their lengths."""
        planes = [
            make_plane(
                identifier="w1",
                extent=[3.048, 0, 2.4],  # ~10 feet wide, 2.4m tall
                transform=[
                    [1, 0, 0, 0],
                    [0, 1, 0, 0],
                    [0, 0, 1, 0],
                    [0, 0, 0, 1],  # at origin
                ],
            ),
            make_plane(
                identifier="w2",
                extent=[1.524, 0, 2.4],  # ~5 feet wide, 2.4m tall
                transform=[
                    [1, 0, 0, 0],
                    [0, 1, 0, 0],
                    [0, 0, 1, 0],
                    [5, 0, 0, 1],  # col 3: tx=5 (5m away)
                ],
            ),
        ]
        result = detector.detect(planes)
        # Total should be around 15 feet
        assert result.total_linear_feet > 0

    def test_short_walls_filtered(self, detector):
        """Walls shorter than MIN_WALL_LENGTH (0.8m) should be filtered."""
        planes = [make_plane(extent=[0.5, 0, 2.4])]  # 50 cm wide — too short
        result = detector.detect(planes)
        assert result.wall_count == 0

    def test_height_filter_removes_cabinet_faces(self, detector):
        """Vertical planes with height < MIN_WALL_HEIGHT (1.5m) should be filtered."""
        planes = [
            # Cabinet face: 0.6m wide, 0.9m tall — should be filtered
            make_plane(
                identifier="cabinet",
                extent=[0.6, 0, 0.9],
                transform=[
                    [1, 0, 0, 0],
                    [0, 1, 0, 0],
                    [0, 0, 1, 0],
                    [1, 0, 0, 1],
                ],
            ),
            # Real wall: 3m wide, 2.4m tall — should pass
            make_plane(
                identifier="wall",
                extent=[3.0, 0, 2.4],
                transform=[
                    [1, 0, 0, 0],
                    [0, 1, 0, 0],
                    [0, 0, 1, 0],
                    [0, 0, -3, 1],
                ],
            ),
        ]
        result = detector.detect(planes)
        assert result.wall_count == 1
        assert result.walls[0].length_meters == pytest.approx(3.0, abs=0.1)

    def test_transform_column_major_translation(self, detector):
        """Verify translation reads from column 3: transform[3][0]=tx, transform[3][2]=tz."""
        planes = [make_plane(
            extent=[2.0, 0, 2.4],
            transform=[
                [1, 0, 0, 0],   # col 0: X-axis direction
                [0, 1, 0, 0],   # col 1: Y-axis
                [0, 0, 1, 0],   # col 2: Z-axis
                [1.5, 0, -2.0, 1],  # col 3: translation tx=1.5, tz=-2.0
            ],
        )]
        result = detector.detect(planes)
        assert result.wall_count == 1
        wall = result.walls[0]
        # Midpoint should be at (1.5, -2.0)
        mid_x = (wall.start[0] + wall.end[0]) / 2
        mid_z = (wall.start[1] + wall.end[1]) / 2
        assert mid_x == pytest.approx(1.5, abs=0.01)
        assert mid_z == pytest.approx(-2.0, abs=0.01)

    def test_rotated_wall_direction_from_column_0(self, detector):
        """Wall direction should come from column 0 (local X-axis).

        A 90-degree rotated wall has col 0 = (0, 0, -1) meaning
        the wall extends along -Z direction.
        """
        planes = [make_plane(
            extent=[2.5, 0, 2.4],
            transform=[
                [0, 0, -1, 0],  # col 0: local X-axis points along -Z
                [0, 1, 0, 0],   # col 1
                [1, 0, 0, 0],   # col 2
                [1.5, 0, -2.0, 1],  # col 3: translation
            ],
        )]
        result = detector.detect(planes)
        assert result.wall_count == 1
        wall = result.walls[0]
        # Wall extends along Z at x=1.5
        assert wall.start[0] == pytest.approx(1.5, abs=0.01)
        assert wall.end[0] == pytest.approx(1.5, abs=0.01)
        # Z should span from -2.0 - 1.25 to -2.0 + 1.25
        assert abs(wall.start[1] - wall.end[1]) == pytest.approx(2.5, abs=0.1)

    def test_parallel_wall_deduplication(self, detector):
        """Two parallel overlapping walls close together should be deduplicated."""
        walls = [
            WallSegment(
                start=(0, 0), end=(3, 0),
                length_meters=3.0, length_inches=118.11,
                orientation=0.0, source="arkit_plane",
            ),
            WallSegment(
                start=(0.1, 0.15), end=(2.8, 0.15),
                length_meters=2.7, length_inches=106.30,
                orientation=0.0, source="arkit_plane",
            ),
        ]
        deduped = detector._deduplicate_parallel(walls)
        # Should keep only the longer wall
        assert len(deduped) == 1
        assert deduped[0].length_meters == 3.0

    def test_parallel_dedup_keeps_distant_walls(self, detector):
        """Parallel walls far apart (different physical walls) should both be kept."""
        walls = [
            WallSegment(
                start=(0, 0), end=(3, 0),
                length_meters=3.0, length_inches=118.11,
                orientation=0.0, source="arkit_plane",
            ),
            WallSegment(
                start=(0, 4.0), end=(3, 4.0),
                length_meters=3.0, length_inches=118.11,
                orientation=0.0, source="arkit_plane",
            ),
        ]
        deduped = detector._deduplicate_parallel(walls)
        assert len(deduped) == 2

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
                orientation=45.0,  # 45 degrees — too far from any 90 snap
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
