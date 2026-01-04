import SwiftUI

struct ContentView: View {
    @EnvironmentObject var appState: AppState
    @State private var showDebugInfo = false

    var body: some View {
        ZStack {
            Group {
                switch appState.currentScreen {
                case .onboarding:
                    OnboardingView()
                case .customerInfo:
                    CustomerInfoView()
                case .scanning:
                    ScanningView()
                case .selection:
                    SelectionView()
                case .addons:
                    AddonsView()
                case .review:
                    ReviewView()
                case .submission:
                    SubmissionView()
                case .success(let referenceNumber):
                    SuccessView(referenceNumber: referenceNumber)
                }
            }
            .animation(.easeInOut, value: appState.currentScreen)
            
            #if DEBUG
            // Debug overlay toggle - tap 3 times in corner
            VStack {
                HStack {
                    Spacer()
                    Button {
                        showDebugInfo.toggle()
                    } label: {
                        Image(systemName: "ladybug.fill")
                            .foregroundColor(.red.opacity(0.3))
                            .padding()
                    }
                }
                Spacer()
            }
            
            // Debug info overlay
            if showDebugInfo {
                DebugInfoOverlay()
            }
            #endif
        }
    }
}

#if DEBUG
struct DebugInfoOverlay: View {
    var body: some View {
        VStack(spacing: 12) {
            Text("Debug Info")
                .font(.headline)
            
            VStack(alignment: .leading, spacing: 8) {
                Text("App: v\(Config.appVersion) (\(Config.buildNumber))")
                Text("Device: \(UIDevice.current.name)")
                Text("iOS: \(UIDevice.current.systemVersion)")
                Divider()
                Text("Supabase URL:")
                    .font(.caption.bold())
                Text(Config.supabaseURL)
                    .font(.caption)
                    .foregroundColor(.blue)
                Text("Using localhost: \(Config.isUsingLocalhost ? "Yes ⚠️" : "No ✅")")
                    .foregroundColor(Config.isUsingLocalhost ? .orange : .green)
            }
            .font(.caption)
            .padding()
        }
        .frame(maxWidth: 300)
        .background(.ultraThinMaterial)
        .cornerRadius(12)
        .shadow(radius: 10)
    }
}
#endif

// MARK: - Screen Equatable
extension AppState.Screen: Equatable {
    static func == (lhs: AppState.Screen, rhs: AppState.Screen) -> Bool {
        switch (lhs, rhs) {
        case (.onboarding, .onboarding),
             (.customerInfo, .customerInfo),
             (.scanning, .scanning),
             (.selection, .selection),
             (.addons, .addons),
             (.review, .review),
             (.submission, .submission):
            return true
        case (.success(let lhsRef), .success(let rhsRef)):
            return lhsRef == rhsRef
        default:
            return false
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(AppState.shared)
}
