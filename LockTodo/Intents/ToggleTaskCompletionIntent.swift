import ActivityKit
import AppIntents
import Foundation
import SwiftData
import UserNotifications
import WidgetKit
import SwiftUI

struct ToggleTaskCompletionIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "LockTodo 할 일 체크"
    static var description = IntentDescription("잠금화면에서 할 일을 바로 완료하거나 다시 열어둡니다.")
    static var openAppWhenRun = false

    @Parameter(title: "할 일 ID")
    var taskID: String

    @Parameter(title: "완료 상태")
    var isCompleted: Bool

    @Parameter(title: "할 일 제목")
    var taskTitle: String

    init() {
        taskID = ""
        isCompleted = true
        taskTitle = ""
    }

    init(taskID: UUID, isCompleted: Bool, taskTitle: String) {
        self.taskID = taskID.uuidString
        self.isCompleted = isCompleted
        self.taskTitle = taskTitle
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        do {
            try await LockTodoTaskMutationStore.setCompletion(
                taskIDString: taskID,
                isCompleted: isCompleted
            )
        } catch {
            WidgetDataStore.recordLockScreenAction(taskTitle.isEmpty ? "체크" : taskTitle, status: "실패")
            WidgetCenter.shared.reloadAllTimelines()
            await LiveActivityService.shared.updateCurrentSummary(startIfNeeded: false)
        }
        return .result()
    }
}

struct ChangeLockScreenTaskPageIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "LockTodo 잠금화면 목록 넘기기"
    static var description = IntentDescription("잠금화면에서 표시되는 할 일 목록 페이지를 넘깁니다.")
    static var openAppWhenRun = false

    @Parameter(title: "다음 페이지")
    var showsNextPage: Bool

    @Parameter(title: "페이지 크기")
    var pageSize: Int

    init() {
        showsNextPage = true
        pageSize = WidgetDataStore.liveActivityTaskPageSize
    }

    init(showsNextPage: Bool, pageSize: Int) {
        self.showsNextPage = showsNextPage
        self.pageSize = pageSize
    }

    func perform() async throws -> some IntentResult {
        await LockTodoTaskMutationStore.changeLockScreenTaskPage(
            showsNextPage: showsNextPage,
            pageSize: pageSize
        )
        return .result()
    }
}

struct CancelMapRouteIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "LockTodo 지도 루트 취소"
    static var description = IntentDescription("잠금화면 길찾기 카드를 종료하고 오늘 투두 리스트로 되돌립니다.")
    static var openAppWhenRun = false

    func perform() async throws -> some IntentResult {
        await LockTodoTaskMutationStore.cancelActiveMapRoute()
        return .result()
    }
}

