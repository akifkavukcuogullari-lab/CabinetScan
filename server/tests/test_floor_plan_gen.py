"""Tests for Stage 7: Floor Plan Generation."""

import json
import pytest

from pipeline.stages.floor_plan_gen import FloorPlanGenerator, FloorPlanResult
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


@pytest.fixture
def sample_snapped():
    obj = DetectedObject(
        label="base cabinet",
        instance_id=0,
        bbox=(50, 50, 150, 200),
        mask=None,
        width_inches=24.0,
        height_inches=34.5,
        depth_inches=24.0,
        confidence=0.9,
        frame_index=0,
        standard_width_inches=24.0,
        deviation_inches=0.0,
    )
    return SnapResult(
        snapped_objects=[
            SnappedObject(
                object=obj,
                raw_width_inches=24.0,
                snapped_width_inches=24.0,
                deviation_inches=0.0,
                is_flagged=False,
            ),
        ],
        flagged_count=0,
        total_snapped=1,
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
        # 3.048m x 2.438m = ~7.43 m² = ~80 ft²
        assert sq_ft > 0

    def test_metadata_passed_through(self, generator, sample_walls, sample_snapped, sample_calibration):
        metadata = {"frame_count": 60, "photo_count": 5}
        result = generator.generate(sample_walls, sample_snapped, sample_calibration, metadata=metadata)
        assert result.measurements_json["frame_count"] == 60
        assert result.measurements_json["photo_count"] == 5
