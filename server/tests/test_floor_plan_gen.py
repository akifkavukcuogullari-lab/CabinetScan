"""Tests for Stage 7: Floor Plan Generation."""

import json
import pytest

from pipeline.stages.floor_plan_gen import (
    FloorPlanGenerator,
    FloorPlanResult,
    _classify_label,
    _ft_in_str,
)
from pipeline.stages.wall_detection import WallDetectionResult, WallSegment
from pipeline.stages.snap_to_standards import SnapResult, SnappedObject
from pipeline.stages.object_detection import DetectedObject
from pipeline.stages.scale_calibration import CalibrationResult


@pytest.fixture
def generator():
    return FloorPlanGenerator()


@pytest.fixture
def sample_walls():
    return WallDetectionResult(
        walls=[
            WallSegment(
                start=(0, 0), end=(3.048, 0),
                length_meters=3.048, length_inches=120.0,
                orientation=0.0, source="arkit_plane",
            ),
            WallSegment(
                start=(3.048, 0), end=(3.048, 2.438),
                length_meters=2.438, length_inches=96.0,
                orientation=90.0, source="arkit_plane",
            ),
        ],
        corners=[(3.048, 0)],
        total_linear_inches=216.0,
        total_linear_feet=18.0,
        wall_count=2,
    )


def _make_snapped_object(
    label: str,
    instance_id: int = 0,
    width_inches: float = 24.0,
    height_inches: float = 34.5,
    world_position: tuple | None = None,
) -> SnappedObject:
    obj = DetectedObject(
        label=label,
        instance_id=instance_id,
        bbox=(50, 50, 150, 200),
        mask=None,
        width_inches=width_inches,
        height_inches=height_inches,
        depth_inches=24.0,
        confidence=0.9,
        frame_index=0,
        standard_width_inches=width_inches,
        deviation_inches=0.0,
        world_position=world_position,
    )
    return SnappedObject(
        object=obj,
        raw_width_inches=width_inches,
        snapped_width_inches=width_inches,
        deviation_inches=0.0,
        is_flagged=False,
    )


@pytest.fixture
def sample_snapped():
    return SnapResult(
        snapped_objects=[
            _make_snapped_object("base cabinet", 0, world_position=(1.0, 0.0, 1.0)),
        ],
        flagged_count=0,
        total_snapped=1,
    )


@pytest.fixture
def multi_object_snapped():
    """SnapResult with objects of different categories."""
    return SnapResult(
        snapped_objects=[
            _make_snapped_object("base cabinet", 0, world_position=(1.0, 0.0, 1.0)),
            _make_snapped_object("upper cabinet", 1, world_position=(1.0, 0.0, 1.0)),
            _make_snapped_object("refrigerator", 2, width_inches=36.0, height_inches=70.0, world_position=(2.5, 0.0, 0.5)),
            _make_snapped_object("sink", 3, width_inches=33.0, height_inches=22.0, world_position=(1.5, 0.0, 1.5)),
            _make_snapped_object("window", 4, width_inches=36.0, height_inches=48.0, world_position=(1.5, 1.0, 0.0)),
            _make_snapped_object("door", 5, width_inches=36.0, height_inches=80.0, world_position=(0.0, 0.0, 1.2)),
        ],
        flagged_count=0,
        total_snapped=6,
    )


@pytest.fixture
def sample_calibration():
    return CalibrationResult(
        scale_factor=1.0,
        confidence="high",
        reference_used="base_cabinet_height",
        cross_validation_score=0.9,
        references_found=["base_cabinet_height", "countertop_height"],
    )


