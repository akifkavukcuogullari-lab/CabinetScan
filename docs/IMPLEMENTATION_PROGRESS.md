# Server Pipeline V2 — Implementation Progress

> **Resume prompt:** *"Continue implementing server pipeline — check `docs/IMPLEMENTATION_PROGRESS.md` for status"*
>
> **Plan:** `.claude/plans/misty-drifting-jellyfish.md`
> **Design:** `docs/SERVER_PIPELINE_V2.md`
> **Branch:** `nonLidarFlow`

---

## Phase 0: Setup
- [x] 0.1 Create `pipeline-dev` custom agent (`.claude/agents/pipeline-dev.md`)
- [x] 0.2 Create progress tracking file (`docs/IMPLEMENTATION_PROGRESS.md`)

## Phase 1: iOS — ARKit Plane Detection & Capture Package
- [ ] 1.1 Enable ARKit plane detection in `AIARSessionManager.swift`
  - [ ] Change `planeDetection = []` → `[.horizontal, .vertical]`
  - [ ] Add `detectedPlanes` storage dictionary
  - [ ] Implement `session(_:didAdd:)` / `session(_:didUpdate:)` for plane anchors
  - [ ] Add `exportPlanesJSON()` method
  - [ ] Clear planes on stop/start
- [ ] 1.1-test: `AIARSessionManagerPlaneTests.swift`
- [ ] 1.2 Create `CapturePackageBuilder.swift`
  - [ ] `CapturePackage` struct (videoURL, posesData, planesData, metadata)
  - [ ] `CapturePackageMetadata` struct (Codable)
  - [ ] `build()` method using session manager exports
- [ ] 1.2-test: `CapturePackageBuilderTests.swift`
- [ ] 1.3 Update `AIFlowCoordinator` for package building
  - [ ] Add `packageBuilder` property
  - [ ] Add `buildCapturePackage(showroomId:)` method

## Phase 2: iOS — Server Pipeline Client & Upload Flow
- [ ] 2.1 Create `ServerPipelineClient.swift` (actor)
  - [ ] `submitJob()` — upload files + create job
  - [ ] `pollForResults()` — poll status + download results
  - [ ] `ServerPipelineResult` struct
  - [ ] Error handling + retry logic
- [ ] 2.1-test: `ServerPipelineClientTests.swift`
- [ ] 2.2 Create `ServerResultAdapter.swift`
  - [ ] Convert server JSON → `MeasurementData`
  - [ ] Map all fields (values in FEET)
  - [ ] Set `scanMethod = .aiFlow`
  - [ ] Populate `aiMetadata`
- [ ] 2.2-test: `ServerResultAdapterTests.swift`
- [ ] 2.3 Wire upload flow into `AIFlowCoordinator.processCapture()`
  - [ ] Build package → submit job → poll → convert results
  - [ ] Update `uploadStatus` at each stage
- [ ] 2.4 Update `ProcessingView.swift` for server pipeline states
  - [ ] Stage-specific messages from server
  - [ ] Error state with retry option
- [ ] 2.5 Wire processing into `AIFlowEntryPoint.swift`
  - [ ] Call `processCapture()` on `.processing` appear
  - [ ] On success: `appState.setMeasurementData(result)`
  - [ ] On error: show in ProcessingView
- [ ] 2.5-test: `AIFlowIntegrationTests.swift`

## Phase 3: Supabase — Database & Edge Functions
- [ ] 3.1 Create `processing_jobs` migration
  - [ ] Table schema with status, progress, results columns
  - [ ] Indexes on status + showroom_id
  - [ ] RLS policies (anon create/read, service_role update)
- [ ] 3.2 Create `create-processing-job` edge function
  - [ ] Validate input (video_url, showroom_id required)
  - [ ] Insert row with status = 'queued'
  - [ ] Trigger RunPod/Modal worker
- [ ] 3.2-test: `create-processing-job.test.ts`
- [ ] 3.3 Create `get-job-status` edge function
  - [ ] Query by job ID
  - [ ] Return status, progress, stage
- [ ] 3.3-test: `get-job-status.test.ts`
- [ ] 3.4 Create `get-job-results` edge function
  - [ ] Query completed job
  - [ ] Return measurements_data, floor_plan URL
- [ ] 3.4-test: `get-job-results.test.ts`
- [ ] 3.5 Create `update-job-status` edge function (service role)
  - [ ] Validate service role auth
  - [ ] Update progress, stage, results

## Phase 4: Server — Python Pipeline
- [ ] 4.0 Project setup (`server/` directory, requirements.txt, Dockerfile)
- [ ] 4.1 Stage 1: Frame Extraction (`frame_extraction.py`)
- [ ] 4.1-test: `test_frame_extraction.py`
- [ ] 4.2 Stage 2: Depth Estimation (`depth_estimation.py`) — Video Depth Anything
- [ ] 4.2-test: `test_depth_estimation.py`
- [ ] 4.3 Stage 3: Scale Calibration (`scale_calibration.py`)
- [ ] 4.3-test: `test_scale_calibration.py`
- [ ] 4.4 Stage 4: Wall Detection (`wall_detection.py`) — ARKit planes
- [ ] 4.4-test: `test_wall_detection.py`
- [ ] 4.5 Stage 5: Object Detection (`object_detection.py`) — SAM 3
- [ ] 4.5-test: `test_object_detection.py`
- [ ] 4.6 Stage 6: Snap to Standards (`snap_to_standards.py`)
- [ ] 4.6-test: `test_snap_to_standards.py`
- [ ] 4.7 Stage 7: Floor Plan Generation (`floor_plan_gen.py`)
- [ ] 4.7-test: `test_floor_plan_gen.py`
- [ ] 4.8 Stage 8: VLM Validation (`vlm_validation.py`)
- [ ] 4.8-test: `test_vlm_validation.py`
- [ ] 4.9 Pipeline Orchestrator (`orchestrator.py`)
- [ ] 4.9-test: `test_orchestrator.py`
- [ ] 4.10 RunPod Handler (`runpod_handler.py`)
- [ ] 4.11 Supabase utils (`utils/supabase_client.py`)

## Phase 5: End-to-End Integration & Testing
- [ ] 5.1 iOS integration test (mock server responses)
- [ ] 5.2 Supabase integration test (job lifecycle)
- [ ] 5.3 Full E2E test (manual — device to dashboard)
- [ ] 5.4 LiDAR flow regression test

---

## Commit Log
| Task | Commit | Date |
|------|--------|------|
| 0.1 + 0.2 | *pending* | |
