import SwiftUI

struct SelectionView: View {
    @EnvironmentObject var appState: AppState
    @State private var currentCategoryIndex = 0
    @State private var currentProductIndex = 0
    @State private var showingColorSelection = false
    @State private var selectedModelForColors: Product? = nil
    @State private var showSelectionsSummary = false

    private var categories: [Category] {
        appState.showroomConfig?.categories ?? []
    }

    private var addons: [Addon] {
        appState.showroomConfig?.addons ?? []
    }

    private var selectedAddonsCount: Int {
        addons.filter { addon in
            appState.getAddonSelection(addon.id)?.isSelected == true
        }.count
    }

    private var selectedProductsCount: Int {
        appState.selections.count
    }

    private var currentCategory: Category? {
        guard currentCategoryIndex < categories.count else { return nil }
        return categories[currentCategoryIndex]
    }

    private var currentProducts: [Product] {
        currentCategory?.products ?? []
    }

    private var progress: Double {
        guard categories.count > 0 else { return 0 }
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

                if showingColorSelection, let product = selectedModelForColors, let category = currentCategory {
                    // Color Selection View
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
                    .padding(.top, 16)
                    .padding(.bottom, 8)

                    // Products carousel
                    if currentProducts.isEmpty {
                        ContentUnavailableView(
                            "No Products",
                            systemImage: "cube.transparent",
                            description: Text("No products available in this category")
                        )
                        .frame(maxHeight: .infinity)
                    } else {
                        // Swipeable product carousel
                        TabView(selection: $currentProductIndex) {
                            ForEach(Array(currentProducts.enumerated()), id: \.element.id) { index, product in
                                ProductCarouselCard(
                                    product: product,
                                    isSelected: appState.selections[category.categoryId]?.id == product.id,
                                    selectedVariant: appState.getSelectedVariant(for: product),
                                    onSelect: {
                                        selectProduct(product, in: category)
                                    }
                                )
                                .tag(index)
                            }
                        }
                        .tabViewStyle(.page(indexDisplayMode: .never))
                        .frame(maxHeight: .infinity)

                        // Custom page indicator
                        HStack(spacing: 8) {
                            ForEach(0..<min(currentProducts.count, 20), id: \.self) { index in
                                Circle()
                                    .fill(index == currentProductIndex ? Color.blue : Color(.systemGray4))
                                    .frame(width: index == currentProductIndex ? 10 : 8, height: index == currentProductIndex ? 10 : 8)
                                    .animation(.spring(response: 0.3), value: currentProductIndex)
                            }
                            if currentProducts.count > 20 {
                                Text("+\(currentProducts.count - 20)")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 8)

                        // Product count
                        Text("\(currentProductIndex + 1) of \(currentProducts.count)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.bottom, 4)
                    }

                    // Selections summary bar
                    if selectedProductsCount > 0 || selectedAddonsCount > 0 {
                        Button {
                            showSelectionsSummary = true
                        } label: {
                            HStack(spacing: 12) {
                                if selectedProductsCount > 0 {
                                    Label("\(selectedProductsCount) products", systemImage: "cube.fill")
                                        .font(.caption)
                                }
                                if selectedAddonsCount > 0 {
                                    Label("\(selectedAddonsCount) add-ons", systemImage: "plus.circle.fill")
                                        .font(.caption)
                                }
                                Spacer()
                                Image(systemName: "chevron.up")
                                    .font(.caption)
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .background(Color(.systemGray6))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.primary)
                        .padding(.horizontal)
                    }

                    // Navigation buttons
                    HStack(spacing: 16) {
                        if currentCategoryIndex > 0 {
                            Button {
                                withAnimation {
                                    currentCategoryIndex -= 1
                                    currentProductIndex = 0
                                }
                            } label: {
                                Label("Back", systemImage: "chevron.left")
                            }
                            .buttonStyle(.bordered)
                        }

                        Spacer()

                        // Skip this category
                        Button {
                            skipCategory()
                        } label: {
                            Text("Skip")
                                .foregroundStyle(.secondary)
                        }

                        if currentCategoryIndex < categories.count - 1 {
                            Button {
                                withAnimation {
                                    currentCategoryIndex += 1
                                    currentProductIndex = 0
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
                                Label("Continue", systemImage: "chevron.right")
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
        .onChange(of: currentCategoryIndex) { _, _ in
            currentProductIndex = 0
        }
        .sheet(isPresented: $showSelectionsSummary) {
            SelectionsSummarySheet(categories: categories, addons: addons)
                .environmentObject(appState)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
    }

    private func selectProduct(_ product: Product, in category: Category) {
        // If product has variants (colors), show color selection
        if product.hasVariants && !product.variants.isEmpty {
            withAnimation(.spring(response: 0.3)) {
                appState.selectProduct(for: category.categoryId, product: product)
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                withAnimation {
                    selectedModelForColors = product
                    showingColorSelection = true
                }
            }
            return
        }

        // Select product and advance
        withAnimation(.spring(response: 0.3)) {
            appState.selectProduct(for: category.categoryId, product: product)
        }

        advanceToNextCategory()
    }

    private func selectColor(_ variant: ProductVariant, for product: Product, in category: Category) {
        withAnimation(.spring(response: 0.3)) {
            appState.selectVariant(for: product, variant: variant)
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            withAnimation {
                showingColorSelection = false
                selectedModelForColors = nil
            }
            advanceToNextCategory()
        }
    }

    private func skipCategory() {
        if currentCategoryIndex < categories.count - 1 {
            withAnimation {
                currentCategoryIndex += 1
                currentProductIndex = 0
            }
        } else {
            appState.proceedToReview()
        }
    }

    private func advanceToNextCategory() {
        if currentCategoryIndex < categories.count - 1 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                withAnimation {
                    currentCategoryIndex += 1
                    currentProductIndex = 0
                }
            }
        }
    }
}

// MARK: - Product Carousel Card (Elegant Tappable Card)
struct ProductCarouselCard: View {
    let product: Product
    let isSelected: Bool
    let selectedVariant: ProductVariant?
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            VStack(spacing: 12) {
                // Product image
                ZStack {
                    RoundedRectangle(cornerRadius: 24)
                        .fill(Color(.systemGray6))

                    if let imageUrl = product.imageUrl,
                       let url = URL(string: imageUrl) {
                        AsyncImage(url: url) { phase in
                            switch phase {
                            case .success(let image):
                                image
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                            case .failure:
                                Image(systemName: "cube")
                                    .font(.system(size: 50))
                                    .foregroundStyle(.tertiary)
                            case .empty:
                                ProgressView()
                            @unknown default:
                                ProgressView()
                            }
                        }
                        .padding(24)
                    } else {
                        Image(systemName: "cube")
                            .font(.system(size: 50))
                            .foregroundStyle(.tertiary)
                    }

                    // Selection indicator
                    if isSelected {
                        RoundedRectangle(cornerRadius: 24)
                            .strokeBorder(.green, lineWidth: 3)

                        VStack {
                            HStack {
                                Spacer()
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.title)
                                    .foregroundStyle(.green)
                                    .background(Circle().fill(.white).padding(2))
                            }
                            Spacer()
                        }
                        .padding(12)
                    }

                    // Badges
                    VStack {
                        HStack {
                            if product.isFeatured {
                                Text("Featured")
                                    .font(.caption2)
                                    .fontWeight(.semibold)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 3)
                                    .background(.yellow)
                                    .clipShape(Capsule())
                            }
                            Spacer()
                            if product.hasVariants && !product.variants.isEmpty {
                                HStack(spacing: 3) {
                                    Image(systemName: "paintpalette.fill")
                                        .font(.caption2)
                                    Text("\(product.variants.count)")
                                        .font(.caption2)
                                        .fontWeight(.semibold)
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(.blue)
                                .foregroundStyle(.white)
                                .clipShape(Capsule())
                            }
                        }
                        Spacer()
                    }
                    .padding(12)
                }
                .frame(maxWidth: .infinity)
                .aspectRatio(1, contentMode: .fit)

                // Product info
                VStack(spacing: 4) {
                    Text(product.name)
                        .font(.title3)
                        .fontWeight(.semibold)
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)

                    if let description = product.description {
                        Text(description)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .lineLimit(2)
                    }

                    if let variant = selectedVariant {
                        Text(variant.name)
                            .font(.subheadline)
                            .foregroundStyle(.blue)
                    }

                    // Price display
                    if let price = selectedVariant?.price ?? product.price {
                        Text("$\(price, specifier: "%.2f")")
                            .font(.headline)
                            .foregroundStyle(.primary)
                    } else if product.hasVariants {
                        let prices = product.variants.compactMap { $0.price }
                        if let minPrice = prices.min(), let maxPrice = prices.max() {
                            if minPrice == maxPrice {
                                Text("$\(minPrice, specifier: "%.2f")")
                                    .font(.headline)
                                    .foregroundStyle(.primary)
                            } else {
                                Text("$\(minPrice, specifier: "%.0f") - $\(maxPrice, specifier: "%.0f")")
                                    .font(.headline)
                                    .foregroundStyle(.primary)
                            }
                        }
                    }
                }

                // Subtle tap hint
                Text("Tap to select")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 8)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Color Selection View (Full Screen)
struct ColorSelectionView: View {
    let product: Product
    let category: Category
    let onSelect: (ProductVariant) -> Void
    let onBack: () -> Void

    @State private var currentColorIndex = 0

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

            // Color carousel
            TabView(selection: $currentColorIndex) {
                ForEach(Array(product.variants.enumerated()), id: \.element.id) { index, variant in
                    ColorCarouselCard(variant: variant) {
                        onSelect(variant)
                    }
                    .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .frame(maxHeight: .infinity)

            // Page indicator
            HStack(spacing: 8) {
                ForEach(0..<min(product.variants.count, 20), id: \.self) { index in
                    Circle()
                        .fill(index == currentColorIndex ? Color.blue : Color(.systemGray4))
                        .frame(width: index == currentColorIndex ? 10 : 8, height: index == currentColorIndex ? 10 : 8)
                }
            }
            .padding(.vertical, 8)

            Text("\(currentColorIndex + 1) of \(product.variants.count) colors")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.bottom, 4)

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

// MARK: - Color Carousel Card (Elegant Tappable Card)
struct ColorCarouselCard: View {
    let variant: ProductVariant
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            VStack(spacing: 12) {
                // Color/door image
                ZStack {
                    RoundedRectangle(cornerRadius: 24)
                        .fill(Color(.systemGray6))

                    if let imageUrl = variant.imageUrl,
                       let url = URL(string: imageUrl) {
                        AsyncImage(url: url) { phase in
                            switch phase {
                            case .success(let image):
                                image
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                            case .failure:
                                colorSwatch
                            case .empty:
                                ProgressView()
                            @unknown default:
                                ProgressView()
                            }
                        }
                        .padding(24)
                    } else {
                        colorSwatch
                    }

                    // Popular badge
                    if variant.isDefault {
                        VStack {
                            HStack {
                                Text("Popular")
                                    .font(.caption2)
                                    .fontWeight(.semibold)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 3)
                                    .background(.yellow)
                                    .clipShape(Capsule())
                                Spacer()
                            }
                            Spacer()
                        }
                        .padding(12)
                    }
                }
                .frame(maxWidth: .infinity)
                .aspectRatio(0.85, contentMode: .fit)

                // Color info
                VStack(spacing: 4) {
                    Text(variant.name)
                        .font(.title3)
                        .fontWeight(.semibold)
                        .foregroundStyle(.primary)

                    if let price = variant.price {
                        Text("$\(price, specifier: "%.2f")")
                            .font(.headline)
                            .foregroundStyle(.primary)
                    }
                }

                // Subtle tap hint
                Text("Tap to select")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 8)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var colorSwatch: some View {
        if let colorCode = variant.colorCode,
           let color = Color(hex: colorCode) {
            RoundedRectangle(cornerRadius: 20)
                .fill(color)
                .padding(32)
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .strokeBorder(Color(.systemGray4), lineWidth: 1)
                        .padding(32)
                )
        } else {
            Image(systemName: "paintpalette")
                .font(.system(size: 50))
                .foregroundStyle(.tertiary)
        }
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

// MARK: - Product Card (kept for backwards compatibility)
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
                }

                VStack(spacing: 2) {
                    Text(product.name)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)

                    if let variant = selectedVariant {
                        Text(variant.name)
                            .font(.caption)
                            .foregroundStyle(.blue)
                    }

                    if let price = selectedVariant?.price ?? product.price {
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

// MARK: - Selections Summary Sheet
struct SelectionsSummarySheet: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) var dismiss
    let categories: [Category]
    let addons: [Addon]

    private var selectedProducts: [(category: Category, product: Product, variant: ProductVariant?)] {
        categories.compactMap { category in
            guard let product = appState.selections[category.categoryId] else { return nil }
            let variant = appState.getSelectedVariant(for: product)
            return (category: category, product: product, variant: variant)
        }
    }

    private var selectedAddons: [(addon: Addon, quantity: Int, notes: String)] {
        addons.compactMap { addon in
            guard let selection = appState.getAddonSelection(addon.id),
                  selection.isSelected else { return nil }
            return (addon: addon, quantity: selection.quantity, notes: selection.notes)
        }
    }

    var body: some View {
        NavigationStack {
            List {
                if !selectedProducts.isEmpty {
                    Section("Selected Products") {
                        ForEach(selectedProducts, id: \.product.id) { item in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.category.name)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    Text(item.product.name)
                                        .font(.subheadline)
                                    if let variant = item.variant {
                                        Text(variant.name)
                                            .font(.caption)
                                            .foregroundStyle(.blue)
                                    }
                                }
                                Spacer()
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                            }
                        }
                    }
                }

                if !selectedAddons.isEmpty {
                    Section("Selected Add-ons") {
                        ForEach(selectedAddons, id: \.addon.id) { item in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.addon.question)
                                        .font(.subheadline)
                                    if !item.notes.isEmpty {
                                        Text(item.notes)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                Spacer()
                                Text("×\(item.quantity)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 2)
                                    .background(Color(.systemGray5))
                                    .clipShape(Capsule())
                            }
                        }
                    }
                }

                if selectedProducts.isEmpty && selectedAddons.isEmpty {
                    ContentUnavailableView(
                        "No Selections Yet",
                        systemImage: "cube.transparent",
                        description: Text("Tap on products to select them")
                    )
                }
            }
            .navigationTitle("Your Selections")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

#Preview {
    SelectionView()
        .environmentObject(AppState.shared)
}
