import Foundation

struct BuyingOption: Identifiable, Equatable {
    let id: UUID
    let title: String
    let subtitle: String
    let optionType: BuyingOptionType
    let storeName: String
    let distanceText: String
    let priceText: String?
    let websiteURL: URL?
    let confidenceLabel: String?
    let source: DataSourceType
    let ranking: StoreScore?
    let recommendationReasons: [String]

    init(
        id: UUID = UUID(),
        title: String,
        subtitle: String,
        optionType: BuyingOptionType,
        storeName: String,
        distanceText: String,
        priceText: String? = nil,
        websiteURL: URL? = nil,
        confidenceLabel: String? = nil,
        source: DataSourceType,
        ranking: StoreScore? = nil,
        recommendationReasons: [String] = []
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.optionType = optionType
        self.storeName = storeName
        self.distanceText = distanceText
        self.priceText = priceText
        self.websiteURL = websiteURL
        self.confidenceLabel = confidenceLabel
        self.source = source
        self.ranking = ranking
        self.recommendationReasons = recommendationReasons
    }
}

enum BuyingOptionType: String, CaseIterable, Identifiable, Codable, Sendable {
    case nearbyStore
    case onlineStore
    case suggestedStore
    case futurePriceComparison

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .nearbyStore:
            return "Nearby Store"
        case .onlineStore:
            return "Online Store"
        case .suggestedStore:
            return "Suggested Store"
        case .futurePriceComparison:
            return "Price Comparison"
        }
    }
}
