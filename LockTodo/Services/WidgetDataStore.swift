import Foundation
import SwiftData
import CoreData
import Darwin

struct SharedHabitSnapshot: Codable, Identifiable, Hashable {
    var id: UUID
    var title: String
    var isCompleted: Bool
    var icon: String
    var colorHex: String
    var streak: Int
}

struct SharedTaskSnapshot: Codable, Identifiable, Hashable {
    var id: UUID
    var title: String
    var isCompleted: Bool
    var isImportant: Bool
    var dueDate: Date?
    var dueTime: Date?
    var boardID: UUID?
    var boardName: String?
    var boardColorHex: String?
    var colorHex: String
}

struct MapTodoRouteSnapshot: Codable, Identifiable, Hashable {
    static let lockScreenMaxAge: TimeInterval = 24 * 60 * 60

    var id: UUID
    var destinationTitle: String
    var previewText: String
    var distanceText: String?
    var taskCount: Int
    var stopCount: Int
    var stopRank: Int
    var latitude: Double
    var longitude: Double
    var startedAt: Date

    var lockScreenTitle: String {
        destinationTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "지도 위치" : destinationTitle
    }

    var summaryText: String {
        let taskText = "\(taskCount)개 할 일"
        if let distanceText, !distanceText.isEmpty {
            return "\(distanceText) · \(taskText)"
        }
        return taskText
    }

    func isLockScreenActive(now: Date = .now) -> Bool {
        now.timeIntervalSince(startedAt) <= Self.lockScreenMaxAge
    }
}

struct SharedCombinedItem: Codable, Hashable, Identifiable {
    var id: UUID
    var title: String
    var isCompleted: Bool
    var colorHex: String
    var isHabit: Bool
    var habitIcon: String?
}

struct TaskSummarySnapshot: Codable, Hashable {
    var generatedAt: Date
    var totalCount: Int
    var completedCount: Int
    var remainingCount: Int
    var importantTasks: [SharedTaskSnapshot]
    var allTodayTasks: [SharedTaskSnapshot]
    var pageIndex: Int
    var focusTitle: String?
    var activeMapRoute: MapTodoRouteSnapshot?
    var allTodayHabits: [SharedHabitSnapshot] = []

    init(
        generatedAt: Date,
        totalCount: Int,
        completedCount: Int,
        remainingCount: Int,
        importantTasks: [SharedTaskSnapshot],
        allTodayTasks: [SharedTaskSnapshot],
        pageIndex: Int,
        focusTitle: String?,
        activeMapRoute: MapTodoRouteSnapshot? = nil,
        allTodayHabits: [SharedHabitSnapshot] = []
    ) {
        self.generatedAt = generatedAt
        self.totalCount = totalCount
        self.completedCount = completedCount
        self.remainingCount = remainingCount
        self.importantTasks = importantTasks
        self.allTodayTasks = allTodayTasks
        self.pageIndex = pageIndex
        self.focusTitle = focusTitle
        self.activeMapRoute = activeMapRoute
        self.allTodayHabits = allTodayHabits
    }

    enum CodingKeys: String, CodingKey {
        case generatedAt, totalCount, completedCount, remainingCount, importantTasks, allTodayTasks, pageIndex, focusTitle, activeMapRoute
        case allTodayHabits
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.generatedAt = try container.decode(Date.self, forKey: .generatedAt)
        self.totalCount = try container.decode(Int.self, forKey: .totalCount)
        self.completedCount = try container.decode(Int.self, forKey: .completedCount)
        self.remainingCount = try container.decode(Int.self, forKey: .remainingCount)
        self.importantTasks = try container.decode([SharedTaskSnapshot].self, forKey: .importantTasks)
        self.allTodayTasks = try container.decode([SharedTaskSnapshot].self, forKey: .allTodayTasks)
        self.pageIndex = try container.decode(Int.self, forKey: .pageIndex)
        self.focusTitle = try container.decodeIfPresent(String.self, forKey: .focusTitle)
        self.activeMapRoute = try container.decodeIfPresent(MapTodoRouteSnapshot.self, forKey: .activeMapRoute)
        self.allTodayHabits = try container.decodeIfPresent([SharedHabitSnapshot].self, forKey: .allTodayHabits) ?? []
    }

    var remainingCombinedCount: Int {
        totalCombinedItems.filter { !$0.isCompleted }.count
    }

    var progress: Double {
        let total = totalCombinedItems.count
        guard total > 0 else { return 1.0 }
        let completed = totalCombinedItems.filter(\.isCompleted).count
        return min(max(Double(completed) / Double(total), 0.0), 1.0)
    }

