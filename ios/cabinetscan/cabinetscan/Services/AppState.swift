import Foundation
import SwiftUI
import Combine

// MARK: - App State
@MainActor
class AppState: ObservableObject {
    static let shared = AppState()

    // MARK: - Published Properties

    @Published var currentScreen: Screen = .onboarding
    @Published var showroomConfig: ShowroomConfig?
    @Published var customerInfo: CustomerInfo?
    @Published var endClientInfo: EndClientInfo?
    @Published var measurementData: MeasurementData?
    @Published var selections: [String: Product] = [:] // categoryId -> selected product
    @Published var variantSelections: [String: ProductVariant] = [:] // productId -> selected variant (for products with colors)
    // Addon selections: addonId -> (isSelected, quantity, notes)
    @Published var addonSelections: [String: (isSelected: Bool, quantity: Int, notes: String)] = [:]
    @Published var specialRequests: String = "" // Additional notes/special requests from customer
    @Published var isLoading = false
    @Published var error: Error?

    // MARK: - Screen Navigation

    enum Screen {
        case onboarding
        case customerInfo
        case scanning
        case selection
        case addons
        case review
        case submission
        case success(referenceNumber: String)
    }

    // MARK: - Actions

    func loadShowroom(code: String) async {
        isLoading = true
        error = nil

        do {
            let config = try await APIService.shared.fetchShowroomConfig(code: code)
            showroomConfig = config
            currentScreen = .customerInfo

            // Cache the config for offline use
            cacheShowroomConfig(config)
        } catch {
            self.error = error
        }

        isLoading = false
    }

    func setCustomerInfo(_ info: CustomerInfo, endClient: EndClientInfo? = nil) {
        customerInfo = info
        endClientInfo = endClient
        currentScreen = .scanning
    }

    func setMeasurementData(_ data: MeasurementData) {
        measurementData = data

        // Skip selection page if no categories available
        let categories = showroomConfig?.categories ?? []
        if categories.isEmpty {
            currentScreen = .review
        } else {
            currentScreen = .selection
        }
    }

    func selectProduct(for categoryId: String, product: Product, variant: ProductVariant? = nil) {
        selections[categoryId] = product
        // Store variant selection if provided
        if let variant = variant {
            variantSelections[product.id] = variant
        } else {
            // Clear any previous variant selection for this product
            variantSelections.removeValue(forKey: product.id)
        }
    }

    func selectVariant(for product: Product, variant: ProductVariant) {
        variantSelections[product.id] = variant
    }

    func getSelectedVariant(for product: Product) -> ProductVariant? {
        return variantSelections[product.id]
    }

    func selectAddon(addonId: String, isSelected: Bool, quantity: Int = 1, notes: String = "") {
        addonSelections[addonId] = (isSelected: isSelected, quantity: quantity, notes: notes)
    }

    func updateAddonQuantity(addonId: String, quantity: Int) {
        if var selection = addonSelections[addonId] {
            selection.quantity = quantity
            addonSelections[addonId] = selection
        }
    }

    func updateAddonNotes(addonId: String, notes: String) {
        if var selection = addonSelections[addonId] {
            selection.notes = notes
            addonSelections[addonId] = selection
        }
    }

    func isAddonSelected(_ addonId: String) -> Bool {
        return addonSelections[addonId]?.isSelected ?? false
    }

    func getAddonSelection(_ addonId: String) -> (isSelected: Bool, quantity: Int, notes: String)? {
        return addonSelections[addonId]
    }

    func proceedToReview() {
        // Check if there are active addons to show
        let addons = showroomConfig?.addons ?? []
        if !addons.isEmpty {
            currentScreen = .addons
        } else {
            currentScreen = .review
        }
    }

    func proceedFromAddons() {
        currentScreen = .review
    }

    func submitProject() async {
        guard let config = showroomConfig,
              let customer = customerInfo,
              let measurements = measurementData else {
            error = APIError.invalidRequest
            return
        }

        isLoading = true
        error = nil
        currentScreen = .submission

        do {
            let projectSelections = selections.map { categoryId, product in
                let variantId = variantSelections[product.id]?.id
                return ProductSelection(
                    categoryId: categoryId,
                    productId: product.id,
                    variantId: variantId,
                    quantity: 1,
                    customerNotes: nil
                )
            }

            // Build addon selections (only include addons that were answered)
            let projectAddonSelections = addonSelections.map { addonId, selection in
                AddonSelection(
                    addonId: addonId,
                    isSelected: selection.isSelected,
                    quantity: selection.isSelected ? selection.quantity : 0,
                    customerNotes: selection.notes.isEmpty ? nil : selection.notes
                )
            }

            let submission = ProjectSubmission(
                showroomId: config.id,
                customer: customer,
                endClient: endClientInfo,
                project: ProjectInfo(
                    name: "Room Scan",
                    notes: specialRequests.isEmpty ? nil : specialRequests
                ),
                measurements: measurements,
                selections: projectSelections,
                addonSelections: projectAddonSelections,
                deviceInfo: DeviceInfo(
                    model: deviceModel,
                    iosVersion: UIDevice.current.systemVersion,
                    appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
                )
            )

            print("🚀 [AppState] Submitting project with \(measurements.visualizationPhotoUrls?.count ?? 0) visualization photos")
            print("🚀 [AppState] Photo URLs: \(measurements.visualizationPhotoUrls ?? [])")

            let response = try await APIService.shared.submitProject(submission)

            if let referenceNumber = response.referenceNumber {
                currentScreen = .success(referenceNumber: referenceNumber)
            } else {
                throw APIError.submissionFailed(message: "No reference number received")
            }
        } catch {
            self.error = error
            currentScreen = .review
        }

        isLoading = false
    }

    func reset() {
        currentScreen = .onboarding
        showroomConfig = nil
        customerInfo = nil
        endClientInfo = nil
        measurementData = nil
        selections = [:]
        variantSelections = [:]
        addonSelections = [:]
        specialRequests = ""
        error = nil
    }

    // MARK: - Private Helpers

    private var deviceModel: String {
        var systemInfo = utsname()
        uname(&systemInfo)
        let machineMirror = Mirror(reflecting: systemInfo.machine)
        return machineMirror.children.reduce("") { identifier, element in
            guard let value = element.value as? Int8, value != 0 else { return identifier }
            return identifier + String(UnicodeScalar(UInt8(value)))
        }
    }

    private func cacheShowroomConfig(_ config: ShowroomConfig) {
        // Save to UserDefaults for offline access
        if let encoded = try? JSONEncoder().encode(config) {
            UserDefaults.standard.set(encoded, forKey: "cached_showroom_\(config.showroomCode)")
        }
    }

    func loadCachedConfig(code: String) -> ShowroomConfig? {
        guard let data = UserDefaults.standard.data(forKey: "cached_showroom_\(code)"),
              let config = try? JSONDecoder().decode(ShowroomConfig.self, from: data) else {
            return nil
        }
        return config
    }
}
