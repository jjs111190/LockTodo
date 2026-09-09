import AppIntents
import Foundation
import SwiftUI
import SwiftData

struct AddTaskIntent: AppIntent {
    static var title: LocalizedStringResource = "LockTodo 새 할 일 추가"
    static var description = IntentDescription("LockTodo를 열지 않고 오늘 할 일을 바로 저장합니다.")
    static var openAppWhenRun = false
    static var authenticationPolicy: IntentAuthenticationPolicy = .alwaysAllowed

    static var parameterSummary: some ParameterSummary {
        Summary("할 일 \(\.$titleText) 추가") {
            \.$notes
            \.$isImportant
            \.$category
            \.$dueDate
            \.$tagsText
            \.$configureDetails
        }
    }

    @Parameter(title: "할 일", requestValueDialog: "추가할 할 일을 입력하거나 말해주세요.")
    var titleText: String

    @Parameter(title: "메모", default: "")
    var notes: String

    @Parameter(title: "중요 표시 (별)", default: false)
    var isImportant: Bool

    @Parameter(title: "카테고리", default: .today)
    var category: TaskCategory

    @Parameter(title: "기한 (날짜)")
    var dueDate: Date?

    @Parameter(title: "태그 (쉼표 구분)", default: "")
    var tagsText: String

    @Parameter(title: "상세 설정 진행", default: false)
    var configureDetails: Bool

    init() {
        titleText = ""
        notes = ""
        isImportant = false
        category = .today
        dueDate = nil
        tagsText = ""
        configureDetails = false
    }

    init(titleText: String = "", notes: String = "", isImportant: Bool = false, category: TaskCategory = .today, tagsText: String = "", dueDate: Date? = nil, configureDetails: Bool = false) {
        self.titleText = titleText
        self.notes = notes
        self.isImportant = isImportant
        self.category = category
        self.tagsText = tagsText
        self.dueDate = dueDate
        self.configureDetails = configureDetails
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        let isInteractive = titleText.isEmpty
        
        var cleanTitle = titleText.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleanTitle.isEmpty {
            cleanTitle = try await $titleText
                .requestValue("추가할 할 일을 입력하거나 말해주세요.")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }

        guard !cleanTitle.isEmpty else {
            ShortcutService.queueAddTask()
            return .result()
        }

        var finalNotes = notes
        var finalIsImportant = isImportant
        var finalCategory = category
        var finalTagsText = tagsText
        var finalDueDate = dueDate

        if isInteractive {
            let needsDetails = try await $configureDetails.requestValue("메모, 중요도, 카테고리, 태그 등의 상세 설정을 입력하시겠습니까?")
            if needsDetails {
                finalNotes = try await $notes.requestValue("메모를 입력해주세요 (없으면 다음)")
                finalIsImportant = try await $isImportant.requestValue("중요 표시(별)를 활성화할까요?")
                finalCategory = try await $category.requestValue("카테고리를 선택해주세요")
                finalDueDate = try await $dueDate.requestValue("기한 날짜를 선택해주세요 (없으면 다음)")
                finalTagsText = try await $tagsText.requestValue("태그를 입력해주세요 (쉼표 구분, 없으면 다음)")
            }
        }

        try await LockTodoTaskMutationStore.addTask(
            title: cleanTitle,
            notes: finalNotes,
            isImportant: finalIsImportant,
            category: finalCategory,
            tagsText: finalTagsText,
            dueDate: finalDueDate
        )
        return .result()
    }
}

struct StartFocusTaskIntent: AppIntent {
    static var title: LocalizedStringResource = "LockTodo 집중 시작"
    static var description = IntentDescription("LockTodo를 열고 오늘의 집중 항목을 확인합니다.")
    static var openAppWhenRun = true

    func perform() async throws -> some IntentResult & ProvidesDialog {
        ShortcutService.queueStartFocus()
        return .result(dialog: "LockTodo 집중 화면을 엽니다.")
    }
}

struct SmartAddTaskIntent: AppIntent {
    static var title: LocalizedStringResource = "LockTodo 스마트 입력"
    static var description = IntentDescription("날짜, 시간, 중요 표시, 태그를 한 문장으로 해석해서 앱을 열지 않고 저장합니다.")
    static var openAppWhenRun = false
    static var authenticationPolicy: IntentAuthenticationPolicy = .alwaysAllowed

    static var parameterSummary: some ParameterSummary {
        Summary("스마트 입력 \(\.$smartText)")
    }

    @Parameter(title: "스마트 입력", requestValueDialog: "예: 내일 오후 3시 병원 ! #건강")
    var smartText: String

    init() {
        smartText = ""
    }

