import SwiftUI
import UIKit

struct CaptureCompleteView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hasAppeared = false

    var body: some View {
        ZStack {
            LockTodoDesign.pageBackground
                .ignoresSafeArea()

            VStack(spacing: 20) {
                ZStack {
                    // The ring stays put while the mark lands inside it, so the
                    // eye has a fixed frame to read the arrival against.
                    Circle()
                        .stroke(Color.accentColor.opacity(0.16), lineWidth: 4)
                        .frame(width: 88, height: 88)

                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 88, weight: .semibold))
                        .foregroundStyle(Color.accentColor)
                        .scaleEffect(hasAppeared ? 1.0 : 0.6)
                        .opacity(hasAppeared ? 1 : 0)
                }

                VStack(spacing: 6) {
                    Text("저장 완료")
                        .font(.system(size: 24, weight: .semibold))
                        .tracking(-0.5)
                        .foregroundStyle(.primary)

                    Text("할 일을 신속하게 기록했습니다.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .opacity(hasAppeared ? 1 : 0)
            }
            .padding(36)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.06), lineWidth: LockTodoDesign.hairline)
            }
            .shadow(color: .black.opacity(0.10), radius: 30, x: 0, y: 14)
        }
        .onAppear {
            // Visual, haptic and the moment of confirmation all land together —
            // a lag between them is what breaks the sense of one event.
            let generator = UINotificationFeedbackGenerator()
            generator.prepare()
            generator.notificationOccurred(.success)

            // A success confirmation is the right place for a little overshoot:
            // it reads as something arriving with weight.
            withAnimation(reduceMotion ? .easeOut(duration: 0.2) : LockTodoMotion.momentum) {
                hasAppeared = true
            }
        }
    }
}

#Preview {
    CaptureCompleteView()
}
