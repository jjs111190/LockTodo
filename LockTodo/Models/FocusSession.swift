import Foundation
import SwiftData

/// One focus (Pomodoro-style) session run against a task. Logged so the
/// Insights screen can show how much deep-focus time a day/week actually held —
/// the counterpart to "how many tasks did I finish".
@Model
final class FocusSession {
    @Attribute(.unique) var id: UUID
    /// The task this session was for, if it still exists. Kept loose (no
    /// relationship) so deleting the task never cascades into the focus history.
    var taskID: UUID?
    var taskTitle: String
    var targetMinutes: Int
    /// Seconds actually spent focused before finishing or stopping.
    var focusedSeconds: Int
    var startedAt: Date
    /// Whether the full target was reached (vs. ended early).
    var completedFully: Bool
    var colorHex: String

    init(
        id: UUID = UUID(),
        taskID: UUID? = nil,
        taskTitle: String,
        targetMinutes: Int,
        focusedSeconds: Int,
        startedAt: Date = .now,
        completedFully: Bool,
        colorHex: String = TaskTint.defaultHex
    ) {
        self.id = id
        self.taskID = taskID
        self.taskTitle = taskTitle
        self.targetMinutes = targetMinutes
        self.focusedSeconds = focusedSeconds
        self.startedAt = startedAt
        self.completedFully = completedFully
        self.colorHex = colorHex
    }

    var focusedMinutes: Int { focusedSeconds / 60 }
}
