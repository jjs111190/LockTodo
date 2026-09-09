import Foundation
import ActivityKit
import SwiftData

@MainActor
final class LiveActivityService: ObservableObject {
    static let shared = LiveActivityService()

    @Published private(set) var isRunning = false
    private var activityObservers: [String: Task<Void, Never>] = [:]

    /// iOS force-ends Live Activities after ~8h. We proactively roll ours over
    /// once it passes this age so it never actually reaches that cap while the
    /// app is opened periodically. Kept comfortably under 8h for headroom.
    private let rollOverAge: TimeInterval = 7 * 3600
    /// Marks content stale near the cap so the system keeps it fresh-looking.
    private let staleWindow: TimeInterval = 8 * 3600

    private init() {}

    private func staleDate() -> Date { Date.now.addingTimeInterval(staleWindow) }

    func refreshState() {
        isRunning = !Activity<LockTodoActivityAttributes>.activities.isEmpty
    }

    /// iOS force-ends Live Activities after roughly 8 hours, and the `.ended`
    /// callback that would recreate ours only fires while the app process is
    /// alive — so a backgrounded app silently loses its lock-screen card and
    /// never gets it back. Re-arming whenever the app returns to the foreground
    /// resets that window: as long as the app is opened within the limit, the
    /// pinned card effectively stays put. (A true always-on card would need an
    /// ActivityKit push server, which this offline app deliberately avoids.)
    func reactivateIfNeeded() async {
        let activities = Activity<LockTodoActivityAttributes>.activities

        if !activities.isEmpty {
            // Roll it over before iOS's ~8h cap kills it: end the aging one and
            // start a fresh card, resetting the window. Otherwise just refresh
            // its contents to the current day.
            if let startedAt = WidgetDataStore.liveActivityStartedAt,
               Date.now.timeIntervalSince(startedAt) >= rollOverAge {
                await end()
                let summary = refreshedSummaryIfNeeded()
                if shouldStartLiveActivity(for: .from(summary: summary)) {
                    await startOrUpdate(summary: summary)
                }
            } else {
                await updateCurrentSummary(startIfNeeded: false)
            }
            return
        }

        let summary = refreshedSummaryIfNeeded()
        let state = LockTodoActivityAttributes.ContentState.from(summary: summary)
        guard shouldStartLiveActivity(for: state) else {
            isRunning = false
            return
        }
        await startOrUpdate(summary: summary)
    }

    func startOrUpdate(from tasks: [TaskItem], focusTask: TaskItem? = nil, focusTitle: String? = nil) async {
        WidgetDataStore.saveSummary(from: tasks, focusTask: focusTask, focusTitle: focusTitle)
        await startOrUpdate(summary: WidgetDataStore.loadSummary())
    }

    func startOrUpdate(summary: TaskSummarySnapshot) async {
        let state = LockTodoActivityAttributes.ContentState.from(summary: summary)
        let activities = Activity<LockTodoActivityAttributes>.activities

        if !activities.isEmpty {
            await updateExistingActivities(with: state)
            observe(activities)
            isRunning = true
            return
        }

        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            isRunning = false
            return
        }

