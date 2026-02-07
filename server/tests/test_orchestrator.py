"""Tests for Pipeline Orchestrator."""

import pytest

from pipeline.orchestrator import (
    PipelineOrchestrator,
    PipelineInput,
    PipelineOutput,
    STAGE_WEIGHTS,
)


class TestStageWeights:
    def test_weights_sum_to_one(self):
        total = sum(STAGE_WEIGHTS.values())
        assert total == pytest.approx(1.0, abs=0.01)

    def test_all_stages_have_weights(self):
        expected_stages = [
            "frame_extraction",
            "depth_estimation",
            "scale_calibration",
            "wall_detection",
            "object_detection",
            "snap_to_standards",
            "floor_plan_gen",
            "vlm_validation",
        ]
        for stage in expected_stages:
            assert stage in STAGE_WEIGHTS, f"Missing weight for {stage}"

    def test_weights_are_positive(self):
        for stage, weight in STAGE_WEIGHTS.items():
            assert weight > 0, f"Weight for {stage} should be positive"


class TestPipelineInput:
    def test_input_with_defaults(self):
        inp = PipelineInput(
            video_path="/tmp/video.mp4",
            poses_json=[],
            planes_json=[],
        )
        assert inp.video_path == "/tmp/video.mp4"
        assert inp.photo_paths == []
        assert inp.metadata == {}

    def test_input_with_all_fields(self):
        inp = PipelineInput(
            video_path="/tmp/video.mp4",
            poses_json=[{"timestamp": 0}],
            planes_json=[{"alignment": "vertical"}],
            photo_paths=["/tmp/photo1.jpg"],
            metadata={"device_model": "iPhone"},
        )
        assert len(inp.poses_json) == 1
        assert len(inp.planes_json) == 1
        assert len(inp.photo_paths) == 1


class TestPipelineOrchestrator:
    def test_orchestrator_init(self):
        orch = PipelineOrchestrator(device="cpu")
        assert orch.device == "cpu"
        assert orch.frame_extractor is not None
        assert orch.wall_detector is not None
        assert orch.snap_to_standards is not None
        assert orch.floor_plan_generator is not None

    def test_orchestrator_has_all_stages(self):
        orch = PipelineOrchestrator(device="cpu")
        assert hasattr(orch, "frame_extractor")
        assert hasattr(orch, "depth_estimator")
        assert hasattr(orch, "scale_calibrator")
        assert hasattr(orch, "wall_detector")
        assert hasattr(orch, "object_detector")
        assert hasattr(orch, "snap_to_standards")
        assert hasattr(orch, "floor_plan_generator")
        assert hasattr(orch, "vlm_validator")