    var orderedTasks: [SharedTaskSnapshot] {
        allTodayTasks.isEmpty ? importantTasks : allTodayTasks
    }

    var totalCombinedItems: [SharedCombinedItem] {
        let tasks = orderedTasks.map { task in
            SharedCombinedItem(
                id: task.id,
                title: task.title,
                isCompleted: task.isCompleted,
                colorHex: task.colorHex,
                isHabit: false,
                habitIcon: nil
            )
        }
        let activeTasks = tasks.filter { !$0.isCompleted }
        let completedTasks = tasks.filter { $0.isCompleted }
        
        return activeTasks + completedTasks
    }

    func pageCount(pageSize: Int) -> Int {
        let safePageSize = max(1, pageSize)
        return max(1, Int(ceil(Double(totalCombinedItems.count) / Double(safePageSize))))
    }

    func clampedPageIndex(pageSize: Int) -> Int {
        min(max(pageIndex, 0), pageCount(pageSize: pageSize) - 1)
    }

    func pageCombinedItems(pageSize: Int) -> [SharedCombinedItem] {
        let safePageSize = max(1, pageSize)
        let page = clampedPageIndex(pageSize: safePageSize)
        let startIndex = page * safePageSize
        guard totalCombinedItems.indices.contains(startIndex) else { return [] }
        let endIndex = min(startIndex + safePageSize, totalCombinedItems.count)
        return Array(totalCombinedItems[startIndex..<endIndex])
    }

    func pageRangeText(pageSize: Int) -> String {
        guard !totalCombinedItems.isEmpty else { return "0/0" }
        let page = clampedPageIndex(pageSize: pageSize)
        let start = page * max(1, pageSize) + 1
        let end = min(start + max(1, pageSize) - 1, totalCombinedItems.count)
        return "\(start)-\(end)/\(totalCombinedItems.count)"
    }

    func pageTasks(pageSize: Int) -> [SharedTaskSnapshot] {
        let safePageSize = max(1, pageSize)
        let page = clampedPageIndex(pageSize: safePageSize)
        let startIndex = page * safePageSize
        guard orderedTasks.indices.contains(startIndex) else { return [] }
        let endIndex = min(startIndex + safePageSize, orderedTasks.count)
        return Array(orderedTasks[startIndex..<endIndex])
    }

    static let empty = TaskSummarySnapshot(
        generatedAt: .now,
        totalCount: 0,
        completedCount: 0,
        remainingCount: 0,
        importantTasks: [],
        allTodayTasks: [],
        pageIndex: 0,
        focusTitle: nil,
        activeMapRoute: nil
    )

    static let sample = TaskSummarySnapshot(
        generatedAt: .now,
        totalCount: 5,
        completedCount: 2,
        remainingCount: 3,
        importantTasks: [
            SharedTaskSnapshot(id: UUID(), title: "기획안 마무리", isCompleted: false, isImportant: true, dueDate: .now, dueTime: nil, boardID: nil, boardName: nil, boardColorHex: nil, colorHex: "#AF52DE"),
            SharedTaskSnapshot(id: UUID(), title: "마트 체크리스트", isCompleted: false, isImportant: true, dueDate: .now, dueTime: nil, boardID: nil, boardName: nil, boardColorHex: nil, colorHex: "#FF9500"),
            SharedTaskSnapshot(id: UUID(), title: "운동 30분", isCompleted: true, isImportant: false, dueDate: .now, dueTime: nil, boardID: nil, boardName: nil, boardColorHex: nil, colorHex: "#34C759")
        ],
        allTodayTasks: [
            SharedTaskSnapshot(id: UUID(), title: "기획안 마무리", isCompleted: false, isImportant: true, dueDate: .now, dueTime: nil, boardID: nil, boardName: nil, boardColorHex: nil, colorHex: "#AF52DE"),
            SharedTaskSnapshot(id: UUID(), title: "마트 체크리스트", isCompleted: false, isImportant: true, dueDate: .now, dueTime: nil, boardID: nil, boardName: nil, boardColorHex: nil, colorHex: "#FF9500"),
            SharedTaskSnapshot(id: UUID(), title: "운동 30분", isCompleted: true, isImportant: false, dueDate: .now, dueTime: nil, boardID: nil, boardName: nil, boardColorHex: nil, colorHex: "#34C759"),
            SharedTaskSnapshot(id: UUID(), title: "저녁 알림 확인", isCompleted: false, isImportant: false, dueDate: .now, dueTime: nil, boardID: nil, boardName: nil, boardColorHex: nil, colorHex: "#8E8E93"),
            SharedTaskSnapshot(id: UUID(), title: "내일 우선순위 정리", isCompleted: true, isImportant: false, dueDate: .now, dueTime: nil, boardID: nil, boardName: nil, boardColorHex: nil, colorHex: "#007AFF")
        ],
        pageIndex: 0,
        focusTitle: "기획안 마무리",
        activeMapRoute: MapTodoRouteSnapshot(
            id: UUID(),
            destinationTitle: "강남역",
            previewText: "마트 체크리스트, 택배 찾기",
            distanceText: "850m",
            taskCount: 2,
            stopCount: 4,
            stopRank: 1,
            latitude: 37.4979,
            longitude: 127.0276,
            startedAt: .now
        )
    )
}

