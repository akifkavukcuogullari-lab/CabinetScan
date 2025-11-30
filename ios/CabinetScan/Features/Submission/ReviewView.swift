import SwiftUI

struct ReviewView: View {
    @EnvironmentObject var appState: AppState

    private var categories: [Category] {
        appState.showroomConfig?.categories ?? []
    }

    var body: some View {
        NavigationStack {
            List {
                // Showroom branding header
                if let config = appState.showroomConfig {
                    Section {
                        HStack {
                            Spacer()
                            ShowroomLogo(
                                logoUrl: config.branding.logoUrl,
                                logoDarkUrl: config.branding.logoDarkUrl,
                                maxHeight: 50,
                                maxWidth: 180
                            )
                            Spacer()
                        }
                        .listRowBackground(Color.clear)
                    }
                }

                // Customer info section
                Section("Your Information") {
                    if let customer = appState.customerInfo {
                        LabeledContent("Name") {
                            Text("\(customer.firstName) \(customer.lastName)")
                        }
                        LabeledContent("Email") {
                            Text(customer.email)
                        }
                        if let phone = customer.phone {
                            LabeledContent("Phone") {
                                Text(phone)
                            }
                        }
                    }
                }

                // Measurements section
                Section("Room Measurements") {
                    if let measurements = appState.measurementData {
                        if let linearFt = measurements.totalLinearFt {
                            LabeledContent("Linear Feet") {
                                Text("\(linearFt, specifier: "%.1f") ft")
                            }
                        }
                        if let sqFt = measurements.totalSqFt {
                            LabeledContent("Square Feet") {
                                Text("\(sqFt, specifier: "%.1f") sq ft")
                            }
                        }
                        if let walls = measurements.wallCount {
                            LabeledContent("Walls") {
                                Text("\(walls)")
                            }
                        }
                        if let windows = measurements.windowCount {
                            LabeledContent("Windows") {
                                Text("\(windows)")
                            }
                        }
                        if let doors = measurements.doorCount {
                            LabeledContent("Doors") {
                                Text("\(doors)")
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
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(category.name)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                        Text(product.name)
                                            .font(.body)
                                    }
                                    Spacer()
                                    if let price = product.price {
                                        Text("$\(price, specifier: "%.2f")")
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                    }
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

#Preview {
    ReviewView()
        .environmentObject(AppState.shared)
}
