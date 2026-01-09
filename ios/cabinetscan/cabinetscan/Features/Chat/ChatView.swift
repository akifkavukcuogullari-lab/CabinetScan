import SwiftUI

struct ChatView: View {
    @Environment(\.dismiss) var dismiss
    @StateObject var viewModel: ChatViewModel
    @State private var messageText = ""
    @FocusState private var isInputFocused: Bool
    var onComplete: (() -> Void)?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Messages List
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 16) {
                            ForEach(viewModel.messages) { message in
                                MessageBubble(
                                    message: message,
                                    assistantName: viewModel.assistantName,
                                    assistantAvatarUrl: viewModel.assistantAvatarUrl
                                )
                                .id(message.id)
                                .transition(.asymmetric(
                                    insertion: .scale(scale: 0.9).combined(with: .opacity),
                                    removal: .opacity
                                ))
                            }

                            // Typing indicator
                            if viewModel.isTyping {
                                TypingIndicator(assistantName: viewModel.assistantName)
                                    .id("typing")
                                    .transition(.scale(scale: 0.9).combined(with: .opacity))
                            }
                        }
                        .padding()
                        .animation(.spring(response: 0.4, dampingFraction: 0.7), value: viewModel.messages.count)
                        .animation(.easeInOut(duration: 0.3), value: viewModel.isTyping)
                    }
                    .onChange(of: viewModel.messages.count) { _, _ in
                        withAnimation {
                            proxy.scrollTo(viewModel.messages.last?.id ?? "typing", anchor: .bottom)
                        }
                    }
                    .onChange(of: viewModel.isTyping) { _, isTyping in
                        if isTyping {
                            withAnimation {
                                proxy.scrollTo("typing", anchor: .bottom)
                            }
                        }
                    }
                }

                // Error message
                if let error = viewModel.error {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                    .background(Color(.systemGray6))
                }

                // Input bar
                ChatInputBar(
                    text: $messageText,
                    isDisabled: viewModel.isLoading || viewModel.isTyping,
                    onSend: {
                        let text = messageText
                        messageText = ""
                        Task {
                            await viewModel.sendMessage(text)
                        }
                    }
                )
                .focused($isInputFocused)
            }
            .navigationTitle(viewModel.assistantName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        Task {
                            await viewModel.completeConversation()
                            onComplete?()
                            dismiss()
                        }
                    }
                    .fontWeight(.medium)
                }
            }
            .task {
                if !viewModel.conversationStarted {
                    await viewModel.startConversation()
                }
            }
            .overlay {
                if viewModel.isLoading && !viewModel.conversationStarted {
                    LoadingOverlay(assistantName: viewModel.assistantName)
                } else if viewModel.conversationAlreadyCompleted {
                    CompletedOverlay(onDismiss: {
                        onComplete?()
                        dismiss()
                    })
                } else if viewModel.error != nil && !viewModel.conversationStarted {
                    ErrorOverlay(
                        error: viewModel.error ?? "Something went wrong",
                        onRetry: {
                            Task {
                                await viewModel.startConversation()
                            }
                        },
                        onDismiss: {
                            dismiss()
                        }
                    )
                }
            }
        }
    }
}

// MARK: - Message Bubble

struct MessageBubble: View {
    let message: ChatMessage
    let assistantName: String
    let assistantAvatarUrl: String?

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            if message.role == .assistant {
                // Assistant avatar
                AssistantAvatar(name: assistantName, avatarUrl: assistantAvatarUrl)

                VStack(alignment: .leading, spacing: 4) {
                    Text(message.content)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(Color(.systemGray5))
                        .foregroundStyle(.primary)
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

                    Text(formatTime(message.createdAt))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .padding(.leading, 4)
                }

                Spacer(minLength: 40)
            } else {
                Spacer(minLength: 40)

                VStack(alignment: .trailing, spacing: 4) {
                    Text(message.content)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(Color.blue)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

                    HStack(spacing: 4) {
                        Text(formatTime(message.createdAt))
                        Image(systemName: "checkmark")
                    }
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.trailing, 4)
                }
            }
        }
    }

    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

// MARK: - Assistant Avatar

struct AssistantAvatar: View {
    let name: String
    let avatarUrl: String?

    var body: some View {
        Group {
            if let urlString = avatarUrl, let url = URL(string: urlString) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    case .failure:
                        fallbackAvatar
                    case .empty:
                        ProgressView()
                    @unknown default:
                        fallbackAvatar
                    }
                }
            } else {
                fallbackAvatar
            }
        }
        .frame(width: 32, height: 32)
        .clipShape(Circle())
    }

    private var fallbackAvatar: some View {
        ZStack {
            LinearGradient(
                colors: [.purple.opacity(0.7), .purple],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Text(initials)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white)
        }
    }

    private var initials: String {
        name.split(separator: " ")
            .prefix(2)
            .compactMap { $0.first }
            .map { String($0).uppercased() }
            .joined()
    }
}

