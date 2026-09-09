import Foundation
import SwiftData
import WatchConnectivity
import WidgetKit

final class WatchConnectivityService: NSObject, WCSessionDelegate {
    static let shared = WatchConnectivityService()

    private enum MessageKey {
        static let summary = "summary"
        static let command = "command"
        static let taskID = "taskID"
        static let isCompleted = "isCompleted"
    }

    private override init() {
        super.init()
    }

    func start() {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        session.delegate = self
        session.activate()
    }

    @MainActor
    func sendCurrentSummary() {
        let context = ModelContext(WidgetDataStore.sharedModelContainer)
        WidgetDataStore.autoUpdateTaskCategories(context: context)
        let tasks = (try? context.fetch(FetchDescriptor<TaskItem>())) ?? []
        let summary = WidgetDataStore.summary(from: tasks)
        send(summary: summary)
    }

    func send(summary: TaskSummarySnapshot) {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        guard session.activationState == .activated else { return }
        guard canSendApplicationContext(to: session) else { return }
        guard let data = try? JSONEncoder().encode(summary) else { return }

        let payload: [String: Any] = [MessageKey.summary: data]
        try? session.updateApplicationContext(payload)

        if session.isReachable {
            session.sendMessage(payload, replyHandler: nil)
        }
    }

    private func canSendApplicationContext(to session: WCSession) -> Bool {
        #if os(iOS)
        session.isPaired && session.isWatchAppInstalled
        #else
        true
        #endif
    }

    func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        guard activationState == .activated else { return }
        Task { @MainActor in
            sendCurrentSummary()
        }
    }

    func sessionDidBecomeInactive(_ session: WCSession) {}

    func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }

    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        handle(message)
    }

    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        handle(userInfo)
    }

    private func handle(_ message: [String: Any]) {
        guard let command = message[MessageKey.command] as? String else {
            return
        }

        if command == "refresh" {
            Task { @MainActor in
                sendCurrentSummary()
            }
            return
        }

        guard command == "toggleTask",
              let taskID = message[MessageKey.taskID] as? String,
              let isCompleted = message[MessageKey.isCompleted] as? Bool else {
            return
        }

        Task { @MainActor in
            try? await LockTodoTaskMutationStore.setCompletion(
                taskIDString: taskID,
                isCompleted: isCompleted
            )
            sendCurrentSummary()
            WidgetCenter.shared.reloadAllTimelines()
        }
    }
}