class TestFloorPlanGenerator:
    def test_generate_produces_result(self, generator, sample_walls, sample_snapped, sample_calibration):
        result = generator.generate(sample_walls, sample_snapped, sample_calibration)
        assert isinstance(result, FloorPlanResult)
        assert result.total_linear_ft > 0
        assert len(result.floor_plan_png) > 0
        assert isinstance(result.measurements_json, dict)

    def test_measurements_json_has_required_fields(self, generator, sample_walls, sample_snapped, sample_calibration):
        result = generator.generate(sample_walls, sample_snapped, sample_calibration)
        mj = result.measurements_json

        assert "room_name" in mj
        assert "room_type" in mj
        assert "total_linear_ft" in mj
        assert "wall_count" in mj
        assert "measurements" in mj
        assert "model_versions" in mj

    def test_measurements_values_in_feet(self, generator, sample_walls, sample_snapped, sample_calibration):
        result = generator.generate(sample_walls, sample_snapped, sample_calibration)
        mj = result.measurements_json

        # total_linear_ft should be in feet (not inches)
        assert mj["total_linear_ft"] == pytest.approx(18.0, rel=0.01)
        assert mj["wall_count"] == 2

    def test_wall_start_end_are_dicts(self, generator, sample_walls, sample_snapped, sample_calibration):
        """Dashboard InteractiveFloorPlan expects start/end as {x, z} dicts."""
        result = generator.generate(sample_walls, sample_snapped, sample_calibration)
        walls = result.measurements_json["measurements"]["walls"]
        assert len(walls) == 2

        wall = walls[0]
        assert isinstance(wall["start"], dict)
        assert "x" in wall["start"]
        assert "z" in wall["start"]
        assert isinstance(wall["end"], dict)
        assert "x" in wall["end"]
        assert "z" in wall["end"]

    def test_wall_coordinates_in_feet(self, generator, sample_walls, sample_snapped, sample_calibration):
        """Wall coordinates should be converted from meters to feet."""
        result = generator.generate(sample_walls, sample_snapped, sample_calibration)
        walls = result.measurements_json["measurements"]["walls"]

        # First wall: start=(0,0) end=(3.048,0) in meters
        # In feet: start=(0,0) end=(~10.0, 0)
        wall0 = walls[0]
        assert wall0["start"]["x"] == pytest.approx(0, abs=0.01)
        assert wall0["end"]["x"] == pytest.approx(10.0, abs=0.1)

    def test_wall_has_required_dashboard_fields(self, generator, sample_walls, sample_snapped, sample_calibration):
        """Each wall must have the fields the dashboard expects."""
        result = generator.generate(sample_walls, sample_snapped, sample_calibration)
        wall = result.measurements_json["measurements"]["walls"][0]

        assert "id" in wall
        assert "position" in wall
        assert "start" in wall
        assert "end" in wall
        assert "width_ft" in wall
        assert "height_ft" in wall
        assert "thickness_ft" in wall
        assert "linear_ft" in wall

    def test_room_bounds_present(self, generator, sample_walls, sample_snapped, sample_calibration):
        """measurements.room should have bounding box in feet."""
        result = generator.generate(sample_walls, sample_snapped, sample_calibration)
        room = result.measurements_json["measurements"]["room"]

        assert "min_x" in room
        assert "max_x" in room
        assert "min_z" in room
        assert "max_z" in room
        assert "ceiling_height_ft" in room
        assert room["ceiling_height_ft"] == 8.0

    def test_cabinets_structure_present(self, generator, sample_walls, sample_snapped, sample_calibration):
        """measurements.cabinets should have upper/lower/wall_oven/pantry arrays."""
        result = generator.generate(sample_walls, sample_snapped, sample_calibration)
        cabinets = result.measurements_json["measurements"]["cabinets"]

        assert isinstance(cabinets, dict)
        assert "upper" in cabinets
        assert "lower" in cabinets
        assert "wall_oven" in cabinets
        assert "pantry" in cabinets

    def test_measurements_has_structured_arrays(self, generator, sample_walls, sample_snapped, sample_calibration):
        """measurements should have appliances, sinks, doors, windows arrays."""
        result = generator.generate(sample_walls, sample_snapped, sample_calibration)
        m = result.measurements_json["measurements"]

        assert isinstance(m["appliances"], list)
        assert isinstance(m["sinks"], list)
        assert isinstance(m["doors"], list)
        assert isinstance(m["windows"], list)

    def test_measurements_json_serializable(self, generator, sample_walls, sample_snapped, sample_calibration):
        result = generator.generate(sample_walls, sample_snapped, sample_calibration)
        # Should not raise
        serialized = json.dumps(result.measurements_json)
        assert len(serialized) > 0

    def test_floor_plan_is_valid_png(self, generator, sample_walls, sample_snapped, sample_calibration):
        result = generator.generate(sample_walls, sample_snapped, sample_calibration)
        # PNG files start with specific magic bytes
        assert result.floor_plan_png[:4] == b"\x89PNG"

    def test_empty_walls(self, generator, sample_snapped, sample_calibration):
        empty_walls = WallDetectionResult(
            walls=[], corners=[], total_linear_inches=0,
            total_linear_feet=0, wall_count=0,
        )
        result = generator.generate(empty_walls, sample_snapped, sample_calibration)
        assert result.total_linear_ft == 0
        assert result.measurements_json["wall_count"] == 0

    def test_sq_ft_estimation(self, generator, sample_walls):
        sq_ft = generator._estimate_sq_ft(sample_walls)
        # 3.048m x 2.438m = ~7.43 m^2 = ~80 ft^2
        assert sq_ft > 0

    def test_metadata_passed_through(self, generator, sample_walls, sample_snapped, sample_calibration):
        metadata = {"frame_count": 60, "photo_count": 5}
        result = generator.generate(sample_walls, sample_snapped, sample_calibration, metadata=metadata)
        assert result.measurements_json["frame_count"] == 60
        assert result.measurements_json["photo_count"] == 5


