import SwiftUI

struct SelectionView: View {
    @EnvironmentObject var appState: AppState
    @State private var currentStepIndex = 0
    @State private var currentProductIndex = 0
    @State private var showingColorSelection = false
    @State private var selectedModelForColors: Product? = nil
    @State private var showSelectionsSummary = false

    // Addon-specific state
    @State private var showAddonDetails = false
    @State private var addonQuantity: Int = 1
    @State private var addonNotes: String = ""

    private var categories: [Category] {
        appState.showroomConfig?.categories ?? []
    }

    private var addons: [Addon] {
        appState.showroomConfig?.addons ?? []
    }

    /// Total number of steps (categories + addons)
    private var totalSteps: Int {
        categories.count + addons.count
    }

    /// Whether we're currently in the addon section
    private var isInAddonSection: Bool {
        currentStepIndex >= categories.count
    }

    /// Current addon index (0-based within addons array)
    private var currentAddonIndex: Int {
        currentStepIndex - categories.count
    }

    /// Current addon being displayed
    private var currentAddon: Addon? {
        guard isInAddonSection, currentAddonIndex < addons.count else { return nil }
        return addons[currentAddonIndex]
    }

    private var selectedAddonsCount: Int {
        addons.filter { addon in
            appState.getAddonSelection(addon.id)?.isSelected == true
        }.count
    }

    /// Get the price coefficient from the selected Cabinet Model color variant
    private var cabinetColorCoefficient: Double {
        guard let cabinetCategory = categories.first(where: { $0.slug == "cabinet-model" }),
              let selectedProduct = appState.selections[cabinetCategory.categoryId],
              let selectedVariant = appState.getSelectedVariant(for: selectedProduct) else {
            return 1.0
        }
        return selectedVariant.priceCoefficient
    }

    private var selectedProductsCount: Int {
        appState.selections.count
    }

    private var currentCategory: Category? {
        guard !isInAddonSection, currentStepIndex < categories.count else { return nil }
        return categories[currentStepIndex]
    }

    private var currentProducts: [Product] {
        currentCategory?.products ?? []
    }

    private var progress: Double {
        guard totalSteps > 0 else { return 0 }
        return Double(currentStepIndex + 1) / Double(totalSteps)
    }

    // MARK: - Helper UI to reduce type-checking complexity
    private func isNextDisabled(for category: Category) -> Bool {
        category.isRequired && appState.selections[category.categoryId] == nil
    }

