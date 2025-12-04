import SwiftUI

struct SelectionView: View {
    @EnvironmentObject var appState: AppState
    @State private var currentCategoryIndex = 0
    @State private var selectedProductForVariants: Product? = nil
    @State private var showVariantPicker = false

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
            .sheet(isPresented: $showVariantPicker) {
                if let product = selectedProductForVariants,
                   let category = currentCategory {
                    VariantPickerSheet(
                        product: product,
                        category: category,
                        onSelect: { variant in
                            selectProductWithVariant(product, variant: variant, in: category)
                            showVariantPicker = false
                        },
                        onCancel: {
                            showVariantPicker = false
                        }
                    )
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
                }
            }
        }
    }

    private func selectProduct(_ product: Product, in category: Category) {
        // If product has variants (colors), show the variant picker
        if product.hasVariants && !product.variants.isEmpty {
            selectedProductForVariants = product
            showVariantPicker = true
            return
        }

        // Otherwise, select the product directly
        withAnimation(.spring(response: 0.3)) {
            appState.selectProduct(for: category.categoryId, product: product)
        }

        advanceToNextCategory()
    }

    private func selectProductWithVariant(_ product: Product, variant: ProductVariant, in category: Category) {
        withAnimation(.spring(response: 0.3)) {
            appState.selectProduct(for: category.categoryId, product: product, variant: variant)
        }

        advanceToNextCategory()
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

// MARK: - Variant Picker Sheet
struct VariantPickerSheet: View {
    let product: Product
    let category: Category
    let onSelect: (ProductVariant) -> Void
    let onCancel: () -> Void

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                // Product header
                HStack(spacing: 12) {
                    if let imageUrl = product.imageUrl,
                       let url = URL(string: imageUrl) {
                        AsyncImage(url: url) { image in
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                        } placeholder: {
                            ProgressView()
                        }
                        .frame(width: 60, height: 60)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text(product.name)
                            .font(.headline)
                        Text("Select a color")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()
                }
                .padding(.horizontal)

                Divider()

                // Color variants grid
                ScrollView {
                    LazyVGrid(columns: [
                        GridItem(.flexible()),
                        GridItem(.flexible()),
                        GridItem(.flexible())
                    ], spacing: 16) {
                        ForEach(product.variants) { variant in
                            VariantCard(variant: variant, onSelect: {
                                onSelect(variant)
                            })
                        }
                    }
                    .padding()
                }
            }
            .navigationTitle("Choose Color")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        onCancel()
                    }
                }
            }
        }
    }
}

// MARK: - Variant Card
struct VariantCard: View {
    let variant: ProductVariant
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            VStack(spacing: 8) {
                // Color swatch or image
                ZStack {
                    if let imageUrl = variant.imageUrl,
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
                    } else if let colorCode = variant.colorCode,
                              let color = Color(hex: colorCode) {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(color)
                            .frame(width: 80, height: 80)
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .strokeBorder(Color(.systemGray4), lineWidth: 1)
                            )
                    } else {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color(.systemGray5))
                            .frame(width: 80, height: 80)
                            .overlay(
                                Image(systemName: "paintpalette")
                                    .foregroundStyle(.secondary)
                            )
                    }

                    // Default badge
                    if variant.isDefault {
                        VStack {
                            HStack {
                                Spacer()
                                Image(systemName: "star.fill")
                                    .font(.caption)
                                    .foregroundStyle(.yellow)
                            }
                            Spacer()
                        }
                        .padding(4)
                    }
                }

                // Variant name
                Text(variant.name)
                    .font(.caption)
                    .fontWeight(.medium)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)

                // Price
                if let price = variant.price {
                    Text("$\(price, specifier: "%.2f")")
                        .font(.caption2)
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
