//
//  ServerPipelineClient.swift
//  cabinetscan
//
//  Phase 2.1: Server pipeline client for uploading capture packages and polling job results.
//  Server Pipeline V2
//

import Foundation

// MARK: - Server Pipeline Error

enum ServerPipelineError: LocalizedError {
    case uploadFailed(String)
    case jobCreationFailed(String)
    case pollingTimeout
    case jobFailed(String)
    case resultsFetchFailed(String)
    case invalidResponse
    case cancelled

    var errorDescription: String? {
        switch self {
        case .uploadFailed(let reason):
            return "Failed to upload capture data: \(reason)"
        case .jobCreationFailed(let reason):
            return "Failed to create processing job: \(reason)"
        case .pollingTimeout:
            return "Processing is taking longer than expected. Please try again."
        case .jobFailed(let reason):
            return "Server processing failed: \(reason)"
        case .resultsFetchFailed(let reason):
            return "Failed to retrieve results: \(reason)"
        case .invalidResponse:
            return "Received invalid response from server"
        case .cancelled:
            return "Processing was cancelled"
        }
    }
}

// MARK: - Server Job Status

struct ServerJobStatus {
    let jobId: String
    let status: Status
    let progress: Double
    let stage: String?
    let errorMessage: String?

    enum Status: String {
        case queued
        case processing
        case completed
        case failed
    }
}

// MARK: - Server Pipeline Result

struct ServerPipelineResult {
    /// Raw measurements data from server (MeasurementData-compatible JSON)
    let measurementsData: [String: Any]

    /// URL to floor plan PNG in Supabase storage
    let floorPlanURL: String?

    /// Whether VLM validation passed
    let validationPassed: Bool

    /// VLM validation issues (if any)
    let validationIssues: [String]

    /// Total processing time in milliseconds
    let processingTimeMs: Int

    /// Scale confidence level from server
    let scaleConfidence: String?

    /// Pipeline version used
    let pipelineVersion: String?
}

// MARK: - Server Pipeline Client

