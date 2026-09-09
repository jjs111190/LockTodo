import SwiftUI
import SwiftData
import UIKit
import UserNotifications
import CoreData
import BackgroundTasks
import WidgetKit

@main
struct LockTodoApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var router = AppRouter()
    @StateObject private var taskViewModel = TaskViewModel()

    init() {
        Self.configureSystemBackgrounds()
        WidgetDataStore.registerDarwinObserver()
        WatchConnectivityService.shared.start()
        LocationReminderService.shared.start()
    }

    var body: some Scene {
        WindowGroup {
            RootView(taskViewModel: taskViewModel)
                .environmentObject(router)
                .modelContainer(Self.sharedModelContainer)
                .onOpenURL { url in
                    let context = Self.sharedModelContainer.mainContext
                    context.rollback()
                    refreshRealtimeLockScreenState(context: context)
                    router.handle(url: url)
                }
                .onReceive(NotificationCenter.default.publisher(for: .lockTodoOpenURL)) { notification in
                    if let url = notification.object as? URL {
                        let context = Self.sharedModelContainer.mainContext
                        context.rollback()
                        refreshRealtimeLockScreenState(context: context)
                        router.handle(url: url)
                    }
                }
                .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
                    let context = Self.sharedModelContainer.mainContext
                    context.rollback()
                    refreshRealtimeLockScreenState(context: context)
                    // Bring back the lock-screen card if iOS ended it in the
                    // background (its ~8h cap) while the app was suspended.
                    Task { await LiveActivityService.shared.reactivateIfNeeded() }
                    router.consumePendingShortcutIfNeeded()
                }
                .onReceive(NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification)) { _ in
                    // Locking the screen suspends the app, and an offline Live
                    // Activity can't be pushed while suspended — so make the last
                    // thing before suspension a fresh push, guaranteeing the
                    // lock-screen card shows the current state the instant you
                    // lock. Then queue a background window so it keeps refreshing.
                    let context = Self.sharedModelContainer.mainContext
                    refreshRealtimeLockScreenState(context: context)
                    BackgroundRefreshCoordinator.schedule()
                }
                .onReceive(NotificationCenter.default.publisher(for: .NSPersistentStoreRemoteChange)) { _ in
                    let context = Self.sharedModelContainer.mainContext
                    context.rollback()
                    refreshRealtimeLockScreenState(context: context)
                }
                .onReceive(NotificationCenter.default.publisher(for: .lockTodoDatabaseChangedExternal)) { _ in
                    let context = Self.sharedModelContainer.mainContext
                    context.rollback()
                    refreshRealtimeLockScreenState(context: context)
                }
                .task {
                    NotificationService.shared.registerCategories()
                    await NotificationService.shared.refreshAuthorizationStatus()
                    let context = Self.sharedModelContainer.mainContext
                    refreshRealtimeLockScreenState(context: context)
                    await LiveActivityService.shared.reactivateIfNeeded()
                    WatchConnectivityService.shared.sendCurrentSummary()
                    if let tasks = try? context.fetch(FetchDescriptor<TaskItem>()) {
                        LocationReminderService.shared.syncMonitoredTasks(allTasks: tasks)
                    }
                    router.consumePendingShortcutIfNeeded()
                }
        }
    }

    static var sharedModelContainer: ModelContainer = {
        WidgetDataStore.sharedModelContainer
    }()

    /// Chrome is a translucent layer that content passes *underneath*, not an
    /// opaque strip that eats a band of the screen. The blur is what tells you
    /// there is more content up there — an opaque bar throws that away, and a
    /// hard 1pt divider under it is a heavier separator than the material needs.
    private static func configureSystemBackgrounds() {
        let accentColor = UIColor.systemBlue
        UIView.appearance().tintColor = accentColor
        UITableView.appearance().sectionHeaderTopPadding = 8

        let navigationBarAppearance = UINavigationBarAppearance()
        navigationBarAppearance.configureWithDefaultBackground()
        navigationBarAppearance.shadowColor = .clear
        navigationBarAppearance.shadowImage = UIImage()
        // Tracking tightens as type grows: at 34pt the default spacing reads
        // loose, at 17pt it is already correct.
        navigationBarAppearance.titleTextAttributes = [
            .foregroundColor: UIColor.label,
            .font: UIFont.systemFont(ofSize: 17, weight: .semibold),
            .kern: -0.2
        ]
        navigationBarAppearance.largeTitleTextAttributes = [
            .foregroundColor: UIColor.label,
            .font: UIFont.systemFont(ofSize: 34, weight: .bold),
            .kern: -0.7
        ]
        navigationBarAppearance.buttonAppearance.normal.titleTextAttributes = [
            .foregroundColor: accentColor
        ]

        // At the scroll edge there is nothing behind the bar to separate from,
        // so the material disappears entirely and the page reads full-bleed.
        let navigationBarEdgeAppearance = UINavigationBarAppearance()
        navigationBarEdgeAppearance.configureWithTransparentBackground()
        navigationBarEdgeAppearance.shadowColor = .clear
        navigationBarEdgeAppearance.shadowImage = UIImage()
        navigationBarEdgeAppearance.titleTextAttributes = navigationBarAppearance.titleTextAttributes
        navigationBarEdgeAppearance.largeTitleTextAttributes = navigationBarAppearance.largeTitleTextAttributes
        navigationBarEdgeAppearance.buttonAppearance = navigationBarAppearance.buttonAppearance

        UINavigationBar.appearance().standardAppearance = navigationBarAppearance
        UINavigationBar.appearance().scrollEdgeAppearance = navigationBarEdgeAppearance
        UINavigationBar.appearance().compactAppearance = navigationBarAppearance
        UINavigationBar.appearance().tintColor = accentColor

        let tabBarAppearance = UITabBarAppearance()
        tabBarAppearance.configureWithDefaultBackground()
        tabBarAppearance.shadowColor = .clear
        tabBarAppearance.shadowImage = UIImage()
        let tabItemAppearance = UITabBarItemAppearance()
        tabItemAppearance.normal.iconColor = .secondaryLabel
        tabItemAppearance.normal.titleTextAttributes = [
            .foregroundColor: UIColor.secondaryLabel,
            .font: UIFont.systemFont(ofSize: 10, weight: .medium)
        ]
        tabItemAppearance.selected.iconColor = accentColor
        tabItemAppearance.selected.titleTextAttributes = [
            .foregroundColor: accentColor,
            .font: UIFont.systemFont(ofSize: 10, weight: .semibold)
        ]
        tabBarAppearance.stackedLayoutAppearance = tabItemAppearance
        tabBarAppearance.inlineLayoutAppearance = tabItemAppearance
        tabBarAppearance.compactInlineLayoutAppearance = tabItemAppearance
        UITabBar.appearance().standardAppearance = tabBarAppearance
        UITabBar.appearance().scrollEdgeAppearance = tabBarAppearance
        UITabBar.appearance().tintColor = accentColor

        let toolbarAppearance = UIToolbarAppearance()
        toolbarAppearance.configureWithDefaultBackground()
        toolbarAppearance.shadowColor = .clear
        UIToolbar.appearance().standardAppearance = toolbarAppearance
        UIToolbar.appearance().scrollEdgeAppearance = toolbarAppearance
        UIToolbar.appearance().tintColor = accentColor
    }

    private func refreshRealtimeLockScreenState(context: ModelContext) {
        context.refreshAll()
        WidgetDataStore.autoUpdateTaskCategories(context: context)

        if let allTasks = try? context.fetch(FetchDescriptor<TaskItem>()) {
            taskViewModel.refreshSharedState(allTasks: allTasks)
        }

        taskViewModel.refresh(context: context)
    }
}

