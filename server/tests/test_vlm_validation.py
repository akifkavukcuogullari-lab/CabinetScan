"""Tests for Stage 8: VLM Validation."""

import pytest

from pipeline.stages.vlm_validation import VLMValidator, ValidationResult


class TestVLMValidator:
    def test_no_api_key_skips_validation(self):
        validator = VLMValidator(api_key=None)
        result = validator.validate(floor_plan_png=b"fake png")
        assert result.passed is True
        assert result.confidence == 0.0
        assert any("skipped" in issue.lower() for issue in result.issues)

    def test_empty_api_key_skips_validation(self):
        validator = VLMValidator(api_key="")
        result = validator.validate(floor_plan_png=b"fake png")
        assert result.passed is True

    def test_result_has_required_fields(self):
        validator = VLMValidator(api_key=None)
        result = validator.validate(floor_plan_png=b"fake png")
        assert isinstance(result, ValidationResult)
        assert isinstance(result.passed, bool)
        assert isinstance(result.issues, list)
        assert isinstance(result.confidence, float)

    def test_invalid_api_key_graceful_failure(self):
        """VLM validation should not block pipeline on failure."""
        validator = VLMValidator(api_key="invalid-key-12345")
        result = validator.validate(
            floor_plan_png=b"fake png",
            kitchen_photo=b"fake photo",
            measurements_json={"room_name": "Kitchen"},
        )
        # Should return passing result with error warning
        assert result.passed is True
        assert len(result.issues) > 0
        assert result.confidence == 0.0