class TestObjectClassification:
    """Tests for object classification into cabinets/appliances/sinks/doors/windows."""

    def test_base_cabinet_classified_as_lower(self, generator, sample_walls, sample_calibration):
        snapped = SnapResult(
            snapped_objects=[_make_snapped_object("base cabinet", 0)],
            flagged_count=0, total_snapped=1,
        )
        result = generator.generate(sample_walls, snapped, sample_calibration)
        cabinets = result.measurements_json["measurements"]["cabinets"]
        assert len(cabinets["lower"]) == 1
        assert len(cabinets["upper"]) == 0

    def test_upper_cabinet_classified(self, generator, sample_walls, sample_calibration):
        snapped = SnapResult(
            snapped_objects=[_make_snapped_object("upper cabinet", 0)],
            flagged_count=0, total_snapped=1,
        )
        result = generator.generate(sample_walls, snapped, sample_calibration)
        cabinets = result.measurements_json["measurements"]["cabinets"]
        assert len(cabinets["upper"]) == 1

    def test_refrigerator_classified_as_appliance(self, generator, sample_walls, sample_calibration):
        snapped = SnapResult(
            snapped_objects=[_make_snapped_object("refrigerator", 0, width_inches=36.0)],
            flagged_count=0, total_snapped=1,
        )
        result = generator.generate(sample_walls, snapped, sample_calibration)
        assert len(result.measurements_json["measurements"]["appliances"]) == 1

    def test_sink_classified(self, generator, sample_walls, sample_calibration):
        snapped = SnapResult(
            snapped_objects=[_make_snapped_object("sink", 0, width_inches=33.0)],
            flagged_count=0, total_snapped=1,
        )
        result = generator.generate(sample_walls, snapped, sample_calibration)
        assert len(result.measurements_json["measurements"]["sinks"]) == 1

    def test_window_classified(self, generator, sample_walls, sample_calibration):
        snapped = SnapResult(
            snapped_objects=[_make_snapped_object("window", 0, width_inches=36.0)],
            flagged_count=0, total_snapped=1,
        )
        result = generator.generate(sample_walls, snapped, sample_calibration)
        assert len(result.measurements_json["measurements"]["windows"]) == 1
        assert result.measurements_json["window_count"] == 1

    def test_door_classified(self, generator, sample_walls, sample_calibration):
        snapped = SnapResult(
            snapped_objects=[_make_snapped_object("door", 0, width_inches=36.0)],
            flagged_count=0, total_snapped=1,
        )
        result = generator.generate(sample_walls, snapped, sample_calibration)
        assert len(result.measurements_json["measurements"]["doors"]) == 1
        assert result.measurements_json["door_count"] == 1

    def test_multi_object_classification(self, generator, sample_walls, multi_object_snapped, sample_calibration):
        """Multiple object types classified into correct arrays."""
        result = generator.generate(sample_walls, multi_object_snapped, sample_calibration)
        m = result.measurements_json["measurements"]

        assert len(m["cabinets"]["lower"]) == 1
        assert len(m["cabinets"]["upper"]) == 1
        assert len(m["appliances"]) == 1
        assert len(m["sinks"]) == 1
        assert len(m["windows"]) == 1
        assert len(m["doors"]) == 1
        assert result.measurements_json["window_count"] == 1
        assert result.measurements_json["door_count"] == 1

    def test_object_position_included(self, generator, sample_walls, sample_calibration):
        """Objects with world_position should have position in JSON."""
        snapped = SnapResult(
            snapped_objects=[_make_snapped_object("base cabinet", 0, world_position=(1.0, 0.0, 2.0))],
            flagged_count=0, total_snapped=1,
        )
        result = generator.generate(sample_walls, snapped, sample_calibration)
        obj = result.measurements_json["measurements"]["objects"][0]
        assert obj["position"] is not None
        assert "x" in obj["position"]
        assert "z" in obj["position"]
        # 1.0m -> ~3.28ft, 2.0m -> ~6.56ft
        assert obj["position"]["x"] == pytest.approx(3.28, abs=0.1)
        assert obj["position"]["z"] == pytest.approx(6.56, abs=0.1)

    def test_object_without_position_has_null(self, generator, sample_walls, sample_calibration):
        """Objects without world_position should have position=None."""
        snapped = SnapResult(
            snapped_objects=[_make_snapped_object("base cabinet", 0, world_position=None)],
            flagged_count=0, total_snapped=1,
        )
        result = generator.generate(sample_walls, snapped, sample_calibration)
        obj = result.measurements_json["measurements"]["objects"][0]
        assert obj["position"] is None


