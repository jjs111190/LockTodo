import SwiftUI
import SwiftData
import WidgetKit

private enum TodayToolPanel: String, CaseIterable, Identifiable {
    case status
    case smart
    case lockAndLocation
    case routine

    var id: Self { self }

    var title: String {
        switch self {
        case .status: "상태"
        case .smart: "스마트 정리"
        case .lockAndLocation: "잠금화면·위치"
        case .routine: "루틴·기록"
        }
    }

    var systemImage: String {
        switch self {
        case .status: "chart.bar.fill"
        case .smart: "wand.and.sparkles"
        case .lockAndLocation: "lock.fill"
        case .routine: "square.grid.2x2.fill"
        }
    }
}

struct TodayView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var router: AppRouter
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Query(sort: \TaskItem.sortOrder, order: .forward) private var allTasks: [TaskItem]
    @Query(sort: \TaskBoard.orderIndex) private var boards: [TaskBoard]
    @Query(sort: \Habit.createdAt, order: .forward) private var habits: [Habit]
    @Query private var habitRecords: [HabitRecord]
    @Query(sort: \DiaryEntry.date, order: .reverse) private var diaries: [DiaryEntry]

    @ObservedObject var viewModel: TaskViewModel
    @StateObject private var liveActivityService = LiveActivityService.shared
    @StateObject private var proAccess = ProAccessService.shared
    @ObservedObject private var locationService = LocationReminderService.shared
    @State private var selectedCategory: TaskCategory = .today
    @State private var selectedTask: TaskItem?
    @State private var carryoverMessage = ""
    @State private var showsCarryoverResult = false
    @State private var plannerMessage = ""
    @State private var showsPlannerResult = false
    @State private var smartActionMessage = ""
    @State private var showsSmartActionResult = false

    @State private var selectedBoardID: UUID? = nil
    @State private var showingBoardList = false
    @State private var showingDiaryWrite = false
    @State private var selectedFocusHabit: Habit? = nil
    @State private var showingHabitManagement = false
    @State private var refreshID = UUID()
    @State private var isDailyReviewExpanded = false
    @State private var isToolsHubExpanded = false
    @State private var selectedToolPanel: TodayToolPanel = .status
    @State private var isPatrolAnimating = false

    @State private var searchText = ""
    @State private var selectedFilter: TaskFilter = .all
    @State private var newQuickTaskTitle = ""

    @State private var showingInsights = false
    @State private var showingProUpgrade = false
    @EnvironmentObject private var toastCenter: LockTodoToastCenter

    @Namespace private var categoryNamespace

    @State private var isSelectionMode = false
    @State private var selectedTaskIDs = Set<UUID>()
    @State private var showingDeleteAllConfirmation = false
    @State private var showingDeleteSelectedConfirmation = false

    private var displayedTasks: [TaskItem] {
        let baseTasks: [TaskItem]
        switch selectedCategory {
        case .today:
            baseTasks = mergedTodayTasksWithNearbyLocationTasks(todayAndMissedTasks)
        case .tomorrow:
            let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: .now)) ?? .now
            baseTasks = viewModel.tasks(on: tomorrow, from: allTasks).filter(isVisibleInTodoList)
        case .later:
            baseTasks = viewModel.laterTasks(from: allTasks).filter(isVisibleInTodoList)
        case .scheduled:
            baseTasks = allTasks
                .filter { $0.category == .scheduled && isVisibleInTodoList($0) }
                .sorted { $0.sortOrder < $1.sortOrder }
        }

        if let selectedBoardID {
            return baseTasks.filter { $0.boardID == selectedBoardID }
        } else {
            return baseTasks
        }
    }

    private var todayAndMissedTasks: [TaskItem] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)

        return allTasks
            .filter { task in
                guard task.category != .later, isVisibleInTodoList(task) else { return false }
                return task.occurs(on: today, calendar: calendar)
            }
            .sorted(by: dateAwareTaskSort)
    }

    private var filteredDisplayedTasks: [TaskItem] {
        var tasks = displayedTasks
        
        if !searchText.isEmpty {
            tasks = tasks.filter {
                $0.title.localizedCaseInsensitiveContains(searchText) ||
                $0.notes.localizedCaseInsensitiveContains(searchText) ||
                $0.locationDisplayName.localizedCaseInsensitiveContains(searchText)
            }
        }
        
        switch selectedFilter {
        case .all:
            break
        case .active:
            tasks = tasks.filter { !$0.isCompleted }
        case .starred:
            tasks = tasks.filter { $0.isImportant }
        }
        
        return tasks
    }

    private var activeTasks: [TaskItem] {
        filteredDisplayedTasks.filter { !$0.isCompleted }
    }

    private var completedTasks: [TaskItem] {
        filteredDisplayedTasks.filter(\.isCompleted)
    }

    private var activeTaskDateSections: [TaskDateSection] {
        makeTaskDateSections(from: activeTasks)
    }

    private var completedTaskDateSections: [TaskDateSection] {
        makeTaskDateSections(from: completedTasks)
    }

    private var nearbyLocationTasks: [TaskItem] {
        locationService.nearbyTasks(from: allTasks)
    }

    private var nearbyLocationTaskIDs: Set<UUID> {
        Set(nearbyLocationTasks.map(\.id))
    }

    private var mapLocationTasks: [TaskItem] {
        allTasks
            .filter { task in
                task.hasLocationTrigger
                    && (task.isCompleted || nearbyLocationTaskIDs.contains(task.id))
            }
            .sorted { lhs, rhs in
                let lhsNearby = nearbyLocationTaskIDs.contains(lhs.id)
                let rhsNearby = nearbyLocationTaskIDs.contains(rhs.id)
                if lhsNearby != rhsNearby { return lhsNearby }
                if lhs.isCompleted != rhs.isCompleted { return !lhs.isCompleted }
                if lhs.isImportant != rhs.isImportant { return lhs.isImportant }

                if let lhsDistance = distanceFromCurrentLocation(to: lhs),
                   let rhsDistance = distanceFromCurrentLocation(to: rhs),
                   lhsDistance != rhsDistance {
                    return lhsDistance < rhsDistance
                }

                return lhs.sortOrder < rhs.sortOrder
            }
    }

    private var lockScreenInboxTasks: [TaskItem] {
        allTasks
            .filter { !$0.isCompleted && $0.isLockScreenInboxTask && isVisibleInTodoList($0) }
            .sorted { lhs, rhs in
                if lhs.isImportant != rhs.isImportant { return lhs.isImportant }
                if let lhsTime = lhs.dueTime, let rhsTime = rhs.dueTime, lhsTime != rhsTime { return lhsTime < rhsTime }
                return lhs.updatedAt > rhs.updatedAt
            }
    }

    private var dayPlannerTimedTasks: [TaskItem] {
        displayedTasks
            .filter { !$0.isCompleted && $0.dueTime != nil }
            .sorted(by: dayPlannerTimedSort)
    }

    private var dayPlannerSchedulableTasks: [TaskItem] {
        displayedTasks
            .filter { !$0.isCompleted && $0.dueTime == nil && !$0.showOnlyAtLocation }
            .sorted(by: dayPlannerTaskSort)
    }

    private var dayPlannerLocationOnlyCount: Int {
        allTasks.filter {
            !$0.isCompleted
                && $0.hasLocationTrigger
                && $0.showOnlyAtLocation
                && nearbyLocationTaskIDs.contains($0.id)
        }.count
    }

    private var laterPullableCount: Int {
        allTasks.filter { !$0.isCompleted && $0.category == .later }.count
    }

    private var upcomingImportantCandidateCount: Int {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: today) ?? today

        return allTasks.filter { task in
            guard !task.isCompleted, !task.isImportant, task.category != .later else { return false }
            if task.hasLocationTrigger { return true }
            guard let dueDate = task.dueDate else { return false }
            return calendar.startOfDay(for: dueDate) <= tomorrow
        }.count
    }

    private var todayReviewTaskExists: Bool {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        return allTasks.contains { task in
            task.title == "오늘 마무리 리뷰" && task.occurs(on: today, calendar: calendar)
        }
    }

    private var commandCenterSubtitle: String {
        if let smartPlan {
            return "추천 시작: \(smartPlan.primaryTask.title)"
        }

        if laterPullableCount > 0 {
            return "나중에 둔 할 일을 오늘로 가져올 수 있어요"
        }

        if upcomingImportantCandidateCount > 0 {
            return "곧 필요한 할 일을 중요 표시로 묶을 수 있어요"
        }

        return "잠금화면에 올릴 오늘 흐름을 정리"
    }

    private var todayMotivation: LockTodoMotivation {
        if activeTasks.isEmpty && !displayedTasks.isEmpty {
            return LockTodoMotivation(
                title: "오늘 목록 완료",
                message: "끝낸 기록은 잠금화면 진행률과 연속 기록에 바로 반영됩니다.",
                systemImage: "checkmark.seal.fill",
                tint: .green,
                actionTitle: "완료 항목 보기"
            )
        }

        if completionStreak >= 3 {
            return LockTodoMotivation(
                title: "\(completionStreak)일 연속 기록 중",
                message: "오늘도 하나만 완료해도 흐름은 이어집니다.",
                systemImage: "flame.fill",
                tint: .orange,
                actionTitle: "하나 시작"
            )
        }

        if let smartPlan {
            return LockTodoMotivation(
                title: "지금은 작은 시작이 좋습니다",
                message: "추천된 '\(smartPlan.primaryTask.title)'부터 실시간 현황으로 시작해 보세요.",
                systemImage: "sparkles",
                tint: Color(hex: smartPlan.primaryTask.safeColorHex),
                actionTitle: "집중 시작"
            )
        }

        return LockTodoMotivation(
            title: "잠금화면에 오늘을 올려두세요",
            message: "앱을 열지 않아도 해야 할 일을 바로 확인할 수 있습니다.",
            systemImage: "lock.fill",
            tint: .accentColor,
            actionTitle: liveActivityService.isRunning ? "고정 해제" : "지금 고정"
        )
    }

    private var shouldShowDayPlanner: Bool {
        !activeTasks.isEmpty || !dayPlannerTimedTasks.isEmpty || dayPlannerLocationOnlyCount > 0
    }

    private var nextTimedTask: TaskItem? {
        dayPlannerTimedTasks.first { task in
            guard let date = dueDateTimeForToday(task) else { return false }
            return date >= .now
        } ?? dayPlannerTimedTasks.first
    }

    private var nextActionTask: TaskItem? {
        if let smartPlan {
            return smartPlan.primaryTask
        }

        if let nextTimedTask {
            return nextTimedTask
        }

        return activeTasks.first
    }

    private var smartPlan: LockTodoSmartPlan? {
        let candidates = displayedTasks.filter { !$0.isCompleted }
        guard !candidates.isEmpty else { return nil }

        let rankedTasks = candidates
            .map { task in
                (
                    task: task,
                    score: smartPlanScore(for: task, nearbyTaskIDs: nearbyLocationTaskIDs),
                    reason: smartPlanReason(for: task, nearbyTaskIDs: nearbyLocationTaskIDs)
                )
            }
            .sorted { lhs, rhs in
                if lhs.score != rhs.score { return lhs.score > rhs.score }
                if lhs.task.isImportant != rhs.task.isImportant { return lhs.task.isImportant }
                return lhs.task.sortOrder < rhs.task.sortOrder
            }

        guard let primary = rankedTasks.first else { return nil }

        return LockTodoSmartPlan(
            primaryTask: primary.task,
            queue: rankedTasks.prefix(3).map(\.task),
            reason: primary.reason,
            dueSoonCount: candidates.filter(isDueSoonForSmartPlan).count,
            importantCount: candidates.filter(\.isImportant).count,
            nearbyCount: candidates.filter { nearbyLocationTaskIDs.contains($0.id) }.count,
            totalActiveCount: candidates.count,
            estimatedFocusMinutes: estimatedFocusMinutes(for: primary.task)
        )
    }

    private func mergedTodayTasksWithNearbyLocationTasks(_ todayTasks: [TaskItem]) -> [TaskItem] {
        var seenIDs = Set<UUID>()
        var mergedTasks: [TaskItem] = []

        for task in todayTasks + nearbyLocationTasks {
            guard !seenIDs.contains(task.id) else { continue }
            seenIDs.insert(task.id)
            mergedTasks.append(task)
        }

        return mergedTasks
    }

    private func makeTaskDateSections(from tasks: [TaskItem]) -> [TaskDateSection] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: tasks) { task in
            sectionDate(for: task, calendar: calendar)
        }

        return grouped
            .map { date, tasks in
                TaskDateSection(
                    date: date,
                    title: titleForTaskDate(date, calendar: calendar),
                    isMissed: isMissedDate(date, calendar: calendar) && tasks.contains { !$0.isCompleted },
                    tasks: tasks.sorted(by: dateAwareTaskSort)
                )
            }
            .sorted { lhs, rhs in
                switch (lhs.date, rhs.date) {
                case let (lhsDate?, rhsDate?):
                    if !calendar.isDate(lhsDate, inSameDayAs: rhsDate) {
                        return lhsDate < rhsDate
                    }
                    return lhs.title < rhs.title
                case (_?, nil):
                    return true
                case (nil, _?):
                    return false
                case (nil, nil):
                    return lhs.title < rhs.title
                }
            }
    }

    private func sectionDate(for task: TaskItem, calendar: Calendar = .current) -> Date? {
        if let dueDate = task.dueDate {
            return calendar.startOfDay(for: dueDate)
        }
        return task.category.defaultDueDate(calendar: calendar).map { calendar.startOfDay(for: $0) }
    }

    private func titleForTaskDate(_ date: Date?, calendar: Calendar = .current) -> String {
        guard let date else { return "날짜 없음" }
        let today = calendar.startOfDay(for: .now)
        if calendar.isDate(date, inSameDayAs: today) { return "오늘" }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: today),
           calendar.isDate(date, inSameDayAs: yesterday) {
            return "어제"
        }
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: today),
           calendar.isDate(date, inSameDayAs: tomorrow) {
            return "내일"
        }
        return date.formatted(.dateTime.month().day().weekday(.abbreviated))
    }

    private func isMissedDate(_ date: Date?, calendar: Calendar = .current) -> Bool {
        guard let date else { return false }
        return calendar.startOfDay(for: date) < calendar.startOfDay(for: .now)
    }

    private func dateAwareTaskSort(_ lhs: TaskItem, _ rhs: TaskItem) -> Bool {
        let calendar = Calendar.current
        let lhsDate = sectionDate(for: lhs, calendar: calendar) ?? .distantFuture
        let rhsDate = sectionDate(for: rhs, calendar: calendar) ?? .distantFuture
        if !calendar.isDate(lhsDate, inSameDayAs: rhsDate) {
            return lhsDate < rhsDate
        }
        if lhs.isCompleted != rhs.isCompleted { return !lhs.isCompleted }
        if lhs.isImportant != rhs.isImportant { return lhs.isImportant }
        if let lhsTime = lhs.dueTime, let rhsTime = rhs.dueTime, lhsTime != rhsTime { return lhsTime < rhsTime }
        return lhs.sortOrder < rhs.sortOrder
    }

    private func isVisibleInTodoList(_ task: TaskItem) -> Bool {
        if task.isCompleted {
            return true
        }

        return !task.showOnlyAtLocation || nearbyLocationTaskIDs.contains(task.id)
    }

    private func distanceFromCurrentLocation(to task: TaskItem) -> Double? {
        guard let coordinate = locationService.currentLocation?.coordinate else { return nil }
        return task.distanceInMeters(
            toLatitude: coordinate.latitude,
            longitude: coordinate.longitude
        )
    }

    private var progress: Double {
        guard !displayedTasks.isEmpty else { return 1 }
        let completedInBase = displayedTasks.filter(\.isCompleted).count
        return Double(completedInBase) / Double(displayedTasks.count)
    }

    var body: some View {
        NavigationStack {
            todayScrollView
            .id(refreshID)
            .background(appBackground)
            // The large title names what you are actually looking at, so it
            // follows the selected category instead of being a fixed label
            // repeated again further down the page.
            .navigationTitle(selectedCategory.title)
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                todayToolbar
            }
            .safeAreaInset(edge: .bottom) {
                bottomBar
            }
            .sheet(isPresented: router.addTaskBinding) {
                AddTaskView(
                    viewModel: viewModel,
                    initialDate: router.addTaskInitialDate,
                    prefillTitle: router.addTaskPrefillTitle,
                    autoFocus: true
                )
            }
            .sheet(item: $selectedTask) { task in
                TaskDetailView(task: task, viewModel: viewModel, allTasks: allTasks)
            }
            .sheet(isPresented: $showingBoardList) {
                BoardListView()
            }
            .sheet(isPresented: $showingDiaryWrite) {
                DiaryWriteView(completedTaskCount: completedTasks.count, totalTaskCount: displayedTasks.count)
            }
            .sheet(item: $selectedFocusHabit) { habit in
                HabitFocusTimerView(habit: habit)
            }
            .sheet(isPresented: $showingHabitManagement) {
                HabitManagementView()
            }
            .sheet(isPresented: $showingInsights) {
                InsightsView()
            }
            .sheet(isPresented: $showingProUpgrade) {
                ProUpgradeView()
            }
            .task {
                modelContext.rollback()
                viewModel.seedIfNeeded(context: modelContext)
                viewModel.autoUpdateTaskCategories(context: modelContext)
                locationService.start()
                locationService.syncMonitoredTasks(allTasks: allTasks)
            }
            .alert("선택한 할 일 삭제", isPresented: $showingDeleteSelectedConfirmation) {
                Button("취소", role: .cancel) {}
                Button("삭제", role: .destructive) {
                    deleteSelectedTasks()
                }
            } message: {
                Text("선택한 \(selectedTaskIDs.count)개의 할 일을 정말 삭제하시겠습니까?")
            }
            .alert("모든 할 일 삭제", isPresented: $showingDeleteAllConfirmation) {
                Button("취소", role: .cancel) {}
                Button("모든 할 일 삭제", role: .destructive) {
                    deleteAllDisplayedTasks()
                }
            } message: {
                Text("현재 화면에 표시된 모든 할 일을 정말 삭제하시겠습니까? 이 작업은 되돌릴 수 없습니다.")
            }
            .onReceive(NotificationCenter.default.publisher(for: .lockTodoDatabaseChangedExternal)) { _ in
                let currentDBCount = WidgetDataStore.dbChangeCounter
                let lastLocalCount = WidgetDataStore.lastLocalChangeCount
                guard currentDBCount > lastLocalCount else { return }
                
                WidgetDataStore.lastLocalChangeCount = currentDBCount
                let context = modelContext
                context.rollback()
                viewModel.refresh(context: context)
                withAnimation(.snappy) {
                    refreshID = UUID()
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
                let context = modelContext
                context.rollback()
                viewModel.refresh(context: context)
                locationService.start()
                locationService.syncMonitoredTasks(allTasks: allTasks)
                withAnimation(.snappy) {
                    refreshID = UUID()
                }
            }
            .onAppear {
                modelContext.rollback()
                viewModel.autoUpdateTaskCategories(context: modelContext)
                locationService.start()
                locationService.syncMonitoredTasks(allTasks: allTasks)
                router.consumePendingShortcutIfNeeded()
            }
            .onChange(of: router.pendingTaskID) { _, newValue in
                guard let targetID = newValue else { return }
                if let task = allTasks.first(where: { $0.id == targetID }) {
                    selectedTask = task
                    router.pendingTaskID = nil
                }
            }
            .onChange(of: sharedStateFingerprint) { _, _ in
                viewModel.refreshSharedState(allTasks: allTasks)
            }
            .alert("미완료 유지", isPresented: $showsCarryoverResult) {
                Button("확인", role: .cancel) {}
            } message: {
                Text(carryoverMessage)
            }
            .alert("오늘 시간표", isPresented: $showsPlannerResult) {
                Button("확인", role: .cancel) {}
            } message: {
                Text(plannerMessage)
            }
            .alert("스마트 정리", isPresented: $showsSmartActionResult) {
                Button("확인", role: .cancel) {}
            } message: {
                Text(smartActionMessage)
            }
        }
    }

    private var todayScrollView: some View {
        ScrollView(showsIndicators: false) {
            todayContent
                .padding(.horizontal, LockTodoDesign.pageInset)
                .padding(.top, 4)
                .padding(.bottom, 96)
        }
    }

    @ViewBuilder
    private var todayContent: some View {
        VStack(spacing: LockTodoDesign.sectionSpacing) {
            todayOverviewCard
                .tutorialHighlightAnchor(.overview)

            categorySelector
            titleAndBoardRow
            taskSections

            if selectedCategory == .today {
                todayToolsHub
            } else if !mapLocationTasks.isEmpty {
                mapLocationTasksCard
            }
        }
    }

    private var todayOverviewCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .center, spacing: 8) {
                Text(todayHeroDateText)
                    .font(.subheadline.weight(.semibold))
                    .tracking(-0.2)
                    .foregroundStyle(.secondary)

                Spacer(minLength: 4)

                if completionStreak > 0 {
                    streakBadge(completionStreak)
                }
            }

            HStack(alignment: .top, spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(todayOverviewTitle)
                        .font(.title3.weight(.semibold))
                        .tracking(-0.4)
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(todayOverviewSubtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 4)

                LockTodoIconActionButton(
                    systemImage: liveActivityService.isRunning ? "pin.fill" : "pin",
                    accessibilityLabel: liveActivityService.isRunning ? "잠금화면 고정 해제" : "잠금화면 고정",
                    prominence: liveActivityService.isRunning ? .primary : .secondary
                ) {
                    toggleLiveActivityPin()
                }
            }

            // Progress is one idea, so it is told once — as a bar. A ring and a
            // bar side by side made the reader check whether they agreed.
            VStack(alignment: .leading, spacing: 8) {
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color.primary.opacity(0.07))
                        Capsule()
                            .fill(Color.accentColor)
                            .frame(width: geometry.size.width * CGFloat(min(max(progress, 0), 1)))
                    }
                }
                .frame(height: 8)
                .lockTodoAnimation(LockTodoMotion.standard, value: progress)

                HStack(spacing: 4) {
                    Text("\(Int((progress * 100).rounded()))%")
                        .font(.footnote.weight(.semibold))
                        .monospacedDigit()
                        .contentTransition(.numericText(value: progress))
                        .foregroundStyle(.primary)

                    Text("완료")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            HStack(spacing: 8) {
                LockTodoOverviewMetric(title: "남음", value: "\(activeTasks.count)", systemImage: "circle")
                LockTodoOverviewMetric(title: "완료", value: "\(completedTasks.count)", systemImage: "checkmark.circle.fill")
                LockTodoOverviewMetric(title: "중요", value: "\(activeTasks.filter(\.isImportant).count)", systemImage: "star.fill")
            }

            if selectedCategory == .today, let nextActionTask {
                nextActionCard(nextActionTask)
            }
        }
        .padding(18)
        .lockTodoCard()
    }

    /// The day, spelled out — the quiet anchor at the top of the hero card
    /// (like Reminders/Fitness), so the card reads as "today" before anything else.
    private var todayHeroDateText: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.dateFormat = "M월 d일 EEEE"
        return formatter.string(from: .now)
    }

    /// A streak flame that grows warmer the longer the run — a small, familiar
    /// "don't break the chain" motivator, derived purely from completed tasks.
    private func streakBadge(_ streak: Int) -> some View {
        let tint: Color = streak >= 14 ? .red : (streak >= 7 ? .orange : Color(hex: "#FF9F0A"))
        return HStack(spacing: 3) {
            Image(systemName: "flame.fill")
                .font(.system(size: 11, weight: .semibold))
            Text("\(streak)")
                .font(.caption2.weight(.bold))
                .monospacedDigit()
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(tint.opacity(0.12), in: Capsule())
        .lockTodoAnimation(LockTodoMotion.snappy, value: streak)
        .accessibilityHidden(true)
    }

    private var todayOverviewTitle: String {
        if displayedTasks.isEmpty {
            return "\(selectedCategory.title) 목록이 비어 있어요"
        }

        if activeTasks.isEmpty {
            return "\(selectedCategory.title) 할 일을 모두 끝냈어요"
        }

        if let smartPlan, selectedCategory == .today {
            return smartPlan.primaryTask.title
        }

        return "\(activeTasks.count)개만 정리하면 돼요"
    }

    private var todayOverviewSubtitle: String {
        if displayedTasks.isEmpty {
            return "아래 입력창이나 오른쪽 위 + 버튼으로 새 할 일을 추가하세요."
        }

        if activeTasks.isEmpty {
            return "완료된 항목은 접힌 영역에서 필요할 때만 확인할 수 있습니다."
        }

        if let smartPlan, selectedCategory == .today {
            return smartPlan.reason
        }

        return "\(completedTasks.count)개 완료, \(activeTasks.filter(\.isImportant).count)개 중요 항목이 있습니다."
    }

    private func nextActionCard(_ task: TaskItem) -> some View {
        let taskColor = Color(hex: task.safeColorHex)

        return HStack(spacing: 10) {
            Button {
                selectedTask = task
            } label: {
                HStack(spacing: 11) {
                    Image(systemName: task.hasLocationTrigger ? "location.fill" : "scope")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 30, height: 30)
                        .background(taskColor, in: Circle())

                    VStack(alignment: .leading, spacing: 1) {
                        Text("다음 액션")
                            .font(.caption2.weight(.semibold))
                            .tracking(0.2)
                            .foregroundStyle(.secondary)

                        Text(task.title)
                            .font(.subheadline.weight(.semibold))
                            .tracking(-0.2)
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }

                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.lockTodoSurface)

            HStack(spacing: 6) {
                LockTodoInlineCircleButton(
                    systemImage: "pin.fill",
                    tint: taskColor,
                    accessibilityLabel: "다음 액션 고정 시작"
                ) {
                    startNextAction(task)
                }

                LockTodoInlineCircleButton(
                    systemImage: "checkmark",
                    tint: .green,
                    accessibilityLabel: "다음 액션 완료"
                ) {
                    toggle(task)
                }
            }
        }
        .padding(11)
        .lockTodoTile()
    }

    @ViewBuilder
    private var todayExtras: some View {
        if isDiaryPromptActive {
            diaryPromptBanner
        }

        if let entry = memoryCapsuleEntry {
            MemoryCapsuleCard(entry: entry)
        }

        habitGridCard
    }

    private var todayToolsHub: some View {
        LockTodoCollapsibleSection(
            title: "도구",
            subtitle: "상태 · 스마트 정리 · 위치 · 루틴",
            systemImage: "square.grid.2x2",
            badge: toolsHubBadge,
            isExpanded: $isToolsHubExpanded
        ) {
            VStack(spacing: 12) {
                LazyVGrid(
                    columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)],
                    spacing: 8
                ) {
                    ForEach(TodayToolPanel.allCases) { panel in
                        toolPanelButton(panel)
                    }
                }

                selectedToolPanelContent
            }
        }
    }

    private func toolPanelButton(_ panel: TodayToolPanel) -> some View {
        let isSelected = selectedToolPanel == panel

        return Button {
            UISelectionFeedbackGenerator().selectionChanged()
            withAnimation(reduceMotion ? .easeOut(duration: 0.15) : LockTodoMotion.snappy) {
                selectedToolPanel = panel
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: panel.systemImage)
                    .font(.system(size: 13, weight: .semibold))

                Text(panel.title)
                    .font(.footnote.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)

                Spacer(minLength: 0)

                Text(toolBadge(for: panel))
                    .font(.caption2.weight(.bold))
                    .monospacedDigit()
            }
            .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
            .padding(.horizontal, 12)
            .frame(height: 42)
            .background(
                isSelected ? Color.accentColor.opacity(0.12) : Color.primary.opacity(0.045),
                in: RoundedRectangle(cornerRadius: 11, style: .continuous)
            )
            .contentShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
        }
        .buttonStyle(TactileButtonStyle(pressedScale: 0.97))
        .accessibilityLabel("\(panel.title), \(toolBadge(for: panel))개")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    @ViewBuilder
    private var selectedToolPanelContent: some View {
        switch selectedToolPanel {
        case .status:
            VStack(spacing: 12) {
                todayMotivationCard

                if !displayedTasks.isEmpty {
                    dailyReviewCard
                }
            }
        case .smart:
            VStack(spacing: 12) {
                todayCommandCenterCard

                if let smartPlan {
                    smartPlanCard(smartPlan)
                }

                if shouldShowDayPlanner {
                    dayPlannerCard
                }
            }
        case .lockAndLocation:
            VStack(spacing: 12) {
                lockScreenPinControlBar

                if !lockScreenInboxTasks.isEmpty {
                    lockScreenInboxCard
                }

                if WidgetDataStore.isPatrolActive {
                    spiritPatrolBanner
                }

                if !mapLocationTasks.isEmpty {
                    mapLocationTasksCard
                }
            }
        case .routine:
            VStack(spacing: 12) {
                todayExtras
            }
        }
    }

    private var toolsHubBadge: String {
        "\(TodayToolPanel.allCases.count)"
    }

    private func toolBadge(for panel: TodayToolPanel) -> String {
        switch panel {
        case .status: statusSectionBadge
        case .smart: smartToolsBadge
        case .lockAndLocation: lockAndLocationBadge
        case .routine: routineSectionBadge
        }
    }

    private var lockScreenPinControlBar: some View {
        HStack {
            Label {
                Text(liveActivityService.isRunning ? "잠금화면 고정 활성화됨" : "잠금화면에 할 일 고정하기")
                    .font(.system(size: 15, weight: .medium))
                    .tracking(-0.2)
            } icon: {
                Image(systemName: liveActivityService.isRunning ? "pin.fill" : "pin")
                    .font(.system(size: 14, weight: .semibold))
                    .contentTransition(.symbolEffect(.replace))
                    .foregroundStyle(liveActivityService.isRunning ? Color.accentColor : Color.secondary)
            }
            .foregroundStyle(.primary)

            Spacer()

            Button {
                toggleLiveActivityPin()
            } label: {
                pinControlButtonLabel
            }
            .buttonStyle(TactileButtonStyle())
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .lockTodoCard()
    }

    private var pinControlButtonLabel: some View {
        Text(liveActivityService.isRunning ? "고정 해제" : "지금 고정")
            .font(.footnote.weight(.semibold))
            .foregroundStyle(liveActivityService.isRunning ? Color.secondary : Color.white)
            .padding(.horizontal, 13)
            .padding(.vertical, 7)
            .background(
                liveActivityService.isRunning
                    ? AnyShapeStyle(Color.primary.opacity(0.07))
                    : AnyShapeStyle(Color.accentColor),
                in: Capsule()
            )
    }

    private var todayCommandCenterCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            LockTodoCardHeader(
                title: "오늘 컨트롤",
                subtitle: commandCenterSubtitle,
                systemImage: "sparkles.rectangle.stack.fill"
            ) {
                LockTodoCountBadge(text: "\(activeTasks.count)개 남음")
            }

            HStack(spacing: 8) {
                LockTodoReviewMetric(title: "추천", value: smartPlan == nil ? "0" : "1")
                LockTodoReviewMetric(title: "중요 후보", value: "\(upcomingImportantCandidateCount)")
                LockTodoReviewMetric(title: "나중에", value: "\(laterPullableCount)")
            }

            if let plan = smartPlan {
                Button {
                    selectedTask = plan.primaryTask
                } label: {
                    HStack(spacing: 11) {
                        Image(systemName: "scope")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Color.accentColor)
                            .frame(width: 30, height: 30)
                            .background(Color.accentColor.opacity(0.12), in: Circle())

                        VStack(alignment: .leading, spacing: 1) {
                            Text("바로 시작하기 좋은 할 일")
                                .font(.caption2.weight(.semibold))
                                .tracking(0.2)
                                .foregroundStyle(.secondary)

                            Text(plan.primaryTask.title)
                                .font(.subheadline.weight(.semibold))
                                .tracking(-0.2)
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                        }

                        Spacer(minLength: 8)

                        Image(systemName: "chevron.right")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.tertiary)
                    }
                    .padding(10)
                    .lockTodoTile()
                    .contentShape(Rectangle())
                }
                .buttonStyle(.lockTodoSurface)
            }

            VStack(spacing: 8) {
                HStack(spacing: 8) {
                    LockTodoCommandActionButton(
                        title: "집중 시작",
                        systemImage: "scope",
                        isProminent: true,
                        isDisabled: smartPlan == nil
                    ) {
                        if let plan = smartPlan {
                            startSmartPlan(plan)
                        }
                    }

                    LockTodoCommandActionButton(
                        title: "중요 정리",
                        systemImage: "flag.fill",
                        isDisabled: upcomingImportantCandidateCount == 0
                    ) {
                        markUpcomingTasksImportant()
                    }
                }

                HStack(spacing: 8) {
                    LockTodoCommandActionButton(
                        title: "나중에 가져오기",
                        systemImage: "tray.and.arrow.up.fill",
                        isDisabled: laterPullableCount == 0
                    ) {
                        promoteLaterTasksToToday()
                    }

                    LockTodoCommandActionButton(
                        title: todayReviewTaskExists ? "리뷰 있음" : "리뷰 추가",
                        systemImage: "moon.stars.fill",
                        isDisabled: todayReviewTaskExists
                    ) {
                        createEveningReviewTask()
                    }
                }
            }
        }
        .padding(16)
        .lockTodoCard()
    }

    private var todayMotivationCard: some View {
        let motivation = todayMotivation

        return HStack(spacing: 12) {
            Image(systemName: motivation.systemImage)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 38, height: 38)
                .background(motivation.tint, in: Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(motivation.title)
                    .font(.system(size: 15, weight: .semibold))
                    .tracking(-0.2)
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Text(motivation.message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)

            Button {
                runMotivationAction()
            } label: {
                Text(motivation.actionTitle)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(motivation.tint)
                    .lineLimit(1)
                    .padding(.horizontal, 11)
                    .padding(.vertical, 7)
                    .background(motivation.tint.opacity(0.12), in: Capsule())
            }
            .buttonStyle(TactileButtonStyle(pressedScale: 0.94))
        }
        .padding(14)
        .lockTodoCard()
        .lockTodoAnimation(LockTodoMotion.content, value: motivation.title)
    }

    private var lockScreenInboxCard: some View {
        VStack(alignment: .leading, spacing: 13) {
            LockTodoCardHeader(
                title: "잠금화면 인박스",
                subtitle: "잠금화면에서 바로 적은 할 일",
                systemImage: "lock.fill",
                tint: .primary
            ) {
                LockTodoCountBadge(text: "\(lockScreenInboxTasks.count)개")
            }

            VStack(spacing: 7) {
                ForEach(Array(lockScreenInboxTasks.prefix(3))) { task in
                    lockScreenInboxRow(task)
                }
            }

            HStack(spacing: 8) {
                Button {
                    focusLockScreenInbox()
                } label: {
                    Label("바로 집중", systemImage: "scope")
                        .font(.footnote.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 3)
                }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.capsule)

                Button {
                    clearLockScreenInbox()
                } label: {
                    Label("정리 완료", systemImage: "tray.and.arrow.down")
                        .font(.footnote.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 3)
                }
                .buttonStyle(.bordered)
                .buttonBorderShape(.capsule)
            }
        }
        .padding(16)
        .lockTodoCard()
    }

    private func lockScreenInboxRow(_ task: TaskItem) -> some View {
        Button {
            selectedTask = task
        } label: {
            HStack(spacing: 10) {
                Image(systemName: task.isImportant ? "star.fill" : "circle")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(task.isImportant ? Color.orange : Color(hex: task.safeColorHex))
                    .frame(width: 26, height: 26)

                VStack(alignment: .leading, spacing: 1) {
                    Text(task.title)
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    Text(lockScreenInboxMetadata(for: task))
                        .font(.caption2)
                        .tracking(0.1)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 6)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .lockTodoTile()
            .contentShape(Rectangle())
        }
        .buttonStyle(.lockTodoSurface)
    }

    private func lockScreenInboxMetadata(for task: TaskItem) -> String {
        var parts: [String] = ["잠금화면"]
        if let dueTime = task.dueTime {
            parts.append(dueTime.formatted(date: .omitted, time: .shortened))
        }
        if task.hasLocationTrigger {
            parts.append(task.locationDisplayName)
        }
        return parts.joined(separator: " · ")
    }

    private func smartPlanCard(_ plan: LockTodoSmartPlan) -> some View {
        LockTodoSmartPlanCard(
            plan: plan,
            onStart: { startSmartPlan(plan) },
            onOpen: { selectedTask = plan.primaryTask }
        )
    }

    private var dayPlannerCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            LockTodoCardHeader(
                title: "오늘 시간표",
                subtitle: dayPlannerSubtitle,
                systemImage: "calendar.badge.clock"
            ) {
                LockTodoCountBadge(text: dayPlannerStatusText)
            }

            HStack(spacing: 8) {
                LockTodoReviewMetric(title: "시간 있음", value: "\(dayPlannerTimedTasks.count)")
                LockTodoReviewMetric(title: "배치 가능", value: "\(dayPlannerSchedulableTasks.count)")
                LockTodoReviewMetric(title: "위치 전용", value: "\(dayPlannerLocationOnlyCount)")
            }

            if let nextTimedTask {
                Button {
                    selectedTask = nextTimedTask
                } label: {
                    HStack(spacing: 11) {
                        Image(systemName: "clock.fill")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Color.accentColor)
                            .frame(width: 28, height: 28)
                            .background(Color.accentColor.opacity(0.12), in: Circle())

                        VStack(alignment: .leading, spacing: 1) {
                            Text("다음 일정")
                                .font(.caption2.weight(.semibold))
                                .tracking(0.2)
                                .foregroundStyle(.secondary)

                            Text(nextTimedTask.title)
                                .font(.subheadline.weight(.semibold))
                                .tracking(-0.2)
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                        }

                        Spacer()

                        Text(nextTimedTaskTimeText(nextTimedTask))
                            .font(.footnote.weight(.medium))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    .padding(10)
                    .lockTodoTile()
                    .contentShape(Rectangle())
                }
                .buttonStyle(.lockTodoSurface)
            }

            HStack(spacing: 8) {
                Button {
                    autoScheduleTodayPlanner()
                } label: {
                    Label("자동 배치", systemImage: "wand.and.sparkles")
                        .font(.footnote.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 3)
                }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.capsule)
                .disabled(dayPlannerSchedulableTasks.isEmpty)

                Button {
                    focusNextTimedTask()
                } label: {
                    Label("다음 집중", systemImage: "scope")
                        .font(.footnote.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 3)
                }
                .buttonStyle(.bordered)
                .buttonBorderShape(.capsule)
                .disabled(nextTimedTask == nil)
            }
        }
        .padding(16)
        .lockTodoCard()
    }

    private var nearbyLocationTasksCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            LockTodoCardHeader(
                title: "현재 위치 근처",
                systemImage: "location.fill",
                isIconFilled: false
            ) {
                LockTodoCountBadge(text: "\(nearbyLocationTasks.count)개")
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)

            ForEach(Array(nearbyLocationTasks.prefix(5).enumerated()), id: \.element.id) { index, task in
                if index > 0 {
                    // Separators start where the text starts, not at the card
                    // edge — the indent is what groups a row with its icon.
                    Divider().padding(.leading, 48)
                }
                locationTaskRow(task)
            }
        }
        .padding(.bottom, 4)
        .lockTodoCard()
    }

    private var mapLocationTasksCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            LockTodoCardHeader(
                title: "지도 지정 할 일",
                systemImage: "map.fill",
                isIconFilled: false
            ) {
                LockTodoCountBadge(text: "\(mapLocationTasks.count)개")
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)

            ForEach(Array(mapLocationTasks.prefix(6).enumerated()), id: \.element.id) { index, task in
                if index > 0 {
                    Divider().padding(.leading, 48)
                }
                locationTaskRow(task)
            }

            if mapLocationTasks.count > 6 {
                Text("외 \(mapLocationTasks.count - 6)개는 지도 화면에서 더 볼 수 있어요")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.top, 10)
            }
        }
        .padding(.bottom, 12)
        .lockTodoCard()
    }

    private func locationTaskRow(_ task: TaskItem) -> some View {
        let taskColor = Color(hex: task.safeColorHex)

        return Button {
            selectedTask = task
        } label: {
            HStack(alignment: .top, spacing: 12) {
                Button {
                    handleTaskToggle(task)
                } label: {
                    Image(systemName: task.isCompleted ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 22))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(task.isCompleted ? taskColor : taskColor.opacity(0.55))
                        .contentTransition(.symbolEffect(.replace.offUp))
                        .frame(width: 26, height: 26)
                        .contentShape(Circle().inset(by: -9))
                }
                .buttonStyle(TactileButtonStyle(pressedScale: 0.86))

                VStack(alignment: .leading, spacing: 4) {
                    Text(task.title)
                        .font(.system(.body, weight: task.isImportant ? .semibold : .regular))
                        .tracking(-0.1)
                        .strikethrough(task.isCompleted, color: .secondary)
                        .foregroundStyle(task.isCompleted ? .secondary : .primary)
                        .lineLimit(2)

                    HStack(spacing: 10) {
                        Label(task.locationDisplayName, systemImage: "mappin.circle")
                            .lineLimit(1)
                        if let distance = locationService.formattedDistance(for: task) {
                            Text(distance)
                                .monospacedDigit()
                        }
                    }
                    .font(.caption)
                    .tracking(0.1)
                    .foregroundStyle(.secondary)
                }
                .opacity(task.isCompleted ? 0.62 : 1)

                Spacer(minLength: 8)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .contentShape(Rectangle())
        }
        .buttonStyle(.lockTodoSurface)
        .lockTodoAnimation(LockTodoMotion.snappy, value: task.isCompleted)
    }

    @ViewBuilder
    private var taskSections: some View {
        if activeTasks.isEmpty {
            emptyState
        } else {
            datedTaskListCard(sections: activeTaskDateSections)
        }

        if !completedTasks.isEmpty {
            completedTasksCard
        }
    }

    private var completedTasksCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                withAnimation(LockTodoMotion.sheet) {
                    viewModel.showCompleted.toggle()
                }
            } label: {
                completedHeaderLabel
            }
            .buttonStyle(.lockTodoSurface)

            if viewModel.showCompleted {
                Divider().padding(.leading, 16)
                datedTaskSections(completedTaskDateSections)
                    .transition(.opacity)
            }
        }
        .padding(.bottom, viewModel.showCompleted ? 4 : 0)
        .lockTodoCard()
    }

    private var completedHeaderLabel: some View {
        HStack {
            Label("완료됨 (\(completedTasks.count))", systemImage: "checkmark.circle.fill")
                .font(.system(size: 15, weight: .medium))
                .tracking(-0.2)
            Spacer()
            Image(systemName: "chevron.down")
                .font(.system(size: 12, weight: .semibold))
                .rotationEffect(.degrees(viewModel.showCompleted ? 180 : 0))
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
        .contentShape(Rectangle())
        .lockTodoAnimation(LockTodoMotion.snappy, value: viewModel.showCompleted)
    }

    private func datedTaskListCard(sections: [TaskDateSection]) -> some View {
        VStack(spacing: 0) {
            datedTaskSections(sections)
        }
        .padding(.bottom, 4)
        .lockTodoCard()
    }

    private func datedTaskSections(_ sections: [TaskDateSection]) -> some View {
        ForEach(sections.indices, id: \.self) { sectionIndex in
            let section = sections[sectionIndex]
            taskDateHeader(section)

            taskRows(tasks: section.tasks)
        }
    }

    private func taskDateHeader(_ section: TaskDateSection) -> some View {
        HStack(spacing: 7) {
            Text(section.title)
                .font(.footnote.weight(.semibold))
                .tracking(-0.1)
                .foregroundStyle(.secondary)
                .textCase(nil)

            if section.isMissed {
                Label("미달성", systemImage: "exclamationmark.circle.fill")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.orange)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Color.orange.opacity(0.12), in: Capsule())
            }

            Spacer()

            Text("\(section.tasks.count)")
                .font(.footnote)
                .monospacedDigit()
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 4)
    }

    private func taskRows(tasks: [TaskItem]) -> some View {
        ForEach(tasks.indices, id: \.self) { index in
            let task = tasks[index]
            taskRow(task)

            if index < tasks.count - 1 {
                Divider()
                    .padding(.leading, 48)
            }
        }
    }

    @ViewBuilder
    private func taskRow(_ task: TaskItem) -> some View {
        let row = TaskRow(
            task: task,
            onToggle: { handleTaskToggle(task) },
            onDelete: { delete(task) },
            onFocus: { setFocus(task) },
            onEdit: { selectedTask = task },
            isSelectionMode: isSelectionMode,
            isSelected: selectedTaskIDs.contains(task.id),
            style: .plain
        )
        .contentShape(Rectangle())
        .onTapGesture { handleTaskTap(task) }

        // Selection mode is a batch operation; swipe would fight the row taps
        // that build the selection, so it's only offered in normal browsing.
        if isSelectionMode {
            row
        } else {
            SwipeActionsRow(
                slideToComplete: task.isCompleted ? nil : SwipeAction(
                    systemImage: "checkmark",
                    tint: .green,
                    accessibilityLabel: "밀어서 완료",
                    action: { completeViaSwipe(task) }
                ),
                trailing: [
                    SwipeAction(
                        systemImage: task.isImportant ? "star.slash.fill" : "star.fill",
                        tint: .orange,
                        accessibilityLabel: task.isImportant ? "중요 해제" : "중요 표시",
                        action: { toggleImportant(task) }
                    ),
                    SwipeAction(
                        systemImage: "trash.fill",
                        tint: .red,
                        isDestructive: true,
                        accessibilityLabel: "삭제",
                        action: { delete(task) }
                    )
                ]
            ) {
                row
            }
        }
    }

    private func toggleImportant(_ task: TaskItem) {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        withAnimation(LockTodoMotion.snappy) {
            task.isImportant.toggle()
            task.updatedAt = .now
        }
        viewModel.update(task, context: modelContext)
    }

    @ToolbarContentBuilder
    private var todayToolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            leadingToolbarItem
        }

        ToolbarItem(placement: .topBarTrailing) {
            trailingToolbarItems
        }
    }

    @ViewBuilder
    private var leadingToolbarItem: some View {
        if isSelectionMode {
            Button("취소") {
                exitSelectionMode()
            }
        } else {
            Button {
                showingBoardList = true
            } label: {
                Image(systemName: "folder.badge.gearshape")
            }
            .accessibilityLabel("보드 관리")
        }
    }

    private var trailingToolbarItems: some View {
        HStack(spacing: 12) {
            if !isSelectionMode {
                toolbarPinButton
                toolbarMenu
                addTaskButton
            } else {
                Button("완료") {
                    exitSelectionMode()
                }
                .bold()
            }
        }
    }

    private var toolbarPinButton: some View {
        Button {
            toggleLiveActivityPin()
        } label: {
            Image(systemName: liveActivityService.isRunning ? "pin.fill" : "pin")
                .font(.body)
                .foregroundStyle(liveActivityService.isRunning ? Color.accentColor : Color.secondary)
        }
        .accessibilityLabel(liveActivityService.isRunning ? "잠금화면 고정 해제" : "잠금화면 고정")
        .tutorialHighlightAnchor(.pin)
    }

    private var toolbarMenu: some View {
        Menu {
            Button {
                if proAccess.isPro {
                    showingInsights = true
                } else {
                    showingProUpgrade = true
                }
            } label: {
                Label(proAccess.isPro ? "인사이트 보기" : "인사이트 보기 · Pro", systemImage: "chart.bar.xaxis")
            }

            Section("보기 설정") {
                Button {
                    withAnimation(.snappy) {
                        viewModel.showCompleted.toggle()
                    }
                } label: {
                    Label(
                        viewModel.showCompleted ? "완료 항목 숨기기" : "완료 항목 보기",
                        systemImage: viewModel.showCompleted ? "eye.slash" : "eye"
                    )
                }

                Picker("필터", selection: $selectedFilter) {
                    ForEach(TaskFilter.allCases) { filter in
                        Label(filter.rawValue, systemImage: filter.systemImage).tag(filter)
                    }
                }
            }

            Section("순찰 및 집중") {
                Button {
                    togglePatrol()
                } label: {
                    Label(
                        WidgetDataStore.isPatrolActive ? "실시간 순찰 종료" : "실시간 순찰 가동",
                        systemImage: WidgetDataStore.isPatrolActive ? "xmark.shield" : "shield"
                    )
                }

                Button {
                    if let first = activeTasks.first {
                        setFocus(first)
                    }
                } label: {
                    Label("첫 항목 집중", systemImage: "scope")
                }
                .disabled(activeTasks.isEmpty)
            }

            Section("스마트 정리") {
                Button {
                    markUpcomingTasksImportant()
                } label: {
                    Label("곧 필요한 할 일 중요 표시", systemImage: "flag.fill")
                }
                .disabled(upcomingImportantCandidateCount == 0)

                Button {
                    promoteLaterTasksToToday()
                } label: {
                    Label("나중에 할 일 3개 가져오기", systemImage: "tray.and.arrow.up.fill")
                }
                .disabled(laterPullableCount == 0)

                Button {
                    createEveningReviewTask()
                } label: {
                    Label("오늘 마무리 리뷰 추가", systemImage: "moon.stars.fill")
                }
                .disabled(todayReviewTaskExists)
            }

            Section("할 일 편집") {
                Button {
                    enterSelectionMode()
                } label: {
                    Label("선택 편집", systemImage: "checklist.checked")
                }
            }
        } label: {
            Image(systemName: "ellipsis.circle")
        }
    }

    private var addTaskButton: some View {
        Button {
            router.presentAddTask(initialDate: quickAddDate, prefillTitle: "")
        } label: {
            Image(systemName: "plus.circle.fill")
                .font(.title2)
        }
        .accessibilityLabel("새 할 일")
        .tutorialHighlightAnchor(.addTask)
    }

    @ViewBuilder
    private var bottomBar: some View {
        if isSelectionMode {
            selectionActionBar
        }
    }

    private func toggleLiveActivityPin() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        Task {
            let isCurrentlyRunning = liveActivityService.isRunning
            if isCurrentlyRunning {
                WidgetDataStore.setAutoLiveActivityEnabled(false)
                await liveActivityService.end()
            } else {
                WidgetDataStore.setAutoLiveActivityEnabled(true)
                await liveActivityService.startOrUpdate(from: allTasks, focusTask: focusedTask)
            }
            viewModel.refreshSharedState(allTasks: allTasks)
            liveActivityService.refreshState()
        }
    }

    private func togglePatrol() {
        Task {
            let nextState = !WidgetDataStore.isPatrolActive
            WidgetDataStore.setPatrolActive(nextState)
            if nextState {
                WidgetDataStore.setAutoLiveActivityEnabled(true)
                await LiveActivityService.shared.startOrUpdate(from: allTasks, focusTask: focusedTask)
            } else {
                await LiveActivityService.shared.end()
            }
            viewModel.refreshSharedState(allTasks: allTasks)
        }
    }

    private func enterSelectionMode() {
        isSelectionMode = true
        selectedTaskIDs.removeAll()
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    private func exitSelectionMode() {
        isSelectionMode = false
        selectedTaskIDs.removeAll()
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    private func handleTaskToggle(_ task: TaskItem) {
        if isSelectionMode {
            toggleSelection(task)
        } else {
            toggle(task)
        }
    }

    private func handleTaskTap(_ task: TaskItem) {
        if isSelectionMode {
            toggleSelection(task)
        } else {
            selectedTask = task
        }
    }

    private var categorySelector: some View {
        HStack(spacing: 0) {
            ForEach(TaskCategory.allCases) { category in
                let isSelected = selectedCategory == category

                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    withAnimation(LockTodoMotion.snappy) {
                        selectedCategory = category
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: category.systemImage)
                            .font(.system(size: 11, weight: .medium))
                        Text(category.title)
                            .font(.footnote.weight(isSelected ? .semibold : .medium))
                            .tracking(-0.1)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .foregroundStyle(isSelected ? Color.primary : Color.secondary)
                    .background {
                        // One shared thumb slides between segments instead of
                        // each segment fading its own background in and out —
                        // the selection stays a single object you can follow.
                        if isSelected {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(LockTodoDesign.cardBackground)
                                .shadow(color: .black.opacity(0.07), radius: 3, y: 1)
                                .matchedGeometryEffect(id: "categoryThumb", in: categoryNamespace)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.lockTodoSurface)
            }
        }
        .padding(2)
        .background(LockTodoDesign.insetBackground, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .lockTodoAnimation(LockTodoMotion.snappy, value: selectedCategory)
    }

    private var titleAndBoardRow: some View {
        HStack {
            Text(boardRowCaption)
                .font(.footnote)
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .contentTransition(.numericText())

            Spacer()

            Menu {
                Button(action: {
                    selectedBoardID = nil
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                }) {
                    HStack {
                        Text("전체 보드")
                        if selectedBoardID == nil {
                            Image(systemName: "checkmark")
                        }
                    }
                }
                
                ForEach(boards) { board in
                    Button(action: {
                        selectedBoardID = board.id
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    }) {
                        HStack {
                            Text(board.name)
                            if selectedBoardID == board.id {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: selectedBoardID == nil ? "folder" : "folder.fill")
                        .font(.system(size: 11))
                    Text(selectedBoardName)
                        .lineLimit(1)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.tertiary)
                }
                .font(.footnote.weight(.medium))
                .foregroundStyle(Color.accentColor)
                .padding(.horizontal, 11)
                .padding(.vertical, 6)
                .background(Color.accentColor.opacity(0.10), in: Capsule())
            }
            .buttonStyle(TactileButtonStyle(pressedScale: 0.96))
        }
        .padding(.top, 4)
        .padding(.bottom, 2)
    }

    /// The row under the segmented control used to repeat the category name
    /// that the large title already says. It now carries the one fact the
    /// title cannot: how much is actually in the list.
    private var boardRowCaption: String {
        if displayedTasks.isEmpty { return "항목 없음" }
        if activeTasks.isEmpty { return "\(completedTasks.count)개 모두 완료" }
        return "\(activeTasks.count)개 남음 · \(completedTasks.count)개 완료"
    }

    private var selectedBoardName: String {
        if let selectedBoardID, let board = boards.first(where: { $0.id == selectedBoardID }) {
            return board.name
        }
        return "전체 보드"
    }

    private var statusSectionSubtitle: String {
        if activeTasks.isEmpty && !displayedTasks.isEmpty {
            return "오늘 흐름이 정리됨"
        }

        if completionStreak > 0 {
            return "\(completionStreak)일 연속 완료 기록"
        }

        return "진행률과 성장 상태"
    }

    private var statusSectionBadge: String {
        "\(Int((progress * 100).rounded()))%"
    }

    private var smartToolsSubtitle: String {
        if let smartPlan {
            return "추천: \(smartPlan.primaryTask.title)"
        }

        if laterPullableCount > 0 {
            return "나중에 둔 할 일 \(laterPullableCount)개"
        }

        if dayPlannerSchedulableTasks.isEmpty {
            return "정리할 항목 없음"
        }

        return "시간 없는 할 일 \(dayPlannerSchedulableTasks.count)개"
    }

    private var smartToolsBadge: String {
        let actionCount = (smartPlan == nil ? 0 : 1)
            + (upcomingImportantCandidateCount > 0 ? 1 : 0)
            + (laterPullableCount > 0 ? 1 : 0)
            + (dayPlannerSchedulableTasks.isEmpty ? 0 : 1)
        return "\(actionCount)"
    }

    private var lockAndLocationSubtitle: String {
        if WidgetDataStore.isPatrolActive {
            return "실시간 카드 가동 중"
        }

        if !lockScreenInboxTasks.isEmpty {
            return "잠금화면 입력 \(lockScreenInboxTasks.count)개"
        }

        if !nearbyLocationTasks.isEmpty {
            return "근처 할 일 \(nearbyLocationTasks.count)개"
        }

        return liveActivityService.isRunning ? "잠금화면 고정 중" : "잠금화면 고정 설정"
    }

    private var lockAndLocationBadge: String {
        "\(lockScreenInboxTasks.count + nearbyLocationTasks.count)"
    }

    private var routineSectionSubtitle: String {
        let activeHabitCount = habits.filter(\.isActive).count
        if isDiaryPromptActive {
            return "오늘 기록을 남길 시간"
        }

        if memoryCapsuleEntry != nil {
            return "돌아온 기록이 있어요"
        }

        if activeHabitCount > 0 {
            return "오늘 루틴 \(activeHabitCount)개"
        }

        return "접어서 화면을 깔끔하게 유지"
    }

    private var routineSectionBadge: String {
        let activeHabitCount = habits.filter(\.isActive).count
        let extraCount = (isDiaryPromptActive ? 1 : 0) + (memoryCapsuleEntry == nil ? 0 : 1)
        return "\(activeHabitCount + extraCount)"
    }

    private func designWeight(for board: TaskBoard) -> Font.Weight {
        selectedBoardID == board.id ? .bold : .semibold
    }

    private var dailyReviewCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                withAnimation(LockTodoMotion.sheet) {
                    isDailyReviewExpanded.toggle()
                }
            } label: {
                HStack(alignment: .center, spacing: 10) {
                    Label("오늘 리뷰", systemImage: "sparkles")
                        .font(.system(size: 17, weight: .semibold))
                        .tracking(-0.3)
                        .foregroundStyle(.primary)

                    Spacer()

                    Text(momentumText)
                        .font(.system(size: 17, weight: .semibold))
                        .monospacedDigit()
                        .contentTransition(.numericText(value: momentumProgress))
                        .foregroundStyle(.tint)

                    Image(systemName: "chevron.down")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.tertiary)
                        .rotationEffect(.degrees(isDailyReviewExpanded ? 180 : 0))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.lockTodoSurface)

            VStack(alignment: .leading, spacing: 14) {
                Text(dailyReviewSummary)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 8) {
                    LockTodoReviewMetric(title: "완료", value: "\(completedTasks.count)")
                    LockTodoReviewMetric(title: "남음", value: "\(activeTasks.count)")
                    LockTodoReviewMetric(title: "중요", value: "\(activeTasks.filter(\.isImportant).count)")
                }

                if activeTasks.isEmpty {
                    Label("오늘 할 일을 모두 완료했습니다", systemImage: "checkmark.seal.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.green)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 2)
                } else {
                    Button {
                        carryOverTodayTasks()
                    } label: {
                        Label("미완료 \(activeTasks.count)개 오늘에 유지", systemImage: "pin.fill")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 4)
                    }
                    .buttonStyle(.borderedProminent)
                    .buttonBorderShape(.capsule)
                    .controlSize(.regular)
                }
            }
            .padding(.top, isDailyReviewExpanded ? 14 : 0)
            .frame(height: isDailyReviewExpanded ? nil : 0, alignment: .top)
            .opacity(isDailyReviewExpanded ? 1.0 : 0.0)
            .clipped()
        }
        .padding(16)
        .lockTodoCard()
    }

    /// An empty list is not an error state — it is the reward for finishing.
    /// Centred, calm, and it says exactly which gesture fills it back up.
    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(Color.accentColor.opacity(0.7))
                .padding(.bottom, 2)

            Text("표시할 할 일이 없습니다")
                .font(.system(size: 17, weight: .semibold))
                .tracking(-0.3)

            Text("아래 입력창이나 오른쪽 위 + 버튼으로\n새 할 일을 추가하세요.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineSpacing(2)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 20)
        .padding(.vertical, 34)
        .lockTodoCard()
    }

    private var momentumText: String {
        let score = Int((momentumProgress * 100).rounded())
        return "\(score)%"
    }

    private var momentumProgress: Double {
        displayedTasks.isEmpty ? 0 : progress
    }

    private var completionStreak: Int {
        let calendar = Calendar.current
        var day = calendar.startOfDay(for: .now)
        var streak = 0

        while streak < 365 {
            let hasCompletion = allTasks.contains { task in
                guard let completedAt = task.completedAt else { return false }
                return calendar.isDate(completedAt, inSameDayAs: day)
            }

            guard hasCompletion else { break }
            streak += 1

            guard let previousDay = calendar.date(byAdding: .day, value: -1, to: day) else {
                break
            }
            day = previousDay
        }

        return streak
    }

    private var dailyReviewSummary: String {
        if activeTasks.isEmpty {
            return "오늘 목록이 정리됐습니다. 잠금화면 카드에서는 완료 상태와 진행률을 계속 확인할 수 있습니다."
        }

        if let importantTask = activeTasks.first(where: \.isImportant) {
            return "가장 먼저 처리할 항목은 ‘\(importantTask.title)’입니다. 끝내지 못한 항목은 오늘 날짜에 그대로 남아 미달성으로 확인할 수 있습니다."
        }

        return "\(activeTasks.count)개가 아직 남아 있습니다. 지금 처리할 수 없는 항목은 오늘 날짜에 유지되어 다음날 자동 이동하지 않습니다."
    }

    private var quickAddDate: Date? {
        switch selectedCategory {
        case .today:
            return Calendar.current.startOfDay(for: .now)
        case .tomorrow:
            return Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: .now))
        case .later:
            return nil
        case .scheduled:
            return Calendar.current.startOfDay(for: .now)
        }
    }

    private var dayPlannerSubtitle: String {
        if dayPlannerSchedulableTasks.isEmpty {
            return dayPlannerTimedTasks.isEmpty ? "오늘 처리할 시간을 기다리는 중" : "오늘 일정이 시간순으로 정리됨"
        }

        return "시간 없는 할 일을 자동으로 배치"
    }

    private var dayPlannerStatusText: String {
        if !dayPlannerSchedulableTasks.isEmpty {
            return "\(dayPlannerSchedulableTasks.count)개 대기"
        }

        if !dayPlannerTimedTasks.isEmpty {
            return "정리됨"
        }

        return "대기 없음"
    }

    private func nextTimedTaskTimeText(_ task: TaskItem) -> String {
        guard let dueTime = task.dueTime else { return "시간 없음" }
        return dueTime.formatted(date: .omitted, time: .shortened)
    }

    private func dayPlannerTimedSort(_ lhs: TaskItem, _ rhs: TaskItem) -> Bool {
        let lhsDate = dueDateTimeForToday(lhs) ?? .distantFuture
        let rhsDate = dueDateTimeForToday(rhs) ?? .distantFuture
        if lhsDate != rhsDate { return lhsDate < rhsDate }
        if lhs.isImportant != rhs.isImportant { return lhs.isImportant }
        return lhs.sortOrder < rhs.sortOrder
    }

    private func dayPlannerTaskSort(_ lhs: TaskItem, _ rhs: TaskItem) -> Bool {
        if lhs.isImportant != rhs.isImportant { return lhs.isImportant }
        if lhs.hasLocationTrigger != rhs.hasLocationTrigger { return !lhs.hasLocationTrigger }
        return lhs.sortOrder < rhs.sortOrder
    }

    private var focusedTask: TaskItem? {
        allTasks.first { $0.id == viewModel.focusTaskID }
    }

    private func smartPlanScore(for task: TaskItem, nearbyTaskIDs: Set<UUID>) -> Int {
        var score = 0

        if nearbyTaskIDs.contains(task.id) {
            score += 110
        }

        if isDueSoonForSmartPlan(task) {
            score += 78
        } else if task.dueTime != nil {
            score += 34
        }

        if task.isImportant {
            score += 52
        }

        if task.hasLocationTrigger {
            score += 18
        }

        if task.notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
            score += 8
        }

        score += max(0, 20 - Int(task.sortOrder.truncatingRemainder(dividingBy: 20)))
        return score
    }

    private func smartPlanReason(for task: TaskItem, nearbyTaskIDs: Set<UUID>) -> String {
        if nearbyTaskIDs.contains(task.id) {
            return "지금 위치 근처에서 바로 처리할 수 있어요"
        }

        if isDueSoonForSmartPlan(task), let dueTime = task.dueTime {
            return "\(dueTime.formatted(date: .omitted, time: .shortened)) 일정이 가까워요"
        }

        if task.isImportant {
            return "중요 표시된 항목이라 먼저 잡는 게 좋아요"
        }

        if task.hasLocationTrigger {
            return "\(task.locationDisplayName)에서 처리할 위치 할 일이에요"
        }

        return "오늘 목록 흐름상 가장 먼저 처리하기 좋은 항목이에요"
    }

    private func isDueSoonForSmartPlan(_ task: TaskItem) -> Bool {
        guard let dueDateTime = dueDateTimeForToday(task) else { return false }
        let interval = dueDateTime.timeIntervalSince(.now)
        return interval <= 7200
    }

    private func dueDateTimeForToday(_ task: TaskItem) -> Date? {
        guard let dueTime = task.dueTime else { return nil }
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        let components = calendar.dateComponents([.hour, .minute], from: dueTime)
        return calendar.date(
            bySettingHour: components.hour ?? 9,
            minute: components.minute ?? 0,
            second: 0,
            of: today
        )
    }

    private func estimatedFocusMinutes(for task: TaskItem) -> Int {
        if isDueSoonForSmartPlan(task) { return 15 }
        if task.isImportant { return 25 }
        if task.hasLocationTrigger { return 10 }
        return 20
    }

    private var appBackground: some View {
        LockTodoDesign.pageBackground
        .ignoresSafeArea()
    }

    private var sharedStateFingerprint: String {
        allTasks
            .map { task in
                [
                    task.id.uuidString,
                    task.title,
                    task.isCompleted.description,
                    task.isImportant.description,
                    task.category.rawValue,
                    String(task.sortOrder),
                    String(task.dueDate?.timeIntervalSinceReferenceDate ?? 0),
                    String(task.dueTime?.timeIntervalSinceReferenceDate ?? 0)
                ].joined(separator: "|")
            }
            .joined(separator: ";")
    }

    private func toggle(_ task: TaskItem) {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        withAnimation(.snappy) {
            viewModel.toggle(task, context: modelContext)
        }
    }

    private func delete(_ task: TaskItem) {
        // Snapshot enough to rebuild the task, so deletion is a reversible nudge
        // (an undo toast) rather than a one-way action needing a confirm dialog.
        let snapshot = TaskSnapshot(task)
        let title = task.title
        // Capture the concrete context now: @Environment values are only valid
        // during body evaluation, and the undo closure runs much later.
        let context = modelContext
        let vm = viewModel

        withAnimation(LockTodoMotion.standard) {
            viewModel.delete(task, context: context)
        }
        UIImpactFeedbackGenerator(style: .rigid).impactOccurred()

        toastCenter.show(
            "‘\(title)’ 삭제됨",
            systemImage: "trash.fill",
            undoTitle: "실행 취소"
        ) {
            withAnimation(LockTodoMotion.standard) {
                snapshot.reinsert(into: context)
            }
            vm.refreshSharedState(allTasks: (try? context.fetch(FetchDescriptor<TaskItem>())) ?? [])
        }
    }

    /// Complete a task from a swipe with a confirming toast (no undo needed —
    /// the checkbox itself toggles it straight back).
    private func completeViaSwipe(_ task: TaskItem) {
        guard !task.isCompleted else { return }
        toggle(task)
        toastCenter.show("‘\(task.title)’ 완료", systemImage: "checkmark.circle.fill")
    }

    private func setFocus(_ task: TaskItem) {
        viewModel.setFocus(task, allTasks: allTasks)
    }

    private func startSmartPlan(_ plan: LockTodoSmartPlan) {
        UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
        viewModel.setFocus(plan.primaryTask, allTasks: allTasks)
        WidgetDataStore.setAutoLiveActivityEnabled(true)

        Task {
            await liveActivityService.startOrUpdate(
                from: allTasks,
                focusTask: plan.primaryTask,
                focusTitle: "스마트 플랜: \(plan.primaryTask.title)"
            )
            liveActivityService.refreshState()
        }
    }

    private func startNextAction(_ task: TaskItem) {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        viewModel.setFocus(task, allTasks: allTasks)
        WidgetDataStore.setAutoLiveActivityEnabled(true)

        Task {
            await liveActivityService.startOrUpdate(
                from: allTasks,
                focusTask: task,
                focusTitle: "다음 액션: \(task.title)"
            )
            liveActivityService.refreshState()
        }
    }

    private func focusLockScreenInbox() {
        guard let task = lockScreenInboxTasks.first else { return }
        viewModel.setFocus(task, allTasks: allTasks)
        WidgetDataStore.setAutoLiveActivityEnabled(true)

        Task {
            await liveActivityService.startOrUpdate(
                from: allTasks,
                focusTask: task,
                focusTitle: "잠금화면: \(task.title)"
            )
            liveActivityService.refreshState()
        }

        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }

    private func clearLockScreenInbox() {
        guard !lockScreenInboxTasks.isEmpty else { return }

        withAnimation(.snappy) {
            for task in lockScreenInboxTasks {
                task.removeLockScreenInboxTag()
                task.updatedAt = .now
            }
            try? modelContext.save()
            viewModel.refreshSharedState(allTasks: allTasks)
        }

        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    private func autoScheduleTodayPlanner() {
        let scheduledCount = viewModel.autoScheduleTodayPlan(
            tasks: displayedTasks,
            context: modelContext
        )

        if scheduledCount == 0 {
            plannerMessage = "자동으로 배치할 오늘 할 일이 없습니다."
        } else {
            plannerMessage = "\(scheduledCount)개 할 일에 오늘 시간과 알림을 자동으로 배치했습니다."
        }

        showsPlannerResult = true
        UIImpactFeedbackGenerator(style: scheduledCount == 0 ? .light : .medium).impactOccurred()
    }

    private func focusNextTimedTask() {
        guard let task = nextTimedTask else { return }
        viewModel.setFocus(task, allTasks: allTasks)
        WidgetDataStore.setAutoLiveActivityEnabled(true)

        Task {
            await liveActivityService.startOrUpdate(
                from: allTasks,
                focusTask: task,
                focusTitle: "다음 일정: \(task.title)"
            )
            liveActivityService.refreshState()
        }

        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }

    private func markUpcomingTasksImportant() {
        let markedCount = viewModel.markUpcomingTasksImportant(
            allTasks: allTasks,
            context: modelContext
        )

        if markedCount == 0 {
            smartActionMessage = "중요 표시할 할 일이 없습니다."
        } else {
            smartActionMessage = "\(markedCount)개 할 일을 중요 항목으로 정리했습니다."
        }

        showsSmartActionResult = true
        UIImpactFeedbackGenerator(style: markedCount == 0 ? .light : .medium).impactOccurred()
    }

    private func promoteLaterTasksToToday() {
        let movedCount = viewModel.promoteLaterTasksToToday(
            allTasks: allTasks,
            limit: 3,
            context: modelContext
        )

        if movedCount == 0 {
            smartActionMessage = "오늘로 가져올 나중에 할 일이 없습니다."
        } else {
            selectedCategory = .today
            smartActionMessage = "나중에 둔 할 일 \(movedCount)개를 오늘 목록으로 가져왔습니다."
        }

        showsSmartActionResult = true
        UIImpactFeedbackGenerator(style: movedCount == 0 ? .light : .medium).impactOccurred()
    }

    private func createEveningReviewTask() {
        let created = viewModel.createEveningReviewTaskIfNeeded(
            allTasks: allTasks,
            context: modelContext
        )

        if created {
            smartActionMessage = "오늘 21:30에 마무리 리뷰 할 일을 추가했습니다."
        } else {
            smartActionMessage = "오늘 마무리 리뷰 할 일이 이미 있습니다."
        }

        showsSmartActionResult = true
        UIImpactFeedbackGenerator(style: created ? .medium : .light).impactOccurred()
    }

    private func runMotivationAction() {
        if activeTasks.isEmpty && !displayedTasks.isEmpty {
            withAnimation(.snappy) {
                viewModel.showCompleted = true
            }
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            return
        }

        if let smartPlan {
            startSmartPlan(smartPlan)
            return
        }

        toggleLiveActivityPin()
    }

    private func carryOverTodayTasks() {
        let keptCount = viewModel.carryOverIncompleteTodayTasks(allTasks: allTasks, context: modelContext)
        if keptCount == 0 {
            carryoverMessage = "오늘에 유지할 미완료 항목이 없습니다."
        } else {
            carryoverMessage = "\(keptCount)개 미완료 항목을 오늘 날짜에 그대로 유지했습니다."
            WidgetDataStore.defaults.set(Date.now.timeIntervalSince1970, forKey: "locktodo.last_carryover_time")
        }
        showsCarryoverResult = true
    }
    
    // --- Diary & Habit Helpers ---
    
    private var isDiaryPromptActive: Bool {
        let calendar = Calendar.current
        let now = Date.now
        let hour = calendar.component(.hour, from: now)
        let isNightTime = hour >= 21 && hour <= 23
        
        let today = calendar.startOfDay(for: now)
        let todayTasks = allTasks.filter { task in
            guard let dueDate = task.dueDate else { return false }
            return calendar.isDate(dueDate, inSameDayAs: today)
        }
        let hasTasksToday = !todayTasks.isEmpty
        
        let hasDiaryToday = diaries.contains { calendar.isDate($0.date, inSameDayAs: today) }
        
        return isNightTime && hasTasksToday && !hasDiaryToday
    }
    
    private var memoryCapsuleEntry: DiaryEntry? {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        return diaries.first { entry in
            let entryDate = calendar.startOfDay(for: entry.date)
            let diff = calendar.dateComponents([.day], from: entryDate, to: today).day ?? 0
            return diff == 30 || diff == 365
        }
    }
    
    private var diaryPromptBanner: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            showingDiaryWrite = true
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "pencil.line")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 38, height: 38)
                    .background(.white.opacity(0.20), in: Circle())

                VStack(alignment: .leading, spacing: 2) {
                    Text("오늘 하루는 어땠나요?")
                        .font(.system(size: 15, weight: .semibold))
                        .tracking(-0.2)
                        .foregroundStyle(.white)
                    Text("오늘을 차분히 정리하고 일기를 남겨보세요.")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.85))
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.7))
            }
            .padding(16)
            .background {
                RoundedRectangle(cornerRadius: LockTodoDesign.cardRadius, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Color(hex: "#8E2DE2"), Color(hex: "#4A00E0")],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }
            .overlay {
                RoundedRectangle(cornerRadius: LockTodoDesign.cardRadius, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.16), lineWidth: LockTodoDesign.hairline)
            }
            .shadow(color: Color(hex: "#4A00E0").opacity(0.26), radius: 16, x: 0, y: 8)
        }
        .buttonStyle(.lockTodoSurface)
    }

    private var habitGridCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("오늘 루틴")
                    .font(.system(size: 15, weight: .semibold))
                    .tracking(-0.2)
                    .foregroundStyle(.primary)

                Spacer()

                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    showingHabitManagement = true
                } label: {
                    Image(systemName: "gearshape.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .frame(width: 30, height: 30)
                        .contentShape(Circle())
                }
                .buttonStyle(TactileButtonStyle(pressedScale: 0.88))
                .accessibilityLabel("루틴 관리")
            }
            .padding(.horizontal, 14)
            .padding(.top, 13)

            let activeHabits = habits.filter(\.isActive)

            if activeHabits.isEmpty {
                Text("설정된 습관이 없습니다.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 14)
                    .padding(.bottom, 14)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(activeHabits) { habit in
                            habitChip(habit)
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.bottom, 14)
                }
                // The chips are meant to run under the card edge, so the scroll
                // is clipped to the card's own corner radius.
                .clipShape(RoundedRectangle(cornerRadius: LockTodoDesign.cardRadius, style: .continuous))
            }
        }
        .lockTodoCard()
    }

    /// A routine chip carries its own completion state, so it is a filled
    /// object when done and a quiet outline when not — the same distinction
    /// the checkbox makes, at chip scale.
    private func habitChip(_ habit: Habit) -> some View {
        let isCompleted = recordFor(habit: habit)?.isCompleted ?? false
        let habitColor = Color(hex: habit.colorHex)

        return HStack(spacing: 8) {
            Button {
                toggleHabit(habit)
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: isCompleted ? "checkmark.circle.fill" : habit.icon)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(isCompleted ? .white : habitColor)
                        .contentTransition(.symbolEffect(.replace))

                    VStack(alignment: .leading, spacing: 0) {
                        Text(habit.title)
                            .font(.footnote.weight(.medium))
                            .foregroundStyle(isCompleted ? .white : .primary)
                            .strikethrough(isCompleted)

                        Text("\(habit.streak)일")
                            .font(.system(size: 10))
                            .monospacedDigit()
                            .foregroundStyle(isCompleted ? .white.opacity(0.8) : .secondary)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(TactileButtonStyle(pressedScale: 0.94))

            if !isCompleted {
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    selectedFocusHabit = habit
                } label: {
                    Image(systemName: "timer")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(habitColor)
                        .frame(width: 22, height: 22)
                        .background(habitColor.opacity(0.14), in: Circle())
                }
                .buttonStyle(TactileButtonStyle(pressedScale: 0.86))
                .accessibilityLabel("\(habit.title) 집중 타이머")
            }
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 8)
        .background {
            let shape = RoundedRectangle(cornerRadius: LockTodoDesign.tileRadius, style: .continuous)
            if isCompleted {
                shape.fill(habitColor)
            } else {
                shape.fill(LockTodoDesign.insetBackground)
            }
        }
        .lockTodoAnimation(LockTodoMotion.snappy, value: isCompleted)
    }
    
    private func recordFor(habit: Habit) -> HabitRecord? {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        return habitRecords.first { $0.habitID == habit.id && calendar.isDate($0.date, inSameDayAs: today) }
    }
    
    private func toggleHabit(_ habit: Habit) {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        if let record = habitRecords.first(where: { $0.habitID == habit.id && calendar.isDate($0.date, inSameDayAs: today) }) {
            withAnimation(.snappy) {
                record.isCompleted.toggle()
                if record.isCompleted {
                    habit.registerCompletionToday()
                }
                try? modelContext.save()
                viewModel.refreshSharedState(allTasks: allTasks)
            }
        }
    }

    private func addQuickTask() {
        let title = newQuickTaskTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        
        let targetCategory: TaskCategory = selectedCategory == .later ? .later : (selectedCategory == .tomorrow ? .tomorrow : .today)
        let defaultDate = targetCategory == .later ? nil : (targetCategory == .tomorrow ? Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: .now)) : Calendar.current.startOfDay(for: .now))
        
        _ = viewModel.addTask(
            title: title,
            notes: "",
            category: targetCategory,
            dueDate: defaultDate,
            boardID: selectedBoardID,
            context: modelContext,
            allTasks: allTasks
        )
        newQuickTaskTitle = ""
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }

    private var selectionActionBar: some View {
        HStack(spacing: 10) {
            Button {
                toggleSelectAll()
            } label: {
                Text(selectedTaskIDs.count == displayedTasks.count ? "선택 해제" : "전체 선택")
                    .font(.footnote.weight(.semibold))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .foregroundStyle(.primary)
                    .background(Color.primary.opacity(0.07), in: Capsule())
            }
            .buttonStyle(TactileButtonStyle(pressedScale: 0.95))

            Spacer(minLength: 0)

            // Destructive actions are red and only red. A second black button
            // beside it read as "even more destructive", which is not a level
            // the system has — so the wider action is the outlined one.
            if !selectedTaskIDs.isEmpty {
                Button {
                    showingDeleteSelectedConfirmation = true
                } label: {
                    Text("\(selectedTaskIDs.count)개 삭제")
                        .font(.footnote.weight(.semibold))
                        .monospacedDigit()
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .foregroundStyle(.white)
                        .background(Color.red, in: Capsule())
                }
                .buttonStyle(TactileButtonStyle(pressedScale: 0.95))
                .transition(.opacity.combined(with: .scale(scale: 0.9)))
            }

            Button {
                showingDeleteAllConfirmation = true
            } label: {
                Text("전체 삭제")
                    .font(.footnote.weight(.semibold))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .foregroundStyle(.red)
                    .background(Color.red.opacity(0.12), in: Capsule())
            }
            .buttonStyle(TactileButtonStyle(pressedScale: 0.95))
        }
        .padding(.horizontal, LockTodoDesign.pageInset)
        .padding(.vertical, 12)
        .background(.regularMaterial)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(LockTodoDesign.separator)
                .frame(height: LockTodoDesign.hairline)
        }
        .lockTodoAnimation(LockTodoMotion.snappy, value: selectedTaskIDs.isEmpty)
    }

    private func toggleSelection(_ task: TaskItem) {
        if selectedTaskIDs.contains(task.id) {
            selectedTaskIDs.remove(task.id)
        } else {
            selectedTaskIDs.insert(task.id)
        }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    private func toggleSelectAll() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        if selectedTaskIDs.count == displayedTasks.count {
            selectedTaskIDs.removeAll()
        } else {
            selectedTaskIDs = Set(displayedTasks.map(\.id))
        }
    }

    private func deleteSelectedTasks() {
        withAnimation(.snappy) {
            for task in allTasks where selectedTaskIDs.contains(task.id) {
                viewModel.delete(task, context: modelContext)
            }
            selectedTaskIDs.removeAll()
            isSelectionMode = false
        }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }

    private func deleteAllDisplayedTasks() {
        withAnimation(.snappy) {
            let targets = displayedTasks
            for task in targets {
                viewModel.delete(task, context: modelContext)
            }
            selectedTaskIDs.removeAll()
            isSelectionMode = false
        }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }

    @ViewBuilder
    private var spiritPatrolBanner: some View {
        let hasIsland = UIDevice.current.hasDynamicIsland
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(0.12))
                    .frame(width: 44, height: 44)
                
                Circle()
                    .stroke(Color.accentColor.opacity(0.24), lineWidth: 2)
                    .frame(width: 44, height: 44)
                    .scaleEffect(isPatrolAnimating ? 1.25 : 1.0)
                    .opacity(isPatrolAnimating ? 0.0 : 1.0)
                
                Image(systemName: hasIsland ? "island.split.top.and.bottom.filled" : "lock.shield.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(Color.accentColor)
            }
            .onAppear {
                withAnimation(.easeOut(duration: 1.5).repeatForever(autoreverses: false)) {
                    isPatrolAnimating = true
                }
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text(hasIsland ? "다이나믹 아일랜드 순찰 가동 중" : "잠금화면 실시간 순찰 가동 중")
                    .font(.system(size: 15, weight: .semibold))
                    .tracking(-0.2)
                    .foregroundStyle(.primary)

                Text(hasIsland ? "상단 다이나믹 아일랜드에서 실시간으로 할 일을 확인할 수 있어요. 꾹 누르면 리스트가 열립니다."
                               : "잠금화면 실시간 카드에서 할 일을 확인할 수 있어요. 잠금화면에서 바로 체크해 보세요.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 4)

            Button {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                Task {
                    WidgetDataStore.setPatrolActive(false)
                    await LiveActivityService.shared.end()
                    viewModel.refreshSharedState(allTasks: allTasks)
                }
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 20))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.tertiary)
                    .contentShape(Circle().inset(by: -10))
            }
            .buttonStyle(TactileButtonStyle(pressedScale: 0.86))
            .accessibilityLabel("순찰 종료")
        }
        .padding(14)
        .lockTodoCard()
    }

}


