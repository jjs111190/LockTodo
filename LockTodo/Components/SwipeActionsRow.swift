import SwiftUI
import UIKit

/// One revealable action behind a swiped row (trailing side).
struct SwipeAction: Identifiable {
    let id = UUID()
    var systemImage: String
    var tint: Color
    /// Destructive trailing actions can fire on a full-length swipe.
    var isDestructive: Bool = false
    var accessibilityLabel: String
    var action: () -> Void
}

/// A task row with two distinct gestures, both built on the fluid-interface
/// principles (1:1 tracking, rubber-banding, momentum, interruptibility):
///
/// - **Leading (slide-to-complete):** drag the whole row right and it fills with
///   green like a "slide to unlock" track. Past the threshold it commits on
///   release and the row slides away completed; short of it, it springs back.
/// - **Trailing (reveal actions):** drag left to reveal important/delete; a full
///   swipe fires the destructive action.
struct SwipeActionsRow<Content: View>: View {
    /// The leading slide-to-complete action. `nil` disables the left gesture
    /// (e.g. already-completed rows).
    var slideToComplete: SwipeAction?
    var trailing: [SwipeAction]
    @ViewBuilder var content: () -> Content

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var offset: CGFloat = 0
    @GestureState private var isDragging = false
    @State private var startOffset: CGFloat = 0
    @State private var crossedThreshold = false

    private let actionWidth: CGFloat = 74
    /// How far right you must slide to commit a completion.
    private let completeThreshold: CGFloat = 128
    /// Rubber-band ceilings.
    private let maxLeading: CGFloat = 260
    private var trailingWidth: CGFloat { CGFloat(trailing.count) * actionWidth }

    private var committed: Bool { slideToComplete != nil && offset >= completeThreshold }

    var body: some View {
        ZStack {
            background
            content()
                .background(LockTodoDesign.cardBackground)
                .offset(x: offset)
                .overlay {
                    // A tap while a tray is open closes it rather than falling
                    // through to the row's own tap.
                    if offset != 0 {
                        Color.clear.contentShape(Rectangle()).onTapGesture { close() }
                    }
                }
                .gesture(dragGesture)
        }
        .clipped()
        .lockTodoAnimation(isDragging ? LockTodoMotion.snappy : LockTodoMotion.momentum, value: offset)
    }

    // MARK: Backgrounds

    @ViewBuilder
    private var background: some View {
        if offset > 0, let action = slideToComplete {
            completeFill(action)
        } else if offset < 0, !trailing.isEmpty {
            trailingTray
        }
    }

    /// The green "slide to complete" track, revealed to the left of the row as
    /// it slides right. Brightens and changes its label once past the commit
    /// point so the outcome is obvious before you let go.
    private func completeFill(_ action: SwipeAction) -> some View {
        HStack(spacing: 0) {
            ZStack(alignment: .trailing) {
                LinearGradient(
                    colors: committed
                        ? [Color(hex: "#34C759"), Color(hex: "#248A3D")]
                        : [Color(hex: "#34C759").opacity(0.85), Color(hex: "#34C759").opacity(0.6)],
                    startPoint: .leading, endPoint: .trailing
                )

                HStack(spacing: 8) {
                    Image(systemName: committed ? "checkmark.circle.fill" : action.systemImage)
                        .font(.system(size: committed ? 20 : 17, weight: .bold))
                        .scaleEffect(committed ? 1.05 : 1)
                    Text(committed ? "놓으면 완료" : "밀어서 완료")
                        .font(.subheadline.weight(.semibold))
                        .fixedSize()
                }
                .foregroundStyle(.white)
                .padding(.trailing, 18)
                .lockTodoAnimation(LockTodoMotion.snappy, value: committed)
            }
            .frame(width: max(offset, 0))

            Spacer(minLength: 0)
        }
    }

