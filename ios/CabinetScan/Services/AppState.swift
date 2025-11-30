import Foundation
import SwiftUI

// MARK: - App State
@MainActor
class AppState: ObservableObject {
    static let shared = AppState()

    // MARK: - Published Properties

    @Published var currentScreen: Screen = .onboarding
    @Published var showroomConfig: ShowroomConfig?
    @Published var customerInfo: CustomerInfo?
    @Published var measurementData: MeasurementData?
    @Published var selections: [String: Product] = [:] // categoryId -> selected product
    @Published var isLoading = false
    @Published var error: Error?

    // MARK: - Screen Navigation

    enum Screen {
        case onboarding
        case customerInfo
        case scanning
        case selection
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

    func setCustomerInfo(_ info: CustomerInfo) {
        customerInfo = info
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

    func selectProduct(for categoryId: String, product: Product) {
        selections[categoryId] = product
    }

    func proceedToReview() {
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
                ProductSelection(
                    categoryId: categoryId,
                    productId: product.id,
                    quantity: 1,
                    customerNotes: nil
                )
            }

            let submission = ProjectSubmission(
                showroomId: config.id,
                customer: customer,
                project: ProjectInfo(
                    name: "Room Scan",
                    notes: nil
                ),
                measurements: measurements,
                selections: projectSelections,
                deviceInfo: DeviceInfo(
                    model: deviceModel,
                    iosVersion: UIDevice.current.systemVersion,
                    appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
                )
            )

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
        measurementData = nil
        selections = [:]
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
