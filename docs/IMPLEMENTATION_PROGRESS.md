# Server Pipeline V2 — Implementation Progress

> **Resume prompt:** *"Continue implementing server pipeline — check `docs/IMPLEMENTATION_PROGRESS.md` for status"*
>
> **Plan:** `.claude/plans/misty-drifting-jellyfish.md`
> **Design:** `docs/SERVER_PIPELINE_V2.md`
> **Branch:** `nonLidarFlow`

---

## Phase 0: Setup
- [x] 0.1 Create `pipeline-dev` custom agent (`.claude/agents/pipeline-dev.md`) _(84567d5)_
- [x] 0.2 Create progress tracking file (`docs/IMPLEMENTATION_PROGRESS.md`) _(84567d5)_

## Phase 1: iOS — ARKit Plane Detection & Capture Package
- [x] 1.1 Enable ARKit plane detection in `AIARSessionManager.swift` _(aae7137)_
  - [x] Change `planeDetection = []` → `[.horizontal, .vertical]`
  - [x] Add `detectedPlanes` storage dictionary
  - [x] Implement `session(_:didAdd:)` / `session(_:didUpdate:)` for plane anchors
  - [x] Add `exportPlanesJSON()` method
  - [x] Clear planes on stop/start
- [x] 1.1-test: `AIARSessionManagerPlaneTests.swift`
- [x] 1.2 Create `CapturePackageBuilder.swift`
  - [x] `CapturePackage` struct (videoURL, posesData, planesData, metadata)
  - [x] `CapturePackageMetadata` struct (Codable)
  - [x] `build()` method using session manager exports
- [x] 1.2-test: `CapturePackageBuilderTests.swift`
- [x] 1.3 Update `AIFlowCoordinator` for package building
  - [x] Add `packageBuilder` property
  - [x] Add `buildCapturePackage(showroomId:)` method

## Phase 2: iOS — Server Pipeline Client & Upload Flow
- [x] 2.1 Create `ServerPipelineClient.swift` (actor)
  - [x] `submitJob()` — upload files + create job
  - [x] `pollForResults()` — poll status + download results
  - [x] `ServerPipelineResult` struct
  - [x] Error handling + retry logic
- [x] 2.1-test: `ServerPipelineClientTests.swift`
- [x] 2.2 Create `ServerResultAdapter.swift`
  - [x] Convert server JSON → `MeasurementData`
  - [x] Map all fields (values in FEET)
  - [x] Set `scanMethod = .aiFlow`
  - [x] Populate `aiMetadata`
- [x] 2.2-test: `ServerResultAdapterTests.swift`
- [x] 2.3 Wire upload flow into `AIFlowCoordinator.processCapture()`
  - [x] Build package → submit job → poll → convert results
  - [x] Update `uploadStatus` at each stage
- [x] 2.4 Update `ProcessingView.swift` for server pipeline states
  - [x] Stage-specific messages from server
  - [x] Error state with retry option
- [x] 2.5 Wire processing into `AIFlowEntryPoint.swift`
  - [x] Call `processCapture()` on `.processing` appear
  - [x] On success: `appState.setMeasurementData(result)`
  - [x] On error: show in ProcessingView
- [ ] 2.5-test: `AIFlowIntegrationTests.swift`

## Phase 3: Supabase — Database & Edge Functions
- [x] 3.1 Create `processing_jobs` migration
  - [x] Table schema with status, progress, results columns
  - [x] Indexes on status + showroom_id
  - [x] RLS policies (anon create/read, service_role update)
- [x] 3.2 Create `create-processing-job` edge function
  - [x] Validate input (video_url, showroom_id required)
  - [x] Insert row with status = 'queued'
  - [ ] Trigger RunPod/Modal worker (TODO placeholder)
- [ ] 3.2-test: `create-processing-job.test.ts`
- [x] 3.3 Create `get-job-status` edge function
  - [x] Query by job ID
  - [x] Return status, progress, stage
- [ ] 3.3-test: `get-job-status.test.ts`
- [x] 3.4 Create `get-job-results` edge function
  - [x] Query completed job
  - [x] Return measurements_data, floor_plan URL
- [ ] 3.4-test: `get-job-results.test.ts`
- [x] 3.5 Create `update-job-status` edge function (service role)
  - [x] Validate service role auth
  - [x] Update progress, stage, results

## Phase 4: Server — Python Pipeline
- [x] 4.0 Project setup (`server/` directory, requirements.txt, Dockerfile)
- [x] 4.1 Stage 1: Frame Extraction (`frame_extraction.py`)
- [x] 4.1-test: `test_frame_extraction.py`
- [x] 4.2 Stage 2: Depth Estimation (`depth_estimation.py`) — Video Depth Anything
- [ ] 4.2-test: `test_depth_estimation.py`
- [x] 4.3 Stage 3: Scale Calibration (`scale_calibration.py`)
- [x] 4.3-test: `test_scale_calibration.py`
- [x] 4.4 Stage 4: Wall Detection (`wall_detection.py`) — ARKit planes
- [x] 4.4-test: `test_wall_detection.py`
- [x] 4.5 Stage 5: Object Detection (`object_detection.py`) — SAM 3
- [ ] 4.5-test: `test_object_detection.py`
- [x] 4.6 Stage 6: Snap to Standards (`snap_to_standards.py`)
- [x] 4.6-test: `test_snap_to_standards.py`
- [x] 4.7 Stage 7: Floor Plan Generation (`floor_plan_gen.py`)
- [x] 4.7-test: `test_floor_plan_gen.py`
- [x] 4.8 Stage 8: VLM Validation (`vlm_validation.py`)
- [x] 4.8-test: `test_vlm_validation.py`
- [x] 4.9 Pipeline Orchestrator (`orchestrator.py`)
- [x] 4.9-test: `test_orchestrator.py`
- [x] 4.10 RunPod Handler (`runpod_handler.py`)
- [x] 4.11 Supabase utils (`utils/supabase_client.py`)

## Phase 5: End-to-End Integration & Testing
- [ ] 5.1 iOS integration test (mock server responses)
- [ ] 5.2 Supabase integration test (job lifecycle)
- [ ] 5.3 Full E2E test (manual — device to dashboard)
- [ ] 5.4 LiDAR flow regression test

---

## Commit Log
| Task | Commit | Date |
|------|--------|------|
| 0.1 + 0.2 | 84567d5 | 2026-02-06 |
| 1.1 | aae7137 | 2026-02-06 |
| 1.1-test + 1.2 + 1.2-test | 19900ed | 2026-02-06 |
| 1.3 | 52c42c5 | 2026-02-06 |
| 2.1–2.5 | 46b86c3 | 2026-02-06 |
| 3.1–3.5 | 2fe07b0 | 2026-02-06 |
| 4.0–4.11 | 93e0947 | 2026-02-06 |
| 2.1-test, 2.2-test, 4.1-test, 4.3–4.9-test | 00575cc | 2026-02-06 |
