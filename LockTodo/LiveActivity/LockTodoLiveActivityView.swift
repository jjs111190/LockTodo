import ActivityKit
import AppIntents
import WidgetKit
import SwiftUI

struct LockTodoLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: LockTodoActivityAttributes.self) { context in
            LockTodoLiveActivityView(state: context.state)
                .activityBackgroundTint(WidgetDataStore.lockScreenBackgroundStyle.activityTint)
                .activitySystemActionForegroundColor(.white)
                .widgetURL(context.state.liveActivityOpenURL)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    if let route = context.state.activeMapRoute {
                        HStack(spacing: 8) {
                            Image(systemName: "location.fill")
                                .font(.system(size: 18, weight: .bold))
                            VStack(alignment: .leading, spacing: 1) {
                                Text("지도 루트")
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundStyle(.secondary)
                                Text(route.lockScreenTitle)
                                    .font(.system(size: 13, weight: .bold))
                                    .lineLimit(1)
                            }
                        }
                    } else {
                        HStack(spacing: 8) {
                            Image(systemName: "checklist")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(.white.opacity(0.85))
                                .frame(width: 28, height: 28)
                                .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                            VStack(alignment: .leading, spacing: 1) {
                                Text("오늘 체크리스트")
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundStyle(.secondary)
                                Text(context.state.headline)
                                    .font(.system(size: 13, weight: .bold))
                                    .lineLimit(1)
                            }
                        }
                    }
                }

                DynamicIslandExpandedRegion(.trailing) {
                    if let route = context.state.activeMapRoute {
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(route.distanceText ?? "이동")
                                .font(.caption.weight(.semibold))
                                .monospacedDigit()
                            Text("\(route.stopRank)/\(route.stopCount)")
                                .font(.caption2.weight(.medium))
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        VStack(alignment: .trailing, spacing: 4) {
                            Text(context.state.progress, format: .percent.precision(.fractionLength(0)))
                                .font(.caption.weight(.semibold))
                                .monospacedDigit()
                            LockTodoActivityProgressBar(progress: context.state.progress)
                                .frame(width: 54, height: 5)
                        }
                    }
                }

                DynamicIslandExpandedRegion(.bottom) {
                    if let route = context.state.activeMapRoute {
                        LockTodoIslandRouteView(route: route)
                    } else {
                        LockTodoIslandTaskList(tasks: context.state.displayTasks)
                    }
                }
            } compactLeading: {
                if context.state.activeMapRoute != nil {
                    Image(systemName: "location.fill")
                        .font(.caption2.weight(.bold))
                } else {
                    Image(systemName: "checklist")
                        .font(.caption2.weight(.bold))
                }
            } compactTrailing: {
                Text(context.state.compactText)
                    .font(.caption2.weight(.semibold))
                    .monospacedDigit()
            } minimal: {
                if context.state.activeMapRoute != nil {
                    Image(systemName: "location.fill")
                        .font(.caption2.weight(.bold))
                } else {
                    Text("\(context.state.remainingCount)")
                        .font(.caption2.weight(.bold))
                        .monospacedDigit()
                }
            }
            .keylineTint(.white.opacity(0.45))
            .widgetURL(context.state.liveActivityOpenURL)
        }
    }
}

struct LockTodoLiveActivityView: View {
    var state: LockTodoActivityAttributes.ContentState

