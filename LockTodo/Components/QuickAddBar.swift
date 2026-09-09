import Foundation
import SwiftUI
import SwiftData
import UIKit

struct QuickAddBar: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme
    @FocusState private var isFocused: Bool

    @ObservedObject var viewModel: TaskViewModel
    var allTasks: [TaskItem]
    var category: TaskCategory = .today
    var date: Date? = Calendar.current.startOfDay(for: .now)
    var autoFocus = false
    var prefillTitle: String = ""
    var onAdd: ((TaskItem) -> Void)?

    @State private var title = ""
    @State private var isImportant = false

    private var smartInput: SmartParsedTaskInput {
        SmartTaskInputParser.parse(
            title,
            fallbackCategory: category,
            fallbackDate: date,
            fallbackImportant: isImportant
        )
    }

    private var isEmpty: Bool {
        title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Button {
                    isImportant.toggle()
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                } label: {
                    Image(systemName: isImportant ? "star.fill" : "star")
                        .font(.system(size: 17))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(isImportant ? .yellow : .secondary)
                        .contentTransition(.symbolEffect(.replace))
                        .frame(width: 36, height: 36)
                        .contentShape(Circle())
                }
                .buttonStyle(TactileButtonStyle(pressedScale: 0.86))
                .accessibilityLabel("중요 표시")

                TextField("할 일 추가", text: $title, axis: .vertical)
                    .lineLimit(1...3)
                    .focused($isFocused)
                    .submitLabel(.done)
                    .onSubmit(add)
                    .font(.body)

                Button(action: add) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 27))
                        .symbolRenderingMode(.hierarchical)
                        // The send control fades and shrinks back rather than
                        // switching off, so it never blinks in and out while
                        // typing the first character.
                        .foregroundStyle(isEmpty ? Color.secondary.opacity(0.5) : Color.accentColor)
                        .scaleEffect(isEmpty ? 0.9 : 1)
                        .frame(width: 36, height: 36)
                        .contentShape(Circle())
                }
                .buttonStyle(TactileButtonStyle(pressedScale: 0.88))
                .disabled(isEmpty)
                .lockTodoAnimation(LockTodoMotion.snappy, value: isEmpty)
                .accessibilityLabel("할 일 추가")
            }

            if smartInput.hasDetectedParts {
                SmartTaskParsePreview(parsed: smartInput)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        // Floating chrome is a material with content passing under it, not an
        // opaque plate. The tint keeps it a shade lighter than the page so it
        // still reads as the interactive layer.
        .background {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(.regularMaterial)
                .overlay {
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .fill(Color.white.opacity(colorScheme == .dark ? 0.04 : 0.5))
                }
        }
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.07), lineWidth: LockTodoDesign.hairline)
        }
        .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.4 : 0.09), radius: 20, x: 0, y: 8)
        .lockTodoAnimation(LockTodoMotion.content, value: smartInput.hasDetectedParts)
        .padding(.horizontal, LockTodoDesign.pageInset)
        .padding(.bottom, 8)
        .onAppear {
            if !prefillTitle.isEmpty {
                title = prefillTitle
            }
            if autoFocus {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                    isFocused = true
                }
            }
        }
        .onChange(of: prefillTitle) { _, newValue in
            guard !newValue.isEmpty else { return }
            title = newValue
            isFocused = true
        }
    }

    private func add() {
        withAnimation(.snappy) {
            let parsed = smartInput
            guard let task = viewModel.addTask(
                title: parsed.title,
                category: parsed.category,
                dueDate: parsed.dueDate,
                dueTime: parsed.dueTime,
                tags: parsed.tags,
                isImportant: parsed.isImportant,
                context: modelContext,
                allTasks: allTasks
            ) else {
                return
            }

            title = ""
            isImportant = false
            isFocused = true
            let refreshedTasks = (try? modelContext.fetch(FetchDescriptor<TaskItem>())) ?? allTasks
            viewModel.refreshSharedState(allTasks: refreshedTasks)
            onAdd?(task)
        }
    }
}

struct SmartParsedTaskInput {
    var title: String
    var category: TaskCategory
    var dueDate: Date?
    var dueTime: Date?
    var tags: [String]
    var isImportant: Bool
    var detectedParts: [String]

    var hasDetectedParts: Bool {
        !detectedParts.isEmpty
    }

    var previewParts: [String] {
        detectedParts
    }
}

