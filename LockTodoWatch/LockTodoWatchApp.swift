import SwiftUI
import WatchConnectivity

@main
struct LockTodoWatchApp: App {
    @StateObject private var watchStore = WatchTaskStore()

    var body: some Scene {
        WindowGroup {
            WatchTodayView()
                .environmentObject(watchStore)
        }
    }
}

struct WatchTodayView: View {
    @EnvironmentObject private var store: WatchTaskStore

    private var activeTasks: [WatchTaskSnapshot] {
        store.summary.orderedTasks.filter { !$0.isCompleted }
    }

    private var completedTasks: [WatchTaskSnapshot] {
        store.summary.orderedTasks.filter(\.isCompleted)
    }

    var body: some View {
        NavigationStack {
            List {
                progressSection

                if store.summary.orderedTasks.isEmpty {
                    emptySection
                } else {
                    if !activeTasks.isEmpty {
                        Section("남은 할 일") {
                            ForEach(activeTasks) { task in
                                taskRow(task)
                            }
                        }
                    }

                    if !completedTasks.isEmpty {
                        Section("완료됨") {
                            ForEach(completedTasks) { task in
                                taskRow(task)
                            }
                        }
                    }
                }
            }
            .navigationTitle("LockTodo")
            .toolbar {
                Button {
                    store.requestRefresh()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .accessibilityLabel("새로고침")
            }
        }
    }

    private var progressSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("오늘")
                        .font(.headline)
                    Spacer()
                    Text("\(store.summary.completedCount)/\(store.summary.totalCount)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                ProgressView(value: store.summary.progress)
                    .tint(.accentColor)

                Text(store.statusText)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 4)
        }
    }

    private var emptySection: some View {
        Section {
            VStack(spacing: 8) {
                Image(systemName: "checkmark.circle")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                Text("오늘 할 일이 없습니다")
                    .font(.headline)
                Text("iPhone에서 할 일을 추가하면 Watch에 표시됩니다.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .center)
        }
    }

    private func taskRow(_ task: WatchTaskSnapshot) -> some View {
        Button {
            store.toggle(task)
        } label: {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: task.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(task.isCompleted ? .green : .secondary)
                    .frame(width: 24)

                VStack(alignment: .leading, spacing: 3) {
                    Text(task.title)
                        .font(.body)
                        .foregroundStyle(task.isCompleted ? .secondary : .primary)
                        .strikethrough(task.isCompleted)
                        .lineLimit(3)

                    HStack(spacing: 5) {
                        if task.isImportant {
                            Label("중요", systemImage: "star.fill")
                        }

                        if let boardName = task.boardName {
                            Text(boardName)
                        }

                        if let dueTime = task.dueTime {
                            Text(dueTime.formatted(date: .omitted, time: .shortened))
                        }
                    }
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .labelStyle(.titleAndIcon)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(task.isCompleted ? "\(task.title) 미완료로 변경" : "\(task.title) 완료")
    }
}

final class WatchTaskStore: NSObject, ObservableObject, WCSessionDelegate {
    @Published var summary: WatchTaskSummarySnapshot = .empty
    @Published var statusText = "iPhone과 동기화 대기 중"

    private let summaryKey = "locktodo.watch.summary"

    override init() {
        super.init()
        loadCachedSummary()
        startSession()
    }

    func requestRefresh() {
        statusText = "새로고침 요청 중"
        guard WCSession.isSupported() else {
            statusText = "WatchConnectivity를 사용할 수 없습니다"
            return
        }

        let session = WCSession.default
        guard session.activationState == .activated, session.isReachable else {
            statusText = "iPhone 앱을 한 번 열어주세요"
            return
        }

        session.sendMessage(["command": "refresh"], replyHandler: nil) { [weak self] _ in
            DispatchQueue.main.async {
                self?.statusText = "iPhone 연결 실패"
            }
        }
    }

    func toggle(_ task: WatchTaskSnapshot) {
        let nextState = !task.isCompleted
        updateLocalTask(id: task.id, isCompleted: nextState)
        sendToggle(taskID: task.id, isCompleted: nextState)
    }

    private func startSession() {
        guard WCSession.isSupported() else {
            statusText = "WatchConnectivity를 사용할 수 없습니다"
            return
        }

        let session = WCSession.default
        session.delegate = self
        session.activate()
    }

    private func loadCachedSummary() {
        guard let data = UserDefaults.standard.data(forKey: summaryKey),
              let cached = try? JSONDecoder().decode(WatchTaskSummarySnapshot.self, from: data) else {
            return
        }
        summary = cached
        statusText = cached.statusText
    }

    private func saveCachedSummary() {
        guard let data = try? JSONEncoder().encode(summary) else { return }
        UserDefaults.standard.set(data, forKey: summaryKey)
    }

    private func applySummaryData(_ data: Data) {
        guard let nextSummary = try? JSONDecoder().decode(WatchTaskSummarySnapshot.self, from: data) else {
            return
        }

        DispatchQueue.main.async {
            self.summary = nextSummary
            self.statusText = nextSummary.statusText
            self.saveCachedSummary()
        }
    }

    private func updateLocalTask(id: UUID, isCompleted: Bool) {
        guard let taskIndex = summary.allTodayTasks.firstIndex(where: { $0.id == id }) else { return }

        summary.allTodayTasks[taskIndex].isCompleted = isCompleted
        summary.completedCount = summary.allTodayTasks.filter(\.isCompleted).count
        summary.totalCount = summary.allTodayTasks.count
        summary.remainingCount = summary.totalCount - summary.completedCount
        statusText = "동기화 중"
        saveCachedSummary()
    }

    private func sendToggle(taskID: UUID, isCompleted: Bool) {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        let payload: [String: Any] = [
            "command": "toggleTask",
            "taskID": taskID.uuidString,
            "isCompleted": isCompleted
        ]

        if session.activationState == .activated, session.isReachable {
            session.sendMessage(payload, replyHandler: nil) { [weak self] _ in
                DispatchQueue.main.async {
                    self?.statusText = "iPhone 연결 실패. 나중에 다시 시도됩니다."
                }
            }
        } else if session.activationState == .activated {
            session.transferUserInfo(payload)
            statusText = "iPhone 연결 시 반영됩니다"
        } else {
            statusText = "동기화 준비 중"
        }
    }

    func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        DispatchQueue.main.async {
            if activationState == .activated {
                self.statusText = self.summary.statusText
            } else {
                self.statusText = "iPhone 연결 준비 실패"
            }
        }
    }

    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        if let data = message["summary"] as? Data {
            applySummaryData(data)
        }
    }

    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        if let data = applicationContext["summary"] as? Data {
            applySummaryData(data)
        }
    }
}