enum LockTodoLockScreenBackgroundStyle: String, Codable, CaseIterable, Identifiable {
    case transparent
    case whiteGlass
    case softGray
    case skyGlass
    case lavenderGlass

    var id: String { rawValue }

    var requiresPro: Bool {
        self == .skyGlass || self == .lavenderGlass
    }

    var title: String {
        switch self {
        case .transparent: "투명"
        case .whiteGlass: "화이트 글래스"
        case .softGray: "소프트 그레이"
        case .skyGlass: "스카이 글래스"
        case .lavenderGlass: "라벤더 글래스"
        }
    }

    var description: String {
        switch self {
        case .transparent: "가장 얇고 배경이 많이 비치는 스타일"
        case .whiteGlass: "아이폰 기본 위젯처럼 밝고 깨끗한 스타일"
        case .softGray: "배경 사진 위에서 글자가 안정적으로 보이는 스타일"
        case .skyGlass: "아주 옅은 파란 유리 스타일"
        case .lavenderGlass: "옅은 보라 유리 스타일"
        }
    }
}

enum WidgetDataStore {
    static let appGroupIdentifier = "group.com.jaeseok.LockTodo"

    @MainActor
    static var sharedModelContainer: ModelContainer = {
        let schema = Schema([TaskItem.self, TaskBoard.self, DiaryEntry.self, Habit.self, HabitRecord.self, FocusSession.self])
        let groupedConfiguration = ModelConfiguration(
            "LockTodo",
            schema: schema,
            groupContainer: .identifier(WidgetDataStore.appGroupIdentifier),
            cloudKitDatabase: .none
        )

        do {
            return try ModelContainer(for: schema, configurations: [groupedConfiguration])
        } catch {
            let localConfiguration = ModelConfiguration("LockTodoLocal", schema: schema, cloudKitDatabase: .none)
            do {
                return try ModelContainer(for: schema, configurations: [localConfiguration])
            } catch {
                fatalError("Unable to create SwiftData container: \(error)")
            }
        }
    }()

    private static let didSeedDefaultHabitsKey = "locktodo.didSeedDefaultHabits.v1"

    /// Seed the starter habits exactly once, ever. A bare `isEmpty` check was
    /// racy: this runs from several launch call sites at once (and once ran in
    /// the widget process), so two contexts could each see "empty" and both
    /// insert the five defaults — again on every relaunch when a store was
    /// momentarily empty. A persisted flag makes it idempotent.
    static var didSeedDefaultHabits: Bool {
        get { defaults.bool(forKey: didSeedDefaultHabitsKey) }
        set { defaults.set(newValue, forKey: didSeedDefaultHabitsKey) }
    }

