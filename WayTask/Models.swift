import Foundation
import SwiftData

@Model
final class GeoLocation {
    var id: UUID
    var title: String
    var latitude: Double
    var longitude: Double
    var radius: Double

    @Relationship(deleteRule: .cascade)
    var shoppingItems: [ShoppingItem]

    init(
        id: UUID = UUID(),
        title: String,
        latitude: Double,
        longitude: Double,
        radius: Double = 200.0,
        shoppingItems: [ShoppingItem] = []
    ) {
        self.id = id
        self.title = title
        self.latitude = latitude
        self.longitude = longitude
        self.radius = radius
        self.shoppingItems = shoppingItems
    }
}

@Model
final class ShoppingItem {
    var id: UUID
    var name: String
    var isCompleted: Bool
    var imageData: Data?

    init(
        id: UUID = UUID(),
        name: String,
        isCompleted: Bool = false,
        imageData: Data? = nil
    ) {
        self.id = id
        self.name = name
        self.isCompleted = isCompleted
        self.imageData = imageData
    }
}//
//  Models.swift
//  WayTask
//
//  Created by Mordechai Zukerman on 27/06/2026.
//

