import SwiftUI

struct ReviewView: View {
    @EnvironmentObject var appState: AppState
    @State private var hasAgreedToTerms = false

    private var categories: [Category] {
        appState.showroomConfig?.categories ?? []
    }

    private var addons: [Addon] {
        appState.showroomConfig?.addons ?? []
    }

    private var selectedAddons: [(addon: Addon, quantity: Int, notes: String)] {
        addons.compactMap { addon in
            guard let selection = appState.getAddonSelection(addon.id),
                  selection.isSelected else { return nil }
            return (addon: addon, quantity: selection.quantity, notes: selection.notes)
        }
    }

    // Application-level legal URLs (CabinetScan platform)
    private let termsUrl = URL(string: "https://cabinetscan.nextlyn.ai/terms")!
    private let privacyUrl = URL(string: "https://cabinetscan.nextlyn.ai/privacy")!

    var body: some View {
        NavigationStack {
            List {
                // Showroom branding header
                if let config = appState.showroomConfig {
                    Section {
                        VStack(spacing: 16) {
                            ShowroomLogoLarge(
                                logoUrl: config.branding.logoUrl,
                                logoDarkUrl: config.branding.logoDarkUrl
                            )
                            .frame(maxWidth: .infinity, alignment: .center)

                            Text(config.name)
                                .font(.title2)
                                .fontWeight(.semibold)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 20)
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 16, leading: 0, bottom: 8, trailing: 0))
                    }
                }

                // Customer info section
                Section("Your Information") {
                    if let customer = appState.customerInfo {
                        LabeledContent("Name") {
                            Text("\(customer.firstName) \(customer.lastName)")
                        }
                        LabeledContent("Type") {
                            Text(customer.customerType.displayName)
                        }
                        LabeledContent("Email") {
                            Text(customer.email)
                        }
                        LabeledContent("Phone") {
                            Text(customer.phone)
                        }
                        if let address = customer.addressLine1 {
                            LabeledContent("Address") {
                                VStack(alignment: .trailing) {
                                    Text(address)
                                    if let city = customer.city, let state = customer.state, let zip = customer.zipCode {
                                        Text("\(city), \(state) \(zip)")
                                    }
                                }
                            }
                        }
                    }
                }

                // End-client info section (for contractors)
                if let endClient = appState.endClientInfo {
                    Section("End Client Information") {
                        if let firstName = endClient.firstName, let lastName = endClient.lastName {
                            LabeledContent("Name") {
                                Text("\(firstName) \(lastName)")
                            }
                        }
                        if let phone = endClient.phone {
                            LabeledContent("Phone") {
                                Text(phone)
                            }
                        }
                        if let email = endClient.email {
                            LabeledContent("Email") {
                                Text(email)
                            }
                        }
                        if let address = endClient.address {
                            LabeledContent("Address") {
                                Text(address)
                            }
                        }
                    }
                }

                // Selections section (products + addons)
                Section("Your Selections") {
                    if appState.selections.isEmpty && selectedAddons.isEmpty {
                        Text("No selections made")
                            .foregroundStyle(.secondary)
                    } else {
                        // Products with images
                        ForEach(categories.filter { appState.selections[$0.categoryId] != nil }) { category in
                            if let product = appState.selections[category.categoryId] {
                                let variant = appState.getSelectedVariant(for: product)
                                HStack(spacing: 12) {
                                    // Product/Variant image
                                    SelectionThumbnail(
                                        imageUrl: variant?.imageUrl ?? product.imageUrl
                                    )

                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(category.name)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                        Text(product.name)
                                            .font(.subheadline)
                                            .fontWeight(.medium)
                                        if let variant = variant {
                                            Text(variant.name)
                                                .font(.caption)
                                                .foregroundStyle(.blue)
                                        }
                                    }

                                    Spacer()

                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(.green)
                                        .font(.title3)
                                }
                                .padding(.vertical, 4)
                            }
                        }

                        // Addons with images
                        ForEach(selectedAddons, id: \.addon.id) { item in
                            HStack(spacing: 12) {
                                // Addon image
                                SelectionThumbnail(
                                    imageUrl: item.addon.imageUrl
                                )

                                VStack(alignment: .leading, spacing: 3) {
                                    Text("Add-on")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    Text(item.addon.question)
                                        .font(.subheadline)
                                        .fontWeight(.medium)
                                        .lineLimit(2)
                                    if !item.notes.isEmpty {
                                        Text(item.notes)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                    }
                                }

                                Spacer()

                                Text("×\(item.quantity)")
                                    .font(.caption)
                                    .fontWeight(.medium)
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 4)
                                    .background(Color.blue)
                                    .clipShape(Capsule())
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }

                // Special requests section
                Section {
                    TextField("Enter any special requests or details...", text: $appState.specialRequests, axis: .vertical)
                        .lineLimit(3...6)
                } header: {
                    Text("Special Requests")
                } footer: {
                    Text("Add any specific requirements, design preferences, or additional details you'd like the showroom to know.")
                }

                // Legal consent section (required for all submissions)
                Section {
                    Toggle(isOn: $hasAgreedToTerms) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("I agree to the")
                                .font(.subheadline)
                            HStack(spacing: 4) {
                                Link("Terms of Service", destination: termsUrl)
                                    .font(.subheadline)
                                    .foregroundStyle(.blue)
                                Text("and")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                Link("Privacy Policy", destination: privacyUrl)
                                    .font(.subheadline)
                                    .foregroundStyle(.blue)
                            }
                        }
                    }
                    .toggleStyle(CheckboxToggleStyle())
                    .onChange(of: hasAgreedToTerms) { _, newValue in
                        if newValue {
                            appState.recordConsent()
                        }
                    }
                } footer: {
                    Text("Your room scan, photos, and contact information will be shared with the showroom to provide you with a quote.")
                }

