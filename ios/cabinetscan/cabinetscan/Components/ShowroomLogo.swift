import SwiftUI

/// A view that displays the showroom logo from URL with proper fallback
struct ShowroomLogo: View {
    let logoUrl: String?
    let logoDarkUrl: String?
    var maxHeight: CGFloat = 60
    var maxWidth: CGFloat = 200

    @Environment(\.colorScheme) private var colorScheme

    private var effectiveLogoUrl: String? {
        if colorScheme == .dark, let darkUrl = logoDarkUrl, !darkUrl.isEmpty {
            return darkUrl
        }
        return logoUrl
    }

    var body: some View {
        Group {
            if let urlString = effectiveLogoUrl, let url = URL(string: urlString) {
                AsyncImage(url: url, transaction: Transaction(animation: .easeIn(duration: 0.2))) { phase in
                    switch phase {
                    case .empty:
                        // Reserve space while loading
                        Color.clear
                            .frame(width: maxWidth, height: maxHeight)
                            .overlay(
                                ProgressView()
                                    .scaleEffect(0.8)
                            )
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(maxWidth: maxWidth, maxHeight: maxHeight)
                    case .failure:
                        fallbackLogo
                    @unknown default:
                        fallbackLogo
                    }
                }
                .frame(maxWidth: maxWidth, maxHeight: maxHeight)
            } else {
                fallbackLogo
            }
        }
        .frame(height: maxHeight)
    }

    private var fallbackLogo: some View {
        Image(systemName: "building.2.fill")
            .font(.system(size: 40))
            .foregroundStyle(.blue)
            .frame(height: maxHeight)
    }
}

/// Large showroom logo for welcome screens
struct ShowroomLogoLarge: View {
    let logoUrl: String?
    let logoDarkUrl: String?

    @Environment(\.colorScheme) private var colorScheme

    private var effectiveLogoUrl: String? {
        if colorScheme == .dark, let darkUrl = logoDarkUrl, !darkUrl.isEmpty {
            return darkUrl
        }
        return logoUrl
    }

    var body: some View {
        Group {
            if let urlString = effectiveLogoUrl, let url = URL(string: urlString) {
                AsyncImage(url: url, transaction: Transaction(animation: .easeIn(duration: 0.2))) { phase in
                    switch phase {
                    case .empty:
                        // Reserve space while loading
                        Color.clear
                            .frame(height: 140)
                            .frame(maxWidth: .infinity)
                            .overlay(
                                ProgressView()
                                    .scaleEffect(0.8)
                            )
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(maxHeight: 140)
                            .frame(maxWidth: .infinity)
                    case .failure:
                        fallbackLogo
                    @unknown default:
                        fallbackLogo
                    }
                }
            } else {
                fallbackLogo
            }
        }
        .frame(height: 140)
        .frame(maxWidth: .infinity)
    }

    private var fallbackLogo: some View {
        Image(systemName: "cube.transparent")
            .font(.system(size: 80))
            .foregroundStyle(.blue)
            .frame(height: 140)
    }
}

#Preview {
    VStack(spacing: 40) {
        ShowroomLogo(logoUrl: nil, logoDarkUrl: nil)
        ShowroomLogoLarge(logoUrl: nil, logoDarkUrl: nil)
    }
}
