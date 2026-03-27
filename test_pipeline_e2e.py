#!/usr/bin/env python3
"""
End-to-end test for the CabinetScan non-LiDAR (AI) server processing pipeline.
Docker v21 deployed with HuggingFace diagnostic logging.

Tests: create-processing-job -> poll status -> fetch results or print error.
Uses only Python stdlib (urllib.request, json, time).
"""

import json
import time
import urllib.request
import urllib.error
import sys
from datetime import datetime, timezone

# -- Configuration -------------------------------------------------------------

SUPABASE_URL = "https://wnyrnpeabhxdqvcpofmb.supabase.co"
ANON_KEY = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6IndueXJucGVhYmh4ZHF2Y3BvZm1iIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NjQyNDYzNTgsImV4cCI6MjA3OTgyMjM1OH0.OOangh4u0sy7oHFQl1pFv6ldNPlN201uY774gpyQlHc"

SHOWROOM_ID = "dc808235-f00d-45ee-b3e3-9b720d2c6926"
VIDEO_URL = "https://wnyrnpeabhxdqvcpofmb.supabase.co/storage/v1/object/public/scans/qnexwr/ai_video_1770503230_1ABCEA71.mp4"
POSES_URL = "https://wnyrnpeabhxdqvcpofmb.supabase.co/storage/v1/object/public/scans/qnexwr/ai_capture_16AEF252-8D80-4EF9-9F54-FF43E14A46B4/poses.json"
PLANES_URL = "https://wnyrnpeabhxdqvcpofmb.supabase.co/storage/v1/object/public/scans/qnexwr/ai_capture_16AEF252-8D80-4EF9-9F54-FF43E14A46B4/planes.json"
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

POLL_INTERVAL_SEC = 10
POLL_TIMEOUT_SEC = 300  # 5 minutes

EDGE_FUNCTION_URL = f"{SUPABASE_URL}/functions/v1/create-processing-job"
REST_URL = f"{SUPABASE_URL}/rest/v1/processing_jobs"


# -- Helpers -------------------------------------------------------------------

def http_request(url, method="GET", data=None, headers=None):
    """Make an HTTP request using urllib.request. Returns (status, headers, body_dict)."""
    headers = headers or {}
    body_bytes = None
    if data is not None:
        body_bytes = json.dumps(data).encode("utf-8")
        headers.setdefault("Content-Type", "application/json")

    req = urllib.request.Request(url, data=body_bytes, headers=headers, method=method)
    try:
        resp = urllib.request.urlopen(req, timeout=30)
        raw = resp.read().decode("utf-8")
        try:
            body = json.loads(raw)
        except json.JSONDecodeError:
            body = {"_raw": raw}
        return resp.status, dict(resp.headers), body
    except urllib.error.HTTPError as e:
        raw = e.read().decode("utf-8") if e.fp else ""
        try:
            body = json.loads(raw)
        except json.JSONDecodeError:
            body = {"_raw": raw}
        return e.code, dict(e.headers), body


def ts():
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def print_section(number, total, title, passed):
    icon = "PASS" if passed else "FAIL"
    print(f"\n[{number}/{total}] {title}: {icon}")


# -- Main Test -----------------------------------------------------------------