    init(smartText: String = "") {
        self.smartText = smartText
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        var cleanText = smartText.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleanText.isEmpty {
            cleanText = try await $smartText
                .requestValue("예: 내일 오후 3시 병원 ! #건강")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }

        guard !cleanText.isEmpty else {
            ShortcutService.queueAddTask()
            return .result(dialog: "입력할 내용이 없어 LockTodo 빠른 입력을 준비했습니다.")
        }

        let parsed = ShortcutSmartTaskParser.parse(cleanText)
        try await LockTodoTaskMutationStore.addTask(
            title: parsed.title,
            isImportant: parsed.isImportant,
            category: parsed.category,
            tagsText: parsed.tags.joined(separator: ","),
            dueDate: parsed.dueDate,
            dueTime: parsed.dueTime,
            colorHex: parsed.colorHex
        )

        return .result(dialog: "\(parsed.title)을(를) 추가했습니다\(parsed.dialogSuffix).")
    }
}

struct StartSmartPlanIntent: AppIntent {
    static var title: LocalizedStringResource = "LockTodo 스마트 플랜 시작"
    static var description = IntentDescription("오늘 해야 할 일 중 우선순위가 높은 항목을 골라 잠금화면 카드에 바로 고정합니다.")
    static var openAppWhenRun = false
    static var authenticationPolicy: IntentAuthenticationPolicy = .alwaysAllowed

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let focusTitle = try await LockTodoTaskMutationStore.startSmartPlan()
        if let focusTitle {
            return .result(dialog: "스마트 플랜을 시작했습니다. 지금은 \(focusTitle)에 집중합니다.")
        } else {
            return .result(dialog: "오늘 바로 집중할 할 일이 없습니다.")
        }
    }
}

struct SetLockTodoPatrolIntent: AppIntent {
    static var title: LocalizedStringResource = "LockTodo 잠금화면 순찰"
    static var description = IntentDescription("잠금화면 Live Activity 순찰 카드를 단축어에서 켜거나 끕니다.")
    static var openAppWhenRun = false
    static var authenticationPolicy: IntentAuthenticationPolicy = .alwaysAllowed

    static var parameterSummary: some ParameterSummary {
        Summary("잠금화면 순찰 \(\.$isActive)")
    }

    @Parameter(title: "순찰 켜기", default: true)
    var isActive: Bool

    init() {
        isActive = true
    }

    init(isActive: Bool = true) {
        self.isActive = isActive
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        try await LockTodoTaskMutationStore.setPatrolActive(isActive)
        return .result(dialog: isActive ? "LockTodo 잠금화면 순찰을 시작했습니다." : "LockTodo 잠금화면 순찰을 종료했습니다.")
    }
}

struct LockTodoShortcuts: AppShortcutsProvider {
    static var shortcutTileColor: ShortcutTileColor = .blue

    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: AddTaskIntent(),
            phrases: [
                "\(.applicationName)에 할 일 추가",
                "\(.applicationName) 새 할 일",
                "\(.applicationName) 빠른 추가",
                "\(.applicationName) 잠금화면 추가",
                "\(.applicationName) 바로 입력"
            ],
            shortTitle: "잠금화면 추가",
            systemImageName: "checklist.checked"
        )

        AppShortcut(
            intent: SmartAddTaskIntent(),
            phrases: [
                "\(.applicationName) 스마트 입력",
                "\(.applicationName) 자연어 추가",
                "\(.applicationName) 한 문장 추가"
            ],
            shortTitle: "스마트 입력",
            systemImageName: "wand.and.sparkles"
        )

        AppShortcut(
            intent: StartFocusTaskIntent(),
            phrases: [
                "\(.applicationName) 집중 시작",
                "\(.applicationName) 오늘 할 일"
            ],
            shortTitle: "집중 시작",
            systemImageName: "scope"
        )

        AppShortcut(
            intent: StartSmartPlanIntent(),
            phrases: [
                "\(.applicationName) 스마트 플랜",
                "\(.applicationName) 다음 할 일",
                "\(.applicationName) 지금 뭐 하지"
            ],
            shortTitle: "스마트 플랜",
            systemImageName: "sparkles"
        )

        AppShortcut(
            intent: SetLockTodoPatrolIntent(),
            phrases: [
                "\(.applicationName) 순찰 시작",
                "\(.applicationName) 잠금화면 순찰",
                "\(.applicationName) 라이브 카드"
            ],
            shortTitle: "잠금화면 순찰",
            systemImageName: "shield.lefthalf.filled"
        )

        AppShortcut(
            intent: ShowTodayTasksIntent(),
            phrases: [
                "\(.applicationName) 오늘 할 일 확인",
                "\(.applicationName) 목록 보기",
                "\(.applicationName) 리스트",
                "\(.applicationName) 순찰 리포트"
            ],
            shortTitle: "오늘 할 일 목록",
            systemImageName: "checklist"
        )
    }
}

