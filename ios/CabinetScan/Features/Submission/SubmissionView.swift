import SwiftUI

struct SubmissionView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        VStack(spacing: 32) {
            Spacer()

            ProgressView()
                .scaleEffect(1.5)

            VStack(spacing: 8) {
                Text("Submitting...")
                    .font(.title2)
                    .fontWeight(.semibold)

                Text("Please wait while we upload your project")
                    .font(.body)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding()
    }
}

#Preview {
    SubmissionView()
        .environmentObject(AppState.shared)
}
