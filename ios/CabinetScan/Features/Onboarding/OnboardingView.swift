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

                // CabinetScan Logo
                VStack(spacing: 16) {
                    Image("Logo")
                        .resizable()
                        .renderingMode(.original)
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: 150, maxHeight: 150)
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
