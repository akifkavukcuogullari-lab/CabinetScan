"""RunPod Serverless Handler — Entry point for GPU pipeline execution.

Downloads input files from Supabase storage, runs the pipeline,
uploads results, and updates job status.
"""

import sys
import traceback

print("[RunPod] Python starting...", flush=True)
print(f"[RunPod] Python version: {sys.version}", flush=True)

# Step 1: Test basic imports
try:
    import asyncio
    import json
    import os
    import tempfile
    from pathlib import Path
    print("[RunPod] Basic imports OK", flush=True)
except Exception as e:
    print(f"[RunPod] FATAL basic imports: {e}", flush=True)
    sys.exit(1)

# Step 2: Test runpod
try:
    import runpod
    print(f"[RunPod] runpod {runpod.__version__} OK", flush=True)
except Exception as e:
    print(f"[RunPod] FATAL runpod: {e}", flush=True)
    sys.exit(1)

# Step 3: Test torch/CUDA
try:
    import torch
    cuda_available = torch.cuda.is_available()
    device_name = torch.cuda.get_device_name(0) if cuda_available else "N/A"
    print(f"[RunPod] torch {torch.__version__}, CUDA: {cuda_available}, GPU: {device_name}", flush=True)
except Exception as e:
    print(f"[RunPod] FATAL torch: {e}", flush=True)
    traceback.print_exc()
    sys.exit(1)

# Step 4: Test pipeline imports
try:
    from pipeline.orchestrator import PipelineOrchestrator, PipelineInput
    from pipeline.utils.supabase_client import SupabaseClient
    from pipeline.utils.errors import PipelineError
    print("[RunPod] Pipeline imports OK", flush=True)
except Exception as e:
    print(f"[RunPod] FATAL pipeline imports: {e}", flush=True)
    traceback.print_exc()
    sys.exit(1)

# Step 5: Authenticate with HuggingFace for gated models (SAM 3, Depth Anything)
try:
    from huggingface_hub import login as hf_login, whoami as hf_whoami
    hf_token = os.environ.get("HF_TOKEN") or os.environ.get("HUGGING_FACE_HUB_TOKEN")
    if hf_token:
        hf_login(token=hf_token, add_to_git_credential=False)
        print(f"[RunPod] HuggingFace login OK (token: {hf_token[:8]}...)", flush=True)
        # Verify token works
        try:
            user_info = hf_whoami()
            print(f"[RunPod] HF user: {user_info.get('name', 'unknown')}", flush=True)
        except Exception as who_err:
            print(f"[RunPod] HF whoami failed: {who_err}", flush=True)
    else:
        print("[RunPod] WARNING: No HF_TOKEN found — gated model downloads will fail", flush=True)
        print(f"[RunPod] Available env vars: {[k for k in os.environ.keys() if 'HF' in k or 'HUGGING' in k]}", flush=True)
except Exception as e:
    print(f"[RunPod] HuggingFace login failed: {e}", flush=True)

# Step 5b: Test HuggingFace access to SAM 3 repo
try:
    from huggingface_hub import model_info
    info = model_info("facebook/sam3")
    print(f"[RunPod] SAM 3 repo accessible: {info.modelId}, files: {len(info.siblings)}", flush=True)
except Exception as e:
    print(f"[RunPod] SAM 3 repo access FAILED: {type(e).__name__}: {e}", flush=True)

# Step 6: Load models
try:
    print("[RunPod] Loading models...", flush=True)
    orchestrator = PipelineOrchestrator(device="cuda" if torch.cuda.is_available() else "cpu")
    orchestrator.load_models()
    print("[RunPod] Models loaded successfully", flush=True)
except Exception as e:
    print(f"[RunPod] FATAL model loading: {e}", flush=True)
    traceback.print_exc()
    # Don't exit — start the worker anyway so we can see the error in logs
    orchestrator = None


async def process_job(job_input: dict) -> dict:
    """Process a single pipeline job."""
    if orchestrator is None:
        job_id = job_input.get("job_id")
        if job_id:
            try:
                supabase = SupabaseClient()
                await supabase.update_job_status(
                    job_id, status="failed",
                    error_message="Models failed to load at startup. Check RunPod logs.",
                )
            except Exception as db_err:
                print(f"[RunPod] Could not update DB for failed model load: {db_err}", flush=True)
        return {"status": "failed", "error": "Models failed to load at startup"}

    job_id = job_input["job_id"]
    supabase = SupabaseClient()

    # Diagnostic: decode JWT to verify role
    import os, base64
    diag_url = os.environ.get("SUPABASE_URL", "NOT_SET")
    diag_key = os.environ.get("SUPABASE_SERVICE_ROLE_KEY", "NOT_SET")
    diag_role = "UNKNOWN"
    try:
        payload = diag_key.split('.')[1]
        payload += '=' * (4 - len(payload) % 4)  # pad base64
        decoded = json.loads(base64.b64decode(payload))
        diag_role = decoded.get("role", "MISSING")
    except Exception:
        pass
    print(f"[DIAG] URL={diag_url} ROLE={diag_role}", flush=True)

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

            return {"status": "completed", "job_id": job_id, "diag_url": diag_url, "diag_role": diag_role}

    except PipelineError as e:
        try:
            await supabase.update_job_status(job_id, status="failed", error_message=str(e))
        except Exception as db_err:
            print(f"[DIAG] DB update also failed: {db_err}", flush=True)
        return {"status": "failed", "error": str(e), "diag_url": diag_url, "diag_role": diag_role}

    except Exception as e:
        try:
            await supabase.update_job_status(job_id, status="failed", error_message=f"Unexpected error: {str(e)}")
        except Exception as db_err:
            print(f"[DIAG] DB update also failed: {db_err}", flush=True)
        return {"status": "failed", "error": str(e), "diag_url": diag_url, "diag_role": diag_role}


async def handler(job: dict) -> dict:
    """RunPod handler entry point."""
    return await process_job(job["input"])


# Start RunPod serverless worker
print("[RunPod] Starting serverless worker...", flush=True)
runpod.serverless.start({"handler": handler})
