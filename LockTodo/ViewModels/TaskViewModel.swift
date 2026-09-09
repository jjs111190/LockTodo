import Foundation
import SwiftData
import WidgetKit

@MainActor
final class TaskViewModel: ObservableObject {
    @Published var showCompleted = false
    @Published var focusTaskID: UUID?

    func addTask(
        title: String,
        notes: String = "",
        category: TaskCategory = .today,
        dueDate: Date? = Calendar.current.startOfDay(for: .now),
        dueTime: Date? = nil,
        reminderDate: Date? = nil,
        repeatRule: RepeatRule = .none,
        tags: [String] = [],
        isImportant: Bool = false,
        colorHex: String = TaskTint.defaultHex,
        boardID: UUID? = nil,
        locationTitle: String = "",
        locationLatitude: Double? = nil,
        locationLongitude: Double? = nil,
        locationRadius: Double = 150,
        locationReminderEnabled: Bool = false,
        showOnlyAtLocation: Bool = false,
        context: ModelContext,
        allTasks: [TaskItem] = []
    ) -> TaskItem? {
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanTitle.isEmpty else { return nil }

        let nextSortOrder = (allTasks.map(\.sortOrder).max() ?? Date().timeIntervalSinceReferenceDate) + 1
        let safeLocation = Self.validLocation(
            latitude: locationLatitude,
            longitude: locationLongitude,
            radius: locationRadius,
            isEnabled: locationReminderEnabled
        )
        let task = TaskItem(
            title: cleanTitle,
            notes: notes.trimmingCharacters(in: .whitespacesAndNewlines),
            category: category,
            isCompleted: false,
            isImportant: isImportant,
            colorHex: colorHex,
            boardID: boardID,
            dueDate: dueDateFor(category: category, explicitDate: dueDate),
            dueTime: dueTime,
            reminderDate: reminderDate,
            repeatRule: repeatRule,
            tags: tags,
            sortOrder: nextSortOrder,
            locationTitle: safeLocation.isEnabled ? locationTitle : "",
            locationLatitude: safeLocation.latitude,
            locationLongitude: safeLocation.longitude,
            locationRadius: safeLocation.radius,
            locationReminderEnabled: safeLocation.isEnabled,
            showOnlyAtLocation: showOnlyAtLocation && safeLocation.isEnabled
        )

        context.insert(task)
        save(context)

        Task {
            await NotificationService.shared.scheduleReminder(for: task)
        }

        return task
    }

    private static func validLocation(
        latitude: Double?,
        longitude: Double?,
        radius: Double,
        isEnabled: Bool
    ) -> (latitude: Double?, longitude: Double?, radius: Double, isEnabled: Bool) {
        let safeRadius = radius.isFinite ? min(max(radius, 100), 500) : 150
        guard isEnabled,
              let latitude,
              let longitude,
              latitude.isFinite,
              longitude.isFinite,
              (-90...90).contains(latitude),
              (-180...180).contains(longitude) else {
            return (nil, nil, safeRadius, false)
        }

        return (latitude, longitude, safeRadius, true)
    }

    func toggle(_ task: TaskItem, context: ModelContext, occurrenceDate: Date = .now) {
        task.markCompleted(!task.isCompleted)
        if task.isCompleted, task.repeatRule != .none {
            createNextOccurrence(from: task, after: occurrenceDate, context: context)
        }
        save(context)
    }

    func delete(_ task: TaskItem, context: ModelContext) {
        NotificationService.shared.cancelReminder(for: task)
        context.delete(task)
        save(context)
    }

    func update(_ task: TaskItem, context: ModelContext) {
        task.updatedAt = .now
        save(context)
        Task {
            NotificationService.shared.cancelReminder(for: task)
            await NotificationService.shared.scheduleReminder(for: task)
        }
    }

    func move(_ tasks: [TaskItem], from source: IndexSet, to destination: Int, context: ModelContext) {
        var reordered = tasks
        reordered.move(fromOffsets: source, toOffset: destination)

        for (index, task) in reordered.enumerated() {
            task.sortOrder = Double(index)
            task.updatedAt = .now
        }

        save(context)
    }

    func tasks(on date: Date, from allTasks: [TaskItem], calendar: Calendar = .current) -> [TaskItem] {
        allTasks
            .filter { $0.occurs(on: date, calendar: calendar) }
            .sorted(by: taskSort)
    }

    func todayTasks(from allTasks: [TaskItem], calendar: Calendar = .current) -> [TaskItem] {
        tasks(on: .now, from: allTasks, calendar: calendar)
    }

    func laterTasks(from allTasks: [TaskItem]) -> [TaskItem] {
        allTasks
            .filter { $0.category == .later }
            .sorted(by: taskSort)
    }

