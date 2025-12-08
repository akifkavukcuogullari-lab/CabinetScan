import SwiftUI

struct SelectionView: View {
    @EnvironmentObject var appState: AppState
    @State private var currentCategoryIndex = 0
    @State private var showingColorSelection = false
    @State private var selectedModelForColors: Product? = nil

    private var categories: [Category] {
        appState.showroomConfig?.categories ?? []
    }

    private var currentCategory: Category? {
        guard currentCategoryIndex < categories.count else { return nil }
        return categories[currentCategoryIndex]
    }

    // Adjust progress to account for color selection step
    private var totalSteps: Int {
        var steps = categories.count
        // Add extra step for each category that has a selected product with variants
        for category in categories {
            if let selectedProduct = appState.selections[category.categoryId],
               selectedProduct.hasVariants && !selectedProduct.variants.isEmpty {
                steps += 1
            }
        }
        return steps
    }

    private var currentStep: Int {
        var step = currentCategoryIndex + 1
        if showingColorSelection {
            step += 1
        }
        return step
    }

    private var progress: Double {
        guard totalSteps > 0 else { return 0 }
        return Double(currentStep) / Double(max(totalSteps, categories.count))
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

                if showingColorSelection, let product = selectedModelForColors, let category = currentCategory {
                    // Color Selection View (full screen, same style as category)
                    ColorSelectionView(
                        product: product,
                        category: category,
                        onSelect: { variant in
                            selectColor(variant, for: product, in: category)
                        },
                        onBack: {
                            withAnimation {
                                showingColorSelection = false
                                selectedModelForColors = nil
                                // Clear the model selection so user can pick again
                                appState.selections.removeValue(forKey: category.categoryId)
                                appState.variantSelections.removeValue(forKey: product.id)
                            }
                        }
                    )
                } else if let category = currentCategory {
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
                                        selectedVariant: appState.getSelectedVariant(for: product),
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
                        if showingColorSelection {
                            withAnimation {
                                showingColorSelection = false
                                selectedModelForColors = nil
                            }
                        } else {
                            appState.currentScreen = .scanning
                        }
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
        // If product has variants (colors), show color selection as next step
        if product.hasVariants && !product.variants.isEmpty {
            // First select the model
            withAnimation(.spring(response: 0.3)) {
                appState.selectProduct(for: category.categoryId, product: product)
            }
            // Then show color selection
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                withAnimation {
                    selectedModelForColors = product
                    showingColorSelection = true
                }
            }
            return
        }

        // Otherwise, select the product directly and advance
        withAnimation(.spring(response: 0.3)) {
            appState.selectProduct(for: category.categoryId, product: product)
        }

        advanceToNextCategory()
    }

    private func selectColor(_ variant: ProductVariant, for product: Product, in category: Category) {
        withAnimation(.spring(response: 0.3)) {
            appState.selectVariant(for: product, variant: variant)
        }

        // Hide color selection and advance
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            withAnimation {
                showingColorSelection = false
                selectedModelForColors = nil
            }
            advanceToNextCategory()
        }
    }

    private func advanceToNextCategory() {
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

// MARK: - Color Selection View (Full Screen)
struct ColorSelectionView: View {
    let product: Product
    let category: Category
    let onSelect: (ProductVariant) -> Void
    let onBack: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Header showing selected model
            HStack(spacing: 12) {
                if let imageUrl = product.imageUrl,
                   let url = URL(string: imageUrl) {
                    AsyncImage(url: url) { image in
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                    } placeholder: {
                        ProgressView()
                    }
                    .frame(width: 50, height: 50)
                    .background(Color(.systemGray6))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(product.name)
                        .font(.headline)
                    Text("Select Color")
                        .font(.title2)
                        .fontWeight(.bold)
                }

                Spacer()
            }
            .padding()
            .background(Color(.systemGray6))

            // Color options grid - larger cards for door images
            ScrollView {
                LazyVGrid(columns: [
                    GridItem(.flexible()),
                    GridItem(.flexible())
                ], spacing: 16) {
                    ForEach(product.variants) { variant in
                        ColorOptionCard(variant: variant) {
                            onSelect(variant)
                        }
                    }
                }
                .padding()
            }

            // Back button
            HStack {
                Button {
                    onBack()
                } label: {
                    Label("Change Model", systemImage: "chevron.left")
                }
                .buttonStyle(.bordered)

                Spacer()
            }
            .padding()
        }
    }
}

