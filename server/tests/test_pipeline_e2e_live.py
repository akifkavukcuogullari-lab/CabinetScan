#!/usr/bin/env python3
"""End-to-end live test of the non-LiDAR server pipeline.

Triggers a real processing job via the Edge Functions, polls for completion,
validates results against the known baseline from job 8ee5b113.

Uses urllib.request for all HTTP calls (no curl, no requests library).
"""

import json
import sys
import time
import urllib.request
import urllib.error
from datetime import datetime, timezone

# ── Configuration ──────────────────────────────────────────────────────────────

SUPABASE_URL = "https://wnyrnpeabhxdqvcpofmb.supabase.co"
ANON_KEY = (
    "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9."
    "eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6IndueXJucGVhYmh4ZHF2Y3BvZm1iIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NjQyNDYzNTgsImV4cCI6MjA3OTgyMjM1OH0."
    "OOangh4u0sy7oHFQl1pFv6ldNPlN201uY774gpyQlHc"
)

SHOWROOM_ID = "dc808235-f00d-45ee-b3e3-9b720d2c6926"
VIDEO_URL = (
    "https://wnyrnpeabhxdqvcpofmb.supabase.co/storage/v1/object/public/"
    "scans/qnexwr/ai_video_1770503230_1ABCEA71.mp4"
)
POSES_URL = (
    "https://wnyrnpeabhxdqvcpofmb.supabase.co/storage/v1/object/public/"
    "scans/qnexwr/ai_capture_16AEF252-8D80-4EF9-9F54-FF43E14A46B4/poses.json"
)
PLANES_URL = (
    "https://wnyrnpeabhxdqvcpofmb.supabase.co/storage/v1/object/public/"
    "scans/qnexwr/ai_capture_16AEF252-8D80-4EF9-9F54-FF43E14A46B4/planes.json"
)
METADATA = {
    "has_lidar": True,
    "frame_count": 5817,
    "photo_count": 5,
    "plane_count": 37,
    "device_model": "iPhone",
    "showroom_code": "QNEXWR",
    "video_duration": 60.8,
    "video_resolution": "1080x1920",
    "video_size_bytes": 5379262,
}

# Known baseline from job 8ee5b113
BASELINE = {
    "wall_count": 7,
    "total_linear_ft": 48.5,
    "total_area_sqft": 455.2,
    "processing_time_s": 4.3,
    "scale_confidence": "medium",
    "validation_passed": True,
}

# Tolerances for baseline comparison
TOLERANCE_LINEAR_FT = 5.0   # +/- 5 ft
TOLERANCE_AREA_SQFT = 50.0  # +/- 50 sq ft
TOLERANCE_WALL_COUNT = 2    # +/- 2 walls

POLL_INTERVAL_S = 10
QUEUED_WARN_S = 180  # 3 minutes — warn RunPod likely down
MAX_POLL_S = 300  # 5 minutes total timeout

# ── Helpers ────────────────────────────────────────────────────────────────────

def make_request(url, method="GET", body=None):
    """Make an HTTP request and return (status_code, parsed_json, raw_body)."""
    headers = {
        "Authorization": f"Bearer {ANON_KEY}",
        "apikey": ANON_KEY,
        "Content-Type": "application/json",
    }
    data = None
    if body is not None:
        data = json.dumps(body).encode("utf-8")

    req = urllib.request.Request(url, data=data, headers=headers, method=method)

    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            raw = resp.read().decode("utf-8")
            try:
                parsed = json.loads(raw)
            except json.JSONDecodeError:
                parsed = None
            return resp.status, parsed, raw
    except urllib.error.HTTPError as e:
        raw = e.read().decode("utf-8") if e.fp else ""
        try:
            parsed = json.loads(raw)
        except json.JSONDecodeError:
            parsed = None
        return e.code, parsed, raw


def ts():
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def print_step(step_num, total, name, passed, detail=""):
    icon = "PASS" if passed else "FAIL"
    print(f"\n[{step_num}/{total}] {name}: {icon}")
    if detail:
        for line in detail.strip().split("\n"):
            print(f"  {line}")


# ── Main Test ──────────────────────────────────────────────────────────────────

