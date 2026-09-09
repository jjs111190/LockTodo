import SwiftUI

struct ProgressRing: View {
    var progress: Double
    var lineWidth: CGFloat = 8
    var showsLabel = true

    private var clamped: Double { min(max(progress, 0), 1) }

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.primary.opacity(0.07), lineWidth: lineWidth)

            Circle()
                .trim(from: 0, to: clamped)
                .stroke(.tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                // The ring fills like a dial being turned, not like a value
                // being teleported — the motion is what makes progress legible.
                .lockTodoAnimation(LockTodoMotion.standard, value: clamped)

            if showsLabel {
                Text(clamped, format: .percent.precision(.fractionLength(0)))
                    .font(.caption.weight(.semibold))
                    .monospacedDigit()
                    .tracking(-0.2)
                    .minimumScaleFactor(0.7)
                    .contentTransition(.numericText(value: clamped))
            }
        }
        .accessibilityLabel("완료율")
        .accessibilityValue(Text("\(Int(clamped * 100))%"))
    }
}

#Preview {
    ProgressRing(progress: 0.64)
        .frame(width: 72, height: 72)
        .padding()
}
