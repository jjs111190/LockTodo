import Foundation

enum ShortcutService {
    static let addTaskURL = URL(string: "locktodo://add")!
    static let todayURL = URL(string: "locktodo://today")!
    static let focusURL = URL(string: "locktodo://focus")!
    static let mapURL = URL(string: "locktodo://map")!

    static func taskURL(id: UUID) -> URL {
        URL(string: "locktodo://task/\(id.uuidString)")!
    }

    static func queueAddTask(prefillTitle: String? = nil) {
        WidgetDataStore.setPendingShortcut(.addTask, prefillTitle: prefillTitle)
    }

    static func queueStartFocus(prefillTitle: String? = nil) {
        WidgetDataStore.setPendingShortcut(.startFocus, prefillTitle: prefillTitle)
    }

    static func takePendingAction() -> (ShortcutAction, String?)? {
        WidgetDataStore.takePendingShortcut()
    }
}