    static func autoUpdateTaskCategories(context: ModelContext) {
        let calendar = Calendar.current
        let todayStart = calendar.startOfDay(for: .now)

        // 날짜가 지난 미완료 항목은 원래 날짜에 남겨 미달성으로 보여준다.
        // 이 함수는 위젯/앱 refresh 시 호출되므로 dueDate를 자동 이동시키지 않는다.
        // Only the main app seeds — never the widget process (its store may
        // differ, which used to re-create the defaults on every refresh).
        #if LOCKTODO_MAIN_APP
        if !didSeedDefaultHabits {
            let habitsDescriptor = FetchDescriptor<Habit>()
            if let habits = try? context.fetch(habitsDescriptor), habits.isEmpty {
                let defaultHabits = [
                    Habit(title: "물 마시기", icon: "drop.fill", colorHex: "#0A84FF"),
                    Habit(title: "스트레칭", icon: "figure.flexibility", colorHex: "#30D158"),
                    Habit(title: "독서", icon: "book.fill", colorHex: "#BF5AF2"),
                    Habit(title: "운동", icon: "figure.run", colorHex: "#FF9F0A"),
                    Habit(title: "비타민", icon: "pills.fill", colorHex: "#FF453A")
                ]
                for habit in defaultHabits {
                    context.insert(habit)
                }
                try? context.save()
            }
            didSeedDefaultHabits = true
        }
        #endif

        // --- 3. Generate Today's HabitRecords (main app only — the widget must
        //        not write habit/pet state) ---
        #if LOCKTODO_MAIN_APP
        if let activeHabits = try? context.fetch(FetchDescriptor<Habit>()) {
            let recordsDescriptor = FetchDescriptor<HabitRecord>()
            let records = (try? context.fetch(recordsDescriptor)) ?? []
            
            var recordCreated = false
            for habit in activeHabits where habit.isActive {
                let hasTodayRecord = records.contains { record in
                    record.habitID == habit.id && calendar.isDate(record.date, inSameDayAs: todayStart)
                }
                
                if !hasTodayRecord {
                    let newRecord = HabitRecord(habitID: habit.id, date: todayStart, isCompleted: false)
                    context.insert(newRecord)
                    recordCreated = true
                    
                    if let yesterday = calendar.date(byAdding: .day, value: -1, to: todayStart) {
                        let hasYesterdayCompletedRecord = records.contains { record in
                            record.habitID == habit.id && calendar.isDate(record.date, inSameDayAs: yesterday) && record.isCompleted
                        }
                        
                        if !hasYesterdayCompletedRecord && habit.streak > 0 {
                            habit.streak = 0
                        }
                    }
                }
            }
            if recordCreated {
                try? context.save()
            }
        }
        #endif
    }

    /// Removes duplicate habits and habit-records left behind by earlier races.
    /// Habits are matched exactly (title + icon + color) so genuinely distinct
    /// habits a user made are never merged; records are unique per habit + day.
    static func dedupeHabitsAndRecords(context: ModelContext) {
        var didChange = false

        if let habits = try? context.fetch(FetchDescriptor<Habit>()), habits.count > 1 {
            var seen = Set<String>()
            for habit in habits.sorted(by: { $0.createdAt < $1.createdAt }) {
                let key = "\(habit.title)|\(habit.icon)|\(habit.colorHex)"
                if seen.contains(key) {
                    context.delete(habit)
                    didChange = true
                } else {
                    seen.insert(key)
                }
            }
        }

        let calendar = Calendar.current
        if let records = try? context.fetch(FetchDescriptor<HabitRecord>()), records.count > 1 {
            var seen = Set<String>()
            for record in records.sorted(by: { $0.date < $1.date }) {
                let day = calendar.startOfDay(for: record.date).timeIntervalSinceReferenceDate
                let key = "\(record.habitID.uuidString)|\(day)"
                if seen.contains(key) {
                    context.delete(record)
                    didChange = true
                } else {
                    seen.insert(key)
                }
            }
        }

        if didChange { try? context.save() }
    }

    private static let summaryKey = "locktodo.today.summary"
    private static let pendingShortcutKey = "locktodo.pending.shortcut"
    private static let pendingPrefillTitleKey = "locktodo.pending.prefill.title"
    private static let autoLiveActivityKey = "locktodo.auto.live.activity"
    private static let lockScreenBackgroundStyleKey = "locktodo.lockscreen.background.style"
    private static let lockScreenTaskPageIndexKey = "locktodo.lockscreen.task.page.index"
    private static let lastLockScreenActionKey = "locktodo.lockscreen.last.action"
    private static let lastLockScreenActionDateKey = "locktodo.lockscreen.last.action.date"
    private static let lastLockScreenActionStatusKey = "locktodo.lockscreen.last.action.status"
    private static let activeMapRouteKey = "locktodo.map.active.route"

    static let liveActivityTaskPageSize = 4
    static let widgetTaskPageSize = 4

    static var defaults: UserDefaults {
        UserDefaults(suiteName: appGroupIdentifier) ?? .standard
    }

    static func loadSummary() -> TaskSummarySnapshot {
        guard let data = defaults.data(forKey: summaryKey),
              var summary = try? JSONDecoder().decode(TaskSummarySnapshot.self, from: data) else {
            var empty = TaskSummarySnapshot.empty
            empty.pageIndex = lockScreenTaskPageIndex
            return empty
        }

        summary.pageIndex = lockScreenTaskPageIndex
        summary.activeMapRoute = activeMapTodoRoute
        if summary.activeMapRoute == nil, summary.focusTitle?.hasPrefix("이동:") == true {
            summary.focusTitle = nil
        }
        return summary
    }

