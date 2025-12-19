import SwiftUI

struct ContentView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
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
            case .review:
                ReviewView()
            case .submission:
                SubmissionView()
            case .success(let referenceNumber):
                SuccessView(referenceNumber: referenceNumber)
            }
        }
        .animation(.easeInOut, value: appState.currentScreen)
    }
}

// MARK: - Screen Equatable
extension AppState.Screen: Equatable {
    static func == (lhs: AppState.Screen, rhs: AppState.Screen) -> Bool {
        switch (lhs, rhs) {
        case (.onboarding, .onboarding),
             (.customerInfo, .customerInfo),
             (.scanning, .scanning),
             (.selection, .selection),
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