                // Submit section
                Section {
                    Button {
                        Task {
                            await appState.submitProject()
                        }
                    } label: {
                        HStack {
                            Spacer()
                            Label("Submit Project", systemImage: "paperplane.fill")
                                .fontWeight(.semibold)
                            Spacer()
                        }
                    }
                    .disabled(appState.isLoading || !hasAgreedToTerms)
                }
            }
            .navigationTitle("Review")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Back") {
                        // Addons are now integrated into selection flow
                        appState.currentScreen = .selection
                    }
                }
            }
            .alert("Error", isPresented: .constant(appState.error != nil)) {
                Button("OK") {
                    appState.error = nil
                }
            } message: {
                if let error = appState.error {
                    Text(error.localizedDescription)
                }
            }
        }
    }
}

// MARK: - Selection Thumbnail
struct SelectionThumbnail: View {
    let imageUrl: String?

    var body: some View {
        Group {
            if let urlString = imageUrl, let url = URL(string: urlString) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    case .failure:
                        placeholderImage
                    case .empty:
                        ProgressView()
                            .frame(width: 56, height: 56)
                    @unknown default:
                        placeholderImage
                    }
                }
            } else {
                placeholderImage
            }
        }
        .frame(width: 56, height: 56)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(Color(.systemGray5), lineWidth: 0.5)
        )
    }

    private var placeholderImage: some View {
        ZStack {
            Color(.systemGray6)
            Image(systemName: "cube.fill")
                .font(.title3)
                .foregroundStyle(.tertiary)
        }
    }
}

// MARK: - Checkbox Toggle Style
struct CheckboxToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: configuration.isOn ? "checkmark.square.fill" : "square")
                .font(.title2)
                .foregroundStyle(configuration.isOn ? .blue : .secondary)
                .onTapGesture {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        configuration.isOn.toggle()
                    }
                }

            configuration.label
        }
    }
}

#Preview {
    ReviewView()
        .environmentObject(AppState.shared)
}