enum LockTodoTaskMutationStore {
    @MainActor
    static func addTask(
        title: String,
        notes: String = "",
        isImportant: Bool = false,
        category: TaskCategory = .today,
        tagsText: String = "",
        dueDate: Date? = nil,
        dueTime: Date? = nil,
        colorHex: String = TaskTint.defaultHex
    ) async throws {
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanTitle.isEmpty else {
            WidgetDataStore.recordLockScreenAction("추가", status: "빈 제목")
            WidgetCenter.shared.reloadAllTimelines()
            await refreshLiveActivities(startIfNeeded: false)
            return
        }

        let container = WidgetDataStore.sharedModelContainer
        let context = ModelContext(container)
        let tasks = try context.fetch(FetchDescriptor<TaskItem>())
        let nextSortOrder = (tasks.map(\.sortOrder).max() ?? Date().timeIntervalSinceReferenceDate) + 1
        
        let resolvedDueDate: Date?
        if let dueDate {
            resolvedDueDate = Calendar.current.startOfDay(for: dueDate)
        } else if category == .later {
            resolvedDueDate = nil
        } else if category == .tomorrow {
            resolvedDueDate = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: .now))
        } else {
            resolvedDueDate = Calendar.current.startOfDay(for: .now)
        }

        let parsedTags = tagsText
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let tags = TaskItem.mergedTags(parsedTags, adding: [TaskItem.lockScreenInboxTag])

        let task = TaskItem(
            title: cleanTitle,
            notes: notes,
            category: category,
            isImportant: isImportant,
            colorHex: colorHex,
            dueDate: resolvedDueDate,
            dueTime: dueTime,
            tags: tags,
            sortOrder: nextSortOrder
        )

        context.insert(task)
        try context.save()

        let refreshedTasks = try context.fetch(FetchDescriptor<TaskItem>())
        let summary = WidgetDataStore.summary(from: refreshedTasks, focusTitle: WidgetDataStore.loadSummary().focusTitle)
        WidgetDataStore.saveSummary(summary)
        sendSummaryToWatchIfAvailable(summary)
        WidgetDataStore.recordLockScreenAction(cleanTitle, status: "추가됨")
        WidgetCenter.shared.reloadAllTimelines()
        WidgetDataStore.postDatabaseChangedNotification()
        await refreshLiveActivities()
    }

    @MainActor
    static func startSmartPlan() async throws -> String? {
        let container = WidgetDataStore.sharedModelContainer
        let context = ModelContext(container)
        let tasks = try context.fetch(FetchDescriptor<TaskItem>())
        let focusTask = bestSmartPlanTask(from: tasks)

        guard let focusTask else {
            WidgetDataStore.saveSummary(from: tasks)
            WidgetDataStore.recordLockScreenAction("스마트 플랜", status: "대기 항목 없음")
            WidgetCenter.shared.reloadAllTimelines()
            await refreshLiveActivities(startIfNeeded: false)
            return nil
        }

        WidgetDataStore.setAutoLiveActivityEnabled(true)
        WidgetDataStore.recordLockScreenAction(focusTask.title, status: "스마트 플랜 시작")
        await LiveActivityService.shared.startOrUpdate(
            from: tasks,
            focusTask: focusTask,
            focusTitle: focusTask.title
        )
        WidgetCenter.shared.reloadAllTimelines()
        return focusTask.title
    }

    @MainActor
    static func setPatrolActive(_ isActive: Bool) async throws {
        let container = WidgetDataStore.sharedModelContainer
        let context = ModelContext(container)
        let tasks = try context.fetch(FetchDescriptor<TaskItem>())

        WidgetDataStore.setPatrolActive(isActive)
        WidgetDataStore.setAutoLiveActivityEnabled(isActive)
        WidgetDataStore.saveSummary(from: tasks, focusTitle: isActive ? "실시간 순찰" : nil)

        if isActive {
            await LiveActivityService.shared.startOrUpdate(from: tasks, focusTitle: "실시간 순찰")
        } else {
            await LiveActivityService.shared.end()
        }

        WidgetDataStore.recordLockScreenAction("실시간 순찰", status: isActive ? "시작" : "종료")
        WidgetCenter.shared.reloadAllTimelines()
    }

    @MainActor
    static func cancelActiveMapRoute() async {
        WidgetDataStore.clearActiveMapTodoRoute()

        do {
            let container = WidgetDataStore.sharedModelContainer
            let context = ModelContext(container)
            let tasks = try context.fetch(FetchDescriptor<TaskItem>())
            let summary = WidgetDataStore.summary(from: tasks, focusTitle: nil)
            WidgetDataStore.saveSummary(summary)
            sendSummaryToWatchIfAvailable(summary)
        } catch {
            var summary = WidgetDataStore.loadSummary()
            summary.activeMapRoute = nil
            if summary.focusTitle?.hasPrefix("이동:") == true {
                summary.focusTitle = nil
            }
            WidgetDataStore.saveSummary(summary)
        }

        WidgetDataStore.recordLockScreenAction("지도 루트", status: "취소")
        WidgetCenter.shared.reloadAllTimelines()
        WidgetDataStore.postDatabaseChangedNotification()
        await refreshLiveActivities()
    }

    @MainActor
    static func setCompletion(taskIDString: String, isCompleted: Bool) async throws {
        guard let taskID = UUID(uuidString: taskIDString) else {
            WidgetDataStore.recordLockScreenAction("체크", status: "잘못된 항목")
            WidgetCenter.shared.reloadAllTimelines()
            await refreshLiveActivities(startIfNeeded: false)
            return
        }

        let container = WidgetDataStore.sharedModelContainer
        let context = ModelContext(container)
        let tasks = try context.fetch(FetchDescriptor<TaskItem>())

        guard let task = tasks.first(where: { $0.id == taskID }) else {
            WidgetDataStore.recordLockScreenAction("체크", status: "항목 없음")
            WidgetCenter.shared.reloadAllTimelines()
            await refreshLiveActivities(startIfNeeded: false)
            return
        }

        let previousSummary = WidgetDataStore.loadSummary()
        task.markCompleted(isCompleted)

        if isCompleted {
            UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [task.id.uuidString])
            if task.repeatRule != .none {
                createNextOccurrence(from: task, after: .now, context: context)
            }
        }

        try context.save()

        let refreshedTasks = try context.fetch(FetchDescriptor<TaskItem>())
        let summary = WidgetDataStore.summary(
            from: refreshedTasks,
            focusTitle: updatedFocusTitle(previousSummary.focusTitle, toggledTask: task)
        )
        WidgetDataStore.saveSummary(summary)
        sendSummaryToWatchIfAvailable(summary)

        WidgetDataStore.recordLockScreenAction(task.title, status: isCompleted ? "체크됨" : "체크 해제됨")
        WidgetCenter.shared.reloadAllTimelines()
        WidgetDataStore.postDatabaseChangedNotification()
        await refreshLiveActivities()
    }

    @MainActor
    static func changeLockScreenTaskPage(showsNextPage: Bool, pageSize: Int) async {
        let summary = WidgetDataStore.loadSummary()
        WidgetDataStore.advanceLockScreenTaskPage(
            totalCount: summary.totalCombinedItems.count,
            pageSize: pageSize,
            showsNextPage: showsNextPage
        )

        WidgetDataStore.recordLockScreenAction(showsNextPage ? "다음 페이지" : "이전 페이지", status: "성공")
        WidgetCenter.shared.reloadAllTimelines()
        await refreshLiveActivities()
    }


    @MainActor
    private static func refreshLiveActivities(startIfNeeded: Bool = true) async {
        await LiveActivityService.shared.updateCurrentSummary(startIfNeeded: startIfNeeded)
    }

    private static func updatedFocusTitle(_ focusTitle: String?, toggledTask: TaskItem) -> String? {
        guard focusTitle == toggledTask.title, toggledTask.isCompleted else {
            return focusTitle
        }
        return nil
    }

    private static func bestSmartPlanTask(from tasks: [TaskItem], calendar: Calendar = .current) -> TaskItem? {
        let today = calendar.startOfDay(for: .now)
        return tasks
            .filter { task in
                guard !task.isCompleted else { return false }
                if task.showOnlyAtLocation { return false }
                let isOverdue = task.dueDate.map { calendar.startOfDay(for: $0) < today } ?? false
                return task.occurs(on: .now, calendar: calendar) || isOverdue
            }
            .sorted { lhs, rhs in
                if lhs.isImportant != rhs.isImportant { return lhs.isImportant }
                switch (lhs.dueTime, rhs.dueTime) {
                case let (lhsTime?, rhsTime?) where lhsTime != rhsTime:
                    return lhsTime < rhsTime
                case (_?, nil):
                    return true
                case (nil, _?):
                    return false
                default:
                    return lhs.sortOrder < rhs.sortOrder
                }
            }
            .first
    }

    private static func sendSummaryToWatchIfAvailable(_ summary: TaskSummarySnapshot) {
        #if LOCKTODO_MAIN_APP
        WatchConnectivityService.shared.send(summary: summary)
        #endif
    }

    private static func createNextOccurrence(from task: TaskItem, after occurrenceDate: Date, context: ModelContext) {
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

        let nextTask = TaskItem(
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
        context.insert(nextTask)
    }

    private static func nextDate(after date: Date, rule: RepeatRule) -> Date? {
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
}

// --- Shared Lock Screen Destination Routing ---

@available(iOS 18.0, *)
public enum LockTodoDestination: String, AppEnum {
    case quickAdd
    case today
    case focus

    public static var typeDisplayRepresentation: TypeDisplayRepresentation {
        "LockTodo 화면"
    }

    public static var caseDisplayRepresentations: [LockTodoDestination: DisplayRepresentation] {
        [
            .quickAdd: DisplayRepresentation(title: "빠른 입력", image: .init(systemName: "plus")),
            .today: DisplayRepresentation(title: "오늘 보기", image: .init(systemName: "checklist")),
            .focus: DisplayRepresentation(title: "집중 시작", image: .init(systemName: "scope"))
        ]
    }

    public var pathName: String {
        switch self {
        case .quickAdd: return "capture"
        case .today: return "today"
        case .focus: return "focus"
        }
    }
}

@available(iOS 18.0, *)
struct LockTodoOpenDestinationIntent: OpenIntent {
    static var title: LocalizedStringResource = "LockTodo 열기"
    static var description = IntentDescription("LockTodo의 빠른 입력, 오늘 목록, 집중 화면을 엽니다.")

    @Parameter(title: "화면")
    var target: LockTodoDestination

    init() {
        target = .quickAdd
    }

    init(target: LockTodoDestination) {
        self.target = target
    }

    @MainActor
    func perform() async throws -> some IntentResult & OpensIntent {
        let url = URL(string: "locktodo://\(target.pathName)")!
        return .result(opensIntent: OpenURLIntent(url))
    }
}

struct ToggleHabitCompletionIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "LockTodo 루틴 체크"
    static var description = IntentDescription("잠금화면에서 습관 루틴을 완료하거나 다시 취소합니다.")
    static var openAppWhenRun = false

    @Parameter(title: "루틴 ID")
    var habitID: String

    @Parameter(title: "완료 상태")
    var isCompleted: Bool

    init() {
        habitID = ""
        isCompleted = true
    }

    init(habitID: UUID, isCompleted: Bool) {
        self.habitID = habitID.uuidString
        self.isCompleted = isCompleted
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        guard let id = UUID(uuidString: habitID) else { return .result() }
        
        let container = WidgetDataStore.sharedModelContainer
        let context = ModelContext(container)
        let habits = (try? context.fetch(FetchDescriptor<Habit>())) ?? []
        
        if let habit = habits.first(where: { $0.id == id }) {
            let today = Calendar.current.startOfDay(for: .now)
            let records = (try? context.fetch(FetchDescriptor<HabitRecord>())) ?? []
            
            if let record = records.first(where: { $0.habitID == habit.id && Calendar.current.isDate($0.date, inSameDayAs: today) }) {
                record.isCompleted = isCompleted
            } else {
                let newRecord = HabitRecord(habitID: habit.id, date: today, isCompleted: isCompleted)
                context.insert(newRecord)
            }
            if isCompleted {
                habit.registerCompletionToday()
            }
            
            try? context.save()
            
            let refreshedTasks = (try? context.fetch(FetchDescriptor<TaskItem>())) ?? []
            let focusTitle = WidgetDataStore.loadSummary().focusTitle
            let summary = WidgetDataStore.summary(from: refreshedTasks, forDate: .now, focusTitle: focusTitle)
            WidgetDataStore.saveSummary(summary)
            
            WidgetDataStore.recordLockScreenAction(habit.title, status: isCompleted ? "루틴 완료" : "루틴 취소")
            WidgetCenter.shared.reloadAllTimelines()
            WidgetDataStore.postDatabaseChangedNotification()
            await LiveActivityService.shared.updateCurrentSummary()
        }
        
        return .result()
    }
}
