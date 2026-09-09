import SwiftUI
import SwiftData

struct HabitManagementView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme
    
    @Query(sort: \Habit.createdAt, order: .forward) private var habits: [Habit]
    
    @State private var showingAddHabit = false
    @State private var habitToEdit: Habit? = nil
    
    var body: some View {
        NavigationStack {
            List {
                if habits.isEmpty {
                    Section {
                        VStack(spacing: 10) {
                            Spacer()
                            Image(systemName: "figure.flexibility")
                                .font(.system(size: 38, weight: .light))
                                .foregroundStyle(.secondary)
                                .padding(.bottom, 2)
                            Text("등록된 루틴이 없습니다")
                                .font(.system(size: 17, weight: .semibold))
                                .tracking(-0.3)
                            Text("나만의 다이어트 및 건강 관리 루틴을\n우측 상단 + 버튼을 눌러 추가해보세요.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                                .lineSpacing(2)
                            Spacer()
                        }
                        .frame(maxWidth: .infinity, minHeight: 200)
                        .listRowBackground(Color.clear)
                    }
                } else {
                    Section {
                        ForEach(habits) { habit in
                            habitRow(for: habit)
                                .listRowInsets(EdgeInsets(top: 5, leading: 16, bottom: 5, trailing: 16))
                                .listRowBackground(Color.clear)
                                .listRowSeparator(.hidden)
                        }
                        .onDelete(perform: deleteHabits)
                    } header: {
                        Text("나의 루틴 목록")
                            .font(.footnote)
                            .textCase(nil)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(LockTodoDesign.pageBackground.ignoresSafeArea())
            .navigationTitle("루틴 설정")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("닫기") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showingAddHabit = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("루틴 추가")
                }
            }
            .sheet(isPresented: $showingAddHabit) {
                HabitEditView()
            }
            .sheet(item: $habitToEdit) { habit in
                HabitEditView(habit: habit)
            }
        }
    }
    
    @ViewBuilder
    private func habitRow(for habit: Habit) -> some View {
        let habitColor = Color(hex: habit.colorHex)
        
        // The whole row opens the editor — a 13pt chevron is a target, not a
        // decoration, and it should not be the only way in.
        Button {
            habitToEdit = habit
        } label: {
            HStack(spacing: 14) {
                Image(systemName: habit.icon)
                    .font(.system(size: 17))
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .background(habitColor, in: Circle())

                VStack(alignment: .leading, spacing: 2) {
                    Text(habit.title)
                        .font(.system(size: 16, weight: .semibold))
                        .tracking(-0.2)
                        .foregroundStyle(.primary)

                    HStack(spacing: 6) {
                        Text("\(habit.streak)일 연속 달성 중")
                            .font(.caption)
                            .monospacedDigit()
                            .foregroundStyle(.secondary)

                        if habit.isReminderEnabled, let reminderTime = habit.reminderTime {
                            Text("·")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                            Label(reminderTime.formatted(date: .omitted, time: .shortened), systemImage: "bell.fill")
                                .font(.caption)
                                .monospacedDigit()
                                .foregroundStyle(habitColor)
                        }
                    }
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.lockTodoSurface)
        .lockTodoCard()
    }
    
    private func deleteHabits(at offsets: IndexSet) {
        for index in offsets {
            let habit = habits[index]
            // 알림 예약 제거
            NotificationService.shared.cancelHabitReminder(for: habit)
            modelContext.delete(habit)
        }
        try? modelContext.save()
    }
}