    func refreshSharedState(allTasks: [TaskItem]) {
        let focus = allTasks.first { $0.id == focusTaskID }
        let summary = WidgetDataStore.summary(from: allTasks, focusTask: focus)
        WidgetDataStore.saveSummary(summary)
        WatchConnectivityService.shared.send(summary: summary)
        LocationReminderService.shared.syncMonitoredTasks(allTasks: allTasks)
        WidgetCenter.shared.reloadTimelines(ofKind: "LockTodoLockScreenWidget")
        WidgetCenter.shared.reloadTimelines(ofKind: "LockTodoMascotWidget")
        WidgetCenter.shared.reloadAllTimelines()

        Task {
            await LiveActivityService.shared.update(from: allTasks, focusTask: focus)
        }
    }

    func setFocus(_ task: TaskItem?, allTasks: [TaskItem]) {
        focusTaskID = task?.id
        refreshSharedState(allTasks: allTasks)
    }

    func carryOverIncompleteTodayTasks(
        allTasks: [TaskItem],
        context: ModelContext,
        calendar: Calendar = .current
    ) -> Int {
        let today = calendar.startOfDay(for: .now)
        let candidates = allTasks
            .filter { task in
                !task.isCompleted
                    && task.category != .later
                    && task.occurs(on: today, calendar: calendar)
            }
            .sorted(by: taskSort)

        guard !candidates.isEmpty else { return 0 }

        for task in candidates {
            task.category = .today
            task.dueDate = today
            task.updatedAt = .now
        }

        save(context)
        return candidates.count
    }

    func autoScheduleTodayPlan(
        tasks: [TaskItem],
        context: ModelContext,
        calendar: Calendar = .current,
        now: Date = .now
    ) -> Int {
        let today = calendar.startOfDay(for: now)
        let candidates = tasks
            .filter { task in
                !task.isCompleted
                    && task.dueTime == nil
                    && !task.showOnlyAtLocation
                    && task.occurs(on: today, calendar: calendar)
            }
            .sorted(by: dayPlanSort)

        let scheduledTasks = Array(candidates.prefix(8))
        guard !scheduledTasks.isEmpty else { return 0 }

        let startTime = nextPlanningSlot(after: now, calendar: calendar)
        for (index, task) in scheduledTasks.enumerated() {
            let slot = calendar.date(byAdding: .minute, value: index * 40, to: startTime) ?? startTime
            task.category = .today
            task.dueDate = today
            task.dueTime = slot
            task.reminderDate = slot
            task.updatedAt = now
        }

        save(context)

        Task {
            for task in scheduledTasks {
                NotificationService.shared.cancelReminder(for: task)
                await NotificationService.shared.scheduleReminder(for: task)
            }
        }

        return scheduledTasks.count
    }

    func promoteLaterTasksToToday(
        allTasks: [TaskItem],
        limit: Int = 3,
        context: ModelContext,
        calendar: Calendar = .current,
        now: Date = .now
    ) -> Int {
        let today = calendar.startOfDay(for: now)
        let candidates = allTasks
            .filter { !$0.isCompleted && $0.category == .later }
            .sorted { lhs, rhs in
                if lhs.isImportant != rhs.isImportant { return lhs.isImportant }
                return lhs.sortOrder < rhs.sortOrder
            }
            .prefix(max(1, limit))

        guard !candidates.isEmpty else { return 0 }

        let baseSortOrder = (allTasks.map(\.sortOrder).max() ?? Date().timeIntervalSinceReferenceDate) + 1
        for (index, task) in candidates.enumerated() {
            task.category = .today
            task.dueDate = today
            task.sortOrder = baseSortOrder + Double(index)
            task.updatedAt = now
        }

        save(context)
        return candidates.count
    }

    func markUpcomingTasksImportant(
        allTasks: [TaskItem],
        context: ModelContext,
        calendar: Calendar = .current,
        now: Date = .now
    ) -> Int {
        let today = calendar.startOfDay(for: now)
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: today) ?? today
        let candidates = allTasks.filter { task in
            guard !task.isCompleted, !task.isImportant, task.category != .later else { return false }
            if task.hasLocationTrigger { return true }
            guard let dueDate = task.dueDate else { return false }
            let dueStart = calendar.startOfDay(for: dueDate)
            return dueStart <= tomorrow
        }

        guard !candidates.isEmpty else { return 0 }

        for task in candidates {
            task.isImportant = true
            task.updatedAt = now
        }

