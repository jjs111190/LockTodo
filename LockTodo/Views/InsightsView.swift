import SwiftUI
import SwiftData
import Charts

/// A read-only look at the data the app already collects — completions,
/// streaks, boards, tags, routines — that previously had nowhere to be seen.
/// Native Swift Charts, so it reads and animates like the rest of the system.
struct InsightsView: View {
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \TaskItem.sortOrder, order: .forward) private var allTasks: [TaskItem]
    @Query(sort: \TaskBoard.orderIndex) private var boards: [TaskBoard]
    @Query private var habits: [Habit]
    @Query private var habitRecords: [HabitRecord]
    @Query(sort: \FocusSession.startedAt, order: .reverse) private var focusSessions: [FocusSession]
    @StateObject private var proAccess = ProAccessService.shared

    @State private var range: InsightRange = .week
    @State private var showingPaywall = false

    private var calendar: Calendar { .current }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(spacing: LockTodoDesign.sectionSpacing) {
                    rangePicker
                    streakHero
                    completionChartCard
                    rateAndPeakRow
                    if periodFocusMinutes > 0 { focusCard }
                    if !boardBreakdown.isEmpty { boardBreakdownCard }
                    if !topTags.isEmpty { tagCard }
                    if !habits.filter(\.isActive).isEmpty { routineCard }
                }
                .padding(.horizontal, LockTodoDesign.pageInset)
                .padding(.top, 8)
                .padding(.bottom, 32)
            }
            .background(LockTodoDesign.pageBackground.ignoresSafeArea())
            .navigationTitle("인사이트")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("닫기") { dismiss() }
                }
            }
            .sheet(isPresented: $showingPaywall) {
                ProUpgradeView()
            }
        }
    }

    // MARK: Range

    private var rangePicker: some View {
        // Weekly is free; the monthly range is a Pro feature. Selecting it
        // without Pro opens the paywall and keeps the view on weekly.
        Picker("기간", selection: Binding(
            get: { range },
            set: { newValue in
                if newValue == .month && !proAccess.isPro {
                    showingPaywall = true
                } else {
                    withAnimation(LockTodoMotion.content) { range = newValue }
                }
            }
        )) {
            ForEach(InsightRange.allCases) { r in
                if r == .month && !proAccess.isPro {
                    Label(r.title, systemImage: "lock.fill").tag(r)
                } else {
                    Text(r.title).tag(r)
                }
            }
        }
        .pickerStyle(.segmented)
    }

    // MARK: Streak hero

    private var streakHero: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 3) {
                Text("연속 완료")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.white.opacity(0.85))
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("\(currentStreak)")
                        .font(.system(size: 40, weight: .bold))
                        .tracking(-1)
                        .monospacedDigit()
                        .contentTransition(.numericText(value: Double(currentStreak)))
                    Text("일")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.85))
                }
                .foregroundStyle(.white)

                Text(streakMessage)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.8))
            }

            Spacer(minLength: 0)

            Image(systemName: "flame.fill")
                .font(.system(size: 46))
                .foregroundStyle(.white.opacity(0.9))
                .shadow(color: .black.opacity(0.1), radius: 6, y: 3)
        }
        .padding(20)
        .background {
            RoundedRectangle(cornerRadius: LockTodoDesign.cardRadius, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: currentStreak > 0
                            ? [Color(hex: "#FF9500"), Color(hex: "#FF5E3A")]
                            : [Color(hex: "#8E8E93"), Color(hex: "#636366")],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        }
        .shadow(color: (currentStreak > 0 ? Color(hex: "#FF5E3A") : .black).opacity(0.22), radius: 16, y: 8)
    }

    private var streakMessage: String {
        if currentStreak == 0 { return "오늘 하나만 완료해도 시작됩니다" }
        if currentStreak >= 7 { return "일주일 넘게 이어지고 있어요" }
        return "흐름을 이어가는 중이에요"
    }

    // MARK: Completion chart

    private var completionChartCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            LockTodoCardHeader(
                title: "완료 추이",
                subtitle: "\(range.title) 동안 끝낸 할 일",
                systemImage: "chart.bar.fill"
            ) {
                LockTodoCountBadge(text: "\(periodCompletedTotal)개")
            }

            Chart(dailyCompletions) { point in
                BarMark(
                    x: .value("날짜", point.date, unit: .day),
                    y: .value("완료", point.count),
                    width: range == .week ? 22 : 6
                )
                .foregroundStyle(
                    LinearGradient(
                        colors: [Color.accentColor, Color.accentColor.opacity(0.65)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .cornerRadius(range == .week ? 6 : 2)
            }
            .chartYAxis {
                AxisMarks(position: .leading) { _ in
                    AxisGridLine().foregroundStyle(Color.primary.opacity(0.06))
                    AxisValueLabel()
                }
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: .day, count: range == .week ? 1 : 7)) { value in
                    AxisValueLabel(format: .dateTime.day().locale(Locale(identifier: "ko_KR")))
                }
            }
            .frame(height: 168)
            .animation(LockTodoMotion.standard, value: range)
        }
        .padding(16)
        .lockTodoCard()
    }

    // MARK: Rate + peak

    private var rateAndPeakRow: some View {
        HStack(spacing: LockTodoDesign.sectionSpacing) {
            VStack(spacing: 10) {
                ZStack {
                    ProgressRing(progress: periodCompletionRate, lineWidth: 7, showsLabel: false)
                        .frame(width: 62, height: 62)
                    Text("\(Int((periodCompletionRate * 100).rounded()))%")
                        .font(.system(size: 16, weight: .semibold))
                        .monospacedDigit()
                }
                Text("완료율")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 18)
            .lockTodoCard()

            VStack(spacing: 6) {
                Image(systemName: "calendar")
                    .font(.system(size: 22))
                    .foregroundStyle(Color.indigo)
                Text(peakWeekdayName)
                    .font(.system(size: 20, weight: .semibold))
                    .tracking(-0.4)
                Text("가장 활발한 요일")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 18)
            .lockTodoCard()
        }
    }

    // MARK: Focus time

    private var focusCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            LockTodoCardHeader(
                title: "집중 시간",
                subtitle: "\(range.title) 동안 몰입한 시간",
                systemImage: "timer"
            ) {
                LockTodoCountBadge(text: "\(periodFocusSessions)회")
            }

            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(focusHoursMinutesText)
                    .font(.system(size: 30, weight: .semibold))
                    .tracking(-0.6)
                    .monospacedDigit()
                    .contentTransition(.numericText())
                Spacer()
                if periodFocusSessions > 0 {
                    Text("평균 \(periodFocusMinutes / max(periodFocusSessions, 1))분/회")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Chart(dailyFocusMinutes) { point in
                BarMark(
                    x: .value("날짜", point.date, unit: .day),
                    y: .value("집중(분)", point.count),
                    width: range == .week ? 22 : 6
                )
                .foregroundStyle(
                    LinearGradient(colors: [Color.orange, Color.orange.opacity(0.6)],
                                   startPoint: .top, endPoint: .bottom)
                )
                .cornerRadius(range == .week ? 6 : 2)
            }
            .chartYAxis {
                AxisMarks(position: .leading) { _ in
                    AxisGridLine().foregroundStyle(Color.primary.opacity(0.06))
                    AxisValueLabel()
                }
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: .day, count: range == .week ? 1 : 7)) { _ in
                    AxisValueLabel(format: .dateTime.day().locale(Locale(identifier: "ko_KR")))
                }
            }
            .frame(height: 120)
            .animation(LockTodoMotion.standard, value: range)
        }
        .padding(16)
        .lockTodoCard()
    }

    private var focusHoursMinutesText: String {
        let m = periodFocusMinutes
        return m >= 60 ? "\(m / 60)시간 \(m % 60)분" : "\(m)분"
    }

    // MARK: Board breakdown

    private var boardBreakdownCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            LockTodoCardHeader(title: "보드별 분포", systemImage: "folder.fill", isIconFilled: false)

            VStack(spacing: 10) {
                ForEach(boardBreakdown) { item in
                    VStack(spacing: 6) {
                        HStack {
                            Text(item.name)
                                .font(.subheadline.weight(.medium))
                                .lineLimit(1)
                            Spacer()
                            Text("\(item.done)/\(item.total)")
                                .font(.caption.weight(.medium))
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule().fill(Color.primary.opacity(0.07))
                                Capsule()
                                    .fill(item.color)
                                    .frame(width: geo.size.width * item.fraction)
                            }
                        }
                        .frame(height: 7)
                    }
                }
            }
        }
        .padding(16)
        .lockTodoCard()
    }

    // MARK: Tags

    private var tagCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            LockTodoCardHeader(title: "자주 쓰는 태그", systemImage: "number", isIconFilled: false)

            FlowLayout(spacing: 8) {
                ForEach(topTags, id: \.tag) { entry in
                    HStack(spacing: 5) {
                        Text("#\(entry.tag)")
                            .font(.footnote.weight(.medium))
                        Text("\(entry.count)")
                            .font(.caption2.weight(.semibold))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 11)
                    .padding(.vertical, 7)
                    .background(Color.primary.opacity(0.05), in: Capsule())
                }
            }
        }
        .padding(16)
        .lockTodoCard()
    }

    // MARK: Routines

    private var routineCard: some View {
        let active = habits.filter(\.isActive)
        return VStack(alignment: .leading, spacing: 14) {
            LockTodoCardHeader(
                title: "루틴 꾸준함",
                subtitle: "최근 7일 달성",
                systemImage: "repeat",
                isIconFilled: false
            )

            VStack(spacing: 12) {
                ForEach(active) { habit in
                    HStack(spacing: 10) {
                        Image(systemName: habit.icon)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Color(hex: habit.colorHex))
                            .frame(width: 26, height: 26)
                            .background(Color(hex: habit.colorHex).opacity(0.14), in: Circle())

                        Text(habit.title)
                            .font(.subheadline.weight(.medium))
                            .lineLimit(1)

                        Spacer(minLength: 8)

                        HStack(spacing: 4) {
                            ForEach(last7Days, id: \.self) { day in
                                Circle()
                                    .fill(habitDone(habit, on: day) ? Color(hex: habit.colorHex) : Color.primary.opacity(0.08))
                                    .frame(width: 9, height: 9)
                            }
                        }
                    }
                }
            }
        }
        .padding(16)
        .lockTodoCard()
    }

    // MARK: - Data

    private var rangeStart: Date {
        let today = calendar.startOfDay(for: .now)
        return calendar.date(byAdding: .day, value: -(range.days - 1), to: today) ?? today
    }

    private var dailyCompletions: [DayCount] {
        let today = calendar.startOfDay(for: .now)
        return (0..<range.days).reversed().compactMap { offset -> DayCount? in
            guard let day = calendar.date(byAdding: .day, value: -offset, to: today) else { return nil }
            let count = allTasks.filter { task in
                guard let completedAt = task.completedAt else { return false }
                return calendar.isDate(completedAt, inSameDayAs: day)
            }.count
            return DayCount(date: day, count: count)
        }
    }

    private var periodCompletedTotal: Int {
        dailyCompletions.reduce(0) { $0 + $1.count }
    }

    private var periodSessions: [FocusSession] {
        focusSessions.filter { $0.startedAt >= rangeStart }
    }

    private var periodFocusSessions: Int { periodSessions.count }

    private var periodFocusMinutes: Int {
        periodSessions.reduce(0) { $0 + $1.focusedSeconds } / 60
    }

    private var dailyFocusMinutes: [DayCount] {
        let today = calendar.startOfDay(for: .now)
        return (0..<range.days).reversed().compactMap { offset -> DayCount? in
            guard let day = calendar.date(byAdding: .day, value: -offset, to: today) else { return nil }
            let seconds = focusSessions
                .filter { calendar.isDate($0.startedAt, inSameDayAs: day) }
                .reduce(0) { $0 + $1.focusedSeconds }
            return DayCount(date: day, count: seconds / 60)
        }
    }

    private var periodCompletionRate: Double {
        // Tasks that were due within the window and are done, over all that were due.
        let due = allTasks.filter { task in
            guard let date = task.displayDate else { return false }
            let day = calendar.startOfDay(for: date)
            return day >= rangeStart && day <= calendar.startOfDay(for: .now)
        }
        guard !due.isEmpty else { return 0 }
        let done = due.filter(\.isCompleted).count
        return Double(done) / Double(due.count)
    }

    private var peakWeekdayName: String {
        var counts = [Int: Int]()
        for task in allTasks {
            guard let completedAt = task.completedAt else { continue }
            let weekday = calendar.component(.weekday, from: completedAt)
            counts[weekday, default: 0] += 1
        }
        guard let best = counts.max(by: { $0.value < $1.value })?.key else { return "-" }
        let symbols = calendar.shortWeekdaySymbols
        return symbols[(best - 1) % symbols.count]
    }

    private var currentStreak: Int {
        var day = calendar.startOfDay(for: .now)
        var streak = 0
        while streak < 400 {
            let done = allTasks.contains { task in
                guard let completedAt = task.completedAt else { return false }
                return calendar.isDate(completedAt, inSameDayAs: day)
            }
            guard done else { break }
            streak += 1
            guard let prev = calendar.date(byAdding: .day, value: -1, to: day) else { break }
            day = prev
        }
        return streak
    }

    private var boardBreakdown: [BoardStat] {
        boards.compactMap { board in
            let tasks = allTasks.filter { $0.boardID == board.id }
            guard !tasks.isEmpty else { return nil }
            let done = tasks.filter(\.isCompleted).count
            return BoardStat(
                id: board.id,
                name: board.name,
                color: Color(hex: board.colorHex),
                done: done,
                total: tasks.count
            )
        }
        .sorted { $0.total > $1.total }
        .prefix(5)
        .map { $0 }
    }

    private var topTags: [(tag: String, count: Int)] {
        var counts = [String: Int]()
        for task in allTasks {
            for tag in task.tags where tag != TaskItem.lockScreenInboxTag {
                counts[tag, default: 0] += 1
            }
        }
        return counts.sorted { $0.value > $1.value }.prefix(10).map { (tag: $0.key, count: $0.value) }
    }

    private var last7Days: [Date] {
        let today = calendar.startOfDay(for: .now)
        return (0..<7).reversed().compactMap { calendar.date(byAdding: .day, value: -$0, to: today) }
    }

    private func habitDone(_ habit: Habit, on day: Date) -> Bool {
        habitRecords.contains { record in
            record.habitID == habit.id && record.isCompleted && calendar.isDate(record.date, inSameDayAs: day)
        }
    }
}

// MARK: - Support types

private enum InsightRange: String, CaseIterable, Identifiable {
    case week, month
    var id: String { rawValue }
    var title: String { self == .week ? "주간" : "월간" }
    var days: Int { self == .week ? 7 : 30 }
}

private struct DayCount: Identifiable {
    let date: Date
    let count: Int
    var id: Date { date }
}

private struct BoardStat: Identifiable {
    let id: UUID
    let name: String
    let color: Color
    let done: Int
    let total: Int
    var fraction: CGFloat { total == 0 ? 0 : CGFloat(done) / CGFloat(total) }
}

/// A minimal wrap-around layout for the tag chips — chips flow onto the next
/// line when they run out of width, like a tag cloud.
private struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth: CGFloat = proposal.width ?? .infinity
        var rowCount = 1
        var x: CGFloat = 0
        var rowHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            rowHeight = max(rowHeight, size.height)
            if x + size.width > maxWidth, x > 0 {
                rowCount += 1
                x = 0
            }
            x += size.width + spacing
        }
        let totalHeight = CGFloat(rowCount) * (rowHeight + spacing) - spacing
        return CGSize(width: maxWidth, height: totalHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
