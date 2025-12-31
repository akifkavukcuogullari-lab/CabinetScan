import SwiftUI

struct ReviewView: View {
    @EnvironmentObject var appState: AppState

    private var categories: [Category] {
        appState.showroomConfig?.categories ?? []
    }

    private var addons: [Addon] {
        appState.showroomConfig?.addons ?? []
    }

    private var selectedAddons: [Addon] {
        addons.filter { appState.isAddonSelected($0.id) }
    }

    var body: some View {
        NavigationStack {
            List {
                // Showroom branding header
                if let config = appState.showroomConfig {
                    Section {
                        VStack(spacing: 12) {
                            GeometryReader { geometry in
                                ShowroomLogo(
                                    logoUrl: config.branding.logoUrl,
                                    logoDarkUrl: config.branding.logoDarkUrl,
                                    maxHeight: 120,
                                    maxWidth: geometry.size.width
                                )
                                .frame(maxWidth: .infinity)
                            }
                            .frame(height: 120)

                            Text(config.name)
                                .font(.title2)
                                .fontWeight(.semibold)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 24, leading: 0, bottom: 16, trailing: 0))
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

                // Selections section
                Section("Selected Products") {
                    if appState.selections.isEmpty {
                        Text("No products selected")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(categories.filter { appState.selections[$0.categoryId] != nil }) { category in
                            if let product = appState.selections[category.categoryId] {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(category.name)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    Text(product.name)
                                        .font(.body)
                                }
                            }
                        }
                    }
                }

                // Addon selections section
                if !selectedAddons.isEmpty {
                    Section("Add-ons") {
                        ForEach(selectedAddons) { addon in
                            HStack {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                                Text(addon.question)
                                    .font(.body)
                            }
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
                    .disabled(appState.isLoading)
                } footer: {
                    Text("By submitting, you agree to share your room measurements and product selections with the showroom.")
                }
            }
            .navigationTitle("Review")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Back") {
                        // Go back to addons if there are any, otherwise to selection
                        if !addons.isEmpty {
                            appState.currentScreen = .addons
                        } else {
                            appState.currentScreen = .selection
                        }
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

#Preview {
    ReviewView()
        .environmentObject(AppState.shared)
}