struct RootView: View {
    @EnvironmentObject private var router: AppRouter
    @AppStorage("locktodo.hasSeenTutorial") private var hasSeenTutorial = false
    @AppStorage("locktodo.hasSeenHighlightTutorial.v1") private var hasSeenHighlightTutorial = false
    @AppStorage("locktodo.appearanceStyle") private var appearanceStyle = "system"
    @ObservedObject var taskViewModel: TaskViewModel
    @StateObject private var toastCenter = LockTodoToastCenter()
    @State private var showsTutorial = false
    @State private var didRunStartupPresentation = false
    @State private var showsHighlightTutorial = false

    private var colorScheme: ColorScheme? {
        switch appearanceStyle {
        case "light": return .light
        case "dark": return .dark
        default: return nil
        }
    }

    var body: some View {
        TabView(selection: $router.selectedTab) {
            TodayView(viewModel: taskViewModel)
                .tabItem {
                    Label("오늘", systemImage: "checklist")
                }
                .tag(AppRouter.Tab.today)

            MapTodoView(viewModel: taskViewModel)
                .tabItem {
                    Label("지도", systemImage: "map")
                }
                .tag(AppRouter.Tab.map)

            CalendarView(taskViewModel: taskViewModel)
                .tabItem {
                    Label("달력", systemImage: "calendar")
                }
                .tag(AppRouter.Tab.calendar)

            SettingsView(taskViewModel: taskViewModel)
                .tabItem {
                    Label("설정", systemImage: "gearshape")
                }
                .tag(AppRouter.Tab.settings)
        }
        .background(LockTodoDesign.pageBackground.ignoresSafeArea())
        .tint(.accentColor)
        .environmentObject(toastCenter)
        // The toast lives above the tab bar so undo nudges float over the whole
        // app, not clipped inside one tab's content.
        .lockTodoToast(toastCenter)
        .dismissKeyboardOnOutsideTap()
        .preferredColorScheme(colorScheme)
        .overlayPreferenceValue(TutorialHighlightPreferenceKey.self) { anchors in
            GeometryReader { proxy in
                if showsHighlightTutorial {
                    HighlightTutorialView(
                        selectedTab: $router.selectedTab,
                        isPresented: $showsHighlightTutorial,
                        targetFrames: anchors.mapValues { proxy[$0] },
                        containerSize: proxy.size,
                        safeAreaInsets: proxy.safeAreaInsets
                    ) {
                        hasSeenHighlightTutorial = true
                    }
                    .transition(.opacity)
                    .zIndex(20)
                }
            }
        }
        .onAppear {
            guard !didRunStartupPresentation else { return }
            didRunStartupPresentation = true

            if !hasSeenTutorial {
                showsTutorial = true
            } else if !hasSeenHighlightTutorial {
                showsHighlightTutorial = true
            }
        }
        .sheet(isPresented: $showsTutorial, onDismiss: {
            hasSeenTutorial = true
            if !hasSeenHighlightTutorial {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                    showsHighlightTutorial = true
                }
            }
        }) {
            NavigationStack {
                TutorialView()
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("시작하기") {
                                hasSeenTutorial = true
                                showsTutorial = false
                            }
                            .fontWeight(.semibold)
                        }
                    }
            }
        }
    }
}