private struct LockTodoMotivation {
    var title: String
    var message: String
    var systemImage: String
    var tint: Color
    var actionTitle: String
}

private struct LockTodoSmartPlan {
    var primaryTask: TaskItem
    var queue: [TaskItem]
    var reason: String
    var dueSoonCount: Int
    var importantCount: Int
    var nearbyCount: Int
    var totalActiveCount: Int
    var estimatedFocusMinutes: Int
}

private struct LockTodoSmartPlanCard: View {
    var plan: LockTodoSmartPlan
    var onStart: () -> Void
    var onOpen: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    private var accent: Color {
        Color(hex: plan.primaryTask.safeColorHex)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            LockTodoCardHeader(
                title: "스마트 플랜",
                subtitle: "\(plan.estimatedFocusMinutes)분 집중으로 시작",
                systemImage: "wand.and.sparkles",
                tint: accent
            ) {
                LockTodoCountBadge(text: "\(plan.totalActiveCount)개 남음", tint: accent)
            }

            Button(action: onOpen) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(plan.primaryTask.title)
                        .font(.system(size: 20, weight: .semibold))
                        .tracking(-0.4)
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(plan.reason)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.lockTodoSurface)

            HStack(spacing: 7) {
                smartPlanMetric("중요 \(plan.importantCount)", systemImage: "flag.fill", isActive: plan.importantCount > 0)
                smartPlanMetric("곧 \(plan.dueSoonCount)", systemImage: "clock.fill", isActive: plan.dueSoonCount > 0)
                smartPlanMetric("근처 \(plan.nearbyCount)", systemImage: "location.fill", isActive: plan.nearbyCount > 0)
            }

