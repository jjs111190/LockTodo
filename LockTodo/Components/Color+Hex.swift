import SwiftUI

// MARK: - Design tokens

enum LockTodoDesign {
    // Layout — everything sits on a 4pt grid so nothing is ever "almost" aligned.
    static let pageInset: CGFloat = 16
    static let sectionSpacing: CGFloat = 14
    static let stackSpacing: CGFloat = 10

    // Radii — concentric. A tile inset inside a card uses the next step down so
    // the curves stay visually parallel instead of fighting each other.
    static let cardRadius: CGFloat = 20
    static let tileRadius: CGFloat = 13
    static let controlRadius: CGFloat = 10
    static let chipRadius: CGFloat = 8

    // Surfaces
    static let pageBackground = Color(uiColor: .systemGroupedBackground)
    static let cardBackground = Color(uiColor: .secondarySystemGroupedBackground)
    static let insetBackground = Color(uiColor: .tertiarySystemGroupedBackground)
    static let separator = Color(uiColor: .separator).opacity(0.22)

    /// Hairline. 0.5pt reads as one physical pixel on 2x, a half on 3x — the
    /// same weight UIKit uses for its own separators.
    static let hairline: CGFloat = 0.5
}

// MARK: - Motion

/// Apple describes springs with two numbers: *response* (how quickly the value
/// reaches the target) and *damping* (how much it overshoots). SwiftUI's
/// `response` / `dampingFraction` map onto them directly, so the values below
/// are the ones Apple ships for the equivalent interactions.
enum LockTodoMotion {
    /// Default for anything that simply moves or changes state. Critically
    /// damped — graceful, never distracting.
    static let standard = Animation.spring(response: 0.4, dampingFraction: 1.0)

    /// Immediate feedback: presses, toggles, selection. Fast enough to feel
    /// like a direct consequence of the touch.
    static let snappy = Animation.spring(response: 0.26, dampingFraction: 1.0)

    /// Sheets, drawers, expanding sections — a hint of overshoot because the
    /// surface is arriving with momentum.
    static let sheet = Animation.spring(response: 0.32, dampingFraction: 0.82)

    /// Reserved for motion the user's own gesture set going. Bounce earns its
    /// place only when a flick or drag preceded it.
    static let momentum = Animation.spring(response: 0.4, dampingFraction: 0.78)

    /// Content appearing/disappearing in place.
    static let content = Animation.spring(response: 0.34, dampingFraction: 0.95)
}

extension View {
    /// Applies a spring, degrading to a short cross-fade when the user has
    /// asked for reduced motion — gentler feedback, not *no* feedback.
    func lockTodoAnimation<V: Equatable>(_ animation: Animation, value: V) -> some View {
        modifier(LockTodoAnimationModifier(animation: animation, value: value))
    }
}

private struct LockTodoAnimationModifier<V: Equatable>: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var animation: Animation
    var value: V

    func body(content: Content) -> some View {
        content.animation(reduceMotion ? .easeOut(duration: 0.18) : animation, value: value)
    }
}

// MARK: - Typography

/// Tracking is size-specific: large text reads too loose at default spacing and
/// wants negative tracking, small text wants a touch more air. One fixed value
/// is always wrong somewhere.
extension View {
    /// Card and section headings.
    func lockTodoTitle() -> some View {
        font(.system(.title3, design: .default, weight: .semibold))
            .tracking(-0.4)
    }

    /// The label above a group of rows.
    func lockTodoSectionTitle() -> some View {
        font(.system(size: 15, weight: .semibold))
            .tracking(-0.2)
    }

    /// Supporting copy under a title.
    func lockTodoSubheadline() -> some View {
        font(.subheadline)
            .tracking(0)
            .foregroundStyle(.secondary)
    }

    /// Metadata, badges, counts.
    func lockTodoCaption() -> some View {
        font(.caption)
            .tracking(0.1)
            .foregroundStyle(.secondary)
    }
}

// MARK: - Surfaces

/// How much a surface lifts off the page. Shadows carry the separation in light
/// mode; in dark mode the fill difference and hairline do the work, because a
/// black shadow on a near-black page is invisible.
enum LockTodoElevation {
    case flat
    case raised
    case floating
}

