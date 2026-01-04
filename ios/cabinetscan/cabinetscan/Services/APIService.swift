import Foundation

// MARK: - API Service
actor APIService {
    static let shared = APIService()

    private let baseURL: String
    private let anonKey: String
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder

    private init() {
        // Load from Config which reads from Info.plist
        self.baseURL = Config.supabaseURL
        self.anonKey = Config.supabaseAnonKey

        self.decoder = JSONDecoder()
        self.encoder = JSONEncoder()
    }

    // MARK: - Configuration

    func configure(baseURL: String, anonKey: String) -> APIService {
        // Note: In production, use a proper configuration approach
        return self
    }

    // MARK: - Fetch Showroom Config

    func fetchShowroomConfig(code: String) async throws -> ShowroomConfig {
        let urlString = "\(baseURL)/functions/v1/get-showroom-config?code=\(code.uppercased())"
        
        Config.logInfo("🌐 Fetching showroom config from: \(urlString)")

        guard let url = URL(string: urlString) else {
            Config.logError("❌ Invalid URL: \(urlString)")
            throw APIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(anonKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 10 // 10 second timeout

        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                Config.logError("❌ Invalid response type")
                throw APIError.invalidResponse
            }
            
            Config.logInfo("📡 Response status: \(httpResponse.statusCode)")

            switch httpResponse.statusCode {
            case 200:
                return try decoder.decode(ShowroomConfig.self, from: data)
            case 404:
                throw APIError.showroomNotFound
            case 400:
                throw APIError.invalidRequest
            default:
                throw APIError.serverError(statusCode: httpResponse.statusCode)
            }
        } catch let error as URLError {
            Config.logError("❌ Network error: \(error.localizedDescription)")
            
            // Provide more specific error messages
            if error.code == .cannotConnectToHost || error.code == .notConnectedToInternet {
                throw APIError.connectionFailed
            } else if error.code == .timedOut {
                throw APIError.timeout
            }
            throw error
        }
    }

    // MARK: - Submit Project

    func submitProject(_ submission: ProjectSubmission) async throws -> SubmissionResponse {
        let urlString = "\(baseURL)/functions/v1/submit-project"

        guard let url = URL(string: urlString) else {
            throw APIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(anonKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 60 // 60 second timeout for submission

        // Encode the submission - catch encoding errors for better debugging
        do {
            request.httpBody = try encoder.encode(submission)
        } catch {
            Config.logError("❌ Failed to encode submission: \(error.localizedDescription)")
            throw APIError.submissionFailed(message: "Failed to prepare submission data. Please try scanning again.")
        }

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        // Handle error status codes first
        if httpResponse.statusCode != 201 {
            // Try to parse error response
            if let errorResponse = try? decoder.decode(APIErrorResponse.self, from: data) {
                // Use customer-friendly message if available (for plan limit errors)
                if let customerMessage = errorResponse.customerMessage {
                    throw APIError.submissionFailed(message: customerMessage)
                }
                // Otherwise use the message or error field
                let errorMessage = errorResponse.message ?? errorResponse.error ?? "Server error (code: \(httpResponse.statusCode))"
                throw APIError.submissionFailed(message: errorMessage)
            }

            // Log raw response for debugging
            if let errorString = String(data: data, encoding: .utf8) {
                Config.logError("❌ Raw error response: \(errorString)")
            }
            throw APIError.submissionFailed(message: "Server error (code: \(httpResponse.statusCode)). Please try again.")
        }

        // Try to decode success response
        do {
            let submissionResponse = try decoder.decode(SubmissionResponse.self, from: data)
            return submissionResponse
        } catch let decodingError as DecodingError {
            Config.logError("❌ Failed to decode response: \(decodingError)")
            if let errorString = String(data: data, encoding: .utf8) {
                Config.logError("❌ Raw response: \(errorString)")
            }
            throw APIError.submissionFailed(message: "Server returned an unexpected response. Please try again.")
        }
    }

    // MARK: - Upload File to Storage

    func uploadFile(bucket: String, path: String, data: Data, contentType: String) async throws -> String {
        let urlString = "\(baseURL)/storage/v1/object/\(bucket)/\(path)"

        guard let url = URL(string: urlString) else {
            throw APIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(anonKey)", forHTTPHeaderField: "Authorization")
        request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        request.httpBody = data
        // CRITICAL: Set longer timeout for large file uploads (3 minutes)
        request.timeoutInterval = 180

        // Use custom session with longer timeout to prevent network timeouts
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 180  // 3 minutes per request
        config.timeoutIntervalForResource = 300  // 5 minutes total
        let session = URLSession(configuration: config)

        let (responseData, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            print("❌ [APIService] Upload failed with status: \((response as? HTTPURLResponse)?.statusCode ?? -1)")
            throw APIError.uploadFailed
        }

        // Return the public URL
        return "\(baseURL)/storage/v1/object/public/\(bucket)/\(path)"
    }
}

// MARK: - API Errors

enum APIError: LocalizedError {
    case invalidURL
    case invalidResponse
    case invalidRequest
    case showroomNotFound
    case serverError(statusCode: Int)
    case submissionFailed(message: String)
    case uploadFailed
    case decodingError
    case connectionFailed
    case timeout

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid URL configuration"
        case .invalidResponse:
            return "Invalid server response"
        case .invalidRequest:
            return "Invalid request"
        case .showroomNotFound:
            return "Showroom not found. Please check the code and try again."
        case .serverError(let statusCode):
            return "Server error (code: \(statusCode))"
        case .submissionFailed(let message):
            return "Submission failed: \(message)"
        case .uploadFailed:
            return "Failed to upload file"
        case .decodingError:
            return "Failed to process server response"
        case .connectionFailed:
            return "Could not connect to the server. Please check:\n• Your internet connection\n• Supabase configuration in Info.plist\n• If using local server, use your computer's IP address instead of 127.0.0.1"
        case .timeout:
            return "Connection timed out. Please check your internet connection and try again."
        }
    }
}
