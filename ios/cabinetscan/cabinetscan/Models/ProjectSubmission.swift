import Foundation

// MARK: - Customer Type
enum CustomerType: String, Codable, CaseIterable {
    case homeowner
    case contractor

    var displayName: String {
        switch self {
        case .homeowner: return "Homeowner"
        case .contractor: return "Contractor"
        }
    }
}

// MARK: - Project Submission
struct ProjectSubmission: Codable {
    let showroomId: String
    let customer: CustomerInfo
    let endClient: EndClientInfo?
    let project: ProjectInfo
    let measurements: MeasurementData
    let selections: [ProductSelection]
    let addonSelections: [AddonSelection]
    let deviceInfo: DeviceInfo?

    enum CodingKeys: String, CodingKey {
        case customer, project, measurements, selections
        case showroomId = "showroom_id"
        case endClient = "end_client"
        case addonSelections = "addon_selections"
        case deviceInfo = "device_info"
    }
}

// MARK: - Customer Info
struct CustomerInfo: Codable {
    let firstName: String
    let lastName: String
    let email: String
    let phone: String  // Now required
    let customerType: CustomerType
    let addressLine1: String?
    let city: String?
    let state: String?
    let zipCode: String?

    enum CodingKeys: String, CodingKey {
        case email, phone, city, state
        case firstName = "first_name"
        case lastName = "last_name"
        case customerType = "customer_type"
        case addressLine1 = "address_line1"
        case zipCode = "zip_code"
    }
}

// MARK: - End Client Info (for contractors)
struct EndClientInfo: Codable {
    let firstName: String?
    let lastName: String?
    let phone: String?
    let email: String?
    let address: String?

    enum CodingKeys: String, CodingKey {
        case phone, email, address
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
    // Video capture fields
    let videoUrl: String?
    let videoThumbnailUrl: String?
    let videoDurationSeconds: Int?
    let videoSizeBytes: Int64?
    let videoResolution: String?
    let videoFormat: String?
    // Visualization photos (multiple angles - up to 5 photos)
    var visualizationPhotoUrls: [String]?

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
        case videoUrl = "video_url"
        case videoThumbnailUrl = "video_thumbnail_url"
        case videoDurationSeconds = "video_duration_seconds"
        case videoSizeBytes = "video_size_bytes"
        case videoResolution = "video_resolution"
        case videoFormat = "video_format"
        case visualizationPhotoUrls = "visualization_photo_urls"
    }
}

// MARK: - Product Selection
struct ProductSelection: Codable {
    let categoryId: String
    let productId: String
    let variantId: String?  // For products with color variants
    let quantity: Int?
    let customerNotes: String?

    enum CodingKeys: String, CodingKey {
        case quantity
        case categoryId = "category_id"
        case productId = "product_id"
        case variantId = "variant_id"
        case customerNotes = "customer_notes"
    }
}

// MARK: - Addon Selection
struct AddonSelection: Codable {
    let addonId: String
    let isSelected: Bool
    let quantity: Int
    let customerNotes: String?

    enum CodingKeys: String, CodingKey {
        case quantity
        case addonId = "addon_id"
        case isSelected = "is_selected"
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