    var body: some View {
        let backgroundStyle = WidgetDataStore.lockScreenBackgroundStyle

        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 8) {
                Image(systemName: "checklist")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white.opacity(0.85))
                    .frame(width: 20, height: 20)
                    .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 6, style: .continuous))


                VStack(alignment: .leading, spacing: 1) {
                    Text(state.headerLabel)
                        .font(.system(size: 8.5, weight: .bold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.60))
                    
                    Text(state.headline)
                        .font(.system(size: 11.5, weight: .bold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.92))
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    Text(state.progress, format: .percent.precision(.fractionLength(0)))
                        .font(.system(size: 11.5, weight: .black, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.white.opacity(0.88))

                    LockTodoActivityProgressBar(progress: state.progress)
                        .frame(width: 50, height: 3.5)
                }
            }

            if let route = state.activeMapRoute {
                LockTodoActivityRouteCard(route: route)
            } else {
                taskListContent
                
                if state.pageCount > 1 {
                    HStack {
                        Spacer()
                        LiveActivityPager(
                            pageText: state.pageRangeText,
                            pageIndex: state.pageIndex,
                            pageCount: state.pageCount
                        )
                        Spacer()
                    }
                    .padding(.top, 2)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .lockTodoTransparentGlassCard(cornerRadius: 22, style: backgroundStyle)
    }

    private var taskListContent: some View {
        Group {
            if state.displayCombinedItems.isEmpty {
                LockTodoActivityStatusLine(title: "오늘 비어 있음")
            } else {
                let leftItems = state.displayCombinedItems.enumerated().filter { $0.offset < 2 }.map { $0.element }
                let rightItems = state.displayCombinedItems.enumerated().filter { $0.offset >= 2 && $0.offset < 4 }.map { $0.element }
                
                HStack(alignment: .top, spacing: 8) {
                    VStack(spacing: 6) {
                        ForEach(leftItems, id: \.id) { item in
                            LockTodoActivityCombinedLine(item: item)
                                .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                                .overlay {
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .stroke(.white.opacity(0.08), lineWidth: 0.8)
                                }
                        }
                    }
                    .frame(maxWidth: .infinity)
                    
                    VStack(spacing: 6) {
                        ForEach(rightItems, id: \.id) { item in
                            LockTodoActivityCombinedLine(item: item)
                                .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                                .overlay {
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .stroke(.white.opacity(0.08), lineWidth: 0.8)
                                }
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
    }
}

private struct LockTodoActivityCombinedLine: View {
    var item: SharedCombinedItem

    var body: some View {
        let itemColor = Color(hex: item.colorHex)
        Button(intent: ToggleTaskCompletionIntent(taskID: item.id, isCompleted: !item.isCompleted, taskTitle: item.title)) {
            HStack(spacing: 8) {
                Image(systemName: item.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(itemColor)
                
                if item.isHabit, let icon = item.habitIcon {
                    Text(icon)
                        .font(.system(size: 10))
                }
                
                Text(item.title)
                    .font(.system(size: 10.5, weight: .bold, design: .rounded))
                    .strikethrough(item.isCompleted, color: .white.opacity(0.4))
                    .foregroundStyle(item.isCompleted ? .white.opacity(0.5) : .white)
                    .lineLimit(1)
                
                Spacer()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
    }
}

private struct LiveActivityPager: View {
    var pageText: String
    var pageIndex: Int
    var pageCount: Int

    var body: some View {
        HStack(spacing: 3) {
            Button(intent: ChangeLockScreenTaskPageIntent(showsNextPage: false, pageSize: WidgetDataStore.liveActivityTaskPageSize)) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 7, weight: .heavy))
                    .frame(width: 16, height: 16)
                    .foregroundStyle(.white.opacity(0.85))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Text(pageText)
                .font(.system(size: 8, weight: .bold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.78)
                .frame(minWidth: 32)
                .foregroundStyle(.white.opacity(0.85))

            Button(intent: ChangeLockScreenTaskPageIntent(showsNextPage: true, pageSize: WidgetDataStore.liveActivityTaskPageSize)) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 7, weight: .heavy))
                    .frame(width: 16, height: 16)
                    .foregroundStyle(.white.opacity(0.85))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 2)
        .background(Color.white.opacity(0.08), in: Capsule())
    }
}

private struct LockTodoActivityHeader: View {
    var state: LockTodoActivityAttributes.ContentState

    var body: some View {
        HStack(alignment: .center, spacing: 11) {
            LockTodoActivityMark(
                symbolName: state.headerSymbolName,
                isDone: state.isCompleteState
            )

            VStack(alignment: .leading, spacing: 2) {
                Text(state.headerLabel)
                    .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.70))

                Text(state.headline)
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
                    .foregroundStyle(.white.opacity(0.96))

                Text(state.lockScreenDetailLine)
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.84)
                    .foregroundStyle(.white.opacity(0.62))
            }

            Spacer(minLength: 8)

            if let route = state.activeMapRoute {
                VStack(alignment: .trailing, spacing: 4) {
                    Text(route.distanceText ?? "이동")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.white.opacity(0.82))

                    Text("\(route.stopRank)/\(route.stopCount) 위치")
                        .font(.system(size: 9, weight: .bold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.66))
                }
            } else {
                VStack(alignment: .trailing, spacing: 5) {
                    Text(state.progress, format: .percent.precision(.fractionLength(0)))
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.white.opacity(0.82))

                    LockTodoActivityProgressBar(progress: state.progress)
                        .frame(width: 76, height: 6)

                    if state.pageCount > 1 {
                        LockTodoActivityPager(state: state)
                    }
                }
            }
        }
    }
}

