import Foundation
import SwiftUI
import Combine

@MainActor
class ChatViewModel: ObservableObject {
    // MARK: - Published Properties
    @Published var messages: [ChatMessage] = []
    @Published var isLoading = false
    @Published var isTyping = false
    @Published var error: String?
    @Published var conversationStarted = false
    @Published var conversationCompleted = false
    @Published var conversationAlreadyCompleted = false  // Set when trying to open a completed conversation

    // MARK: - Private Properties
    private var conversationId: String?
    private let projectId: String
    private let referenceNumber: String
    let assistantName: String
    let assistantAvatarUrl: String?

    // MARK: - Initialization
    init(projectId: String, referenceNumber: String, assistantName: String, assistantAvatarUrl: String?) {
        self.projectId = projectId
        self.referenceNumber = referenceNumber
        self.assistantName = assistantName
        self.assistantAvatarUrl = assistantAvatarUrl
    }

    // MARK: - Start Conversation
    func startConversation() async {
        guard !conversationStarted else { return }

        isLoading = true
        error = nil

        do {
            let response = try await ChatService.shared.startConversation(
                projectId: projectId,
                referenceNumber: referenceNumber
            )

            conversationId = response.conversationId

            // Add greeting as first message
            let greetingMessage = ChatMessage(
                id: UUID().uuidString,
                role: .assistant,
                content: response.greeting,
                createdAt: Date()
            )
            messages.append(greetingMessage)
            conversationStarted = true

            // Haptic feedback
            let generator = UIImpactFeedbackGenerator(style: .light)
            generator.impactOccurred()

        } catch let chatError as ChatError {
            if case .conversationCompleted = chatError {
                conversationAlreadyCompleted = true
            }
            self.error = chatError.localizedDescription
            Config.logError("Failed to start conversation: \(chatError.localizedDescription)")
        } catch {
            self.error = error.localizedDescription
            Config.logError("Failed to start conversation: \(error.localizedDescription)")
        }

        isLoading = false
    }

    // MARK: - Send Message
    func sendMessage(_ text: String) async {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty, let conversationId = conversationId else { return }

        // Add user message immediately
        let userMessage = ChatMessage(
            id: UUID().uuidString,
            role: .user,
            content: trimmedText,
            createdAt: Date()
        )
        messages.append(userMessage)

        // Haptic feedback
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.impactOccurred()

        // Show typing indicator
        isTyping = true
        error = nil

        do {
            let response = try await ChatService.shared.sendMessage(
                conversationId: conversationId,
                message: trimmedText
            )

            // Add assistant response
            let assistantMessage = ChatMessage(
                id: response.messageId,
                role: .assistant,
                content: response.content,
                createdAt: Date()
            )
            messages.append(assistantMessage)

            // Haptic feedback for response
            let responseGenerator = UINotificationFeedbackGenerator()
            responseGenerator.notificationOccurred(.success)

        } catch {
            self.error = error.localizedDescription
            Config.logError("Failed to send message: \(error.localizedDescription)")
        }

        isTyping = false
    }

    // MARK: - Complete Conversation
    func completeConversation() async {
        guard let conversationId = conversationId, !conversationCompleted else { return }

        do {
            try await ChatService.shared.completeConversation(conversationId: conversationId)
            conversationCompleted = true

            // Haptic feedback
            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.success)

            Config.logInfo("Conversation completed: \(conversationId)")
        } catch {
            // Don't show error - completing is best-effort
            Config.logError("Failed to complete conversation: \(error.localizedDescription)")
        }
    }
}
