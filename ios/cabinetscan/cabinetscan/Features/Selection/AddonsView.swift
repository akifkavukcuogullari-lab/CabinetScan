import SwiftUI

struct AddonsView: View {
    @EnvironmentObject var appState: AppState
    @State private var currentAddonIndex = 0
    @State private var showDetails = false // Show quantity and notes when Yes is selected
    @State private var quantity: Int = 1
    @State private var notes: String = ""

    private var addons: [Addon] {
        appState.showroomConfig?.addons ?? []
    }

    private var currentAddon: Addon? {
        guard currentAddonIndex < addons.count else { return nil }
        return addons[currentAddonIndex]
    }

    private var progress: Double {
        guard addons.count > 0 else { return 0 }
        return Double(currentAddonIndex + 1) / Double(addons.count)
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

                // Progress bar
                ProgressView(value: progress)
                    .progressViewStyle(.linear)
                    .tint(.blue)

                if let addon = currentAddon {
                    ScrollView {
                        VStack(spacing: 20) {
                            // Addon counter
                            Text("\(currentAddonIndex + 1) of \(addons.count)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .padding(.top, 8)

                            // Addon image (if available)
                            if let imageUrl = addon.imageUrl,
                               let url = URL(string: imageUrl) {
                                AsyncImage(url: url) { image in
                                    image
                                        .resizable()
                                        .aspectRatio(contentMode: .fit)
                                } placeholder: {
                                    RoundedRectangle(cornerRadius: 16)
                                        .fill(Color(.systemGray5))
                                        .overlay(
                                            ProgressView()
                                        )
                                }
                                .frame(maxHeight: 250)
                                .clipShape(RoundedRectangle(cornerRadius: 16))
                                .padding(.horizontal)
                            }

                            // Question/Title
                            Text(addon.question)
                                .font(.title2)
                                .fontWeight(.bold)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal)

                            // Description (if available)
                            if let description = addon.description {
                                Text(description)
                                    .font(.body)
                                    .foregroundStyle(.secondary)
                                    .multilineTextAlignment(.center)
                                    .padding(.horizontal)
                            }

                            // Price info (if available)
                            if let price = addon.pricePerUnit {
                                Text("$\(price, specifier: "%.2f") / \(addon.unit)")
                                    .font(.subheadline)
                                    .foregroundStyle(.blue)
                                    .padding(.horizontal)
                            }

                            if !showDetails {
                                // Yes/No buttons
                                HStack(spacing: 16) {
                                    // No button
                                    Button {
                                        selectNo()
                                    } label: {
                                        HStack {
                                            Image(systemName: "xmark")
                                                .font(.title3)
                                            Text("No")
                                                .fontWeight(.semibold)
                                        }
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 16)
                                        .background(Color(.systemGray5))
                                        .foregroundStyle(.primary)
                                        .clipShape(RoundedRectangle(cornerRadius: 12))
                                    }

                                    // Yes button
                                    Button {
                                        selectYes()
                                    } label: {
                                        HStack {
                                            Image(systemName: "checkmark")
                                                .font(.title3)
                                            Text("Yes")
                                                .fontWeight(.semibold)
                                        }
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 16)
                                        .background(Color.green)
                                        .foregroundStyle(.white)
                                        .clipShape(RoundedRectangle(cornerRadius: 12))
                                    }
                                }
                                .padding(.horizontal)
                                .padding(.top, 8)
                            } else {
                                // Quantity and Details section (shown after Yes)
                                VStack(spacing: 16) {
                                    // Compact quantity selector
                                    HStack {
                                        Text("Quantity")
                                            .font(.subheadline)
                                            .foregroundStyle(.secondary)

                                        Spacer()

                                        HStack(spacing: 16) {
                                            Button {
                                                if quantity > 1 { quantity -= 1 }
                                            } label: {
                                                Image(systemName: "minus.circle.fill")
                                                    .font(.title2)
                                                    .foregroundStyle(quantity > 1 ? .blue : .gray)
                                            }
                                            .disabled(quantity <= 1)

                                            Text("\(quantity)")
                                                .font(.title3)
                                                .fontWeight(.semibold)
                                                .frame(minWidth: 32)

                                            Button {
                                                quantity += 1
                                            } label: {
                                                Image(systemName: "plus.circle.fill")
                                                    .font(.title2)
                                                    .foregroundStyle(.blue)
                                            }
                                        }
                                    }
                                    .padding(.horizontal)

                                    // Details text field
                                    TextField("Notes (optional)", text: $notes, axis: .vertical)
                                        .lineLimit(2...4)
                                        .textFieldStyle(.roundedBorder)
                                        .padding(.horizontal)

                                    // Buttons row
                                    HStack(spacing: 12) {
                                        Button {
                                            withAnimation {
                                                showDetails = false
                                            }
                                        } label: {
                                            Label("Change", systemImage: "chevron.left")
                                                .frame(maxWidth: .infinity)
                                                .padding(.vertical, 14)
                                        }
                                        .buttonStyle(.bordered)

                                        Button {
                                            confirmAndContinue()
                                        } label: {
                                            Label("Continue", systemImage: "chevron.right")
                                                .fontWeight(.semibold)
                                                .frame(maxWidth: .infinity)
                                                .padding(.vertical, 14)
                                        }
                                        .buttonStyle(.borderedProminent)
                                    }
                                    .padding(.horizontal)
                                }
                                .padding(.top, 8)
                            }

                            Spacer(minLength: 20)
                        }
                    }
                } else {
                    ContentUnavailableView(
                        "No Add-ons Available",
                        systemImage: "plus.circle",
                        description: Text("No additional options available")
                    )
                }
            }
            .navigationTitle("Additional Options")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Back") {
                        if showDetails {
                            // Go back to Yes/No selection
                            withAnimation {
                                showDetails = false
                            }
                        } else if currentAddonIndex > 0 {
                            // Go to previous addon
                            withAnimation {
                                currentAddonIndex -= 1
                                resetCurrentAddonState()
                            }
                        } else {
                            // Go back to selection
                            appState.currentScreen = .selection
                        }
                    }
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Skip All") {
                        appState.proceedFromAddons()
                    }
                    .foregroundStyle(.secondary)
                }
            }
        }
        .onAppear {
            // Load existing selection if going back
            loadExistingSelection()
        }
    }

    private func selectNo() {
        guard let addon = currentAddon else { return }

        // Save "No" selection
        appState.selectAddon(addonId: addon.id, isSelected: false, quantity: 0, notes: "")

        // Auto-advance to next addon
        advanceToNextAddon()
    }

    private func selectYes() {
        // Show quantity and details section
        withAnimation(.spring(response: 0.3)) {
            showDetails = true
        }
    }

    private func confirmAndContinue() {
        guard let addon = currentAddon else { return }

        // Save "Yes" selection with quantity and notes
        appState.selectAddon(addonId: addon.id, isSelected: true, quantity: quantity, notes: notes)

        // Advance to next addon
        advanceToNextAddon()
    }

    private func advanceToNextAddon() {
        if currentAddonIndex < addons.count - 1 {
            withAnimation {
                currentAddonIndex += 1
                resetCurrentAddonState()
            }
        } else {
            // All addons answered, proceed to review
            appState.proceedFromAddons()
        }
    }

    private func resetCurrentAddonState() {
        showDetails = false
        quantity = 1
        notes = ""
        loadExistingSelection()
    }

    private func loadExistingSelection() {
        guard let addon = currentAddon,
              let selection = appState.getAddonSelection(addon.id) else {
            return
        }

        if selection.isSelected {
            showDetails = true
            quantity = selection.quantity
            notes = selection.notes
        }
    }
}

#Preview {
    AddonsView()
        .environmentObject(AppState.shared)
}
