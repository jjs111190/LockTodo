import Foundation
import UserNotifications

@MainActor
final class NotificationService: ObservableObject {
    static let shared = NotificationService()

    @Published private(set) var authorizationStatus: UNAuthorizationStatus = .notDetermined

    private init() {}

    func refreshAuthorizationStatus() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        authorizationStatus = settings.authorizationStatus
    }

    func requestAuthorization() async -> Bool {
        do {
            let granted = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
            await refreshAuthorizationStatus()
            return granted
        } catch {
            await refreshAuthorizationStatus()
            return false
        }
    }

    func registerCategories() {
        let openAction = UNNotificationAction(
            identifier: "OPEN_TASK",
            title: "열기",
            options: [.foreground]
        )
        let category = UNNotificationCategory(
            identifier: "TASK_REMINDER",
            actions: [openAction],
            intentIdentifiers: [],
            options: []
        )
        UNUserNotificationCenter.current().setNotificationCategories([category])
    }

    func scheduleReminder(for task: TaskItem) async {
        guard let reminderDate = task.reminderDate, reminderDate > .now else { return }

        let content = UNMutableNotificationContent()
        content.title = task.title
        content.body = task.notes.isEmpty ? "오늘 할 일을 확인하세요." : task.notes
        content.sound = .default
        content.categoryIdentifier = "TASK_REMINDER"
        content.userInfo = ["taskID": task.id.uuidString, "url": "locktodo://task/\(task.id.uuidString)"]

        var repeats = false
        let dateComponents: DateComponents
        switch task.repeatRule {
        case .none:
            dateComponents = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: reminderDate)
        case .daily, .weekdays:
            repeats = true
            dateComponents = Calendar.current.dateComponents([.hour, .minute], from: reminderDate)
        case .weekly:
            repeats = true
            dateComponents = Calendar.current.dateComponents([.weekday, .hour, .minute], from: reminderDate)
        case .monthly:
            repeats = true
            dateComponents = Calendar.current.dateComponents([.day, .hour, .minute], from: reminderDate)
        }

        let request = UNNotificationRequest(
            identifier: task.id.uuidString,
            content: content,
            trigger: UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: repeats)
        )

        try? await UNUserNotificationCenter.current().add(request)
    }

    func cancelReminder(for task: TaskItem) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [task.id.uuidString])
    }

    func scheduleEveningReminderIfNeeded(hour: Int = 20, minute: Int = 0) async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else { return }

        let content = UNMutableNotificationContent()
        content.title = "LockTodo"
        content.body = "오늘 끝내지 않은 일을 확인하세요."
        content.sound = .default
        content.userInfo = ["url": "locktodo://today"]

        var components = DateComponents()
        components.hour = hour
        components.minute = minute

        let request = UNNotificationRequest(
            identifier: "locktodo.evening.reminder",
            content: content,
            trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
        )
        try? await UNUserNotificationCenter.current().add(request)
    }

    func scheduleHabitReminder(for habit: Habit) async {
        cancelHabitReminder(for: habit)
        
        guard habit.isReminderEnabled, let reminderTime = habit.reminderTime else { return }
        
        // 오프셋 적용된 시각 구하기
        let offset = habit.reminderOffsetMinutes
        let triggerTime = Calendar.current.date(byAdding: .minute, value: -offset, to: reminderTime) ?? reminderTime
        
        let content = UNMutableNotificationContent()
        content.title = "루틴 알람: \(habit.title)"
        
        if offset == 0 {
            content.body = "오늘의 루틴을 실천할 시간이에요! 힘내세요! 💪"
        } else if offset % 60 == 0 {
            let hours = offset / 60
            content.body = "루틴 시작 \(hours)시간 전입니다! 잊지 말고 준비하세요. ⏰"
        } else {
            content.body = "루틴 시작 \(offset)분 전입니다! 잊지 말고 준비하세요. ⏰"
        }
        
        content.sound = .default
        content.userInfo = ["habitID": habit.id.uuidString, "url": "locktodo://today"]
        
        let dateComponents = Calendar.current.dateComponents([.hour, .minute], from: triggerTime)
        
        let request = UNNotificationRequest(
            identifier: "habit_\(habit.id.uuidString)",
            content: content,
            trigger: UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: true)
        )
        
        try? await UNUserNotificationCenter.current().add(request)
    }

    func cancelHabitReminder(for habit: Habit) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["habit_\(habit.id.uuidString)"])
    }
}
