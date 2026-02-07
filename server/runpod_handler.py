"""RunPod Serverless Handler — Entry point for GPU pipeline execution.

Downloads input files from Supabase storage, runs the pipeline,
uploads results, and updates job status.
"""

import asyncio
import json
import os
import tempfile
from pathlib import Path

import runpod

from pipeline.orchestrator import PipelineOrchestrator, PipelineInput
from pipeline.utils.supabase_client import SupabaseClient
from pipeline.utils.errors import PipelineError


# Load models once at container startup (persistent in VRAM)
print("[RunPod] Loading models...")
orchestrator = PipelineOrchestrator(device="cuda")
orchestrator.load_models()
print("[RunPod] Models loaded successfully")


async def process_job(job_input: dict) -> dict:
    """Process a single pipeline job.

    Args:
        job_input: {
            "job_id": str,
            "video_url": str,
            "poses_url": str | None,
            "planes_url": str | None,
            "metadata": dict,
        }

    Returns:
        {"status": "completed"} or {"status": "failed", "error": str}
    """
    job_id = job_input["job_id"]
    supabase = SupabaseClient()

    try:
        # Update status to processing
        await supabase.update_job_status(
            job_id, status="processing", progress=0.0, stage="Downloading files..."
        )

        # Download input files to temp directory
        with tempfile.TemporaryDirectory() as tmpdir:
            tmpdir = Path(tmpdir)

            # Download video
            video_data = await supabase.download_file(job_input["video_url"])
            video_path = tmpdir / "video.mp4"
            video_path.write_bytes(video_data)

            # Download poses
            poses_json = []
            if job_input.get("poses_url"):
                poses_data = await supabase.download_file(job_input["poses_url"])
                poses_json = json.loads(poses_data).get("poses", [])

            # Download planes
            planes_json = []
            if job_input.get("planes_url"):
                planes_data = await supabase.download_file(job_input["planes_url"])
                planes_json = json.loads(planes_data)

            # Build pipeline input
            pipeline_input = PipelineInput(
                video_path=str(video_path),
                poses_json=poses_json,
                planes_json=planes_json,
                metadata=job_input.get("metadata", {}),
            )

            # Progress callback
            async def on_progress(progress: float, stage: str) -> None:
                await supabase.update_job_status(
                    job_id, progress=progress, stage=stage
                )

            # Run pipeline (sync, wrapped for progress)
            def sync_progress(progress: float, stage: str) -> None:
                asyncio.get_event_loop().create_task(on_progress(progress, stage))

            output = orchestrator.run(pipeline_input, on_progress=sync_progress)

            # Upload results
            showroom_code = job_input.get("metadata", {}).get("showroom_code", "unknown")
            base_path = f"{showroom_code}/results/{job_id}"

            # Upload floor plan PNG
            floor_plan_url = await supabase.upload_file(
                bucket="scans",
                path=f"{base_path}/floor_plan.png",
                data=output.floor_plan_png,
                content_type="image/png",
            )

            # Upload measurements JSON
            measurements_bytes = json.dumps(output.measurements_json, indent=2).encode()
            measurements_url = await supabase.upload_file(
                bucket="scans",
                path=f"{base_path}/measurements.json",
                data=measurements_bytes,
                content_type="application/json",
            )

            # Update job as completed
            await supabase.update_job_status(
                job_id,
                status="completed",
                progress=1.0,
                stage="Complete",
                floor_plan_png_url=floor_plan_url,
                measurements_json_url=measurements_url,
                measurements_data=output.measurements_json,
                scale_confidence=output.scale_confidence,
                validation_passed=output.validation_passed,
                validation_issues=output.validation_issues,
                processing_time_ms=output.processing_time_ms,
                stage_timings=output.stage_timings,
            )

            return {"status": "completed", "job_id": job_id}

    except PipelineError as e:
        await supabase.update_job_status(
            job_id,
            status="failed",
            error_message=str(e),
        )
        return {"status": "failed", "error": str(e)}

    except Exception as e:
        await supabase.update_job_status(
            job_id,
            status="failed",
            error_message=f"Unexpected error: {str(e)}",
        )
        return {"status": "failed", "error": str(e)}


def handler(job: dict) -> dict:
    """RunPod handler entry point."""
    return asyncio.run(process_job(job["input"]))


# Start RunPod serverless worker
runpod.serverless.start({"handler": handler})