private struct ShortcutParsedTaskInput {
    var title: String
    var category: TaskCategory
    var dueDate: Date?
    var dueTime: Date?
    var tags: [String]
    var isImportant: Bool
    var colorHex: String
    var detectedParts: [String]

    var dialogSuffix: String {
        guard !detectedParts.isEmpty else { return "" }
        return " (\(detectedParts.joined(separator: ", ")))"
    }
}

private enum ShortcutSmartTaskParser {
    static func parse(_ rawText: String, calendar: Calendar = .current) -> ShortcutParsedTaskInput {
        let originalText = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        var workingText = originalText
        var detectedParts: [String] = []

        let tags = extractTags(from: workingText)
        if !tags.isEmpty {
            workingText = removeMatches(pattern: "#[\\p{L}\\p{N}_-]+", from: workingText)
            detectedParts.append(contentsOf: tags.map { "#\($0)" })
        }

        let color = parseColor(in: workingText)
        if let color {
            workingText = removeMatches(pattern: color.pattern, from: workingText)
            detectedParts.append(color.label)
        }

        let hasImportantMarker = containsMatch(pattern: "(^|\\s)(!+|중요|중요함)(?=\\s|$)", in: workingText)
        if hasImportantMarker {
            workingText = removeMatches(pattern: "(^|\\s)(!+|중요|중요함)(?=\\s|$)", from: workingText)
            detectedParts.append("중요")
        }

        var category = TaskCategory.today
        var dueDate: Date? = calendar.startOfDay(for: .now)
        if let dateMatch = parseDate(in: workingText, calendar: calendar) {
            workingText = removeMatches(pattern: dateMatch.pattern, from: workingText)
            category = dateMatch.category
            dueDate = dateMatch.date
            detectedParts.append(dateMatch.label)
        }

        var dueTime: Date?
        if let timeMatch = parseTime(in: workingText, baseDate: dueDate ?? calendar.startOfDay(for: .now), calendar: calendar) {
            workingText = removeMatches(pattern: timeMatch.pattern, from: workingText)
            dueTime = timeMatch.time
            if category == .later {
                category = .today
                dueDate = calendar.startOfDay(for: .now)
            }
            detectedParts.append(timeMatch.label)
        }

        let cleanedTitle = normalizeTitle(workingText)
        return ShortcutParsedTaskInput(
            title: cleanedTitle.isEmpty ? originalText : cleanedTitle,
            category: category,
            dueDate: category == .later ? nil : dueDate,
            dueTime: category == .later ? nil : dueTime,
            tags: tags,
            isImportant: hasImportantMarker,
            colorHex: color?.hex ?? TaskTint.defaultHex,
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

    private struct ColorMatch {
        var pattern: String
        var hex: String
        var label: String
    }

    private static func parseDate(in text: String, calendar: Calendar) -> DateMatch? {
        let today = calendar.startOfDay(for: .now)
        let keywordMatches: [(String, TaskCategory, Date?, String)] = [
            ("(^|\\s)오늘(?=\\s|$)", .today, today, "오늘"),
            ("(^|\\s)내일(?=\\s|$)", .tomorrow, calendar.date(byAdding: .day, value: 1, to: today), "내일"),
            ("(^|\\s)모레(?=\\s|$)", .scheduled, calendar.date(byAdding: .day, value: 2, to: today), "모레"),
            ("(^|\\s)주말(?=\\s|$)", .scheduled, nextWeekday(7, from: today, calendar: calendar), "주말"),
            ("(^|\\s)다음\\s*주(?=\\s|$)", .scheduled, calendar.date(byAdding: .day, value: 7, to: today), "다음 주"),
            ("(^|\\s)나중에(?=\\s|$)", .later, nil, "나중에")
        ]

        for match in keywordMatches where containsMatch(pattern: match.0, in: text) {
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
            if containsMatch(pattern: pattern, in: text),
               let date = nextWeekday(weekday.1, from: today, calendar: calendar) {
                return DateMatch(pattern: pattern, category: .scheduled, date: date, label: weekday.2)
            }
        }

        return parseNumericDate(in: text, calendar: calendar)
    }

    private static func parseNumericDate(in text: String, calendar: Calendar) -> DateMatch? {
        let patterns = [
            "(^|\\s)(\\d{1,2})/(\\d{1,2})(?=\\s|$)",
            "(^|\\s)(\\d{1,2})월\\s*(\\d{1,2})일(?=\\s|$)"
        ]

        for pattern in patterns {
            guard let match = firstMatch(pattern: pattern, in: text),
                  match.numberOfRanges >= 4,
                  let monthRange = Range(match.range(at: 2), in: text),
                  let dayRange = Range(match.range(at: 3), in: text),
                  let month = Int(text[monthRange]),
                  let day = Int(text[dayRange]) else {
                continue
            }

            var components = calendar.dateComponents([.year], from: .now)
            components.month = month
            components.day = day
            guard let date = calendar.date(from: components) else { continue }
            let today = calendar.startOfDay(for: .now)
            let resolvedDate = date < today ? calendar.date(byAdding: .year, value: 1, to: date) ?? date : date
            return DateMatch(pattern: pattern, category: .scheduled, date: resolvedDate, label: "\(month)/\(day)")
        }

        return nil
    }

    private static func parseTime(in text: String, baseDate: Date, calendar: Calendar) -> TimeMatch? {
        let keywordTimes: [(String, Int, Int, String)] = [
            ("(^|\\s)아침(?=\\s|$)", 9, 0, "아침 9:00"),
            ("(^|\\s)점심(?=\\s|$)", 12, 0, "점심 12:00"),
            ("(^|\\s)저녁(?=\\s|$)", 18, 0, "저녁 6:00"),
            ("(^|\\s)밤(?=\\s|$)", 21, 0, "밤 9:00"),
            ("(^|\\s)정오(?=\\s|$)", 12, 0, "정오")
        ]

        for keywordTime in keywordTimes where containsMatch(pattern: keywordTime.0, in: text) {
            if let date = calendar.date(bySettingHour: keywordTime.1, minute: keywordTime.2, second: 0, of: baseDate) {
                return TimeMatch(pattern: keywordTime.0, time: date, label: keywordTime.3)
            }
        }

        let pattern = "(^|\\s)(오전|오후)?\\s*(\\d{1,2})(?:(?::(\\d{2}))|(?:시\\s*(?:(\\d{1,2})분?)?))(?=\\s|$)"
        guard let match = firstMatch(pattern: pattern, in: text),
              match.numberOfRanges >= 6,
              let hourRange = Range(match.range(at: 3), in: text),
              var hour = Int(text[hourRange]) else {
            return nil
        }

        var minute = 0
        if let minuteRange = validRange(match.range(at: 4), in: text) ?? validRange(match.range(at: 5), in: text),
           let parsedMinute = Int(text[minuteRange]) {
            minute = parsedMinute
        }

        guard (0...59).contains(minute), (0...24).contains(hour) else { return nil }

        if let periodRange = validRange(match.range(at: 2), in: text) {
            let period = String(text[periodRange])
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

        return TimeMatch(pattern: pattern, time: date, label: date.formatted(date: .omitted, time: .shortened))
    }

    private static func parseColor(in text: String) -> ColorMatch? {
        let colorMap: [(String, String, String)] = [
            ("파랑|블루", TaskTint.blue.rawValue, "파랑"),
            ("빨강|레드", TaskTint.red.rawValue, "빨강"),
            ("주황|오렌지", TaskTint.orange.rawValue, "주황"),
            ("노랑|옐로우", TaskTint.yellow.rawValue, "노랑"),
            ("초록|그린", TaskTint.green.rawValue, "초록"),
            ("민트", TaskTint.mint.rawValue, "민트"),
            ("청록|틸", TaskTint.teal.rawValue, "청록"),
            ("남색|인디고", TaskTint.indigo.rawValue, "남색"),
            ("보라|퍼플", TaskTint.purple.rawValue, "보라"),
            ("분홍|핑크", TaskTint.pink.rawValue, "분홍"),
            ("갈색|브라운", TaskTint.brown.rawValue, "갈색"),
            ("회색|그레이", TaskTint.gray.rawValue, "회색")
        ]

        for color in colorMap {
            let pattern = "(^|\\s)(색상?|컬러)[:=]?\\s*(\(color.0))(?=\\s|$)"
            if containsMatch(pattern: pattern, in: text) {
                return ColorMatch(pattern: pattern, hex: color.1, label: color.2)
            }

            let shortPattern = "(^|\\s)@(\(color.0))(?=\\s|$)"
            if containsMatch(pattern: shortPattern, in: text) {
                return ColorMatch(pattern: shortPattern, hex: color.1, label: color.2)
            }
        }

        return nil
    }

    private static func extractTags(from text: String) -> [String] {
        matches(pattern: "#([\\p{L}\\p{N}_-]+)", in: text).compactMap { match in
            guard match.numberOfRanges > 1,
                  let range = Range(match.range(at: 1), in: text) else {
                return nil
            }
            return String(text[range]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        .filter { !$0.isEmpty }
    }

    private static func normalizeTitle(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: ",.;·")))
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