enum SmartTaskInputParser {
    static func parse(
        _ rawTitle: String,
        fallbackCategory: TaskCategory,
        fallbackDate: Date?,
        fallbackImportant: Bool,
        calendar: Calendar = .current
    ) -> SmartParsedTaskInput {
        let originalTitle = rawTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        var workingTitle = originalTitle
        var detectedParts: [String] = []

        let tags = extractTags(from: workingTitle)
        if !tags.isEmpty {
            workingTitle = removeMatches(pattern: "#[\\p{L}\\p{N}_-]+", from: workingTitle)
            detectedParts.append(contentsOf: tags.map { "#\($0)" })
        }

        let hasImportantMarker = containsMatch(pattern: "(^|\\s)(!+|중요|중요함)(?=\\s|$)", in: workingTitle)
        if hasImportantMarker {
            workingTitle = removeMatches(pattern: "(^|\\s)(!+|중요|중요함)(?=\\s|$)", from: workingTitle)
            detectedParts.append("중요")
        }

        var category = fallbackCategory
        var dueDate = fallbackDate
        if let dateMatch = parseDate(in: workingTitle, calendar: calendar) {
            workingTitle = removeMatches(pattern: dateMatch.pattern, from: workingTitle)
            category = dateMatch.category
            dueDate = dateMatch.date
            detectedParts.append(dateMatch.label)
        }

        var dueTime: Date?
        if let timeMatch = parseTime(in: workingTitle, baseDate: dueDate ?? fallbackDate ?? calendar.startOfDay(for: .now), calendar: calendar) {
            workingTitle = removeMatches(pattern: timeMatch.pattern, from: workingTitle)
            dueTime = timeMatch.time
            if category == .later {
                category = .today
                dueDate = calendar.startOfDay(for: .now)
            }
            detectedParts.append(timeMatch.label)
        }

        let cleanedTitle = normalizeTitle(workingTitle)
        return SmartParsedTaskInput(
            title: cleanedTitle.isEmpty ? originalTitle : cleanedTitle,
            category: category,
            dueDate: category == .later ? nil : dueDate,
            dueTime: category == .later ? nil : dueTime,
            tags: tags,
            isImportant: fallbackImportant || hasImportantMarker,
            detectedParts: detectedParts
        )
    }

    private struct DateMatch {
        var pattern: String
        var category: TaskCategory
        var date: Date?
        var label: String
    }

    private struct TimeMatch {
        var pattern: String
        var time: Date
        var label: String
    }

    private static func parseDate(in title: String, calendar: Calendar) -> DateMatch? {
        let today = calendar.startOfDay(for: .now)
        let keywordMatches: [(String, TaskCategory, Date?, String)] = [
            ("(^|\\s)오늘(?=\\s|$)", .today, today, "오늘"),
            ("(^|\\s)내일(?=\\s|$)", .tomorrow, calendar.date(byAdding: .day, value: 1, to: today), "내일"),
            ("(^|\\s)모레(?=\\s|$)", .scheduled, calendar.date(byAdding: .day, value: 2, to: today), "모레"),
            ("(^|\\s)글피(?=\\s|$)", .scheduled, calendar.date(byAdding: .day, value: 3, to: today), "글피"),
            ("(^|\\s)주말(?=\\s|$)", .scheduled, nextWeekend(from: today, calendar: calendar), "주말"),
            ("(^|\\s)다음\\s*주(?=\\s|$)", .scheduled, calendar.date(byAdding: .day, value: 7, to: today), "다음 주"),
            ("(^|\\s)나중에(?=\\s|$)", .later, nil, "나중에")
        ]

        for match in keywordMatches where containsMatch(pattern: match.0, in: title) {
            return DateMatch(pattern: match.0, category: match.1, date: match.2, label: match.3)
        }

        let weekdays = [
            ("월요일|월욜|월", 2, "월요일"),
            ("화요일|화욜|화", 3, "화요일"),
            ("수요일|수욜|수", 4, "수요일"),
            ("목요일|목욜|목", 5, "목요일"),
            ("금요일|금욜|금", 6, "금요일"),
            ("토요일|토욜|토", 7, "토요일"),
            ("일요일|일욜|일", 1, "일요일")
        ]

        for weekday in weekdays {
            let pattern = "(^|\\s)(\(weekday.0))(?=\\s|$)"
            if containsMatch(pattern: pattern, in: title),
               let date = nextWeekday(weekday.1, from: today, calendar: calendar) {
                return DateMatch(pattern: pattern, category: .scheduled, date: date, label: weekday.2)
            }
        }

        return parseNumericDate(in: title, calendar: calendar)
    }

    private static func parseNumericDate(in title: String, calendar: Calendar) -> DateMatch? {
        let patterns = [
            "(^|\\s)(\\d{1,2})/(\\d{1,2})(?=\\s|$)",
            "(^|\\s)(\\d{1,2})월\\s*(\\d{1,2})일(?=\\s|$)"
        ]

        for pattern in patterns {
            guard let match = firstMatch(pattern: pattern, in: title),
                  match.numberOfRanges >= 4,
                  let monthRange = Range(match.range(at: 2), in: title),
                  let dayRange = Range(match.range(at: 3), in: title),
                  let month = Int(title[monthRange]),
                  let day = Int(title[dayRange]) else {
                continue
            }

            var components = calendar.dateComponents([.year], from: .now)
            components.month = month
            components.day = day
            guard let date = calendar.date(from: components) else { continue }
            let today = calendar.startOfDay(for: .now)
            let resolvedDate = date < today
                ? calendar.date(byAdding: .year, value: 1, to: date) ?? date
                : date
            return DateMatch(pattern: pattern, category: .scheduled, date: resolvedDate, label: "\(month)/\(day)")
        }

        return nil
    }

