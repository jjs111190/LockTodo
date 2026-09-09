import CoreLocation
import Foundation
import SwiftData
import UserNotifications
import WidgetKit

struct TaskLocationDraft: Hashable {
    var title: String
    var latitude: Double
    var longitude: Double
    var radius: Double
}

@MainActor
final class LocationReminderService: NSObject, ObservableObject {
    static let shared = LocationReminderService()

    @Published private(set) var authorizationStatus: CLAuthorizationStatus = .notDetermined
    @Published private(set) var currentLocation: CLLocation?
    @Published private(set) var statusMessage: String?

    private let manager = CLLocationManager()
    private var pendingLocationContinuations: [CheckedContinuation<CLLocation?, Never>] = []
    private var isUpdatingLocation = false
    private var monitoredTaskFingerprint: String?

    private override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        manager.distanceFilter = 50
        authorizationStatus = manager.authorizationStatus
    }

    func start() {
        authorizationStatus = manager.authorizationStatus
        if canUseLocation {
            startUpdatingLocationIfNeeded()
        } else {
            stopUpdatingLocationIfNeeded()
        }
    }

    func requestLocationAccess() {
        switch authorizationStatus {
        case .notDetermined:
            manager.requestAlwaysAuthorization()
        case .authorizedWhenInUse:
            manager.requestAlwaysAuthorization()
            startUpdatingLocationIfNeeded()
        case .authorizedAlways:
            startUpdatingLocationIfNeeded()
        case .denied, .restricted:
            statusMessage = "설정에서 위치 권한을 허용해야 위치 할 일을 사용할 수 있습니다."
        @unknown default:
            statusMessage = "위치 권한 상태를 확인할 수 없습니다."
        }
    }

    func captureCurrentLocation() async -> TaskLocationDraft? {
        requestLocationAccess()
        guard canUseLocation else { return nil }
        await requestNotificationAuthorizationIfNeeded()

        if let currentLocation, currentLocation.timestamp > Date().addingTimeInterval(-120) {
            return draft(from: currentLocation)
        }

        manager.requestLocation()
        let location = await withCheckedContinuation { continuation in
            pendingLocationContinuations.append(continuation)
        }
        guard let location else { return nil }
        return draft(from: location)
    }

    func syncMonitoredTasks(allTasks: [TaskItem]) {
        authorizationStatus = manager.authorizationStatus
        let locationTasks = Self.monitoredLocationTasks(from: allTasks)
        let nextFingerprint = Self.monitoringFingerprint(for: locationTasks)

        guard canUseLocation, CLLocationManager.isMonitoringAvailable(for: CLCircularRegion.self) else {
            clearMonitoredRegionsIfNeeded()
            return
        }
        let maximumRadius = manager.maximumRegionMonitoringDistance
        guard maximumRadius.isFinite, maximumRadius >= 100 else {
            clearMonitoredRegionsIfNeeded()
            return
        }

        guard nextFingerprint != monitoredTaskFingerprint else { return }
        stopLockTodoRegions()
        monitoredTaskFingerprint = nextFingerprint

        for task in locationTasks {
            guard let latitude = task.locationLatitude, let longitude = task.locationLongitude else { continue }
            guard latitude.isFinite,
                  longitude.isFinite,
                  (-90...90).contains(latitude),
                  (-180...180).contains(longitude) else {
                continue
            }

            let center = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
            guard CLLocationCoordinate2DIsValid(center) else { continue }

            let requestedRadius = task.locationRadius.isFinite ? task.locationRadius : 150
            let radius = min(max(requestedRadius, 100), maximumRadius)
            guard radius.isFinite, radius > 0 else { continue }

            let region = CLCircularRegion(center: center, radius: radius, identifier: regionIdentifier(for: task.id))
            region.notifyOnEntry = true
            region.notifyOnExit = true
            manager.startMonitoring(for: region)
        }
    }

    func nearbyTasks(from tasks: [TaskItem]) -> [TaskItem] {
        guard let currentLocation else { return [] }
        return tasks
            .compactMap { task -> (task: TaskItem, distance: CLLocationDistance)? in
                guard !task.isCompleted, task.hasLocationTrigger else { return nil }
                guard let distance = task.distanceInMeters(
                    toLatitude: currentLocation.coordinate.latitude,
                    longitude: currentLocation.coordinate.longitude
                ) else {
                    return nil
                }
                return distance <= Self.safeRadius(for: task) ? (task, distance) : nil
            }
            .sorted { $0.distance < $1.distance }
            .map(\.task)
    }

    func formattedDistance(for task: TaskItem) -> String? {
        guard let currentLocation,
              let distance = task.distanceInMeters(
                toLatitude: currentLocation.coordinate.latitude,
                longitude: currentLocation.coordinate.longitude
              ) else {
            return nil
        }

        if distance >= 1_000 {
            return String(format: "%.1fkm", distance / 1_000)
        } else {
            return "\(Int(distance.rounded()))m"
        }
    }

    private var canUseLocation: Bool {
        authorizationStatus == .authorizedAlways || authorizationStatus == .authorizedWhenInUse
    }

    private func startUpdatingLocationIfNeeded() {
        guard !isUpdatingLocation else { return }
        manager.startUpdatingLocation()
        isUpdatingLocation = true
    }

    private func stopUpdatingLocationIfNeeded() {
        guard isUpdatingLocation else { return }
        manager.stopUpdatingLocation()
        isUpdatingLocation = false
    }

    private func draft(from location: CLLocation) -> TaskLocationDraft {
        currentLocation = location
        return TaskLocationDraft(
            title: "현재 위치",
            latitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude,
            radius: 150
        )
    }

    private func stopLockTodoRegions() {
        for region in manager.monitoredRegions where region.identifier.hasPrefix("locktodo.task.") {
            manager.stopMonitoring(for: region)
        }
    }

    private func clearMonitoredRegionsIfNeeded() {
        guard monitoredTaskFingerprint != nil else { return }
        stopLockTodoRegions()
        monitoredTaskFingerprint = nil
    }

    private func regionIdentifier(for taskID: UUID) -> String {
        "locktodo.task.\(taskID.uuidString)"
    }

    private func taskID(fromRegionIdentifier identifier: String) -> UUID? {
        guard identifier.hasPrefix("locktodo.task.") else { return nil }
        return UUID(uuidString: String(identifier.dropFirst("locktodo.task.".count)))
    }

    private func isNearby(_ task: TaskItem, location: CLLocation) -> Bool {
        guard let distance = task.distanceInMeters(
            toLatitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude
        ) else {
            return false
        }
        return distance <= Self.safeRadius(for: task)
    }

    private static func monitoredLocationTasks(from tasks: [TaskItem]) -> ArraySlice<TaskItem> {
        tasks
            .filter { task in
                guard !task.isCompleted,
                      task.hasLocationTrigger,
                      let latitude = task.locationLatitude,
                      let longitude = task.locationLongitude else {
                    return false
                }

                return latitude.isFinite
                    && longitude.isFinite
                    && (-90...90).contains(latitude)
                    && (-180...180).contains(longitude)
            }
            .sorted { lhs, rhs in
                if lhs.isImportant != rhs.isImportant { return lhs.isImportant }
                return lhs.sortOrder < rhs.sortOrder
            }
            .prefix(20)
    }

    private static func monitoringFingerprint(for tasks: ArraySlice<TaskItem>) -> String {
        tasks.map { task in
            let latitude = task.locationLatitude ?? 0
            let longitude = task.locationLongitude ?? 0
            return [
                task.id.uuidString,
                String(format: "%.6f", latitude),
                String(format: "%.6f", longitude),
                String(format: "%.0f", safeRadius(for: task))
            ].joined(separator: ":")
        }
        .joined(separator: "|")
    }

    private static func safeRadius(for task: TaskItem) -> CLLocationDistance {
        let radius = task.locationRadius.isFinite ? task.locationRadius : 150
        return max(radius, 100)
    }

    private func resolvePendingLocationRequests(with location: CLLocation?) {
        let continuations = pendingLocationContinuations
        pendingLocationContinuations.removeAll()
        continuations.forEach { $0.resume(returning: location) }
    }

    private func requestNotificationAuthorizationIfNeeded() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        if settings.authorizationStatus == .notDetermined {
            _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
        }
        await NotificationService.shared.refreshAuthorizationStatus()
    }

    private func handleRegionEntry(taskID: UUID) {
        let context = WidgetDataStore.sharedModelContainer.mainContext
        let descriptor = FetchDescriptor<TaskItem>(
            predicate: #Predicate { $0.id == taskID }
        )
        guard let task = try? context.fetch(descriptor).first,
              !task.isCompleted,
              task.hasLocationTrigger else {
            return
        }

        if let lastNotification = task.lastLocationNotificationAt,
           Date().timeIntervalSince(lastNotification) < 900 {
            return
        }

        task.lastLocationNotificationAt = .now
        task.updatedAt = .now
        try? context.save()
        WidgetDataStore.setLocationTask(taskID, isActive: true)
        refreshLockScreenState(context: context)
        scheduleLocationNotification(for: task)
    }

    private func handleRegionExit(taskID: UUID) {
        guard WidgetDataStore.setLocationTask(taskID, isActive: false) else { return }
        refreshLockScreenState(context: WidgetDataStore.sharedModelContainer.mainContext)
    }

    private func refreshActiveLocationTasks(at location: CLLocation) {
        let context = WidgetDataStore.sharedModelContainer.mainContext
        guard let tasks = try? context.fetch(FetchDescriptor<TaskItem>()) else { return }

        let activeIDs = Set(tasks.compactMap { task -> UUID? in
            guard !task.isCompleted, task.hasLocationTrigger, isNearby(task, location: location) else { return nil }
            return task.id
        })
        guard WidgetDataStore.replaceActiveLocationTaskIDs(with: activeIDs) else { return }
        refreshLockScreenState(context: context, tasks: tasks)
    }

    private func refreshLockScreenState(context: ModelContext, tasks providedTasks: [TaskItem]? = nil) {
        guard let tasks = providedTasks ?? (try? context.fetch(FetchDescriptor<TaskItem>())) else { return }
        let previousSummary = WidgetDataStore.loadSummary()
        let focus = tasks.first { $0.title == previousSummary.focusTitle }
        let summary = WidgetDataStore.summary(from: tasks, focusTask: focus)
        WidgetDataStore.saveSummary(summary)
        WidgetCenter.shared.reloadAllTimelines()
        WatchConnectivityService.shared.send(summary: summary)

        Task {
            await LiveActivityService.shared.startOrUpdate(summary: summary)
        }
    }

    private func scheduleLocationNotification(for task: TaskItem) {
        let content = UNMutableNotificationContent()
        content.title = "근처 할 일"
        content.body = "\(task.locationDisplayName): \(task.title)"
        content.sound = .default
        content.categoryIdentifier = "TASK_REMINDER"
        content.userInfo = ["taskID": task.id.uuidString, "url": "locktodo://task/\(task.id.uuidString)"]

        let request = UNNotificationRequest(
            identifier: "locktodo.location.\(task.id.uuidString)",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }
}