    static func saveSummary(_ summary: TaskSummarySnapshot) {
        var summary = summary
        summary.pageIndex = lockScreenTaskPageIndex
        summary.activeMapRoute = normalizedActiveRoute(summary.activeMapRoute)
        if summary.activeMapRoute == nil, summary.focusTitle?.hasPrefix("이동:") == true {
            summary.focusTitle = nil
        }
        guard let data = try? JSONEncoder().encode(summary) else { return }
        defaults.set(data, forKey: summaryKey)
        defaults.set(Date.now.timeIntervalSince1970, forKey: "locktodo.today.summary.last_write")
        defaults.synchronize()
    }

    static var activeMapTodoRoute: MapTodoRouteSnapshot? {
        guard let data = defaults.data(forKey: activeMapRouteKey),
              let route = try? JSONDecoder().decode(MapTodoRouteSnapshot.self, from: data) else {
            return nil
        }

        guard route.isLockScreenActive() else {
            defaults.removeObject(forKey: activeMapRouteKey)
            return nil
        }
        return route
    }

    static func saveActiveMapTodoRoute(_ route: MapTodoRouteSnapshot) {
        guard let data = try? JSONEncoder().encode(route) else { return }
        defaults.set(data, forKey: activeMapRouteKey)
        recordLockScreenAction(route.lockScreenTitle, status: "지도 루트 시작")
        postDatabaseChangedNotification()
    }

    static func clearActiveMapTodoRoute() {
        defaults.removeObject(forKey: activeMapRouteKey)
        var summary = loadSummary()
        summary.activeMapRoute = nil
        if summary.focusTitle?.hasPrefix("이동:") == true {
            summary.focusTitle = nil
        }
        saveSummary(summary)
        recordLockScreenAction("지도 루트", status: "종료")
        postDatabaseChangedNotification()
    }

    private static func normalizedActiveRoute(_ route: MapTodoRouteSnapshot?) -> MapTodoRouteSnapshot? {
        if let route, route.isLockScreenActive() {
            return route
        }
        return activeMapTodoRoute
    }

    static var isAutoLiveActivityEnabled: Bool {
        guard defaults.object(forKey: autoLiveActivityKey) != nil else { return true }
        return defaults.bool(forKey: autoLiveActivityKey)
    }

    static func setAutoLiveActivityEnabled(_ isEnabled: Bool) {
        defaults.set(isEnabled, forKey: autoLiveActivityKey)
    }

    private static let patrolActiveKey = "locktodo.patrol.active"
    private static let activeLocationTaskMapKey = "locktodo.location.active_task_map"
    private static let liveActivityStartedAtKey = "locktodo.liveactivity.started_at"

    /// When the currently-running Live Activity was (re)started. Used to roll it
    /// over before iOS's ~8h auto-dismiss so the card effectively stays put.
    static var liveActivityStartedAt: Date? {
        get {
            let t = defaults.double(forKey: liveActivityStartedAtKey)
            return t > 0 ? Date(timeIntervalSince1970: t) : nil
        }
        set {
            if let newValue {
                defaults.set(newValue.timeIntervalSince1970, forKey: liveActivityStartedAtKey)
            } else {
                defaults.removeObject(forKey: liveActivityStartedAtKey)
            }
        }
    }

    /// A location task stays "active" (shown on the lock screen) only this long
    /// after we last confirmed you were near it. iOS geofence *exit* events are
    /// unreliable and the widget extension can't read your real location, so a
    /// once-triggered task would otherwise linger forever. This age cap — plus
    /// a same-day check — is the backstop that makes it disappear once you've
    /// moved on or the day rolls over. Every confirmed-nearby update refreshes
    /// the timestamp, so a task you're genuinely still next to never expires.
    private static let activeLocationMaxAge: TimeInterval = 4 * 3600

    static var isPatrolActive: Bool {
        defaults.bool(forKey: patrolActiveKey)
    }

    static var activeLocationTaskIDs: Set<UUID> {
        Set(prunedActiveLocationMap().keys.compactMap(UUID.init(uuidString:)))
    }

    private static func activeLocationMap() -> [String: Double] {
        (defaults.dictionary(forKey: activeLocationTaskMapKey) as? [String: Double]) ?? [:]
    }