            VStack(spacing: 6) {
                ForEach(Array(plan.queue.enumerated()), id: \.element.id) { index, task in
                    HStack(spacing: 9) {
                        Text("\(index + 1)")
                            .font(.system(size: 10, weight: .semibold))
                            .monospacedDigit()
                            .foregroundStyle(.white)
                            .frame(width: 20, height: 20)
                            .background(Color(hex: task.safeColorHex), in: Circle())

                        Text(task.title)
                            .font(.footnote.weight(index == 0 ? .semibold : .regular))
                            .foregroundStyle(index == 0 ? .primary : .secondary)
                            .lineLimit(1)

                        Spacer(minLength: 8)
                    }
                    .padding(.horizontal, 9)
                    .padding(.vertical, 7)
                    .background(LockTodoDesign.insetBackground, in: Capsule())
                }
            }

            Button(action: onStart) {
                Label("지금 집중", systemImage: "scope")
                    .font(.footnote.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 3)
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.capsule)
        }
        .padding(16)
        .lockTodoCard()
    }

    private func smartPlanMetric(_ text: String, systemImage: String, isActive: Bool) -> some View {
        Label(text, systemImage: systemImage)
            .font(.caption.weight(.medium))
            .foregroundStyle(isActive ? accent : Color.secondary)
            .lineLimit(1)
            .minimumScaleFactor(0.85)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 7)
            .background(
                isActive ? accent.opacity(0.12) : Color.primary.opacity(0.05),
                in: Capsule()
            )
    }
}

