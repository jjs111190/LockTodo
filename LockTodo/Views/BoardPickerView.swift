import SwiftUI
import SwiftData

struct BoardPickerView: View {
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \TaskBoard.orderIndex) private var boards: [TaskBoard]

    @Binding var selectedBoardID: UUID?

    var body: some View {
        NavigationStack {
            List {
                Button {
                    selectedBoardID = nil
                    dismiss()
                } label: {
                    HStack {
                        ZStack {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(Color.secondary.opacity(0.12))
                                .frame(width: 32, height: 32)

                            Image(systemName: "sun.max.fill")
                                .font(.footnote)
                                .foregroundStyle(.orange)
                        }

                        Text("기본 (오늘)")
                            .font(.body)
                            .foregroundStyle(.primary)

                        Spacer()

                        if selectedBoardID == nil {
                            Image(systemName: "checkmark")
                                .font(.subheadline.weight(.bold))
                                .foregroundStyle(Color.accentColor)
                        }
                    }
                }
                .buttonStyle(.plain)

                Section("내 보드 선택") {
                    ForEach(boards) { board in
                        Button {
                            selectedBoardID = board.id
                            dismiss()
                        } label: {
                            HStack(spacing: 12) {
                                ZStack {
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .fill(Color(hex: board.colorHex).opacity(0.12))
                                        .frame(width: 32, height: 32)

                                    Image(systemName: board.icon)
                                        .font(.footnote)
                                        .foregroundStyle(Color(hex: board.colorHex))
                                }

                                Text(board.name)
                                    .font(.body)
                                    .foregroundStyle(.primary)

                                Spacer()

                                if selectedBoardID == board.id {
                                    Image(systemName: "checkmark")
                                        .font(.subheadline.weight(.bold))
                                        .foregroundStyle(Color.accentColor)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .navigationTitle("보드 지정")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("닫기") { dismiss() }
                }
            }
        }
    }
}

