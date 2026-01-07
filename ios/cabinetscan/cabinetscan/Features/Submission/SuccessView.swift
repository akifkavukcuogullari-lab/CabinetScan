import SwiftUI

struct SuccessView: View {
    @EnvironmentObject var appState: AppState
    let referenceNumber: String

    var body: some View {
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

            Spacer()

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

            // Thank you message
            Text("Thank you for your submission. We'll be in touch soon!")
                .font(.body)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal)

            Spacer()

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
    SuccessView(referenceNumber: "ABC123")
        .environmentObject(AppState.shared)
}