    /// Drops entries older than the max age or from a previous day, writing the
    /// cleaned map back so the expiry self-heals even inside the widget process.
    @discardableResult
    private static func prunedActiveLocationMap() -> [String: Double] {
        let now = Date.now
        let calendar = Calendar.current
        let map = activeLocationMap()
        let valid = map.filter { _, timestamp in
            let stamped = Date(timeIntervalSince1970: timestamp)
            return calendar.isDate(stamped, inSameDayAs: now)
                && now.timeIntervalSince(stamped) < activeLocationMaxAge
        }
        if valid.count != map.count {
            defaults.set(valid, forKey: activeLocationTaskMapKey)
        }
        return valid
    }

    @discardableResult
    static func setLocationTask(_ taskID: UUID, isActive: Bool) -> Bool {
        var map = prunedActiveLocationMap()
        let key = taskID.uuidString
        let changed: Bool
        if isActive {
            changed = map[key] == nil
            map[key] = Date.now.timeIntervalSince1970 // always refresh so it stays alive
        } else {
            changed = map.removeValue(forKey: key) != nil
        }
        defaults.set(map, forKey: activeLocationTaskMapKey)
        return changed
    }

    @discardableResult
    static func replaceActiveLocationTaskIDs(with taskIDs: Set<UUID>) -> Bool {
        let existing = Set(prunedActiveLocationMap().keys.compactMap(UUID.init(uuidString:)))
        let changed = taskIDs != existing
        // Refresh timestamps for everything currently nearby; anything absent
        // here is dropped. Runs on every location update, so nearby tasks keep
        // a fresh stamp and only truly-left ones age out.
        let now = Date.now.timeIntervalSince1970
        let map = Dictionary(uniqueKeysWithValues: taskIDs.map { ($0.uuidString, now) })
        defaults.set(map, forKey: activeLocationTaskMapKey)
        return changed
    }

    static func setPatrolActive(_ isActive: Bool) {
        defaults.set(isActive, forKey: patrolActiveKey)
        postDatabaseChangedNotification()
    }

    static var lockScreenBackgroundStyle: LockTodoLockScreenBackgroundStyle {
        guard let rawValue = defaults.string(forKey: lockScreenBackgroundStyleKey),
              let style = LockTodoLockScreenBackgroundStyle(rawValue: rawValue) else {
            return .transparent
        }
        return style
    }

    static func setLockScreenBackgroundStyle(_ style: LockTodoLockScreenBackgroundStyle) {
        defaults.set(style.rawValue, forKey: lockScreenBackgroundStyleKey)
    }

    static var lockScreenTaskPageIndex: Int {
        max(0, defaults.integer(forKey: lockScreenTaskPageIndexKey))
    }

    static func setLockScreenTaskPageIndex(_ pageIndex: Int) {
        defaults.set(max(0, pageIndex), forKey: lockScreenTaskPageIndexKey)
    }

    @discardableResult
    static func advanceLockScreenTaskPage(totalCount: Int, pageSize: Int, showsNextPage: Bool) -> Int {
        let safePageSize = max(1, pageSize)
        let pageCount = max(1, Int(ceil(Double(max(0, totalCount)) / Double(safePageSize))))
        let currentPage = min(lockScreenTaskPageIndex, pageCount - 1)
        let nextPage: Int

        if showsNextPage {
            nextPage = (currentPage + 1) % pageCount
        } else {
            nextPage = (currentPage - 1 + pageCount) % pageCount
        }

        setLockScreenTaskPageIndex(nextPage)
        return nextPage
    }

    static func liveActivityStaleDate(now: Date = .now, calendar: Calendar = .current) -> Date {
        calendar.date(byAdding: .hour, value: 24, to: now) ?? now.addingTimeInterval(24 * 60 * 60)
    }

    static func recordLockScreenAction(_ action: String, status: String) {
        defaults.set(action, forKey: lastLockScreenActionKey)
        defaults.set(Date.now, forKey: lastLockScreenActionDateKey)
        defaults.set(status, forKey: lastLockScreenActionStatusKey)
    }

    static var lastLockScreenActionDescription: String {
        guard let action = defaults.string(forKey: lastLockScreenActionKey),
              let status = defaults.string(forKey: lastLockScreenActionStatusKey),
              let date = defaults.object(forKey: lastLockScreenActionDateKey) as? Date else {
            return "기록 없음"
        }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.dateFormat = "HH:mm:ss"
        return "\(formatter.string(from: date)) · \(action) · \(status)"
    }