// MARK: - Typing Indicator

struct TypingIndicator: View {
    let assistantName: String
    @State private var animationPhase = 0

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            AssistantAvatar(name: assistantName, avatarUrl: nil)

            HStack(spacing: 4) {
                ForEach(0..<3, id: \.self) { index in
                    Circle()
                        .fill(Color(.systemGray3))
                        .frame(width: 8, height: 8)
                        .scaleEffect(animationPhase == index ? 1.2 : 0.8)
                        .animation(
                            .easeInOut(duration: 0.5)
                                .repeatForever()
                                .delay(Double(index) * 0.15),
                            value: animationPhase
                        )
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(Color(.systemGray5))
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

            Spacer()
        }
        .onAppear {
            animationPhase = 1
        }
    }
}

// MARK: - Chat Input Bar

struct ChatInputBar: View {
    @Binding var text: String
    let isDisabled: Bool
    let onSend: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            TextField("Type a message...", text: $text, axis: .vertical)
                .textFieldStyle(.plain)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Color(.systemGray6))
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                .lineLimit(1...5)
                .disabled(isDisabled)

            Button {
                onSend()
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 32))
                    .foregroundStyle(text.isEmpty || isDisabled ? Color.gray : Color.blue)
            }
            .disabled(text.isEmpty || isDisabled)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(.bar)
    }
}

// MARK: - Loading Overlay

struct LoadingOverlay: View {
    let assistantName: String
    @State private var isAnimating = false

    var body: some View {
        ZStack {
            Color(.systemBackground).opacity(0.95)
                .ignoresSafeArea()

            VStack(spacing: 20) {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [.purple.opacity(0.3), .purple.opacity(0.1)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 80, height: 80)
                        .scaleEffect(isAnimating ? 1.1 : 0.9)

                    Image(systemName: "bubble.left.and.bubble.right.fill")
                        .font(.system(size: 32))
                        .foregroundStyle(.purple)
                        .symbolEffect(.pulse, options: .repeating)
                }
                .animation(.easeInOut(duration: 1).repeatForever(autoreverses: true), value: isAnimating)

                Text("Connecting to \(assistantName)...")
                    .font(.headline)
                    .foregroundStyle(.secondary)
            }
        }
        .onAppear {
            isAnimating = true
        }
    }
}

// MARK: - Completed Overlay

struct CompletedOverlay: View {
    let onDismiss: () -> Void

    var body: some View {
        ZStack {
            Color(.systemBackground).opacity(0.95)
                .ignoresSafeArea()

            VStack(spacing: 24) {
                ZStack {
                    Circle()
                        .fill(Color.green.opacity(0.1))
                        .frame(width: 80, height: 80)

                    Image(systemName: "checkmark.bubble.fill")
                        .font(.system(size: 32))
                        .foregroundStyle(.green)
                }

                VStack(spacing: 8) {
                    Text("Chat Completed")
                        .font(.headline)

                    Text("This conversation has already been completed. Thank you for sharing your design vision!")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }

                Button {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    onDismiss()
                } label: {
                    Text("Got It")
                        .fontWeight(.medium)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .padding(.horizontal, 48)
            }
        }
    }
}

// MARK: - Error Overlay

struct ErrorOverlay: View {
    let error: String
    let onRetry: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        ZStack {
            Color(.systemBackground).opacity(0.95)
                .ignoresSafeArea()

            VStack(spacing: 24) {
                ZStack {
                    Circle()
                        .fill(Color.red.opacity(0.1))
                        .frame(width: 80, height: 80)

                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 32))
                        .foregroundStyle(.red)
                }

                VStack(spacing: 8) {
                    Text("Connection Error")
                        .font(.headline)

                    Text(error)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }

                VStack(spacing: 12) {
                    Button {
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        onRetry()
                    } label: {
                        Label("Try Again", systemImage: "arrow.clockwise")
                            .fontWeight(.medium)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)

                    Button("Dismiss") {
                        onDismiss()
                    }
                    .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 48)
            }
        }
    }
}

// MARK: - Preview

#Preview {
    ChatView(
        viewModel: ChatViewModel(
            projectId: "test-project",
            referenceNumber: "ABC123",
            assistantName: "Sophie",
            assistantAvatarUrl: nil
        ),
        onComplete: nil
    )
}
