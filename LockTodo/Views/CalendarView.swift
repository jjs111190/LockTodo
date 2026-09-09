import SwiftUI
import SwiftData
import UIKit

struct CalendarView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \TaskItem.sortOrder, order: .forward) private var allTasks: [TaskItem]

    @ObservedObject var taskViewModel: TaskViewModel
    @ObservedObject private var locationService = LocationReminderService.shared
    @StateObject private var calendarViewModel = CalendarViewModel()
    @State private var selectedTask: TaskItem?
    @State private var isAddTaskPresented = false
    /// The month the pager measures its offsets from (fixed at first appear).
    @State private var baseMonth = Calendar.current.date(
        from: Calendar.current.dateComponents([.year, .month], from: .now)
    ) ?? Calendar.current.startOfDay(for: .now)
    /// Current page = month offset from `baseMonth`.
    @State private var pageIndex = 0
    /// ±10 years of pageable months.
    private let pageRange = -120...120

    /// Vertical scroll offset (0 at top, negative as you scroll down). Scrolling
    /// down collapses the summary so the calendar rises and fills more space.
    @State private var scrollOffset: CGFloat = 0
    private var collapse: CGFloat { min(max(-scrollOffset / 90, 0), 1) }
    /// Approximate natural height of the summary card, used only while collapsing.
    private let summaryExpandedHeight: CGFloat = 62

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 0), count: 7)

    private var nearbyLocationTaskIDs: Set<UUID> {
        Set(locationService.nearbyTasks(from: allTasks).map(\.id))
    }

    private var calendarVisibleTasks: [TaskItem] {
        allTasks.filter { task in
            !task.showOnlyAtLocation || task.isCompleted || nearbyLocationTaskIDs.contains(task.id)
        }
    }

    private var selectedTasks: [TaskItem] {
        taskViewModel.tasks(on: calendarViewModel.selectedDate, from: calendarVisibleTasks)
    }

    private var monthDays: [Date] {
        calendarViewModel.daysInVisibleGrid().compactMap { $0 }
    }

    private var visibleMonthTasks: [TaskItem] {
        return calendarVisibleTasks.filter { task in
            monthDays.contains { task.occurs(on: $0) }
        }
    }

    private var activeMonthTasks: [TaskItem] {
        visibleMonthTasks.filter { !$0.isCompleted }
    }

    private var completedMonthTasks: [TaskItem] {
        visibleMonthTasks.filter(\.isCompleted)
    }

    private var visibleMonthLocationTaskCount: Int {
        activeMonthTasks.filter(\.hasLocationTrigger).count
    }

    private var monthCompletionRate: Double {
        guard !visibleMonthTasks.isEmpty else { return 1 }
        return Double(completedMonthTasks.count) / Double(visibleMonthTasks.count)
    }

    private var busiestMonthDay: (date: Date, count: Int)? {
        let rankedDays = monthDays.compactMap { date -> (date: Date, count: Int)? in
            let count = calendarViewModel.count(on: date, tasks: calendarVisibleTasks)
            return count > 0 ? (date, count) : nil
        }

        return rankedDays.sorted { lhs, rhs in
            if lhs.count != rhs.count { return lhs.count > rhs.count }
            return lhs.date < rhs.date
        }.first
    }

    private var nextEmptyMonthDay: Date? {
        let today = Calendar.current.startOfDay(for: .now)
        let futureEmptyDay = monthDays.first { date in
            date >= today && calendarViewModel.count(on: date, tasks: calendarVisibleTasks) == 0
        }

        return futureEmptyDay ?? monthDays.first { date in
            calendarViewModel.count(on: date, tasks: calendarVisibleTasks) == 0
        }
    }

    private var calendarBriefingSubtitle: String {
        if activeMonthTasks.isEmpty {
            return "이번 달 할 일이 모두 정리됐습니다"
        }

        if let busiestMonthDay {
            return "\(busiestMonthDay.date.formatted(.dateTime.month().day()))에 \(busiestMonthDay.count)개 집중"
        }

        return "이번 달 일정을 한눈에 정리"
    }

    private var selectedWeekDays: [Date] {
        let calendar = Calendar.current
        guard let weekInterval = calendar.dateInterval(of: .weekOfYear, for: calendarViewModel.selectedDate) else {
            return []
        }

        return (0..<7).compactMap {
            calendar.date(byAdding: .day, value: $0, to: weekInterval.start)
        }
    }

    private var selectedWeekTasks: [TaskItem] {
        selectedWeekDays.flatMap { date in
            taskViewModel.tasks(on: date, from: calendarVisibleTasks)
        }
    }

    private var selectedWeekActiveCount: Int {
        selectedWeekTasks.filter { !$0.isCompleted }.count
    }

    private var selectedWeekCompletedCount: Int {
        selectedWeekTasks.filter(\.isCompleted).count
    }

    private var selectedWeekBusiestDay: (date: Date, count: Int)? {
        selectedWeekDays
            .map { ($0, calendarViewModel.count(on: $0, tasks: calendarVisibleTasks)) }
            .filter { $0.1 > 0 }
            .sorted { lhs, rhs in
                if lhs.1 != rhs.1 { return lhs.1 > rhs.1 }
                return lhs.0 < rhs.0
            }
            .first
    }

    private var selectedWeekLightDay: Date? {
        selectedWeekDays
            .filter { $0 >= Calendar.current.startOfDay(for: .now) }
            .sorted { lhs, rhs in
                let lhsCount = calendarViewModel.count(on: lhs, tasks: calendarVisibleTasks)
                let rhsCount = calendarViewModel.count(on: rhs, tasks: calendarVisibleTasks)
                if lhsCount != rhsCount { return lhsCount < rhsCount }
                return lhs < rhs
            }
            .first
    }

    private var selectedWeekRangeTitle: String {
        guard let first = selectedWeekDays.first, let last = selectedWeekDays.last else {
            return "이번 주"
        }

        return "\(first.formatted(.dateTime.month().day())) - \(last.formatted(.dateTime.month().day()))"
    }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 6) {
                    Color.clear
                        .frame(height: 0)
                        .background(GeometryReader { geo in
                            Color.clear.preference(
                                key: CalScrollOffsetKey.self,
                                value: geo.frame(in: .named("calScroll")).minY
                            )
                        })

                    calendarHeader
                        .padding(.bottom, 4)

                    // Collapsing summary: shrinks and fades as you scroll down,
                    // giving the calendar the freed space. A fixed collapse
                    // height (not a measured one) keeps this out of any layout
                    // feedback loop between the frame and its measured size.
                    calendarCompactSummary
                        .frame(height: collapse < 0.01 ? nil : summaryExpandedHeight * (1 - collapse), alignment: .top)
                        .scaleEffect(1 - collapse * 0.04, anchor: .top)
                        .opacity(1 - collapse)
                        .clipped()
                        .padding(.bottom, 8 * (1 - collapse))

                    weekdayHeader
                        .padding(.bottom, 2)
                    monthPager

                    selectedDateSummary
                        .padding(.top, 4)

                    VStack(spacing: 10) {
                        ForEach(selectedTasks) { task in
                            TaskRow(
                                task: task,
                                onToggle: {
                                    taskViewModel.toggle(task, context: modelContext, occurrenceDate: calendarViewModel.selectedDate)
                                },
                                onDelete: {
                                    taskViewModel.delete(task, context: modelContext)
                                },
                                onFocus: {
                                    taskViewModel.setFocus(task, allTasks: allTasks)
                                },
                                onEdit: { selectedTask = task }
                            )
                            .onTapGesture { selectedTask = task }
                        }

                        if selectedTasks.isEmpty {
                            ContentUnavailableView("할 일 없음", systemImage: "calendar", description: Text("선택한 날짜에 추가된 할 일이 없습니다."))
                                .padding(.vertical, 20)
                        }
                    }
                }
                .padding(.horizontal, LockTodoDesign.pageInset)
                .padding(.top, 4)
                .padding(.bottom, 92)
            }
            .coordinateSpace(name: "calScroll")
            .onPreferenceChange(CalScrollOffsetKey.self) { value in
                scrollOffset = value
            }
            .background(LockTodoDesign.pageBackground.ignoresSafeArea())
            .navigationTitle("달력")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        isAddTaskPresented = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("선택한 날짜에 할 일 추가")
                }
            }
            .task {
                locationService.start()
                locationService.syncMonitoredTasks(allTasks: allTasks)
            }
            .sheet(isPresented: $isAddTaskPresented) {
                AddTaskView(
                    viewModel: taskViewModel,
                    initialDate: Calendar.current.startOfDay(for: calendarViewModel.selectedDate),
                    autoFocus: true
                )
            }
            .sheet(item: $selectedTask) { task in
                TaskDetailView(task: task, viewModel: taskViewModel, allTasks: allTasks)
            }
        }
    }

    // A horizontally-paging month view: swipe/scroll left or right and the
    // month grid pages through like the system Calendar. `pageIndex` is the
    // month offset from `baseMonth`; it and `visibleMonth` stay in sync.
    private var monthPager: some View {
        TabView(selection: $pageIndex) {
            ForEach(pageRange, id: \.self) { offset in
                monthDayGrid(for: calendarViewModel.month(byAddingMonths: offset, to: baseMonth))
                    .tag(offset)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .frame(height: 336) // fixed so 5- and 6-week months page cleanly
        .onChange(of: pageIndex) { _, newValue in
            let month = calendarViewModel.month(byAddingMonths: newValue, to: baseMonth)
            if calendarViewModel.monthsBetween(baseMonth, calendarViewModel.visibleMonth) != newValue {
                calendarViewModel.visibleMonth = month
            }
        }
        // External month jumps (오늘 / 가벼운 날 / 빈 날) move visibleMonth; mirror
        // that back into the pager so the page slides to match.
        .onChange(of: calendarViewModel.visibleMonth) { _, month in
            let target = calendarViewModel.monthsBetween(baseMonth, month)
            if target != pageIndex {
                withAnimation(LockTodoMotion.standard) { pageIndex = target }
            }
        }
        .onAppear {
            pageIndex = calendarViewModel.monthsBetween(baseMonth, calendarViewModel.visibleMonth)
        }
    }

    private func monthDayGrid(for month: Date) -> some View {
        LazyVGrid(columns: columns, spacing: 2) {
            ForEach(Array(calendarViewModel.daysInGrid(for: month).enumerated()), id: \.offset) { _, date in
                CalendarDayCell(
                    date: date,
                    count: date.map { calendarViewModel.count(on: $0, tasks: calendarVisibleTasks) } ?? 0,
                    completionRate: date.map { calendarViewModel.completionRate(on: $0, tasks: calendarVisibleTasks) } ?? 0,
                    isToday: date.map(calendarViewModel.isToday) ?? false,
                    isSelected: date.map(calendarViewModel.isSelected) ?? false
                )
                .onTapGesture {
                    if let date {
                        calendarViewModel.selectedDate = date
                    }
                }
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private func changeMonth(by delta: Int) {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        let next = min(max(pageIndex + delta, pageRange.lowerBound), pageRange.upperBound)
        withAnimation(LockTodoMotion.standard) { pageIndex = next }
    }

    private var calendarHeader: some View {
        HStack {
            // The month name is the anchor of this screen, so it gets title
            // weight and the arrows stay quiet beside it.
            Text(calendarViewModel.monthTitle)
                .font(.title2.weight(.semibold))
                .tracking(-0.5)
                .contentTransition(.numericText())

            Spacer()

            HStack(spacing: 2) {
                Button {
                    changeMonth(by: -1)
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 15, weight: .semibold))
                        .frame(width: 36, height: 36)
                        .contentShape(Circle())
                }
                .buttonStyle(TactileButtonStyle(pressedScale: 0.86))
                .accessibilityLabel("이전 달")

                Button {
                    changeMonth(by: 1)
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 15, weight: .semibold))
                        .frame(width: 36, height: 36)
                        .contentShape(Circle())
                }
                .buttonStyle(TactileButtonStyle(pressedScale: 0.86))
                .accessibilityLabel("다음 달")
            }
        }
        .padding(.horizontal, 2)
        .lockTodoAnimation(LockTodoMotion.standard, value: calendarViewModel.monthTitle)
    }

    private var calendarCompactSummary: some View {
        HStack(spacing: 8) {
            CalendarInsightMetric(title: "남음", value: "\(activeMonthTasks.count)", tint: .accentColor)
            CalendarInsightMetric(title: "완료", value: "\(completedMonthTasks.count)", tint: .green)
            CalendarInsightMetric(title: "이번 주", value: "\(selectedWeekActiveCount)", tint: .indigo)

            Spacer(minLength: 4)

            ProgressRing(progress: monthCompletionRate, lineWidth: 4, showsLabel: false)
                .frame(width: 30, height: 30)
                .accessibilityLabel("월간 완료율")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .lockTodoCard(radius: LockTodoDesign.tileRadius, elevation: .flat)
    }

    private var calendarBriefingCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            LockTodoCardHeader(
                title: "월간 브리핑",
                subtitle: calendarBriefingSubtitle,
                systemImage: "calendar.badge.checkmark"
            ) {
                ProgressRing(progress: monthCompletionRate, lineWidth: 5, showsLabel: false)
                    .frame(width: 34, height: 34)
            }

            HStack(spacing: 8) {
                CalendarInsightMetric(title: "남은 일", value: "\(activeMonthTasks.count)", tint: .accentColor)
                CalendarInsightMetric(title: "완료", value: "\(completedMonthTasks.count)", tint: .green)
                CalendarInsightMetric(title: "위치", value: "\(visibleMonthLocationTaskCount)", tint: .purple)
            }

            HStack(spacing: 8) {
                Button {
                    focusToday()
                } label: {
                    Label("오늘", systemImage: "location.fill")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 3)
                }
                .buttonStyle(.bordered)
                .buttonBorderShape(.capsule)

                Button {
                    focusNextEmptyDay()
                } label: {
                    Label("빈 날 찾기", systemImage: "calendar.badge.plus")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 3)
                }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.capsule)
                .disabled(nextEmptyMonthDay == nil)
            }
            .font(.footnote.weight(.semibold))
        }
        .padding(16)
        .lockTodoCard()
    }

    private var selectedWeekDigestCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            LockTodoCardHeader(
                title: "주간 다이제스트",
                subtitle: selectedWeekRangeTitle,
                systemImage: "chart.bar.doc.horizontal",
                tint: .indigo
            ) {
                if let selectedWeekBusiestDay {
                    LockTodoCountBadge(text: "\(selectedWeekBusiestDay.count)개 집중", tint: .indigo)
                }
            }

            HStack(spacing: 8) {
                CalendarInsightMetric(title: "이번 주 남음", value: "\(selectedWeekActiveCount)", tint: .indigo)
                CalendarInsightMetric(title: "완료", value: "\(selectedWeekCompletedCount)", tint: .green)
                CalendarInsightMetric(title: "가벼운 날", value: selectedWeekLightDayText, tint: .orange)
            }

            if let selectedWeekBusiestDay {
                Label(
                    "\(selectedWeekBusiestDay.date.formatted(.dateTime.weekday(.wide).month().day()))에 할 일이 가장 많습니다.",
                    systemImage: "exclamationmark.circle"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 8) {
                Button {
                    focusLightWeekDay()
                } label: {
                    Label("가벼운 날 보기", systemImage: "sparkles")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 3)
                }
                .buttonStyle(.bordered)
                .buttonBorderShape(.capsule)
                .disabled(selectedWeekLightDay == nil)

                Button {
                    isAddTaskPresented = true
                } label: {
                    Label("선택일 추가", systemImage: "plus")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 3)
                }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.capsule)
            }
            .font(.footnote.weight(.semibold))
        }
        .padding(16)
        .lockTodoCard()
    }

    private var weekdayHeader: some View {
        LazyVGrid(columns: columns, spacing: 0) {
            ForEach(calendarViewModel.weekdaySymbols, id: \.self) { symbol in
                Text(symbol)
                    .font(.caption)
                    .tracking(0.2)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(.bottom, 2)
    }

    private var selectedDateSummary: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(calendarViewModel.selectedDate.formatted(.dateTime.weekday(.wide).month().day()))
                    .font(.system(size: 17, weight: .semibold))
                    .tracking(-0.3)
                    .contentTransition(.opacity)
                Text("\(selectedTasks.filter { !$0.isCompleted }.count)개 남음")
                    .font(.subheadline)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            Spacer()
            ProgressRing(
                progress: calendarViewModel.completionRate(on: calendarViewModel.selectedDate, tasks: calendarVisibleTasks),
                lineWidth: 5
            )
            .frame(width: 42, height: 42)
        }
        .padding(14)
        .lockTodoCard(radius: LockTodoDesign.tileRadius, elevation: .flat)
        .lockTodoAnimation(LockTodoMotion.standard, value: calendarViewModel.selectedDate)
    }

    private var selectedWeekLightDayText: String {
        guard let selectedWeekLightDay else { return "-" }
        return selectedWeekLightDay.formatted(.dateTime.weekday(.abbreviated))
    }

    private func focusToday() {
        let today = Calendar.current.startOfDay(for: .now)
        withAnimation(.snappy) {
            calendarViewModel.visibleMonth = today
            calendarViewModel.selectedDate = today
        }
    }

    private func focusNextEmptyDay() {
        guard let nextEmptyMonthDay else { return }
        withAnimation(.snappy) {
            calendarViewModel.selectedDate = nextEmptyMonthDay
        }
    }

    private func focusLightWeekDay() {
        guard let selectedWeekLightDay else { return }
        withAnimation(.snappy) {
            calendarViewModel.visibleMonth = selectedWeekLightDay
            calendarViewModel.selectedDate = selectedWeekLightDay
        }
    }
}

private struct CalScrollOffsetKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

private struct CalendarInsightMetric: View {
    var title: String
    var value: String
    var tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption2)
                .tracking(0.1)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
            Text(value)
                .font(.system(size: 18, weight: .semibold))
                .tracking(-0.3)
                .foregroundStyle(tint)
                .monospacedDigit()
                .contentTransition(.numericText())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .lockTodoTile()
        .lockTodoAnimation(LockTodoMotion.standard, value: value)
    }
}