private struct LockTodoActivityPager: View {
    var state: LockTodoActivityAttributes.ContentState

    var body: some View {
        HStack(spacing: 5) {
            Button(intent: ChangeLockScreenTaskPageIntent(showsNextPage: false, pageSize: WidgetDataStore.liveActivityTaskPageSize)) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 8, weight: .bold))
                    .frame(width: 24, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("이전 목록")

            Text("\(state.pageIndex + 1)/\(state.pageCount)")
                .font(.system(size: 9, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.white.opacity(0.72))

            Button(intent: ChangeLockScreenTaskPageIntent(showsNextPage: true, pageSize: WidgetDataStore.liveActivityTaskPageSize)) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 8, weight: .bold))
                    .frame(width: 24, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("다음 목록")
        }
        .foregroundStyle(.white.opacity(0.78))
        .padding(.horizontal, 5)
        .padding(.vertical, 3)
        .lockTodoGlassPill(cornerRadius: 10, fillOpacity: 0.10)
        .accessibilityLabel("잠금화면 목록 페이지")
        .accessibilityValue(Text("\(state.pageIndex + 1) / \(state.pageCount)"))
    }
}

private struct LockTodoActivityMark: View {
    var symbolName: String = "checklist"
    var isDone: Bool

    var body: some View {
        ZStack {
            Circle()
                .fill(.white.opacity(0.16))
                .frame(width: 38, height: 38)
                .overlay {
                    Circle()
                        .stroke(.white.opacity(0.34), lineWidth: 0.8)
                }

            Image(systemName: isDone ? "checkmark" : symbolName)
                .font(.system(size: 15.5, weight: .bold, design: .rounded))
                .foregroundStyle(.white.opacity(0.94))
        }
        .accessibilityHidden(true)
    }
}

private struct LockTodoActivityFocusPill: View {
    var title: String

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: "scope")
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(.white.opacity(0.84))

            Text(title)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.82)
                .foregroundStyle(.white.opacity(0.84))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .lockTodoGlassPill(cornerRadius: 15, fillOpacity: 0.12)
    }
}

private struct LockTodoActivityRouteCard: View {
    var route: MapTodoRouteSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "arrow.triangle.turn.up.right.diamond.fill")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.95))
                    .frame(width: 28, height: 28)
                    .background(.white.opacity(0.16), in: Circle())

                VStack(alignment: .leading, spacing: 2) {
                    Text(route.lockScreenTitle)
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .lineLimit(1)
                        .minimumScaleFactor(0.82)
                        .foregroundStyle(.white.opacity(0.94))

                    Text(route.previewText.isEmpty ? route.summaryText : route.previewText)
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .lineLimit(1)
                        .minimumScaleFactor(0.80)
                        .foregroundStyle(.white.opacity(0.70))
                }

                Spacer(minLength: 8)
            }

            HStack(spacing: 7) {
                routePill(text: route.distanceText ?? "거리 계산 중", systemImage: "figure.walk")
                routePill(text: "\(route.taskCount)개", systemImage: "checklist")
                routePill(text: "앱 안 길찾기", systemImage: "map")
                Spacer(minLength: 2)
                Button(intent: CancelMapRouteIntent()) {
                    Label("취소", systemImage: "xmark.circle")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .lineLimit(1)
                        .foregroundStyle(.white.opacity(0.88))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 4)
                        .background(.white.opacity(0.12), in: Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("지도 루트 취소")
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 15, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .stroke(.white.opacity(0.12), lineWidth: 0.8)
        }
    }

    private func routePill(text: String, systemImage: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: systemImage)
                .font(.system(size: 9, weight: .bold))
            Text(text)
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .lineLimit(1)
        }
        .foregroundStyle(.white.opacity(0.82))
        .padding(.horizontal, 7)
        .padding(.vertical, 4)
        .background(.white.opacity(0.10), in: Capsule())
    }
}