    @ViewBuilder
    private func nextButton(for category: Category) -> some View {
        let disabled = isNextDisabled(for: category)
        Button {
            advanceToNextStep()
        } label: {
            HStack(spacing: 4) {
                Text("Next")
                    .font(.subheadline.weight(.semibold))
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .background(
                Capsule().fill(
                    disabled
                    ? AnyShapeStyle(Color.gray.opacity(0.5))
                    : AnyShapeStyle(
                        LinearGradient(
                            colors: [Color.blue.opacity(0.9), Color.blue],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                )
            )
            .shadow(
                color: disabled ? .clear : .blue.opacity(0.25),
                radius: 6, y: 3
            )
        }
        .disabled(disabled)
    }

    private struct PageIndicatorView: View {
        let count: Int
        let currentIndex: Int
        var body: some View {
            HStack(spacing: 8) {
                ForEach(0..<min(count, 20), id: \.self) { index in
                    Circle()
                        .fill(index == currentIndex ? Color.blue : Color(.systemGray4))
                        .frame(width: index == currentIndex ? 10 : 8, height: index == currentIndex ? 10 : 8)
                        .animation(.spring(response: 0.3), value: currentIndex)
                }
                if count > 20 {
                    Text("+\(count - 20)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    /// Calculate effective addon price with coefficient if applicable
    private func effectiveAddonPrice(_ basePrice: Double, for addon: Addon) -> Double {
        if addon.useColorCoefficient {
            return basePrice * cabinetColorCoefficient
        }
        return basePrice
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Large showroom logo
                if let config = appState.showroomConfig {
                    ShowroomLogo(
                        logoUrl: config.branding.logoUrl,
                        logoDarkUrl: config.branding.logoDarkUrl,
                        maxHeight: 100,
                        maxWidth: 300
                    )
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                }

                // Progress bar
                ProgressView(value: progress)
                    .progressViewStyle(.linear)
                    .tint(.blue)
                    .padding(.horizontal, 16)

                // Step indicator
                Text("Step \(currentStepIndex + 1) of \(totalSteps)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.top, 8)

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
                } else if !isInAddonSection, let category = currentCategory {
                    // PRODUCT CATEGORY VIEW
                    VStack(spacing: 4) {
                        Text(category.name)
                            .font(.title2)
                            .fontWeight(.bold)
                    }
                    .padding(.top, 8)
                    .padding(.bottom, 8)

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
                                    showPrice: category.showPriceToCustomer,
                                    colorCoefficient: cabinetColorCoefficient,
                                    onSelect: {
                                        selectProduct(product, in: category)
                                    }
                                )
                                .tag(index)
                            }
                        }
                        .tabViewStyle(.page(indexDisplayMode: .never))
                        .frame(maxHeight: .infinity)

                        // Custom page indicator replaced
                        PageIndicatorView(count: currentProducts.count, currentIndex: currentProductIndex)
                            .padding(.vertical, 8)

                        // Product count
                        Text("\(currentProductIndex + 1) of \(currentProducts.count) products")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.bottom, 4)
                    }

                    // Elegant navigation buttons for products
                    HStack(spacing: 12) {
                        if currentStepIndex > 0 {
                            Button {
                                goToPreviousStep()
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: "chevron.left")
                                        .font(.caption.weight(.semibold))
                                    Text("Back")
                                        .font(.subheadline.weight(.medium))
                                }
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 10)
                                .background(.ultraThinMaterial)
                                .clipShape(Capsule())
                                .overlay(
                                    Capsule()
                                        .strokeBorder(Color(.systemGray4), lineWidth: 0.5)
                                )
                            }
                        }

                        Spacer()

                        // Skip this category
                        Button {
                            skipCurrentStep()
                        } label: {
                            Text("Skip")
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(.tertiary)
                        }

                        nextButton(for: category)
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)

                } else if isInAddonSection, let addon = currentAddon {
                    // ADDON VIEW (integrated)
                    ScrollView {
                        VStack(spacing: 20) {
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
                                        .overlay(ProgressView())
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

                            // Price info (if available and showPriceToCustomer is enabled)
                            if addon.showPriceToCustomer, let price = addon.pricePerUnit {
                                Text("$\(effectiveAddonPrice(price, for: addon), specifier: "%.2f") / \(addon.unit)")
                                    .font(.subheadline)
                                    .foregroundStyle(.blue)
                                    .padding(.horizontal)
                            }

                            if !showAddonDetails {
                                // Elegant Yes/No buttons
                                HStack(spacing: 12) {
                                    Button {
                                        selectAddonNo(addon)
                                    } label: {
                                        HStack(spacing: 6) {
                                            Image(systemName: "xmark")
                                                .font(.subheadline.weight(.medium))
                                            Text("No thanks")
                                                .font(.subheadline.weight(.medium))
                                        }
                                        .foregroundStyle(.secondary)
                                        .padding(.horizontal, 20)
                                        .padding(.vertical, 12)
                                        .background(.ultraThinMaterial)
                                        .clipShape(Capsule())
                                        .overlay(
                                            Capsule()
                                                .strokeBorder(Color(.systemGray4), lineWidth: 0.5)
                                        )
                                    }

                                    Button {
                                        selectAddonYes()
                                    } label: {
                                        HStack(spacing: 6) {
                                            Image(systemName: "checkmark")
                                                .font(.subheadline.weight(.semibold))
                                            Text("Yes, add this")
                                                .font(.subheadline.weight(.semibold))
                                        }
                                        .foregroundStyle(.white)
                                        .padding(.horizontal, 20)
                                        .padding(.vertical, 12)
                                        .background(
                                            Capsule()
                                                .fill(
                                                    LinearGradient(
                                                        colors: [Color.green.opacity(0.9), Color.green],
                                                        startPoint: .top,
                                                        endPoint: .bottom
                                                    )
                                                )
                                        )
                                        .shadow(color: .green.opacity(0.3), radius: 8, y: 4)
                                    }
                                }
                                .padding(.top, 16)
                            } else {
                                // Elegant quantity and details section
                                VStack(spacing: 20) {
                                    // Quantity stepper with glass effect
                                    HStack {
                                        Text("Quantity")
                                            .font(.subheadline)
                                            .foregroundStyle(.secondary)

                                        Spacer()

                                        HStack(spacing: 0) {
                                            Button {
                                                withAnimation(.spring(response: 0.25)) {
                                                    if addonQuantity > 1 { addonQuantity -= 1 }
                                                }
                                            } label: {
                                                Image(systemName: "minus")
                                                    .font(.subheadline.weight(.medium))
                                                    .foregroundStyle(addonQuantity > 1 ? .primary : .tertiary)
                                                    .frame(width: 36, height: 36)
                                            }
                                            .disabled(addonQuantity <= 1)

                                            Text("\(addonQuantity)")
                                                .font(.body.weight(.semibold))
                                                .frame(minWidth: 40)
                                                .contentTransition(.numericText())

                                            Button {
                                                withAnimation(.spring(response: 0.25)) {
                                                    addonQuantity += 1
                                                }
                                            } label: {
                                                Image(systemName: "plus")
                                                    .font(.subheadline.weight(.medium))
                                                    .foregroundStyle(.primary)
                                                    .frame(width: 36, height: 36)
                                            }
                                        }
                                        .background(.ultraThinMaterial)
                                        .clipShape(Capsule())
                                        .overlay(
                                            Capsule()
                                                .strokeBorder(Color(.systemGray4), lineWidth: 0.5)
                                        )
                                    }
                                    .padding(.horizontal, 24)

                                    // Notes field with subtle styling
                                    TextField("Add a note (optional)", text: $addonNotes, axis: .vertical)
                                        .lineLimit(2...3)
                                        .font(.subheadline)
                                        .padding(12)
                                        .background(Color(.systemGray6).opacity(0.5))
                                        .clipShape(RoundedRectangle(cornerRadius: 10))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 10)
                                                .strokeBorder(Color(.systemGray4), lineWidth: 0.5)
                                        )
                                        .padding(.horizontal, 24)

                                    // Action buttons
                                    HStack(spacing: 12) {
                                        Button {
                                            withAnimation(.spring(response: 0.3)) {
                                                showAddonDetails = false
                                            }
                                        } label: {
                                            HStack(spacing: 4) {
                                                Image(systemName: "chevron.left")
                                                    .font(.caption.weight(.semibold))
                                                Text("Change")
                                                    .font(.subheadline.weight(.medium))
                                            }
                                            .foregroundStyle(.secondary)
                                            .padding(.horizontal, 16)
                                            .padding(.vertical, 10)
                                            .background(.ultraThinMaterial)
                                            .clipShape(Capsule())
                                            .overlay(
                                                Capsule()
                                                    .strokeBorder(Color(.systemGray4), lineWidth: 0.5)
                                            )
                                        }

                                        Button {
                                            confirmAddonAndContinue(addon)
                                        } label: {
                                            HStack(spacing: 4) {
                                                Text("Continue")
                                                    .font(.subheadline.weight(.semibold))
                                                Image(systemName: "chevron.right")
                                                    .font(.caption.weight(.semibold))
                                            }
                                            .foregroundStyle(.white)
                                            .padding(.horizontal, 20)
                                            .padding(.vertical, 10)
                                            .background(
                                                Capsule()
                                                    .fill(
                                                        LinearGradient(
                                                            colors: [Color.blue.opacity(0.9), Color.blue],
                                                            startPoint: .top,
                                                            endPoint: .bottom
                                                        )
                                                    )
                                            )
                                            .shadow(color: .blue.opacity(0.25), radius: 6, y: 3)
                                        }
                                    }
                                    .padding(.horizontal, 24)
                                }
                                .padding(.top, 12)
                            }

                            Spacer(minLength: 20)
                        }
                    }

