import SwiftUI
import SwiftData
import WidgetKit

struct BoardDetailView: View {
    @Environment(\.modelContext) private var modelContext
    var board: TaskBoard

    @Query(sort: \TaskItem.sortOrder, order: .forward) private var allTasks: [TaskItem]

    @State private var newTaskTitle: String = ""
    @State private var showCompleted = false
    @StateObject private var viewModel = TaskViewModel()
    @ObservedObject private var locationService = LocationReminderService.shared
    @State private var selectedTask: TaskItem?

    private var nearbyLocationTaskIDs: Set<UUID> {
        Set(locationService.nearbyTasks(from: allTasks).map(\.id))
    }

    private var boardTasks: [TaskItem] {
        allTasks.filter { task in
            task.boardID == board.id
                && (!task.showOnlyAtLocation || nearbyLocationTaskIDs.contains(task.id))
        }
    }

    private var activeTasks: [TaskItem] {
        boardTasks.filter { !$0.isCompleted }
    }

    private var completedTasks: [TaskItem] {
        boardTasks.filter(\.isCompleted)
    }

    private var progress: Double {
        guard !boardTasks.isEmpty else { return 1.0 }
        return Double(completedTasks.count) / Double(boardTasks.count)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header stats card
            VStack(spacing: 12) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(board.name)
                            .font(.system(size: 28, weight: .bold))
                            .tracking(-0.6)
                            .foregroundStyle(Color(hex: board.colorHex))
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)

                        Text("\(activeTasks.count)개 남음 · 완료 \(completedTasks.count)개")
                            .font(.subheadline)
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                    Spacer()

                    ProgressRing(progress: progress, lineWidth: 6, showsLabel: true)
                        .frame(width: 56, height: 56)
                        .tint(Color(hex: board.colorHex))
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 16)
            .background(LockTodoDesign.cardBackground)
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(LockTodoDesign.separator)
                    .frame(height: LockTodoDesign.hairline)
            }

            // Task List
            List {
                Section {
                    ForEach(activeTasks) { task in
                        TaskRow(
                            task: task,
                            onToggle: { toggle(task) },
                            onDelete: { delete(task) },
                            onFocus: { },
                            onEdit: { selectedTask = task }
                        )
                        .onTapGesture { selectedTask = task }
                        .listRowInsets(EdgeInsets(top: 5, leading: 16, bottom: 5, trailing: 16))
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                    }

                    if activeTasks.isEmpty {
                        emptyState
                            .listRowInsets(EdgeInsets(top: 18, leading: 16, bottom: 18, trailing: 16))
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                    }
                } header: {
                    Text("할 일 목록")
                }

                if !completedTasks.isEmpty {
                    Section {
                        if showCompleted {
                            ForEach(completedTasks) { task in
                                TaskRow(
                                    task: task,
                                    onToggle: { toggle(task) },
                                    onDelete: { delete(task) },
                                    onFocus: { },
                                    onEdit: { selectedTask = task }
                                )
                                .onTapGesture { selectedTask = task }
                                .listRowInsets(EdgeInsets(top: 5, leading: 16, bottom: 5, trailing: 16))
                                .listRowSeparator(.hidden)
                                .listRowBackground(Color.clear)
                            }
                        }
                    } header: {
                        Button {
                            withAnimation(LockTodoMotion.sheet) {
                                showCompleted.toggle()
                            }
                        } label: {
                            HStack(spacing: 5) {
                                Text("완료됨 \(completedTasks.count)")
                                    .monospacedDigit()
                                Image(systemName: "chevron.down")
                                    .font(.system(size: 11, weight: .semibold))
                                    .rotationEffect(.degrees(showCompleted ? 180 : 0))
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.lockTodoSurface)
                        .font(.footnote.weight(.medium))
                        .textCase(nil)
                        .foregroundStyle(.secondary)
                        .lockTodoAnimation(LockTodoMotion.snappy, value: showCompleted)
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(LockTodoDesign.pageBackground)

            // Quick Add Input Bar
            VStack {
                HStack(spacing: 10) {
                    TextField("새 할 일 바로 추가...", text: $newTaskTitle, onCommit: addTask)
                        .textFieldStyle(.plain)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 11)
                        .background(LockTodoDesign.insetBackground, in: Capsule())

                    Button(action: addTask) {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 27))
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(
                                isNewTaskTitleEmpty ? Color.secondary.opacity(0.5) : Color(hex: board.colorHex)
                            )
                            .scaleEffect(isNewTaskTitleEmpty ? 0.9 : 1)
                            .contentShape(Circle().inset(by: -6))
                    }
                    .buttonStyle(TactileButtonStyle(pressedScale: 0.88))
                    .disabled(isNewTaskTitleEmpty)
                    .lockTodoAnimation(LockTodoMotion.snappy, value: isNewTaskTitleEmpty)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                // The input bar floats over the list rather than sitting on an
                // opaque strip, so content stays visible right up to the edge.
                .background(.regularMaterial)
                .overlay(alignment: .top) {
                    Rectangle()
                        .fill(LockTodoDesign.separator)
                        .frame(height: LockTodoDesign.hairline)
                }
            }
        }
        .navigationTitle(board.name)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $selectedTask) { task in
            TaskDetailView(task: task, viewModel: viewModel, allTasks: allTasks)
        }
        .task {
            locationService.start()
            locationService.syncMonitoredTasks(allTasks: allTasks)
        }
    }

    private var isNewTaskTitleEmpty: Bool {
        newTaskTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Text("보드가 비어 있습니다")
                .font(.system(size: 17, weight: .semibold))
                .tracking(-0.3)
            Text("아래 입력창을 통해 보드에 할 일을\n신속하게 추가해 보세요.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineSpacing(2)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 20)
        .padding(.vertical, 30)
        .lockTodoCard()
    }

    private func toggle(_ task: TaskItem) {
        viewModel.toggle(task, context: modelContext)
    }

    private func delete(_ task: TaskItem) {
        modelContext.delete(task)
        try? modelContext.save()
        WidgetDataStore.saveSummary(from: allTasks.filter { $0.id != task.id })
        WidgetCenter.shared.reloadAllTimelines()
        Task {
            await LiveActivityService.shared.updateCurrentSummary()
        }
    }

    private func addTask() {
        let cleanTitle = newTaskTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanTitle.isEmpty else { return }

        let nextSortOrder = (allTasks.map(\.sortOrder).max() ?? Date().timeIntervalSinceReferenceDate) + 1
        let task = TaskItem(
            title: cleanTitle,
            category: .today,
            colorHex: board.colorHex,
            boardID: board.id,
            dueDate: Calendar.current.startOfDay(for: .now),
            sortOrder: nextSortOrder
        )

        modelContext.insert(task)
        try? modelContext.save()

        newTaskTitle = ""
        WidgetDataStore.saveSummary(from: allTasks + [task])
        WidgetCenter.shared.reloadAllTimelines()
        Task {
            await LiveActivityService.shared.updateCurrentSummary()
        }
    }
}
