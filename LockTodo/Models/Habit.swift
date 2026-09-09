import Foundation
import SwiftData

@Model
final class Habit {
    @Attribute(.unique) var id: UUID
    var title: String
    var icon: String // SF Symbol name
    var colorHex: String
    var isActive: Bool
    var targetFrequency: String // e.g. "daily"
    var streak: Int
    var lastRecordDate: Date?
    var createdAt: Date
    var reminderTime: Date?
    var isReminderEnabled: Bool
    var reminderOffsetMinutes: Int

    init(
        id: UUID = UUID(),
        title: String,
        icon: String = "circle",
        colorHex: String = "#0A84FF",
        isActive: Bool = true,
        targetFrequency: String = "daily",
        streak: Int = 0,
        lastRecordDate: Date? = nil,
        createdAt: Date = .now,
        reminderTime: Date? = nil,
        isReminderEnabled: Bool = false,
        reminderOffsetMinutes: Int = 0
    ) {
        self.id = id
        self.title = title
        self.icon = icon
        self.colorHex = colorHex
        self.isActive = isActive
        self.targetFrequency = targetFrequency
        self.streak = streak
        self.lastRecordDate = lastRecordDate
        self.createdAt = createdAt
        self.reminderTime = reminderTime
        self.isReminderEnabled = isReminderEnabled
        self.reminderOffsetMinutes = reminderOffsetMinutes
    }

    /// Advances the streak for a completion today: continues it if yesterday was
    /// recorded, resets to 1 after a gap, and is a no-op if today is already
    /// counted. Records the completion date so the next call can compare.
    func registerCompletionToday(calendar: Calendar = .current, now: Date = .now) {
        let today = calendar.startOfDay(for: now)
        if let lastDate = lastRecordDate {
            let lastStart = calendar.startOfDay(for: lastDate)
            if lastStart == today {
                // Already counted today.
            } else if let yesterday = calendar.date(byAdding: .day, value: -1, to: today),
                      lastStart == yesterday {
                streak += 1
            } else {
                streak = 1
            }
        } else {
            streak = 1
        }
        lastRecordDate = now
    }
}
