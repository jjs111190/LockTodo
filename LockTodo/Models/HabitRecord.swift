import Foundation
import SwiftData

@Model
final class HabitRecord {
    @Attribute(.unique) var id: UUID
    var habitID: UUID
    var date: Date
    var isCompleted: Bool

    init(
        id: UUID = UUID(),
        habitID: UUID,
        date: Date = Calendar.current.startOfDay(for: .now),
        isCompleted: Bool = false
    ) {
        self.id = id
        self.habitID = habitID
        self.date = date
        self.isCompleted = isCompleted
    }
}
