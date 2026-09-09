import Foundation

@MainActor
final class CalendarViewModel: ObservableObject {
    @Published var visibleMonth: Date = Calendar.current.startOfDay(for: .now)
    @Published var selectedDate: Date = Calendar.current.startOfDay(for: .now)

    private let calendar: Calendar = {
        var calendar = Calendar.current
        calendar.firstWeekday = 1
        return calendar
    }()

    var monthTitle: String {
        visibleMonth.formatted(.dateTime.year().month(.wide))
    }

    var weekdaySymbols: [String] {
        calendar.shortStandaloneWeekdaySymbols
    }

    func daysInVisibleGrid() -> [Date?] {
        daysInGrid(for: visibleMonth)
    }

    /// The 7-column day grid for any month (nil = padding cell). Parametrised so
    /// a horizontally-paging calendar can render neighbouring months.
    func daysInGrid(for month: Date) -> [Date?] {
        guard let monthInterval = calendar.dateInterval(of: .month, for: month),
              let firstWeek = calendar.dateInterval(of: .weekOfMonth, for: monthInterval.start),
              let lastWeek = calendar.dateInterval(of: .weekOfMonth, for: monthInterval.end.addingTimeInterval(-1)) else {
            return []
        }

        var days: [Date?] = []
        var cursor = firstWeek.start
        while cursor < lastWeek.end {
            if calendar.isDate(cursor, equalTo: month, toGranularity: .month) {
                days.append(cursor)
            } else {
                days.append(nil)
            }
            cursor = calendar.date(byAdding: .day, value: 1, to: cursor) ?? lastWeek.end
        }
        return days
    }

    func moveMonth(by value: Int) {
        visibleMonth = calendar.date(byAdding: .month, value: value, to: visibleMonth) ?? visibleMonth
    }

    /// Month = `base` shifted by `offset` months, normalised to the 1st — the
    /// value the paging calendar binds each page to.
    func month(byAddingMonths offset: Int, to base: Date) -> Date {
        let start = calendar.date(from: calendar.dateComponents([.year, .month], from: base)) ?? base
        return calendar.date(byAdding: .month, value: offset, to: start) ?? start
    }

    /// How many months `month` is from `base` (used to sync the pager index).
    func monthsBetween(_ base: Date, _ month: Date) -> Int {
        let b = calendar.dateComponents([.year, .month], from: base)
        let m = calendar.dateComponents([.year, .month], from: month)
        return ((m.year ?? 0) - (b.year ?? 0)) * 12 + ((m.month ?? 0) - (b.month ?? 0))
    }

    func count(on date: Date, tasks: [TaskItem]) -> Int {
        tasks.filter { $0.occurs(on: date, calendar: calendar) }.count
    }

    func completionRate(on date: Date, tasks: [TaskItem]) -> Double {
        let dayTasks = tasks.filter { $0.occurs(on: date, calendar: calendar) }
        guard !dayTasks.isEmpty else { return 0 }
        return Double(dayTasks.filter(\.isCompleted).count) / Double(dayTasks.count)
    }

    func isToday(_ date: Date) -> Bool {
        calendar.isDateInToday(date)
    }

    func isSelected(_ date: Date) -> Bool {
        calendar.isDate(date, inSameDayAs: selectedDate)
    }
}
