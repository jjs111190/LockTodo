import SwiftUI
import SwiftData

struct DiaryWriteView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    var completedTaskCount: Int
    var totalTaskCount: Int

    @State private var selectedMood: String = "😊 좋았어요"
    @State private var content: String = ""
    @State private var isSaved = false
    @State private var savedMessage = ""

    private let moods = [
        "😎 최고였어요",
        "😊 좋았어요",
        "😐 평범했어요",
        "😢 힘들었어요",
        "😴 피곤했어요"
    ]

    var body: some View {
        NavigationStack {
            VStack {
                if isSaved {
                    savedSuccessView
                } else {
                    diaryFormView
                }
            }
            .navigationTitle("오늘 하루 기록")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if !isSaved {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("닫기") {
                            dismiss()
                        }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("저장") {
                            saveEntry()
                        }
                        .disabled(content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .fontWeight(.semibold)
                    }
                }
            }
        }
    }
    
    private var diaryFormView: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 24) {
                // Today's completed tasks summary banner
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("오늘 나의 진행도")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        Text("할 일 \(completedTaskCount)개 완료 / 총 \(totalTaskCount)개")
                            .font(.system(size: 17, weight: .semibold))
                            .tracking(-0.3)
                            .monospacedDigit()
                            .foregroundStyle(.primary)
                    }
                    Spacer()
                    Image(systemName: "sparkles")
                        .font(.title2)
                        .foregroundStyle(.yellow)
                }
                .padding(16)
                .lockTodoCard()

                // Mood Selection Section
                VStack(alignment: .leading, spacing: 12) {
                    Text("오늘 하루는 어땠나요?")
                        .font(.system(size: 17, weight: .semibold))
                        .tracking(-0.3)
                        .foregroundStyle(.primary)

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(moods, id: \.self) { mood in
                                let isSelected = selectedMood == mood

                                Button {
                                    // A mood is a light, playful choice, so this
                                    // is one of the few places bounce belongs.
                                    withAnimation(LockTodoMotion.momentum) {
                                        selectedMood = mood
                                    }
                                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                } label: {
                                    Text(mood)
                                        .font(.system(size: 15, weight: .medium))
                                        .padding(.horizontal, 16)
                                        .padding(.vertical, 12)
                                        .background(isSelected ? Color.accentColor : LockTodoDesign.insetBackground)
                                        .foregroundStyle(isSelected ? .white : .primary)
                                        .clipShape(Capsule())
                                        .scaleEffect(isSelected ? 1.04 : 1.0)
                                }
                                .buttonStyle(TactileButtonStyle(pressedScale: 0.94))
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }

                // Content Write Section
                VStack(alignment: .leading, spacing: 12) {
                    Text("오늘의 감상 한 줄")
                        .font(.system(size: 17, weight: .semibold))
                        .tracking(-0.3)
                        .foregroundStyle(.primary)

                    TextField("오늘 어떤 일이 있었나요? 짧게 적어보세요.", text: $content, axis: .vertical)
                        .font(.body)
                        .lineSpacing(2)
                        .lineLimit(3...6)
                        .padding(16)
                        .lockTodoCard()
                }

                Spacer(minLength: 40)
            }
            .padding(LockTodoDesign.pageInset)
        }
        .background(LockTodoDesign.pageBackground.ignoresSafeArea())
    }
    
    private var savedSuccessView: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 72))
                .foregroundStyle(Color.accentColor)
                .transition(.scale)

            Text(savedMessage)
                .font(.system(size: 24, weight: .semibold))
                .tracking(-0.6)
                .lineSpacing(2)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
                .foregroundStyle(.primary)

            Spacer()

            Button {
                dismiss()
            } label: {
                Text("완료")
                    .font(.system(size: 17, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.capsule)
            .controlSize(.large)
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(LockTodoDesign.pageBackground.ignoresSafeArea())
    }
    
    private func saveEntry() {
        let newEntry = DiaryEntry(
            date: .now,
            moodRawValue: selectedMood,
            content: content,
            completedTaskCount: completedTaskCount,
            totalTaskCount: totalTaskCount
        )
        
        modelContext.insert(newEntry)

        let messages = [
            "오늘도 수고했어요. 내일도 힘내요!",
            "일기 쓰기 완료! 오늘 하루를 잘 마무리했어요.",
            "생각을 적는 건 참 좋은 습관이에요. 잘했어요!",
            "오늘 하루도 수고 많았어요. 푹 쉬어요!",
            "꾸준히 이어가는 모습이 멋져요!"
        ]
        savedMessage = messages.randomElement() ?? "오늘도 수고했어요!"
        
        withAnimation(.spring(response: 0.45, dampingFraction: 0.75)) {
            isSaved = true
        }
        
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)
    }
}