/// A small circular action that sits inside a row. Kept as one component so
/// every instance has the same tap target, the same press response, and the
/// same tint treatment.
private struct LockTodoInlineCircleButton: View {
    var systemImage: String
    var tint: Color
    var accessibilityLabel: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 30, height: 30)
                .background(tint.opacity(0.12), in: Circle())
                .contentShape(Circle().inset(by: -6))
        }
        .buttonStyle(TactileButtonStyle(pressedScale: 0.88))
        .accessibilityLabel(accessibilityLabel)
    }
}

private struct LockTodoCommandActionButton: View {
    var title: String
    var systemImage: String
    var isProminent = false
    var isDisabled = false
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(.system(size: 12, weight: .semibold))
                Text(title)
                    .font(.footnote.weight(.semibold))
                    .tracking(-0.1)
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 11)
            .foregroundStyle(isProminent ? Color.white : Color.primary)
            // The secondary fill is a neutral tint rather than white, so it
            // holds up in dark mode instead of glowing.
            .background(
                isProminent ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(Color.primary.opacity(0.06)),
                in: Capsule()
            )
        }
        .buttonStyle(TactileButtonStyle(pressedScale: 0.97))
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.38 : 1)
    }
}

private struct LockTodoCollapsibleSection<Content: View>: View {
    var title: String
    var subtitle: String
    var systemImage: String
    var badge: String
    @Binding var isExpanded: Bool
    @ViewBuilder var content: () -> Content

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 10) {
            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                withAnimation(reduceMotion ? .easeOut(duration: 0.18) : LockTodoMotion.sheet) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: systemImage)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.accentColor)
                        .frame(width: 32, height: 32)
                        .background(Color.accentColor.opacity(0.11), in: Circle())

                    VStack(alignment: .leading, spacing: 1) {
                        Text(title)
                            .font(.system(size: 15, weight: .semibold))
                            .tracking(-0.2)
                            .foregroundStyle(.primary)

                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    Spacer(minLength: 8)

                    Text(badge)
                        .font(.caption.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(Color.accentColor)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.accentColor.opacity(0.11), in: Capsule())

                    // The chevron turns rather than swapping glyphs, so the
                    // control tells you which way the section is heading.
                    Image(systemName: "chevron.down")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.tertiary)
                        .rotationEffect(.degrees(isExpanded ? 180 : 0))
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .contentShape(RoundedRectangle(cornerRadius: LockTodoDesign.cardRadius, style: .continuous))
            }
            .buttonStyle(.lockTodoSurface)
            .lockTodoCard()

            if isExpanded {
                content()
                    .frame(maxWidth: .infinity, alignment: .top)
                    // Anchored to the top edge so the content reads as unfolding
                    // out of its own header rather than appearing from nowhere.
                    .transition(
                        .opacity.combined(with: .scale(scale: 0.97, anchor: .top))
                    )
            }
        }
        .frame(maxWidth: .infinity, alignment: .top)
        .lockTodoAnimation(LockTodoMotion.sheet, value: isExpanded)
    }
}

