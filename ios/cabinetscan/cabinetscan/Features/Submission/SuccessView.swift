import SwiftUI

struct SuccessView: View {
    @EnvironmentObject var appState: AppState
    let referenceNumber: String
    let projectId: String
    @State private var showChat = false
    @State private var chatCompleted = false

    // Check if AI chatbot is enabled
    private var aiChatbot: AIChatbotConfig? {
        appState.showroomConfig?.aiChatbot
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 32) {
                // Showroom logo at top
                if let config = appState.showroomConfig {
                    ShowroomLogo(
                        logoUrl: config.branding.logoUrl,
                        logoDarkUrl: config.branding.logoDarkUrl,
                        maxHeight: 50,
                        maxWidth: 160
                    )
                    .padding(.top, 20)
                }

                // Success animation
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 80))
                    .foregroundStyle(.green)

                VStack(spacing: 12) {
                    Text("Success!")
                        .font(.largeTitle)
                        .fontWeight(.bold)

                    Text("Your project has been submitted")
                        .font(.body)
                        .foregroundStyle(.secondary)
                }

                // Reference number card
                VStack(spacing: 8) {
                    Text("Reference Number")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text(referenceNumber)
                        .font(.system(.title, design: .monospaced))
                        .fontWeight(.bold)
                        .padding()
                        .background(Color(.systemGray6))
                        .clipShape(RoundedRectangle(cornerRadius: 12))

                    Button {
                        UIPasteboard.general.string = referenceNumber
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    } label: {
                        Label("Copy", systemImage: "doc.on.doc")
                            .font(.caption)
                    }
                    .buttonStyle(.bordered)
                }
                .padding()
                .background(Color(.systemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .shadow(color: .black.opacity(0.1), radius: 10, y: 5)

                // AI Designer Agent Chat Invite (if enabled and not completed)
                if let chatbot = aiChatbot, chatbot.enabled, !chatCompleted {
                    ChatInviteCard(
                        assistantName: chatbot.assistantName,
                        assistantAvatarUrl: chatbot.assistantAvatarUrl,
                        onStartChat: {
                            showChat = true
                            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        }
                    )
                    .transition(.scale.combined(with: .opacity))
                }

                // Chat completed message
                if chatCompleted {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.bubble.fill")
                            .foregroundStyle(.green)
                        Text("Chat completed - thank you!")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding()
                    .background(Color(.systemGray6))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .transition(.scale.combined(with: .opacity))
                }

                // Thank you message
                Text("Thank you for your submission. We'll be in touch soon!")
                    .font(.body)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal)

                // Next steps
                VStack(spacing: 12) {
                    Text("What's Next?")
                        .font(.headline)

                    VStack(alignment: .leading, spacing: 8) {
                        NextStepRow(number: 1, text: "You'll receive a confirmation email")
                        NextStepRow(number: 2, text: "The showroom will review your project")
                        NextStepRow(number: 3, text: "They'll contact you with a quote")
                    }
                }
                .padding()
                .background(Color(.systemGray6))
                .clipShape(RoundedRectangle(cornerRadius: 12))

                Button {
                    appState.reset()
                } label: {
                    Text("Start New Project")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .padding(.horizontal)
                .padding(.bottom, 32)
            }
            .padding()
        }
        .sheet(isPresented: $showChat) {
            if let chatbot = aiChatbot {
                ChatView(
                    viewModel: ChatViewModel(
                        projectId: projectId,
                        referenceNumber: referenceNumber,
                        assistantName: chatbot.assistantName,
                        assistantAvatarUrl: chatbot.assistantAvatarUrl
                    ),
                    onComplete: {
                        withAnimation {
                            chatCompleted = true
                        }
                    }
                )
            }
        }
    }
}

// MARK: - Chat Invite Card

struct ChatInviteCard: View {
    let assistantName: String
    let assistantAvatarUrl: String?
    let onStartChat: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            // Avatar
            Group {
                if let urlString = assistantAvatarUrl, let url = URL(string: urlString) {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                        case .failure, .empty:
                            defaultAvatar
                        @unknown default:
                            defaultAvatar
                        }
                    }
                } else {
                    defaultAvatar
                }
            }
            .frame(width: 60, height: 60)
            .clipShape(Circle())
            .shadow(color: .purple.opacity(0.3), radius: 8, y: 4)

            // Text
            VStack(spacing: 8) {
                Text("Have a few minutes?")
                    .font(.headline)

                Text("Chat with \(assistantName) to share more about your design vision")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            // Chat button
            Button(action: onStartChat) {
                Label("Chat with \(assistantName)", systemImage: "bubble.left.fill")
                    .fontWeight(.medium)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(.purple)
            .controlSize(.large)

            // Skip button
            Button("Maybe Later") {
                // Just dismiss, do nothing
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(.systemGray6))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.purple.opacity(0.2), lineWidth: 1)
        )
    }

    private var defaultAvatar: some View {
        ZStack {
            LinearGradient(
                colors: [.purple.opacity(0.7), .purple],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Image(systemName: "person.fill")
                .font(.system(size: 24))
                .foregroundStyle(.white)
        }
    }
}

struct NextStepRow: View {
    let number: Int
    let text: String

    var body: some View {
        HStack(spacing: 12) {
            Text("\(number)")
                .font(.caption)
                .fontWeight(.bold)
                .frame(width: 24, height: 24)
                .background(.blue)
                .foregroundStyle(.white)
                .clipShape(Circle())

            Text(text)
                .font(.subheadline)
        }
    }
}

#Preview {
    SuccessView(referenceNumber: "ABC123", projectId: "test-project")
        .environmentObject(AppState.shared)
}
