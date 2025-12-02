import SwiftUI

struct SelectionView: View {
    @EnvironmentObject var appState: AppState
    @State private var currentCategoryIndex = 0

    private var categories: [Category] {
        appState.showroomConfig?.categories ?? []
    }

    private var currentCategory: Category? {
        guard currentCategoryIndex < categories.count else { return nil }
        return categories[currentCategoryIndex]
    }

    private var progress: Double {
        guard !categories.isEmpty else { return 0 }
        return Double(currentCategoryIndex + 1) / Double(categories.count)
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

                if let category = currentCategory {
                    // Category header
                    VStack(spacing: 4) {
                        Text(category.name)
                            .font(.title2)
                            .fontWeight(.bold)

                        Text("\(currentCategoryIndex + 1) of \(categories.count)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding()

                    // Products grid
                    if category.products.isEmpty {
                        ContentUnavailableView(
                            "No Products",
                            systemImage: "cube.transparent",
                            description: Text("No products available in this category")
                        )
                        .frame(maxHeight: .infinity)
                    } else {
                        ScrollView {
                            LazyVGrid(columns: [
                                GridItem(.flexible()),
                                GridItem(.flexible())
                            ], spacing: 16) {
                                ForEach(category.products) { product in
                                    ProductCard(
                                        product: product,
                                        isSelected: appState.selections[category.categoryId]?.id == product.id,
                                        onSelect: {
                                            selectProduct(product, in: category)
                                        }
                                    )
                                }
                            }
                            .padding()
                        }
                    }

                    // Navigation buttons
                    HStack(spacing: 16) {
                        if currentCategoryIndex > 0 {
                            Button {
                                withAnimation {
                                    currentCategoryIndex -= 1
                                }
                            } label: {
                                Label("Back", systemImage: "chevron.left")
                            }
                            .buttonStyle(.bordered)
                        }

                        Spacer()

                        if currentCategoryIndex < categories.count - 1 {
                            Button {
                                withAnimation {
                                    currentCategoryIndex += 1
                                }
                            } label: {
                                Label("Next", systemImage: "chevron.right")
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(category.isRequired && appState.selections[category.categoryId] == nil)
                        } else {
                            Button {
                                appState.proceedToReview()
                            } label: {
                                Text("Review")
                            }
                            .buttonStyle(.borderedProminent)
                        }
                    }
                    .padding()
                } else {
                    ContentUnavailableView(
                        "No Categories",
                        systemImage: "folder",
                        description: Text("No product categories configured")
                    )
                }
            }
            .navigationTitle("Select Products")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Back") {
                        appState.currentScreen = .scanning
                    }
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Skip All") {
                        appState.proceedToReview()
                    }
                    .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func selectProduct(_ product: Product, in category: Category) {
        withAnimation(.spring(response: 0.3)) {
            appState.selectProduct(for: category.categoryId, product: product)
        }

        // Auto-advance after selection (with delay)
        if currentCategoryIndex < categories.count - 1 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                withAnimation {
                    currentCategoryIndex += 1
                }
            }
        }
    }
}

// MARK: - Product Card
struct ProductCard: View {
    let product: Product
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            VStack(spacing: 8) {
                // Product image
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(.systemGray6))
                        .aspectRatio(1, contentMode: .fit)

                    if let imageUrl = product.imageUrl,
                       let url = URL(string: imageUrl) {
                        AsyncImage(url: url) { image in
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                        } placeholder: {
                            ProgressView()
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    } else {
                        Image(systemName: "cube")
                            .font(.system(size: 40))
                            .foregroundStyle(.tertiary)
                    }

                    // Selection indicator
                    if isSelected {
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(.blue, lineWidth: 3)

                        VStack {
                            HStack {
                                Spacer()
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.title2)
                                    .foregroundStyle(.blue)
                                    .background(Circle().fill(.white))
                            }
                            Spacer()
                        }
                        .padding(8)
                    }

                    // Featured badge
                    if product.isFeatured {
                        VStack {
                            HStack {
                                Text("Featured")
                                    .font(.caption2)
                                    .fontWeight(.bold)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(.yellow)
                                    .clipShape(Capsule())
                                Spacer()
                            }
                            Spacer()
                        }
                        .padding(8)
                    }
                }

                // Product info
                VStack(spacing: 2) {
                    Text(product.name)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)

                    if let price = product.price {
                        Text("$\(price, specifier: "%.2f")")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    SelectionView()
        .environmentObject(AppState.shared)
}
