"""Pipeline error definitions."""


class PipelineError(Exception):
    """Base error for all pipeline stages."""

    def __init__(self, stage: str, message: str):
        self.stage = stage
        self.message = message
        super().__init__(f"[{stage}] {message}")


class FrameExtractionError(PipelineError):
    def __init__(self, message: str):
        super().__init__("frame_extraction", message)


class DepthEstimationError(PipelineError):
    def __init__(self, message: str):
        super().__init__("depth_estimation", message)


class ScaleCalibrationError(PipelineError):
    def __init__(self, message: str):
        super().__init__("scale_calibration", message)


class WallDetectionError(PipelineError):
    def __init__(self, message: str):
        super().__init__("wall_detection", message)


class ObjectDetectionError(PipelineError):
    def __init__(self, message: str):
        super().__init__("object_detection", message)


class FloorPlanError(PipelineError):
    def __init__(self, message: str):
        super().__init__("floor_plan_gen", message)


class ValidationError(PipelineError):
    def __init__(self, message: str):
        super().__init__("vlm_validation", message)
