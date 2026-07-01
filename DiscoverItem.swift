import Foundation

enum DiscoverCategory: String, CaseIterable, Codable, Identifiable, Sendable {
    case nearbyToday = "Nearby Today"
    case forYou = "For You"
    case basedOnYourList = "Based on Your List"
    case newAroundYou = "New Around You"

    var id: String {
        rawValue
    }
}

enum DiscoverSourceType: String, Codable, Sendable {
    case localSample
    case shoppingContext
    case savedStore
    case futureRecommendation
}

struct DiscoverItem: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    let title: String
    let subtitle: String
    let category: DiscoverCategory
    let distance: String?
    let systemImageName: String?
    let relevanceReason: String
    let sourceType: DiscoverSourceType
    let relatedStoreID: UUID?
    let canOpenMap: Bool

    init(
        id: UUID = UUID(),
        title: String,
        subtitle: String,
        category: DiscoverCategory,
        distance: String? = nil,
        systemImageName: String? = nil,
        relevanceReason: String,
        sourceType: DiscoverSourceType,
        relatedStoreID: UUID? = nil,
        canOpenMap: Bool = false
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.category = category
        self.distance = distance
        self.systemImageName = systemImageName
        self.relevanceReason = relevanceReason
        self.sourceType = sourceType
        self.relatedStoreID = relatedStoreID
        self.canOpenMap = canOpenMap
    }
}