def main():
    print("=" * 70)
    print("  CabinetScan Non-LiDAR Pipeline E2E Test")
    print(f"  Environment: QA (wnyrnpeabhxdqvcpofmb)")
    print(f"  Docker: v21 (HuggingFace diagnostic logging)")
    print(f"  Timestamp: {ts()}")
    print("=" * 70)

    overall_start = time.time()
    results = {}

    # -- [1/6] Pre-flight: check Supabase is reachable -------------------------
    print("\n--- [1/6] Pre-Flight Checks ---")
    try:
        status, _, body = http_request(
            f"{SUPABASE_URL}/rest/v1/",
            headers={
                "apikey": ANON_KEY,
                "Authorization": f"Bearer {ANON_KEY}",
            },
        )
        preflight_ok = status == 200
        print(f"  Supabase REST reachable: status={status}")
    except Exception as e:
        preflight_ok = False
        print(f"  Supabase REST unreachable: {e}")

    # Verify processing_jobs table exists via a select
    try:
        status2, _, body2 = http_request(
            f"{REST_URL}?select=id&limit=1",
            headers={
                "apikey": ANON_KEY,
                "Authorization": f"Bearer {ANON_KEY}",
            },
        )
        table_ok = status2 == 200
        print(f"  processing_jobs table: status={status2}")
    except Exception as e:
        table_ok = False
        print(f"  processing_jobs table check failed: {e}")

    # Check Edge Function endpoint responds to OPTIONS
    try:
        status3, _, _ = http_request(
            EDGE_FUNCTION_URL,
            method="OPTIONS",
            headers={
                "apikey": ANON_KEY,
                "Authorization": f"Bearer {ANON_KEY}",
            },
        )
        ef_ok = status3 in (200, 204)
        print(f"  Edge Function CORS: status={status3}")
    except Exception as e:
        ef_ok = False
        print(f"  Edge Function check failed: {e}")

    results["preflight"] = preflight_ok and table_ok and ef_ok
    print_section(1, 6, "Pre-Flight", results["preflight"])

    if not results["preflight"]:
        print("\n  ABORTING: Pre-flight checks failed. Cannot proceed.")
        sys.exit(1)

    # -- [2/6] Trigger processing job ------------------------------------------
    print("\n--- [2/6] Trigger Processing Job ---")
    payload = {
        "video_url": VIDEO_URL,
        "poses_url": POSES_URL,
        "planes_url": PLANES_URL,
        "photo_urls": [],
        "showroom_id": SHOWROOM_ID,
        "metadata": METADATA,
    }
    print(f"  POST {EDGE_FUNCTION_URL}")
    print(f"  Payload keys: {list(payload.keys())}")

    trigger_start = time.time()
    status, resp_headers, body = http_request(
        EDGE_FUNCTION_URL,
        method="POST",
        data=payload,
        headers={
            "apikey": ANON_KEY,
            "Authorization": f"Bearer {ANON_KEY}",
        },
    )
    trigger_duration = time.time() - trigger_start

    print(f"  Response: HTTP {status} ({trigger_duration:.1f}s)")
    print(f"  Body: {json.dumps(body, indent=2)}")

    trigger_ok = status == 201 and "job_id" in body
    results["trigger"] = trigger_ok
    print_section(2, 6, "Trigger Job", results["trigger"])

    if not trigger_ok:
        print(f"  ABORTING: Job creation failed with status {status}")
        sys.exit(1)

    job_id = body["job_id"]
    runpod_triggered = body.get("runpod_triggered", False)
    runpod_job_id = body.get("runpod_job_id")
    runpod_error = body.get("runpod_error")

    print(f"\n  Job ID:           {job_id}")
    print(f"  RunPod triggered: {runpod_triggered}")
    print(f"  RunPod job ID:    {runpod_job_id}")
    if runpod_error:
        print(f"  RunPod error:     {runpod_error}")

    # -- [3/6] Validate initial response ---------------------------------------
    print("\n--- [3/6] Validate Response ---")
    response_ok = (
        body.get("status") == "queued"
        and body.get("job_id") is not None
    )
    if runpod_triggered:
        print(f"  status='queued': OK")
        print(f"  RunPod dispatched: OK (job {runpod_job_id})")
    else:
        print(f"  status='queued': OK (job created in DB)")
        print(f"  RunPod NOT dispatched: {runpod_error}")
        print(f"  NOTE: Worker may not pick up this job automatically.")

    results["response"] = response_ok
    print_section(3, 6, "Validate Response", results["response"])

    # -- [4/6] Poll database for status changes --------------------------------
    print("\n--- [4/6] Poll Database Status ---")
    print(f"  Polling every {POLL_INTERVAL_SEC}s, timeout {POLL_TIMEOUT_SEC}s (5 min)")

    poll_start = time.time()
    poll_count = 0
    final_status = "queued"
    final_row = None
    seen_processing = False
    status_transitions = ["queued (t=0s)"]

    while True:
        elapsed = time.time() - poll_start
        if elapsed > POLL_TIMEOUT_SEC:
            print(f"\n  TIMEOUT after {elapsed:.0f}s ({poll_count} polls)")
            break

        time.sleep(POLL_INTERVAL_SEC)
        poll_count += 1

        try:
            qstatus, _, qbody = http_request(
                f"{REST_URL}?id=eq.{job_id}&select=*",
                headers={
                    "apikey": ANON_KEY,
                    "Authorization": f"Bearer {ANON_KEY}",
                },
            )
            if qstatus == 200 and isinstance(qbody, list) and len(qbody) > 0:
                row = qbody[0]
                current_status = row.get("status", "unknown")
                progress = row.get("progress", 0)
                stage = row.get("stage", "")

                if current_status != final_status:
                    transition_time = time.time() - poll_start
                    status_transitions.append(f"{current_status} (t={transition_time:.0f}s)")

                if current_status == "processing" and not seen_processing:
                    seen_processing = True
                    print(f"  [{ts()}] Poll #{poll_count}: STATUS CHANGED -> processing "
                          f"(progress={progress:.0%}, stage='{stage}')")
                    print(f"    *** Worker has started! ***")
                elif current_status != final_status:
                    print(f"  [{ts()}] Poll #{poll_count}: STATUS CHANGED -> {current_status} "
                          f"(progress={progress:.0%}, stage='{stage}')")
                else:
                    print(f"  [{ts()}] Poll #{poll_count}: {current_status} "
                          f"(progress={progress:.0%}, stage='{stage}')")

                final_status = current_status
                final_row = row

                if current_status in ("completed", "failed"):
                    break
            else:
                print(f"  [{ts()}] Poll #{poll_count}: query returned status={qstatus}")
        except Exception as e:
            print(f"  [{ts()}] Poll #{poll_count}: ERROR {e}")

    poll_duration = time.time() - poll_start

    print(f"\n  Status transitions: {' -> '.join(status_transitions)}")
    print(f"  Worker started (queued->processing): {'YES' if seen_processing else 'NO'}")
    print(f"  Poll duration: {poll_duration:.0f}s ({poll_count} polls)")

    db_ok = final_status in ("completed", "failed")
    results["database"] = db_ok
    print_section(4, 6, "Database State", results["database"])

    # -- [5/6] Analyze results or error ----------------------------------------
    print("\n--- [5/6] Analyze Results ---")

    if final_row is None:
        print("  No row data available.")
        results["results"] = False
    elif final_status == "completed":
        print("  STATUS: COMPLETED")
        print(f"  processing_time_ms: {final_row.get('processing_time_ms')}")
        print(f"  scale_confidence:   {final_row.get('scale_confidence')}")
        print(f"  validation_passed:  {final_row.get('validation_passed')}")
        print(f"  validation_issues:  {json.dumps(final_row.get('validation_issues', []))}")
        print(f"  floor_plan_png_url: {final_row.get('floor_plan_png_url')}")
        print(f"  measurements_json_url: {final_row.get('measurements_json_url')}")

        # Stage timings
        stage_timings = final_row.get("stage_timings", {})
        if stage_timings:
            print(f"\n  Stage Timings:")
            for stage_name, ms in stage_timings.items():
                if isinstance(ms, (int, float)):
                    print(f"    {stage_name:25s} {ms:>8.0f} ms")
                else:
                    print(f"    {stage_name:25s} {ms}")

        # Measurements data
        mdata = final_row.get("measurements_data", {})
        if mdata and isinstance(mdata, dict):
            objects = mdata.get("objects", [])
            cabinets = [o for o in objects if o.get("type") == "cabinet"]
            appliances = [o for o in objects if o.get("type") == "appliance"]
            print(f"\n  Detected Objects:")
            print(f"    Total:      {len(objects)}")
            print(f"    Cabinets:   {len(cabinets)}")
            print(f"    Appliances: {len(appliances)}")
            for obj in objects:
                dims = obj.get("dimensions", {})
                w = dims.get("width_inches", "?")
                h = dims.get("height_inches", "?")
                d = dims.get("depth_inches", "?")
                print(f"      - {obj.get('label', obj.get('type', '?'))}: "
                      f"{w}\"W x {h}\"H x {d}\"D "
                      f"(conf={obj.get('confidence', '?')})")
        else:
            print("\n  measurements_data: empty or null")

        results["results"] = True

    elif final_status == "failed":
        error_msg = final_row.get("error_message", "no error_message set")
        print(f"  STATUS: FAILED")
        print(f"  error_message: {error_msg}")
        print(f"  stage:         {final_row.get('stage')}")
        print(f"  progress:      {final_row.get('progress')}")
        print(f"  worker_id:     {final_row.get('worker_id')}")
        print(f"  started_at:    {final_row.get('started_at')}")
        print(f"  completed_at:  {final_row.get('completed_at')}")

        # Stage timings (partial)
        stage_timings = final_row.get("stage_timings", {})
        if stage_timings:
            print(f"\n  Stage Timings (partial):")
            for stage_name, ms in stage_timings.items():
                if isinstance(ms, (int, float)):
                    print(f"    {stage_name:25s} {ms:>8.0f} ms")
                else:
                    print(f"    {stage_name:25s} {ms}")

        if seen_processing:
            print("\n  DIAGNOSIS: Job transitioned queued -> processing -> failed.")
            print("  The RunPod worker DID start but the pipeline failed during execution.")
            print(f"  Failed at stage: {final_row.get('stage', 'unknown')}")
        else:
            print("\n  DIAGNOSIS: Job failed without ever reaching 'processing'.")
            print("  The worker may have crashed at startup or failed before updating status.")

        results["results"] = False

    else:
        # Timed out in queued/processing
        print(f"  STATUS: {final_status} (timed out waiting)")
        print(f"  stage:    {final_row.get('stage')}")
        print(f"  progress: {final_row.get('progress')}")
        if final_status == "processing":
            print("  NOTE: Pipeline is still running. Increase timeout to wait longer.")
        elif final_status == "queued":
            print("  NOTE: Worker never started. Check RunPod deployment and logs.")
            if not runpod_triggered:
                print(f"  ROOT CAUSE: RunPod was never triggered. Error: {runpod_error}")
        results["results"] = False

    print_section(5, 6, "Results", results["results"])

    # -- [6/6] Artifact checks (only if completed) -----------------------------
    print("\n--- [6/6] Artifact Validation ---")

    if final_status == "completed" and final_row:
        fp_url = final_row.get("floor_plan_png_url")
        mj_url = final_row.get("measurements_json_url")
        artifact_ok = True

        if fp_url:
            try:
                areq = urllib.request.Request(fp_url, method="HEAD")
                aresp = urllib.request.urlopen(areq, timeout=10)
                cl = aresp.headers.get("Content-Length", "0")
                print(f"  Floor plan PNG: accessible, size={cl} bytes")
            except Exception as e:
                print(f"  Floor plan PNG: NOT accessible ({e})")
                artifact_ok = False
        else:
            print("  Floor plan PNG URL: missing")
            artifact_ok = False

        if mj_url:
            try:
                areq = urllib.request.Request(mj_url, method="HEAD")
                aresp = urllib.request.urlopen(areq, timeout=10)
                cl = aresp.headers.get("Content-Length", "0")
                print(f"  Measurements JSON: accessible, size={cl} bytes")
            except Exception as e:
                print(f"  Measurements JSON: NOT accessible ({e})")
                artifact_ok = False
        else:
            print("  Measurements JSON URL: missing")
            artifact_ok = False

        results["artifacts"] = artifact_ok
    else:
        print("  Skipped (job did not complete successfully)")
        results["artifacts"] = False

    print_section(6, 6, "Artifacts", results["artifacts"])

    # -- Summary ---------------------------------------------------------------
    total_duration = time.time() - overall_start
    all_passed = all(results.values())

    print("\n" + "=" * 70)
    print("  Pipeline Test Report Summary")
    print("=" * 70)
    print(f"  Timestamp:         {ts()}")
    print(f"  Environment:       QA (wnyrnpeabhxdqvcpofmb)")
    print(f"  Docker version:    v21")
    print(f"  Job ID:            {job_id}")
    print(f"  RunPod triggered:  {runpod_triggered}")
    print(f"  RunPod job ID:     {runpod_job_id}")
    print(f"  Status transitions:{' -> '.join(status_transitions)}")
    print(f"  Duration:          {total_duration:.0f}s")
    print()
    print(f"  [1/6] Pre-Flight:        {'PASS' if results.get('preflight') else 'FAIL'}")
    print(f"  [2/6] Trigger Job:       {'PASS' if results.get('trigger') else 'FAIL'}")
    print(f"  [3/6] Validate Response: {'PASS' if results.get('response') else 'FAIL'}")
    print(f"  [4/6] Database State:    {'PASS' if results.get('database') else 'FAIL'}")
    print(f"  [5/6] Results:           {'PASS' if results.get('results') else 'FAIL'}")
    print(f"  [6/6] Artifacts:         {'PASS' if results.get('artifacts') else 'FAIL'}")
    print()

    if all_passed:
        print("  Overall: PASS")
    else:
        print("  Overall: FAIL")
        if not results.get("database"):
            if final_status == "queued":
                print("\n  Diagnosis: Worker never picked up the job.")
                print("  - Check RunPod endpoint is deployed and active")
                print("  - Check RUNPOD_ENDPOINT_ID and RUNPOD_API_KEY in Edge Function secrets")
                print(f"  - RunPod triggered by Edge Function: {runpod_triggered}")
            elif final_status == "processing":
                print("\n  Diagnosis: Pipeline started but did not finish within 5 min timeout.")
                print("  - Re-run with longer timeout, or check RunPod logs for crash/OOM")
        elif final_status == "failed":
            print(f"\n  Diagnosis: Pipeline failed with error:")
            print(f"    {final_row.get('error_message', 'unknown') if final_row else 'unknown'}")

    print("=" * 70)
    sys.exit(0 if all_passed else 1)


if __name__ == "__main__":
    main()
