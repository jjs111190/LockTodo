import SwiftUI
import SwiftData
import UIKit
import WidgetKit
import AppIntents

struct SettingsView: View {
    @Environment(\.openURL) private var openURL
    @EnvironmentObject private var router: AppRouter
    @Query(sort: \TaskItem.sortOrder, order: .forward) private var allTasks: [TaskItem]
    @ObservedObject var taskViewModel: TaskViewModel
    @StateObject private var notificationService = NotificationService.shared
    @StateObject private var liveActivityService = LiveActivityService.shared
    @StateObject private var proAccess = ProAccessService.shared
    @State private var autoLiveActivity = WidgetDataStore.isAutoLiveActivityEnabled
    @State private var lockScreenBackgroundStyle = WidgetDataStore.lockScreenBackgroundStyle
    @State private var lastLockScreenAction = WidgetDataStore.lastLockScreenActionDescription
    @State private var lockScreenTestStatus = "대기 중"
    @State private var copiedShortcutExample = false
    @State private var androidExportStatus = "대기 중"
    @State private var androidExportFile: LockTodoShareFile?
    @State private var showingProUpgrade = false
    @AppStorage("locktodo.appearanceStyle") private var appearanceStyle = "system"

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button {
                        showingProUpgrade = true
                    } label: {
                        HStack(spacing: 14) {
                            Image(systemName: proAccess.isPro ? "checkmark.seal.fill" : "sparkles")
                                .font(.system(size: 19, weight: .semibold))
                                .foregroundStyle(proAccess.isPro ? Color.green : Color.accentColor)
                                .frame(width: 40, height: 40)
                                .background(
                                    (proAccess.isPro ? Color.green : Color.accentColor).opacity(0.12),
                                    in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                                )

                            VStack(alignment: .leading, spacing: 2) {
                                Text(proAccess.isPro ? "LockTodo Pro 활성화됨" : "LockTodo Pro")
                                    .font(.headline)
                                    .foregroundStyle(.primary)
                                Text(proAccess.isPro ? "모든 Pro 기능을 이용할 수 있습니다." : "구독 없이 고급 기능을 영구 잠금 해제")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.tertiary)
                        }
                        .padding(.vertical, 4)
                    }
                    .buttonStyle(.plain)
                }

                Section("도움말") {
                    NavigationLink {
                        TutorialView()
                    } label: {
                        Label("사용 튜토리얼", systemImage: "questionmark.circle")
                    }
                }

                Section("빠른 실행") {
                    NavigationLink {
                        ShortcutGuideView()
                    } label: {
                        Label("Action Button, 뒷면 탭, Siri 설정", systemImage: "button.programmable")
                    }

                    NavigationLink {
                        WidgetPreviewView()
                    } label: {
                        Label("잠금화면 위젯 미리보기", systemImage: "rectangle.on.rectangle")
                    }
                }

                Section("단축어 자동화 및 뒷면 탭") {
                    ShortcutAutomationDashboard()
                        .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16))
                        .listRowBackground(Color.clear)

                    if #available(iOS 17.0, *) {
                        SiriTipView(intent: AddTaskIntent())
                            .padding(.vertical, 4)
                    }

                    Button {
                        if let url = URL(string: "shortcuts://create-shortcut?name=LockTodo%20%ED%95%A0%20%EC%9D%BC%20%EC%B6%94%EA%B0%80") {
                            openURL(url)
                        }
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Label("1단계: 'LockTodo 할 일 추가' 단축어 만들기", systemImage: "sparkles")
                                .font(.body.bold())
                                .foregroundStyle(.blue)
                            Text("탭하면 단축어 생성 창이 즉시 실행됩니다. 동작 추가에서 'LockTodo 할 일 추가'를 넣어 저장해 주세요.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 4)
                    }

                    Button {
                        if let url = URL(string: "App-Prefs:root=ACCESSIBILITY&path=TOUCH_REACHABILITY") {
                            openURL(url)
                        }
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Label("2단계: 아이폰 뒷면 탭 설정 바로가기", systemImage: "hand.tap.fill")
                                .font(.body.bold())
                            Text("터치 메뉴 최하단의 '뒷면 탭' -> '이중 탭'에서 방금 추가한 단축어를 지정해 주세요.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 4)
                    }

                    Button {
                        if let url = URL(string: "shortcuts://") {
                            openURL(url)
                        }
                    } label: {
                        Label("단축어 앱에서 LockTodo 액션 찾기", systemImage: "app.badge")
                    }

                    Button {
                        UIPasteboard.general.string = "내일 오후 3시 병원 예약 ! #건강 색상:파랑"
                        copiedShortcutExample = true
                    } label: {
                        Label(copiedShortcutExample ? "스마트 입력 예시 복사됨" : "스마트 입력 예시 복사", systemImage: copiedShortcutExample ? "checkmark.circle" : "doc.on.doc")
                    }

                    Button {
                        openURL(ShortcutService.mapURL)
                    } label: {
                        Label("지도 할 일 화면 열기 테스트", systemImage: "map")
                    }

                    Text("단축어 앱에서 자동화 > 개인용 자동화 만들기 > 앱 또는 시간/위치 조건을 선택한 뒤 LockTodo 스마트 입력, 스마트 플랜, 잠금화면 순찰 액션을 연결하면 됩니다. 모든 동작은 로컬 저장소와 Apple 기본 단축어 시스템만 사용합니다.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("잠금화면 + 버튼") {
                    LockScreenControlDashboard(lastAction: lastLockScreenAction)
                        .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16))
                        .listRowBackground(Color.clear)

                    Button {
                        openURL(ShortcutService.addTaskURL)
                        lastLockScreenAction = WidgetDataStore.lastLockScreenActionDescription
                    } label: {
                        Label("빠른 입력 흐름 테스트", systemImage: "checklist.checked")
                    }

                    Text("iOS 18 이상에서는 잠금화면 하단 손전등/카메라 위치에 LockTodo 컨트롤을 직접 선택할 수 있습니다. 잠금화면에서는 짧게 탭하지 말고 0.5초 정도 길게 눌러 실행합니다. 기존 컨트롤이 반응하지 않으면 잠금화면 사용자화에서 삭제한 뒤 새로 ‘LockTodo 빠른 입력’을 다시 넣어야 합니다.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("잠금화면 표시") {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("상시 표시: 일반 잠금화면 위젯", systemImage: "rectangle.on.rectangle")
                            .font(.subheadline.weight(.semibold))
                        Text("잠금화면을 길게 눌러 사용자화 > 위젯 추가 > LockTodo의 직사각형 위젯을 선택하세요. 사용자가 제거하기 전까지 계속 표시되고 자정과 할 일 변경에 맞춰 갱신됩니다.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)

                    HStack {
                        Label("실시간 현황", systemImage: liveActivityService.isRunning ? "waveform.path.ecg" : "waveform.path")
                        Spacer()
                        Text(liveActivityService.isRunning ? "표시 중" : "꺼짐")
                            .foregroundStyle(.secondary)
                    }

                    Toggle(isOn: Binding(
                        get: { autoLiveActivity },
                        set: { isEnabled in
                            autoLiveActivity = isEnabled
                            WidgetDataStore.setAutoLiveActivityEnabled(isEnabled)
                            Task {
                                if isEnabled {
                                    await liveActivityService.startOrUpdate(from: allTasks)
                                    taskViewModel.refreshSharedState(allTasks: allTasks)
                                } else {
                                    await liveActivityService.end()
                                }
                            }
                        }
                    )) {
                        Label("앱 사용 중 자동 시작", systemImage: "arrow.clockwise")
                    }

                    Button {
                        Task {
                            WidgetDataStore.setAutoLiveActivityEnabled(true)
                            autoLiveActivity = true
                            await liveActivityService.startOrUpdate(from: allTasks)
                            taskViewModel.refreshSharedState(allTasks: allTasks)
                            liveActivityService.refreshState()
                        }
                    } label: {
                        Label("실시간 현황 시작", systemImage: "play.circle")
                    }

                    Button(role: .destructive) {
                        Task {
                            WidgetDataStore.setAutoLiveActivityEnabled(false)
                            autoLiveActivity = false
                            await liveActivityService.end()
                        }
                    } label: {
                        Label("실시간 현황 종료", systemImage: "stop.circle")
                    }

                    Text("Live Activity는 위치 도착이나 집중처럼 진행 중인 상태를 보여주는 임시 카드입니다. iOS 정책상 활성 8시간과 종료 후 최대 4시간을 합쳐 최대 12시간 안에 사라질 수 있습니다.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("잠금화면 동작 테스트") {
                    HStack {
                        Label("마지막 동작", systemImage: "waveform.path.ecg")
                        Spacer()
                        Text(lastLockScreenAction)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.trailing)
                    }

                    HStack {
                        Label("테스트", systemImage: "checkmark.seal")
                        Spacer()
                        Text(lockScreenTestStatus)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }

                    Button {
                        runLockScreenInteractionTest()
                    } label: {
                        Label("체크/해제 동작 자체 테스트", systemImage: "checkmark.circle.badge.xmark")
                    }
                }

                Section("잠금화면 투두 배경") {
                    Picker("배경 스타일", selection: $lockScreenBackgroundStyle) {
                        ForEach(LockTodoLockScreenBackgroundStyle.allCases) { style in
                            VStack(alignment: .leading, spacing: 2) {
                                HStack {
                                    Text(style.title)
                                    if style.requiresPro {
                                        Image(systemName: "sparkles")
                                    }
                                }
                                Text(style.description)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .tag(style)
                        }
                    }
                    .pickerStyle(.inline)
                    .onChange(of: lockScreenBackgroundStyle) { _, newValue in
                        if newValue.requiresPro && !proAccess.isPro {
                            lockScreenBackgroundStyle = WidgetDataStore.lockScreenBackgroundStyle
                            showingProUpgrade = true
                            return
                        }
                        WidgetDataStore.setLockScreenBackgroundStyle(newValue)
                        WidgetCenter.shared.reloadAllTimelines()
                        taskViewModel.refreshSharedState(allTasks: allTasks)
                    }

                    Text("이 설정은 잠금화면 Live Activity 카드와 Rectangular 위젯 배경에 같이 적용됩니다. ‘투명’은 검은 카드가 생기지 않도록 매우 얇은 흰색 레이어만 사용합니다.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("잠금화면에 안 보일 때") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("잠금화면 목록은 두 가지입니다.")
                            .font(.subheadline.weight(.semibold))
                        Text("작은 위젯은 잠금화면을 길게 눌러 직접 추가해야 하며 반영구적으로 유지됩니다. 큰 카드 형태의 실시간 현황은 앱에서 시작하는 Live Activity라 iOS 수명 제한이 있습니다.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)

                    VStack(alignment: .leading, spacing: 8) {
                        Text("확인 순서")
                            .font(.subheadline.weight(.semibold))
                        Text("1. 잠금화면 편집에서 LockTodo 직사각형 위젯을 추가합니다.\n2. 위치 이동이나 집중을 시작할 때 ‘실시간 현황 시작’을 누릅니다.\n3. 설정 > LockTodo에서 Live Activities가 꺼져 있으면 켭니다.\n4. 설정 > Face ID 및 암호에서 잠겨 있는 동안 Live Activities 접근을 허용합니다.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)

                    Button {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            openURL(url)
                        }
                    } label: {
                        Label("LockTodo 설정 열기", systemImage: "gearshape")
                    }
                }

                Section("알림") {
                    HStack {
                        Label("권한", systemImage: "bell")
                        Spacer()
                        Text(statusText)
                            .foregroundStyle(.secondary)
                    }

                    Button {
                        Task {
                            _ = await notificationService.requestAuthorization()
                            await notificationService.scheduleEveningReminderIfNeeded()
                        }
                    } label: {
                        Label("알림 권한 요청", systemImage: "bell.badge")
                    }

                    Button {
                        Task {
                            await notificationService.scheduleEveningReminderIfNeeded()
                        }
                    } label: {
                        Label("저녁 미완료 알림 켜기", systemImage: "moon")
                    }
                }

                Section("iOS 제한") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("전원/볼륨 버튼은 앱에서 설정할 수 없습니다.")
                            .font(.subheadline.weight(.semibold))
                        Text("전원 버튼 3번 클릭, 볼륨 아래 버튼, 전원+볼륨 아래 조합은 스크린샷, 긴급 구조 요청, 손쉬운 사용 단축키 같은 iOS 시스템 기능으로 예약되어 있습니다. 앱이 이 버튼 입력을 가로채거나 다른 동작으로 바꾸는 공개 API는 없습니다.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)

                    VStack(alignment: .leading, spacing: 8) {
                        Text("가능한 우회")
                            .font(.subheadline.weight(.semibold))
                        Text("Apple 정책 안에서 가장 가까운 방식은 App Intent입니다. LockTodo 새 할 일 추가는 잠긴 상태에서도 실행 가능한 alwaysAllowed Intent로 구성되어 있어 Siri, 단축어, Action Button, 뒷면 탭에서 시스템 입력 프롬프트나 음성 입력으로 할 일을 받아 저장할 수 있습니다.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)

                    VStack(alignment: .leading, spacing: 8) {
                        Text("잠금화면 입력 제한")
                            .font(.subheadline.weight(.semibold))
                        Text("잠금화면 위젯, Live Activity, 하단 컨트롤 안에는 앱 키보드나 텍스트필드를 표시할 수 없습니다. 이 기능을 열어주는 공개 API나 일반 App Store 앱용 권한은 없습니다. 하단 LockTodo 컨트롤은 앱을 여는 역할만 하고, 앱 없이 저장하려면 Siri/단축어 입력을 사용해야 합니다.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }

                Section("데이터") {
                    Label("모든 할 일은 iPhone 로컬 SwiftData 저장소에 저장됩니다.", systemImage: "iphone")
                    Label("할 일과 위치 데이터는 외부 서버로 전송하지 않습니다.", systemImage: "lock")
                    Label("Pro는 Apple StoreKit의 일회성 인앱 구매로만 처리됩니다.", systemImage: "apple.logo")
                    Label("App Group 스냅샷 구조로 위젯과 향후 iCloud 동기화 확장을 분리했습니다.", systemImage: "square.stack.3d.up")
                }
                .font(.footnote)

                Section("Android 공유") {
                    HStack {
                        Label("내보내기 상태", systemImage: "arrow.up.doc")
                        Spacer()
                        Text(androidExportStatus)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.trailing)
                    }

                    Button {
                        exportTasksForAndroid()
                    } label: {
                        Label("Android용 할 일 파일 만들기", systemImage: "shippingbox.and.arrow.backward")
                    }

                    Text("서버 없이 무료로 Android에서 볼 수 있도록 현재 할 일을 JSON 파일로 내보냅니다. Android LockTodo 앱에서 이 파일을 열면 목록을 가져올 수 있습니다.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("화면 스타일") {
                    Picker("테마", selection: $appearanceStyle) {
                        Text("시스템 설정").tag("system")
                        Text("라이트 모드").tag("light")
                        Text("다크 모드").tag("dark")
                    }
                    .pickerStyle(.segmented)
                }

                Section("정보") {
                    HStack {
                        Label("앱 버전", systemImage: "info.circle")
                        Spacer()
                        Text("v2.1.0")
                            .foregroundStyle(.secondary)
                    }

                    NavigationLink {
                        UpdateHistoryView()
                    } label: {
                        Label("업데이트 내역", systemImage: "clock.arrow.circlepath")
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("설정")
            .navigationBarTitleDisplayMode(.inline)
            .task {
                autoLiveActivity = WidgetDataStore.isAutoLiveActivityEnabled
                lockScreenBackgroundStyle = WidgetDataStore.lockScreenBackgroundStyle
                lastLockScreenAction = WidgetDataStore.lastLockScreenActionDescription
                await notificationService.refreshAuthorizationStatus()
                liveActivityService.refreshState()
            }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
                lastLockScreenAction = WidgetDataStore.lastLockScreenActionDescription
                liveActivityService.refreshState()
            }
            .sheet(item: $androidExportFile) { exportFile in
                LockTodoActivityShareSheet(activityItems: [exportFile.url])
            }
            .sheet(isPresented: $showingProUpgrade) {
                ProUpgradeView()
            }
        }
    }

    private var statusText: String {
        switch notificationService.authorizationStatus {
        case .notDetermined: "미결정"
        case .denied: "거부됨"
        case .authorized: "허용됨"
        case .provisional: "임시 허용"
        case .ephemeral: "임시"
        @unknown default: "알 수 없음"
        }
    }

    private func runLockScreenInteractionTest() {
        guard let task = allTasks.first(where: { $0.occurs(on: .now) && $0.repeatRule == .none }) else {
            lockScreenTestStatus = "오늘 항목 없음"
            return
        }

        let taskID = task.id.uuidString
        let originalState = task.isCompleted
        lockScreenTestStatus = "테스트 중"

        Task {
            do {
                try await LockTodoTaskMutationStore.setCompletion(
                    taskIDString: taskID,
                    isCompleted: !originalState
                )
                try await Task.sleep(for: .milliseconds(250))
                try await LockTodoTaskMutationStore.setCompletion(
                    taskIDString: taskID,
                    isCompleted: originalState
                )

                await MainActor.run {
                    lockScreenTestStatus = "통과"
                    lastLockScreenAction = WidgetDataStore.lastLockScreenActionDescription
                    taskViewModel.refreshSharedState(allTasks: allTasks)
                    liveActivityService.refreshState()
                }
            } catch {
                await MainActor.run {
                    lockScreenTestStatus = "실패"
                    lastLockScreenAction = WidgetDataStore.lastLockScreenActionDescription
                }
            }
        }
    }

    private func exportTasksForAndroid() {
        do {
            let url = try LockTodoAndroidExportService.makeExportFile(tasks: allTasks)
            androidExportStatus = "\(allTasks.count)개 준비됨"
            androidExportFile = LockTodoShareFile(url: url)
        } catch {
            androidExportStatus = "실패"
        }
    }
}

private struct LockTodoShareFile: Identifiable {
    let id = UUID()
    var url: URL
}

private struct LockTodoActivityShareSheet: UIViewControllerRepresentable {
    var activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

private struct LockScreenControlDashboard: View {
    var lastAction: String

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 12) {
                Image(systemName: "checklist.checked")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.tint)
                    .frame(width: 52, height: 52)
                    .background(
                        Color.accentColor.opacity(0.12),
                        in: RoundedRectangle(cornerRadius: LockTodoDesign.tileRadius, style: .continuous)
                    )

                VStack(alignment: .leading, spacing: 2) {
                    Text("LockTodo Control")
                        .font(.system(size: 16, weight: .semibold))
                        .tracking(-0.2)
                    Text("잠금화면 하단 버튼을 생산성 버튼으로 바꿉니다.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)
            }

            HStack(spacing: 8) {
                ControlCapabilityPill(title: "빠른 입력", systemImage: "plus")
                ControlCapabilityPill(title: "오늘 보기", systemImage: "checklist")
                ControlCapabilityPill(title: "집중", systemImage: "scope")
            }

            HStack(spacing: 8) {
                Image(systemName: "waveform.path.ecg")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("마지막 동작")
                    .font(.caption.weight(.semibold))
                Spacer(minLength: 8)
                Text(lastAction)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 9)
            .lockTodoTile()
        }
        .padding(16)
        .lockTodoCard()
    }
}

private struct ControlCapabilityPill: View {
    var title: String
    var systemImage: String

    var body: some View {
        VStack(spacing: 5) {
            Image(systemName: systemImage)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color.accentColor)
                .frame(width: 28, height: 28)
                .background(Color.accentColor.opacity(0.12), in: Circle())

            Text(title)
                .font(.caption2.weight(.medium))
                .lineLimit(1)
                .minimumScaleFactor(0.78)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 9)
        .lockTodoTile()
    }
}

private struct ShortcutAutomationDashboard: View {
    private let actions = [
        ("스마트 입력", "내일 오후 3시 병원 ! #건강처럼 한 문장으로 추가", "wand.and.sparkles"),
        ("스마트 플랜", "오늘 항목 중 다음 집중 대상을 실시간 현황으로 시작", "sparkles"),
        ("잠금화면 순찰", "단축어 자동화로 Live Activity 카드 켜기/끄기", "shield.lefthalf.filled")
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Image(systemName: "app.badge")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 46, height: 46)
                    .background(Color.accentColor, in: RoundedRectangle(cornerRadius: LockTodoDesign.tileRadius, style: .continuous))

                VStack(alignment: .leading, spacing: 2) {
                    Text("LockTodo Shortcuts")
                        .font(.system(size: 16, weight: .semibold))
                        .tracking(-0.2)
                    Text("앱을 열지 않고 추가, 고정, 자동화를 실행합니다.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            VStack(spacing: 8) {
                ForEach(actions, id: \.0) { action in
                    HStack(spacing: 11) {
                        Image(systemName: action.2)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Color.accentColor)
                            .frame(width: 30, height: 30)
                            .background(Color.accentColor.opacity(0.12), in: Circle())

                        VStack(alignment: .leading, spacing: 1) {
                            Text(action.0)
                                .font(.subheadline.weight(.semibold))
                                .tracking(-0.1)
                            Text(action.1)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 11)
                    .padding(.vertical, 9)
                    .lockTodoTile()
                }
            }
        }
        .padding(16)
        .lockTodoCard()
    }
}

struct UpdateHistoryView: View {
    var body: some View {
        List {
            Section("최신 업데이트") {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("v2.1.0")
                            .font(.headline.bold())
                        Spacer()
                        Text("2026-06-11")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    
                    Text("• 단축어 플래터 배경 및 글래스모피즘(유리 느낌) 완성")
                        .font(.subheadline)
                    Text("• 단축어 목록 패딩 개선 및 항목 탭 터치 영역 확대")
                        .font(.subheadline)
                    Text("• 홈 화면 단순화 및 프리미엄 드롭다운 형태 보드 필터 적용")
                        .font(.subheadline)
                    Text("• 홈 화면 검색 바를 네이티브 내비게이션 검색으로 통합")
                        .font(.subheadline)
                    Text("• 습관 루틴 탭/롱프레스 제스처 통합 및 타이머 버튼 간소화")
                        .font(.subheadline)
                }
                .padding(.vertical, 4)
            }
            
            Section("이전 업데이트") {
                VStack(alignment: .leading, spacing: 12) {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("v2.0.0")
                                .font(.headline.bold())
                            Spacer()
                            Text("2026-06-10")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        
                        Text("• 집중 타이머와 인사이트(통계·연속 기록) 추가")
                            .font(.subheadline)
                        Text("• 잠금화면 Live Activity 백그라운드 자동 갱신")
                            .font(.subheadline)
                        Text("• 다이나믹 아일랜드 및 노치 영역별 알맞은 레이아웃 탑재")
                            .font(.subheadline)
                        Text("• 단축어 플래터 내 상세 설정(메모, 중요도, 태그 등) 입력 지원")
                            .font(.subheadline)
                    }
                    
                    Divider()
                    
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("v1.0.0")
                                .font(.headline.bold())
                            Spacer()
                            Text("최초 출시")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        
                        Text("• LockTodo 잠금화면 할 일 리스트 최초 출시")
                            .font(.subheadline)
                        Text("• 실시간 잠금화면 위젯 및 Live Activity 연동")
                            .font(.subheadline)
                    }
                }
                .padding(.vertical, 4)
            }
        }
        .navigationTitle("업데이트 내역")
        .navigationBarTitleDisplayMode(.inline)
    }
}
