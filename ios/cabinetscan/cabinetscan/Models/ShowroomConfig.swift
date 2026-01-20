import Foundation

// MARK: - Showroom Configuration
struct ShowroomConfig: Codable, Identifiable {
    let id: String
    let name: String
    let showroomCode: String
    let branding: Branding
    let categories: [Category]
    let addons: [Addon]
    let subscription: SubscriptionInfo?
    let aiChatbot: AIChatbotConfig?

    enum CodingKeys: String, CodingKey {
        case id, name, branding, categories, addons, subscription
        case showroomCode = "showroom_code"
        case aiChatbot = "ai_chatbot"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        showroomCode = try container.decode(String.self, forKey: .showroomCode)
        branding = try container.decode(Branding.self, forKey: .branding)
        categories = try container.decode([Category].self, forKey: .categories)
        addons = try container.decodeIfPresent([Addon].self, forKey: .addons) ?? []
        subscription = try container.decodeIfPresent(SubscriptionInfo.self, forKey: .subscription)
        aiChatbot = try container.decodeIfPresent(AIChatbotConfig.self, forKey: .aiChatbot)
    }
}

// MARK: - AI Chatbot Config
struct AIChatbotConfig: Codable {
    let enabled: Bool
    let assistantName: String
    let assistantAvatarUrl: String?

    enum CodingKeys: String, CodingKey {
        case enabled
        case assistantName = "assistant_name"
        case assistantAvatarUrl = "assistant_avatar_url"
    }
}

// MARK: - Addon
struct Addon: Codable, Identifiable {
    let id: String
    let question: String
    let description: String?
    let unit: String
    let pricePerUnit: Double?
    let imageUrl: String?
    let displayOrder: Int
    let useColorCoefficient: Bool
    let showPriceToCustomer: Bool

    enum CodingKeys: String, CodingKey {
        case id, question, description, unit
        case pricePerUnit = "price_per_unit"
        case imageUrl = "image_url"
        case displayOrder = "display_order"
        case useColorCoefficient = "use_color_coefficient"
        case showPriceToCustomer = "show_price_to_customer"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        question = try container.decode(String.self, forKey: .question)
        description = try container.decodeIfPresent(String.self, forKey: .description)
        unit = try container.decode(String.self, forKey: .unit)
        pricePerUnit = try container.decodeIfPresent(Double.self, forKey: .pricePerUnit)
        imageUrl = try container.decodeIfPresent(String.self, forKey: .imageUrl)
        displayOrder = try container.decode(Int.self, forKey: .displayOrder)
        useColorCoefficient = try container.decodeIfPresent(Bool.self, forKey: .useColorCoefficient) ?? false
        showPriceToCustomer = try container.decodeIfPresent(Bool.self, forKey: .showPriceToCustomer) ?? false
    }
}

// MARK: - Subscription Info
struct SubscriptionInfo: Codable {
    let status: String
    let plan: String?
    let videoCapture: ShowroomVideoCaptureSettings?

    enum CodingKeys: String, CodingKey {
        case status, plan
        case videoCapture = "video_capture"
    }
}

// MARK: - Video Capture Settings
struct ShowroomVideoCaptureSettings: Codable {
    let enabled: Bool
    let maxDurationSeconds: Int
    let maxSizeMb: Int

    enum CodingKeys: String, CodingKey {
        case enabled
        case maxDurationSeconds = "max_duration_seconds"
        case maxSizeMb = "max_size_mb"
    }
}

// MARK: - Branding
struct Branding: Codable {
    let logoUrl: String?
    let logoDarkUrl: String?

    enum CodingKeys: String, CodingKey {
        case logoUrl = "logo_url"
        case logoDarkUrl = "logo_dark_url"
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
    let showPriceToCustomer: Bool
    let products: [Product]

