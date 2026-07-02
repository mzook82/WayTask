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

    init(
        id: UUID = UUID(),
        startedAt: Date = Date(),
        finishedAt: Date? = nil,
        isActive: Bool = true,
        itemIDs: [UUID] = [],
        collectedItemIDs: [UUID] = []
    ) {
        self.id = id
        self.startedAt = startedAt
        self.finishedAt = finishedAt
        self.isActive = isActive
        self.itemIDListRawValue = Self.encode(itemIDs)
        self.collectedItemIDListRawValue = Self.encode(collectedItemIDs)
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
