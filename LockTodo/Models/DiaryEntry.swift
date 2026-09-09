import Foundation
import SwiftData

@Model
final class DiaryEntry {
    @Attribute(.unique) var id: UUID
    var date: Date
    var moodRawValue: String // Mood emoji or string representation
    var content: String
    var completedTaskCount: Int
    var totalTaskCount: Int
    var createdAt: Date

    init(
        id: UUID = UUID(),
        date: Date = .now,
        moodRawValue: String,
        content: String,
        completedTaskCount: Int = 0,
        totalTaskCount: Int = 0,
        createdAt: Date = .now
    ) {
        self.id = id
        self.date = date
        self.moodRawValue = moodRawValue
        self.content = content
        self.completedTaskCount = completedTaskCount
        self.totalTaskCount = totalTaskCount
        self.createdAt = createdAt
    }
}
