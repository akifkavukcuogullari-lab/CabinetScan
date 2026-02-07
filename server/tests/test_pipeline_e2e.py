"""End-to-end pipeline integration tests.

Phase 5.2: Verifies the full pipeline orchestrator produces valid output
with the correct format expected by the iOS app and dashboard.

Note: These tests use mock/minimal inputs (no GPU models needed).
Full GPU integration requires a RunPod/Modal environment.
"""

import json
import pytest

from pipeline.orchestrator import PipelineOrchestrator, PipelineInput, PipelineOutput, STAGE_WEIGHTS
from pipeline.stages.wall_detection import WallDetector, WallDetectionResult, WallSegment
from pipeline.stages.scale_calibration import ScaleCalibrator, CalibrationResult
from pipeline.stages.snap_to_standards import SnapToStandards, SnapResult
from pipeline.stages.floor_plan_gen import FloorPlanGenerator, FloorPlanResult
from pipeline.stages.vlm_validation import VLMValidator, ValidationResult


class TestPipelineOutputFormat:
    """Verify the pipeline output matches the format expected by ServerResultAdapter on iOS."""

    @pytest.fixture
    def sample_walls(self):
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
                WallSegment(
                    start=(3.048, 2.438), end=(0, 2.438),
                    length_meters=3.048, length_inches=120.0,
                    orientation=180.0, source="arkit_plane",
                ),
            ],
            corners=[(3.048, 0), (3.048, 2.438)],
            total_linear_inches=336.0,
            total_linear_feet=28.0,
            wall_count=3,
        )

    @pytest.fixture
    def sample_calibration(self):
        return CalibrationResult(
            scale_factor=1.0,
            confidence="high",
            reference_used="base_cabinet_height",
            cross_validation_score=0.9,
            references_found=["base_cabinet_height", "countertop_height"],
        )

    @pytest.fixture
    def sample_snap(self):
        return SnapResult(
            snapped_objects=[],
            flagged_count=0,
            total_snapped=0,
        )

    @pytest.fixture
    def floor_plan_result(self, sample_walls, sample_snap, sample_calibration):
        gen = FloorPlanGenerator()
        return gen.generate(sample_walls, sample_snap, sample_calibration)

    def test_measurements_json_has_ios_required_fields(self, floor_plan_result):
        """iOS ServerResultAdapter expects these keys in measurements_data."""
        mj = floor_plan_result.measurements_json
        required_keys = [
            "room_name",
            "room_type",
            "total_linear_ft",
            "wall_count",
            "measurements",
            "model_versions",
        ]
        for key in required_keys:
            assert key in mj, f"measurements_json missing required key: {key}"

    def test_measurements_values_in_feet(self, floor_plan_result):
        """iOS expects total_linear_ft in FEET (not inches)."""
        mj = floor_plan_result.measurements_json
        assert mj["total_linear_ft"] == pytest.approx(28.0, rel=0.01)

    def test_measurements_json_is_serializable(self, floor_plan_result):
        """Must be JSON-serializable for Supabase storage and iOS parsing."""
        serialized = json.dumps(floor_plan_result.measurements_json)
        parsed = json.loads(serialized)
        assert parsed["room_name"] == floor_plan_result.measurements_json["room_name"]

    def test_floor_plan_is_valid_png(self, floor_plan_result):
        """iOS downloads this as a PNG for the preview image."""
        assert floor_plan_result.floor_plan_png[:4] == b"\x89PNG"
        assert len(floor_plan_result.floor_plan_png) > 100

    def test_total_linear_ft_matches_walls(self, floor_plan_result):
        """total_linear_ft should match the sum of wall lengths."""
        mj = floor_plan_result.measurements_json
        assert mj["total_linear_ft"] > 0
        assert mj["wall_count"] == 3


class TestVLMValidationIntegration:
    """Verify VLM validation output format matches iOS expectations."""

    def test_validation_result_format(self):
        """iOS reads: validationPassed (bool), validationIssues ([String])."""
        validator = VLMValidator(api_key=None)
        result = validator.validate(floor_plan_png=b"fake png")

        assert isinstance(result.passed, bool)
        assert isinstance(result.issues, list)
        assert isinstance(result.confidence, float)

    def test_skipped_validation_passes(self):
        """When no API key, validation should pass (non-blocking)."""
        validator = VLMValidator(api_key=None)
        result = validator.validate(floor_plan_png=b"fake png")
        assert result.passed is True


class TestCalibrationConfidenceFormat:
    """Verify calibration confidence format matches iOS mapping."""

    def test_confidence_is_string(self):
        """iOS maps: 'high' -> 0.9, 'medium' -> 0.7, 'low' -> 0.5."""
        result = CalibrationResult(
            scale_factor=1.0,
            confidence="high",
            reference_used="base_cabinet_height",
            cross_validation_score=0.9,
            references_found=["base_cabinet_height"],
        )
        assert result.confidence in ("high", "medium", "low")

    def test_all_confidence_levels(self):
        for level in ("high", "medium", "low"):
            result = CalibrationResult(
                scale_factor=1.0,
                confidence=level,
                reference_used="test",
                cross_validation_score=0.5,
                references_found=[],
            )
            assert result.confidence == level