    @MainActor
    static func saveSummary(
        from tasks: [TaskItem],
        focusTask: TaskItem? = nil,
        focusTitle: String? = nil,
        calendar: Calendar = .current
    ) {
        saveSummary(summary(from: tasks, forDate: .now, focusTask: focusTask, focusTitle: focusTitle, calendar: calendar))
    }

    @MainActor
    static func summary(
        from tasks: [TaskItem],
        forDate targetDate: Date = .now,
        focusTask: TaskItem? = nil,
        focusTitle: String? = nil,
        calendar: Calendar = .current
    ) -> TaskSummarySnapshot {
        let targetStart = calendar.startOfDay(for: targetDate)

        // One context for the whole call: this runs on every widget timeline
        // reload and Live Activity refresh, so spinning up a fresh context per
        // fetch was needless churn on the hot path.
        let context = ModelContext(sharedModelContainer)
        let boards: [TaskBoard] = (try? context.fetch(FetchDescriptor<TaskBoard>())) ?? []

        let sortedTasks = tasks.sorted { lhs, rhs in
            if lhs.isCompleted != rhs.isCompleted { return !lhs.isCompleted }
            if lhs.isImportant != rhs.isImportant { return lhs.isImportant }
            return lhs.sortOrder < rhs.sortOrder
        }
        #if LOCKTODO_MAIN_APP
        let nearbyLocationTaskIDs = Set(LocationReminderService.shared.nearbyTasks(from: tasks).map(\.id))
            .union(activeLocationTaskIDs)
        #else
        let nearbyLocationTaskIDs = activeLocationTaskIDs
        #endif

        let allSnapshots: [SharedTaskSnapshot] = sortedTasks.compactMap { task in
            guard !task.showOnlyAtLocation || nearbyLocationTaskIDs.contains(task.id) else {
                return nil
            }

            let occurs: Bool
            let isCompleted: Bool
            
            if task.isCompleted {
                if let completedAt = task.completedAt {
                    occurs = calendar.isDate(completedAt, inSameDayAs: targetStart)
                } else {
                    occurs = false
                }
                isCompleted = true
            } else {
                let taskOccurs = task.occurs(on: targetDate, calendar: calendar)
                    || (task.hasLocationTrigger && nearbyLocationTaskIDs.contains(task.id))
                occurs = taskOccurs
                isCompleted = false
            }
            
            guard occurs else { return nil }
            
            let matchedBoard = boards.first { $0.id == task.boardID }
            return SharedTaskSnapshot(
                id: task.id,
                title: task.title,
                isCompleted: isCompleted,
                isImportant: task.isImportant,
                dueDate: isCompleted ? task.dueDate : targetStart,
                dueTime: task.dueTime,
                boardID: task.boardID,
                boardName: matchedBoard?.name,
                boardColorHex: matchedBoard?.colorHex,
                colorHex: task.colorHex
            )
        }

        let visibleTasks = allSnapshots
            .sorted { lhs, rhs in
                if lhs.isCompleted != rhs.isCompleted { return !lhs.isCompleted }
                if lhs.isImportant != rhs.isImportant { return lhs.isImportant }
                return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
            }
            .prefix(3)

        let habitSnapshots: [SharedHabitSnapshot] = {
            let fetchedHabits = (try? context.fetch(FetchDescriptor<Habit>())) ?? []
            let fetchedRecords = (try? context.fetch(FetchDescriptor<HabitRecord>())) ?? []
            let todayStart = calendar.startOfDay(for: targetDate)
            
            return fetchedHabits.filter(\.isActive).map { habit in
                let isCompleted = fetchedRecords.contains { record in
                    record.habitID == habit.id && calendar.isDate(record.date, inSameDayAs: todayStart) && record.isCompleted
                }
                return SharedHabitSnapshot(
                    id: habit.id,
                    title: habit.title,
                    isCompleted: isCompleted,
                    icon: habit.icon,
                    colorHex: habit.colorHex,
                    streak: habit.streak
                )
            }
        }()

        return TaskSummarySnapshot(
            generatedAt: targetDate,
            totalCount: allSnapshots.count,
            completedCount: allSnapshots.filter(\.isCompleted).count,
            remainingCount: allSnapshots.filter { !$0.isCompleted }.count,
            importantTasks: Array(visibleTasks),
            allTodayTasks: allSnapshots,
            pageIndex: lockScreenTaskPageIndex,
            focusTitle: focusTask?.title ?? focusTitle,
            activeMapRoute: activeMapTodoRoute,
            allTodayHabits: habitSnapshots
        )
    }

