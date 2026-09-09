import AppIntents
import SwiftUI
import WidgetKit

@available(iOSApplicationExtension 18.0, *)
struct LockTodoQuickAddControlWidget: ControlWidget {
    let kind = "LockTodoQuickAddControlWidgetV2"

    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: kind) {
            ControlWidgetButton(action: LockTodoOpenDestinationIntent(target: .quickAdd)) {
                Label("빠른 입력", systemImage: "plus")
            }
            .tint(.accentColor)
        }
        .displayName("LockTodo 빠른 입력")
        .description("잠금화면 하단 버튼에서 LockTodo 입력 화면을 바로 엽니다.")
    }
}

@available(iOSApplicationExtension 18.0, *)
struct LockTodoTodayControlWidget: ControlWidget {
    let kind = "LockTodoTodayControlWidgetV2"

    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: kind) {
            ControlWidgetButton(action: LockTodoOpenDestinationIntent(target: .today)) {
                Label("오늘 보기", systemImage: "checklist")
            }
            .tint(.accentColor)
        }
        .displayName("LockTodo 오늘 보기")
        .description("잠금화면 하단 버튼에서 오늘 목록을 바로 엽니다.")
    }
}

@available(iOSApplicationExtension 18.0, *)
struct LockTodoFocusControlWidget: ControlWidget {
    let kind = "LockTodoFocusControlWidgetV2"

    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: kind) {
            ControlWidgetButton(action: LockTodoOpenDestinationIntent(target: .focus)) {
                Label("집중 시작", systemImage: "scope")
            }
            .tint(.accentColor)
        }
        .displayName("LockTodo 집중 시작")
        .description("잠금화면 하단 버튼에서 오늘 집중 화면을 바로 엽니다.")
    }
}
