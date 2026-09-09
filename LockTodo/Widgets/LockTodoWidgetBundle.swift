import WidgetKit
import SwiftUI

@main
struct LockTodoWidgetBundle: WidgetBundle {
    var body: some Widget {
        LockTodoLockScreenWidget()
        LockTodoLiveActivityWidget()
        LockTodoMascotWidget()

        if #available(iOSApplicationExtension 18.0, *) {
            LockTodoQuickAddControlWidget()
            LockTodoTodayControlWidget()
            LockTodoFocusControlWidget()
        }
    }
}