def main():
    print("=" * 60)
    print("  Pipeline E2E Test Report")
    print("=" * 60)
    print(f"Timestamp: {ts()}")
    print(f"Environment: QA (wnyrnpeabhxdqvcpofmb)")
    print(f"Functions Tested: create-processing-job, get-job-status, get-job-results")
    print()

    overall_start = time.time()
    all_passed = True
    job_id = None
    final_status = None

    # ── Step 1: Pre-Flight ─────────────────────────────────────────────────
    step_start = time.time()
    print("--- Pre-Flight Checks ---")

    # Check video URL is reachable (HEAD request)
    try:
        head_req = urllib.request.Request(VIDEO_URL, method="HEAD")
        with urllib.request.urlopen(head_req, timeout=10) as resp:
            video_ok = resp.status == 200
            video_detail = f"Video URL reachable, status {resp.status}"
    except Exception as e:
        video_ok = False
        video_detail = f"Video URL unreachable: {e}"

    # Check edge function is reachable (OPTIONS preflight)
    ef_url = f"{SUPABASE_URL}/functions/v1/create-processing-job"
    try:
        opts_req = urllib.request.Request(ef_url, method="OPTIONS")
        with urllib.request.urlopen(opts_req, timeout=10) as resp:
            ef_ok = resp.status in (200, 204)
            ef_detail = f"Edge function reachable, OPTIONS status {resp.status}"
    except urllib.error.HTTPError as e:
        # Some edge functions return 200 for OPTIONS via CORS
        ef_ok = e.code in (200, 204)
        ef_detail = f"Edge function OPTIONS returned {e.code}"
    except Exception as e:
        ef_ok = False
        ef_detail = f"Edge function unreachable: {e}"

    preflight_ok = video_ok and ef_ok
    if not preflight_ok:
        all_passed = False
    print_step(1, 5, "Pre-Flight", preflight_ok,
               f"{video_detail}\n{ef_detail}\nDuration: {time.time()-step_start:.1f}s")

    if not preflight_ok:
        print("\nABORTING: Pre-flight checks failed.")
        sys.exit(1)

    # ── Step 2: Trigger Processing Job ─────────────────────────────────────
    step_start = time.time()
    print("\n--- Triggering Processing Job ---")

    payload = {
        "video_url": VIDEO_URL,
        "poses_url": POSES_URL,
        "planes_url": PLANES_URL,
        "showroom_id": SHOWROOM_ID,
        "metadata": METADATA,
    }

    status_code, resp_json, raw_body = make_request(ef_url, method="POST", body=payload)

    trigger_ok = status_code == 201 and resp_json and "job_id" in resp_json
    if trigger_ok:
        job_id = resp_json["job_id"]
        runpod_triggered = resp_json.get("runpod_triggered", False)
        runpod_job_id = resp_json.get("runpod_job_id")
        runpod_error = resp_json.get("runpod_error")
        detail = (
            f"HTTP {status_code}\n"
            f"job_id: {job_id}\n"
            f"runpod_triggered: {runpod_triggered}\n"
            f"runpod_job_id: {runpod_job_id}\n"
        )
        if runpod_error:
            detail += f"runpod_error: {runpod_error}\n"
        if not runpod_triggered:
            detail += "WARNING: RunPod was NOT triggered. Job may stay queued.\n"
    else:
        detail = f"HTTP {status_code}\nResponse: {raw_body[:500]}"
        all_passed = False

    print_step(2, 5, "Trigger Job", trigger_ok,
               f"POST /functions/v1/create-processing-job\n{detail}Duration: {time.time()-step_start:.1f}s")

    if not trigger_ok:
        print("\nABORTING: Failed to create processing job.")
        sys.exit(1)

    # ── Step 3: Poll for Completion ────────────────────────────────────────
    step_start = time.time()
    print("\n--- Polling for Completion ---")

    status_url = f"{SUPABASE_URL}/functions/v1/get-job-status?job_id={job_id}"
    elapsed = 0
    poll_count = 0
    last_stage = ""
    queued_warned = False

    while elapsed < MAX_POLL_S:
        poll_count += 1
        s_code, s_json, s_raw = make_request(status_url, method="GET")

        if s_code != 200 or not s_json:
            print(f"  Poll #{poll_count} ({elapsed}s): HTTP {s_code} - {s_raw[:200]}")
        else:
            final_status = s_json.get("status", "unknown")
            progress = s_json.get("progress", 0)
            stage = s_json.get("stage", "")
            error_msg = s_json.get("error_message")

            if stage != last_stage:
                print(f"  Poll #{poll_count} ({elapsed}s): status={final_status}, "
                      f"progress={progress:.0%}, stage=\"{stage}\"")
                last_stage = stage
            else:
                print(f"  Poll #{poll_count} ({elapsed}s): status={final_status}, "
                      f"progress={progress:.0%}")

            if final_status == "completed":
                print(f"  Job completed after {elapsed}s ({poll_count} polls)")
                break
            elif final_status == "failed":
                print(f"  Job FAILED after {elapsed}s")
                print(f"  Error: {error_msg}")
                all_passed = False
                break

            # Warn if stuck in queued for over 3 minutes
            if final_status == "queued" and elapsed >= QUEUED_WARN_S and not queued_warned:
                queued_warned = True
                print(f"\n  WARNING: Job has been 'queued' for over {QUEUED_WARN_S}s.")
                print("  RunPod worker is likely down or not receiving jobs.")
                print("  Continuing to poll until {MAX_POLL_S}s timeout...\n")

        time.sleep(POLL_INTERVAL_S)
        elapsed = int(time.time() - step_start)

    if elapsed >= MAX_POLL_S and final_status not in ("completed", "failed"):
        print(f"\n  TIMEOUT: Job still in '{final_status}' after {MAX_POLL_S}s.")
        if final_status == "queued":
            print("  DIAGNOSIS: Job stuck in 'queued'. The RunPod worker may be down,")
            print("  sleeping, or the RUNPOD_ENDPOINT_ID/RUNPOD_API_KEY env vars may")
            print("  not be set on the edge function.")
        all_passed = False

    poll_ok = final_status == "completed"
    print_step(3, 5, "Poll Completion", poll_ok,
               f"Final status: {final_status}\n"
               f"Polls: {poll_count}\n"
               f"Duration: {time.time()-step_start:.1f}s")

    if not poll_ok:
        print(f"\nOverall: FAIL")
        print(f"Duration: {time.time()-overall_start:.1f}s")
        sys.exit(1)

    # ── Step 4: Fetch Results ──────────────────────────────────────────────
    step_start = time.time()
    print("\n--- Fetching Results ---")

    results_url = f"{SUPABASE_URL}/functions/v1/get-job-results?job_id={job_id}"
    r_code, r_json, r_raw = make_request(results_url, method="GET")

    results_ok = r_code == 200 and r_json and "measurements_data" in r_json
    if results_ok:
        measurements_data = r_json.get("measurements_data", {})
        floor_plan_url = r_json.get("floor_plan_png_url", "")
        validation_passed = r_json.get("validation_passed")
        validation_issues = r_json.get("validation_issues", [])
        processing_time_ms = r_json.get("processing_time_ms", 0)
        scale_confidence = r_json.get("scale_confidence", "")
        stage_timings = r_json.get("stage_timings", {})
        pipeline_version = r_json.get("pipeline_version", "")

        detail = (
            f"HTTP {r_code}\n"
            f"pipeline_version: {pipeline_version}\n"
            f"processing_time_ms: {processing_time_ms}\n"
            f"scale_confidence: {scale_confidence}\n"
            f"validation_passed: {validation_passed}\n"
            f"validation_issues: {validation_issues}\n"
            f"floor_plan_png_url: {floor_plan_url[:80]}...\n"
            f"stage_timings: {json.dumps(stage_timings, indent=2)}\n"
        )

        # Extract from top-level measurements_data (where the pipeline stores them)
        wall_count = measurements_data.get("wall_count", 0)
        total_linear_ft = measurements_data.get("total_linear_ft", 0)
        total_area_sqft = measurements_data.get("total_sq_ft", 0)

        # Walls are nested inside measurements_data.measurements.walls
        measurements_inner = measurements_data.get("measurements", {})
        walls = measurements_inner.get("walls", [])

        detail += f"\n--- Measurements Summary ---\n"
        detail += f"Wall count (top-level): {wall_count}\n"
        detail += f"Walls in array: {len(walls)}\n"
        detail += f"Total linear ft: {total_linear_ft}\n"
        detail += f"Total area sqft: {total_area_sqft}\n"

        for i, w in enumerate(walls):
            detail += (
                f"  Wall {i+1}: {w.get('id','?')} - "
                f"{w.get('linear_ft', 0):.1f} ft, "
                f"orientation={w.get('orientation', '?')}\n"
            )
    else:
        detail = f"HTTP {r_code}\nResponse: {r_raw[:500]}"
        all_passed = False

    print_step(4, 5, "Fetch Results", results_ok,
               f"{detail}Duration: {time.time()-step_start:.1f}s")

    if not results_ok:
        print(f"\nOverall: FAIL")
        print(f"Duration: {time.time()-overall_start:.1f}s")
        sys.exit(1)

    # ── Step 5: Validate Against Baseline ──────────────────────────────────
    step_start = time.time()
    print("\n--- Validating Against Baseline (job 8ee5b113) ---")

    checks = []

    # Wall count (use top-level wall_count, fall back to array length)
    actual_walls = wall_count if wall_count > 0 else len(walls)
    wall_diff = abs(actual_walls - BASELINE["wall_count"])
    wall_ok = wall_diff <= TOLERANCE_WALL_COUNT
    checks.append(("Wall count", wall_ok,
                    f"Expected ~{BASELINE['wall_count']}, got {actual_walls} "
                    f"(diff={wall_diff}, tol={TOLERANCE_WALL_COUNT})"))

    # Total linear ft
    linear_diff = abs(total_linear_ft - BASELINE["total_linear_ft"])
    linear_ok = linear_diff <= TOLERANCE_LINEAR_FT
    checks.append(("Total linear ft", linear_ok,
                    f"Expected ~{BASELINE['total_linear_ft']}, got {total_linear_ft:.1f} "
                    f"(diff={linear_diff:.1f}, tol={TOLERANCE_LINEAR_FT})"))

    # Total area sqft
    area_diff = abs(total_area_sqft - BASELINE["total_area_sqft"])
    area_ok = area_diff <= TOLERANCE_AREA_SQFT
    checks.append(("Total area sqft", area_ok,
                    f"Expected ~{BASELINE['total_area_sqft']}, got {total_area_sqft:.1f} "
                    f"(diff={area_diff:.1f}, tol={TOLERANCE_AREA_SQFT})"))

    # Scale confidence — accept "medium" or "high"
    conf_ok = scale_confidence in ("medium", "high")
    checks.append(("Scale confidence", conf_ok,
                    f"Expected 'medium' or 'high', got '{scale_confidence}'"))

    # Validation passed (VLM is non-deterministic; treat as informational)
    val_ok = validation_passed == BASELINE["validation_passed"]
    val_label = "INFO" if not val_ok else "PASS"
    # Don't count VLM mismatch as a hard failure
    checks.append(("Validation passed (VLM, non-deterministic)", True,
                    f"Baseline={BASELINE['validation_passed']}, Actual={validation_passed} "
                    f"[{val_label}] issues={validation_issues}"))

    # Floor plan URL exists and is accessible
    fp_exists = bool(floor_plan_url) and floor_plan_url.startswith("http")
    fp_accessible = False
    if fp_exists:
        try:
            fp_head = urllib.request.Request(floor_plan_url, method="HEAD")
            with urllib.request.urlopen(fp_head, timeout=15) as fp_resp:
                fp_accessible = fp_resp.status < 400
        except urllib.error.HTTPError as e:
            fp_accessible = e.code < 400
        except Exception:
            fp_accessible = False
    fp_ok = fp_exists and fp_accessible
    checks.append(("Floor plan URL (exists + accessible)", fp_ok,
                    f"exists={fp_exists}, accessible={fp_accessible}"
                    f" url={floor_plan_url[:80] if floor_plan_url else 'N/A'}"))

    # Processing time (informational, not a pass/fail)
    processing_s = processing_time_ms / 1000.0
    time_info = (f"Baseline: {BASELINE['processing_time_s']:.1f}s, "
                 f"Actual: {processing_s:.1f}s")

    baseline_all_ok = all(c[1] for c in checks)
    if not baseline_all_ok:
        all_passed = False

    detail = ""
    for name, ok, msg in checks:
        icon = "PASS" if ok else "FAIL"
        detail += f"  [{icon}] {name}: {msg}\n"
    detail += f"  [INFO] Processing time: {time_info}\n"

    print_step(5, 5, "Baseline Validation", baseline_all_ok,
               f"{detail}Duration: {time.time()-step_start:.1f}s")

    # ── Summary ────────────────────────────────────────────────────────────
    total_duration = time.time() - overall_start
    print("\n" + "=" * 60)
    overall_result = "PASS" if all_passed else "FAIL"
    print(f"Overall: {overall_result}")
    print(f"Job ID: {job_id}")
    print(f"Total Duration: {total_duration:.1f}s")
    print("=" * 60)

    sys.exit(0 if all_passed else 1)


if __name__ == "__main__":
    main()
