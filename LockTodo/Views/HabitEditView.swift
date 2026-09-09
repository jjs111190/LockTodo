import SwiftUI
import SwiftData

struct HabitEditView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme
    
    var habit: Habit? // 수정 대상 (nil 이면 새로 추가)
    
    @State private var title: String = ""
    @State private var selectedIcon: String = "circle"
    @State private var selectedColorHex: String = "#0A84FF"
    @State private var isReminderEnabled: Bool = false
    @State private var reminderTime: Date = Date()
    @State private var reminderOffsetMinutes: Int = 0
    
    // 미리 알림 오프셋 옵션 (분 단위)
    private let offsetOptions = [
        (0, "정시 알림"),
        (10, "10분 전"),
        (30, "30분 전"),
        (60, "1시간 전"),
        (120, "2시간 전"),
        (180, "3시간 전")
    ]
    
    // 건강, 다이어트 및 일상 생활 루틴에 어울리는 대표 아이콘들
    private let icons = [
        "figure.run", "figure.walk", "apple.logo", "drop.fill", "fork.knife",
        "dumbbell.fill", "flame.fill", "heart.fill", "lungs.fill", "brain.head.profile",
        "cup.and.saucer.fill", "pill.fill", "sleep", "bed.double.fill", "book.fill",
        "circle"
    ]
    
    private let colors = [
        "#0A84FF", "#30D158", "#BF5AF2", "#FF9F0A", "#FF453A",
        "#64D2FF", "#34C759", "#AF52DE", "#FF9500", "#FF3B30",
        "#5856D6", "#00C7BE", "#8E8E93", "#A2845E", "#1D1D1F"
    ]
    
    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 20) {
                    // 1. 루틴 이름
                    VStack(alignment: .leading, spacing: 8) {
                        Text("루틴 이름")
                            .font(.footnote.weight(.semibold))
                            .tracking(0.1)
                            .foregroundStyle(.secondary)
                        
                        TextField("예: 물 2L 마시기, 30분 달리기, 샐러드 먹기", text: $title)
                            .font(.body)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 13)
                            .lockTodoCard(radius: LockTodoDesign.tileRadius)
                    }
                    .padding(.horizontal, LockTodoDesign.pageInset)
                    
                    // 2. 테마 색상 및 아이콘 선택
                    VStack(alignment: .leading, spacing: 14) {
                        Text("테마 색상 및 아이콘")
                            .font(.footnote.weight(.semibold))
                            .tracking(0.1)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 16)
                        
                        // 색상 선택 그리드
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 12) {
                                ForEach(colors, id: \.self) { colorHex in
                                    let isSelected = selectedColorHex == colorHex

                                    Button {
                                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                        withAnimation(LockTodoMotion.snappy) {
                                            selectedColorHex = colorHex
                                        }
                                    } label: {
                                        Circle()
                                            .fill(Color(hex: colorHex))
                                            .frame(width: isSelected ? 28 : 32, height: isSelected ? 28 : 32)
                                            .frame(width: 38, height: 38)
                                            .background {
                                                Circle()
                                                    .strokeBorder(
                                                        isSelected ? Color(hex: colorHex).opacity(0.4) : .clear,
                                                        lineWidth: 3
                                                    )
                                            }
                                    }
                                    .buttonStyle(TactileButtonStyle(pressedScale: 0.88))
                                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                                }
                            }
                            .padding(.horizontal, LockTodoDesign.pageInset)
                            .padding(.vertical, 2)
                        }

                        // 아이콘 선택 그리드
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 6), spacing: 10) {
                            ForEach(icons, id: \.self) { icon in
                                let isSelected = selectedIcon == icon

                                Button {
                                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                    withAnimation(LockTodoMotion.snappy) {
                                        selectedIcon = icon
                                    }
                                } label: {
                                    Image(systemName: icon)
                                        .font(.system(size: 18))
                                        .foregroundStyle(isSelected ? .white : Color(hex: selectedColorHex))
                                        .frame(width: 44, height: 44)
                                        .background(
                                            isSelected
                                                ? Color(hex: selectedColorHex)
                                                : Color(hex: selectedColorHex).opacity(0.12),
                                            in: RoundedRectangle(cornerRadius: LockTodoDesign.controlRadius, style: .continuous)
                                        )
                                }
                                .buttonStyle(TactileButtonStyle(pressedScale: 0.9))
                                .accessibilityAddTraits(isSelected ? .isSelected : [])
                            }
                        }
                        .padding(.horizontal, LockTodoDesign.pageInset)
                    }
                    
                    // 3. 루틴 시간 및 알람 설정 (시간 설정 가능)
                    VStack(alignment: .leading, spacing: 14) {
                        Text("알림(알람) 설정")
                            .font(.footnote.weight(.semibold))
                            .tracking(0.1)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 16)
                        
                        VStack(spacing: 0) {
                            Toggle(isOn: $isReminderEnabled.animation(LockTodoMotion.sheet)) {
                                Label("매일 지정 시간 알람 받기", systemImage: "bell.badge.fill")
                                    .font(.system(size: 15, weight: .medium))
                            }
                            .tint(Color(hex: selectedColorHex))
                            .padding(14)

                            if isReminderEnabled {
                                Divider().padding(.leading, 14)

                                DatePicker(
                                    "시간 설정",
                                    selection: $reminderTime,
                                    displayedComponents: .hourAndMinute
                                )
                                .datePickerStyle(.compact)
                                .font(.system(size: 15, weight: .regular))
                                .padding(14)

                                Divider().padding(.leading, 14)

                                HStack {
                                    Label("알림 받기 기준", systemImage: "timer")
                                        .font(.system(size: 15, weight: .regular))
                                    Spacer()
                                    Picker("미리 알림", selection: $reminderOffsetMinutes) {
                                        ForEach(offsetOptions, id: \.0) { offset, title in
                                            Text(title).tag(offset)
                                        }
                                    }
                                    .pickerStyle(.menu)
                                    .tint(Color(hex: selectedColorHex))
                                }
                                .padding(14)
                            }
                        }
                        .lockTodoCard()
                        .padding(.horizontal, LockTodoDesign.pageInset)
                    }
                }
                .padding(.vertical, 16)
            }
            .background(LockTodoDesign.pageBackground.ignoresSafeArea())
            .navigationTitle(habit == nil ? "새 루틴 만들기" : "루틴 수정하기")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("취소") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("저장") {
                        save()
                    }
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .onAppear {
                if let habit {
                    title = habit.title
                    selectedIcon = habit.icon
                    selectedColorHex = habit.colorHex
                    isReminderEnabled = habit.isReminderEnabled
                    reminderOffsetMinutes = habit.reminderOffsetMinutes
                    if let savedTime = habit.reminderTime {
                        reminderTime = savedTime
                    }
                }
            }
        }
    }
    
    private func save() {
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanTitle.isEmpty else { return }
        
        let resolvedReminderTime = isReminderEnabled ? reminderTime : nil
        
        if let habit {
            // 수정 모드
            habit.title = cleanTitle
            habit.icon = selectedIcon
            habit.colorHex = selectedColorHex
            habit.isReminderEnabled = isReminderEnabled
            habit.reminderTime = resolvedReminderTime
            habit.reminderOffsetMinutes = isReminderEnabled ? reminderOffsetMinutes : 0
            
            // 알림 갱신
            Task {
                if isReminderEnabled {
                    await NotificationService.shared.scheduleHabitReminder(for: habit)
                } else {
                    NotificationService.shared.cancelHabitReminder(for: habit)
                }
            }
        } else {
            // 추가 모드
            let newHabit = Habit(
                title: cleanTitle,
                icon: selectedIcon,
                colorHex: selectedColorHex,
                isActive: true,
                reminderTime: resolvedReminderTime,
                isReminderEnabled: isReminderEnabled,
                reminderOffsetMinutes: isReminderEnabled ? reminderOffsetMinutes : 0
            )
            modelContext.insert(newHabit)
            
            // 알림 등록
            Task {
                if isReminderEnabled {
                    await NotificationService.shared.scheduleHabitReminder(for: newHabit)
                }
            }
        }
        
        try? modelContext.save()
        dismiss()
    }
}