// MARK: - Color Option Card (Larger for door images)
struct ColorOptionCard: View {
    let variant: ProductVariant
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            VStack(spacing: 8) {
                // Door image or color swatch - taller aspect ratio for doors
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(.systemGray6))
                        .aspectRatio(0.6, contentMode: .fit) // Taller for door images

                    if let imageUrl = variant.imageUrl,
                       let url = URL(string: imageUrl) {
                        AsyncImage(url: url) { image in
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                        } placeholder: {
                            ProgressView()
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    } else if let colorCode = variant.colorCode,
                              let color = Color(hex: colorCode) {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(color)
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .strokeBorder(Color(.systemGray4), lineWidth: 1)
                            )
                    } else {
                        Image(systemName: "paintpalette")
                            .font(.system(size: 40))
                            .foregroundStyle(.tertiary)
                    }

                    // Default badge
                    if variant.isDefault {
                        VStack {
                            HStack {
                                Text("Popular")
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

                // Color name
                Text(variant.name)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)

                // Price
                if let price = variant.price {
                    Text("$\(price, specifier: "%.2f")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Color Extension for Hex
extension Color {
    init?(hex: String) {
        var hexSanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        hexSanitized = hexSanitized.replacingOccurrences(of: "#", with: "")

        var rgb: UInt64 = 0

        guard Scanner(string: hexSanitized).scanHexInt64(&rgb) else {
            return nil
        }

        let red = Double((rgb & 0xFF0000) >> 16) / 255.0
        let green = Double((rgb & 0x00FF00) >> 8) / 255.0
        let blue = Double(rgb & 0x0000FF) / 255.0

        self.init(red: red, green: green, blue: blue)
    }
}

// MARK: - Product Card
struct ProductCard: View {
    let product: Product
    let isSelected: Bool
    let selectedVariant: ProductVariant?
    let onSelect: () -> Void

    init(product: Product, isSelected: Bool, selectedVariant: ProductVariant? = nil, onSelect: @escaping () -> Void) {
        self.product = product
        self.isSelected = isSelected
        self.selectedVariant = selectedVariant
        self.onSelect = onSelect
    }

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
                                .aspectRatio(contentMode: .fit)
                        } placeholder: {
                            ProgressView()
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
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

                    // Featured badge or variants indicator
                    VStack {
                        HStack {
                            if product.isFeatured {
                                Text("Featured")
                                    .font(.caption2)
                                    .fontWeight(.bold)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(.yellow)
                                    .clipShape(Capsule())
                            }
                            Spacer()
                            if product.hasVariants && !product.variants.isEmpty {
                                HStack(spacing: 2) {
                                    Image(systemName: "paintpalette.fill")
                                        .font(.caption2)
                                    Text("\(product.variants.count)")
                                        .font(.caption2)
                                        .fontWeight(.bold)
                                }
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(.blue.opacity(0.9))
                                .foregroundStyle(.white)
                                .clipShape(Capsule())
                            }
                        }
                        Spacer()
                    }
                    .padding(8)
                }

                // Product info
                VStack(spacing: 2) {
                    Text(product.name)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)

                    // Show selected variant name if applicable
                    if let variant = selectedVariant {
                        Text(variant.name)
                            .font(.caption)
                            .foregroundStyle(.blue)
                    }

                    // Show price (variant price takes precedence)
                    if let price = selectedVariant?.price ?? product.price {
                        Text("$\(price, specifier: "%.2f")")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else if product.hasVariants {
                        // Show price range for products with variants
                        let prices = product.variants.compactMap { $0.price }
                        if let minPrice = prices.min(), let maxPrice = prices.max() {
                            if minPrice == maxPrice {
                                Text("$\(minPrice, specifier: "%.2f")")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            } else {
                                Text("$\(minPrice, specifier: "%.0f") - $\(maxPrice, specifier: "%.0f")")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
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