/// The number is the point, so it gets the size and the weight; the label sits
/// under it, quiet and small. Reading the value never requires reading the
/// caption first.
private struct LockTodoOverviewMetric: View {
    var title: String
    var value: String
    var systemImage: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 4) {
                Image(systemName: systemImage)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Color.accentColor)

                Text(title)
                    .font(.caption2)
                    .tracking(0.1)
                    .foregroundStyle(.secondary)
            }

            Text(value)
                .font(.system(size: 20, weight: .semibold))
                .tracking(-0.4)
                .monospacedDigit()
                .foregroundStyle(.primary)
                .contentTransition(.numericText())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 11)
        .padding(.vertical, 10)
        .lockTodoTile()
        .lockTodoAnimation(LockTodoMotion.standard, value: value)
    }
}

private struct LockTodoHeaderMetricMini: View {
    var systemImage: String
    var color: Color
    var title: String
    var value: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(color)

            VStack(alignment: .leading, spacing: 0) {
                Text(title)
                    .font(.system(size: 9))
                    .tracking(0.1)
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.caption.weight(.semibold))
                    .monospacedDigit()
            }
        }
        .lineLimit(1)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            LockTodoDesign.cardBackground,
            in: RoundedRectangle(cornerRadius: LockTodoDesign.controlRadius, style: .continuous)
        )
    }
}

