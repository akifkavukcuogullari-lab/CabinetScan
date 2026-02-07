"""Stage 8: VLM Validation — Validate results using vision-language model.

Sends the floor plan + a representative kitchen photo to GPT-4o
to sanity-check the measurements. Best-effort, non-blocking on failure.
"""

import json
import base64
from dataclasses import dataclass

from ..utils.errors import ValidationError


@dataclass
class ValidationResult:
    """Result of VLM validation."""
    passed: bool
    issues: list[str]
    confidence: float  # 0-1
    raw_response: str | None = None


class VLMValidator:
    """Validate measurements using a vision-language model."""

    SYSTEM_PROMPT = """You are a kitchen measurement validator. Given a floor plan image and a photo of the kitchen, check if the measurements are reasonable.

Look for:
1. Wall lengths that seem wrong (e.g., 2-foot kitchen wall)
2. Cabinet counts that don't match what you see
3. Missing major items (e.g., no refrigerator when one is visible)
4. Unreasonable room dimensions

Respond with JSON:
{
    "passed": true/false,
    "issues": ["issue 1", "issue 2"],
    "confidence": 0.0-1.0
}"""

    def __init__(self, api_key: str | None = None):
        self.api_key = api_key

    def validate(
        self,
        floor_plan_png: bytes,
        kitchen_photo: bytes | None = None,
        measurements_json: dict | None = None,
    ) -> ValidationResult:
        """Validate measurements using GPT-4o.

        This is best-effort: if it fails, returns a passing result
        with a warning rather than blocking the pipeline.

        Args:
            floor_plan_png: Floor plan image
            kitchen_photo: Optional representative kitchen photo
            measurements_json: Optional measurements data

        Returns:
            ValidationResult
        """
        if not self.api_key:
            return ValidationResult(
                passed=True,
                issues=["VLM validation skipped (no API key)"],
                confidence=0.0,
            )

        try:
            import openai

            client = openai.OpenAI(api_key=self.api_key)

            # Build messages with images
            content = [{"type": "text", "text": "Validate these kitchen measurements:"}]

            # Add floor plan
            fp_b64 = base64.b64encode(floor_plan_png).decode()
            content.append({
                "type": "image_url",
                "image_url": {"url": f"data:image/png;base64,{fp_b64}"},
            })

            # Add kitchen photo if available
            if kitchen_photo:
                photo_b64 = base64.b64encode(kitchen_photo).decode()
                content.append({
                    "type": "image_url",
                    "image_url": {"url": f"data:image/jpeg;base64,{photo_b64}"},
                })

            # Add measurements summary
            if measurements_json:
                summary = json.dumps(measurements_json, indent=2)[:2000]
                content.append({"type": "text", "text": f"Measurements:\n{summary}"})

            response = client.chat.completions.create(
                model="gpt-4o",
                messages=[
                    {"role": "system", "content": self.SYSTEM_PROMPT},
                    {"role": "user", "content": content},
                ],
                response_format={"type": "json_object"},
                max_tokens=500,
            )

            result_text = response.choices[0].message.content or "{}"
            result = json.loads(result_text)

            return ValidationResult(
                passed=result.get("passed", True),
                issues=result.get("issues", []),
                confidence=result.get("confidence", 0.5),
                raw_response=result_text,
            )

        except Exception as e:
            # Best-effort: don't block pipeline on validation failure
            return ValidationResult(
                passed=True,
                issues=[f"VLM validation failed: {str(e)}"],
                confidence=0.0,
            )
