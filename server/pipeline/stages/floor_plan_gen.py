"""Stage 7: Floor Plan Generation — Create floor plan PNG and measurements JSON.

Generates a 300 DPI professional architectural floor plan and the
measurements_data JSON in MeasurementData-compatible format (values in FEET).
"""

import math
import json
from dataclasses import dataclass
from typing import Any

import numpy as np

from .wall_detection import WallDetectionResult, WallSegment
from .snap_to_standards import SnapResult, SnappedObject
from .scale_calibration import CalibrationResult
from ..utils.errors import FloorPlanError


@dataclass
class FloorPlanResult:
    """Result of floor plan generation."""
    floor_plan_png: bytes  # PNG image data
    measurements_json: dict[str, Any]  # MeasurementData-compatible
    total_linear_ft: float
    total_sq_ft: float


# Object label classification
_UPPER_LABELS = {"upper cabinet"}
_LOWER_LABELS = {"base cabinet"}
_WALL_OVEN_LABELS = {"wall oven"}
_PANTRY_LABELS = {"tall cabinet", "pantry"}
_APPLIANCE_LABELS = {"refrigerator", "range", "oven", "dishwasher", "microwave"}
_SINK_LABELS = {"sink"}
_DOOR_LABELS = {"door"}
_WINDOW_LABELS = {"window"}

# Max plausible dimensions (inches) — clamp anything larger
_MAX_WIDTH_IN = 236.0   # ~20ft / 6m
_MAX_HEIGHT_IN = 177.0  # ~15ft / 4.5m


def _clamp_inches(value: float, max_val: float) -> float:
    return min(value, max_val)


def _classify_label(label: str) -> str:
    """Return category key for a detection label."""
    lbl = label.lower().strip()
    if lbl in _UPPER_LABELS:
        return "upper"
    if lbl in _LOWER_LABELS:
        return "lower"
    if lbl in _WALL_OVEN_LABELS:
        return "wall_oven"
    if lbl in _PANTRY_LABELS:
        return "pantry"
    if lbl in _APPLIANCE_LABELS:
        return "appliance"
    if lbl in _SINK_LABELS:
        return "sink"
    if lbl in _DOOR_LABELS:
        return "door"
    if lbl in _WINDOW_LABELS:
        return "window"
    # Default: treat as lower cabinet
    return "lower"


def _ft_in_str(total_inches: float) -> str:
    """Format inches as feet-inches string, e.g. 150 -> 12'-6\"."""
    feet = int(total_inches) // 12
    inches = round(total_inches - feet * 12)
    if inches == 12:
        feet += 1
        inches = 0
    if inches == 0:
        return f"{feet}'-0\""
    return f"{feet}'-{inches}\""