private struct LockTodoActivityProgressBar: View {
    var progress: Double

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(.white.opacity(0.18))
                Capsule()
                    .fill(.white.opacity(0.84))
                    .frame(width: max(7, geometry.size.width * min(max(progress, 0), 1)))
            }
        }
        .accessibilityLabel("완료율")
        .accessibilityValue(Text("\(Int(progress * 100))%"))
    }
}

private struct LockTodoActivityTaskLine: View {
    var task: SharedTaskSnapshot
    var isPrimary: Bool

    var body: some View {
        Button(intent: ToggleTaskCompletionIntent(taskID: task.id, isCompleted: !task.isCompleted, taskTitle: task.title)) {
            content
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
        .accessibilityLabel(Text(task.isCompleted ? "\(task.title) 미완료로 변경" : "\(task.title) 완료"))
    }

    private var content: some View {
        let taskColor = Color(hex: task.colorHex)
        return HStack(spacing: 11) {
            ZStack {
                if task.isCompleted {
                    Circle()
                        .fill(taskColor.opacity(0.68))
                        .frame(width: 16, height: 16)
                    Image(systemName: "checkmark")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.white)
                } else {
                    Circle()
                        .stroke(taskColor.opacity(0.88), lineWidth: 1.5)
                        .frame(width: 16, height: 16)
                }
            }
            .frame(width: 18, height: 18)

            Text(task.title)
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .lineLimit(1)
                .strikethrough(task.isCompleted)
                .foregroundStyle(.white.opacity(task.isCompleted ? 0.45 : (isPrimary ? 0.95 : 0.78)))
            
            if task.isImportant {
                Image(systemName: "star.fill")
                    .font(.system(size: 8))
                    .foregroundStyle(.yellow.opacity(0.85))
            }
            
            if let boardName = task.boardName {
                Text(boardName)
                    .font(.system(size: 8, weight: .bold, design: .rounded))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1.5)
                    .foregroundStyle(.white.opacity(0.8))
                    .background(Color(hex: task.boardColorHex ?? "#8E8E93").opacity(0.24), in: RoundedRectangle(cornerRadius: 4))
            }

            Spacer(minLength: 0)

            if let dueText = task.lockScreenDueText {
                Text(dueText)
                    .font(.system(size: 9.5, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white.opacity(task.isCompleted ? 0.35 : 0.68))
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }
}

private struct LockTodoActivityStatusLine: View {
    var title: String

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: "sparkles")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.84))
                .frame(width: 22, height: 22)

            Text(title)
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.78)
                .foregroundStyle(.white.opacity(0.70))

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .lockTodoGlassPill(cornerRadius: 17, fillOpacity: 0.10)
    }
}

private struct LockTodoIslandRouteView: View {
    var route: MapTodoRouteSnapshot

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "map.fill")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.green)

            VStack(alignment: .leading, spacing: 1) {
                Text(route.lockScreenTitle)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                Text(route.summaryText)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, minHeight: 25, alignment: .leading)
    }
}

