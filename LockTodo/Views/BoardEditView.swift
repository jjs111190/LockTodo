import SwiftUI
import SwiftData
import WidgetKit

struct BoardEditView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \TaskBoard.orderIndex) private var boards: [TaskBoard]
    @Query private var tasks: [TaskItem]

    var board: TaskBoard?

    @State private var name: String = ""
    @State private var selectedIcon: String = "list.bullet"
    @State private var selectedColorHex: String = "#0A84FF"
    @State private var isPinnedToLockScreen: Bool = false

    private let icons = [
        "sun.max.fill", "book.fill", "cart.fill", "person.fill",
        "figure.run", "arrow.clockwise", "briefcase.fill",
        "graduationcap.fill", "house.fill", "heart.fill", "list.bullet"
    ]

    private let colors = [
        "#0A84FF",
        "#30D158",
        "#BF5AF2",
        "#FF9F0A",
        "#FF453A",
        "#64D2FF",
        "#FF375F"
    ]

    var body: some View {
        NavigationStack {
            Form {
                Section("보드 정보") {
                    TextField("보드 이름", text: $name)
                        .textInputAutocapitalization(.words)
                }

                Section("아이콘 선택") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 5), spacing: 12) {
                        ForEach(icons, id: \.self) { icon in
                            Button {
                                selectedIcon = icon
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            } label: {
                                Image(systemName: icon)
                                    .font(.title2)
                                    .frame(width: 44, height: 44)
                                    .foregroundStyle(selectedIcon == icon ? .white : .primary)
                                    .background(selectedIcon == icon ? Color(hex: selectedColorHex) : Color(.tertiarySystemGroupedBackground))
                                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 8)
                }

                Section("색상 선택") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 7), spacing: 12) {
                        ForEach(colors, id: \.self) { colorHex in
                            Button {
                                selectedColorHex = colorHex
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            } label: {
                                Circle()
                                    .fill(Color(hex: colorHex))
                                    .frame(width: 34, height: 34)
                                    .overlay {
                                        if selectedColorHex == colorHex {
                                            Circle()
                                                .stroke(Color.primary, lineWidth: 2)
                                        }
                                    }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 8)
                }

                Section("잠금화면 설정") {
                    Toggle("잠금화면 위젯에 고정", isOn: $isPinnedToLockScreen)
                }
            }
            .navigationTitle(board == nil ? "새 보드 추가" : "보드 편집")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("취소") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("저장", action: saveBoard)
                        .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .fontWeight(.semibold)
                }
            }
            .onAppear {
                if let board {
                    name = board.name
                    selectedIcon = board.icon
                    selectedColorHex = board.colorHex
                    isPinnedToLockScreen = board.isPinnedToLockScreen
                }
            }
        }
    }

    private func saveBoard() {
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanName.isEmpty else { return }

        if let board {
            board.name = cleanName
            board.icon = selectedIcon
            board.colorHex = selectedColorHex
            board.isPinnedToLockScreen = isPinnedToLockScreen
            board.updatedAt = .now
        } else {
            let nextIndex = (boards.map(\.orderIndex).max() ?? -1) + 1
            let newBoard = TaskBoard(
                name: cleanName,
                icon: selectedIcon,
                colorHex: selectedColorHex,
                orderIndex: nextIndex,
                isPinnedToLockScreen: isPinnedToLockScreen
            )
            modelContext.insert(newBoard)
        }

        try? modelContext.save()
        WidgetDataStore.saveSummary(from: tasks)
        WidgetCenter.shared.reloadAllTimelines()
        Task {
            await LiveActivityService.shared.updateCurrentSummary()
        }
        dismiss()
    }
}
