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

                // Logo placeholder
                Image(systemName: "cube.transparent")
                    .font(.system(size: 80))
                    .foregroundStyle(.blue)

                VStack(spacing: 8) {
                    Text("Welcome")
                        .font(.largeTitle)
                        .fontWeight(.bold)

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
