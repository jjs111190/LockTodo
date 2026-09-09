import SwiftUI

struct WidgetPreviewView: View {
    private let summary = TaskSummarySnapshot.sample

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 18) {
                Text("Lock Screen Controls")
                    .font(.headline)
                controlsPreview

                Text("Inline")
                    .font(.headline)
                inlinePreview

                Text("Circular")
                    .font(.headline)
                circularPreview

                Text("Rectangular")
                    .font(.headline)
                rectangularPreview
            }
            .padding()
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle("위젯 미리보기")
    }

    private var controlsPreview: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 16) {
                LockScreenControlPreviewButton(title: "빠른 입력", systemImage: "checklist.checked", isPrimary: true)
                LockScreenControlPreviewButton(title: "오늘 보기", systemImage: "list.bullet.circle", isPrimary: false)
                LockScreenControlPreviewButton(title: "집중", systemImage: "scope", isPrimary: false)
            }

            Text("iOS 18 이상 잠금화면 사용자화에서 손전등/카메라 자리에 선택할 수 있는 LockTodo 컨트롤입니다.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var inlinePreview: some View {
        HStack(spacing: 6) {
            Image(systemName: "checklist")
            Text("오늘 \(summary.remainingCount)개 남음")
        }
        .font(.headline)
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var circularPreview: some View {
        ProgressRing(progress: summary.progress, lineWidth: 7)
            .frame(width: 90, height: 90)
            .padding(18)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var rectangularPreview: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("\(summary.remainingCount)개 남음")
                    .font(.headline)
                Spacer()
                Text(summary.progress, format: .percent.precision(.fractionLength(0)))
                    .font(.caption.weight(.semibold))
                    .monospacedDigit()
            }

            ForEach(summary.importantTasks.prefix(3)) { task in
                HStack(spacing: 6) {
                    Image(systemName: task.isCompleted ? "checkmark.circle.fill" : "circle")
                    Text(task.title)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }
                .font(.caption)
                .foregroundStyle(task.isCompleted ? .secondary : .primary)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

private struct LockScreenControlPreviewButton: View {
    var title: String
    var systemImage: String
    var isPrimary: Bool

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                Circle()
                    .fill(isPrimary ? Color.accentColor.opacity(0.18) : Color(.tertiarySystemGroupedBackground))
                    .frame(width: 52, height: 52)

                Circle()
                    .strokeBorder(isPrimary ? Color.accentColor.opacity(0.35) : Color.primary.opacity(0.10), lineWidth: 1)
                    .frame(width: 52, height: 52)

                Image(systemName: systemImage)
                    .font(.system(size: 19, weight: .semibold, design: .rounded))
                    .foregroundStyle(isPrimary ? Color.accentColor : Color.secondary)
            }

            Text(title)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
    }
}