private struct LockTodoIslandTaskList: View {
    var tasks: [SharedTaskSnapshot]

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if tasks.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 9.5, weight: .bold))
                        .foregroundStyle(.yellow)
                    Text("오늘 할 일을 모두 완료했어요!")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.85))
                }
                .frame(maxWidth: .infinity, minHeight: 24, alignment: .leading)
            } else {
                ForEach(Array(tasks.prefix(2).enumerated()), id: \.element.id) { index, task in
                    Button(intent: ToggleTaskCompletionIntent(taskID: task.id, isCompleted: !task.isCompleted, taskTitle: task.title)) {
                        HStack(spacing: 6) {
                            Image(systemName: task.isCompleted ? "checkmark.circle.fill" : "circle")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(task.isCompleted ? Color.green : Color.white.opacity(0.86))

                            Text(task.title)
                                .font(.caption.weight(index == 0 ? .semibold : .regular))
                                .lineLimit(1)
                                .minimumScaleFactor(0.78)
                                .strikethrough(task.isCompleted)
                        }
                        .frame(maxWidth: .infinity, minHeight: 24, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text(task.isCompleted ? "\(task.title) 미완료로 변경" : "\(task.title) 완료"))
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private extension View {
    @ViewBuilder
    func lockTodoTransparentGlassCard(cornerRadius: CGFloat, style: LockTodoLockScreenBackgroundStyle) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

        self
            .background {
                shape
                    .fill(style.cardFill)
                    .overlay {
                        shape.fill(
                            LinearGradient(
                                colors: [
                                    style.cardHighlight,
                                    style.cardMidtone,
                                    style.cardShadow
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                    }
                    .overlay {
                        shape.stroke(style.cardStroke, lineWidth: 0.8)
                    }
            }
            .compositingGroup()
            .shadow(color: .black.opacity(style.shadowOpacity), radius: 18, x: 0, y: 8)
    }

    func lockTodoGlassPill(cornerRadius: CGFloat, fillOpacity: Double) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

        return self
            .background {
                shape
                    .fill(.white.opacity(fillOpacity))
                    .overlay {
                        shape.stroke(.white.opacity(0.18), lineWidth: 0.7)
                    }
            }
    }
}

private extension LockTodoLockScreenBackgroundStyle {
    var activityTint: Color {
        switch self {
        case .transparent:
            return .white.opacity(0.03)
        case .whiteGlass:
            return .white.opacity(0.13)
        case .softGray:
            return Color(white: 0.82).opacity(0.16)
        case .skyGlass:
            return Color(red: 0.74, green: 0.88, blue: 1.0).opacity(0.13)
        case .lavenderGlass:
            return Color(red: 0.86, green: 0.82, blue: 1.0).opacity(0.13)
        }
    }

    var cardFill: Color {
        switch self {
        case .transparent:
            return .white.opacity(0.045)
        case .whiteGlass:
            return .white.opacity(0.16)
        case .softGray:
            return Color(white: 0.72).opacity(0.16)
        case .skyGlass:
            return Color(red: 0.68, green: 0.84, blue: 1.0).opacity(0.14)
        case .lavenderGlass:
            return Color(red: 0.78, green: 0.72, blue: 1.0).opacity(0.14)
        }
    }

    var cardHighlight: Color {
        switch self {
        case .transparent:
            return .white.opacity(0.12)
        case .whiteGlass:
            return .white.opacity(0.24)
        case .softGray:
            return .white.opacity(0.18)
        case .skyGlass:
            return .white.opacity(0.18)
        case .lavenderGlass:
            return .white.opacity(0.18)
        }
    }

    var cardMidtone: Color {
        switch self {
        case .transparent:
            return .white.opacity(0.035)
        case .whiteGlass:
            return .white.opacity(0.10)
        case .softGray:
            return Color(white: 0.80).opacity(0.08)
        case .skyGlass:
            return Color(red: 0.68, green: 0.84, blue: 1.0).opacity(0.08)
        case .lavenderGlass:
            return Color(red: 0.78, green: 0.72, blue: 1.0).opacity(0.08)
        }
    }

    var cardShadow: Color {
        switch self {
        case .transparent:
            return .white.opacity(0.012)
        case .whiteGlass:
            return .white.opacity(0.04)
        case .softGray:
            return Color(white: 0.62).opacity(0.04)
        case .skyGlass:
            return Color(red: 0.55, green: 0.74, blue: 1.0).opacity(0.05)
        case .lavenderGlass:
            return Color(red: 0.62, green: 0.54, blue: 1.0).opacity(0.05)
        }
    }

    var cardStroke: Color {
        switch self {
        case .transparent:
            return .white.opacity(0.22)
        case .whiteGlass:
            return .white.opacity(0.36)
        case .softGray:
            return .white.opacity(0.28)
        case .skyGlass:
            return .white.opacity(0.30)
        case .lavenderGlass:
            return .white.opacity(0.30)
        }
    }

    var shadowOpacity: Double {
        switch self {
        case .transparent:
            return 0.04
        case .whiteGlass:
            return 0.07
        case .softGray, .skyGlass, .lavenderGlass:
            return 0.08
        }
    }
}

private extension LockTodoActivityAttributes.ContentState {
    var isMapRouteActive: Bool {
        activeMapRoute != nil
    }

    var isEmptyState: Bool {
        totalCount == 0
    }

    var isCompleteState: Bool {
        !isEmptyState && remainingCount == 0
    }

    var headerLabel: String {
        isMapRouteActive ? "지도 루트" : "오늘 체크리스트"
    }

    var headerSymbolName: String {
        isMapRouteActive ? "location.fill" : "checklist"
    }

    var headline: String {
        if let route = activeMapRoute { return route.distanceText ?? "이동 중" }
        if isEmptyState { return "오늘 할 일 없음" }
        if isCompleteState { return "오늘 완료" }
        return "\(remainingCount)개 남음"
    }

    var subtitle: String {
        if isEmptyState { return "대기 중" }
        if isCompleteState { return "모든 할 일을 완료했습니다" }
        return "\(completedCount)/\(totalCount) 완료"
    }

    var symbolName: String {
        isCompleteState ? "checkmark.circle.fill" : "checklist"
    }

    var compactText: String {
        if let route = activeMapRoute { return route.distanceText ?? "지도" }
        return isCompleteState ? "완료" : "\(remainingCount)개"
    }

    var displayTitles: [String] {
        if isEmptyState { return ["오늘 비어 있음"] }
        if isCompleteState { return ["모든 항목 완료"] }
        return importantTitles.isEmpty ? ["중요 항목 없음"] : importantTitles
    }

    var displayTasks: [SharedTaskSnapshot] {
        taskSnapshots
    }

    var lockScreenDetailLine: String {
        if let route = activeMapRoute {
            return "\(route.lockScreenTitle) · \(route.taskCount)개 할 일"
        }
        if isEmptyState { return "새 할 일을 추가하면 여기에 표시됩니다" }
        if isCompleteState { return "\(completedCount)/\(totalCount) 완료" }
        return "\(completedCount)/\(totalCount) 완료 · \(pageRangeText)"
    }

    var liveActivityOpenURL: URL {
        if activeMapRoute != nil {
            return URL(string: "locktodo://map")!
        }
        return URL(string: "locktodo://today")!
    }
}

private extension SharedTaskSnapshot {
    var lockScreenDueText: String? {
        guard let dueTime else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: dueTime)
    }
}

private struct LockTodoActivityHabitLine: View {
    var habit: SharedHabitSnapshot

    var body: some View {
        Button(intent: ToggleHabitCompletionIntent(habitID: habit.id, isCompleted: !habit.isCompleted)) {
            content
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
        .accessibilityLabel(Text(habit.isCompleted ? "\(habit.title) 미완료로 변경" : "\(habit.title) 완료"))
    }

    private var content: some View {
        let habitColor = Color(hex: habit.colorHex)
        return HStack(spacing: 11) {
            ZStack {
                if habit.isCompleted {
                    Circle()
                        .fill(habitColor.opacity(0.68))
                        .frame(width: 16, height: 16)
                    Image(systemName: "checkmark")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.white)
                } else {
                    Circle()
                        .stroke(habitColor.opacity(0.88), lineWidth: 1.5)
                        .frame(width: 16, height: 16)
                }
            }
            .frame(width: 18, height: 18)

            if !habit.icon.isEmpty {
                Text(habit.icon)
                    .font(.system(size: 13))
            }

            Text(habit.title)
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .lineLimit(1)
                .strikethrough(habit.isCompleted)
                .foregroundStyle(.white.opacity(habit.isCompleted ? 0.45 : 0.95))

            Spacer()

            if habit.streak > 0 {
                HStack(spacing: 2) {
                    Text("🔥")
                        .font(.system(size: 10))
                    Text("\(habit.streak)일째")
                        .font(.system(size: 9.5, weight: .bold, design: .rounded))
                        .foregroundStyle(.orange.opacity(0.9))
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(.white.opacity(0.08), in: Capsule())
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }
}

#Preview("Live Activity", as: .content, using: LockTodoActivityAttributes(dayIdentifier: "today")) {
    LockTodoLiveActivityWidget()
} contentStates: {
    LockTodoActivityAttributes.ContentState.sample
}
