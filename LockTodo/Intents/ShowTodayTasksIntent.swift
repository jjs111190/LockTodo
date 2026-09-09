import AppIntents
import SwiftUI
import SwiftData
import WidgetKit

struct ShowTodayTasksIntent: AppIntent {
    static var title: LocalizedStringResource = "LockTodo 오늘 할 일 목록 및 체크"
    static var description = IntentDescription("오늘 할 일 목록을 단축어 팝업으로 직접 확인하고 완료 처리합니다.")
    static var openAppWhenRun = false
    static var authenticationPolicy: IntentAuthenticationPolicy = .alwaysAllowed

    @MainActor
    func perform() async throws -> some IntentResult & ShowsSnippetView {
        let context = ModelContext(WidgetDataStore.sharedModelContainer)
        let tasks = (try? context.fetch(FetchDescriptor<TaskItem>())) ?? []
        WidgetDataStore.saveSummary(from: tasks)
        WidgetCenter.shared.reloadAllTimelines()
        await LiveActivityService.shared.updateCurrentSummary()
        
        return .result(
            view: ShortcutsTaskListView()
        )
    }
}

@MainActor
struct ShortcutsTaskListView: View {
    private let appPurple = Color(red: 0.416, green: 0.392, blue: 0.965)

    var body: some View {
        let summary = WidgetDataStore.loadSummary()
        let todayTasks = summary.allTodayTasks

        VStack(alignment: .leading, spacing: 10) {
            // 1. 헤더 (타이틀, 남은 개수, 진행률 배지)
            HStack(alignment: .center, spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(appPurple)

                Text("오늘 할 일")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.primary)

                Text("\(summary.remainingCount)")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(.secondary)

                Spacer()

                Text("\(Int(summary.progress * 100))%")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(appPurple)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(appPurple.opacity(0.10), in: Capsule())
            }

            // 2. 상태 한 줄
            Text(statusLine(remainingCount: summary.remainingCount, totalCount: summary.totalCount))
                .font(.system(size: 11.5, weight: .medium, design: .rounded))
                .foregroundStyle(Color.secondary)
                .lineLimit(1)
                .multilineTextAlignment(.leading)

            // 3. 초슬림 진행도 게이지바
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.primary.opacity(0.05))
                    Capsule()
                        .fill(appPurple)
                        .frame(width: geo.size.width * CGFloat(summary.progress))
                }
            }
            .frame(height: 2)
            .padding(.bottom, 2)
            
            Divider()
                .opacity(0.10)
            
            // 4. 할 일 리스트 (애플 미리알림 스타일)
            VStack(spacing: 0) {
                if todayTasks.isEmpty {
                    HStack(spacing: 6) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(appPurple.opacity(0.8))
                        Text("새로운 할 일을 추가해 보세요!")
                            .font(.system(size: 11.5, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 20)
                    .frame(maxWidth: .infinity, alignment: .center)
                } else {
                    ForEach(Array(todayTasks.enumerated()), id: \.element.id) { index, task in
                        VStack(spacing: 0) {
                            Button(intent: ToggleTaskCompletionIntent(taskID: task.id, isCompleted: !task.isCompleted, taskTitle: task.title)) {
                                HStack(spacing: 10) {
                                    Image(systemName: task.isCompleted ? "checkmark.circle.fill" : "circle")
                                        .font(.system(size: 16.5))
                                        .foregroundStyle(task.isCompleted ? appPurple : appPurple.opacity(0.4))
                                    
                                    Text(task.title)
                                        .font(.system(size: 13, weight: .medium, design: .rounded))
                                        .strikethrough(task.isCompleted)
                                        .foregroundStyle(task.isCompleted ? Color.primary.opacity(0.4) : Color.primary)
                                        .lineLimit(1)
                                    
                                    if task.isImportant {
                                        Image(systemName: "star.fill")
                                            .font(.system(size: 8))
                                            .foregroundStyle(.orange)
                                    }
                                    
                                    Spacer()
                                }
                                .padding(.vertical, 8)
                                .background(Color.white.opacity(0.0001))
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            
                            // 인셋 구분선 적용 (체크박스 크기 + 여백 고려하여 leading 26 패딩 적용)
                            if index < todayTasks.count - 1 {
                                Divider()
                                    .padding(.leading, 26)
                                    .opacity(0.10)
                            }
                        }
                    }
                }
                
                Divider()
                    .opacity(0.10)
                
                // 5. 할 일 추가 액션 (인라인 버튼)
                Button(intent: AddTaskIntent()) {
                    HStack(spacing: 8) {
                        Image(systemName: "plus")
                            .font(.system(size: 12, weight: .bold))
                        Text("새로운 할 일")
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                        Spacer()
                    }
                    .foregroundStyle(appPurple)
                    .padding(.vertical, 8)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
        .background(Color.clear)
    }

    private func statusLine(remainingCount: Int, totalCount: Int) -> String {
        if totalCount == 0 { return "오늘 추가된 할 일이 없어요" }
        if remainingCount == 0 { return "오늘 할 일을 모두 끝냈어요" }
        return "\(remainingCount)개 남았어요"
    }
}
