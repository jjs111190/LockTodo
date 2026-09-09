import SwiftUI
import SwiftData

struct MemoryCapsuleCard: View {
    var entry: DiaryEntry
    
    private var daysAgoText: String {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        let entryDate = calendar.startOfDay(for: entry.date)
        let diff = calendar.dateComponents([.day], from: entryDate, to: today).day ?? 0
        
        if diff == 365 {
            return "1년 전 오늘의 기억"
        } else if diff == 30 {
            return "30일 전 오늘의 기억"
        } else {
            return "\(diff)일 전 오늘의 기억"
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Label(daysAgoText, systemImage: "clock.arrow.2.circlepath")
                    .font(.footnote.weight(.semibold))
                    .tracking(0.1)
                    // Type over a coloured surface needs more contrast and a
                    // touch more weight than the same type on a plain page.
                    .foregroundStyle(.white.opacity(0.92))

                Spacer(minLength: 0)

                Text(entry.moodRawValue)
                    .font(.system(size: 15))
                    .frame(width: 28, height: 28)
                    .background(.white.opacity(0.22), in: Circle())
            }

            Text("“\(entry.content)”")
                .font(.system(size: 18, weight: .medium, design: .serif))
                .tracking(-0.2)
                .lineSpacing(3)
                .foregroundStyle(.white)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.vertical, 2)

            Rectangle()
                .fill(.white.opacity(0.28))
                .frame(height: 0.5)

            HStack {
                Text(entry.date.formatted(.dateTime.year().month().day()))
                    .monospacedDigit()

                Spacer()

                Text("완료한 일: \(entry.completedTaskCount)/\(entry.totalTaskCount)")
                    .monospacedDigit()
            }
            .font(.caption)
            .tracking(0.1)
            .foregroundStyle(.white.opacity(0.8))
        }
        .padding(18)
        .background {
            RoundedRectangle(cornerRadius: LockTodoDesign.cardRadius, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(hex: "#FF7B92"),
                            Color(hex: "#FF5E62"),
                            Color(hex: "#FF9966")
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        }
        .overlay {
            RoundedRectangle(cornerRadius: LockTodoDesign.cardRadius, style: .continuous)
                .strokeBorder(Color.white.opacity(0.18), lineWidth: LockTodoDesign.hairline)
        }
        // The shadow is tinted with the card's own colour so the light looks
        // like it came off this object rather than a generic grey drop.
        .shadow(color: Color(hex: "#FF5E62").opacity(0.28), radius: 18, x: 0, y: 8)
    }
}

