import Foundation
import SwiftData

enum TaskTint: String, Codable, CaseIterable, Identifiable {
    case blue = "#007AFF"
    case red = "#FF3B30"
    case orange = "#FF9500"
    case yellow = "#FFCC00"
    case green = "#34C759"
    case mint = "#00C7BE"
    case teal = "#30B0C7"
    case indigo = "#5856D6"
    case purple = "#AF52DE"
    case pink = "#FF2D55"
    case brown = "#A2845E"
    case gray = "#8E8E93"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .blue: "파랑"
        case .red: "빨강"
        case .orange: "주황"
        case .yellow: "노랑"
        case .green: "초록"
        case .mint: "민트"
        case .teal: "청록"
        case .indigo: "남색"
        case .purple: "보라"
        case .pink: "분홍"
        case .brown: "갈색"
        case .gray: "회색"
        }
    }

    static let defaultHex = TaskTint.blue.rawValue

    static func normalized(_ hex: String) -> String {
        let cleanHex = hex.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        return allCases.first { $0.rawValue == cleanHex }?.rawValue ?? defaultHex
    }
}

@Model
final class TaskItem {
    @Attribute(.unique) var id: UUID
    var title: String
    var notes: String
    var categoryRawValue: String
    var isCompleted: Bool
    var isImportant: Bool
    var colorHex: String = TaskTint.defaultHex
    var boardID: UUID?
    var createdAt: Date
    var updatedAt: Date
    var completedAt: Date?
    var dueDate: Date?
    var dueTime: Date?
    var reminderDate: Date?
    var repeatRuleRawValue: String
    var tagText: String
    var sortOrder: Double
    var locationTitle: String = ""
    var locationLatitude: Double?
    var locationLongitude: Double?
    var locationRadius: Double = 150
    var locationReminderEnabled: Bool = false
    var showOnlyAtLocation: Bool = false
    var lastLocationNotificationAt: Date?

    init(
        id: UUID = UUID(),
        title: String,
        notes: String = "",
        category: TaskCategory = .today,
        isCompleted: Bool = false,
        isImportant: Bool = false,
        colorHex: String = TaskTint.defaultHex,
        boardID: UUID? = nil,
        createdAt: Date = .now,
        updatedAt: Date = .now,
        completedAt: Date? = nil,
        dueDate: Date? = Calendar.current.startOfDay(for: .now),
        dueTime: Date? = nil,
        reminderDate: Date? = nil,
        repeatRule: RepeatRule = .none,
        tags: [String] = [],
        sortOrder: Double = Date().timeIntervalSinceReferenceDate,
        locationTitle: String = "",
        locationLatitude: Double? = nil,
        locationLongitude: Double? = nil,
        locationRadius: Double = 150,
        locationReminderEnabled: Bool = false,
        showOnlyAtLocation: Bool = false,
        lastLocationNotificationAt: Date? = nil
    ) {
        self.id = id
        self.title = title
        self.notes = notes
        self.categoryRawValue = category.rawValue
        self.isCompleted = isCompleted
        self.isImportant = isImportant
        self.colorHex = TaskTint.normalized(colorHex)
        self.boardID = boardID
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.completedAt = completedAt
        self.dueDate = dueDate
        self.dueTime = dueTime
        self.reminderDate = reminderDate
        self.repeatRuleRawValue = repeatRule.rawValue
        self.tagText = tags.joined(separator: ",")
        self.sortOrder = sortOrder
        self.locationTitle = locationTitle
        self.locationLatitude = locationLatitude
        self.locationLongitude = locationLongitude
        self.locationRadius = locationRadius
        self.locationReminderEnabled = locationReminderEnabled
        self.showOnlyAtLocation = showOnlyAtLocation
        self.lastLocationNotificationAt = lastLocationNotificationAt
    }
}

extension TaskItem {
    var category: TaskCategory {
        get { TaskCategory(rawValue: categoryRawValue) ?? .today }
        set {
            categoryRawValue = newValue.rawValue
            updatedAt = .now
        }
    }