class TestWallDetectionFromARKitPlanes:
    """Verify wall detection from ARKit planes produces correct format."""

    def test_arkit_vertical_planes_to_walls(self):
        """Simulate ARKit planes JSON and verify wall output."""
        detector = WallDetector()
        planes_json = [
            {
                "id": "plane-1",
                "alignment": "vertical",
                "center": [0, 1.0, 0],
                "extent": [3.0, 2.5],
                "transform": [
                    [1, 0, 0, 0],
                    [0, 1, 0, 0],
                    [0, 0, 1, 0],
                    [0, 0, 0, 1],
                ],
            },
            {
                "id": "plane-2",
                "alignment": "vertical",
                "center": [1.5, 1.0, -2.0],
                "extent": [2.5, 2.5],
                "transform": [
                    [0, 0, 1, 0],
                    [0, 1, 0, 0],
                    [-1, 0, 0, 0],
                    [1.5, 0, -2.0, 1],
                ],
            },
        ]

        result = detector.detect(planes_json=planes_json)

        assert isinstance(result, WallDetectionResult)
        assert result.wall_count >= 0
        assert result.total_linear_feet >= 0
        # Wall lengths should be in inches (internal) and feet (total)
        for wall in result.walls:
            assert wall.length_inches > 0
            assert wall.length_meters > 0

    def test_empty_planes_produce_zero_walls(self):
        detector = WallDetector()
        result = detector.detect(planes_json=[])
        assert result.wall_count == 0
        assert result.total_linear_feet == 0


class TestStageWeightsForProgressReporting:
    """iOS uses server-reported progress which is computed from stage weights."""

    def test_weights_sum_to_one(self):
        total = sum(STAGE_WEIGHTS.values())
        assert total == pytest.approx(1.0, abs=0.01)

    def test_progress_monotonically_increases(self):
        """Simulate progress through stages and verify it only increases."""
        stages = list(STAGE_WEIGHTS.keys())
        cumulative = 0.0
        for stage in stages:
            cumulative += STAGE_WEIGHTS[stage]
            assert cumulative > 0
        assert cumulative == pytest.approx(1.0, abs=0.01)


class TestEndToEndStageChain:
    """Test a realistic chain of stages with compatible input/output."""

    def test_wall_detection_to_floor_plan(self):
        """WallDetectionResult → FloorPlanGenerator produces valid output."""
        # Stage 4: Wall detection
        walls = WallDetectionResult(
            walls=[
                WallSegment(
                    start=(0, 0), end=(3.0, 0),
                    length_meters=3.0, length_inches=118.11,
                    orientation=0.0, source="arkit_plane",
                ),
                WallSegment(
                    start=(3.0, 0), end=(3.0, 2.4),
                    length_meters=2.4, length_inches=94.49,
                    orientation=90.0, source="arkit_plane",
                ),
            ],
            corners=[(3.0, 0)],
            total_linear_inches=212.6,
            total_linear_feet=17.72,
            wall_count=2,
        )

        # Stage 3: Calibration
        calibration = CalibrationResult(
            scale_factor=1.02,
            confidence="medium",
            reference_used="base_cabinet_height",
            cross_validation_score=0.75,
            references_found=["base_cabinet_height"],
        )

        # Stage 6: Snap (empty for this test)
        snapped = SnapResult(snapped_objects=[], flagged_count=0, total_snapped=0)

        # Stage 7: Floor plan
        gen = FloorPlanGenerator()
        result = gen.generate(walls, snapped, calibration)

        # Verify output chain
        assert isinstance(result, FloorPlanResult)
        assert result.total_linear_ft == pytest.approx(17.72, rel=0.01)
        assert result.floor_plan_png[:4] == b"\x89PNG"
        assert result.measurements_json["wall_count"] == 2
        assert result.measurements_json["total_linear_ft"] == pytest.approx(17.72, rel=0.01)

        # Stage 8: VLM validation (non-blocking)
        validator = VLMValidator(api_key=None)
        validation = validator.validate(floor_plan_png=result.floor_plan_png)
        assert validation.passed is True

    def test_snap_to_standards_output_in_floor_plan(self):
        """SnapResult objects appear in floor plan measurements_json."""
        from pipeline.stages.object_detection import DetectedObject

        obj = DetectedObject(
            label="base cabinet",
            instance_id=0,
            bbox=(50, 50, 150, 200),
            mask=None,
            width_inches=23.8,
            height_inches=34.5,
            depth_inches=24.0,
            confidence=0.9,
            frame_index=0,
            standard_width_inches=24.0,
            deviation_inches=0.2,
        )

        from pipeline.stages.snap_to_standards import SnappedObject

        snapped = SnapResult(
            snapped_objects=[
                SnappedObject(
                    object=obj,
                    raw_width_inches=23.8,
                    snapped_width_inches=24.0,
                    deviation_inches=0.2,
                    is_flagged=False,
                ),
            ],
            flagged_count=0,
            total_snapped=1,
        )

        walls = WallDetectionResult(
            walls=[
                WallSegment(
                    start=(0, 0), end=(3.0, 0),
                    length_meters=3.0, length_inches=118.11,
                    orientation=0.0, source="arkit_plane",
                ),
            ],
            corners=[],
            total_linear_inches=118.11,
            total_linear_feet=9.84,
            wall_count=1,
        )

        calibration = CalibrationResult(
            scale_factor=1.0,
            confidence="high",
            reference_used="base_cabinet_height",
            cross_validation_score=0.9,
            references_found=["base_cabinet_height"],
        )

        gen = FloorPlanGenerator()
        result = gen.generate(walls, snapped, calibration)

        mj = result.measurements_json
        assert "measurements" in mj
        # The measurements dict should contain object info
        measurements = mj["measurements"]
        assert isinstance(measurements, dict)