    private var trailingTray: some View {
        GeometryReader { proxy in
            let fullSwipe = -offset > proxy.size.width * 0.55
            HStack(spacing: 0) {
                Spacer(minLength: 0)
                HStack(spacing: 0) {
                    ForEach(Array(trailing.enumerated()), id: \.element.id) { index, action in
                        let isCommitting = fullSwipe && index == 0
                        Button {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            close()
                            action.action()
                        } label: {
                            Image(systemName: action.systemImage)
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .background(action.tint)
                        }
                        .buttonStyle(.plain)
                        .frame(width: isCommitting ? max(-offset, actionWidth) : actionWidth)
                        .accessibilityLabel(action.accessibilityLabel)
                    }
                }
                .frame(width: max(-offset, trailingWidth))
                .frame(maxHeight: .infinity)
            }
        }
    }

    // MARK: Gesture

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 14, coordinateSpace: .local)
            .updating($isDragging) { _, state, _ in state = true }
            .onChanged { value in
                if startOffset == 0 && offset != 0 { startOffset = offset }
                let raw = startOffset + value.translation.width
                offset = rubberBanded(raw)

                // Tick as the completion threshold is crossed, so the commit
                // point is felt, not just seen.
                if slideToComplete != nil {
                    let nowCommitted = offset >= completeThreshold
                    if nowCommitted != crossedThreshold {
                        crossedThreshold = nowCommitted
                        UIImpactFeedbackGenerator(style: nowCommitted ? .medium : .light).impactOccurred()
                    }
                }
            }
            .onEnded { value in
                defer { crossedThreshold = false }

                if offset > 0 {
                    if slideToComplete != nil && offset >= completeThreshold {
                        commitComplete()
                    } else {
                        close()
                    }
                    return
                }

                if offset < 0, !trailing.isEmpty {
                    let width = UIScreen.main.bounds.width
                    let projected = offset + project(value.velocity.width)
                    if let destructive = trailing.first(where: { $0.isDestructive }),
                       -projected > width * 0.55 {
                        commitFullSwipe(destructive)
                    } else {
                        settleTrailing(open: -projected > trailingWidth / 2)
                    }
                    return
                }

                close()
            }
    }

    // Apple's momentum-projection function (where a flick coasts to rest).
    private func project(_ velocity: CGFloat, decelerationRate: CGFloat = 0.998) -> CGFloat {
        (velocity / 1000) * decelerationRate / (1 - decelerationRate)
    }

    private func rubberBanded(_ value: CGFloat) -> CGFloat {
        if value >= 0 {
            guard slideToComplete != nil else { return rubber(value, dim: 60) * 0.4 }
            return value <= maxLeading ? value : maxLeading + rubber(value - maxLeading, dim: 140)
        } else {
            let magnitude = -value
            guard !trailing.isEmpty else { return -rubber(magnitude, dim: 60) * 0.4 }
            return magnitude <= trailingWidth ? value : -(trailingWidth + rubber(magnitude - trailingWidth, dim: 140))
        }
    }

    private func rubber(_ overshoot: CGFloat, dim: CGFloat, constant: CGFloat = 0.55) -> CGFloat {
        (overshoot * dim * constant) / (dim + constant * overshoot)
    }

    // MARK: Commit / settle

    private func commitComplete() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        // Fill the whole row green and slide it away, then run the action —
        // the row itself will drop from the active list once completed.
        withAnimation(reduceMotion ? .easeOut(duration: 0.2) : LockTodoMotion.standard) {
            offset = UIScreen.main.bounds.width
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
            slideToComplete?.action()
            offset = 0
            startOffset = 0
        }
    }

    private func commitFullSwipe(_ action: SwipeAction) {
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
        withAnimation(reduceMotion ? .easeOut(duration: 0.2) : LockTodoMotion.standard) {
            offset = -UIScreen.main.bounds.width
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
            action.action()
            offset = 0
            startOffset = 0
        }
    }

    private func settleTrailing(open: Bool) {
        withAnimation(reduceMotion ? .easeOut(duration: 0.2) : LockTodoMotion.momentum) {
            offset = open ? -trailingWidth : 0
        }
        startOffset = open ? -trailingWidth : 0
        if open { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
    }

    private func close() {
        withAnimation(reduceMotion ? .easeOut(duration: 0.2) : LockTodoMotion.momentum) {
            offset = 0
        }
        startOffset = 0
    }
}