                    // Back button for addons (when not showing details)
                    if !showAddonDetails && currentStepIndex > 0 {
                        HStack {
                            Button {
                                goToPreviousStep()
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: "chevron.left")
                                        .font(.caption.weight(.semibold))
                                    Text("Back")
                                        .font(.subheadline.weight(.medium))
                                }
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 10)
                                .background(.ultraThinMaterial)
                                .clipShape(Capsule())
                                .overlay(
                                    Capsule()
                                        .strokeBorder(Color(.systemGray4), lineWidth: 0.5)
                                )
                            }

                            Spacer()
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                    }
                } else {
                    ContentUnavailableView(
                        "No Items",
                        systemImage: "folder",
                        description: Text("No product categories or addons configured")
                    )
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Back") {
                        if showingColorSelection {
                            withAnimation {
                                showingColorSelection = false
                                selectedModelForColors = nil
                            }
                        } else if showAddonDetails {
                            withAnimation {
                                showAddonDetails = false
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
        .onChange(of: currentStepIndex) { _, _ in
            currentProductIndex = 0
            resetAddonState()
        }
        .sheet(isPresented: $showSelectionsSummary) {
            SelectionsSummarySheet(categories: categories, addons: addons)
                .environmentObject(appState)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
    }

    // MARK: - Product Selection Methods

    private func selectProduct(_ product: Product, in category: Category) {
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

        withAnimation(.spring(response: 0.3)) {
            appState.selectProduct(for: category.categoryId, product: product)
        }

        // Auto-advance to next step
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            advanceToNextStep()
        }
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
            // Auto-advance to next step
            advanceToNextStep()
        }
    }

    // MARK: - Addon Selection Methods

    private func selectAddonNo(_ addon: Addon) {
        appState.selectAddon(addonId: addon.id, isSelected: false, quantity: 0, notes: "")
        // Auto-advance to next step
        advanceToNextStep()
    }

    private func selectAddonYes() {
        withAnimation(.spring(response: 0.3)) {
            showAddonDetails = true
        }
    }

    private func confirmAddonAndContinue(_ addon: Addon) {
        appState.selectAddon(addonId: addon.id, isSelected: true, quantity: addonQuantity, notes: addonNotes)
        advanceToNextStep()
    }

    private func resetAddonState() {
        showAddonDetails = false
        addonQuantity = 1
        addonNotes = ""

        // Load existing selection if any
        if let addon = currentAddon,
           let selection = appState.getAddonSelection(addon.id),
           selection.isSelected {
            showAddonDetails = true
            addonQuantity = selection.quantity
            addonNotes = selection.notes
        }
    }

    // MARK: - Navigation Methods

    private func skipCurrentStep() {
        advanceToNextStep()
    }

    private func goToPreviousStep() {
        if currentStepIndex > 0 {
            withAnimation {
                currentStepIndex -= 1
            }
        }
    }

    private func advanceToNextStep() {
        if currentStepIndex < totalSteps - 1 {
            withAnimation {
                currentStepIndex += 1
            }
        } else {
            // All steps completed, proceed to review
            appState.proceedToReview()
        }
    }
}

