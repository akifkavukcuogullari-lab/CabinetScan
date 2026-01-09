import Foundation

// MARK: - Chat Service
actor ChatService {
    static let shared = ChatService()

    private let baseURL: String
    private let anonKey: String
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder

    private init() {
        self.baseURL = Config.supabaseURL
        self.anonKey = Config.supabaseAnonKey
        self.decoder = JSONDecoder()
        self.encoder = JSONEncoder()
    }

    // MARK: - Start Chat Conversation

    /// Starts a new chat conversation for a project
    /// - Parameters:
    ///   - projectId: The project ID
    ///   - referenceNumber: The project reference number
    /// - Returns: StartChatResponse with conversation ID and greeting
    func startConversation(projectId: String, referenceNumber: String) async throws -> StartChatResponse {
        let urlString = "\(baseURL)/functions/v1/ai-chat-start"

        guard let url = URL(string: urlString) else {
            throw ChatError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(anonKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 30 // 30 second timeout for AI response

        let body: [String: String] = [
            "project_id": projectId,
            "reference_number": referenceNumber
        ]

        request.httpBody = try encoder.encode(body)

        Config.logInfo("Starting chat conversation for project: \(projectId)")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw ChatError.invalidResponse
            }

            Config.logInfo("Start chat response status: \(httpResponse.statusCode)")

            switch httpResponse.statusCode {
            case 200:
                return try decoder.decode(StartChatResponse.self, from: data)
            case 400:
                if let errorResponse = try? JSONDecoder().decode([String: String].self, from: data),
                   let errorMessage = errorResponse["error"] {
                    throw ChatError.apiError(errorMessage)
                }
                throw ChatError.invalidRequest
            case 404:
                throw ChatError.projectNotFound
            case 403:
                // Check if conversation is completed
                if let errorResponse = try? JSONDecoder().decode([String: Bool].self, from: data),
                   errorResponse["completed"] == true {
                    throw ChatError.conversationCompleted
                }
                throw ChatError.chatNotAvailable
            default:
                throw ChatError.serverError(statusCode: httpResponse.statusCode)
            }
        } catch let error as URLError {
            Config.logError("Chat network error: \(error.localizedDescription)")
            if error.code == .notConnectedToInternet {
                throw ChatError.noConnection
            } else if error.code == .timedOut {
                throw ChatError.timeout
            }
            throw error
        }
    }

    // MARK: - Send Message

    /// Sends a message to an existing conversation
    /// - Parameters:
    ///   - conversationId: The conversation ID
    ///   - message: The user's message
    /// - Returns: SendMessageResponse with AI response
    func sendMessage(conversationId: String, message: String) async throws -> SendMessageResponse {
        let urlString = "\(baseURL)/functions/v1/ai-chat-message"

        guard let url = URL(string: urlString) else {
            throw ChatError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(anonKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 60 // 60 second timeout for AI response

        let body: [String: String] = [
            "conversation_id": conversationId,
            "message": message
        ]

        request.httpBody = try encoder.encode(body)

        Config.logInfo("Sending message to conversation: \(conversationId)")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw ChatError.invalidResponse
            }

            Config.logInfo("Send message response status: \(httpResponse.statusCode)")

            switch httpResponse.statusCode {
            case 200:
                return try decoder.decode(SendMessageResponse.self, from: data)
            case 400:
                if let errorResponse = try? JSONDecoder().decode([String: String].self, from: data),
                   let errorMessage = errorResponse["error"] {
                    throw ChatError.apiError(errorMessage)
                }
                throw ChatError.invalidRequest
            case 404:
                throw ChatError.conversationNotFound
            default:
                throw ChatError.serverError(statusCode: httpResponse.statusCode)
            }
        } catch let error as URLError {
            Config.logError("Chat network error: \(error.localizedDescription)")
            if error.code == .notConnectedToInternet {
                throw ChatError.noConnection
            } else if error.code == .timedOut {
                throw ChatError.timeout
            }
            throw error
        }
    }

    // MARK: - Complete Conversation

    /// Completes a conversation and generates a summary
    /// - Parameter conversationId: The conversation ID
    func completeConversation(conversationId: String) async throws {
        let urlString = "\(baseURL)/functions/v1/ai-chat-complete"

        guard let url = URL(string: urlString) else {
            throw ChatError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(anonKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 30

        let body: [String: String] = [
            "conversation_id": conversationId
        ]

        request.httpBody = try encoder.encode(body)

        Config.logInfo("Completing conversation: \(conversationId)")

        do {
            let (_, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw ChatError.invalidResponse
            }

            Config.logInfo("Complete conversation response status: \(httpResponse.statusCode)")

            if httpResponse.statusCode != 200 {
                throw ChatError.serverError(statusCode: httpResponse.statusCode)
            }
        } catch let error as URLError {
            Config.logError("Chat network error: \(error.localizedDescription)")
            // Don't throw - completing is best-effort
        }
    }
}

// MARK: - Chat Errors

enum ChatError: LocalizedError {
    case invalidURL
    case invalidResponse
    case invalidRequest
    case projectNotFound
    case conversationNotFound
    case chatNotAvailable
    case conversationCompleted
    case noConnection
    case timeout
    case serverError(statusCode: Int)
    case apiError(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid chat service URL"
        case .invalidResponse:
            return "Invalid response from chat service"
        case .invalidRequest:
            return "Invalid request"
        case .projectNotFound:
            return "Project not found"
        case .conversationNotFound:
            return "Conversation not found"
        case .chatNotAvailable:
            return "Chat is not available for this showroom"
        case .conversationCompleted:
            return "This chat conversation has already been completed"
        case .noConnection:
            return "No internet connection. Please check your connection and try again."
        case .timeout:
            return "The request timed out. Please try again."
        case .serverError(let statusCode):
            return "Server error (status \(statusCode)). Please try again later."
        case .apiError(let message):
            return message
        }
    }
}