struct LockTodoCardModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    var radius: CGFloat
    var elevation: LockTodoElevation

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)

        content
            .background(LockTodoDesign.cardBackground, in: shape)
            .overlay {
                shape.strokeBorder(LockTodoDesign.separator, lineWidth: LockTodoDesign.hairline)
            }
            .compositingGroup()
            .shadow(color: ambientShadow, radius: ambientRadius, x: 0, y: ambientOffset)
            .shadow(color: keyShadow, radius: keyRadius, x: 0, y: keyOffset)
    }

    // A large diffuse shadow reads as ambient light; a small tight one anchors
    // the surface to the page. Together they look like a real object rather
    // than a rectangle with a blur behind it.
    private var isDark: Bool { colorScheme == .dark }

    private var ambientShadow: Color {
        guard !isDark else { return .clear }
        switch elevation {
        case .flat: return .clear
        case .raised: return Color.black.opacity(0.045)
        case .floating: return Color.black.opacity(0.08)
        }
    }

    private var keyShadow: Color {
        guard !isDark else { return .clear }
        switch elevation {
        case .flat: return .clear
        case .raised: return Color.black.opacity(0.03)
        case .floating: return Color.black.opacity(0.05)
        }
    }

    private var ambientRadius: CGFloat {
        switch elevation {
        case .flat: return 0
        case .raised: return 14
        case .floating: return 24
        }
    }

    private var keyRadius: CGFloat {
        switch elevation {
        case .flat: return 0
        case .raised: return 2
        case .floating: return 4
        }
    }

    private var ambientOffset: CGFloat {
        switch elevation {
        case .flat: return 0
        case .raised: return 6
        case .floating: return 12
        }
    }

    private var keyOffset: CGFloat {
        switch elevation {
        case .flat: return 0
        case .raised: return 1
        case .floating: return 2
        }
    }
}

/// A tile nested *inside* a card. Uses the recessed fill rather than another
/// card surface, so the hierarchy stays legible instead of stacking two
/// identical planes.
struct LockTodoTileModifier: ViewModifier {
    var radius: CGFloat

    func body(content: Content) -> some View {
        content
            .background(
                LockTodoDesign.insetBackground,
                in: RoundedRectangle(cornerRadius: radius, style: .continuous)
            )
    }
}

extension View {
    func lockTodoCard(
        radius: CGFloat = LockTodoDesign.cardRadius,
        elevation: LockTodoElevation = .raised
    ) -> some View {
        modifier(LockTodoCardModifier(radius: radius, elevation: elevation))
    }

    func lockTodoTile(radius: CGFloat = LockTodoDesign.tileRadius) -> some View {
        modifier(LockTodoTileModifier(radius: radius))
    }

    func tutorialHighlightAnchor(_ target: TutorialHighlightTarget) -> some View {
        anchorPreference(key: TutorialHighlightPreferenceKey.self, value: .bounds) {
            [target: $0]
        }
    }
}

// MARK: - Card header

/// Nearly every card in the app opens with an icon, a title, a line of
/// support copy and a count. Defining it once means those four things are
/// always the same size, the same weight and the same distance apart — which
/// is what lets someone learn the layout on one card and read every other one
/// at a glance.
struct LockTodoCardHeader<Trailing: View>: View {
    var title: String
    var subtitle: String?
    var systemImage: String
    var tint: Color = .accentColor
    /// Filled icons read as the card's identity; tinted ones sit quieter and
    /// are right for supporting sections.
    var isIconFilled = true
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(spacing: 11) {
            Image(systemName: systemImage)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(isIconFilled ? .white : tint)
                .frame(width: 32, height: 32)
                .background(isIconFilled ? tint : tint.opacity(0.12), in: Circle())

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .tracking(-0.2)
                    .foregroundStyle(.primary)

                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 8)

            trailing()
        }
    }
}

extension LockTodoCardHeader where Trailing == EmptyView {
    init(
        title: String,
        subtitle: String? = nil,
        systemImage: String,
        tint: Color = .accentColor,
        isIconFilled: Bool = true
    ) {
        self.init(
            title: title,
            subtitle: subtitle,
            systemImage: systemImage,
            tint: tint,
            isIconFilled: isIconFilled,
            trailing: { EmptyView() }
        )
    }
}

/// The count pill that sits at the trailing edge of a card header.
struct LockTodoCountBadge: View {
    var text: String
    var tint: Color = .accentColor

    var body: some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .monospacedDigit()
            .foregroundStyle(tint)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(tint.opacity(0.12), in: Capsule())
    }
}

// MARK: - Tutorial anchors

enum TutorialHighlightTarget: Hashable {
    case overview
    case addTask
    case pin
}

struct TutorialHighlightPreferenceKey: PreferenceKey {
    static var defaultValue: [TutorialHighlightTarget: Anchor<CGRect>] = [:]

    static func reduce(
        value: inout [TutorialHighlightTarget: Anchor<CGRect>],
        nextValue: () -> [TutorialHighlightTarget: Anchor<CGRect>]
    ) {
        value.merge(nextValue(), uniquingKeysWith: { _, latest in latest })
    }
}

// MARK: - Color

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (1, 1, 1, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}
