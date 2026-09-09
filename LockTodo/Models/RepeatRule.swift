import Foundation

enum RepeatRule: String, Codable, CaseIterable, Identifiable {
    case none
    case daily
    case weekdays
    case weekly
    case monthly

    var id: String { rawValue }

    var title: String {
        switch self {
        case .none: "반복 없음"
        case .daily: "매일"
        case .weekdays: "평일"
        case .weekly: "매주"
        case .monthly: "매월"
        }
    }
}