private struct HighlightTutorialView: View {
    @Binding var selectedTab: AppRouter.Tab
    @Binding var isPresented: Bool
    var targetFrames: [TutorialHighlightTarget: CGRect]
    var containerSize: CGSize
    var safeAreaInsets: EdgeInsets
    var onFinish: () -> Void
    @State private var step = 0

    private let steps: [(title: String, detail: String, image: String)] = [
        ("오늘의 흐름", "완료율과 연속 기록 아래에서 오늘 해야 할 일을 바로 확인할 수 있어요.", "checklist"),
        ("빠른 할 일 추가", "오른쪽 위 + 버튼을 누르면 작성 화면이 바로 열려요.", "plus.circle.fill"),
        ("잠금화면에 고정", "상단 핀 버튼을 누르면 오늘 목록이 잠금화면에 표시돼요.", "pin.fill"),
        ("화면 이동", "지도, 달력, 설정은 아래 탭에서 언제든 열 수 있어요.", "rectangle.3.group")
    ]

    var body: some View {
        ZStack {
                // Dim to focus: the scrim pushes the app back so the ring is
                // unmistakably the subject.
                Color.black.opacity(0.55)
                    .ignoresSafeArea()

                highlight

                VStack {
                    HStack {
                        Spacer()
                        Button("건너뛰기") { finish() }
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.9))
                            .padding(.horizontal, 16)
                            .padding(.top, 10)
                    }

                    Spacer()

                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Image(systemName: steps[step].image)
                                .font(.title3.weight(.semibold))
                                .foregroundStyle(.tint)
                                .contentTransition(.symbolEffect(.replace))

                            Spacer()

                            // Progress as dots, not a fraction — the shape of
                            // "how far along am I" is read faster than digits.
                            HStack(spacing: 5) {
                                ForEach(0..<steps.count, id: \.self) { index in
                                    Capsule()
                                        .fill(index == step ? Color.accentColor : Color.secondary.opacity(0.3))
                                        .frame(width: index == step ? 16 : 5, height: 5)
                                }
                            }
                        }

