"""Pipeline Orchestrator — Runs all 8 stages sequentially.

Models are loaded once at worker startup and kept in VRAM.
Progress is reported after each stage via callback.
"""

import json
import os
import time
from dataclasses import dataclass, field
from typing import Any, Callable

from .stages.frame_extraction import FrameExtractor
from .stages.depth_estimation import DepthEstimator
from .stages.scale_calibration import ScaleCalibrator
from .stages.wall_detection import WallDetector
from .stages.object_detection import ObjectDetector
from .stages.snap_to_standards import SnapToStandards
from .stages.floor_plan_gen import FloorPlanGenerator
from .stages.vlm_validation import VLMValidator
from .utils.errors import PipelineError


@dataclass
class PipelineInput:
    """Input to the pipeline orchestrator."""
    video_path: str
    poses_json: list[dict]
    planes_json: list[dict]
    photo_paths: list[str] = field(default_factory=list)
    metadata: dict[str, Any] = field(default_factory=dict)


@dataclass
class PipelineOutput:
    """Output from the pipeline orchestrator."""
    measurements_json: dict[str, Any]
    floor_plan_png: bytes
    validation_passed: bool
    validation_issues: list[str]
    processing_time_ms: int
    stage_timings: dict[str, int]
    scale_confidence: str


# Stage weights for progress reporting (sum = 1.0)
STAGE_WEIGHTS = {
    "frame_extraction": 0.10,
    "depth_estimation": 0.30,
    "scale_calibration": 0.05,
    "wall_detection": 0.10,
    "object_detection": 0.25,
    "snap_to_standards": 0.05,
    "floor_plan_gen": 0.10,
    "vlm_validation": 0.05,
}


class PipelineOrchestrator:
    """Orchestrates the 8-stage pipeline."""

    def __init__(self, device: str = "cuda"):
        self.device = device

        # Initialize stages
        self.frame_extractor = FrameExtractor()
        self.depth_estimator = DepthEstimator(device=device)
        self.scale_calibrator = ScaleCalibrator()
        self.wall_detector = WallDetector()
        self.object_detector = ObjectDetector(device=device)
        self.snap_to_standards = SnapToStandards()
        self.floor_plan_generator = FloorPlanGenerator()
        self.vlm_validator = VLMValidator(api_key=os.environ.get("OPENAI_API_KEY"))

    def load_models(self) -> None:
        """Load ML models into VRAM. Call once at worker startup."""
        self.depth_estimator.load_model()
        self.object_detector.load_model()

    def run(
        self,
        input: PipelineInput,
        on_progress: Callable[[float, str], None] | None = None,
    ) -> PipelineOutput:
        """Run the full pipeline.

        Args:
            input: Pipeline input data
            on_progress: Optional callback (progress: 0-1, stage_name: str)

        Returns:
            PipelineOutput with measurements and floor plan
        """
        start_time = time.time()
        stage_timings: dict[str, int] = {}
        cumulative_progress = 0.0

        def report(stage: str) -> None:
            nonlocal cumulative_progress
            cumulative_progress += STAGE_WEIGHTS.get(stage, 0)
            if on_progress:
                on_progress(min(cumulative_progress, 1.0), stage)

        try:
            # Stage 1: Frame Extraction
            stage_start = time.time()
            if on_progress:
                on_progress(0.0, "Extracting video frames...")
            frames = self.frame_extractor.extract(
                input.video_path, input.poses_json
            )
            stage_timings["frame_extraction"] = int((time.time() - stage_start) * 1000)
            report("frame_extraction")

            # Stage 2: Depth Estimation
            stage_start = time.time()
            if on_progress:
                on_progress(cumulative_progress, "Estimating depth...")
            depth_frames = self.depth_estimator.estimate(frames)
            stage_timings["depth_estimation"] = int((time.time() - stage_start) * 1000)
            report("depth_estimation")

            # Stage 3: Scale Calibration
            stage_start = time.time()
            if on_progress:
                on_progress(cumulative_progress, "Calibrating scale...")
            calibration = self.scale_calibrator.calibrate(depth_frames)
            stage_timings["scale_calibration"] = int((time.time() - stage_start) * 1000)
            report("scale_calibration")

            # Stage 4: Wall Detection
            stage_start = time.time()
            if on_progress:
                on_progress(cumulative_progress, "Detecting walls...")
            walls = self.wall_detector.detect(input.planes_json)
            stage_timings["wall_detection"] = int((time.time() - stage_start) * 1000)
            report("wall_detection")

            # Stage 5: Object Detection
            stage_start = time.time()
            if on_progress:
                on_progress(cumulative_progress, "Detecting cabinets and appliances...")
            objects = self.object_detector.detect(depth_frames, calibration)
            stage_timings["object_detection"] = int((time.time() - stage_start) * 1000)
            report("object_detection")

            # Stage 6: Snap to Standards
            stage_start = time.time()
            if on_progress:
                on_progress(cumulative_progress, "Matching standard sizes...")
            snapped = self.snap_to_standards.snap(objects.objects)
            stage_timings["snap_to_standards"] = int((time.time() - stage_start) * 1000)
            report("snap_to_standards")

            # Stage 7: Floor Plan Generation
            stage_start = time.time()
            if on_progress:
                on_progress(cumulative_progress, "Creating floor plan...")
            floor_plan = self.floor_plan_generator.generate(
                walls, snapped, calibration, input.metadata
            )
            stage_timings["floor_plan_gen"] = int((time.time() - stage_start) * 1000)
            report("floor_plan_gen")

            # Stage 8: VLM Validation
            stage_start = time.time()
            if on_progress:
                on_progress(cumulative_progress, "Validating results...")
            validation = self.vlm_validator.validate(
                floor_plan.floor_plan_png,
                measurements_json=floor_plan.measurements_json,
            )
            stage_timings["vlm_validation"] = int((time.time() - stage_start) * 1000)
            report("vlm_validation")

            total_ms = int((time.time() - start_time) * 1000)

            return PipelineOutput(
                measurements_json=floor_plan.measurements_json,
                floor_plan_png=floor_plan.floor_plan_png,
                validation_passed=validation.passed,
                validation_issues=validation.issues,
                processing_time_ms=total_ms,
                stage_timings=stage_timings,
                scale_confidence=calibration.confidence,
            )

        except PipelineError:
            raise
        except Exception as e:
            raise PipelineError("orchestrator", f"Unexpected error: {e}")