private struct LockTodoReviewMetric: View {
    var title: String
    var value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption2)
                .tracking(0.1)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 17, weight: .semibold))
                .tracking(-0.3)
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .lockTodoTile()
    }
}

private struct LockTodoIconActionButton: View {
    enum Prominence {
        case primary
        case secondary
    }

    var systemImage: String
    var accessibilityLabel: String
    var prominence: Prominence = .secondary
    var isDisabled = false
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 16, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                // Replace rather than cross-fade: the pin visibly swaps, which
                // is the confirmation that the tap did something.
                .contentTransition(.symbolEffect(.replace))
                .frame(width: 42, height: 42)
                .foregroundStyle(foregroundStyle)
                .background(backgroundStyle, in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(TactileButtonStyle(pressedScale: 0.9))
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.36 : 1)
        .lockTodoAnimation(LockTodoMotion.snappy, value: prominence)
        .accessibilityLabel(accessibilityLabel)
    }

    private var foregroundStyle: Color {
        switch prominence {
        case .primary:
            return .white
        case .secondary:
            return .secondary
        }
    }

    private var backgroundStyle: Color {
        switch prominence {
        case .primary:
            return .accentColor
        case .secondary:
            return Color.primary.opacity(0.06)
        }
    }
}

enum TaskFilter: String, CaseIterable, Identifiable {
    case all = "모두"
    case active = "진행 중"
    case starred = "중요"
    
