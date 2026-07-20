import Foundation
import SwiftData

@Model
final class ShoppingSession {
    var id: UUID
    var startedAt: Date
    var finishedAt: Date?
    var isActive: Bool
    var itemIDListRawValue: String
    var collectedItemIDListRawValue: String
    var shoppingListID: UUID?
    var selectedStoreID: UUID?
    var selectedStoreName: String?
    var selectedStoreLatitude: Double?
    var selectedStoreLongitude: Double?

    init(
        id: UUID = UUID(),
        startedAt: Date = Date(),
        finishedAt: Date? = nil,
        isActive: Bool = true,
        itemIDs: [UUID] = [],
        collectedItemIDs: [UUID] = [],
        shoppingListID: UUID? = nil,
        selectedStoreID: UUID? = nil,
        selectedStoreName: String? = nil,
        selectedStoreLatitude: Double? = nil,
        selectedStoreLongitude: Double? = nil
    ) {
        self.id = id
        self.startedAt = startedAt
        self.finishedAt = finishedAt
        self.isActive = isActive
        self.itemIDListRawValue = Self.encode(itemIDs)
        self.collectedItemIDListRawValue = Self.encode(collectedItemIDs)
        self.shoppingListID = shoppingListID
        self.selectedStoreID = selectedStoreID
        self.selectedStoreName = selectedStoreName
        self.selectedStoreLatitude = selectedStoreLatitude
        self.selectedStoreLongitude = selectedStoreLongitude
    }

    var itemIDs: [UUID] {
        get { Self.decode(itemIDListRawValue) }
        set { itemIDListRawValue = Self.encode(newValue) }
    }

    var collectedItemIDs: [UUID] {
        get { Self.decode(collectedItemIDListRawValue) }
        set { collectedItemIDListRawValue = Self.encode(newValue) }
    }

    var remainingItemCount: Int {
        max(itemIDs.count - collectedItemIDs.count, 0)
    }

    func containsItem(_ item: ShoppingItem) -> Bool {
        itemIDs.contains(item.id)
    }

    func isCollected(_ item: ShoppingItem) -> Bool {
        collectedItemIDs.contains(item.id)
    }

    private static func encode(_ ids: [UUID]) -> String {
        ids.map(\.uuidString).joined(separator: ",")
    }

    private static func decode(_ rawValue: String) -> [UUID] {
        rawValue
            .split(separator: ",")
            .compactMap { UUID(uuidString: String($0)) }
    }
}
