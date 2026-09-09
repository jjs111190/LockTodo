import AppIntents
import WidgetKit
import SwiftUI

struct LockTodoLockScreenWidget: Widget {
    let kind = "LockTodoLockScreenWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: LockTodoWidgetProvider()) { entry in
            LockTodoLockScreenWidgetView(entry: entry)
                .containerBackground(for: .widget) {
                    LockTodoLockScreenWidgetBackground(style: WidgetDataStore.lockScreenBackgroundStyle)
                }
                .tint(.white)
        }
        .configurationDisplayName("LockTodo")
        .description("오늘 남은 할 일과 진행률을 잠금화면에서 확인합니다.")
        .supportedFamilies([.accessoryInline, .accessoryCircular, .accessoryRectangular])
    }
}

struct LockTodoLockScreenWidgetView: View {
    @Environment(\.widgetFamily) private var family
    @Environment(\.widgetRenderingMode) private var renderingMode
    var entry: LockTodoWidgetEntry

    var body: some View {
        switch family {
        case .accessoryInline:
            inlineView
        case .accessoryCircular:
            circularView
        case .accessoryRectangular:
            rectangularView
        default:
            rectangularView
        }
    }

    private var inlineView: some View {
        Label {
            Text(entry.summary.remainingCombinedCount == 0 ? "완료" : "\(entry.summary.remainingCombinedCount)개 남음")
                .monospacedDigit()
        } icon: {
            Image(systemName: "checkmark.circle.fill")
        }
        .widgetAccentable()
    }