    private static func parseTime(in title: String, baseDate: Date, calendar: Calendar) -> TimeMatch? {
        let keywordTimes: [(String, Int, Int, String)] = [
            ("(^|\\s)아침(?=\\s|$)", 9, 0, "아침 9:00"),
            ("(^|\\s)점심(?=\\s|$)", 12, 0, "점심 12:00"),
            ("(^|\\s)저녁(?=\\s|$)", 18, 0, "저녁 6:00"),
            ("(^|\\s)밤(?=\\s|$)", 21, 0, "밤 9:00"),
            ("(^|\\s)정오(?=\\s|$)", 12, 0, "정오")
        ]

        for keywordTime in keywordTimes where containsMatch(pattern: keywordTime.0, in: title) {
            if let date = calendar.date(bySettingHour: keywordTime.1, minute: keywordTime.2, second: 0, of: baseDate) {
                return TimeMatch(pattern: keywordTime.0, time: date, label: keywordTime.3)
            }
        }

        let pattern = "(^|\\s)(오전|오후)?\\s*(\\d{1,2})(?:(?::(\\d{2}))|(?:시\\s*(?:(\\d{1,2})분?)?))(?=\\s|$)"
        guard let match = firstMatch(pattern: pattern, in: title),
              match.numberOfRanges >= 6,
              let hourRange = Range(match.range(at: 3), in: title),
              var hour = Int(title[hourRange]) else {
            return nil
        }

        var minute = 0
        if let minuteRange = validRange(match.range(at: 4), in: title) ?? validRange(match.range(at: 5), in: title),
           let parsedMinute = Int(title[minuteRange]) {
            minute = parsedMinute
        }

        guard (0...59).contains(minute), (0...24).contains(hour) else { return nil }

        if let periodRange = validRange(match.range(at: 2), in: title) {
            let period = String(title[periodRange])
            if period == "오후", hour < 12 {
                hour += 12
            } else if period == "오전", hour == 12 {
                hour = 0
            }
        } else if (1...7).contains(hour) {
            hour += 12
        }

        guard let date = calendar.date(bySettingHour: min(hour, 23), minute: minute, second: 0, of: baseDate) else {
            return nil
        }

        let label = date.formatted(date: .omitted, time: .shortened)
        return TimeMatch(pattern: pattern, time: date, label: label)
    }

    private static func extractTags(from title: String) -> [String] {
        matches(pattern: "#([\\p{L}\\p{N}_-]+)", in: title).compactMap { match in
            guard match.numberOfRanges > 1,
                  let range = Range(match.range(at: 1), in: title) else {
                return nil
            }
            return String(title[range]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        .filter { !$0.isEmpty }
    }

    private static func normalizeTitle(_ title: String) -> String {
        title
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: ",.;·")))
    }

    private static func nextWeekend(from date: Date, calendar: Calendar) -> Date? {
        nextWeekday(7, from: date, calendar: calendar)
    }

    private static func nextWeekday(_ targetWeekday: Int, from date: Date, calendar: Calendar) -> Date? {
        let currentWeekday = calendar.component(.weekday, from: date)
        let daysToAdd = (targetWeekday - currentWeekday + 7) % 7
        return calendar.date(byAdding: .day, value: daysToAdd, to: date)
    }

    private static func containsMatch(pattern: String, in text: String) -> Bool {
        firstMatch(pattern: pattern, in: text) != nil
    }

    private static func firstMatch(pattern: String, in text: String) -> NSTextCheckingResult? {
        matches(pattern: pattern, in: text).first
    }

    private static func matches(pattern: String, in text: String) -> [NSTextCheckingResult] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return []
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.matches(in: text, range: range)
    }

    private static func removeMatches(pattern: String, from text: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return text
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.stringByReplacingMatches(in: text, range: range, withTemplate: " ")
    }

    private static func validRange(_ nsRange: NSRange, in text: String) -> Range<String.Index>? {
        guard nsRange.location != NSNotFound else { return nil }
        return Range(nsRange, in: text)
    }
}

struct SmartTaskParsePreview: View {
    var parsed: SmartParsedTaskInput
    var onApply: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 8) {
            Label("자동 해석", systemImage: "wand.and.sparkles")
                .font(.caption2.weight(.semibold))
                .tracking(0.1)
                .foregroundStyle(Color.accentColor)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 5) {
                    ForEach(parsed.previewParts, id: \.self) { part in
                        Text(part)
                            .font(.caption2.weight(.medium))
                            .tracking(0.1)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.primary.opacity(0.06), in: Capsule())
                    }
                }
            }

            if let onApply {
                Button("적용", action: onApply)
                    .font(.caption2.weight(.bold))
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
            }
        }
    }
}
