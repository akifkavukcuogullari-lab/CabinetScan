import SwiftUI

struct AddonsView: View {
    @EnvironmentObject var appState: AppState

    private var addons: [Addon] {
        appState.showroomConfig?.addons ?? []
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Showroom logo
                if let config = appState.showroomConfig {
                    ShowroomLogo(
                        logoUrl: config.branding.logoUrl,
                        logoDarkUrl: config.branding.logoDarkUrl,
                        maxHeight: 36,
                        maxWidth: 140
                    )
                    .padding(.vertical, 8)
                }

                // Header
                VStack(spacing: 4) {
                    Text("Additional Options")
                        .font(.title2)
                        .fontWeight(.bold)

                    Text("Would you like to add any of these items?")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding()

                // Addons list
                if addons.isEmpty {
                    ContentUnavailableView(
                        "No Add-ons Available",
                        systemImage: "plus.circle",
                        description: Text("No additional options available")
                    )
                    .frame(maxHeight: .infinity)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 16) {
                            ForEach(addons) { addon in
                                AddonCard(
                                    addon: addon,
                                    isSelected: appState.isAddonSelected(addon.id),
                                    onToggle: { isSelected in
                                        withAnimation(.spring(response: 0.3)) {
                                            appState.selectAddon(addonId: addon.id, isSelected: isSelected)
                                        }
                                    }
                                )
                            }

                            // Notes text field
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Additional Details (Optional)")
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                    .foregroundStyle(.secondary)

                                TextField("Any specific requests or details about add-ons...", text: $appState.addonNotes, axis: .vertical)
                                    .lineLimit(3...6)
                                    .textFieldStyle(.roundedBorder)
                            }
                            .padding(.top, 8)
                        }
                        .padding()
                    }
                }

                // Continue button
                VStack(spacing: 12) {
                    Button {
                        appState.proceedFromAddons()
                    } label: {
                        Text("Continue to Review")
                            .fontWeight(.semibold)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                }
                .padding()
            }
            .navigationTitle("Add-ons")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Back") {
                        appState.currentScreen = .selection
                    }
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Skip") {
                        appState.proceedFromAddons()
                    }
                    .foregroundStyle(.secondary)
                }
            }
        }
    }
}

// MARK: - Addon Card
struct AddonCard: View {
    let addon: Addon
    let isSelected: Bool
    let onToggle: (Bool) -> Void

    var body: some View {
        Button {
            onToggle(!isSelected)
        } label: {
            HStack(spacing: 16) {
                // Addon image
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(.systemGray6))
                        .frame(width: 80, height: 80)

                    if let imageUrl = addon.imageUrl,
                       let url = URL(string: imageUrl) {
                        AsyncImage(url: url) { image in
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                        } placeholder: {
                            ProgressView()
                        }
                        .frame(width: 80, height: 80)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    } else {
                        Image(systemName: "plus.circle")
                            .font(.system(size: 30))
                            .foregroundStyle(.tertiary)
                    }
                }

                // Addon info
                VStack(alignment: .leading, spacing: 4) {
                    Text(addon.question)
                        .font(.headline)
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.leading)

                    if let description = addon.description {
                        Text(description)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                    }

                    if let price = addon.pricePerUnit {
                        Text("$\(price, specifier: "%.2f") / \(addon.unit)")
                            .font(.caption)
                            .foregroundStyle(.blue)
                    }
                }

                Spacer()

                // Yes/No indicator
                ZStack {
                    Circle()
                        .fill(isSelected ? Color.green : Color(.systemGray5))
                        .frame(width: 44, height: 44)

                    Image(systemName: isSelected ? "checkmark" : "plus")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(isSelected ? .white : .secondary)
                }
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(.systemBackground))
                    .shadow(color: .black.opacity(0.05), radius: 8, y: 2)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(isSelected ? Color.green : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    AddonsView()
        .environmentObject(AppState.shared)
}