    var repeatRule: RepeatRule {
        get { RepeatRule(rawValue: repeatRuleRawValue) ?? .none }
        set {
            repeatRuleRawValue = newValue.rawValue
            updatedAt = .now
        }
    }

    var tags: [String] {
        get {
            tagText
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        }
        set {
            tagText = newValue
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .joined(separator: ",")
            updatedAt = .now
        }
    }

    var safeColorHex: String {
        TaskTint.normalized(colorHex)
    }

    var displayDate: Date? {
        dueDate ?? category.defaultDueDate()
    }

    var hasLocationTrigger: Bool {
        locationReminderEnabled && locationLatitude != nil && locationLongitude != nil
    }

    static let lockScreenInboxTag = "잠금화면"

    var isLockScreenInboxTask: Bool {
        tags.contains { $0.caseInsensitiveCompare(Self.lockScreenInboxTag) == .orderedSame }
    }

    var locationDisplayName: String {
        let cleanTitle = locationTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        return cleanTitle.isEmpty ? "저장한 위치" : cleanTitle
    }

    static func mergedTags(_ tags: [String], adding requiredTags: [String]) -> [String] {
        var seen = Set<String>()
        var merged: [String] = []

        for tag in tags + requiredTags {
            let cleanTag = tag.trimmingCharacters(in: .whitespacesAndNewlines)
            let key = cleanTag.lowercased()
            guard !cleanTag.isEmpty, !seen.contains(key) else { continue }
            seen.insert(key)
            merged.append(cleanTag)
        }

        return merged
    }

    func removeLockScreenInboxTag() {
        tags = tags.filter { $0.caseInsensitiveCompare(Self.lockScreenInboxTag) != .orderedSame }
    }

    func occurs(on date: Date, calendar: Calendar = .current) -> Bool {
        guard category != .later else { return false }

        let targetDay = calendar.startOfDay(for: date)
        let baseDate = dueDate ?? category.defaultDueDate(calendar: calendar)
        guard let baseDate else { return false }
        let baseDay = calendar.startOfDay(for: baseDate)

        if isCompleted {
            if let completedAt, calendar.isDate(completedAt, inSameDayAs: targetDay) {
                return true
            }
            return calendar.isDate(baseDay, inSameDayAs: targetDay)
        }

        guard targetDay >= baseDay else { return false }

        switch repeatRule {
        case .none:
            return calendar.isDate(baseDay, inSameDayAs: targetDay)
        case .daily:
            return true
        case .weekdays:
            let weekday = calendar.component(.weekday, from: targetDay)
            return weekday != 1 && weekday != 7
        case .weekly:
            let days = calendar.dateComponents([.day], from: baseDay, to: targetDay).day ?? 0
            return days >= 0 && days % 7 == 0
        case .monthly:
            let months = calendar.dateComponents([.month], from: baseDay, to: targetDay).month ?? 0
            return months >= 0 && calendar.component(.day, from: baseDay) == calendar.component(.day, from: targetDay)
        }
    }

    func markCompleted(_ completed: Bool) {
        isCompleted = completed
        completedAt = completed ? .now : nil
        updatedAt = .now
    }

    func distanceInMeters(toLatitude latitude: Double, longitude: Double) -> Double? {
        guard let taskLatitude = locationLatitude, let taskLongitude = locationLongitude else {
            return nil
        }

        let earthRadius = 6_371_000.0
        let latitudeDelta = (latitude - taskLatitude) * .pi / 180
        let longitudeDelta = (longitude - taskLongitude) * .pi / 180
        let startLatitude = taskLatitude * .pi / 180
        let endLatitude = latitude * .pi / 180
        let a = sin(latitudeDelta / 2) * sin(latitudeDelta / 2)
            + cos(startLatitude) * cos(endLatitude)
            * sin(longitudeDelta / 2) * sin(longitudeDelta / 2)
        let c = 2 * atan2(sqrt(a), sqrt(1 - a))
        return earthRadius * c
    }
}
