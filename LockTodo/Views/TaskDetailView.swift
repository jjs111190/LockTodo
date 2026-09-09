import SwiftUI
import SwiftData

struct TaskDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @ObservedObject private var locationService = LocationReminderService.shared

    @Bindable var task: TaskItem
    @ObservedObject var viewModel: TaskViewModel
    var allTasks: [TaskItem]

    @State private var hasDueDate: Bool
    @State private var editableDueDate: Date
    @State private var hasDueTime: Bool
    @State private var editableDueTime: Date
    @State private var hasReminder: Bool
    @State private var editableReminderDate: Date
    @State private var tagsText: String
    @State private var selectedColorHex: String
    @State private var hasLocationReminder: Bool
    @State private var locationTitle: String
    @State private var locationLatitude: Double?
    @State private var locationLongitude: Double?
    @State private var locationRadius: Double
    @State private var isCapturingLocation = false
    @State private var locationMessage: String?
    @State private var didCommit = false
    @State private var didDelete = false
    @State private var showingFocusTimer = false

    init(task: TaskItem, viewModel: TaskViewModel, allTasks: [TaskItem]) {
        self.task = task
        self.viewModel = viewModel
        self.allTasks = allTasks
        _hasDueDate = State(initialValue: task.dueDate != nil)
        _editableDueDate = State(initialValue: task.dueDate ?? Calendar.current.startOfDay(for: .now))
        _hasDueTime = State(initialValue: task.dueTime != nil)
        _editableDueTime = State(initialValue: task.dueTime ?? .now)
        _hasReminder = State(initialValue: task.reminderDate != nil)
        _editableReminderDate = State(initialValue: task.reminderDate ?? .now)
        _tagsText = State(initialValue: task.tags.joined(separator: ", "))
        _selectedColorHex = State(initialValue: task.safeColorHex)
        _hasLocationReminder = State(initialValue: task.hasLocationTrigger)
        _locationTitle = State(initialValue: task.locationTitle)
        _locationLatitude = State(initialValue: task.locationLatitude)
        _locationLongitude = State(initialValue: task.locationLongitude)
        _locationRadius = State(initialValue: task.locationRadius)
    }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 16) {
                    titleAndStatusSection

                    if !task.isCompleted {
                        Button {
                            showingFocusTimer = true
                        } label: {
                            Label("집중 타이머 시작", systemImage: "timer")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 15)
                        }
                        .buttonStyle(TactileButtonStyle(pressedScale: 0.98))
                        .foregroundStyle(.white)
                        .background(
                            Color(hex: selectedColorHex),
                            in: RoundedRectangle(cornerRadius: LockTodoDesign.cardRadius, style: .continuous)
                        )
                    }

                    organizationSection
                    scheduleSection
                    locationSection
                    notesSection

                    Button(role: .destructive) {
                        deleteTask()
                    } label: {
                        Label("할 일 삭제", systemImage: "trash")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                    }
                    .buttonStyle(TactileButtonStyle(pressedScale: 0.98))
                    .foregroundStyle(.red)
                    .background(
                        Color.red.opacity(0.10),
                        in: RoundedRectangle(cornerRadius: LockTodoDesign.cardRadius, style: .continuous)
                    )
                    .padding(.top, 4)
                }
                .padding(.horizontal, LockTodoDesign.pageInset)
                .padding(.top, 12)
                .padding(.bottom, 36)
            }
            .background(LockTodoDesign.pageBackground.ignoresSafeArea())
            .navigationTitle("할 일 수정")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $showingFocusTimer) {
                TaskFocusTimerView(task: task, viewModel: viewModel)
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        saveAndDismiss()
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .accessibilityLabel("닫기")
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        saveAndDismiss()
                    } label: {
                        Image(systemName: "checkmark")
                    }
                    .fontWeight(.semibold)
                    .accessibilityLabel("저장")
                }
            }
            .onDisappear {
                guard !didCommit, !didDelete else { return }
                applyEdits()
            }
        }
    }

    private var titleAndStatusSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                Circle()
                    .fill(Color(hex: selectedColorHex))
                    .frame(width: 10, height: 10)
                    .padding(.top, 8)

                TextField("할 일 제목", text: $task.title, axis: .vertical)
                    .font(.title3.weight(.semibold))
                    .lineLimit(1...3)

                Button {
                    task.isImportant.toggle()
                } label: {
                    Image(systemName: task.isImportant ? "star.fill" : "star")
                        .foregroundStyle(task.isImportant ? .orange : .secondary)
                        .frame(width: 30, height: 30)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(task.isImportant ? "중요 해제" : "중요 표시")
            }

            Picker("상태", selection: completionBinding) {
                Label("진행중", systemImage: "clock").tag(false)
                Label("완료", systemImage: "checkmark.circle.fill").tag(true)
            }
            .pickerStyle(.segmented)
        }
        .padding(16)
        .lockTodoCard()
    }

    private var organizationSection: some View {
        TaskDetailEditorSection(title: "정리", systemImage: "tray.full") {
            Picker("목록", selection: categoryBinding) {
                ForEach(TaskCategory.allCases) { category in
                    Text(category.title).tag(category)
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 10) {
                Label("색상", systemImage: "paintpalette")
                    .font(.subheadline)
                TaskColorSwatchPicker(selection: $selectedColorHex)
            }

            Divider()

            Picker("반복", selection: repeatBinding) {
                ForEach(RepeatRule.allCases) { rule in
                    Text(rule.title).tag(rule)
                }
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
            detailToggle(title: "날짜", systemImage: "calendar", isOn: $hasDueDate)
            if hasDueDate {
                DatePicker("마감일", selection: $editableDueDate, displayedComponents: .date)
                    .datePickerStyle(.compact)
                    .padding(.leading, 32)
            }

            Divider()

            detailToggle(title: "시간", systemImage: "clock", isOn: $hasDueTime)
            if hasDueTime {
                DatePicker("마감 시간", selection: $editableDueTime, displayedComponents: .hourAndMinute)
                    .datePickerStyle(.compact)
                    .padding(.leading, 32)
            }

            Divider()

            detailToggle(title: "알림", systemImage: "bell", isOn: $hasReminder)
            if hasReminder {
                DatePicker("알림 시간", selection: $editableReminderDate, displayedComponents: [.date, .hourAndMinute])
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

                    Button {
                        captureCurrentLocation()
                    } label: {
                        if isCapturingLocation {
                            ProgressView()
                                .controlSize(.small)
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
            TextField("메모 추가", text: $task.notes, axis: .vertical)
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

    private var categoryBinding: Binding<TaskCategory> {
        Binding(
            get: { task.category },
            set: { task.category = $0 }
        )
    }

    private var completionBinding: Binding<Bool> {
        Binding(
            get: { task.isCompleted },
            set: { newValue in
                guard task.isCompleted != newValue else { return }
                viewModel.toggle(task, context: modelContext, occurrenceDate: editableDueDate)
            }
        )
    }

    private var repeatBinding: Binding<RepeatRule> {
        Binding(
            get: { task.repeatRule },
            set: { newValue in
                task.repeatRule = newValue
                if newValue != .none, !hasDueDate {
                    hasDueDate = true
                    editableDueDate = Calendar.current.startOfDay(for: .now)
                }
            }
        )
    }

    private var locationCoordinateText: String {
        guard let locationLatitude, let locationLongitude else {
            return "저장된 위치 없음"
        }
        return String(format: "%.5f, %.5f", locationLatitude, locationLongitude)
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

    private func saveAndDismiss() {
        applyEdits()
        didCommit = true
        dismiss()
    }

    private func deleteTask() {
        didDelete = true
        viewModel.delete(task, context: modelContext)
        dismiss()
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

    private func applyEdits() {
        task.title = task.title.trimmingCharacters(in: .whitespacesAndNewlines)
        task.colorHex = TaskTint.normalized(selectedColorHex)
        task.dueDate = (hasDueDate || task.repeatRule != .none) ? Calendar.current.startOfDay(for: editableDueDate) : nil
        task.dueTime = hasDueTime ? editableDueTime : nil
        task.reminderDate = hasReminder ? editableReminderDate : nil
        task.tags = tagsText
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        task.locationTitle = locationTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        task.locationLatitude = hasLocationReminder ? locationLatitude : nil
        task.locationLongitude = hasLocationReminder ? locationLongitude : nil
        task.locationRadius = locationRadius
        task.locationReminderEnabled = hasLocationReminder && locationLatitude != nil && locationLongitude != nil
        if !task.locationReminderEnabled {
            task.showOnlyAtLocation = false
        }
        viewModel.update(task, context: modelContext)
    }
}

struct TaskDetailEditorSection<Content: View>: View {
    var title: String
    var systemImage: String
    var content: Content

    init(title: String, systemImage: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.systemImage = systemImage
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Section labels are quiet and small — they name the group without
            // competing with the values inside it.
            Label(title, systemImage: systemImage)
                .font(.footnote.weight(.semibold))
                .tracking(0.1)
                .foregroundStyle(.secondary)

            content
        }
        .padding(16)
        .lockTodoCard()
    }
}
