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
    MIN_WALL_LENGTH = 0.3  # ~12 inches
    # Distance threshold for merging collinear segments (meters)
    MERGE_DISTANCE = 0.3

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

        # Filter short segments
        walls = [w for w in merged if w.length_meters >= self.MIN_WALL_LENGTH]

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
        """Convert ARKit vertical planes to wall segments."""
        walls = []
        for plane in planes:
            transform = plane.get("transform", [])
            center = plane.get("center", [0, 0, 0])
            extent = plane.get("extent", [0, 0, 0])

            if not transform or len(transform) < 4:
                continue

            # Extract position from 4x4 transform matrix
            # transform[i][3] = translation for row i
            tx = transform[0][3] if len(transform[0]) > 3 else 0
            tz = transform[2][3] if len(transform[2]) > 3 else 0

            # Wall extent along its primary axis
            wall_width = extent[0] if len(extent) > 0 else 0  # width in meters

            if wall_width <= 0:
                continue

            # Compute orientation from transform rotation
            # The plane normal is the Y-axis of the transform
            angle = math.atan2(transform[0][0], transform[0][2]) if len(transform[0]) > 2 else 0
            angle_deg = math.degrees(angle)

            # Compute start/end points
            half_w = wall_width / 2.0
            dx = half_w * math.cos(angle)
            dz = half_w * math.sin(angle)

            start = (tx - dx, tz - dz)
            end = (tx + dx, tz + dz)
            length = wall_width

            walls.append(WallSegment(
                start=start,
                end=end,
                length_meters=length,
                length_inches=length / 0.0254,
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
