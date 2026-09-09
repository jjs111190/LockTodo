import SwiftUI
import SwiftData

enum TaskRowStyle {
    case card
    case plain
}

struct TaskRow: View {
    @Environment(\.colorScheme) private var colorScheme
    @Bindable var task: TaskItem
    var onToggle: () -> Void
    var onDelete: () -> Void
    var onFocus: () -> Void
    var onEdit: () -> Void
    var isSelectionMode: Bool
    var isSelected: Bool
    var style: TaskRowStyle

    init(
        task: TaskItem,
        onToggle: @escaping () -> Void,
        onDelete: @escaping () -> Void,
        onFocus: @escaping () -> Void,
        onEdit: @escaping () -> Void,
        isSelectionMode: Bool = false,
        isSelected: Bool = false,
        style: TaskRowStyle = .card
    ) {
        self.task = task
        self.onToggle = onToggle
        self.onDelete = onDelete
        self.onFocus = onFocus
        self.onEdit = onEdit
        self.isSelectionMode = isSelectionMode
        self.isSelected = isSelected
        self.style = style
    }

    var body: some View {
        let taskColor = Color(hex: task.safeColorHex)
        let isDone = !isSelectionMode && task.isCompleted
        let shape = RoundedRectangle(cornerRadius: LockTodoDesign.cardRadius, style: .continuous)

        HStack(alignment: .top, spacing: 12) {
            Button(action: onToggle) {
                Image(systemName: checkboxSymbol)
                    .font(.system(size: 22))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(checkboxTint(taskColor))
                    .contentTransition(.symbolEffect(.replace.offUp))
                    .frame(width: 26, height: 26)
                    // Negative inset grows the touch target to a comfortable
                    // 44pt without pushing the layout around.
                    .contentShape(Circle().inset(by: -9))
            }
            .buttonStyle(TactileButtonStyle(pressedScale: 0.86))
            .accessibilityLabel(isSelectionMode ? (isSelected ? "선택됨" : "선택 안됨") : (task.isCompleted ? "미완료로 변경" : "완료"))

            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text(task.title)
                        .font(.system(.body, weight: task.isImportant ? .semibold : .regular))
                        .tracking(-0.1)
                        .strikethrough(isDone, color: .secondary)
                        .foregroundStyle(isDone ? .secondary : .primary)
                        .lineLimit(2)

                    if task.isImportant {
                        Image(systemName: "star.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(.orange)
                            .accessibilityLabel("중요")
                    }
                }

                statusBadges(taskColor: taskColor)
                metadata
            }
            // Completion drains a row of emphasis rather than hiding it — the
            // record still counts, it just stops competing for attention.
            .opacity(isDone ? 0.62 : 1)

            Spacer(minLength: 8)

            if !isSelectionMode {
                Menu {
                    Button(action: onEdit) {
                        Label("수정", systemImage: "pencil")
                    }
                    Button(action: onFocus) {
                        Label("집중 항목", systemImage: "scope")
                    }
                    Button(role: .destructive, action: onDelete) {
                        Label("삭제", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.tertiary)
                        .frame(width: 30, height: 30)
                        .contentShape(Rectangle())
                }
                .buttonStyle(TactileButtonStyle(pressedScale: 0.88))
            }
        }
        .padding(style == .card ? 14 : 10)
        .background {
            if style == .card {
                shape.fill(LockTodoDesign.cardBackground)
            }
        }
        .overlay {
            if style == .card {
                shape.strokeBorder(LockTodoDesign.separator, lineWidth: LockTodoDesign.hairline)
            }
        }
        .overlay(alignment: .leading) {
            // The task's colour lives on a leading edge marker instead of a
            // floating dot in the corner: it belongs to the whole row, and it
            // reads as a category at a glance down a long list.
            if style == .card {
                Capsule()
                    .fill(task.isImportant ? Color.orange : taskColor)
                    .frame(width: 3)
                    .padding(.vertical, 14)
                    .padding(.leading, 1)
                    .opacity(isDone ? 0.35 : 1)
            }
        }
        .contentShape(shape)
        .lockTodoAnimation(LockTodoMotion.snappy, value: task.isCompleted)
        .contextMenu {
            if !isSelectionMode {
                Button(action: onEdit) {
                    Label("수정", systemImage: "pencil")
                }
                Button(action: onFocus) {
                    Label("집중 항목", systemImage: "scope")
                }
                Button(role: .destructive, action: onDelete) {
                    Label("삭제", systemImage: "trash")
                }
            }
        }
    }

    private var isMissed: Bool {
        guard !task.isCompleted, let dueDate = task.dueDate else { return false }
        return Calendar.current.startOfDay(for: dueDate) < Calendar.current.startOfDay(for: .now)
    }

    private var checkboxSymbol: String {
        if isSelectionMode {
            return isSelected ? "checkmark.circle.fill" : "circle"
        }
        return task.isCompleted ? "checkmark.circle.fill" : "circle"
    }

    private func checkboxTint(_ taskColor: Color) -> Color {
        if isSelectionMode {
            return isSelected ? taskColor : Color.secondary.opacity(0.5)
        }
        return task.isCompleted ? taskColor : taskColor.opacity(0.55)
    }

    @ViewBuilder
    private func statusBadges(taskColor: Color) -> some View {
        // "In progress" is the default state of every incomplete task, so
        // stamping a badge on it says nothing. Only the states that actually
        // need attention get one.
        if task.isCompleted {
            TaskStatusBadge(title: "완료", systemImage: "checkmark.seal.fill", tint: .green)
        } else if isMissed {
            TaskStatusBadge(title: "미달성", systemImage: "exclamationmark.circle.fill", tint: .orange)
        }
    }

    @ViewBuilder
    private var metadata: some View {
        let tags = task.tags
        if task.dueTime != nil || !tags.isEmpty || !task.notes.isEmpty || task.repeatRule != .none || task.hasLocationTrigger {
            HStack(spacing: 10) {
                if let dueTime = task.dueTime {
                    Label(dueTime.formatted(date: .omitted, time: .shortened), systemImage: "clock")
                        .monospacedDigit()
                }

                if task.hasLocationTrigger {
                    Label(task.locationDisplayName, systemImage: "location")
                        .lineLimit(1)
                }

                if task.repeatRule != .none {
                    Label(task.repeatRule.title, systemImage: "repeat")
                }

                if !task.notes.isEmpty {
                    Image(systemName: "note.text")
                        .accessibilityLabel("메모 있음")
                }

                ForEach(tags.prefix(2), id: \.self) { tag in
                    Text("#\(tag)")
                        .lineLimit(1)
                }
            }
            .font(.caption)
            .tracking(0.1)
            .foregroundStyle(.secondary)
            .labelStyle(TaskMetadataLabelStyle())
        }
    }
}

/// Metadata icons sit optically level with their text and a hair tighter than
/// a default `Label`, so each pair reads as one token instead of two things.
private struct TaskMetadataLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 3) {
            configuration.icon
                .font(.system(size: 10, weight: .medium))
            configuration.title
        }
    }
}

private struct TaskStatusBadge: View {
    var title: String
    var systemImage: String
    var tint: Color

    var body: some View {
        Label(title, systemImage: systemImage)
            .font(.caption2.weight(.semibold))
            .labelStyle(TaskMetadataLabelStyle())
            .foregroundStyle(tint)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(tint.opacity(0.12), in: Capsule())
    }
}