    enum CodingKeys: String, CodingKey {
        case id, name, slug, description, products
        case categoryId = "category_id"
        case pricingUnit = "pricing_unit"
        case iconName = "icon_name"
        case displayOrder = "display_order"
        case isRequired = "is_required"
        case showPriceToCustomer = "show_price_to_customer"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        categoryId = try container.decode(String.self, forKey: .categoryId)
        name = try container.decode(String.self, forKey: .name)
        slug = try container.decode(String.self, forKey: .slug)
        description = try container.decodeIfPresent(String.self, forKey: .description)
        pricingUnit = try container.decode(PricingUnit.self, forKey: .pricingUnit)
        iconName = try container.decodeIfPresent(String.self, forKey: .iconName)
        displayOrder = try container.decode(Int.self, forKey: .displayOrder)
        isRequired = try container.decode(Bool.self, forKey: .isRequired)
        showPriceToCustomer = try container.decodeIfPresent(Bool.self, forKey: .showPriceToCustomer) ?? false
        products = try container.decode([Product].self, forKey: .products)
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
    let hasVariants: Bool
    let useColorCoefficient: Bool
    let variants: [ProductVariant]

    enum CodingKeys: String, CodingKey {
        case id, name, description, price, specifications, variants
        case imageUrl = "image_url"
        case thumbnailUrl = "thumbnail_url"
        case displayOrder = "display_order"
        case isFeatured = "is_featured"
        case hasVariants = "has_variants"
        case useColorCoefficient = "use_color_coefficient"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        description = try container.decodeIfPresent(String.self, forKey: .description)
        price = try container.decodeIfPresent(Double.self, forKey: .price)
        imageUrl = try container.decodeIfPresent(String.self, forKey: .imageUrl)
        thumbnailUrl = try container.decodeIfPresent(String.self, forKey: .thumbnailUrl)
        displayOrder = try container.decode(Int.self, forKey: .displayOrder)
        isFeatured = try container.decode(Bool.self, forKey: .isFeatured)
        specifications = try container.decodeIfPresent([String: AnyCodable].self, forKey: .specifications)
        hasVariants = try container.decodeIfPresent(Bool.self, forKey: .hasVariants) ?? false
        useColorCoefficient = try container.decodeIfPresent(Bool.self, forKey: .useColorCoefficient) ?? false
        variants = try container.decodeIfPresent([ProductVariant].self, forKey: .variants) ?? []
    }
}

// MARK: - Product Variant (Color)
struct ProductVariant: Codable, Identifiable {
    let id: String
    let name: String
    let colorCode: String?
    let price: Double?
    let priceCoefficient: Double
    let imageUrl: String?
    let thumbnailUrl: String?
    let displayOrder: Int
    let isDefault: Bool

    enum CodingKeys: String, CodingKey {
        case id, name, price
        case colorCode = "color_code"
        case priceCoefficient = "price_coefficient"
        case imageUrl = "image_url"
        case thumbnailUrl = "thumbnail_url"
        case displayOrder = "display_order"
        case isDefault = "is_default"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        colorCode = try container.decodeIfPresent(String.self, forKey: .colorCode)
        price = try container.decodeIfPresent(Double.self, forKey: .price)
        priceCoefficient = try container.decodeIfPresent(Double.self, forKey: .priceCoefficient) ?? 1.0
        imageUrl = try container.decodeIfPresent(String.self, forKey: .imageUrl)
        thumbnailUrl = try container.decodeIfPresent(String.self, forKey: .thumbnailUrl)
        displayOrder = try container.decode(Int.self, forKey: .displayOrder)
        isDefault = try container.decode(Bool.self, forKey: .isDefault)
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
        case let float as Float:
            // Handle non-finite Float values (NaN, Infinity) - JSON doesn't support these
            if float.isFinite {
                try container.encode(Double(float))
            } else {
                try container.encode(0.0)
            }
        case let double as Double:
            // Handle non-finite Double values (NaN, Infinity) - JSON doesn't support these
            if double.isFinite {
                try container.encode(double)
            } else {
                try container.encode(0.0)
            }
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