extension LocationReminderService: @preconcurrency CLLocationManagerDelegate {
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorizationStatus = manager.authorizationStatus
        if canUseLocation {
            statusMessage = nil
            startUpdatingLocationIfNeeded()
        } else if authorizationStatus == .denied || authorizationStatus == .restricted {
            statusMessage = "설정에서 위치 권한을 허용해야 위치 할 일을 사용할 수 있습니다."
            stopUpdatingLocationIfNeeded()
            clearMonitoredRegionsIfNeeded()
            resolvePendingLocationRequests(with: nil)
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        guard CLLocationCoordinate2DIsValid(location.coordinate),
              location.horizontalAccuracy >= 0 else {
            return
        }
        currentLocation = location
        refreshActiveLocationTasks(at: location)
        resolvePendingLocationRequests(with: location)
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        statusMessage = "현재 위치를 가져오지 못했습니다."
        resolvePendingLocationRequests(with: nil)
    }

    func locationManager(_ manager: CLLocationManager, didEnterRegion region: CLRegion) {
        guard let taskID = taskID(fromRegionIdentifier: region.identifier) else { return }
        handleRegionEntry(taskID: taskID)
    }

    func locationManager(_ manager: CLLocationManager, didExitRegion region: CLRegion) {
        guard let taskID = taskID(fromRegionIdentifier: region.identifier) else { return }
        handleRegionExit(taskID: taskID)
    }
}
