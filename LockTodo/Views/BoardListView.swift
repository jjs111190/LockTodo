import SwiftUI
import SwiftData
import WidgetKit

struct BoardListView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \TaskBoard.orderIndex) private var boards: [TaskBoard]
    @Query private var tasks: [TaskItem]

    @State private var editingBoard: TaskBoard?
    @State private var showingAddBoard = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(boards) { board in
                        boardRow(board: board)
                            .listRowInsets(EdgeInsets(top: 5, leading: 16, bottom: 5, trailing: 16))
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                    }
                    .onDelete(perform: deleteBoards)
                    .onMove(perform: moveBoards)
                } header: {
                    Text("내 보드 목록")
                        .font(.footnote)
                        .textCase(nil)
                        .foregroundStyle(.secondary)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(LockTodoDesign.pageBackground.ignoresSafeArea())
            .navigationTitle("보드 관리")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("닫기") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: 16) {
                        EditButton()
                        Button {
                            showingAddBoard = true
                        } label: {
                            Image(systemName: "plus")
                        }
                    }
                }
            }
            .sheet(isPresented: $showingAddBoard) {
                BoardEditView(board: nil)
            }
            .sheet(item: $editingBoard) { board in
                BoardEditView(board: board)
            }
        }
    }

    private func boardRow(board: TaskBoard) -> some View {
        let boardTasks = tasks.filter { $0.boardID == board.id }
        let incompleteTasks = boardTasks.filter { !$0.isCompleted }
        let completedCount = boardTasks.filter(\.isCompleted).count
        let totalCount = boardTasks.count
        let progress = totalCount > 0 ? Double(completedCount) / Double(totalCount) : 0.0

        return NavigationLink(destination: BoardDetailView(board: board)) {
            HStack(spacing: 14) {
                Image(systemName: board.icon)
                    .font(.system(size: 18))
                    .foregroundStyle(Color(hex: board.colorHex))
                    .frame(width: 44, height: 44)
                    .background(
                        Color(hex: board.colorHex).opacity(0.13),
                        in: RoundedRectangle(cornerRadius: LockTodoDesign.tileRadius, style: .continuous)
                    )

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 5) {
                        Text(board.name)
                            .font(.system(size: 17, weight: .semibold))
                            .tracking(-0.3)
                            .foregroundStyle(.primary)

                        if board.isPinnedToLockScreen {
                            Image(systemName: "pin.fill")
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                                .accessibilityLabel("잠금화면 고정됨")
                        }
                    }

                    Text("\(incompleteTasks.count)개 남음 · 완료율 \(Int(progress * 100))%")
                        .font(.subheadline)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button {
                    editingBoard = board
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.system(size: 20))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.secondary)
                        .contentShape(Circle().inset(by: -8))
                }
                .buttonStyle(TactileButtonStyle(pressedScale: 0.86))
                .accessibilityLabel("\(board.name) 편집")
            }
            .padding(14)
            .lockTodoCard()
        }
        .buttonStyle(.lockTodoSurface)
    }

    private func deleteBoards(at offsets: IndexSet) {
        for index in offsets {
            let board = boards[index]
            let boardTasks = tasks.filter { $0.boardID == board.id }
            for task in boardTasks {
                task.boardID = nil
            }
            modelContext.delete(board)
        }
        try? modelContext.save()
        refreshLockScreenState()
    }

    private func moveBoards(from source: IndexSet, to destination: Int) {
        var reordered = boards
        reordered.move(fromOffsets: source, toOffset: destination)
        for (index, board) in reordered.enumerated() {
            board.orderIndex = index
        }
        try? modelContext.save()
        refreshLockScreenState()
    }

    private func refreshLockScreenState() {
        WidgetDataStore.saveSummary(from: tasks)
        WidgetCenter.shared.reloadAllTimelines()
        Task {
            await LiveActivityService.shared.updateCurrentSummary()
        }
    }
}
