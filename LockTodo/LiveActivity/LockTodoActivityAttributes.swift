import Foundation
import ActivityKit

struct LockTodoActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var remainingCount: Int
        var completedCount: Int
        var totalCount: Int
        var importantTitles: [String]
        var taskSnapshots: [SharedTaskSnapshot]
        var allTodayHabits: [SharedHabitSnapshot]
        var pageIndex: Int
        var pageCount: Int
        var pageRangeText: String
        var focusTitle: String?
        var updatedAt: Date
        var displayCombinedItems: [SharedCombinedItem]

        var activeMapRoute: MapTodoRouteSnapshot?

        var progress: Double {
            let total = totalCount
            guard total > 0 else { return 1 }
            return min(max(Double(completedCount) / Double(total), 0), 1)
        }

        var isDone: Bool {
            totalCount > 0 && remainingCount == 0
        }
    }

    var dayIdentifier: String
}

extension LockTodoActivityAttributes.ContentState {
    static func from(summary: TaskSummarySnapshot) -> Self {
        let pageSize = WidgetDataStore.liveActivityTaskPageSize
        let combined = summary.totalCombinedItems
        let completed = combined.filter(\.isCompleted).count
        let remaining = combined.count - completed
        
        return LockTodoActivityAttributes.ContentState(
            remainingCount: remaining,
            completedCount: completed,
            totalCount: combined.count,
            importantTitles: summary.orderedTasks.prefix(3).map(\.title),
            taskSnapshots: summary.pageTasks(pageSize: pageSize),
            allTodayHabits: summary.allTodayHabits,
            pageIndex: summary.clampedPageIndex(pageSize: pageSize),
            pageCount: summary.pageCount(pageSize: pageSize),
            pageRangeText: summary.pageRangeText(pageSize: pageSize),
            focusTitle: summary.focusTitle,
            updatedAt: summary.generatedAt,
            displayCombinedItems: summary.pageCombinedItems(pageSize: pageSize),
            activeMapRoute: summary.activeMapRoute
        )
    }

    static let sample = LockTodoActivityAttributes.ContentState(
        remainingCount: 3,
        completedCount: 2,
        totalCount: 5,
        importantTitles: ["기획안 마무리", "마트 체크리스트", "운동 30분"],
        taskSnapshots: TaskSummarySnapshot.sample.pageTasks(pageSize: WidgetDataStore.liveActivityTaskPageSize),
        allTodayHabits: [],
        pageIndex: 0,
        pageCount: TaskSummarySnapshot.sample.pageCount(pageSize: WidgetDataStore.liveActivityTaskPageSize),
        pageRangeText: TaskSummarySnapshot.sample.pageRangeText(pageSize: WidgetDataStore.liveActivityTaskPageSize),
        focusTitle: "기획안 마무리",
        updatedAt: .now,
        displayCombinedItems: [],
        activeMapRoute: TaskSummarySnapshot.sample.activeMapRoute
    )
}
