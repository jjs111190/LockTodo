import SwiftUI
import SwiftData
import AVFoundation

struct HabitFocusTimerView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    var habit: Habit
    
    // Timer states: 25 minutes = 1500 seconds. For testing or real use, we set it.
    @State private var timeRemaining = 1500
    @State private var isRunning = false
    @State private var totalTime = 1500
    @State private var timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    @State private var isFinished = false
    
    private var minutesText: String {
        let mins = timeRemaining / 60
        return String(format: "%02d", mins)
    }
    
    private var secondsText: String {
        let secs = timeRemaining % 60
        return String(format: "%02d", secs)
    }
    
    private var progress: Double {
        Double(totalTime - timeRemaining) / Double(totalTime)
    }
    
    var body: some View {
        VStack(spacing: 24) {
            // Header
            HStack {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                
                Spacer()
                
                Text("\(habit.title) 집중")
                    .font(.system(size: 17, weight: .semibold))
                    .tracking(-0.3)
                    .lineLimit(1)
                
                Spacer()
                
                // Invisible spacer for balance
                Image(systemName: "xmark.circle.fill")
                    .font(.title2)
                    .opacity(0)
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            
            Spacer()

            Text(isFinished ? "집중을 끝냈어요" : isRunning ? "집중하는 중" : "집중할 준비가 되었나요?")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .contentTransition(.opacity)
                .padding(.bottom, 20)

            // Timer Ring
            ZStack {
                Circle()
                    .stroke(Color(hex: habit.colorHex).opacity(0.12), lineWidth: 16)
                    .frame(width: 240, height: 240)
                
                Circle()
                    .trim(from: 0, to: CGFloat(min(1.0, max(0.0, 1.0 - progress))))
                    .stroke(
                        Color(hex: habit.colorHex),
                        style: StrokeStyle(lineWidth: 16, lineCap: .round)
                    )
                    .frame(width: 240, height: 240)
                    .rotationEffect(.degrees(-90))
                    .animation(.linear(duration: 1.0), value: timeRemaining)
                
                VStack(spacing: 2) {
                    // Big numerals want *less* weight and negative tracking,
                    // not more: at 56pt a heavy face reads as shouting, and
                    // default spacing looks slack.
                    HStack(spacing: 0) {
                        Text(minutesText)
                        Text(":")
                        Text(secondsText)
                    }
                    .font(.system(size: 56, weight: .light, design: .rounded))
                    .tracking(-1.5)
                    .monospacedDigit()
                    .foregroundStyle(.primary)

                    Text("뽀모도로")
                        .font(.caption)
                        .tracking(0.3)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 20)
            
            Spacer()
            
            // Fast Forward Button (Only for debugging/testing so user can skip wait)
            #if DEBUG
            Button("2초 남기기 (디버그)") {
                timeRemaining = 2
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .buttonStyle(.bordered)
            #endif
            
            // Controls
            HStack(spacing: 24) {
                if isFinished {
                    Button {
                        dismiss()
                    } label: {
                        Text("목록으로 돌아가기")
                            .font(.system(size: 17, weight: .semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                    }
                    .buttonStyle(.borderedProminent)
                    .buttonBorderShape(.capsule)
                    .tint(Color(hex: habit.colorHex))
                } else {
                    Button {
                        isRunning.toggle()
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    } label: {
                        HStack(spacing: 7) {
                            Image(systemName: isRunning ? "pause.fill" : "play.fill")
                                .contentTransition(.symbolEffect(.replace))
                            Text(isRunning ? "일시정지" : "시작")
                        }
                        .font(.system(size: 17, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                    }
                    .buttonStyle(.borderedProminent)
                    .buttonBorderShape(.capsule)
                    .tint(Color(hex: habit.colorHex))

                    if isRunning || timeRemaining < totalTime {
                        Button {
                            resetTimer()
                        } label: {
                            Text("초기화")
                                .font(.system(size: 17, weight: .semibold))
                                .frame(width: 96)
                                .padding(.vertical, 16)
                        }
                        .buttonStyle(.bordered)
                        .buttonBorderShape(.capsule)
                        .tint(.red)
                        .transition(.opacity.combined(with: .scale(scale: 0.9)))
                    }
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 32)
            .lockTodoAnimation(LockTodoMotion.snappy, value: isRunning)
        }
        .onReceive(timer) { _ in
            guard isRunning else { return }
            if timeRemaining > 0 {
                timeRemaining -= 1
            } else {
                completeFocus()
            }
        }
        .onAppear {
            UIApplication.shared.isIdleTimerDisabled = true
        }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false
        }
    }
    
    private func resetTimer() {
        isRunning = false
        timeRemaining = totalTime
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }
    
    private func completeFocus() {
        isRunning = false
        isFinished = true
        
        // Complete habit today
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        let habitID = habit.id
        
        // Find today's record
        let recordDescriptor = FetchDescriptor<HabitRecord>()
        if let records = try? modelContext.fetch(recordDescriptor) {
            if let record = records.first(where: { $0.habitID == habitID && calendar.isDate($0.date, inSameDayAs: today) }) {
                record.isCompleted = true
                habit.registerCompletionToday()
            }
        }
        
        // Sound and Haptics
        AudioServicesPlaySystemSound(1025)
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)
    }
}

