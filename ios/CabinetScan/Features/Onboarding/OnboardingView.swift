import SwiftUI

struct OnboardingView: View {
    @EnvironmentObject var appState: AppState
    @State private var showroomCode = ""
    @State private var isLoading = false
    @State private var showError = false
    @State private var errorMessage = ""

    var body: some View {
        NavigationStack {
            VStack(spacing: 32) {
                Spacer()

                // Nextlyn Scan Logo
                VStack(spacing: 16) {
                    // Try to use Logo asset, otherwise show app icon style
                    if let uiImage = UIImage(named: "Logo") {
                        Image(uiImage: uiImage)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(maxWidth: 240, maxHeight: 100)
                    } else {
                        // Fallback: App branding with icon
                        VStack(spacing: 12) {
                            Image(systemName: "cube.transparent.fill")
                                .font(.system(size: 60))
                                .foregroundStyle(
                                    LinearGradient(
                                        colors: [.blue, .cyan],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )

                            Text("Nextlyn Scan")
                                .font(.system(size: 32, weight: .bold, design: .rounded))
                                .foregroundStyle(
                                    LinearGradient(
                                        colors: [.blue, .cyan],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                        }
                    }
                }

                VStack(spacing: 8) {
                    Text("Welcome")
                        .font(.title)
                        .fontWeight(.semibold)

                    Text("Enter your showroom code to get started")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                VStack(spacing: 16) {
                    TextField("Showroom Code", text: $showroomCode)
                        .textFieldStyle(.roundedBorder)
                        .font(.title2)
                        .multilineTextAlignment(.center)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .frame(maxWidth: 200)

                    Button {
                        Task {
                            await loadShowroom()
                        }
                    } label: {
                        if isLoading {
                            ProgressView()
                                .progressViewStyle(.circular)
                                .tint(.white)
                        } else {
                            Text("Continue")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(showroomCode.count < 4 || isLoading)
                }

                Spacer()

                // QR Code Scanner Button
                Button {
                    // TODO: Implement QR scanner
                } label: {
                    Label("Scan QR Code", systemImage: "qrcode.viewfinder")
                }
                .foregroundStyle(.secondary)
                .padding(.bottom, 32)
            }
            .padding()
            .alert("Error", isPresented: $showError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage)
            }
        }
    }

    private func loadShowroom() async {
        isLoading = true

        do {
            let config = try await APIService.shared.fetchShowroomConfig(code: showroomCode)
            await MainActor.run {
                appState.showroomConfig = config
                appState.currentScreen = .customerInfo
            }
        } catch {
            await MainActor.run {
                errorMessage = error.localizedDescription
                showError = true
            }
        }

        isLoading = false
    }
}

#Preview {
    OnboardingView()
        .environmentObject(AppState.shared)
}
