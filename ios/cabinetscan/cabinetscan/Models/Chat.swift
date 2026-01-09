import Foundation

// MARK: - Chat Conversation
struct ChatConversation: Codable {
    let id: String
    let threadId: String
    let greeting: String
    let assistantName: String

    enum CodingKeys: String, CodingKey {
        case id
        case threadId = "thread_id"
        case greeting
        case assistantName = "assistant_name"
    }
}

// MARK: - Chat Message
struct ChatMessage: Identifiable, Codable, Equatable {
    let id: String
    let role: MessageRole
    let content: String
    let createdAt: Date

    enum MessageRole: String, Codable {
        case user
        case assistant
    }

    enum CodingKeys: String, CodingKey {
        case id, role, content
        case createdAt = "created_at"
    }

    // Local message init (for UI before server response)
    init(id: String = UUID().uuidString, role: MessageRole, content: String, createdAt: Date = Date()) {
        self.id = id
        self.role = role
        self.content = content
        self.createdAt = createdAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        role = try container.decode(MessageRole.self, forKey: .role)
        content = try container.decode(String.self, forKey: .content)

        // Handle date decoding
        if let dateString = try? container.decode(String.self, forKey: .createdAt) {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = formatter.date(from: dateString) {
                createdAt = date
            } else {
                // Try without fractional seconds
                formatter.formatOptions = [.withInternetDateTime]
                createdAt = formatter.date(from: dateString) ?? Date()
            }
        } else {
            createdAt = Date()
        }
    }
}

// MARK: - API Responses
struct StartChatResponse: Codable {
    let conversationId: String
    let threadId: String
    let greeting: String
    let assistantName: String

    enum CodingKeys: String, CodingKey {
        case conversationId = "conversation_id"
        case threadId = "thread_id"
        case greeting
        case assistantName = "assistant_name"
    }
}

struct SendMessageResponse: Codable {
    let messageId: String
    let content: String

    enum CodingKeys: String, CodingKey {
        case messageId = "message_id"
        case content
    }
}