class TestFloorPlanRendering:
    """Tests for the professional floor plan renderer."""

    def test_render_with_objects(self, generator, sample_walls, multi_object_snapped, sample_calibration):
        """Renderer should handle all object types without crashing."""
        result = generator.generate(sample_walls, multi_object_snapped, sample_calibration)
        assert result.floor_plan_png[:4] == b"\x89PNG"
        assert len(result.floor_plan_png) > 1000  # should be a substantial image

    def test_render_empty_walls_no_crash(self, generator, sample_calibration):
        empty_walls = WallDetectionResult(
            walls=[], corners=[], total_linear_inches=0,
            total_linear_feet=0, wall_count=0,
        )
        empty_snapped = SnapResult(snapped_objects=[], flagged_count=0, total_snapped=0)
        result = generator.generate(empty_walls, empty_snapped, sample_calibration)
        assert result.floor_plan_png[:4] == b"\x89PNG"

    def test_model_versions_updated(self, generator, sample_walls, sample_snapped, sample_calibration):
        result = generator.generate(sample_walls, sample_snapped, sample_calibration)
        versions = result.measurements_json["model_versions"]
        assert versions["depth"] == "depth_anything_v2_metric_indoor"


class TestHelpers:
    def test_classify_label_base_cabinet(self):
        assert _classify_label("base cabinet") == "lower"

    def test_classify_label_upper_cabinet(self):
        assert _classify_label("upper cabinet") == "upper"

    def test_classify_label_refrigerator(self):
        assert _classify_label("refrigerator") == "appliance"

    def test_classify_label_sink(self):
        assert _classify_label("sink") == "sink"

    def test_classify_label_door(self):
        assert _classify_label("door") == "door"

    def test_classify_label_window(self):
        assert _classify_label("window") == "window"

    def test_classify_label_tall_cabinet(self):
        assert _classify_label("tall cabinet") == "pantry"

    def test_classify_label_unknown_defaults_to_lower(self):
        assert _classify_label("something unknown") == "lower"

    def test_ft_in_str_exact_feet(self):
        assert _ft_in_str(120.0) == "10'-0\""

    def test_ft_in_str_with_inches(self):
        assert _ft_in_str(150.0) == "12'-6\""

    def test_ft_in_str_small(self):
        assert _ft_in_str(36.0) == "3'-0\""
