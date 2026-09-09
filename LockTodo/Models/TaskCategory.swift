import Foundation
import AppIntents

enum TaskCategory: String, Codable, CaseIterable, Identifiable {
    case today
    case tomorrow
    case later
    case scheduled

    var id: String { rawValue }

    var title: String {
        switch self {
        case .today: "오늘"
        case .tomorrow: "내일"
        case .later: "나중에"
        case .scheduled: "예약됨"
        }
    }

    var systemImage: String {
        switch self {
        case .today: "sun.max"
        case .tomorrow: "calendar.badge.clock"
        case .later: "tray"
        case .scheduled: "calendar"
        }
    }

    func defaultDueDate(calendar: Calendar = .current, now: Date = .now) -> Date? {
        switch self {
        case .today:
            return calendar.startOfDay(for: now)
        case .tomorrow:
            return calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now))
        case .later:
            return nil
        case .scheduled:
            return calendar.startOfDay(for: now)
        }
    }
}

@available(iOS 16.0, *)
extension TaskCategory: AppEnum {
    public static var typeDisplayRepresentation: TypeDisplayRepresentation {
        "카테고리"
    }

    public static var caseDisplayRepresentations: [TaskCategory : DisplayRepresentation] {
        [
            .today: DisplayRepresentation(title: "오늘", image: .init(systemName: "sun.max")),
            .tomorrow: DisplayRepresentation(title: "내일", image: .init(systemName: "calendar.badge.clock")),
            .later: DisplayRepresentation(title: "나중에", image: .init(systemName: "tray")),
            .scheduled: DisplayRepresentation(title: "예약됨", image: .init(systemName: "calendar"))
        ]
    }
}
