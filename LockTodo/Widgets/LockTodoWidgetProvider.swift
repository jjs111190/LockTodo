import WidgetKit
import SwiftUI
import SwiftData

struct LockTodoWidgetEntry: TimelineEntry {
    let date: Date
    let summary: TaskSummarySnapshot
}

struct LockTodoWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> LockTodoWidgetEntry {
        LockTodoWidgetEntry(date: .now, summary: .empty)
    }

    func getSnapshot(in context: Context, completion: @escaping (LockTodoWidgetEntry) -> Void) {
        Task { @MainActor in
            let now = Date.now
            completion(LockTodoWidgetEntry(date: now, summary: currentSummary(at: now)))
        }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<LockTodoWidgetEntry>) -> Void) {
        Task { @MainActor in
            let calendar = Calendar.current
            let now = Date.now
            let startOfTomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) ?? now.addingTimeInterval(86400)
            let refreshAfterMidnight = calendar.date(byAdding: .minute, value: 1, to: startOfTomorrow) ?? startOfTomorrow.addingTimeInterval(60)
            let safetyRefresh = now.addingTimeInterval(15 * 60)
            let nextRefresh = min(safetyRefresh, refreshAfterMidnight)
            let currentEntry = LockTodoWidgetEntry(date: now, summary: currentSummary(at: now))
            
            let container = WidgetDataStore.sharedModelContainer
            let modelContext = ModelContext(container)
            
            if let tasks = try? modelContext.fetch(FetchDescriptor<TaskItem>()) {
                var entries = [currentEntry]
                
                let tomorrowSummary = WidgetDataStore.summary(from: tasks, forDate: startOfTomorrow)
                let tomorrowEntry = LockTodoWidgetEntry(date: startOfTomorrow, summary: tomorrowSummary)
                entries.append(tomorrowEntry)
                
                completion(Timeline(entries: entries, policy: .after(nextRefresh)))
            } else {
                completion(Timeline(entries: [currentEntry], policy: .after(nextRefresh)))
            }
        }
    }

    @MainActor
    private func currentSummary(at now: Date) -> TaskSummarySnapshot {
        // Always recompute rather than trusting the saved snapshot. The snapshot
        // is frozen at save time, so a task you left the area for (or a past-date
        // one) would keep showing until the app happened to re-save. Rebuilding
        // here re-applies the self-expiring location IDs and the date filter, so
        // stale location/date tasks drop off every widget refresh.
        let storedSummary = WidgetDataStore.loadSummary()
        let container = WidgetDataStore.sharedModelContainer
        let context = ModelContext(container)
        WidgetDataStore.autoUpdateTaskCategories(context: context)

        if let tasks = try? context.fetch(FetchDescriptor<TaskItem>()) {
            let focus = tasks.first { $0.title == storedSummary.focusTitle }
            let refreshedSummary = WidgetDataStore.summary(from: tasks, forDate: now, focusTask: focus)
            WidgetDataStore.saveSummary(refreshedSummary)
            return refreshedSummary
        }

        return storedSummary
    }
}
