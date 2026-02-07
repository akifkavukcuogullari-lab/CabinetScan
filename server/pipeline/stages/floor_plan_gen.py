"""Stage 7: Floor Plan Generation — Create floor plan PNG and measurements JSON.

Generates a 300 DPI floor plan image and the measurements_data JSON
in MeasurementData-compatible format (values in FEET).
"""

import json
from dataclasses import dataclass
from typing import Any

from .wall_detection import WallDetectionResult
from .snap_to_standards import SnapResult
from .scale_calibration import CalibrationResult
from ..utils.errors import FloorPlanError


@dataclass
class FloorPlanResult:
    """Result of floor plan generation."""
    floor_plan_png: bytes  # PNG image data
    measurements_json: dict[str, Any]  # MeasurementData-compatible
    total_linear_ft: float
    total_sq_ft: float


class FloorPlanGenerator:
    """Generate floor plan and measurements JSON."""

    DPI = 300
    PIXELS_PER_FOOT = 40  # Scale for the floor plan image

    def generate(
        self,
        walls: WallDetectionResult,
        snapped_objects: SnapResult,
        calibration: CalibrationResult,
        metadata: dict[str, Any] | None = None,
    ) -> FloorPlanResult:
        """Generate floor plan and measurements.

        Args:
            walls: Detected wall segments
            snapped_objects: Objects with snapped measurements
            calibration: Scale calibration result
            metadata: Additional metadata from capture

        Returns:
            FloorPlanResult with PNG and measurements JSON
        """
        # Generate measurements JSON (MeasurementData format, values in FEET)
        measurements_json = self._build_measurements_json(
            walls, snapped_objects, calibration, metadata
        )

        # Generate floor plan PNG
        floor_plan_png = self._render_floor_plan(walls, snapped_objects)

        total_linear_ft = walls.total_linear_feet
        # Estimate square footage from wall bounding box
        total_sq_ft = self._estimate_sq_ft(walls)

        return FloorPlanResult(
            floor_plan_png=floor_plan_png,
            measurements_json=measurements_json,
            total_linear_ft=total_linear_ft,
            total_sq_ft=total_sq_ft,
        )

    def _build_measurements_json(
        self,
        walls: WallDetectionResult,
        snapped: SnapResult,
        calibration: CalibrationResult,
        metadata: dict[str, Any] | None,
    ) -> dict[str, Any]:
        """Build MeasurementData-compatible JSON.

        All values in FEET (not inches).
        """
        # Build walls list
        wall_data = []
        for i, wall in enumerate(walls.walls):
            wall_data.append({
                "id": f"wall_{i}",
                "length_ft": wall.length_inches / 12.0,
                "orientation": wall.orientation,
                "start": list(wall.start),
                "end": list(wall.end),
            })

        # Build objects list
        object_data = []
        for snapped_obj in snapped.snapped_objects:
            obj = snapped_obj.object
            object_data.append({
                "id": f"obj_{obj.instance_id}",
                "label": obj.label,
                "width_ft": snapped_obj.snapped_width_inches / 12.0,
                "height_ft": obj.height_inches / 12.0,
                "raw_width_ft": snapped_obj.raw_width_inches / 12.0,
                "is_flagged": snapped_obj.is_flagged,
                "confidence": obj.confidence,
            })

        # Count objects by type
        base_count = sum(1 for s in snapped.snapped_objects if "base" in s.object.label.lower())
        upper_count = sum(1 for s in snapped.snapped_objects if "upper" in s.object.label.lower())
        window_count = sum(1 for s in snapped.snapped_objects if "window" in s.object.label.lower())
        door_count = sum(1 for s in snapped.snapped_objects if "door" in s.object.label.lower())

        return {
            "room_name": "Kitchen",
            "room_type": "kitchen",
            "total_linear_ft": walls.total_linear_feet,
            "total_sq_ft": self._estimate_sq_ft(walls),
            "wall_count": walls.wall_count,
            "window_count": window_count,
            "door_count": door_count,
            "measurements": {
                "walls": wall_data,
                "objects": object_data,
                "base_cabinet_count": base_count,
                "upper_cabinet_count": upper_count,
                "flagged_items": snapped.flagged_count,
            },
            "calibration_method": "multi_reference",
            "scale_factor": calibration.scale_factor,
            "overall_confidence": calibration.cross_validation_score,
            "frame_count": metadata.get("frame_count", 0) if metadata else 0,
            "photo_count": metadata.get("photo_count", 0) if metadata else 0,
            "coverage_percentage": 0,  # Will be computed from spatial coverage
            "model_versions": {
                "depth": "video_depth_anything_v2",
                "segmentation": "sam3",
                "pipeline": "v2",
            },
        }

    def _render_floor_plan(
        self,
        walls: WallDetectionResult,
        snapped: SnapResult,
    ) -> bytes:
        """Render a floor plan PNG image.

        Uses matplotlib for cross-platform rendering.
        """
        try:
            import matplotlib
            matplotlib.use("Agg")
            import matplotlib.pyplot as plt
            from io import BytesIO

            fig, ax = plt.subplots(1, 1, figsize=(10, 10), dpi=self.DPI)
            ax.set_aspect("equal")

            # Draw walls
            for wall in walls.walls:
                ax.plot(
                    [wall.start[0], wall.end[0]],
                    [wall.start[1], wall.end[1]],
                    "k-", linewidth=2,
                )

                # Label wall length
                mid_x = (wall.start[0] + wall.end[0]) / 2
                mid_y = (wall.start[1] + wall.end[1]) / 2
                length_ft = wall.length_inches / 12.0
                ax.text(
                    mid_x, mid_y, f"{length_ft:.1f}'",
                    ha="center", va="bottom", fontsize=8,
                )

            # Draw corners
            for corner in walls.corners:
                ax.plot(corner[0], corner[1], "ro", markersize=4)

            # Draw objects
            for snapped_obj in snapped.snapped_objects:
                obj = snapped_obj.object
                color = "red" if snapped_obj.is_flagged else "blue"
                # Simplified: just place a labeled marker
                ax.text(
                    0, 0, f"{obj.label}\n{snapped_obj.snapped_width_inches}\"",
                    fontsize=6, color=color, ha="center",
                )

            ax.set_title("Floor Plan", fontsize=12)
            ax.grid(True, alpha=0.3)

            buf = BytesIO()
            fig.savefig(buf, format="png", bbox_inches="tight")
            plt.close(fig)
            buf.seek(0)
            return buf.read()

        except Exception as e:
            raise FloorPlanError(f"Failed to render floor plan: {e}")

    def _estimate_sq_ft(self, walls: WallDetectionResult) -> float:
        """Estimate room square footage from wall bounding box."""
        if not walls.walls:
            return 0.0

        all_x = []
        all_z = []
        for wall in walls.walls:
            all_x.extend([wall.start[0], wall.end[0]])
            all_z.extend([wall.start[1], wall.end[1]])

        if not all_x or not all_z:
            return 0.0

        width_m = max(all_x) - min(all_x)
        depth_m = max(all_z) - min(all_z)

        # Convert m² to ft²
        sq_meters = width_m * depth_m
        sq_feet = sq_meters * 10.764  # 1 m² ≈ 10.764 ft²
        return round(sq_feet, 1)