    @ViewBuilder
    private var circularView: some View {
        if let firstTask = entry.summary.pageTasks(pageSize: 1).first {
            Button(intent: ToggleTaskCompletionIntent(taskID: firstTask.id, isCompleted: !firstTask.isCompleted, taskTitle: firstTask.title)) {
                circularGauge
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
        } else {
            circularGauge
        }
    }

    private var circularGauge: some View {
        Gauge(value: entry.summary.progress) {
            Text("진행률")
        } currentValueLabel: {
            Text("\(Int(entry.summary.progress * 100))%")
                .font(.system(size: 9, weight: .bold, design: .rounded))
                .minimumScaleFactor(0.7)
        }
        .gaugeStyle(.accessoryCircularCapacity)
        .widgetAccentable()
        .accessibilityLabel("LockTodo 진행률")
        .accessibilityValue(Text("\(Int(entry.summary.progress * 100))%"))
    }

    private enum CombinedWidgetLineItem: Identifiable {
        case task(SharedTaskSnapshot)
        case habit(SharedHabitSnapshot)
        
        var id: UUID {
            switch self {
            case .task(let t): return t.id
            case .habit(let h): return h.id
            }
        }
    }

    private var rectangularView: some View {
        let pageSize = WidgetDataStore.widgetTaskPageSize
        let pageCombined = entry.summary.pageCombinedItems(pageSize: pageSize)
        let pageCount = entry.summary.pageCount(pageSize: pageSize)
        let pageIndex = entry.summary.clampedPageIndex(pageSize: pageSize)
        let pageRangeText = entry.summary.pageRangeText(pageSize: pageSize)

        let totalItemsCount = entry.summary.totalCombinedItems.count
        let totalCompletedCount = entry.summary.totalCombinedItems.filter(\.isCompleted).count
        let combinedProgress: Double = totalItemsCount > 0 ? Double(totalCompletedCount) / Double(totalItemsCount) : 1.0
        
        return AnyView(VStack(alignment: .leading, spacing: 3) {
            LockScreenWidgetHeader(
                summary: entry.summary,
                pageCount: pageCount,
                pageIndex: pageIndex,
                pageRangeText: pageRangeText
            )

            if pageCombined.isEmpty {
                Link(destination: ShortcutService.addTaskURL) {
                    HStack(spacing: 5) {
                        Image(systemName: "plus.circle")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .widgetAccentable()
                        Text("할 일 & 루틴 추가")
                            .font(.system(size: 10, weight: .semibold, design: .rounded))
                            .lineLimit(1)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                }
            } else {
                let leftItems = pageCombined.enumerated().filter { $0.offset < 2 }.map { $0.element }
                let rightItems = pageCombined.enumerated().filter { $0.offset >= 2 && $0.offset < 4 }.map { $0.element }
                
                HStack(alignment: .top, spacing: 8) {
                    VStack(alignment: .leading, spacing: 3) {
                        ForEach(leftItems, id: \.id) { item in
                            widgetLine(for: item)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    
                    VStack(alignment: .leading, spacing: 3) {
                        ForEach(rightItems, id: \.id) { item in
                            widgetLine(for: item)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxWidth: .infinity)
            }

            Spacer(minLength: 0)

            HStack(spacing: 6) {
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.primary.opacity(0.18))
                        .frame(height: 2.5)

                    GeometryReader { geometry in
                        Capsule()
                            .fill(Color.primary)
                            .frame(width: max(0, geometry.size.width * min(max(combinedProgress, 0), 1)))
                            .frame(height: 2.5)
                            .widgetAccentable()
                    }
                    .frame(height: 2.5)
                }

                Text("\(totalCompletedCount)/\(max(totalItemsCount, 0))")
                    .font(.system(size: 9.5, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .widgetAccentable()
            }
            .frame(height: 10)
        }
        .padding(.vertical, 1)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading))
    }

    @ViewBuilder
    private func widgetLine(for item: SharedCombinedItem) -> some View {
        let itemColor = Color(hex: item.colorHex)
        if !item.isHabit {
            Button(intent: ToggleTaskCompletionIntent(taskID: item.id, isCompleted: !item.isCompleted, taskTitle: item.title)) {
                HStack(spacing: 4) {
                    if item.isCompleted {
                        ZStack {
                            Circle()
                                .fill(renderingMode == .fullColor ? itemColor : Color.primary)
                                .frame(width: 6.5, height: 6.5)
                            Image(systemName: "checkmark")
                                .font(.system(size: 4.5, weight: .bold))
                                .foregroundStyle(renderingMode == .fullColor ? .black : Color.black)
                        }
                        .widgetAccentable(renderingMode != .fullColor)
                    } else {
                        Circle()
                            .stroke(renderingMode == .fullColor ? itemColor : Color.primary, lineWidth: 1.2)
                            .frame(width: 6.5, height: 6.5)
                            .widgetAccentable(renderingMode != .fullColor)
                    }
                    
                    Text(item.title)
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .lineLimit(1)
                        .strikethrough(item.isCompleted)
                        .foregroundStyle(item.isCompleted ? Color.primary.opacity(0.48) : (renderingMode == .fullColor ? itemColor : Color.primary))
                        .minimumScaleFactor(0.85)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        } else {
            let habitIcon = item.habitIcon ?? "🌿"
            Button(intent: ToggleHabitCompletionIntent(habitID: item.id, isCompleted: !item.isCompleted)) {
                HStack(spacing: 4) {
                    if item.isCompleted {
                        ZStack {
                            Circle()
                                .fill(itemColor.opacity(0.64))
                                .frame(width: 5, height: 5)
                            Image(systemName: "checkmark")
                                .font(.system(size: 3.5, weight: .bold))
                                .foregroundStyle(.black)
                        }
                        .widgetAccentable()
                    } else {
                        Circle()
                            .stroke(itemColor.opacity(0.72), lineWidth: 0.9)
                            .frame(width: 5, height: 5)
                            .widgetAccentable()
                    }
                    
                    Text("\(habitIcon) \(item.title)")
                        .font(.system(size: 8, weight: .medium, design: .rounded))
                        .lineLimit(1)
                        .strikethrough(item.isCompleted)
                        .foregroundStyle(item.isCompleted ? Color.primary.opacity(0.38) : Color.primary.opacity(0.72))
                        .minimumScaleFactor(0.85)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

}

private struct LockScreenWidgetHeader: View {
    var summary: TaskSummarySnapshot
    var pageCount: Int
    var pageIndex: Int
    var pageRangeText: String

    var body: some View {
        HStack(alignment: .center, spacing: 5) {
            HStack(spacing: 4) {
                Image(systemName: "checklist")
                    .font(.system(size: 10, weight: .bold))
                    .widgetAccentable()

                Text(summary.remainingCombinedCount == 0 ? "모두 완료" : "\(summary.remainingCombinedCount)개 남음")
                    .font(.system(size: 11.5, weight: .heavy, design: .rounded))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
                    .widgetAccentable()
            }

            Spacer(minLength: 3)

            if pageCount > 1 {
                LockScreenWidgetPager(
                    pageText: pageRangeText,
                    pageIndex: pageIndex,
                    pageCount: pageCount
                )
            } else {
                Link(destination: summary.remainingCombinedCount == 0 ? ShortcutService.todayURL : ShortcutService.addTaskURL) {
                    Image(systemName: summary.remainingCombinedCount == 0 ? "checkmark.circle.fill" : "plus.circle.fill")
                        .font(.system(size: 12, weight: .bold))
                        .frame(width: 20, height: 18)
                        .contentShape(Rectangle())
                        .widgetAccentable()
                }
                .accessibilityLabel(summary.remainingCombinedCount == 0 ? "오늘 목록 열기" : "할 일 추가")
            }
        }
        .frame(height: 18)
        .frame(maxWidth: .infinity, alignment: .center)
    }
}

private struct LockScreenWidgetProgress: View {
    var progress: Double
    var completedCount: Int
    var totalCount: Int

    var body: some View {
        HStack(spacing: 5) {
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.primary.opacity(0.13))
                    Capsule()
                        .fill(Color.primary.opacity(0.72))
                        .frame(width: max(5, geometry.size.width * min(max(progress, 0), 1)))
                        .widgetAccentable()
                }
            }
            .frame(height: 3)

            Text(totalCount == 0 ? "0%" : "\(Int(progress * 100))%")
                .font(.system(size: 8, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: 26, alignment: .trailing)
                .widgetAccentable()
        }
        .frame(height: 5)
        .accessibilityLabel("완료율")
        .accessibilityValue(Text("\(completedCount)개 완료, \(totalCount)개 중"))
    }
}

private struct LockScreenWidgetPager: View {
    var pageText: String
    var pageIndex: Int
    var pageCount: Int

    var body: some View {
        HStack(spacing: 1) {
            Button(intent: ChangeLockScreenTaskPageIntent(showsNextPage: false, pageSize: WidgetDataStore.widgetTaskPageSize)) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 8, weight: .heavy))
                    .frame(width: 16, height: 17)
                    .contentShape(Rectangle())
                    .widgetAccentable()
            }
            .buttonStyle(.plain)
            .accessibilityLabel("이전 목록")

            Text(pageText)
                .font(.system(size: 8.5, weight: .bold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.78)
                .frame(minWidth: 32)
                .widgetAccentable()

            Button(intent: ChangeLockScreenTaskPageIntent(showsNextPage: true, pageSize: WidgetDataStore.widgetTaskPageSize)) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 8, weight: .heavy))
                    .frame(width: 16, height: 17)
                    .contentShape(Rectangle())
                    .widgetAccentable()
            }
            .buttonStyle(.plain)
            .accessibilityLabel("다음 목록")
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, 1)
        .background(Color.primary.opacity(0.08), in: Capsule())
        .accessibilityLabel("잠금화면 목록 페이지")
        .accessibilityValue(Text("\(pageIndex + 1) / \(pageCount)"))
    }
}

private struct LockScreenWidgetEmptyState: View {
    var isComplete: Bool

    var body: some View {
        Link(destination: ShortcutService.addTaskURL) {
            HStack(spacing: 5) {
                Image(systemName: isComplete ? "sparkles" : "plus")
                    .font(.system(size: 8.5, weight: .bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 13)

                Text(isComplete ? "완료됨 ✨" : "+ 추가")
                    .font(.system(size: 9.5, weight: .bold, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.86)

                Spacer(minLength: 0)
            }
            .frame(height: 31)
            .frame(maxWidth: .infinity, alignment: .center)
            .contentShape(Rectangle())
        }
        .foregroundStyle(.secondary)
        .accessibilityLabel("할 일 추가")
    }
}

private struct LockTodoLockScreenWidgetBackground: View {
    var style: LockTodoLockScreenBackgroundStyle

    var body: some View {
        LinearGradient(
            colors: [
                style.widgetHighlight,
                style.widgetFill,
                style.widgetShadow
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

private struct LockScreenWidgetTaskLine: View {
    var task: SharedTaskSnapshot
    var isPrimary: Bool

    var body: some View {
        Button(intent: ToggleTaskCompletionIntent(taskID: task.id, isCompleted: !task.isCompleted, taskTitle: task.title)) {
            HStack(spacing: 5) {
                ZStack {
                    if task.isCompleted {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(Color.primary.opacity(0.68))
                    } else {
                        Circle()
                            .stroke(Color.primary.opacity(0.72), lineWidth: 1.1)
                            .frame(width: 11, height: 11)
                    }
                }
                .frame(width: 13, height: 13)
                .widgetAccentable()

                if let boardName = task.boardName {
                    Text(boardName)
                        .font(.system(size: 7, weight: .bold, design: .rounded))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: 30)
                        .widgetAccentable()
                }

                Text(task.title)
                    .font(.system(size: isPrimary ? 10.5 : 10.2, weight: task.isImportant || isPrimary ? .bold : .semibold, design: .rounded))
                    .lineLimit(1)
                    .strikethrough(task.isCompleted)
                    .foregroundStyle(task.isCompleted ? Color.primary.opacity(0.42) : Color.primary)
                    .minimumScaleFactor(0.72)
                    .layoutPriority(1)

                if task.isImportant {
                    Image(systemName: "star.fill")
                        .font(.system(size: 6, weight: .bold))
                        .foregroundStyle(.secondary)
                        .widgetAccentable()
                }

                if let dueText = task.widgetDueText {
                    Text(dueText)
                        .font(.system(size: 7.5, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 2)
            .frame(height: 16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                if isPrimary && !task.isCompleted {
                    Capsule()
                        .fill(Color.primary.opacity(0.055))
                        .widgetAccentable()
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
        .accessibilityLabel(Text(task.isCompleted ? "\(task.title) 미완료로 변경" : "\(task.title) 완료"))
    }
}

private extension LockTodoLockScreenBackgroundStyle {
    var widgetHighlight: Color {
        switch self {
        case .transparent:
            return .white.opacity(0.08)
        case .whiteGlass:
            return .white.opacity(0.20)
        case .softGray:
            return Color(white: 0.78).opacity(0.16)
        case .skyGlass:
            return Color(red: 0.72, green: 0.88, blue: 1.0).opacity(0.16)
        case .lavenderGlass:
            return Color(red: 0.82, green: 0.78, blue: 1.0).opacity(0.16)
        }
    }

    var widgetFill: Color {
        switch self {
        case .transparent:
            return .white.opacity(0.025)
        case .whiteGlass:
            return .white.opacity(0.12)
        case .softGray:
            return Color(white: 0.68).opacity(0.12)
        case .skyGlass:
            return Color(red: 0.64, green: 0.82, blue: 1.0).opacity(0.12)
        case .lavenderGlass:
            return Color(red: 0.74, green: 0.68, blue: 1.0).opacity(0.12)
        }
    }

    var widgetShadow: Color {
        switch self {
        case .transparent:
            return .white.opacity(0.005)
        case .whiteGlass:
            return .white.opacity(0.04)
        case .softGray:
            return Color(white: 0.58).opacity(0.06)
        case .skyGlass:
            return Color(red: 0.52, green: 0.72, blue: 1.0).opacity(0.06)
        case .lavenderGlass:
            return Color(red: 0.58, green: 0.50, blue: 1.0).opacity(0.06)
        }
    }
}

private extension SharedTaskSnapshot {
    var widgetDueText: String? {
        guard let dueTime else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: dueTime)
    }
}

#Preview(as: .accessoryRectangular) {
    LockTodoLockScreenWidget()
} timeline: {
    LockTodoWidgetEntry(date: .now, summary: .sample)
}

struct LockTodoMascotWidget: Widget {
    let kind = "LockTodoMascotWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: LockTodoWidgetProvider()) { entry in
            LockTodoProgressWidgetView(entry: entry)
                .containerBackground(for: .widget) { Color(.systemBackground) }
        }
        .configurationDisplayName("오늘 진행률")
        .description("오늘 완료율과 남은 할 일을 홈 화면에서 한눈에 확인하세요.")
        .supportedFamilies([.systemSmall])
    }
}

/// A calm, Apple-style small widget: today's date, a completion ring, and the
/// remaining count. No character — just the information, legible in light and
/// dark, tinted with the app accent.
struct LockTodoProgressWidgetView: View {
    var entry: LockTodoWidgetEntry

    private var dateText: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.dateFormat = "M월 d일 EEEE"
        return formatter.string(from: entry.date)
    }

    var body: some View {
        let summary = entry.summary
        let progress = summary.progress
        let remaining = summary.remainingCount
        let done = summary.totalCount > 0 && remaining == 0

        VStack(alignment: .leading, spacing: 0) {
            Text("오늘")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(.primary)
            Text(dateText)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            Spacer(minLength: 6)

            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(done ? "완료" : "\(remaining)")
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .foregroundStyle(done ? Color.accentColor : .primary)
                        .contentTransition(.numericText(value: Double(remaining)))
                    Text(done ? "모두 끝냈어요" : (summary.totalCount == 0 ? "할 일 없음" : "개 남음"))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }

                Spacer()

                ZStack {
                    Circle()
                        .stroke(Color.primary.opacity(0.08), lineWidth: 6)
                    Circle()
                        .trim(from: 0, to: max(0.001, CGFloat(progress)))
                        .stroke(
                            Color.accentColor,
                            style: StrokeStyle(lineWidth: 6, lineCap: .round)
                        )
                        .rotationEffect(.degrees(-90))
                    Text("\(Int(progress * 100))%")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)
                        .minimumScaleFactor(0.7)
                }
                .frame(width: 52, height: 52)
            }
        }
        .padding(14)
    }
}