// MARK: - Product Carousel Card (Elegant Tappable Card)
struct ProductCarouselCard: View {
    let product: Product
    let isSelected: Bool
    let selectedVariant: ProductVariant?
    let showPrice: Bool
    let colorCoefficient: Double
    let onSelect: () -> Void

    /// Calculate effective price with coefficient if applicable
    private func effectivePrice(_ basePrice: Double) -> Double {
        if product.useColorCoefficient {
            return basePrice * colorCoefficient
        }
        return basePrice
    }

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

                    // Selection indicator - centered checkmark
                    if isSelected {
                        RoundedRectangle(cornerRadius: 24)
                            .strokeBorder(.green, lineWidth: 3)

                        // Centered checkmark
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 56))
                            .foregroundStyle(.green)
                            .background(
                                Circle()
                                    .fill(.white)
                                    .frame(width: 50, height: 50)
                            )
                            .shadow(color: .black.opacity(0.15), radius: 8, y: 4)
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

                    // Price display (only if showPrice is enabled)
                    if showPrice {
                        if let price = selectedVariant?.price ?? product.price {
                            Text("$\(effectivePrice(price), specifier: "%.2f")")
                                .font(.headline)
                                .foregroundStyle(.primary)
                        } else if product.hasVariants {
                            let prices = product.variants.compactMap { $0.price }
                            if let minPrice = prices.min(), let maxPrice = prices.max() {
                                let effectiveMin = effectivePrice(minPrice)
                                let effectiveMax = effectivePrice(maxPrice)
                                if effectiveMin == effectiveMax {
                                    Text("$\(effectiveMin, specifier: "%.2f")")
                                        .font(.headline)
                                        .foregroundStyle(.primary)
                                } else {
                                    Text("$\(effectiveMin, specifier: "%.0f") - $\(effectiveMax, specifier: "%.0f")")
                                        .font(.headline)
                                        .foregroundStyle(.primary)
                                }
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

    var body: some View {
        VStack(spacing: 16) {
            Text("Select Color")
                .font(.title2)
                .fontWeight(.bold)
                .padding(.top, 16)

            Text(product.name)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            ScrollView {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
                    ForEach(product.variants) { variant in
                        ColorOptionCard(
                            variant: variant,
                            showPrice: category.showPriceToCustomer,
                            onSelect: { onSelect(variant) }
                        )
                    }
                }
                .padding(.horizontal)
            }

            Button {
                onBack()
            } label: {
                Label("Change Model", systemImage: "chevron.left")
            }
            .buttonStyle(.bordered)
            .padding(.bottom)
        }
    }
}

// MARK: - Color Option Card
struct ColorOptionCard: View {
    let variant: ProductVariant
    let showPrice: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            VStack(spacing: 8) {
                // Variant image or color swatch
                ZStack {
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color(.systemGray6))

                    if let imageUrl = variant.imageUrl,
                       let url = URL(string: imageUrl) {
                        AsyncImage(url: url) { image in
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                        } placeholder: {
                            ProgressView()
                        }
                        .padding(12)
                    } else {
                        Image(systemName: "paintpalette")
                            .font(.title)
                            .foregroundStyle(.tertiary)
                    }
                }
                .aspectRatio(1, contentMode: .fit)

                Text(variant.name)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)

                if showPrice, let price = variant.price {
                    Text("$\(price, specifier: "%.2f")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(8)
            .background(Color(.systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .shadow(color: .black.opacity(0.05), radius: 4, y: 2)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Selections Summary Sheet
struct SelectionsSummarySheet: View {
    @EnvironmentObject var appState: AppState
    let categories: [Category]
    let addons: [Addon]

    var body: some View {
        NavigationStack {
            List {
                Section("Products") {
                    ForEach(categories) { category in
                        if let product = appState.selections[category.categoryId] {
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(category.name)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    Text(product.name)
                                        .font(.subheadline)
                                    if let variant = appState.getSelectedVariant(for: product) {
                                        Text(variant.name)
                                            .font(.caption)
                                            .foregroundStyle(.blue)
                                    }
                                }
                                Spacer()
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                            }
                        } else {
                            HStack {
                                Text(category.name)
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Text("Skipped")
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                    }
                }

                if !addons.isEmpty {
                    Section("Add-ons") {
                        ForEach(addons) { addon in
                            if let selection = appState.getAddonSelection(addon.id), selection.isSelected {
                                HStack {
                                    VStack(alignment: .leading) {
                                        Text(addon.question)
                                            .font(.subheadline)
                                        Text("Qty: \(selection.quantity)")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(.green)
                                }
                            } else {
                                HStack {
                                    Text(addon.question)
                                        .foregroundStyle(.secondary)
                                    Spacer()
                                    Text("No")
                                        .font(.caption)
                                        .foregroundStyle(.tertiary)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Your Selections")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

#Preview {
    SelectionView()
        .environmentObject(AppState.shared)
}

