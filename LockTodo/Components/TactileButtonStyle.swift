import SwiftUI

/// Feedback lives on the *press*, not the release. The moment lag appears the
/// sense of directness falls off a cliff, so the scale change starts on
/// touch-down and springs back on lift — and because it's a spring, a fast
/// double-press stays continuous instead of snapping between states.
struct TactileButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// How far the control sinks under the finger. Small controls need a
    /// proportionally larger change to register at all.
    var pressedScale: CGFloat = 0.96

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(reduceMotion ? 1.0 : (configuration.isPressed ? pressedScale : 1.0))
            .opacity(configuration.isPressed ? 0.72 : 1.0)
            .animation(
                reduceMotion ? .easeOut(duration: 0.12) : LockTodoMotion.snappy,
                value: configuration.isPressed
            )
    }
}

/// For surfaces rather than controls — cards, rows, banners. The whole plate
/// dips slightly, which reads as pressing an object rather than a button.
struct LockTodoSurfaceButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(reduceMotion ? 1.0 : (configuration.isPressed ? 0.985 : 1.0))
            .brightness(configuration.isPressed ? -0.025 : 0)
            .animation(
                reduceMotion ? .easeOut(duration: 0.12) : LockTodoMotion.snappy,
                value: configuration.isPressed
            )
    }
}

extension ButtonStyle where Self == LockTodoSurfaceButtonStyle {
    static var lockTodoSurface: LockTodoSurfaceButtonStyle { LockTodoSurfaceButtonStyle() }
}

extension ButtonStyle where Self == TactileButtonStyle {
    static var tactile: TactileButtonStyle { TactileButtonStyle() }
}
