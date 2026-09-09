import Foundation
import SwiftData

@Model
final class TaskBoard {
    @Attribute(.unique) var id: UUID
    var name: String
    var icon: String // SF Symbol name
    var colorHex: String // Color representing the board
    var orderIndex: Int
    var isPinnedToLockScreen: Bool
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        icon: String = "list.bullet",
        colorHex: String = "#0A84FF",
        orderIndex: Int = 0,
        isPinnedToLockScreen: Bool = false,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.name = name
        self.icon = icon
        self.colorHex = colorHex
        self.orderIndex = orderIndex
        self.isPinnedToLockScreen = isPinnedToLockScreen
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