        save(context)
        return candidates.count
    }

    func createEveningReviewTaskIfNeeded(
        allTasks: [TaskItem],
        context: ModelContext,
        calendar: Calendar = .current,
        now: Date = .now
    ) -> Bool {
        let today = calendar.startOfDay(for: now)
        let reviewTitle = "오늘 마무리 리뷰"
        let alreadyExists = allTasks.contains { task in
            task.title == reviewTitle && task.occurs(on: today, calendar: calendar)
        }
        guard !alreadyExists else { return false }

        let reviewTime = calendar.date(bySettingHour: 21, minute: 30, second: 0, of: today) ?? today
        _ = addTask(
            title: reviewTitle,
            notes: "오늘 끝낸 일과 내일 잠금화면에 올릴 일을 정리하세요.",
            category: .today,
            dueDate: today,
            dueTime: reviewTime,
            reminderDate: reviewTime,
            tags: ["리뷰", TaskItem.lockScreenInboxTag],
            isImportant: true,
            colorHex: TaskTint.purple.rawValue,
            context: context,
            allTasks: allTasks
        )
        return true
    }

    func autoUpdateTaskCategories(context: ModelContext) {
        WidgetDataStore.autoUpdateTaskCategories(context: context)
        if let refreshedTasks = try? context.fetch(FetchDescriptor<TaskItem>()) {
            refreshSharedState(allTasks: refreshedTasks)
        }
    }

    func refresh(context: ModelContext) {
        context.refreshAll()
        objectWillChange.send()
    }


    func seedIfNeeded(context: ModelContext) {
        removeLegacySampleTasksIfNeeded(context: context)
        seedDefaultBoardsIfNeeded(context: context)
        // Clean up any duplicates left by earlier seeding races.
        WidgetDataStore.dedupeHabitsAndRecords(context: context)
    }

    private func seedDefaultBoardsIfNeeded(context: ModelContext) {
        if let boards = try? context.fetch(FetchDescriptor<TaskBoard>()), boards.isEmpty {
            let defaults = [
                TaskBoard(name: "오늘", icon: "sun.max.fill", colorHex: "#FF9500", orderIndex: 0, isPinnedToLockScreen: true),
                TaskBoard(name: "학교", icon: "book.fill", colorHex: "#5856D6", orderIndex: 1, isPinnedToLockScreen: true),
                TaskBoard(name: "개인", icon: "person.fill", colorHex: "#34C759", orderIndex: 2, isPinnedToLockScreen: false),
                TaskBoard(name: "쇼핑", icon: "cart.fill", colorHex: "#FF2D55", orderIndex: 3, isPinnedToLockScreen: true),
                TaskBoard(name: "운동", icon: "figure.run", colorHex: "#30B0C7", orderIndex: 4, isPinnedToLockScreen: false),
                TaskBoard(name: "루틴", icon: "arrow.clockwise", colorHex: "#AF52DE", orderIndex: 5, isPinnedToLockScreen: true)
            ]
            for board in defaults {
                context.insert(board)
            }
            try? context.save()
        }
    }

    private func removeLegacySampleTasksIfNeeded(context: ModelContext) {
        let cleanupKey = "locktodo.removedLegacySampleTasks.v1"
        guard !WidgetDataStore.defaults.bool(forKey: cleanupKey) else { return }

        let descriptor = FetchDescriptor<TaskItem>()
        guard let tasks = try? context.fetch(descriptor) else { return }
        let legacyTaskIDs = Set(tasks.filter(isLegacySampleTask).map(\.id))
        guard !legacyTaskIDs.isEmpty else {
            WidgetDataStore.defaults.set(true, forKey: cleanupKey)
            WidgetDataStore.saveSummary(from: tasks)
            WidgetCenter.shared.reloadAllTimelines()
            Task {
                await LiveActivityService.shared.updateCurrentSummary()
            }
            return
        }

        for task in tasks where legacyTaskIDs.contains(task.id) {
            NotificationService.shared.cancelReminder(for: task)
            context.delete(task)
        }

        save(context)

        let remainingTasks = (try? context.fetch(descriptor)) ?? []
        WidgetDataStore.saveSummary(from: remainingTasks)
        WidgetCenter.shared.reloadAllTimelines()
        Task {
            await LiveActivityService.shared.updateCurrentSummary()
        }
        WidgetDataStore.defaults.set(true, forKey: cleanupKey)
    }

    private func isLegacySampleTask(_ task: TaskItem) -> Bool {
        switch task.title {
        case "잠금화면 위젯 확인":
            task.category == .today
                && task.isImportant
                && task.notes == "위젯을 누르면 바로 입력 화면으로 이동"
                && task.tags.contains("Lock")
        case "저녁 미완료 알림 켜기":
            task.category == .today && task.tags.contains("알림")
        case "마트 체크리스트 만들기":
            task.category == .today && task.tags.contains("개인")
        case "회의 메모 정리":
            task.category == .tomorrow && task.tags.contains("업무")
        case "나중에 읽을 글 모으기":
            task.category == .later && task.tags.contains("나중에")
        default:
            false
        }
    }

    private func taskSort(_ lhs: TaskItem, _ rhs: TaskItem) -> Bool {
        if lhs.isCompleted != rhs.isCompleted { return !lhs.isCompleted }
        if lhs.isImportant != rhs.isImportant { return lhs.isImportant }
        if let lhsTime = lhs.dueTime, let rhsTime = rhs.dueTime, lhsTime != rhsTime { return lhsTime < rhsTime }
        return lhs.sortOrder < rhs.sortOrder
    }

    private func dayPlanSort(_ lhs: TaskItem, _ rhs: TaskItem) -> Bool {
        if lhs.isImportant != rhs.isImportant { return lhs.isImportant }
        if lhs.hasLocationTrigger != rhs.hasLocationTrigger { return !lhs.hasLocationTrigger }
        return taskSort(lhs, rhs)
    }

    private func nextPlanningSlot(after date: Date, calendar: Calendar) -> Date {
        let safeDate = calendar.date(byAdding: .minute, value: 10, to: date) ?? date
        let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: safeDate)
        let minute = components.minute ?? 0
        let roundedMinute = minute <= 30 ? 30 : 60

        if roundedMinute == 60 {
            let base = calendar.date(
                bySettingHour: components.hour ?? 9,
                minute: 0,
                second: 0,
                of: safeDate
            ) ?? safeDate
            return calendar.date(byAdding: .hour, value: 1, to: base) ?? safeDate
        }

        return calendar.date(
            bySettingHour: components.hour ?? 9,
            minute: roundedMinute,
            second: 0,
            of: safeDate
        ) ?? safeDate
    }

    private func dueDateFor(category: TaskCategory, explicitDate: Date?) -> Date? {
        switch category {
        case .today, .tomorrow:
            return explicitDate ?? category.defaultDueDate()
        case .later:
            return nil
        case .scheduled:
            return explicitDate ?? Calendar.current.startOfDay(for: .now)
        }
    }

    private func createNextOccurrence(from task: TaskItem, after occurrenceDate: Date, context: ModelContext) {
        let calendar = Calendar.current
        let baseDate = task.dueDate ?? occurrenceDate
        let completedOccurrenceDate = max(calendar.startOfDay(for: baseDate), calendar.startOfDay(for: occurrenceDate))
        guard let nextDate = nextDate(after: completedOccurrenceDate, rule: task.repeatRule) else { return }
        let nextReminder: Date?
        if let reminderDate = task.reminderDate {
            let reminderComponents = Calendar.current.dateComponents([.hour, .minute], from: reminderDate)
            nextReminder = Calendar.current.date(
                bySettingHour: reminderComponents.hour ?? 9,
                minute: reminderComponents.minute ?? 0,
                second: 0,
                of: nextDate
            )
        } else {
            nextReminder = nil
        }

        let copy = TaskItem(
            title: task.title,
            notes: task.notes,
            category: .scheduled,
            isImportant: task.isImportant,
            colorHex: task.safeColorHex,
            dueDate: nextDate,
            dueTime: task.dueTime,
            reminderDate: nextReminder,
            repeatRule: task.repeatRule,
            tags: task.tags,
            sortOrder: task.sortOrder + 0.1
        )
        context.insert(copy)
    }

    private func nextDate(after date: Date, rule: RepeatRule) -> Date? {
        let calendar = Calendar.current
        switch rule {
        case .none:
            return nil
        case .daily:
            return calendar.date(byAdding: .day, value: 1, to: date)
        case .weekdays:
            var candidate = calendar.date(byAdding: .day, value: 1, to: date)
            while let date = candidate {
                let weekday = calendar.component(.weekday, from: date)
                if weekday != 1 && weekday != 7 { return date }
                candidate = calendar.date(byAdding: .day, value: 1, to: date)
            }
            return nil
        case .weekly:
            return calendar.date(byAdding: .weekOfYear, value: 1, to: date)
        case .monthly:
            return calendar.date(byAdding: .month, value: 1, to: date)
        }
    }

    private func save(_ context: ModelContext) {
        try? context.save()
        if let refreshedTasks = try? context.fetch(FetchDescriptor<TaskItem>()) {
            refreshSharedState(allTasks: refreshedTasks)
            let currentCounter = WidgetDataStore.dbChangeCounter
            WidgetDataStore.lastLocalChangeCount = currentCounter + 1
            WidgetDataStore.postDatabaseChangedNotification()
        }
    }
}
