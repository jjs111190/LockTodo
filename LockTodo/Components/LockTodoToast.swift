import SwiftUI
import UIKit

/// A transient message that can carry a single undo action — the app's answer
/// to Apple's "forgiveness" principle: a slip (a swipe-delete, a bulk clear)
/// should be a quiet, reversible nudge, not a modal confirmation for every act.
struct LockTodoToastState: Equatable {
    var message: String
    var systemImage: String
    /// Present only when the action can be taken back.
    var undoTitle: String?

    static func == (lhs: LockTodoToastState, rhs: LockTodoToastState) -> Bool {
        lhs.message == rhs.message && lhs.systemImage == rhs.systemImage && lhs.undoTitle == rhs.undoTitle
    }
}

@MainActor
final class LockTodoToastCenter: ObservableObject {
    @Published private(set) var state: LockTodoToastState?
    private var onUndo: (() -> Void)?
    private var dismissTask: Task<Void, Never>?

    /// Show a toast. If `onUndo` is provided the toast offers an undo button and
    /// stays a beat longer so the action is genuinely reachable.
    func show(
        _ message: String,
        systemImage: String = "checkmark.circle.fill",
        undoTitle: String? = nil,
        duration: TimeInterval = 3.2,
        onUndo: (() -> Void)? = nil
    ) {
        self.onUndo = onUndo
        withAnimation(LockTodoMotion.sheet) {
            state = LockTodoToastState(message: message, systemImage: systemImage, undoTitle: onUndo == nil ? nil : undoTitle)
        }

        dismissTask?.cancel()
        dismissTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(onUndo == nil ? duration : duration + 1.5))
            guard !Task.isCancelled else { return }
            self?.dismiss()
        }
    }

    func triggerUndo() {
        UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
        onUndo?()
        onUndo = nil
        dismiss()
    }

    func dismiss() {
        dismissTask?.cancel()
        withAnimation(LockTodoMotion.momentum) {
            state = nil
        }
    }
}

/// The floating pill. Materialises from the bottom with blur + scale so it
/// reads as a real surface arriving, and can be flicked down to dismiss.
struct LockTodoToastOverlay: View {
    @ObservedObject var center: LockTodoToastCenter
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var dragOffset: CGFloat = 0

    /// Height of a standard tab bar plus a small gap, so the toast sits clear
    /// of it. The overlay lives above the whole tab UI at the root.
    private var bottomInset: CGFloat { 64 }

    var body: some View {
        VStack {
            Spacer(minLength: 0)
            if let state = center.state {
                HStack(spacing: 11) {
                    Image(systemName: state.systemImage)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Color.accentColor)

                    Text(state.message)
                        .font(.subheadline.weight(.medium))
                        .tracking(-0.1)
                        .foregroundStyle(.primary)
                        .lineLimit(2)

                    if let undoTitle = state.undoTitle {
                        Spacer(minLength: 8)
                        Button(undoTitle) {
                            center.triggerUndo()
                        }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.accentColor)
                    } else {
                        Spacer(minLength: 0)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 13)
                .frame(maxWidth: .infinity)
                .background(.regularMaterial, in: Capsule())
                .overlay {
                    Capsule().strokeBorder(Color.primary.opacity(0.06), lineWidth: LockTodoDesign.hairline)
                }
                .shadow(color: .black.opacity(0.14), radius: 24, y: 10)
                .padding(.horizontal, LockTodoDesign.pageInset)
                // Clears the tab bar so the pill floats just above it rather
                // than hiding behind the (opaque, UIKit-drawn) bar.
                .padding(.bottom, bottomInset)
                .offset(y: dragOffset)
                .gesture(
                    DragGesture()
                        .onChanged { value in dragOffset = max(0, value.translation.height) }
                        .onEnded { value in
                            if value.translation.height > 40 || value.velocity.height > 400 {
                                center.dismiss()
                            }
                            withAnimation(LockTodoMotion.momentum) { dragOffset = 0 }
                        }
                )
                .transition(
                    reduceMotion
                        ? .opacity
                        : .move(edge: .bottom).combined(with: .opacity)
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .allowsHitTesting(center.state != nil)
    }
}

extension View {
    /// Hosts a toast center as a bottom overlay for the screen.
    func lockTodoToast(_ center: LockTodoToastCenter) -> some View {
        overlay(alignment: .bottom) {
            LockTodoToastOverlay(center: center)
        }
    }
}
