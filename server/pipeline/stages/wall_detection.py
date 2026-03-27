"""Stage 4: Wall Detection — Parse ARKit planes into wall segments.

Converts ARKit plane anchors (horizontal + vertical) into wall
segments with positions and lengths. Snaps to 90-degree grid
and merges collinear segments.
"""

import math
import numpy as np
from dataclasses import dataclass

from ..utils.errors import WallDetectionError


@dataclass
class WallSegment:
    """A detected wall segment."""
    start: tuple[float, float]  # (x, z) in meters
    end: tuple[float, float]  # (x, z) in meters
    length_meters: float
    length_inches: float
    orientation: float  # angle in degrees (0, 90, 180, 270)
    source: str  # "arkit_plane" or "depth_inferred"


@dataclass
class WallDetectionResult:
    """Result of wall detection stage."""
    walls: list[WallSegment]
    corners: list[tuple[float, float]]  # corner points
    total_linear_inches: float
    total_linear_feet: float
    wall_count: int


class WallDetector:
    """Detect walls from ARKit plane data."""

    # Angle snapping tolerance (degrees)
    SNAP_ANGLE_TOLERANCE = 15.0
    # Minimum wall length to keep (meters)
    MIN_WALL_LENGTH = 0.8  # ~31 inches — filters small vertical surfaces
    # Minimum wall height to keep (meters) — filters cabinet faces (~0.9m)
    MIN_WALL_HEIGHT = 1.5  # ~5 feet — real walls are typically 2.0-2.5m
    # Distance threshold for merging collinear segments (meters)
    MERGE_DISTANCE = 0.3
    # Perpendicular distance for parallel wall deduplication (meters)
    PARALLEL_DISTANCE = 0.3

    def detect(self, planes_json: list[dict]) -> WallDetectionResult:
        """Detect walls from ARKit plane data.

        Args:
            planes_json: List of ARKit plane dictionaries with
                         identifier, alignment, center, extent, transform

        Returns:
            WallDetectionResult with wall segments and measurements
        """
        # Filter to vertical planes only (walls)
        vertical_planes = [
            p for p in planes_json
            if p.get("alignment") == "vertical"
        ]

        if not vertical_planes:
            return WallDetectionResult(
                walls=[], corners=[], total_linear_inches=0,
                total_linear_feet=0, wall_count=0,
            )

        # Convert planes to wall segments
        raw_walls = self._planes_to_walls(vertical_planes)

        # Snap to 90-degree grid
        snapped = self._snap_to_grid(raw_walls)

        # Merge collinear segments
        merged = self._merge_collinear(snapped)

        # Deduplicate parallel overlapping walls (keep longest)
        deduped = self._deduplicate_parallel(merged)

        # Filter short segments
        walls = [w for w in deduped if w.length_meters >= self.MIN_WALL_LENGTH]

        # Find corners
        corners = self._find_corners(walls)

        # Calculate totals
        total_inches = sum(w.length_inches for w in walls)
        total_feet = total_inches / 12.0

        return WallDetectionResult(
            walls=walls,
            corners=corners,
            total_linear_inches=total_inches,
            total_linear_feet=total_feet,
            wall_count=len(walls),
        )

    def _planes_to_walls(self, planes: list[dict]) -> list[WallSegment]:
        """Convert ARKit vertical planes to wall segments.

        ARKit exports column-major 4x4 transform matrices:
          transform[col][row]
        Translation is in column 3: transform[3][0]=tx, transform[3][2]=tz
        Local X-axis (wall direction) is column 0: transform[0][0], transform[0][2]
        """
        walls = []
        for plane in planes:
            transform = plane.get("transform", [])
            extent = plane.get("extent", [0, 0, 0])

            if not transform or len(transform) < 4:
                continue

            # ARKit extent: [width, 0, height] — extent[1] is always 0 (depth/thickness)
            wall_width = extent[0] if len(extent) > 0 else 0
            wall_height = extent[2] if len(extent) > 2 else 0

            if wall_width <= 0:
                continue

            # Filter by height — real walls are 2.0-2.5m, cabinet faces ~0.9m
            if wall_height < self.MIN_WALL_HEIGHT:
                continue

            # Extract translation from column 3 (column-major)
            tx = transform[3][0] if len(transform[3]) > 0 else 0
            tz = transform[3][2] if len(transform[3]) > 2 else 0

            # Wall direction from column 0 (local X-axis), normalized
            dir_x = transform[0][0] if len(transform[0]) > 0 else 1
            dir_z = transform[0][2] if len(transform[0]) > 2 else 0
            dir_len = math.sqrt(dir_x * dir_x + dir_z * dir_z)
            if dir_len > 0:
                dir_x /= dir_len
                dir_z /= dir_len

            # Compute orientation angle from direction vector
            angle = math.atan2(dir_x, dir_z)
            angle_deg = math.degrees(angle)

            # Compute start/end points: center +/- half_width along direction
            half_w = wall_width / 2.0
            start = (tx - half_w * dir_x, tz - half_w * dir_z)
            end = (tx + half_w * dir_x, tz + half_w * dir_z)

            walls.append(WallSegment(
                start=start,
                end=end,
                length_meters=wall_width,
                length_inches=wall_width / 0.0254,
                orientation=angle_deg,
                source="arkit_plane",
            ))

        return walls

    def _snap_to_grid(self, walls: list[WallSegment]) -> list[WallSegment]:
        """Snap wall orientations to nearest 90-degree angle."""
        snapped = []
        for wall in walls:
            # Snap to nearest 90 degrees
            angle = wall.orientation % 360
            snap_angles = [0, 90, 180, 270, 360]
            nearest = min(snap_angles, key=lambda a: abs(angle - a))
            if nearest == 360:
                nearest = 0

            if abs(angle - nearest) <= self.SNAP_ANGLE_TOLERANCE:
                snapped.append(WallSegment(
                    start=wall.start,
                    end=wall.end,
                    length_meters=wall.length_meters,
                    length_inches=wall.length_inches,
                    orientation=float(nearest),
                    source=wall.source,
                ))
            else:
                # Keep original if too far from grid
                snapped.append(wall)

        return snapped

    def _merge_collinear(self, walls: list[WallSegment]) -> list[WallSegment]:
        """Merge nearly collinear wall segments."""
        if len(walls) <= 1:
            return walls

        # Group by orientation
        groups: dict[float, list[WallSegment]] = {}
        for wall in walls:
            key = round(wall.orientation / 90) * 90 % 360
            groups.setdefault(key, []).append(wall)

        merged: list[WallSegment] = []
        for _orientation, group in groups.items():
            # Sort by position along the wall axis
            group.sort(key=lambda w: w.start[0] + w.start[1])

            current = group[0]
            for wall in group[1:]:
                # Check if walls are close enough to merge
                dist = math.sqrt(
                    (current.end[0] - wall.start[0]) ** 2 +
                    (current.end[1] - wall.start[1]) ** 2
                )

                if dist <= self.MERGE_DISTANCE:
                    # Merge: extend current wall to cover both
                    new_length = math.sqrt(
                        (wall.end[0] - current.start[0]) ** 2 +
                        (wall.end[1] - current.start[1]) ** 2
                    )
                    current = WallSegment(
                        start=current.start,
                        end=wall.end,
                        length_meters=new_length,
                        length_inches=new_length / 0.0254,
                        orientation=current.orientation,
                        source=current.source,
                    )
                else:
                    merged.append(current)
                    current = wall

            merged.append(current)

        return merged

    def _deduplicate_parallel(self, walls: list[WallSegment]) -> list[WallSegment]:
        """Remove parallel overlapping walls, keeping the longest in each cluster.

        ARKit often detects 2-3 overlapping planes for the same physical wall.
        Group walls by orientation, then within each group find walls that are
        close in perpendicular distance and keep only the longest.
        """
        if len(walls) <= 1:
            return walls

        # Group by snapped orientation
        groups: dict[float, list[WallSegment]] = {}
        for wall in walls:
            key = round(wall.orientation / 90) * 90 % 360
            groups.setdefault(key, []).append(wall)

        result: list[WallSegment] = []
        for _orientation, group in groups.items():
            # Sort by length descending so we keep the longest
            group.sort(key=lambda w: w.length_meters, reverse=True)
            kept: list[WallSegment] = []

            for wall in group:
                # Check if this wall is parallel and close to an already-kept wall
                is_duplicate = False
                for existing in kept:
                    perp_dist = self._perpendicular_distance(wall, existing)
                    if perp_dist <= self.PARALLEL_DISTANCE:
                        is_duplicate = True
                        break
                if not is_duplicate:
                    kept.append(wall)

            result.extend(kept)

        return result

    @staticmethod
    def _perpendicular_distance(w1: WallSegment, w2: WallSegment) -> float:
        """Compute perpendicular distance between midpoints of two parallel walls."""
        mid1 = ((w1.start[0] + w1.end[0]) / 2, (w1.start[1] + w1.end[1]) / 2)
        mid2 = ((w2.start[0] + w2.end[0]) / 2, (w2.start[1] + w2.end[1]) / 2)

        # Direction of w1
        dx = w1.end[0] - w1.start[0]
        dz = w1.end[1] - w1.start[1]
        length = math.sqrt(dx * dx + dz * dz)
        if length == 0:
            return math.sqrt((mid1[0] - mid2[0]) ** 2 + (mid1[1] - mid2[1]) ** 2)

        # Perpendicular = component of (mid2 - mid1) orthogonal to wall direction
        nx, nz = -dz / length, dx / length  # normal vector
        return abs((mid2[0] - mid1[0]) * nx + (mid2[1] - mid1[1]) * nz)

    def _find_corners(self, walls: list[WallSegment]) -> list[tuple[float, float]]:
        """Find corner points where walls meet."""
        corners = []
        for i, w1 in enumerate(walls):
            for w2 in walls[i + 1:]:
                # Check if walls are perpendicular
                angle_diff = abs(w1.orientation - w2.orientation) % 180
                if abs(angle_diff - 90) > self.SNAP_ANGLE_TOLERANCE:
                    continue

                # Check if endpoints are close
                for p1 in [w1.start, w1.end]:
                    for p2 in [w2.start, w2.end]:
                        dist = math.sqrt((p1[0] - p2[0]) ** 2 + (p1[1] - p2[1]) ** 2)
                        if dist <= self.MERGE_DISTANCE:
                            midpoint = ((p1[0] + p2[0]) / 2, (p1[1] + p2[1]) / 2)
                            corners.append(midpoint)

        return corners