    var id: String { rawValue }
    
    var systemImage: String {
        switch self {
        case .all: return "list.bullet"
        case .active: return "circle"
        case .starred: return "star.fill"
        }
    }
}

/// A value copy of a task's fields, enough to recreate it after a delete so an
/// undo restores the same row rather than a blank one.
private struct TaskSnapshot {
    let title: String
    let notes: String
    let category: TaskCategory
    let isCompleted: Bool
    let isImportant: Bool
    let colorHex: String
    let boardID: UUID?
    let dueDate: Date?
    let dueTime: Date?
    let reminderDate: Date?
    let repeatRule: RepeatRule
    let tags: [String]
    let sortOrder: Double
    let locationTitle: String
    let locationLatitude: Double?
    let locationLongitude: Double?
    let locationRadius: Double
    let locationReminderEnabled: Bool
    let showOnlyAtLocation: Bool

    init(_ task: TaskItem) {
        title = task.title
        notes = task.notes
        category = task.category
        isCompleted = task.isCompleted
        isImportant = task.isImportant
        colorHex = task.safeColorHex
        boardID = task.boardID
        dueDate = task.dueDate
        dueTime = task.dueTime
        reminderDate = task.reminderDate
        repeatRule = task.repeatRule
        tags = task.tags
        sortOrder = task.sortOrder
        locationTitle = task.locationTitle
        locationLatitude = task.locationLatitude
        locationLongitude = task.locationLongitude
        locationRadius = task.locationRadius
        locationReminderEnabled = task.locationReminderEnabled
        showOnlyAtLocation = task.showOnlyAtLocation
    }

