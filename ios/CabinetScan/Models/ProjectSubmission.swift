import Foundation

// MARK: - Project Submission
struct ProjectSubmission: Codable {
    let showroomId: String
    let customer: CustomerInfo
    let project: ProjectInfo
    let measurements: MeasurementData
    let selections: [ProductSelection]
    let deviceInfo: DeviceInfo?

    enum CodingKeys: String, CodingKey {
        case customer, project, measurements, selections
        case showroomId = "showroom_id"
        case deviceInfo = "device_info"
    }
}

// MARK: - Customer Info
struct CustomerInfo: Codable {
    let firstName: String
    let lastName: String
    let email: String
    let phone: String?
    let address: String?
    let city: String?
    let state: String?
    let zipcode: String?

    enum CodingKeys: String, CodingKey {
        case email, phone, address, city, state, zipcode
        case firstName = "first_name"
        case lastName = "last_name"
    }
}

// MARK: - Project Info
struct ProjectInfo: Codable {
    let name: String
    let notes: String?
}

// MARK: - Measurement Data
struct MeasurementData: Codable {
    let roomName: String?
    let roomType: String?
    let roomplanData: [String: AnyCodable]
    let totalLinearFt: Double?
    let totalSqFt: Double?
    let wallCount: Int?
    let windowCount: Int?
    let doorCount: Int?
    let measurements: [String: AnyCodable]?
    let usdzFileUrl: String?
    let glbFileUrl: String?
    let previewImageUrl: String?

    enum CodingKeys: String, CodingKey {
        case measurements
        case roomName = "room_name"
        case roomType = "room_type"
        case roomplanData = "roomplan_data"
        case totalLinearFt = "total_linear_ft"
        case totalSqFt = "total_sq_ft"
        case wallCount = "wall_count"
        case windowCount = "window_count"
        case doorCount = "door_count"
        case usdzFileUrl = "usdz_file_url"
        case glbFileUrl = "glb_file_url"
        case previewImageUrl = "preview_image_url"
    }
}

// MARK: - Product Selection
struct ProductSelection: Codable {
    let categoryId: String
    let productId: String
    let quantity: Int?
    let customerNotes: String?

    enum CodingKeys: String, CodingKey {
        case quantity
        case categoryId = "category_id"
        case productId = "product_id"
        case customerNotes = "customer_notes"
    }
}

// MARK: - Device Info
struct DeviceInfo: Codable {
    let model: String?
    let iosVersion: String?
    let appVersion: String?

    enum CodingKeys: String, CodingKey {
        case model
        case iosVersion = "ios_version"
        case appVersion = "app_version"
    }
}

// MARK: - Submission Response
struct SubmissionResponse: Codable {
    let success: Bool
    let projectId: String?
    let referenceNumber: String?
    let showroomName: String?
    let error: String?

    enum CodingKeys: String, CodingKey {
        case success, error
        case projectId = "project_id"
        case referenceNumber = "reference_number"
        case showroomName = "showroom_name"
    }
}