struct WatchTaskSnapshot: Codable, Identifiable, Hashable {
    var id: UUID
    var title: String
    var isCompleted: Bool
    var isImportant: Bool
    var dueDate: Date?
    var dueTime: Date?
    var boardID: UUID?
    var boardName: String?
    var boardColorHex: String?
}

struct WatchTaskSummarySnapshot: Codable, Hashable {
    var generatedAt: Date
    var totalCount: Int
    var completedCount: Int
    var remainingCount: Int
    var importantTasks: [WatchTaskSnapshot]
    var allTodayTasks: [WatchTaskSnapshot]
    var pageIndex: Int
    var focusTitle: String?

    var orderedTasks: [WatchTaskSnapshot] {
        allTodayTasks.isEmpty ? importantTasks : allTodayTasks
    }

    var progress: Double {
        guard totalCount > 0 else { return 1 }
        return min(max(Double(completedCount) / Double(totalCount), 0), 1)
    }

    var statusText: String {
        guard totalCount > 0 else { return "동기화됨" }
        if remainingCount == 0 { return "오늘 할 일을 모두 완료했습니다" }
        return "\(remainingCount)개 남음"
    }

    static let empty = WatchTaskSummarySnapshot(
        generatedAt: .now,
        totalCount: 0,
        completedCount: 0,
        remainingCount: 0,
        importantTasks: [],
        allTodayTasks: [],
        pageIndex: 0,
        focusTitle: nil
    )
}
