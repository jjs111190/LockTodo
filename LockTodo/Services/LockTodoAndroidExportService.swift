import Foundation

struct LockTodoAndroidExportPayload: Codable {
    var schemaVersion: Int
    var generatedAt: Date
    var tasks: [LockTodoAndroidExportTask]
}

struct LockTodoAndroidExportTask: Codable {
    var id: UUID
    var title: String
    var notes: String
    var category: String
    var isCompleted: Bool
    var isImportant: Bool
    var colorHex: String
    var dueDate: Date?
    var dueTime: Date?
    var locationTitle: String
    var locationLatitude: Double?
    var locationLongitude: Double?
    var locationRadius: Double
    var showOnlyAtLocation: Bool
    var tags: [String]
}

enum LockTodoAndroidExportService {
    static func makeExportFile(tasks: [TaskItem], now: Date = .now) throws -> URL {
        let payload = LockTodoAndroidExportPayload(
            schemaVersion: 1,
            generatedAt: now,
            tasks: tasks
                .sorted { lhs, rhs in
                    if lhs.isCompleted != rhs.isCompleted { return !lhs.isCompleted }
                    if lhs.isImportant != rhs.isImportant { return lhs.isImportant }
                    return lhs.sortOrder < rhs.sortOrder
                }
                .map { task in
                    LockTodoAndroidExportTask(
                        id: task.id,
                        title: task.title,
                        notes: task.notes,
                        category: task.categoryRawValue,
                        isCompleted: task.isCompleted,
                        isImportant: task.isImportant,
                        colorHex: task.safeColorHex,
                        dueDate: task.dueDate,
                        dueTime: task.dueTime,
                        locationTitle: task.locationTitle,
                        locationLatitude: task.locationLatitude,
                        locationLongitude: task.locationLongitude,
                        locationRadius: task.locationRadius,
                        showOnlyAtLocation: task.showOnlyAtLocation,
                        tags: task.tags
                    )
                }
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        let data = try encoder.encode(payload)
        let filenameDate = ISO8601DateFormatter()
            .string(from: now)
            .replacingOccurrences(of: ":", with: "-")
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("LockTodo-Android-\(filenameDate)")
            .appendingPathExtension("json")
        try data.write(to: url, options: [.atomic])
        return url
    }
}