                        Text(steps[step].title)
                            .font(.title2.weight(.bold))
                            .tracking(-0.5)

                        Text(steps[step].detail)
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)

                        Button {
                            advance()
                        } label: {
                            Text(step == steps.count - 1 ? "시작하기" : "다음")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                        }
                        .buttonStyle(.borderedProminent)
                        .buttonBorderShape(.roundedRectangle(radius: 14))
                        .padding(.top, 2)
                    }
                    .padding(20)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                    .overlay {
                        // A bright top edge reads as light catching the
                        // material — it is what makes glass look like glass.
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.18), lineWidth: 0.5)
                    }
                    .shadow(color: .black.opacity(0.28), radius: 30, y: 12)
                    .padding(.horizontal, 16)
                    .padding(.bottom, step == 3 ? 96 : 28)
                }
        }
        .lockTodoAnimation(LockTodoMotion.standard, value: step)
        .onAppear { selectedTab = .today }
    }

    @ViewBuilder
    private var highlight: some View {
        let rect = highlightRect
        let radius: CGFloat = step == 0 ? LockTodoDesign.cardRadius + 3 : 16
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)

        shape
            .strokeBorder(Color.white, lineWidth: 2.5)
            .background(Color.white.opacity(0.10), in: shape)
            .frame(width: rect.width, height: rect.height)
            .position(x: rect.midX, y: rect.midY)
            .shadow(color: .white.opacity(0.3), radius: 14)
            .allowsHitTesting(false)
    }

    private var highlightRect: CGRect {
        let target: TutorialHighlightTarget? = switch step {
        case 0: .overview
        case 1: .addTask
        case 2: .pin
        default: nil
        }

        if let target, let frame = targetFrames[target], !frame.isEmpty {
            return frame.insetBy(dx: -7, dy: -7)
        }

        if step == 3 {
            let height: CGFloat = 68 + safeAreaInsets.bottom
            return CGRect(
                x: 6,
                y: containerSize.height - height,
                width: containerSize.width - 12,
                height: height - 4
            )
        }

        // Toolbar anchors can arrive one layout pass later. Keep the fallback
        // aligned to the actual safe-area and navigation bar instead of a fixed y.
        let buttonSize: CGFloat = 50
        let top = safeAreaInsets.top + 4
        let trailing = step == 1 ? 10.0 : 64.0
        return CGRect(
            x: containerSize.width - trailing - buttonSize,
            y: top,
            width: buttonSize,
            height: buttonSize
        )
    }

    private func advance() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        if step < steps.count - 1 {
            step += 1
        } else {
            finish()
        }
    }

    private func finish() {
        onFinish()
        withAnimation(LockTodoMotion.content) {
            isPresented = false
        }
    }
}

private extension View {
    func dismissKeyboardOnOutsideTap() -> some View {
        background(KeyboardDismissTapLayer().allowsHitTesting(false))
    }
}