class FloorPlanGenerator:
    """Generate floor plan and measurements JSON."""

    DPI = 300
    PIXELS_PER_FOOT = 40  # Scale for the floor plan image

    # Rendering colors
    WALL_COLOR = "#3D3D3D"
    FLOOR_COLOR = "#F5F5F2"
    BG_COLOR = "#FFFFFF"
    CABINET_COLOR = "#E8E0D0"
    APPLIANCE_COLOR = "#D0D0D0"
    DIM_COLOR = "#555555"
    WALL_THICKNESS_FT = 0.33

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
        total_sq_ft = self._estimate_sq_ft(walls)

        return FloorPlanResult(
            floor_plan_png=floor_plan_png,
            measurements_json=measurements_json,
            total_linear_ft=total_linear_ft,
            total_sq_ft=total_sq_ft,
        )

    # Meters to feet conversion factor
    M_TO_FT = 3.28084

    def _build_measurements_json(
        self,
        walls: WallDetectionResult,
        snapped: SnapResult,
        calibration: CalibrationResult,
        metadata: dict[str, Any] | None,
    ) -> dict[str, Any]:
        """Build dashboard-compatible measurements JSON.

        Dashboard InteractiveFloorPlan expects:
        - measurements.room: bounding box in feet
        - measurements.walls: with start/end as {x, z} dicts, dimensions in feet
        - measurements.cabinets/appliances/sinks/doors/windows: structured arrays
        All coordinate values converted from meters to feet.
        """
        # Compute room bounds from wall coordinates (in feet)
        all_x_ft: list[float] = []
        all_z_ft: list[float] = []
        for wall in walls.walls:
            all_x_ft.extend([
                wall.start[0] * self.M_TO_FT,
                wall.end[0] * self.M_TO_FT,
            ])
            all_z_ft.extend([
                wall.start[1] * self.M_TO_FT,
                wall.end[1] * self.M_TO_FT,
            ])

        room_data = {
            "min_x": round(min(all_x_ft), 2) if all_x_ft else 0,
            "max_x": round(max(all_x_ft), 2) if all_x_ft else 0,
            "min_z": round(min(all_z_ft), 2) if all_z_ft else 0,
            "max_z": round(max(all_z_ft), 2) if all_z_ft else 0,
            "ceiling_height_ft": 8.0,
        }

        # Build walls list with dashboard-compatible format
        wall_data = []
        for i, wall in enumerate(walls.walls):
            start_x_ft = round(wall.start[0] * self.M_TO_FT, 2)
            start_z_ft = round(wall.start[1] * self.M_TO_FT, 2)
            end_x_ft = round(wall.end[0] * self.M_TO_FT, 2)
            end_z_ft = round(wall.end[1] * self.M_TO_FT, 2)
            mid_x_ft = round((start_x_ft + end_x_ft) / 2, 2)
            mid_z_ft = round((start_z_ft + end_z_ft) / 2, 2)
            width_ft = round(wall.length_inches / 12.0, 2)

            wall_data.append({
                "id": f"wall_{i}",
                "position": {"x": mid_x_ft, "z": mid_z_ft},
                "start": {"x": start_x_ft, "z": start_z_ft},
                "end": {"x": end_x_ft, "z": end_z_ft},
                "width_ft": width_ft,
                "height_ft": 8.0,
                "thickness_ft": self.WALL_THICKNESS_FT,
                "linear_ft": width_ft,
                "orientation": wall.orientation,
            })

        # Classify objects into categories
        cabinets: dict[str, list] = {"upper": [], "lower": [], "wall_oven": [], "pantry": []}
        appliances: list[dict] = []
        sinks: list[dict] = []
        doors: list[dict] = []
        windows: list[dict] = []

        # Also build the flat objects list for backward compatibility
        object_data = []
        for snapped_obj in snapped.snapped_objects:
            obj = snapped_obj.object
            w_in = _clamp_inches(snapped_obj.snapped_width_inches, _MAX_WIDTH_IN)
            h_in = _clamp_inches(obj.height_inches, _MAX_HEIGHT_IN)

            # Position from world_position (meters -> feet), or None
            position = None
            if obj.world_position is not None:
                position = {
                    "x": round(obj.world_position[0] * self.M_TO_FT, 2),
                    "z": round(obj.world_position[2] * self.M_TO_FT, 2),
                }

            item = {
                "id": f"obj_{obj.instance_id}",
                "label": obj.label,
                "width_ft": round(w_in / 12.0, 2),
                "height_ft": round(h_in / 12.0, 2),
                "raw_width_ft": round(_clamp_inches(snapped_obj.raw_width_inches, _MAX_WIDTH_IN) / 12.0, 2),
                "is_flagged": snapped_obj.is_flagged,
                "confidence": obj.confidence,
                "position": position,
            }
            object_data.append(item)

            # Classify into structured arrays
            cat = _classify_label(obj.label)
            if cat in ("upper", "lower", "wall_oven", "pantry"):
                cabinets[cat].append(item)
            elif cat == "appliance":
                appliances.append(item)
            elif cat == "sink":
                sinks.append(item)
            elif cat == "door":
                doors.append(item)
            elif cat == "window":
                windows.append(item)

        window_count = len(windows)
        door_count = len(doors)

        return {
            "room_name": "Kitchen",
            "room_type": "kitchen",
            "total_linear_ft": walls.total_linear_feet,
            "total_sq_ft": self._estimate_sq_ft(walls),
            "wall_count": walls.wall_count,
            "window_count": window_count,
            "door_count": door_count,
            "measurements": {
                "room": room_data,
                "walls": wall_data,
                "objects": object_data,
                "cabinets": cabinets,
                "appliances": appliances,
                "sinks": sinks,
                "doors": doors,
                "windows": windows,
                "flagged_items": snapped.flagged_count,
            },
            "calibration_method": "multi_reference",
            "scale_factor": calibration.scale_factor,
            "overall_confidence": calibration.cross_validation_score,
            "frame_count": metadata.get("frame_count", 0) if metadata else 0,
            "photo_count": metadata.get("photo_count", 0) if metadata else 0,
            "coverage_percentage": 0,
            "model_versions": {
                "depth": "depth_anything_v2_metric_indoor",
                "segmentation": "sam3",
                "pipeline": "v2",
            },
        }

    # ------------------------------------------------------------------ #
    # Professional floor plan renderer
    # ------------------------------------------------------------------ #

    def _render_floor_plan(
        self,
        walls: WallDetectionResult,
        snapped: SnapResult,
    ) -> bytes:
        """Render a professional architectural floor plan PNG.

        Draws filled wall polygons, object symbols (cabinets, appliances,
        doors, windows), dimension lines, and room labels.
        """
        try:
            import matplotlib
            matplotlib.use("Agg")
            import matplotlib.pyplot as plt
            import matplotlib.patches as mpatches
            from matplotlib.patches import FancyArrowPatch, Arc, Rectangle
            from io import BytesIO

            # Compute room bounds in feet
            all_x_ft: list[float] = []
            all_z_ft: list[float] = []
            for w in walls.walls:
                all_x_ft.extend([
                    w.start[0] * self.M_TO_FT,
                    w.end[0] * self.M_TO_FT,
                ])
                all_z_ft.extend([
                    w.start[1] * self.M_TO_FT,
                    w.end[1] * self.M_TO_FT,
                ])

            if all_x_ft and all_z_ft:
                min_x = min(all_x_ft)
                max_x = max(all_x_ft)
                min_z = min(all_z_ft)
                max_z = max(all_z_ft)
            else:
                min_x = max_x = min_z = max_z = 0.0

            room_w = max_x - min_x
            room_h = max_z - min_z
            pad = max(3.0, max(room_w, room_h) * 0.25)

            # Figure sizing
            plot_w = room_w + 2 * pad
            plot_h = room_h + 2 * pad
            aspect = plot_w / max(plot_h, 0.1)
            fig_h = 10
            fig_w = max(6, min(16, fig_h * aspect))

            fig, ax = plt.subplots(1, 1, figsize=(fig_w, fig_h), dpi=self.DPI)
            fig.patch.set_facecolor(self.BG_COLOR)
            ax.set_facecolor(self.BG_COLOR)
            ax.set_aspect("equal")

            # Draw floor fill (off-white interior)
            if walls.walls:
                floor_rect = Rectangle(
                    (min_x, min_z), room_w, room_h,
                    facecolor=self.FLOOR_COLOR, edgecolor="none", zorder=0,
                )
                ax.add_patch(floor_rect)

            # Draw walls as thick filled polygons
            for wall in walls.walls:
                self._draw_wall_polygon(ax, wall)

            # Draw objects along walls
            self._draw_objects(ax, snapped, walls)

            # Draw dimension lines outside the room
            self._draw_dimension_lines(ax, walls, min_x, max_x, min_z, max_z)

            # Room label centered
            sq_ft = self._estimate_sq_ft(walls)
            if room_w > 0 and room_h > 0:
                cx = (min_x + max_x) / 2
                cz = (min_z + max_z) / 2
                ax.text(
                    cx, cz, "KITCHEN",
                    ha="center", va="center",
                    fontsize=14, fontweight="bold", color="#333333",
                    zorder=10,
                )
                ax.text(
                    cx, cz - room_h * 0.08,
                    f"{sq_ft:.0f} sq ft",
                    ha="center", va="center",
                    fontsize=10, color="#666666",
                    zorder=10,
                )

            # Axis limits
            ax.set_xlim(min_x - pad, max_x + pad)
            ax.set_ylim(min_z - pad, max_z + pad)

            # Remove axes / grid
            ax.axis("off")

            # Title block at bottom
            total_ft = walls.total_linear_feet
            obj_count = len(snapped.snapped_objects)
            fig.text(
                0.5, 0.02,
                f"{walls.wall_count} walls  |  {total_ft:.1f} linear ft  |  "
                f"{obj_count} objects  |  ~{sq_ft:.0f} sq ft",
                ha="center", va="bottom", fontsize=8, color="#888888",
            )

            buf = BytesIO()
            fig.savefig(buf, format="png", bbox_inches="tight",
                        facecolor=fig.get_facecolor(), edgecolor="none")
            plt.close(fig)
            buf.seek(0)
            return buf.read()

        except Exception as e:
            raise FloorPlanError(f"Failed to render floor plan: {e}")

    def _draw_wall_polygon(self, ax, wall: WallSegment) -> None:
        """Draw a single wall as a filled polygon with thickness."""
        import matplotlib.patches as mpatches

        sx = wall.start[0] * self.M_TO_FT
        sz = wall.start[1] * self.M_TO_FT
        ex = wall.end[0] * self.M_TO_FT
        ez = wall.end[1] * self.M_TO_FT

        dx = ex - sx
        dz = ez - sz
        length = math.sqrt(dx * dx + dz * dz)
        if length < 1e-6:
            return

        # Normal direction (perpendicular to wall)
        nx = -dz / length
        nz = dx / length
        half_t = self.WALL_THICKNESS_FT / 2.0

        # Four corners of the wall rectangle
        polygon = [
            (sx + nx * half_t, sz + nz * half_t),
            (ex + nx * half_t, ez + nz * half_t),
            (ex - nx * half_t, ez - nz * half_t),
            (sx - nx * half_t, sz - nz * half_t),
        ]
        patch = mpatches.Polygon(
            polygon, closed=True,
            facecolor=self.WALL_COLOR, edgecolor=self.WALL_COLOR,
            linewidth=0.5, zorder=5,
        )
        ax.add_patch(patch)

    def _draw_objects(self, ax, snapped: SnapResult, walls: WallDetectionResult) -> None:
        """Draw object symbols placed along nearest wall."""
        import matplotlib.patches as mpatches
        from matplotlib.patches import Arc

        for snapped_obj in snapped.snapped_objects:
            obj = snapped_obj.object
            cat = _classify_label(obj.label)

            # Determine position: use world_position projected to XZ,
            # or skip if no position available
            if obj.world_position is None:
                continue

            ox = obj.world_position[0] * self.M_TO_FT
            oz = obj.world_position[2] * self.M_TO_FT

            w_ft = _clamp_inches(snapped_obj.snapped_width_inches, _MAX_WIDTH_IN) / 12.0
            h_ft = 2.0  # default depth for plan view (2ft cabinet depth)

            if cat == "lower":
                self._draw_base_cabinet(ax, ox, oz, w_ft, h_ft)
            elif cat == "upper":
                self._draw_upper_cabinet(ax, ox, oz, w_ft, h_ft)
            elif cat == "appliance":
                lbl = obj.label.lower()
                if "refrigerator" in lbl:
                    self._draw_appliance_rect(ax, ox, oz, w_ft, h_ft, "REF")
                elif "range" in lbl:
                    self._draw_range(ax, ox, oz, w_ft, h_ft)
                elif "dishwasher" in lbl:
                    self._draw_appliance_dashed(ax, ox, oz, w_ft, h_ft, "DW")
                elif "microwave" in lbl:
                    self._draw_appliance_rect(ax, ox, oz, w_ft, max(h_ft, 1.5), "MW")
                else:
                    self._draw_appliance_rect(ax, ox, oz, w_ft, h_ft, "")
            elif cat == "sink":
                self._draw_sink(ax, ox, oz, w_ft, h_ft)
            elif cat == "window":
                self._draw_window(ax, ox, oz, w_ft, walls)
            elif cat == "door":
                self._draw_door(ax, ox, oz, w_ft)

    def _draw_base_cabinet(self, ax, x, z, w, d):
        """Tan filled rectangle with counter edge line."""
        import matplotlib.patches as mpatches
        rect = mpatches.Rectangle(
            (x - w / 2, z - d / 2), w, d,
            facecolor=self.CABINET_COLOR, edgecolor="#999999",
            linewidth=0.5, zorder=3,
        )
        ax.add_patch(rect)
        # Counter edge line along front
        ax.plot(
            [x - w / 2, x + w / 2], [z + d / 2, z + d / 2],
            color="#777777", linewidth=1.0, zorder=4,
        )

    def _draw_upper_cabinet(self, ax, x, z, w, d):
        """Dashed outline rectangle."""
        import matplotlib.patches as mpatches
        rect = mpatches.Rectangle(
            (x - w / 2, z - d / 2), w, d,
            facecolor="none", edgecolor="#999999",
            linewidth=0.8, linestyle="--", zorder=3,
        )
        ax.add_patch(rect)

    def _draw_appliance_rect(self, ax, x, z, w, d, label):
        """Gray filled rectangle with centered label."""
        import matplotlib.patches as mpatches
        rect = mpatches.Rectangle(
            (x - w / 2, z - d / 2), w, d,
            facecolor=self.APPLIANCE_COLOR, edgecolor="#888888",
            linewidth=0.5, zorder=3,
        )
        ax.add_patch(rect)
        if label:
            ax.text(
                x, z, label, ha="center", va="center",
                fontsize=6, fontweight="bold", color="#555555", zorder=4,
            )

    def _draw_appliance_dashed(self, ax, x, z, w, d, label):
        """Dashed rectangle for dishwasher-type."""
        import matplotlib.patches as mpatches
        rect = mpatches.Rectangle(
            (x - w / 2, z - d / 2), w, d,
            facecolor="none", edgecolor="#888888",
            linewidth=0.8, linestyle="--", zorder=3,
        )
        ax.add_patch(rect)
        if label:
            ax.text(
                x, z, label, ha="center", va="center",
                fontsize=6, color="#555555", zorder=4,
            )

    def _draw_range(self, ax, x, z, w, d):
        """Rectangle with 4 burner circles."""
        import matplotlib.patches as mpatches
        rect = mpatches.Rectangle(
            (x - w / 2, z - d / 2), w, d,
            facecolor=self.APPLIANCE_COLOR, edgecolor="#888888",
            linewidth=0.5, zorder=3,
        )
        ax.add_patch(rect)
        # 4 burner circles in a 2x2 grid
        burner_r = min(w, d) * 0.12
        offsets = [(-0.25, -0.25), (0.25, -0.25), (-0.25, 0.25), (0.25, 0.25)]
        for dx_frac, dz_frac in offsets:
            bx = x + dx_frac * w * 0.6
            bz = z + dz_frac * d * 0.6
            circle = mpatches.Circle(
                (bx, bz), burner_r,
                facecolor="none", edgecolor="#666666",
                linewidth=0.5, zorder=4,
            )
            ax.add_patch(circle)

    def _draw_sink(self, ax, x, z, w, d):
        """Rectangle with oval basin."""
        import matplotlib.patches as mpatches
        rect = mpatches.Rectangle(
            (x - w / 2, z - d / 2), w, d,
            facecolor=self.CABINET_COLOR, edgecolor="#999999",
            linewidth=0.5, zorder=3,
        )
        ax.add_patch(rect)
        # Oval basin
        basin = mpatches.Ellipse(
            (x, z), w * 0.6, d * 0.5,
            facecolor="none", edgecolor="#666666",
            linewidth=0.8, zorder=4,
        )
        ax.add_patch(basin)

    def _draw_window(self, ax, x, z, w, walls: WallDetectionResult):
        """3-line window symbol in wall."""
        # Draw 3 parallel lines perpendicular to nearest wall
        half_w = w / 2
        t = self.WALL_THICKNESS_FT * 0.4
        for offset in [-t, 0, t]:
            ax.plot(
                [x - half_w, x + half_w],
                [z + offset, z + offset],
                color="#4488CC", linewidth=1.0, zorder=6,
            )

    def _draw_door(self, ax, x, z, w):
        """Quarter-circle arc swing."""
        from matplotlib.patches import Arc
        # Door swing arc
        arc = Arc(
            (x - w / 2, z), w, w,
            angle=0, theta1=0, theta2=90,
            color="#666666", linewidth=0.8, zorder=6,
        )
        ax.add_patch(arc)
        # Door line
        ax.plot(
            [x - w / 2, x + w / 2], [z, z],
            color="#666666", linewidth=1.0, zorder=6,
        )

    def _draw_dimension_lines(
        self, ax,
        walls: WallDetectionResult,
        min_x: float, max_x: float,
        min_z: float, max_z: float,
    ) -> None:
        """Draw dimension lines outside the room perimeter."""
        offset = 1.5  # feet outside the room

        for wall in walls.walls:
            sx = wall.start[0] * self.M_TO_FT
            sz = wall.start[1] * self.M_TO_FT
            ex = wall.end[0] * self.M_TO_FT
            ez = wall.end[1] * self.M_TO_FT

            mid_x = (sx + ex) / 2
            mid_z = (sz + ez) / 2
            length_in = wall.length_inches
            label = _ft_in_str(length_in)

            dx = ex - sx
            dz = ez - sz
            length = math.sqrt(dx * dx + dz * dz)
            if length < 1e-6:
                continue

            # Normal direction — push label outward from room center
            nx = -dz / length
            nz = dx / length
            room_cx = (min_x + max_x) / 2
            room_cz = (min_z + max_z) / 2
            to_center_x = room_cx - mid_x
            to_center_z = room_cz - mid_z
            dot = nx * to_center_x + nz * to_center_z
            if dot > 0:
                nx, nz = -nx, -nz

            lx = mid_x + nx * offset
            lz = mid_z + nz * offset

            # Dimension line with arrows
            ax.annotate(
                "", xy=(sx + nx * offset * 0.6, sz + nz * offset * 0.6),
                xytext=(ex + nx * offset * 0.6, ez + nz * offset * 0.6),
                arrowprops=dict(arrowstyle="<->", color=self.DIM_COLOR, lw=0.7),
                zorder=7,
            )

            # Extension lines from wall ends to dimension line
            for px, pz in [(sx, sz), (ex, ez)]:
                ax.plot(
                    [px, px + nx * offset * 0.7],
                    [pz, pz + nz * offset * 0.7],
                    color=self.DIM_COLOR, linewidth=0.4, zorder=7,
                )

            # Label
            angle_deg = math.degrees(math.atan2(dz, dx))
            if angle_deg > 90:
                angle_deg -= 180
            elif angle_deg < -90:
                angle_deg += 180

            ax.text(
                lx, lz, label,
                ha="center", va="center",
                fontsize=7, color=self.DIM_COLOR,
                rotation=angle_deg,
                bbox=dict(boxstyle="round,pad=0.15", fc="white", ec="none", alpha=0.9),
                zorder=8,
            )

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

        # Convert m^2 to ft^2
        sq_meters = width_m * depth_m
        sq_feet = sq_meters * 10.764  # 1 m^2 ~ 10.764 ft^2
        return round(sq_feet, 1)