    @MainActor
    static func summaryForAllTasks(tasks: [TaskItem], calendar: Calendar = .current) -> TaskSummarySnapshot {
        let boards: [TaskBoard] = {
            let context = ModelContext(sharedModelContainer)
            let fetched = try? context.fetch(FetchDescriptor<TaskBoard>())
            return fetched ?? []
        }()

        let sortedTasks = tasks.sorted { lhs, rhs in
            if lhs.isCompleted != rhs.isCompleted { return !lhs.isCompleted }
            if lhs.isImportant != rhs.isImportant { return lhs.isImportant }
            return lhs.sortOrder < rhs.sortOrder
        }

        let allSnapshots: [SharedTaskSnapshot] = sortedTasks.map { task in
            let matchedBoard = boards.first { $0.id == task.boardID }
            return SharedTaskSnapshot(
                id: task.id,
                title: task.title,
                isCompleted: task.isCompleted,
                isImportant: task.isImportant,
                dueDate: task.dueDate,
                dueTime: task.dueTime,
                boardID: task.boardID,
                boardName: matchedBoard?.name,
                boardColorHex: matchedBoard?.colorHex,
                colorHex: task.colorHex
            )
        }

        return TaskSummarySnapshot(
            generatedAt: .now,
            totalCount: allSnapshots.count,
            completedCount: allSnapshots.filter(\.isCompleted).count,
            remainingCount: allSnapshots.filter { !$0.isCompleted }.count,
            importantTasks: Array(allSnapshots.filter(\.isImportant).prefix(3)),
            allTodayTasks: allSnapshots,
            pageIndex: lockScreenTaskPageIndex,
            focusTitle: WidgetDataStore.loadSummary().focusTitle,
            activeMapRoute: activeMapTodoRoute
        )
    }

    static func setPendingShortcut(_ action: ShortcutAction, prefillTitle: String? = nil) {
        defaults.set(action.rawValue, forKey: pendingShortcutKey)
        defaults.set(prefillTitle, forKey: pendingPrefillTitleKey)
    }

    static func takePendingShortcut() -> (ShortcutAction, String?)? {
        guard let rawValue = defaults.string(forKey: pendingShortcutKey),
              let action = ShortcutAction(rawValue: rawValue) else {
            return nil
        }
        let title = defaults.string(forKey: pendingPrefillTitleKey)
        defaults.removeObject(forKey: pendingShortcutKey)
        defaults.removeObject(forKey: pendingPrefillTitleKey)
        return (action, title)
    }
}

enum ShortcutAction: String, Codable {
    case addTask
    case startFocus
}

// MARK: - Real-time Database Synchronization Helpers

extension WidgetDataStore {
    static let databaseChangedNotificationName = "com.jaeseok.LockTodo.databaseChanged"
    
    static var lastLocalChangeCount: Int {
        get { defaults.integer(forKey: "lastLocalChangeCount") }
        set { defaults.set(newValue, forKey: "lastLocalChangeCount") }
    }
    
    static var dbChangeCounter: Int {
        get { defaults.integer(forKey: "dbChangeCounter") }
        set { defaults.set(newValue, forKey: "dbChangeCounter") }
    }
    
    static func incrementChangeCounter() {
        let next = dbChangeCounter + 1
        dbChangeCounter = next
    }

    static func postDatabaseChangedNotification() {
        incrementChangeCounter()
        let center = CFNotificationCenterGetDarwinNotifyCenter()
        CFNotificationCenterPostNotification(
            center,
            CFNotificationName(databaseChangedNotificationName as CFString),
            nil,
            nil,
            true
        )
    }
    
    static func registerDarwinObserver() {
        CFNotificationCenterAddObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            nil,
            { _, _, _, _, _ in
                DispatchQueue.main.async {
                    NotificationCenter.default.post(name: .lockTodoDatabaseChangedExternal, object: nil)
                }
            },
            databaseChangedNotificationName as CFString,
            nil,
            .deliverImmediately
        )
    }
}

extension ModelContext {
    var managedObjectContext: NSManagedObjectContext? {
        guard let child = Mirror(reflecting: self).children.first(where: { $0.label == "_nsContext" }) else {
            return nil
        }
        return child.value as? NSManagedObjectContext
    }
    
    func refreshAll() {
        managedObjectContext?.refreshAllObjects()
    }
}

extension Notification.Name {
    static let lockTodoDatabaseChangedExternal = Notification.Name("LockTodoDatabaseChangedExternal")
}
