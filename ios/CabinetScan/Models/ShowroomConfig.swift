import Foundation

// MARK: - Showroom Configuration
struct ShowroomConfig: Codable, Identifiable {
    let id: String
    let name: String
    let showroomCode: String
    let branding: Branding
    let categories: [Category]

    enum CodingKeys: String, CodingKey {
        case id, name, branding, categories
        case showroomCode = "showroom_code"
    }
}

// MARK: - Branding
struct Branding: Codable {
    let logoUrl: String?
    let logoDarkUrl: String?
    let primaryColor: String
    let secondaryColor: String
    let accentColor: String
    let backgroundColor: String
    let textColor: String
    let welcomeMessage: String?
    let thankYouMessage: String?
    let termsUrl: String?
    let privacyUrl: String?

    enum CodingKeys: String, CodingKey {
        case logoUrl = "logo_url"
        case logoDarkUrl = "logo_dark_url"
        case primaryColor = "primary_color"
        case secondaryColor = "secondary_color"
        case accentColor = "accent_color"
        case backgroundColor = "background_color"
        case textColor = "text_color"
        case welcomeMessage = "welcome_message"
        case thankYouMessage = "thank_you_message"
        case termsUrl = "terms_url"
        case privacyUrl = "privacy_url"
    }
}

// MARK: - Category
struct Category: Codable, Identifiable {
    let id: String
    let categoryId: String
    let name: String
    let slug: String
    let description: String?
    let pricingUnit: PricingUnit
    let iconName: String?
    let displayOrder: Int
    let isRequired: Bool
    let products: [Product]

    enum CodingKeys: String, CodingKey {
        case id, name, slug, description, products
        case categoryId = "category_id"
        case pricingUnit = "pricing_unit"
        case iconName = "icon_name"
        case displayOrder = "display_order"
        case isRequired = "is_required"
    }
}

// MARK: - Product
struct Product: Codable, Identifiable {
    let id: String
    let name: String
    let description: String?
    let price: Double?
    let imageUrl: String?
    let thumbnailUrl: String?
    let displayOrder: Int
    let isFeatured: Bool
    let specifications: [String: AnyCodable]?

    enum CodingKeys: String, CodingKey {
        case id, name, description, price, specifications
        case imageUrl = "image_url"
        case thumbnailUrl = "thumbnail_url"
        case displayOrder = "display_order"
        case isFeatured = "is_featured"
    }
}

// MARK: - Pricing Unit
enum PricingUnit: String, Codable {
    case perLinearFt = "per_linear_ft"
    case perSqFt = "per_sq_ft"
    case perPiece = "per_piece"
    case perCabinet = "per_cabinet"
    case flat = "flat"
    case none = "none"

    var displayName: String {
        switch self {
        case .perLinearFt: return "per linear ft"
        case .perSqFt: return "per sq ft"
        case .perPiece: return "per piece"
        case .perCabinet: return "per cabinet"
        case .flat: return "flat rate"
        case .none: return ""
        }
    }
}

// MARK: - AnyCodable for flexible JSON
struct AnyCodable: Codable {
    let value: Any

    init(_ value: Any) {
        self.value = value
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if let bool = try? container.decode(Bool.self) {
            value = bool
        } else if let int = try? container.decode(Int.self) {
            value = int
        } else if let double = try? container.decode(Double.self) {
            value = double
        } else if let string = try? container.decode(String.self) {
            value = string
        } else if let array = try? container.decode([AnyCodable].self) {
            value = array.map { $0.value }
        } else if let dict = try? container.decode([String: AnyCodable].self) {
            value = dict.mapValues { $0.value }
        } else {
            value = NSNull()
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()

        switch value {
        case let bool as Bool:
            try container.encode(bool)
        case let int as Int:
            try container.encode(int)
        case let double as Double:
            try container.encode(double)
        case let string as String:
            try container.encode(string)
        case let array as [Any]:
            try container.encode(array.map { AnyCodable($0) })
        case let dict as [String: Any]:
            try container.encode(dict.mapValues { AnyCodable($0) })
        default:
            try container.encodeNil()
        }
    }
}