/// Handles uploading capture packages to Supabase storage and managing server processing jobs.
///
/// Flow:
/// 1. Upload video, poses, planes, photos to Supabase storage
/// 2. Call `create-processing-job` edge function
/// 3. Poll `get-job-status` until completed/failed
/// 4. Fetch results from `get-job-results`
///
/// Usage:
/// ```swift
/// let client = ServerPipelineClient()
/// let jobId = try await client.submitJob(package: package, showroomCode: "DEMO")
/// let result = try await client.pollForResults(jobId: jobId) { progress, stage in
///     print("Progress: \(progress), Stage: \(stage)")
/// }
/// ```
actor ServerPipelineClient {

    // MARK: - Constants

    private enum Constants {
        /// Polling interval in seconds
        static let pollIntervalSeconds: Double = 2.0
        /// Maximum polling attempts (5 minutes at 2s intervals = 150)
        static let maxPollAttempts = 150
        /// Maximum retry attempts for transient errors
        static let maxRetries = 3
        /// Storage bucket name
        static let storageBucket = "scans"
    }

    // MARK: - Dependencies

    private let uploader: AIFlowUploader

    // MARK: - State

    private var isCancelled = false

    // MARK: - Initialization

    init(uploader: AIFlowUploader = AIFlowUploader()) {
        self.uploader = uploader
    }

    // MARK: - Cancel

    /// Cancel any in-progress polling
    func cancel() {
        isCancelled = true
    }

    /// Reset cancellation state for new submissions
    private func resetCancellation() {
        isCancelled = false
    }

    // MARK: - Submit Job

    /// Upload capture package files and create a server processing job.
    ///
    /// Upload order:
    /// 1. Video (largest file, via AIFlowUploader with compression)
    /// 2. Photos (via AIFlowUploader)
    /// 3. Poses JSON
    /// 4. Planes JSON
    /// 5. Create processing job
    ///
    /// - Parameters:
    ///   - package: The capture package to upload
    ///   - showroomCode: Showroom code for storage paths
    ///   - showroomId: Showroom UUID for job context
    ///   - onProgress: Progress callback (stage message)
    /// - Returns: Job ID from server
    func submitJob(
        package: CapturePackage,
        showroomCode: String,
        showroomId: String,
        onProgress: @MainActor @Sendable (String) -> Void
    ) async throws -> String {
        resetCancellation()

        let captureId = UUID().uuidString

        // 1. Upload video
        await onProgress("Uploading video...")
        let videoData = try await uploader.uploadVideo(
            from: package.videoURL,
            showroomCode: showroomCode
        )

        try checkCancellation()

        // 2. Upload photos
        var photoURLs: [String] = []
        if !package.photos.isEmpty {
            await onProgress("Uploading photos...")
            photoURLs = try await uploader.uploadPhotos(
                package.photos,
                showroomCode: showroomCode
            )
        }

        try checkCancellation()

        // 3. Upload poses JSON
        await onProgress("Uploading pose data...")
        let posesPath = "\(showroomCode.lowercased())/ai_capture_\(captureId)/poses.json"
        let posesURL = try await APIService.shared.uploadFile(
            bucket: Constants.storageBucket,
            path: posesPath,
            data: package.posesData,
            contentType: "application/json"
        )

        try checkCancellation()

        // 4. Upload planes JSON
        await onProgress("Uploading plane data...")
        let planesPath = "\(showroomCode.lowercased())/ai_capture_\(captureId)/planes.json"
        let planesURL = try await APIService.shared.uploadFile(
            bucket: Constants.storageBucket,
            path: planesPath,
            data: package.planesData,
            contentType: "application/json"
        )

        try checkCancellation()

        // 5. Create processing job
        await onProgress("Starting server processing...")
        let jobId = try await createProcessingJob(
            videoURL: videoData.videoUrl,
            posesURL: posesURL,
            planesURL: planesURL,
            photoURLs: photoURLs,
            showroomId: showroomId,
            metadata: package.metadata,
            videoData: videoData
        )

        print("[ServerPipelineClient] Job created: \(jobId)")
        return jobId
    }

    // MARK: - Poll for Results

    /// Poll the server for job completion and return results.
    ///
    /// - Parameters:
    ///   - jobId: The job ID to poll
    ///   - onProgress: Progress callback with (progress 0-1, stage description)
    /// - Returns: Server pipeline result
    func pollForResults(
        jobId: String,
        onProgress: @MainActor @Sendable (Double, String) -> Void
    ) async throws -> ServerPipelineResult {
        var attempts = 0

        while attempts < Constants.maxPollAttempts {
            try checkCancellation()

            let status = try await getJobStatus(jobId: jobId)

            await onProgress(status.progress, status.stage ?? "Processing...")

            switch status.status {
            case .completed:
                print("[ServerPipelineClient] Job completed after \(attempts) polls")
                return try await getJobResults(jobId: jobId)

            case .failed:
                let message = status.errorMessage ?? "Unknown error"
                print("[ServerPipelineClient] Job failed: \(message)")
                throw ServerPipelineError.jobFailed(message)

            case .queued, .processing:
                attempts += 1
                try await Task.sleep(nanoseconds: UInt64(Constants.pollIntervalSeconds * 1_000_000_000))
            }
        }

        print("[ServerPipelineClient] Polling timeout after \(attempts) attempts")
        throw ServerPipelineError.pollingTimeout
    }

    // MARK: - Edge Function Calls

    /// Call `create-processing-job` edge function.
    private func createProcessingJob(
        videoURL: String,
        posesURL: String,
        planesURL: String,
        photoURLs: [String],
        showroomId: String,
        metadata: CapturePackageMetadata,
        videoData: AIUploadedVideoData
    ) async throws -> String {
        let body: [String: Any] = [
            "video_url": videoURL,
            "poses_url": posesURL,
            "planes_url": planesURL,
            "photo_urls": photoURLs,
            "showroom_id": showroomId,
            "metadata": [
                "device_model": metadata.deviceModel,
                "os_version": metadata.osVersion,
                "video_duration": metadata.videoDuration,
                "frame_count": metadata.frameCount,
                "photo_count": metadata.photoCount,
                "has_lidar": metadata.hasLiDAR,
                "plane_count": metadata.planeCount,
                "video_resolution": videoData.resolution,
                "video_size_bytes": videoData.sizeBytes
            ]
        ]

        let responseData = try await callEdgeFunction(
            name: "create-processing-job",
            method: "POST",
            body: body
        )

        guard let json = try? JSONSerialization.jsonObject(with: responseData) as? [String: Any],
              let jobId = json["job_id"] as? String else {
            throw ServerPipelineError.jobCreationFailed("Invalid response from server")
        }

        return jobId
    }

    /// Call `get-job-status` edge function.
    private func getJobStatus(jobId: String) async throws -> ServerJobStatus {
        let responseData = try await callEdgeFunction(
            name: "get-job-status",
            method: "GET",
            queryParams: ["job_id": jobId]
        )

        guard let json = try? JSONSerialization.jsonObject(with: responseData) as? [String: Any],
              let statusString = json["status"] as? String,
              let status = ServerJobStatus.Status(rawValue: statusString) else {
            throw ServerPipelineError.invalidResponse
        }

        return ServerJobStatus(
            jobId: jobId,
            status: status,
            progress: json["progress"] as? Double ?? 0,
            stage: json["stage"] as? String,
            errorMessage: json["error_message"] as? String
        )
    }

    /// Call `get-job-results` edge function.
    private func getJobResults(jobId: String) async throws -> ServerPipelineResult {
        let responseData = try await callEdgeFunction(
            name: "get-job-results",
            method: "GET",
            queryParams: ["job_id": jobId]
        )

        guard let json = try? JSONSerialization.jsonObject(with: responseData) as? [String: Any] else {
            throw ServerPipelineError.resultsFetchFailed("Invalid JSON response")
        }

        guard let measurementsData = json["measurements_data"] as? [String: Any] else {
            throw ServerPipelineError.resultsFetchFailed("Missing measurements data")
        }

        return ServerPipelineResult(
            measurementsData: measurementsData,
            floorPlanURL: json["floor_plan_png_url"] as? String,
            validationPassed: json["validation_passed"] as? Bool ?? false,
            validationIssues: json["validation_issues"] as? [String] ?? [],
            processingTimeMs: json["processing_time_ms"] as? Int ?? 0,
            scaleConfidence: json["scale_confidence"] as? String,
            pipelineVersion: json["pipeline_version"] as? String
        )
    }

    // MARK: - HTTP Helpers

    /// Call a Supabase edge function with retry logic.
    private func callEdgeFunction(
        name: String,
        method: String,
        body: [String: Any]? = nil,
        queryParams: [String: String]? = nil
    ) async throws -> Data {
        let baseURL = Config.supabaseURL
        let anonKey = Config.supabaseAnonKey

        var urlString = "\(baseURL)/functions/v1/\(name)"

        // Add query parameters for GET requests
        if let queryParams = queryParams, !queryParams.isEmpty {
            let queryString = queryParams.map { "\($0.key)=\($0.value)" }.joined(separator: "&")
            urlString += "?\(queryString)"
        }

        guard let url = URL(string: urlString) else {
            throw ServerPipelineError.invalidResponse
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Bearer \(anonKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 30

        if let body = body {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }

        // Retry logic
        var lastError: Error?
        for attempt in 1...Constants.maxRetries {
            do {
                let (data, response) = try await URLSession.shared.data(for: request)

                guard let httpResponse = response as? HTTPURLResponse else {
                    throw ServerPipelineError.invalidResponse
                }

                switch httpResponse.statusCode {
                case 200, 201:
                    return data
                case 404:
                    throw ServerPipelineError.resultsFetchFailed("Job not found")
                default:
                    let errorMessage = parseErrorMessage(from: data) ?? "Server error (code: \(httpResponse.statusCode))"
                    if method == "POST" {
                        throw ServerPipelineError.jobCreationFailed(errorMessage)
                    } else {
                        throw ServerPipelineError.resultsFetchFailed(errorMessage)
                    }
                }
            } catch let error as URLError {
                lastError = error
                let retryable: [URLError.Code] = [
                    .networkConnectionLost, .timedOut, .cannotConnectToHost,
                    .notConnectedToInternet, .cannotFindHost
                ]
                if retryable.contains(error.code) && attempt < Constants.maxRetries {
                    let delay = pow(2.0, Double(attempt))
                    print("[ServerPipelineClient] Retry \(attempt)/\(Constants.maxRetries) in \(Int(delay))s for \(name)")
                    try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                    continue
                }
                throw ServerPipelineError.uploadFailed(error.localizedDescription)
            } catch {
                throw error
            }
        }

        throw lastError ?? ServerPipelineError.invalidResponse
    }

    /// Parse error message from edge function error response.
    private func parseErrorMessage(from data: Data) -> String? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return json["error"] as? String ?? json["message"] as? String
    }

    /// Check if the client has been cancelled.
    private func checkCancellation() throws {
        if isCancelled {
            throw ServerPipelineError.cancelled
        }
    }
}