    func reinsert(into context: ModelContext) {
        let task = TaskItem(
            title: title,
            notes: notes,
            category: category,
            isCompleted: isCompleted,
            isImportant: isImportant,
            colorHex: colorHex,
            boardID: boardID,
            completedAt: isCompleted ? .now : nil,
            dueDate: dueDate,
            dueTime: dueTime,
            reminderDate: reminderDate,
            repeatRule: repeatRule,
            tags: tags,
            sortOrder: sortOrder,
            locationTitle: locationTitle,
            locationLatitude: locationLatitude,
            locationLongitude: locationLongitude,
            locationRadius: locationRadius,
            locationReminderEnabled: locationReminderEnabled,
            showOnlyAtLocation: showOnlyAtLocation
        )
        context.insert(task)
        try? context.save()
    }
}

private struct TaskDateSection: Identifiable {
    var date: Date?
    var title: String
    var isMissed: Bool
    var tasks: [TaskItem]

    var id: String {
        date.map { String(Calendar.current.startOfDay(for: $0).timeIntervalSinceReferenceDate) } ?? "none"
    }
}

extension UIDevice {
    var hasDynamicIsland: Bool {
        if let windowScene = UIApplication.shared.connectedScenes
            .first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene,
           let window = windowScene.windows.first(where: { $0.isKeyWindow }) {
            return window.safeAreaInsets.top >= 51
        }
        return false
    }
}
