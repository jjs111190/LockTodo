import Foundation
import SwiftUI

@MainActor
final class AppRouter: ObservableObject {
    enum Tab: Hashable {
        case today
        case map
        case calendar
        case settings
    }

    @Published var selectedTab: Tab = .today
    @Published var isAddTaskPresented = false
    @Published var addTaskInitialDate: Date? = Calendar.current.startOfDay(for: .now)
    @Published var addTaskPrefillTitle = ""
    @Published var quickAddPrefill = ""
    @Published var shouldFocusQuickAdd = false
    @Published var pendingTaskID: UUID?
    @Published var isQuickCaptureMode = false

    var addTaskBinding: Binding<Bool> {
        Binding(
            get: { self.isAddTaskPresented },
            set: { self.isAddTaskPresented = $0 }
        )
    }

    func presentAddTask(initialDate: Date? = Calendar.current.startOfDay(for: .now), prefillTitle: String = "", isQuickCapture: Bool = false) {
        selectedTab = .today
        addTaskInitialDate = initialDate
        addTaskPrefillTitle = prefillTitle
        isQuickCaptureMode = isQuickCapture
        isAddTaskPresented = true
        shouldFocusQuickAdd = true
    }

    func focusQuickAdd(prefillTitle: String = "") {
        selectedTab = .today
        quickAddPrefill = prefillTitle
        shouldFocusQuickAdd = true
    }

    func handle(url: URL) {
        guard url.scheme == "locktodo" else { return }

        switch url.host {
        case "capture":
            presentAddTask(prefillTitle: url.queryValue(named: "title") ?? "", isQuickCapture: true)
        case "add":
            presentAddTask(prefillTitle: url.queryValue(named: "title") ?? "", isQuickCapture: false)
        case "today":
            selectedTab = .today
            shouldFocusQuickAdd = false
        case "focus":
            selectedTab = .today
            shouldFocusQuickAdd = false
        case "calendar":
            selectedTab = .calendar
        case "map":
            selectedTab = .map
        case "task":
            if let idString = url.pathComponents.dropFirst().first,
               let id = UUID(uuidString: idString) {
                selectedTab = .today
                pendingTaskID = id
            }
        default:
            break
        }
    }

    func consumePendingShortcutIfNeeded() {
        guard let (action, prefillTitle) = ShortcutService.takePendingAction() else { return }
        switch action {
        case .addTask:
            presentAddTask(prefillTitle: prefillTitle ?? "")
        case .startFocus:
            selectedTab = .today
            shouldFocusQuickAdd = false
        }
    }
}

private extension URL {
    func queryValue(named name: String) -> String? {
        URLComponents(url: self, resolvingAgainstBaseURL: false)?
            .queryItems?
            .first { $0.name == name }?
            .value
    }
}
