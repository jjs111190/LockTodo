import SwiftUI

struct CalendarDayCell: View {
    var date: Date?
    var count: Int
    var completionRate: Double
    var isToday: Bool
    var isSelected: Bool

    var body: some View {
        Group {
            if let date {
                VStack(spacing: 4) {
                    Text("\(Calendar.current.component(.day, from: date))")
                        .font(.system(size: 16, weight: weight))
                        .monospacedDigit()
                        .foregroundStyle(numberColor)
                        .frame(width: 32, height: 32)
                        .background {
                            // Selection is a filled disc; today is the same
                            // disc drawn as an outline. Same shape, same place,
                            // different emphasis — so the two never read as
                            // unrelated decorations.
                            ZStack {
                                Circle()
                                    .fill(Color.accentColor)
                                    .opacity(isSelected ? 1 : 0)
                                    .scaleEffect(isSelected ? 1 : 0.7)

                                if isToday && !isSelected {
                                    Circle()
                                        .strokeBorder(Color.accentColor.opacity(0.45), lineWidth: 1.5)
                                }
                            }
                        }
                        .lockTodoAnimation(LockTodoMotion.snappy, value: isSelected)

                    indicators
                        .frame(height: 5)
                }
                .frame(maxWidth: .infinity, minHeight: 54)
                .contentShape(Rectangle())
                .accessibilityLabel(date.formatted(date: .abbreviated, time: .omitted))
                .accessibilityValue(count == 0 ? "할 일 없음" : "\(count)개")
            } else {
                Color.clear
                    .frame(maxWidth: .infinity, minHeight: 54)
            }
        }
    }

    private var weight: Font.Weight {
        if isSelected { return .semibold }
        return isToday ? .semibold : .regular
    }

    private var numberColor: Color {
        if isSelected { return .white }
        return isToday ? .accentColor : .primary
    }

    /// A day with work shows one dot; a busy day shows a second. Density is
    /// carried by the dots rather than by a number crowding the date.
    @ViewBuilder
    private var indicators: some View {
        HStack(spacing: 3) {
            if count > 0 {
                Circle()
                    .fill(completionRate >= 1 ? Color.green : (isSelected ? Color.accentColor : Color.accentColor.opacity(0.85)))
                    .frame(width: 5, height: 5)

                if count > 2 {
                    Circle()
                        .fill(Color.secondary.opacity(0.35))
                        .frame(width: 5, height: 5)
                }
            }
        }
    }
}
