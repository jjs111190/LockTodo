import SwiftUI
import SwiftData

struct AddTaskView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var router: AppRouter
    @Query(sort: \TaskItem.sortOrder, order: .forward) private var allTasks: [TaskItem]
    @FocusState private var titleFocused: Bool
    @ObservedObject private var locationService = LocationReminderService.shared

    @ObservedObject var viewModel: TaskViewModel
    var initialDate: Date?
    var prefillTitle: String
    var autoFocus: Bool
    var initialLocation: TaskLocationDraft?
    var showOnlyAtInitialLocation: Bool

    @State private var title: String
    @State private var notes = ""
    @State private var category: TaskCategory
    @State private var hasDueDate: Bool
    @State private var dueDate: Date
    @State private var dueTime: Date
    @State private var hasTime = false
    @State private var hasReminder = false
    @State private var reminderDate: Date
    @State private var repeatRule: RepeatRule = .none
    @State private var tagsText = ""
    @State private var isImportant = false
    @State private var selectedColorHex = TaskTint.defaultHex
    @State private var isShowingComplete = false
    @State private var boardID: UUID? = nil
    @State private var showingBoardPicker = false
    @State private var hasLocationReminder = false
    @State private var locationTitle = ""
    @State private var locationLatitude: Double?
    @State private var locationLongitude: Double?
    @State private var locationRadius = 150.0
    @State private var isCapturingLocation = false
    @State private var locationMessage: String?

    init(
        viewModel: TaskViewModel,
        initialDate: Date? = Calendar.current.startOfDay(for: .now),
        prefillTitle: String = "",
        autoFocus: Bool = true,
        initialLocation: TaskLocationDraft? = nil,
        showOnlyAtInitialLocation: Bool = false
    ) {
        self.viewModel = viewModel
        self.initialDate = initialDate
        self.prefillTitle = prefillTitle
        self.autoFocus = autoFocus
        self.initialLocation = initialLocation
        self.showOnlyAtInitialLocation = showOnlyAtInitialLocation
        _title = State(initialValue: prefillTitle)
        let inferredCategory: TaskCategory
        if let initialDate {
            let calendar = Calendar.current
            if calendar.isDateInToday(initialDate) {
                inferredCategory = .today
            } else if calendar.isDateInTomorrow(initialDate) {
                inferredCategory = .tomorrow
            } else {
                inferredCategory = .scheduled
            }
        } else {
            inferredCategory = .today
        }
        _category = State(initialValue: inferredCategory)
        _hasDueDate = State(initialValue: true)
        let date = initialDate ?? Calendar.current.startOfDay(for: .now)
        _dueDate = State(initialValue: date)
        _dueTime = State(initialValue: Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: date) ?? date)
        _reminderDate = State(initialValue: Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: date) ?? date)
        _hasLocationReminder = State(initialValue: initialLocation != nil)
        _locationTitle = State(initialValue: initialLocation?.title ?? "")
        _locationLatitude = State(initialValue: initialLocation?.latitude)
        _locationLongitude = State(initialValue: initialLocation?.longitude)
        _locationRadius = State(initialValue: initialLocation?.radius ?? 150)
        _locationMessage = State(initialValue: initialLocation == nil ? nil : "이 위치에 도착하면 오늘 목록에 표시됩니다.")
    }

    var body: some View {
        NavigationStack {
            ZStack {
                if isShowingComplete {
                    CaptureCompleteView()
                        .transition(.opacity)
                } else {
                    mainFormView
                }
            }
            .navigationTitle(router.isQuickCaptureMode ? "빠른 할 일 추가" : "새 할 일")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if !isShowingComplete {
                    ToolbarItem(placement: .cancellationAction) {
                        Button { dismiss() } label: {
                            Image(systemName: "xmark")
                        }
                        .accessibilityLabel("닫기")
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button(action: saveAndCompleteFlow) {
                            Image(systemName: "checkmark")
                        }
                            .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                            .fontWeight(.semibold)
                            .accessibilityLabel("저장")
                    }
                }
            }
            .onAppear {
                if autoFocus {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                        titleFocused = true
                    }
                }
            }
        }
    }

    private var mainFormView: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 16) {
                titleSection
                organizationSection
                scheduleSection
                locationSection
                notesSection
            }
            .padding(.horizontal, LockTodoDesign.pageInset)
            .padding(.top, 12)
            .padding(.bottom, 36)
        }
        .background(LockTodoDesign.pageBackground.ignoresSafeArea())
    }

    private var titleSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                Circle()
                    .fill(Color(hex: selectedColorHex))
                    .frame(width: 10, height: 10)
                    .padding(.top, 9)
                    .lockTodoAnimation(LockTodoMotion.snappy, value: selectedColorHex)

                TextField("할 일 제목", text: $title, axis: .vertical)
                    .font(.title3.weight(.semibold))
                    .tracking(-0.3)
                    .focused($titleFocused)
                    .lineLimit(1...3)
                    .submitLabel(.done)
                    .onSubmit(saveAndCompleteFlow)

                Button {
                    isImportant.toggle()
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                } label: {
                    Image(systemName: isImportant ? "star.fill" : "star")
                        .font(.system(size: 17))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(isImportant ? .orange : .secondary)
                        .contentTransition(.symbolEffect(.replace))
                        .frame(width: 32, height: 32)
                        .contentShape(Circle().inset(by: -6))
                }
                .buttonStyle(TactileButtonStyle(pressedScale: 0.86))
                .accessibilityLabel(isImportant ? "중요 해제" : "중요 표시")
            }

            if smartInput.hasDetectedParts {
                Divider()
                SmartTaskParsePreview(parsed: smartInput, onApply: applySmartInput)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(16)
        .lockTodoCard()
        .lockTodoAnimation(LockTodoMotion.content, value: smartInput.hasDetectedParts)
    }

    private var organizationSection: some View {
        TaskDetailEditorSection(title: "정리", systemImage: "tray.full") {
            Picker("목록", selection: $category) {
                ForEach(TaskCategory.allCases) { item in
                    Text(item.title).tag(item)
                }
            }
            .onChange(of: category) { _, newValue in
                hasDueDate = newValue != .later
                updateDatesFor(category: newValue)
            }

            Divider()

            VStack(alignment: .leading, spacing: 10) {
                Label("색상", systemImage: "paintpalette")
                    .font(.subheadline)
                TaskColorSwatchPicker(selection: $selectedColorHex)
            }

            Divider()

            Button {
                showingBoardPicker = true
            } label: {
                HStack {
                    Label("보드", systemImage: "square.grid.2x2")
                    Spacer()
                    if let selectedBoard {
                        HStack(spacing: 6) {
                            Image(systemName: selectedBoard.icon)
                                .foregroundStyle(Color(hex: selectedBoard.colorHex))
                            Text(selectedBoard.name)
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        Text("없음")
                            .foregroundStyle(.secondary)
                    }
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.tertiary)
                }
            }
            .buttonStyle(.plain)
            .sheet(isPresented: $showingBoardPicker) {
                BoardPickerView(selectedBoardID: $boardID)
            }

            Divider()

            Picker("반복", selection: $repeatRule) {
                ForEach(RepeatRule.allCases) { rule in
                    Text(rule.title).tag(rule)
                }
            }
            .onChange(of: repeatRule) { _, newValue in
                guard newValue != .none, !hasDueDate else { return }
                hasDueDate = true
                category = .today
                dueDate = Calendar.current.startOfDay(for: .now)
            }

            Divider()

            HStack(spacing: 10) {
                Image(systemName: "number")
                    .foregroundStyle(.secondary)
                    .frame(width: 22)
                TextField("태그를 쉼표로 구분", text: $tagsText)
                    .textInputAutocapitalization(.never)
            }
        }
    }

    private var scheduleSection: some View {
        TaskDetailEditorSection(title: "일정", systemImage: "calendar") {
            detailToggle(title: "날짜", systemImage: "calendar", isOn: Binding(
                get: { hasDueDate },
                set: { enabled in
                    hasDueDate = enabled
                    if enabled && category == .later {
                        category = .today
                        updateDatesFor(category: .today)
                    } else if !enabled {
                        category = .later
                    }
                }
            ))
            if hasDueDate {
                DatePicker("마감일", selection: $dueDate, displayedComponents: .date)
                    .datePickerStyle(.compact)
                    .padding(.leading, 32)
            }

            Divider()

            detailToggle(title: "시간", systemImage: "clock", isOn: $hasTime)
            if hasTime {
                DatePicker("마감 시간", selection: $dueTime, displayedComponents: .hourAndMinute)
                    .datePickerStyle(.compact)
                    .padding(.leading, 32)
            }

            Divider()

            detailToggle(title: "알림", systemImage: "bell", isOn: $hasReminder)
            if hasReminder {
                DatePicker("알림 시간", selection: $reminderDate, displayedComponents: [.date, .hourAndMinute])
                    .datePickerStyle(.compact)
                    .padding(.leading, 32)
            }
        }
    }

    private var locationSection: some View {
        TaskDetailEditorSection(title: "위치", systemImage: "location") {
            detailToggle(
                title: "위치에서 보이기",
                systemImage: "mappin.and.ellipse",
                isOn: Binding(
                    get: { hasLocationReminder },
                    set: { setLocationReminderEnabled($0) }
                )
            )

            if hasLocationReminder {
                Divider()

                TextField("장소 이름", text: $locationTitle)
                    .textInputAutocapitalization(.words)

                HStack(spacing: 10) {
                    Label(locationCoordinateText, systemImage: locationLatitude == nil ? "location.slash" : "location.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)

                    Spacer(minLength: 8)

                    Button(action: captureCurrentLocation) {
                        if isCapturingLocation {
                            ProgressView().controlSize(.small)
                        } else {
                            Image(systemName: "location.circle.fill")
                                .font(.title3)
                        }
                    }
                    .buttonStyle(.plain)
                    .disabled(isCapturingLocation)
                    .accessibilityLabel(locationLatitude == nil ? "현재 위치 저장" : "위치 갱신")
                }

                Stepper("반경 \(Int(locationRadius))m", value: $locationRadius, in: 100...500, step: 50)

                if let message = locationMessage ?? locationService.statusMessage {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var notesSection: some View {
        TaskDetailEditorSection(title: "메모", systemImage: "note.text") {
            TextField("메모 추가", text: $notes, axis: .vertical)
                .lineLimit(3...8)
                .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }

    private func detailToggle(title: String, systemImage: String, isOn: Binding<Bool>) -> some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .foregroundStyle(.secondary)
                .frame(width: 22)
            Text(title)
                .font(.subheadline)
            Spacer()
            Toggle("", isOn: isOn)
                .labelsHidden()
        }
    }

    private var selectedBoard: TaskBoard? {
        guard let boardID else { return nil }
        return try? modelContext.fetch(FetchDescriptor<TaskBoard>()).first { $0.id == boardID }
    }

    private var quickDateButtons: some View {
        HStack(spacing: 8) {
            quickDateButton(title: "오늘", systemImage: "sun.max.fill", isSelected: category == .today && Calendar.current.isDateInToday(dueDate)) {
                category = .today
                dueDate = Calendar.current.startOfDay(for: .now)
            }
            quickDateButton(title: "내일", systemImage: "calendar.badge.clock", isSelected: category == .tomorrow && Calendar.current.isDateInTomorrow(dueDate)) {
                category = .tomorrow
                if let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: .now)) {
                    dueDate = tomorrow
                }
            }
            quickDateButton(title: "이번 주", systemImage: "calendar.badge.plus", isSelected: category == .scheduled && !Calendar.current.isDateInToday(dueDate) && !Calendar.current.isDateInTomorrow(dueDate)) {
                category = .scheduled
                if let nextDate = Calendar.current.date(byAdding: .day, value: 3, to: Calendar.current.startOfDay(for: .now)) {
                    dueDate = nextDate
                }
            }
            quickDateButton(title: "나중에", systemImage: "tray", isSelected: category == .later) {
                category = .later
            }
        }
    }

    private func quickDateButton(title: String, systemImage: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            action()
        }) {
            HStack(spacing: 5) {
                Image(systemName: systemImage)
                    .font(.system(size: 11, weight: .medium))
                Text(title)
                    .font(.footnote.weight(.medium))
            }
            .padding(.horizontal, 13)
            .padding(.vertical, 8)
            .foregroundStyle(isSelected ? .white : .primary)
            .background(isSelected ? Color.accentColor : LockTodoDesign.insetBackground)
            .clipShape(Capsule())
        }
        .buttonStyle(TactileButtonStyle(pressedScale: 0.94))
        .lockTodoAnimation(LockTodoMotion.snappy, value: isSelected)
    }

    private func updateDatesFor(category: TaskCategory) {
        if let defaultDate = category.defaultDueDate() {
            dueDate = defaultDate
            dueTime = Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: defaultDate) ?? defaultDate
            reminderDate = dueTime
        }
    }

    private var locationCoordinateText: String {
        guard let locationLatitude, let locationLongitude else {
            return "저장된 위치 없음"
        }
        return String(format: "%.5f, %.5f", locationLatitude, locationLongitude)
    }

    private var smartInput: SmartParsedTaskInput {
        SmartTaskInputParser.parse(
            title,
            fallbackCategory: category,
            fallbackDate: category == .later ? nil : dueDate,
            fallbackImportant: isImportant
        )
    }

    private func applySmartInput() {
        let parsed = smartInput
        guard parsed.hasDetectedParts else { return }

        title = parsed.title
        category = parsed.category
        hasDueDate = parsed.category != .later
        if let parsedDate = parsed.dueDate {
            dueDate = parsedDate
        }
        if let parsedTime = parsed.dueTime {
            hasTime = true
            dueTime = parsedTime
        }
        isImportant = parsed.isImportant
        tagsText = mergedTags(existingText: tagsText, parsedTags: parsed.tags).joined(separator: ", ")
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    private func setLocationReminderEnabled(_ isEnabled: Bool) {
        hasLocationReminder = isEnabled
        guard isEnabled else {
            locationMessage = nil
            return
        }

        Task {
            await ensureLocationDraft()
        }
    }

    private func captureCurrentLocation() {
        Task {
            await ensureLocationDraft(forceRefresh: true)
        }
    }

    private func ensureLocationDraft(forceRefresh: Bool = false) async {
        guard forceRefresh || locationLatitude == nil || locationLongitude == nil else { return }

        await MainActor.run {
            isCapturingLocation = true
            locationMessage = nil
        }

        let draft = await locationService.captureCurrentLocation()

        await MainActor.run {
            isCapturingLocation = false
            guard let draft else {
                locationMessage = locationService.statusMessage ?? "위치 권한을 허용한 뒤 다시 시도하세요."
                return
            }

            locationTitle = locationTitle.isEmpty ? draft.title : locationTitle
            locationLatitude = draft.latitude
            locationLongitude = draft.longitude
            locationRadius = draft.radius
            locationMessage = "이 위치에 가까워지면 할 일이 위에 표시됩니다."
        }
    }

    private func saveAndCompleteFlow() {
        let parsed = smartInput
        let cleanTitle = parsed.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanTitle.isEmpty else { return }

        var tags = mergedTags(existingText: tagsText, parsedTags: parsed.tags)
        if router.isQuickCaptureMode {
            tags = TaskItem.mergedTags(tags, adding: [TaskItem.lockScreenInboxTag])
        }
        let shouldSaveDate = hasDueDate || repeatRule != .none
        let finalCategory: TaskCategory = shouldSaveDate ? parsed.category : .later
        let finalDueDate = shouldSaveDate ? (parsed.dueDate ?? Calendar.current.startOfDay(for: dueDate)) : nil
        let finalDueTime = parsed.dueTime ?? (hasTime ? dueTime : nil)

        let task = viewModel.addTask(
            title: cleanTitle,
            notes: notes,
            category: finalCategory,
            dueDate: finalDueDate,
            dueTime: finalDueTime,
            reminderDate: hasReminder ? reminderDate : nil,
            repeatRule: repeatRule,
            tags: tags,
            isImportant: parsed.isImportant,
            colorHex: selectedColorHex,
            boardID: boardID,
            locationTitle: locationTitle,
            locationLatitude: hasLocationReminder ? locationLatitude : nil,
            locationLongitude: hasLocationReminder ? locationLongitude : nil,
            locationRadius: locationRadius,
            locationReminderEnabled: hasLocationReminder && locationLatitude != nil && locationLongitude != nil,
            showOnlyAtLocation: showOnlyAtInitialLocation && hasLocationReminder && locationLatitude != nil && locationLongitude != nil,
            context: modelContext,
            allTasks: allTasks
        )

        guard let task else { return }
        let hasLocationTrigger = task.hasLocationTrigger
        let refreshedTasks = (try? modelContext.fetch(FetchDescriptor<TaskItem>())) ?? allTasks
        viewModel.refreshSharedState(allTasks: refreshedTasks)

        if hasLocationTrigger {
            LocationReminderService.shared.requestLocationAccess()
            Task {
                _ = await NotificationService.shared.requestAuthorization()
            }
        }

        if router.isQuickCaptureMode {
            titleFocused = false
            withAnimation(.easeInOut(duration: 0.25)) {
                isShowingComplete = true
            }
            
            Task {
                try? await Task.sleep(for: .milliseconds(600))
                await MainActor.run {
                    dismiss()
                }
            }
        } else {
            dismiss()
        }
    }

    private func mergedTags(existingText: String, parsedTags: [String]) -> [String] {
        let existingTags = existingText
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        var seen = Set<String>()
        var merged: [String] = []
        for tag in existingTags + parsedTags {
            let key = tag.lowercased()
            guard !seen.contains(key) else { continue }
            seen.insert(key)
            merged.append(tag)
        }
        return merged
    }
}

struct TaskColorSwatchPicker: View {
    @Binding var selection: String

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(TaskTint.allCases) { tint in
                    let isSelected = TaskTint.normalized(selection) == tint.rawValue

                    Button {
                        withAnimation(LockTodoMotion.snappy) {
                            selection = tint.rawValue
                        }
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    } label: {
                        ZStack {
                            Circle()
                                .fill(Color(hex: tint.rawValue))
                                // The selected swatch grows into its ring
                                // rather than having a ring appear around it.
                                .frame(width: isSelected ? 28 : 30, height: isSelected ? 28 : 30)

                            if isSelected {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundStyle(.white)
                                    .transition(.opacity.combined(with: .scale(scale: 0.6)))
                            }
                        }
                        .frame(width: 38, height: 38)
                        .background {
                            Circle()
                                .strokeBorder(
                                    isSelected ? Color(hex: tint.rawValue).opacity(0.4) : Color.clear,
                                    lineWidth: 3
                                )
                        }
                    }
                    .buttonStyle(TactileButtonStyle(pressedScale: 0.88))
                    .accessibilityLabel(tint.title)
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                }
            }
            .padding(.vertical, 2)
        }
    }
}
