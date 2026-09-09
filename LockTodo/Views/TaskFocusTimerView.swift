import SwiftUI
import SwiftData
import UIKit

/// A Pomodoro-style focus timer for a single task. Finishing (or stopping) logs
/// a `FocusSession`, which the Insights screen turns into deep-focus stats — so
/// "time spent focusing" grows alongside "tasks completed".
struct TaskFocusTimerView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let task: TaskItem
    var viewModel: TaskViewModel

    private let presets = [15, 25, 50]

    @State private var targetMinutes = 25
    @State private var secondsRemaining = 25 * 60
    @State private var isRunning = false
    @State private var isFinished = false
    @State private var logged = false
    @State private var didCompleteTask = false
    @State private var timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    private var taskColor: Color { Color(hex: task.safeColorHex) }
    private var totalSeconds: Int { targetMinutes * 60 }
    private var elapsedSeconds: Int { totalSeconds - secondsRemaining }
    private var progress: Double {
        totalSeconds == 0 ? 0 : Double(elapsedSeconds) / Double(totalSeconds)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Spacer(minLength: 0)
            statusArea
            timerRing
                .padding(.vertical, 24)
            Spacer(minLength: 0)
            if !isFinished { presetPicker }
            controls
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 28)
        .background(LockTodoDesign.pageBackground.ignoresSafeArea())
        .onReceive(timer) { _ in tick() }
        .onAppear { UIApplication.shared.isIdleTimerDisabled = true }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false
            logSessionIfNeeded() // capture partial focus if closed early
        }
        .interactiveDismissDisabled(isRunning)
    }

    // MARK: Header

    private var header: some View {
        HStack {
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 32, height: 32)
                    .contentShape(Circle())
            }
            .buttonStyle(TactileButtonStyle(pressedScale: 0.86))

            Spacer()

            VStack(spacing: 2) {
                Text("집중")
                    .font(.caption.weight(.semibold))
                    .tracking(0.3)
                    .foregroundStyle(.secondary)
                Text(task.title)
                    .font(.system(size: 16, weight: .semibold))
                    .tracking(-0.2)
                    .lineLimit(1)
            }

            Spacer()

            Color.clear.frame(width: 32, height: 32)
        }
        .padding(.top, 12)
    }

    // MARK: Status

    private var statusArea: some View {
        Text(isFinished ? "집중을 끝냈어요"
             : isRunning ? "집중하는 중"
             : "준비되면 시작하세요")
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .contentTransition(.opacity)
    }

    // MARK: Ring

    private var timerRing: some View {
        ZStack {
            Circle()
                .stroke(taskColor.opacity(0.12), lineWidth: 14)

            Circle()
                .trim(from: 0, to: min(max(progress, 0), 1))
                .stroke(taskColor, style: StrokeStyle(lineWidth: 14, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .lockTodoAnimation(LockTodoMotion.standard, value: progress)

            VStack(spacing: 2) {
                Text(timeString)
                    .font(.system(size: 54, weight: .light, design: .rounded))
                    .tracking(-1.5)
                    .monospacedDigit()
                    .foregroundStyle(.primary)
                    .contentTransition(.numericText(countsDown: true))
                Text(isFinished ? "완료" : "\(targetMinutes)분 세션")
                    .font(.caption)
                    .tracking(0.2)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 240, height: 240)
    }

    private var timeString: String {
        let s = max(secondsRemaining, 0)
        return String(format: "%02d:%02d", s / 60, s % 60)
    }

    // MARK: Presets

    private var presetPicker: some View {
        HStack(spacing: 8) {
            ForEach(presets, id: \.self) { minutes in
                let isSelected = targetMinutes == minutes
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    withAnimation(LockTodoMotion.snappy) {
                        targetMinutes = minutes
                        secondsRemaining = minutes * 60
                    }
                } label: {
                    Text("\(minutes)분")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11)
                        .foregroundStyle(isSelected ? .white : .primary)
                        .background(isSelected ? taskColor : Color.primary.opacity(0.06), in: Capsule())
                }
                .buttonStyle(TactileButtonStyle(pressedScale: 0.95))
                .disabled(isRunning || elapsedSeconds > 0)
            }
        }
        .opacity(isRunning || elapsedSeconds > 0 ? 0.4 : 1)
        .padding(.bottom, 16)
    }

    // MARK: Controls

    @ViewBuilder
    private var controls: some View {
        if isFinished {
            VStack(spacing: 10) {
                if !task.isCompleted && !didCompleteTask {
                    Button {
                        completeTask()
                    } label: {
                        Label("할 일도 완료 처리", systemImage: "checkmark.circle.fill")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                    }
                    .buttonStyle(.borderedProminent)
                    .buttonBorderShape(.roundedRectangle(radius: 16))
                    .tint(taskColor)
                }

                Button {
                    dismiss()
                } label: {
                    Text(didCompleteTask ? "닫기" : "그대로 두고 닫기")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                }
                .buttonStyle(.bordered)
                .buttonBorderShape(.roundedRectangle(radius: 16))
            }
        } else {
            HStack(spacing: 12) {
                Button {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    withAnimation(LockTodoMotion.snappy) { isRunning.toggle() }
                } label: {
                    HStack(spacing: 7) {
                        Image(systemName: isRunning ? "pause.fill" : "play.fill")
                            .contentTransition(.symbolEffect(.replace))
                        Text(isRunning ? "일시정지" : elapsedSeconds > 0 ? "이어서" : "시작")
                    }
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.roundedRectangle(radius: 16))
                .tint(taskColor)

                if elapsedSeconds > 0 {
                    Button {
                        reset()
                    } label: {
                        Text("초기화")
                            .font(.headline)
                            .frame(width: 96)
                            .padding(.vertical, 16)
                    }
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.roundedRectangle(radius: 16))
                    .tint(.red)
                    .transition(.opacity.combined(with: .scale(scale: 0.9)))
                }
            }
            .lockTodoAnimation(LockTodoMotion.snappy, value: elapsedSeconds > 0)
        }
    }

    // MARK: Logic

    private func tick() {
        guard isRunning, !isFinished else { return }
        if secondsRemaining > 1 {
            secondsRemaining -= 1
        } else {
            secondsRemaining = 0
            finish()
        }
    }

    private func finish() {
        isRunning = false
        isFinished = true
        logSessionIfNeeded(fully: true)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    private func reset() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        // Reset abandons the current attempt — log whatever focus happened.
        logSessionIfNeeded()
        withAnimation(LockTodoMotion.snappy) {
            isRunning = false
            secondsRemaining = totalSeconds
        }
    }

    private func completeTask() {
        didCompleteTask = true
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        withAnimation(LockTodoMotion.snappy) {
            viewModel.toggle(task, context: modelContext)
        }
    }

    /// Records the session once. Only counts sessions with at least a minute of
    /// real focus so idle opens don't pollute the stats.
    private func logSessionIfNeeded(fully: Bool = false) {
        guard !logged else { return }
        let focused = fully ? totalSeconds : elapsedSeconds
        guard focused >= 60 else { return }
        logged = true

        let session = FocusSession(
            taskID: task.id,
            taskTitle: task.title,
            targetMinutes: targetMinutes,
            focusedSeconds: focused,
            completedFully: fully,
            colorHex: task.safeColorHex
        )
        modelContext.insert(session)
        try? modelContext.save()
    }
}