        do {
            let attributes = LockTodoActivityAttributes(dayIdentifier: Self.todayIdentifier())
            _ = try Activity.request(
                attributes: attributes,
                content: ActivityContent(state: state, staleDate: staleDate()),
                pushType: nil
            )
            WidgetDataStore.liveActivityStartedAt = .now
            observe(Activity<LockTodoActivityAttributes>.activities)
            isRunning = true
        } catch {
            isRunning = false
        }
    }

    func update(from tasks: [TaskItem], focusTask: TaskItem? = nil, focusTitle: String? = nil) async {
        WidgetDataStore.saveSummary(from: tasks, focusTask: focusTask, focusTitle: focusTitle)
        await updateCurrentSummary(startIfNeeded: true)
    }

    func updateCurrentSummary(startIfNeeded: Bool = true) async {
        let summary = refreshedSummaryIfNeeded()
        let state = LockTodoActivityAttributes.ContentState.from(summary: summary)

        guard !Activity<LockTodoActivityAttributes>.activities.isEmpty else {
            if startIfNeeded && shouldStartLiveActivity(for: state) {
                await startOrUpdate(summary: summary)
            } else {
                isRunning = false
            }
            return
        }

        await updateExistingActivities(with: state)
        refreshState()
    }

    func end() async {
        activityObservers.values.forEach { $0.cancel() }
        activityObservers.removeAll()
        let state = LockTodoActivityAttributes.ContentState.from(summary: WidgetDataStore.loadSummary())
        for activity in Activity<LockTodoActivityAttributes>.activities {
            await activity.end(ActivityContent(state: state, staleDate: nil), dismissalPolicy: .immediate)
        }
        WidgetDataStore.liveActivityStartedAt = nil
        isRunning = false
    }

    private func updateExistingActivities(with state: LockTodoActivityAttributes.ContentState) async {
        for activity in Activity<LockTodoActivityAttributes>.activities {
            await activity.update(
                ActivityContent(
                    state: state,
                    staleDate: staleDate()
                )
            )
        }
        observe(Activity<LockTodoActivityAttributes>.activities)
    }

    private func shouldStartLiveActivity(for state: LockTodoActivityAttributes.ContentState) -> Bool {
        if WidgetDataStore.isPatrolActive { return true }
        guard WidgetDataStore.isAutoLiveActivityEnabled else { return false }
        return true
    }

    private func observe(_ activities: [Activity<LockTodoActivityAttributes>]) {
        let activeIDs = Set(activities.map(\.id))
        for (id, observer) in activityObservers where !activeIDs.contains(id) {
            observer.cancel()
            activityObservers[id] = nil
        }

        for activity in activities where activityObservers[activity.id] == nil {
            activityObservers[activity.id] = Task { [weak self] in
                for await state in activity.activityStateUpdates {
                    guard !Task.isCancelled else { return }
                    await self?.handleActivityState(state, activityID: activity.id)
                }
            }
        }
    }

    private func handleActivityState(_ state: ActivityState, activityID: String) async {
        refreshState()
        guard state == .ended || state == .dismissed else { return }
        activityObservers[activityID]?.cancel()
        activityObservers[activityID] = nil

        // Respect an explicit swipe-away. Recreating a dismissed activity can
        // feel like lock-screen spam and ignores the user's choice.
        guard state == .ended else { return }
        guard WidgetDataStore.isAutoLiveActivityEnabled || WidgetDataStore.isPatrolActive else { return }
        try? await Task.sleep(for: .milliseconds(500))
        await updateCurrentSummary(startIfNeeded: true)
    }

    /// Always rebuilds the summary from live data instead of trusting the saved
    /// snapshot. The snapshot is frozen at save time, so a task added while you
    /// were at a place (or a past-dated one) would linger in it all day. Rebuild
    /// re-applies the current location (self-expiring nearby IDs) and date
    /// filters, so left-location and past-date tasks actually drop out.
    private func refreshedSummaryIfNeeded() -> TaskSummarySnapshot {
        let storedSummary = WidgetDataStore.loadSummary()
        let context = ModelContext(WidgetDataStore.sharedModelContainer)
        WidgetDataStore.autoUpdateTaskCategories(context: context)

        guard let tasks = try? context.fetch(FetchDescriptor<TaskItem>()) else {
            return storedSummary
        }

        let focus = tasks.first { $0.title == storedSummary.focusTitle }
        let summary = WidgetDataStore.summary(from: tasks, focusTask: focus)
        WidgetDataStore.saveSummary(summary)
        return summary
    }

    private static func todayIdentifier() -> String {
        let formatter = DateFormatter()
        formatter.calendar = .current
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: .now)
    }
}