private struct KeyboardDismissTapLayer: UIViewRepresentable {
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: .zero)
        view.isUserInteractionEnabled = false
        context.coordinator.attachIfNeeded(to: view)
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.attachIfNeeded(to: uiView)
    }

    static func dismantleUIView(_ uiView: UIView, coordinator: Coordinator) {
        coordinator.detach()
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        private weak var recognizer: UITapGestureRecognizer?
        private weak var window: UIWindow?

        func attachIfNeeded(to view: UIView) {
            DispatchQueue.main.async { [weak self, weak view] in
                guard let self, self.recognizer == nil, let window = view?.window else { return }

                let recognizer = UITapGestureRecognizer(target: self, action: #selector(self.handleTap(_:)))
                recognizer.cancelsTouchesInView = false
                recognizer.delegate = self
                window.addGestureRecognizer(recognizer)
                self.recognizer = recognizer
                self.window = window
            }
        }

        func detach() {
            if let recognizer, let window {
                window.removeGestureRecognizer(recognizer)
            }
            recognizer = nil
            window = nil
        }

        @objc private func handleTap(_ recognizer: UITapGestureRecognizer) {
            guard let window = recognizer.view as? UIWindow else { return }
            let point = recognizer.location(in: window)
            guard window.hitTest(point, with: nil)?.isTextInputDescendant != true else { return }
            window.endEditing(true)
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
            touch.view?.isTextInputDescendant != true
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            true
        }
    }
}

private extension UIView {
    var isTextInputDescendant: Bool {
        if self is UITextField || self is UITextView || self is UISearchBar {
            return true
        }
        return superview?.isTextInputDescendant ?? false
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        // Must register the handler before launch finishes, or iOS refuses to
        // hand us the background window later.
        BackgroundRefreshCoordinator.register()
        BackgroundRefreshCoordinator.schedule()
        return true
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        guard let urlString = response.notification.request.content.userInfo["url"] as? String,
              let url = URL(string: urlString) else {
            return
        }

        await MainActor.run {
            NotificationCenter.default.post(name: .lockTodoOpenURL, object: url)
        }
    }
}

extension Notification.Name {
    static let lockTodoOpenURL = Notification.Name("LockTodoOpenURL")
}

/// Keeps the lock-screen Live Activity and widgets fresh while the app is
/// suspended. An offline app receives no ActivityKit push, so a Live Activity
/// left on the lock screen would otherwise freeze at whatever it showed when the
/// app was last open. A repeating `BGAppRefreshTask` is the only Apple-sanctioned
/// way to update it without a push server: each time iOS grants a background
/// window, we recompute today's summary from live data (dropping left-location
/// and past-date items, rolling the day over) and push it to the Activity and
/// widgets. iOS decides the cadence — typically tens of minutes, more often for
/// frequently-used apps — so this is best-effort freshness, not instant. Truly
/// real-time background updates would require APNs, which this app avoids by
/// design.
enum BackgroundRefreshCoordinator {
    static let taskIdentifier = "com.jaeseok.LockTodo.refresh"
    private static let minimumInterval: TimeInterval = 15 * 60

    static func register() {
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: taskIdentifier,
            using: nil
        ) { task in
            guard let refreshTask = task as? BGAppRefreshTask else {
                task.setTaskCompleted(success: false)
                return
            }
            handle(refreshTask)
        }
    }

    static func schedule() {
        let request = BGAppRefreshTaskRequest(identifier: taskIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: minimumInterval)
        // Fails on the Simulator and when the user has turned Background App
        // Refresh off — neither is fatal, the foreground paths still update.
        try? BGTaskScheduler.shared.submit(request)
    }

    private static func handle(_ task: BGAppRefreshTask) {
        // Line up the next window first so the chain never breaks, even if this
        // run is cut short.
        schedule()

        let work = Task { @MainActor in
            await refreshNow()
            task.setTaskCompleted(success: !Task.isCancelled)
        }

        task.expirationHandler = { work.cancel() }
    }

    /// Recompute today's state from live data and push it everywhere.
    @MainActor
    static func refreshNow() async {
        // reactivateIfNeeded rebuilds the summary from the store (self-expiring
        // location IDs + date filter) and either rolls the card over past the
        // ~8h cap or updates it in place.
        await LiveActivityService.shared.reactivateIfNeeded()
        WidgetCenter.shared.reloadAllTimelines()
    }
}
