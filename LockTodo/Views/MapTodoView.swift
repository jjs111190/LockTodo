import CoreLocation
import MapKit
import SwiftData
import SwiftUI
import UIKit
import WidgetKit

struct MapTodoView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \TaskItem.sortOrder, order: .forward) private var allTasks: [TaskItem]

    @ObservedObject var viewModel: TaskViewModel
    @ObservedObject private var locationService = LocationReminderService.shared
    @StateObject private var searchModel = MapLocationSearchModel()

    @State private var mapRegion = Self.defaultRegion
    @State private var cameraPosition: MapCameraPosition = .region(Self.defaultRegion)
    @State private var mapCenter = Self.defaultCoordinate
    @State private var selectedLocationTitle = "지도 위치"
    @State private var selectedNamedCoordinate: CLLocationCoordinate2D?
    @State private var selectedCluster: MapTaskCluster?
    @State private var taskToAssign: TaskItem?
    @State private var selectedMarkerColorHex = TaskTint.defaultHex
    @State private var isAddTaskPresented = false
    @State private var isSearchPresented = false
    @State private var isLocationTodoPanelPresented = false
    @State private var isLocationTodoListExpanded = false
    @State private var activeMapRoute = WidgetDataStore.activeMapTodoRoute
    @State private var inAppRoutePolyline: MKPolyline?
    @State private var inAppRouteID: UUID?
    @State private var inAppRouteMapRect: MKMapRect?
    @State private var inAppRouteSummary: InAppRouteSummary?
    @State private var activeDirections: MKDirections?
    @State private var isRouteCalculating = false
    @State private var routeMessage: String?
    @State private var routeTravelMode: MapRouteTravelMode = .walking
    @State private var isRouteStepsExpanded = false
    @State private var didFocusInitialLocation = false
    @State private var arrivalCheckInMessage: String?
    @State private var taskPendingDeletion: TaskItem?
    @State private var clusterPendingDeletion: MapTaskCluster?
    @FocusState private var isSearchFocused: Bool

    private static let defaultCoordinate = CLLocationCoordinate2D(latitude: 37.5665, longitude: 126.9780)
    private static let defaultRegion = MKCoordinateRegion(
        center: defaultCoordinate,
        span: MKCoordinateSpan(latitudeDelta: 0.08, longitudeDelta: 0.08)
    )

    private var locationTasks: [TaskItem] {
        allTasks
            .filter { !$0.isCompleted && $0.hasLocationTrigger }
            .sorted { lhs, rhs in
                if lhs.isImportant != rhs.isImportant { return lhs.isImportant }
                return lhs.sortOrder < rhs.sortOrder
            }
    }

    private var completedLocationTasks: [TaskItem] {
        allTasks
            .filter { $0.isCompleted && $0.hasLocationTrigger }
            .sorted { lhs, rhs in
                let lhsDate = lhs.completedAt ?? lhs.updatedAt
                let rhsDate = rhs.completedAt ?? rhs.updatedAt
                return lhsDate > rhsDate
            }
    }

    private var locationPanelBadgeText: String? {
        let totalCount = locationTasks.count + completedLocationTasks.count
        return totalCount == 0 ? nil : "\(totalCount)"
    }

    private var assignableTasks: [TaskItem] {
        allTasks
            .filter { !$0.isCompleted }
            .sorted { lhs, rhs in
                if lhs.hasLocationTrigger != rhs.hasLocationTrigger { return !lhs.hasLocationTrigger }
                if lhs.isImportant != rhs.isImportant { return lhs.isImportant }
                return lhs.sortOrder < rhs.sortOrder
            }
    }

    private var nearbyTasks: [TaskItem] {
        locationService.nearbyTasks(from: allTasks)
    }

    private var nearbyTaskIDs: Set<UUID> {
        Set(nearbyTasks.map(\.id))
    }

    private var routeStops: [MapTodoRouteStop] {
        let currentLocation = locationService.currentLocation

        let sortedClusters = clusters.sorted { lhs, rhs in
            let lhsNearby = lhs.tasks.contains { nearbyTaskIDs.contains($0.id) }
            let rhsNearby = rhs.tasks.contains { nearbyTaskIDs.contains($0.id) }
            if lhsNearby != rhsNearby { return lhsNearby }

            if let currentLocation {
                let lhsDistance = distance(from: currentLocation, to: lhs.coordinate)
                let rhsDistance = distance(from: currentLocation, to: rhs.coordinate)
                if abs(lhsDistance - rhsDistance) > 5 {
                    return lhsDistance < rhsDistance
                }
            }

            let lhsImportantCount = lhs.tasks.filter(\.isImportant).count
            let rhsImportantCount = rhs.tasks.filter(\.isImportant).count
            if lhsImportantCount != rhsImportantCount { return lhsImportantCount > rhsImportantCount }

            if lhs.tasks.count != rhs.tasks.count { return lhs.tasks.count > rhs.tasks.count }
            return lhs.title < rhs.title
        }

        return sortedClusters.enumerated().map { index, cluster in
            MapTodoRouteStop(
                rank: index + 1,
                cluster: cluster,
                distance: currentLocation.map { distance(from: $0, to: cluster.coordinate) }
            )
        }
    }

    private var routeBriefing: MapRouteBriefing? {
        guard routeStops.count > 1 else { return nil }
        let taskCount = routeStops.reduce(0) { $0 + $1.cluster.tasks.count }
        let importantCount = routeStops.reduce(0) { partialResult, stop in
            partialResult + stop.cluster.tasks.filter(\.isImportant).count
        }
        let estimatedDistance = estimatedRouteDistance(for: routeStops).flatMap(formattedRouteDistance)

        return MapRouteBriefing(
            placeCount: routeStops.count,
            taskCount: taskCount,
            importantCount: importantCount,
            estimatedDistanceText: estimatedDistance
        )
    }

    private var isNavigationModeActive: Bool {
        activeMapRoute != nil
    }

    private var navigationStep: InAppRouteStepSummary? {
        guard let steps = inAppRouteSummary?.steps, !steps.isEmpty else { return nil }
        guard let currentLocation = locationService.currentLocation else { return steps.first }

        let nearbySteps = steps.enumerated().compactMap { index, step -> (index: Int, distance: CLLocationDistance)? in
            guard let distance = step.distance(from: currentLocation) else { return nil }
            return (index, distance)
        }

        guard let nearestStep = nearbySteps.min(by: { $0.distance < $1.distance }) else {
            return steps.first
        }

        if nearestStep.distance < 35, nearestStep.index + 1 < steps.count {
            return steps[nearestStep.index + 1]
        }

        return steps[nearestStep.index]
    }

    private var clusters: [MapTaskCluster] {
        let grouped = Dictionary(grouping: locationTasks) { task in
            MapTaskCluster.key(latitude: task.locationLatitude ?? 0, longitude: task.locationLongitude ?? 0)
        }

        return grouped.values.compactMap { tasks in
            guard let first = tasks.first,
                  let latitude = first.locationLatitude,
                  let longitude = first.locationLongitude else {
                return nil
            }

            return MapTaskCluster(
                coordinate: CLLocationCoordinate2D(latitude: latitude, longitude: longitude),
                tasks: tasks.sorted { $0.sortOrder < $1.sortOrder }
            )
        }
        .sorted { lhs, rhs in
            if lhs.tasks.count != rhs.tasks.count { return lhs.tasks.count > rhs.tasks.count }
            return lhs.title < rhs.title
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                mapLayer
                if !isNavigationModeActive {
                    centerPin
                }
                mapOverlay
            }
            .toolbar(.hidden, for: .navigationBar)
            .sheet(item: $selectedCluster) { cluster in
                MapTaskClusterSheet(
                    cluster: cluster,
                    viewModel: viewModel,
                    allTasks: allTasks,
                    onDirections: {
                        selectedCluster = nil
                        openDirections(to: cluster)
                    },
                    onDismiss: { selectedCluster = nil },
                    onDelete: { task in
                        deleteLocationTask(task)
                        selectedCluster = nil
                    },
                    onRefresh: refreshMapState
                )
            }
            .sheet(isPresented: $isAddTaskPresented, onDismiss: refreshMapState) {
                AddTaskView(
                    viewModel: viewModel,
                    initialDate: Calendar.current.startOfDay(for: .now),
                    autoFocus: true,
                    initialLocation: selectedMapLocationDraft,
                    showOnlyAtInitialLocation: true
                )
            }
            .task {
                activeMapRoute = WidgetDataStore.activeMapTodoRoute
                locationService.start()
                locationService.syncMonitoredTasks(allTasks: allTasks)
                await focusInitialCurrentLocationIfNeeded()
                if activeMapRoute != nil {
                    refreshRouteForActiveDestination()
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .lockTodoDatabaseChangedExternal)) { _ in
                let previousRouteID = activeMapRoute?.id
                let nextRoute = WidgetDataStore.activeMapTodoRoute
                activeMapRoute = nextRoute
                if nextRoute == nil {
                    clearInAppRoute()
                } else if previousRouteID != nextRoute?.id, !isRouteCalculating {
                    refreshRouteForActiveDestination()
                }
            }
            .confirmationDialog(
                "위치 할 일 삭제",
                isPresented: Binding(
                    get: { taskPendingDeletion != nil },
                    set: { if !$0 { taskPendingDeletion = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button("삭제", role: .destructive) {
                    if let task = taskPendingDeletion {
                        deleteLocationTask(task)
                    }
                    taskPendingDeletion = nil
                }
                Button("취소", role: .cancel) {
                    taskPendingDeletion = nil
                }
            } message: {
                if let task = taskPendingDeletion {
                    Text("'\(task.title)'을(를) 완전히 삭제합니다.")
                }
            }
            .confirmationDialog(
                "이 위치의 할 일 삭제",
                isPresented: Binding(
                    get: { clusterPendingDeletion != nil },
                    set: { if !$0 { clusterPendingDeletion = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button("이 위치의 할 일 모두 삭제", role: .destructive) {
                    if let cluster = clusterPendingDeletion {
                        deleteLocationCluster(cluster)
                    }
                    clusterPendingDeletion = nil
                }
                Button("취소", role: .cancel) {
                    clusterPendingDeletion = nil
                }
            } message: {
                if let cluster = clusterPendingDeletion {
                    Text("'\(cluster.title)'에 있는 \(cluster.tasks.count)개 할 일을 완전히 삭제합니다.")
                }
            }
        }
    }

    private func focusInitialCurrentLocationIfNeeded() async {
        guard !didFocusInitialLocation else { return }
        didFocusInitialLocation = true

        if let location = locationService.currentLocation {
            moveCamera(to: location.coordinate, span: 0.012)
            return
        }

        if let draft = await locationService.captureCurrentLocation() {
            let coordinate = CLLocationCoordinate2D(latitude: draft.latitude, longitude: draft.longitude)
            moveCamera(to: coordinate, span: 0.012)
            selectedLocationTitle = draft.title
            selectedNamedCoordinate = coordinate
        } else if let location = locationService.currentLocation {
            moveCamera(to: location.coordinate, span: 0.012)
        }
    }

    private var mapLayer: some View {
        SwiftUITodoMapContainer(
            cameraPosition: $cameraPosition,
            clusters: clusters,
            nearbyTaskIDs: nearbyTaskIDs,
            routePolyline: inAppRoutePolyline,
            onRegionChanged: { newRegion in
                mapRegion = newRegion
                updateMapCenter(newRegion.center)
            },
            onClusterSelected: { selectedCluster = $0 }
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.white)
        .ignoresSafeArea()
    }

    private var centerPin: some View {
        LockTodoMapCenterMarker()
            .offset(y: -24)
            .allowsHitTesting(false)
    }

    private var mapOverlay: some View {
        Group {
            if let activeMapRoute {
                navigationOverlay(activeMapRoute)
            } else {
                defaultMapOverlay
            }
        }
    }

    private var defaultMapOverlay: some View {
        VStack(spacing: 10) {
            floatingTopControls

            if !nearbyTasks.isEmpty {
                arrivalCheckInPanel
            }

            Spacer()

            mapBottomControls
        }
        .padding(.horizontal, 14)
        .padding(.top, 10)
        .padding(.bottom, 12)
    }

    private var mapBottomControls: some View {
        VStack(alignment: .trailing, spacing: 10) {
            floatingMapActionButtons

            if isLocationTodoPanelPresented {
                if !clusters.isEmpty || !completedLocationTasks.isEmpty {
                    locationTodoListPanel
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }

                assignmentPanel
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
        .animation(.snappy(duration: 0.24), value: isLocationTodoPanelPresented)
    }

    private func navigationOverlay(_ route: MapTodoRouteSnapshot) -> some View {
        VStack(spacing: 12) {
            navigationTopBanner(route)

            Spacer()

            if !nearbyTasks.isEmpty {
                arrivalCheckInPanel
            }

            navigationBottomPanel(route)
        }
        .padding(.horizontal, 14)
        .padding(.top, 10)
        .padding(.bottom, 12)
    }

    private var floatingTopControls: some View {
        VStack(alignment: .trailing, spacing: 10) {
            HStack(spacing: 10) {
                Spacer()

                connectedSearchControl

                Button {
                    focusCurrentLocation()
                } label: {
                    Image(systemName: "location.fill")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(Color.accentColor)
                        .frame(width: 44, height: 44)
                        .background(.regularMaterial, in: Circle())
                        .shadow(color: Color.black.opacity(0.12), radius: 12, x: 0, y: 6)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("현재 위치")
            }

            if shouldShowSearchResults {
                searchResultsPanel
                    .frame(maxWidth: 336)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
    }

    private var connectedSearchControl: some View {
        HStack(spacing: 0) {
            Button {
                toggleSearchPanel()
            } label: {
                Image(systemName: isSearchPresented ? "xmark" : "magnifyingglass")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(isSearchPresented ? Color.secondary : Color.primary)
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isSearchPresented ? "검색 닫기" : "장소 검색")

            if isSearchPresented {
                TextField("장소 검색", text: $searchModel.query)
                    .textInputAutocapitalization(.never)
                    .disableAutocorrection(true)
                    .focused($isSearchFocused)
                    .submitLabel(.search)
                    .onSubmit {
                        searchTypedLocation()
                    }
                    .font(.subheadline.weight(.medium))
                    .frame(width: 206)
                    .transition(.opacity.combined(with: .move(edge: .trailing)))

                if !searchModel.query.isEmpty {
                    Button {
                        searchModel.clear()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("검색어 지우기")
                    .frame(width: 34, height: 44)
                    .transition(.opacity)
                }
            }
        }
        .padding(.trailing, isSearchPresented ? 8 : 0)
        .frame(height: 44)
        .background(.regularMaterial, in: Capsule())
        .overlay {
            Capsule()
                .stroke(Color.white.opacity(0.22), lineWidth: 0.8)
        }
        .shadow(color: Color.black.opacity(0.12), radius: 12, x: 0, y: 6)
        .animation(.snappy(duration: 0.24), value: isSearchPresented)
    }

    private var floatingMapActionButtons: some View {
        HStack(spacing: 10) {
            MapFloatingActionButton(
                title: "위치 할 일",
                systemImage: "mappin.and.ellipse",
                badgeText: locationPanelBadgeText,
                isActive: isLocationTodoPanelPresented,
                isPrimary: false
            ) {
                withAnimation(.snappy(duration: 0.24)) {
                    isLocationTodoPanelPresented.toggle()
                }
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            }

            MapFloatingActionButton(
                title: "할 일 추가",
                systemImage: "plus",
                badgeText: nil,
                isActive: false,
                isPrimary: true
            ) {
                isAddTaskPresented = true
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            }
        }
    }

    private var shouldShowSearchResults: Bool {
        isSearchPresented && (!searchModel.results.isEmpty || searchModel.isResolving || searchModel.message != nil)
    }

    private var searchResultsPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            if searchModel.isResolving {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("검색 중")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                }
                .padding(12)
            }

            ForEach(searchModel.results.prefix(6)) { result in
                Button {
                    selectSearchResult(result)
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "mappin.circle.fill")
                            .font(.title3)
                            .foregroundStyle(Color.accentColor)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(result.title)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.primary)
                                .lineLimit(1)

                            if !result.subtitle.isEmpty {
                                Text(result.subtitle)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }

                        Spacer(minLength: 8)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                }
                .buttonStyle(.plain)
            }

            if let message = searchModel.message {
                Text(message)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .padding(12)
            }
        }
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .stroke(Color.primary.opacity(0.07), lineWidth: 1)
        }
    }

    private var nearbyTaskStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(nearbyTasks.prefix(8)) { task in
                    Button {
                        selectedCluster = clusters.first { cluster in
                            cluster.tasks.contains { $0.id == task.id }
                        }
                    } label: {
                        Label(task.title, systemImage: "location.fill")
                            .font(.caption.weight(.semibold))
                            .lineLimit(1)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 7)
                            .background(.regularMaterial, in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 2)
        }
    }

    private var locationTodoListPanel: some View {
        VStack(alignment: .leading, spacing: isLocationTodoListExpanded ? 10 : 8) {
            Button {
                withAnimation(.snappy(duration: 0.24)) {
                    isLocationTodoListExpanded.toggle()
                }
            } label: {
                HStack(spacing: 10) {
                    Label("위치 할 일", systemImage: "mappin.and.ellipse")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)

                    Spacer(minLength: 8)

                    Text("\(clusters.count)곳 · 진행 \(locationTasks.count) · 완료 \(completedLocationTasks.count)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)

                    Image(systemName: "chevron.up")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(isLocationTodoListExpanded ? 0 : 180))
                        .frame(width: 22, height: 22)
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isLocationTodoListExpanded ? "위치 할 일 접기" : "위치 할 일 펼치기")

            if let routeBriefing {
                MapRouteBriefingCard(briefing: routeBriefing) {
                    if let nextStop = routeStops.first {
                        openDirections(to: nextStop.cluster)
                    }
                }
            }

            if let nextStop = routeStops.first {
                routeNextStopCard(nextStop)
            }

            if isLocationTodoListExpanded {
                expandedLocationTodoList
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                completedLocationTodoSection
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            } else {
                Group {
                    if routeStops.isEmpty {
                        collapsedCompletedLocationSummary
                    } else {
                        collapsedLocationTodoSummary
                    }
                }
                .transition(.opacity)
            }
        }
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        }
    }

    private var arrivalCheckInPanel: some View {
        MapArrivalCheckInPanel(
            tasks: Array(nearbyTasks.prefix(4)),
            totalCount: nearbyTasks.count,
            message: arrivalCheckInMessage,
            distanceText: { locationService.formattedDistance(for: $0) },
            onCompleteTask: completeNearbyTask,
            onCompleteAll: completeNearbyTasks,
            onFocus: focusNearestNearbyTask
        )
    }

    private var collapsedLocationTodoSummary: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 7) {
                ForEach(routeStops.prefix(4)) { stop in
                    Button {
                        openDirections(to: stop.cluster)
                    } label: {
                        HStack(spacing: 6) {
                            Text("\(stop.rank)")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.white)
                                .frame(width: 22, height: 22)
                                .background(Color(hex: stop.cluster.tintColorHex), in: Circle())

                            Text(stop.cluster.title)
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.primary)
                                .lineLimit(1)

                            Image(systemName: "arrow.triangle.turn.up.right.diamond.fill")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(Color(hex: stop.cluster.tintColorHex))
                        }
                        .padding(.leading, 5)
                        .padding(.trailing, 9)
                        .padding(.vertical, 5)
                        .background(Color.white.opacity(0.86), in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(stop.cluster.title) 길안내")
                }
            }
        }
    }

    private var collapsedCompletedLocationSummary: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("완료한 위치 할 일 \(completedLocationTasks.count)개", systemImage: "checkmark.circle.fill")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 7) {
                    ForEach(completedLocationTasks.prefix(5)) { task in
                        Button {
                            focusTaskLocation(task)
                        } label: {
                            Label(task.title, systemImage: "checkmark.circle.fill")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                                .padding(.horizontal, 9)
                                .padding(.vertical, 6)
                                .background(Color.white.opacity(0.86), in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var expandedLocationTodoList: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 8) {
                ForEach(routeStops.prefix(8)) { stop in
                    MapRouteStopRow(
                        stop: stop,
                        distanceText: formattedRouteDistance(stop.distance),
                        onFocus: { focusRouteStop(stop) },
                        onDirections: { openDirections(to: stop.cluster) },
                        onDeleteTask: { taskPendingDeletion = $0 },
                        onDeleteCluster: { clusterPendingDeletion = stop.cluster }
                    )
                }
            }
        }
        .frame(maxHeight: 170)
    }

    private var completedLocationTodoSection: some View {
        Group {
            if !completedLocationTasks.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Label("완료한 위치 할 일", systemImage: "checkmark.seal.fill")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.primary)

                        Spacer(minLength: 8)

                        Text("\(completedLocationTasks.count)개")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }

                    VStack(spacing: 7) {
                        ForEach(completedLocationTasks.prefix(6)) { task in
                            CompletedLocationTaskRow(
                                task: task,
                                completedText: completedLocationText(for: task),
                                onFocus: { focusTaskLocation(task) },
                                onRestore: { restoreCompletedLocationTask(task) },
                                onDelete: { taskPendingDeletion = task }
                            )
                        }
                    }
                }
                .padding(10)
                .background(Color.white.opacity(0.78), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
        }
    }

    private func routeNextStopCard(_ stop: MapTodoRouteStop) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                Text("\(stop.rank)")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 30, height: 30)
                    .background(Color(hex: stop.cluster.tintColorHex), in: Circle())

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Label("다음 위치", systemImage: "sparkles")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(Color.accentColor)

                        if let distanceText = formattedRouteDistance(stop.distance) {
                            Text(distanceText)
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }

                    Text(stop.cluster.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    Text(routePreviewText(for: stop))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)
            }

            HStack(spacing: 8) {
                Button {
                    focusRouteStop(stop)
                } label: {
                    Label("지도에서 보기", systemImage: "location.viewfinder")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)

                Button {
                    openDirections(to: stop.cluster)
                } label: {
                    Label("길안내", systemImage: "arrow.triangle.turn.up.right.diamond.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            }
            .font(.caption.weight(.semibold))
        }
        .padding(10)
        .background(Color.white.opacity(0.92), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func navigationTopBanner(_ route: MapTodoRouteSnapshot) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: navigationInstructionIcon)
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(Color.accentColor)
                .frame(width: 48, height: 48)
                .background(Color.white, in: Circle())

            VStack(alignment: .leading, spacing: 5) {
                Text(navigationInstructionEyebrow)
                    .font(.caption.weight(.black))
                    .foregroundStyle(.white.opacity(0.78))

                Text(navigationInstructionText(for: route))
                    .font(.system(size: 21, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .minimumScaleFactor(0.78)

                if let distance = navigationInstructionDistanceText {
                    Text(distance)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.white.opacity(0.82))
                        .monospacedDigit()
                }
            }

            Spacer(minLength: 8)

            Button {
                endActiveMapRoute()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .background(.white.opacity(0.18), in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("길찾기 종료")
        }
        .padding(14)
        .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: Color.black.opacity(0.18), radius: 16, x: 0, y: 8)
    }

    private func navigationBottomPanel(_ route: MapTodoRouteSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(route.lockScreenTitle)
                        .font(.headline.weight(.bold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    Text(route.summaryText)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                Button {
                    focusActiveRoute(route)
                } label: {
                    Image(systemName: "location.viewfinder")
                        .font(.caption.weight(.black))
                        .frame(width: 36, height: 36)
                        .background(Color.white.opacity(0.82), in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("목적지 보기")

                Button {
                    fitInAppRoute()
                } label: {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .font(.caption.weight(.black))
                        .frame(width: 36, height: 36)
                        .background(Color.white.opacity(0.82), in: Circle())
                }
                .buttonStyle(.plain)
                .disabled(inAppRouteMapRect == nil)
                .accessibilityLabel("경로 전체 보기")
            }

            routeModeSelector

            if isRouteCalculating {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("앱 안에서 경로 계산 중")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(Color.white.opacity(0.72), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            } else if let inAppRouteSummary {
                navigationSummaryContent(inAppRouteSummary)
            } else if let routeMessage {
                Label(routeMessage, systemImage: "exclamationmark.triangle")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.white.opacity(0.72), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
        }
        .padding(14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.white.opacity(0.28), lineWidth: 1)
        }
        .shadow(color: Color.black.opacity(0.16), radius: 18, x: 0, y: 8)
    }

    private func navigationSummaryContent(_ summary: InAppRouteSummary) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                navigationMetric(summary.expectedTravelTimeText, systemImage: "clock.fill", tint: Color.accentColor)
                navigationMetric(summary.distanceText, systemImage: "point.topleft.down.curvedto.point.bottomright.up", tint: Color.blue)
                navigationMetric(summary.travelModeTitle, systemImage: "location.north.line.fill", tint: Color.green)
            }

            HStack(spacing: 8) {
                Button {
                    withAnimation(.snappy(duration: 0.24)) {
                        isRouteStepsExpanded.toggle()
                    }
                } label: {
                    Label(
                        isRouteStepsExpanded ? "단계 접기" : "단계 보기",
                        systemImage: "list.bullet"
                    )
                    .font(.caption.weight(.bold))
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(summary.steps.isEmpty)

                Button {
                    fitInAppRoute()
                } label: {
                    Label("전체 보기", systemImage: "map")
                        .font(.caption.weight(.bold))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            }

            if isRouteStepsExpanded {
                NavigationStepList(steps: summary.steps)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
    }

    private func navigationMetric(_ text: String, systemImage: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Image(systemName: systemImage)
                .font(.caption.weight(.bold))
                .foregroundStyle(tint)

            Text(text)
                .font(.subheadline.weight(.black))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 11)
        .padding(.vertical, 10)
        .background(Color.white.opacity(0.76), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var navigationInstructionEyebrow: String {
        if isRouteCalculating { return "경로 계산 중" }
        if routeMessage != nil { return "길찾기 확인 필요" }
        return "다음 안내"
    }

    private var navigationInstructionIcon: String {
        if isRouteCalculating { return "location.north.line" }
        if routeMessage != nil { return "exclamationmark.triangle.fill" }
        return "arrow.turn.up.right"
    }

    private var navigationInstructionDistanceText: String? {
        guard let navigationStep, !navigationStep.distanceText.isEmpty else { return nil }
        return navigationStep.distanceText
    }

    private func navigationInstructionText(for route: MapTodoRouteSnapshot) -> String {
        if isRouteCalculating { return "\(route.lockScreenTitle)까지 경로 찾는 중" }
        if let routeMessage { return routeMessage }
        if let navigationStep { return navigationStep.instruction }
        return "\(route.lockScreenTitle)로 이동"
    }

    private func activeMapRoutePanel(_ route: MapTodoRouteSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            activeRouteHeader(route)
            routeModeSelector

            if isRouteCalculating {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("앱 안에서 경로 계산 중")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                }
            } else if let inAppRouteSummary {
                InAppRouteSummaryView(
                    summary: inAppRouteSummary,
                    isStepsExpanded: isRouteStepsExpanded,
                    onToggleSteps: {
                        withAnimation(.snappy(duration: 0.24)) {
                            isRouteStepsExpanded.toggle()
                        }
                    },
                    onFitRoute: fitInAppRoute
                )
            } else if let routeMessage {
                Label(routeMessage, systemImage: "exclamationmark.triangle")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.accentColor.opacity(0.18), lineWidth: 1)
        }
    }

    private func activeRouteHeader(_ route: MapTodoRouteSnapshot) -> some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: "point.topleft.down.curvedto.point.bottomright.up")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(Color.accentColor)
                .frame(width: 30, height: 30)
                .background(Color.white.opacity(0.92), in: Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text("앱 내부 길찾기")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(Color.accentColor)

                Text(route.lockScreenTitle)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Text(route.summaryText)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            Button {
                fitInAppRoute()
            } label: {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .font(.caption.weight(.bold))
                    .frame(width: 30, height: 30)
            }
            .buttonStyle(.plain)
            .disabled(inAppRouteMapRect == nil)
            .accessibilityLabel("경로 전체 보기")

            Button {
                focusActiveRoute(route)
            } label: {
                Image(systemName: "location.viewfinder")
                    .font(.caption.weight(.bold))
                    .frame(width: 30, height: 30)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("목적지 위치 보기")

            Button {
                endActiveMapRoute()
            } label: {
                Image(systemName: "xmark")
                    .font(.caption.weight(.bold))
                    .frame(width: 30, height: 30)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("지도 루트 종료")
        }
    }

    private var routeModeSelector: some View {
        HStack(spacing: 6) {
            ForEach(MapRouteTravelMode.allCases) { mode in
                Button {
                    guard routeTravelMode != mode else { return }
                    routeTravelMode = mode
                    refreshRouteForActiveDestination()
                } label: {
                    Label(mode.title, systemImage: mode.systemImage)
                        .font(.caption2.weight(.bold))
                        .lineLimit(1)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 7)
                        .background(
                            routeTravelMode == mode ? Color.accentColor.opacity(0.16) : Color.white.opacity(0.72),
                            in: Capsule()
                        )
                        .foregroundStyle(routeTravelMode == mode ? Color.accentColor : Color.secondary)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var assignmentPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Menu {
                    ForEach(assignableTasks) { task in
                        Button {
                            selectTaskForMapAssignment(task)
                        } label: {
                            Label(task.title, systemImage: task.hasLocationTrigger ? "location.fill" : "circle")
                        }
                    }
                } label: {
                    Label(taskToAssign?.title ?? "기존 할 일 선택", systemImage: "checklist")
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.bordered)
                .disabled(assignableTasks.isEmpty)

                Button {
                    assignSelectedTaskToMapCenter()
                } label: {
                    Image(systemName: "mappin.and.ellipse")
                        .font(.headline)
                }
                .buttonStyle(.borderedProminent)
                .disabled(taskToAssign == nil)
                .accessibilityLabel("지도 위치 지정")
            }

            if taskToAssign != nil {
                VStack(alignment: .leading, spacing: 7) {
                    HStack(spacing: 6) {
                        Image(systemName: "paintpalette.fill")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(Color(hex: selectedMarkerColorHex))

                        Text("마커 색")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.secondary)

                        Spacer()
                    }

                    TaskColorSwatchPicker(
                        selection: Binding(
                            get: { selectedMarkerColorHex },
                            set: { updateSelectedMarkerColor($0) }
                        )
                    )
                }
                .padding(.horizontal, 2)
            }

            HStack {
                Label(selectedLocationTitle, systemImage: "mappin.circle")
                    .lineLimit(1)
                Spacer()
                Text(mapCenterText)
                    .monospacedDigit()
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        }
    }

    private var mapCenterText: String {
        let coordinate = resolvedMapCenter
        return String(format: "%.5f, %.5f", coordinate.latitude, coordinate.longitude)
    }

    private var selectedMapLocationDraft: TaskLocationDraft {
        let coordinate = resolvedMapCenter
        return TaskLocationDraft(
            title: selectedLocationTitle,
            latitude: coordinate.latitude,
            longitude: coordinate.longitude,
            radius: 150
        )
    }

    private var resolvedMapCenter: CLLocationCoordinate2D {
        if Self.isValidCoordinate(mapCenter) {
            return mapCenter
        }

        if let currentCoordinate = locationService.currentLocation?.coordinate,
           Self.isValidCoordinate(currentCoordinate) {
            return currentCoordinate
        }

        return Self.defaultCoordinate
    }

    private func focusCurrentLocation() {
        Task {
            if let draft = await locationService.captureCurrentLocation() {
                selectedLocationTitle = draft.title
                selectedNamedCoordinate = CLLocationCoordinate2D(latitude: draft.latitude, longitude: draft.longitude)
                moveCamera(
                    to: CLLocationCoordinate2D(latitude: draft.latitude, longitude: draft.longitude),
                    span: 0.012
                )
            }
        }
    }

    private func focusCluster(_ cluster: MapTaskCluster) {
        selectedLocationTitle = cluster.title
        selectedNamedCoordinate = cluster.coordinate
        moveCamera(to: cluster.coordinate, span: 0.012)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    private func focusTaskLocation(_ task: TaskItem) {
        guard let latitude = task.locationLatitude, let longitude = task.locationLongitude else { return }
        let coordinate = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        selectedLocationTitle = task.locationDisplayName
        selectedNamedCoordinate = coordinate
        moveCamera(to: coordinate, span: 0.012)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    private func focusRouteStop(_ stop: MapTodoRouteStop) {
        focusCluster(stop.cluster)
    }

    private func focusNearestNearbyTask() {
        guard let task = nearbyTasks.first else { return }
        if let cluster = clusters.first(where: { cluster in
            cluster.tasks.contains { $0.id == task.id }
        }) {
            focusCluster(cluster)
            return
        }

        guard let latitude = task.locationLatitude, let longitude = task.locationLongitude else { return }
        let coordinate = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        selectedLocationTitle = task.locationDisplayName
        selectedNamedCoordinate = coordinate
        moveCamera(to: coordinate, span: 0.012)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    private func openDirections(to cluster: MapTaskCluster) {
        let stop = routeStops.first { $0.cluster.id == cluster.id }
            ?? MapTodoRouteStop(rank: 1, cluster: cluster, distance: nil)
        startActiveMapRoute(stop)
        calculateInAppRoute(to: cluster.coordinate, title: cluster.title)
    }

    private func startActiveMapRoute(_ stop: MapTodoRouteStop) {
        let route = routeSnapshot(for: stop)
        WidgetDataStore.saveActiveMapTodoRoute(route)
        WidgetDataStore.saveSummary(from: allTasks, focusTitle: "이동: \(route.lockScreenTitle)")
        activeMapRoute = route
        withAnimation(.snappy(duration: 0.22)) {
            isLocationTodoPanelPresented = false
            isSearchPresented = false
            isRouteStepsExpanded = false
        }
        isSearchFocused = false
        WidgetCenter.shared.reloadAllTimelines()

        Task {
            await LiveActivityService.shared.startOrUpdate(
                from: allTasks,
                focusTitle: "이동: \(route.lockScreenTitle)"
            )
        }

        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }

    private func endActiveMapRoute() {
        activeDirections?.cancel()
        WidgetDataStore.clearActiveMapTodoRoute()
        WidgetDataStore.saveSummary(from: allTasks)
        activeMapRoute = nil
        clearInAppRoute()
        WidgetCenter.shared.reloadAllTimelines()

        Task {
            await LiveActivityService.shared.update(from: allTasks)
        }

        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    private func refreshRouteForActiveDestination() {
        guard let route = activeMapRoute else { return }
        let coordinate = CLLocationCoordinate2D(latitude: route.latitude, longitude: route.longitude)
        calculateInAppRoute(to: coordinate, title: route.lockScreenTitle)
    }

    private func calculateInAppRoute(to coordinate: CLLocationCoordinate2D, title: String) {
        activeDirections?.cancel()
        isRouteCalculating = true
        routeMessage = nil
        inAppRouteSummary = nil

        let sourceCoordinate = locationService.currentLocation?.coordinate ?? mapRegion.center
        let request = MKDirections.Request()
        request.source = MKMapItem(placemark: MKPlacemark(coordinate: sourceCoordinate))
        request.destination = MKMapItem(placemark: MKPlacemark(coordinate: coordinate))
        request.transportType = routeTravelMode.transportType
        request.requestsAlternateRoutes = false

        let directions = MKDirections(request: request)
        activeDirections = directions

        Task { @MainActor in
            do {
                let response = try await directions.calculate()
                guard activeDirections === directions else { return }
                guard let route = response.routes.first else {
                    showRouteFailureMessage()
                    return
                }

                let nextRouteID = UUID()
                inAppRouteID = nextRouteID
                inAppRoutePolyline = route.polyline
                inAppRouteMapRect = route.polyline.boundingMapRect.paddedForDisplay
                inAppRouteSummary = InAppRouteSummary(
                    id: nextRouteID,
                    title: title,
                    distanceText: formattedRouteDistance(route.distance) ?? "거리 계산 중",
                    expectedTravelTimeText: formattedTravelTime(route.expectedTravelTime),
                    travelModeTitle: routeTravelMode.title,
                    startText: locationService.currentLocation == nil ? "지도 중심에서 출발" : "현재 위치에서 출발",
                    steps: route.steps.map { step in
                        let stepCoordinate = step.polyline.coordinate
                        return InAppRouteStepSummary(
                            instruction: step.instructions.trimmingCharacters(in: .whitespacesAndNewlines),
                            distanceText: formattedRouteDistance(step.distance) ?? "",
                            latitude: Self.isValidCoordinate(stepCoordinate) ? stepCoordinate.latitude : nil,
                            longitude: Self.isValidCoordinate(stepCoordinate) ? stepCoordinate.longitude : nil
                        )
                    }
                    .filter { !$0.instruction.isEmpty }
                )
                isRouteCalculating = false
                isRouteStepsExpanded = false
                routeMessage = nil
                fitInAppRoute()
            } catch {
                guard activeDirections === directions else { return }
                showRouteFailureMessage()
            }
        }
    }

    private func showRouteFailureMessage() {
        isRouteCalculating = false
        clearInAppRoute(keepsMessage: true)
        routeMessage = "앱 안 경로를 찾지 못했습니다. 이동수단을 바꿔보세요."
    }

    private func clearInAppRoute(keepsMessage: Bool = false) {
        inAppRoutePolyline = nil
        inAppRouteID = nil
        inAppRouteMapRect = nil
        inAppRouteSummary = nil
        isRouteCalculating = false
        isRouteStepsExpanded = false
        if !keepsMessage {
            routeMessage = nil
        }
    }

    private func fitInAppRoute() {
        guard let mapRect = inAppRouteMapRect,
              !mapRect.isNull,
              mapRect.size.width > 0,
              mapRect.size.height > 0 else {
            if let activeMapRoute {
                focusActiveRoute(activeMapRoute)
            }
            return
        }

        let fittedRegion = MKCoordinateRegion(mapRect).normalizedForDisplay
        withAnimation(.snappy(duration: 0.24)) {
            mapRegion = fittedRegion
            cameraPosition = .region(fittedRegion)
            updateMapCenter(fittedRegion.center)
        }
    }

    private func focusActiveRoute(_ route: MapTodoRouteSnapshot) {
        let coordinate = CLLocationCoordinate2D(latitude: route.latitude, longitude: route.longitude)
        selectedLocationTitle = route.lockScreenTitle
        selectedNamedCoordinate = coordinate
        moveCamera(to: coordinate, span: 0.012)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    private func routeSnapshot(for stop: MapTodoRouteStop) -> MapTodoRouteSnapshot {
        MapTodoRouteSnapshot(
            id: UUID(),
            destinationTitle: stop.cluster.title,
            previewText: stop.cluster.previewTitle,
            distanceText: formattedRouteDistance(stop.distance),
            taskCount: stop.cluster.tasks.count,
            stopCount: max(routeStops.count, 1),
            stopRank: stop.rank,
            latitude: stop.cluster.coordinate.latitude,
            longitude: stop.cluster.coordinate.longitude,
            startedAt: .now
        )
    }

    private func estimatedRouteDistance(for stops: [MapTodoRouteStop]) -> CLLocationDistance? {
        guard let currentLocation = locationService.currentLocation else { return nil }
        var totalDistance: CLLocationDistance = 0
        var previousLocation = currentLocation

        for stop in stops {
            let nextLocation = CLLocation(
                latitude: stop.cluster.coordinate.latitude,
                longitude: stop.cluster.coordinate.longitude
            )
            totalDistance += previousLocation.distance(from: nextLocation)
            previousLocation = nextLocation
        }

        return totalDistance
    }

    private func completeNearbyTask(_ task: TaskItem) {
        guard !task.isCompleted else { return }
        let shouldEndRoute = activeMapRoute.map { isTask(task, nearRoute: $0) } ?? false
        viewModel.toggle(task, context: modelContext)
        refreshMapState()

        if shouldEndRoute && !nearbyTasks.contains(where: { !$0.isCompleted && $0.id != task.id }) {
            endActiveMapRoute()
        }

        showArrivalCheckInMessage("\(task.title) 완료")
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }

    private func completeNearbyTasks() {
        let tasksToComplete = nearbyTasks.filter { !$0.isCompleted }
        guard !tasksToComplete.isEmpty else { return }
        let shouldEndRoute = activeMapRoute.map { route in
            tasksToComplete.contains { isTask($0, nearRoute: route) }
        } ?? false

        for task in tasksToComplete {
            viewModel.toggle(task, context: modelContext)
        }

        refreshMapState()
        if shouldEndRoute {
            endActiveMapRoute()
        }

        showArrivalCheckInMessage("근처 할 일 \(tasksToComplete.count)개 완료")
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    private func restoreCompletedLocationTask(_ task: TaskItem) {
        guard task.isCompleted else { return }
        viewModel.toggle(task, context: modelContext)
        refreshMapState()
        showArrivalCheckInMessage("\(task.title) 다시 진행 중")
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }

    private func deleteLocationTask(_ task: TaskItem) {
        let shouldEndRoute = activeMapRoute.map { isTask(task, nearRoute: $0) } ?? false
        viewModel.delete(task, context: modelContext)
        refreshMapState()

        if shouldEndRoute {
            endActiveMapRoute()
        }

        showArrivalCheckInMessage("\(task.title) 삭제됨")
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }

    private func deleteLocationCluster(_ cluster: MapTaskCluster) {
        let tasks = cluster.tasks
        guard !tasks.isEmpty else { return }
        let shouldEndRoute = activeMapRoute.map { route in
            tasks.contains { isTask($0, nearRoute: route) }
        } ?? false

        for task in tasks {
            viewModel.delete(task, context: modelContext)
        }

        refreshMapState()
        if shouldEndRoute {
            endActiveMapRoute()
        }

        showArrivalCheckInMessage("\(tasks.count)개 삭제됨")
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }

    private func completedLocationText(for task: TaskItem) -> String {
        guard let completedAt = task.completedAt else {
            return "완료됨"
        }

        return completedAt.formatted(.dateTime.month().day().hour().minute())
    }

    private func isTask(_ task: TaskItem, nearRoute route: MapTodoRouteSnapshot) -> Bool {
        guard let latitude = task.locationLatitude, let longitude = task.locationLongitude else {
            return false
        }
        let taskLocation = CLLocation(latitude: latitude, longitude: longitude)
        let routeLocation = CLLocation(latitude: route.latitude, longitude: route.longitude)
        return taskLocation.distance(from: routeLocation) <= max(task.locationRadius, 100)
    }

    private func showArrivalCheckInMessage(_ message: String) {
        withAnimation(.snappy(duration: 0.18)) {
            arrivalCheckInMessage = message
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 2.4) {
            guard arrivalCheckInMessage == message else { return }
            withAnimation(.snappy(duration: 0.18)) {
                arrivalCheckInMessage = nil
            }
        }
    }

    private func distance(from location: CLLocation, to coordinate: CLLocationCoordinate2D) -> CLLocationDistance {
        let target = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        return location.distance(from: target)
    }

    private func formattedRouteDistance(_ distance: CLLocationDistance?) -> String? {
        guard let distance else { return nil }
        if distance >= 1_000 {
            return String(format: "%.1fkm", distance / 1_000)
        }
        return "\(Int(distance.rounded()))m"
    }

    private func formattedTravelTime(_ seconds: TimeInterval) -> String {
        let minutes = max(1, Int((seconds / 60).rounded()))
        if minutes < 60 {
            return "\(minutes)분"
        }

        let hours = minutes / 60
        let remainingMinutes = minutes % 60
        if remainingMinutes == 0 {
            return "\(hours)시간"
        }
        return "\(hours)시간 \(remainingMinutes)분"
    }

    private func routePreviewText(for stop: MapTodoRouteStop) -> String {
        let taskCountText = "\(stop.cluster.tasks.count)개 할 일"
        let preview = stop.cluster.previewTitle
        if preview.isEmpty { return taskCountText }
        return "\(taskCountText) · \(preview)"
    }

    private func moveCamera(to coordinate: CLLocationCoordinate2D, span: CLLocationDegrees) {
        withAnimation(.snappy) {
            let region = MKCoordinateRegion(
                center: coordinate,
                span: MKCoordinateSpan(latitudeDelta: span, longitudeDelta: span)
            )
            mapRegion = region
            cameraPosition = .region(region)
            mapCenter = coordinate
        }
    }

    private func assignSelectedTaskToMapCenter() {
        guard let taskToAssign else { return }
        let coordinate = resolvedMapCenter

        taskToAssign.colorHex = TaskTint.normalized(selectedMarkerColorHex)
        taskToAssign.locationTitle = selectedLocationTitle
        taskToAssign.locationLatitude = coordinate.latitude
        taskToAssign.locationLongitude = coordinate.longitude
        taskToAssign.locationRadius = min(max(taskToAssign.locationRadius, 150), 500)
        taskToAssign.locationReminderEnabled = true
        viewModel.update(taskToAssign, context: modelContext)
        refreshMapState()
        LocationReminderService.shared.requestLocationAccess()

        Task {
            _ = await NotificationService.shared.requestAuthorization()
        }

        self.taskToAssign = nil
        withAnimation(.snappy(duration: 0.24)) {
            isLocationTodoPanelPresented = false
        }
    }

    private func selectTaskForMapAssignment(_ task: TaskItem) {
        taskToAssign = task
        selectedMarkerColorHex = task.safeColorHex
    }

    private func updateSelectedMarkerColor(_ colorHex: String) {
        let normalizedColor = TaskTint.normalized(colorHex)
        selectedMarkerColorHex = normalizedColor

        guard let taskToAssign else { return }
        taskToAssign.colorHex = normalizedColor
        viewModel.update(taskToAssign, context: modelContext)
        refreshMapState()
    }

    private func toggleSearchPanel() {
        withAnimation(.snappy) {
            isSearchPresented.toggle()
            if isSearchPresented {
                isLocationTodoPanelPresented = false
                isLocationTodoListExpanded = false
            }
        }

        if isSearchPresented {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
                isSearchFocused = true
            }
        } else {
            isSearchFocused = false
        }
    }

    private func selectSearchResult(_ result: MapLocationSearchResult) {
        Task {
            guard let draft = await searchModel.resolve(result) else { return }
            let coordinate = CLLocationCoordinate2D(latitude: draft.latitude, longitude: draft.longitude)
            selectedLocationTitle = draft.title
            selectedNamedCoordinate = coordinate
            moveCamera(to: coordinate, span: 0.02)
            isSearchFocused = false
            withAnimation(.snappy) {
                isSearchPresented = false
                isLocationTodoPanelPresented = false
                isLocationTodoListExpanded = false
            }
        }
    }

    private func searchTypedLocation() {
        Task {
            guard let draft = await searchModel.resolveTypedQuery() else { return }
            let coordinate = CLLocationCoordinate2D(latitude: draft.latitude, longitude: draft.longitude)
            selectedLocationTitle = draft.title
            selectedNamedCoordinate = coordinate
            moveCamera(to: coordinate, span: 0.02)
            isSearchFocused = false
            withAnimation(.snappy) {
                isSearchPresented = false
                isLocationTodoPanelPresented = false
                isLocationTodoListExpanded = false
            }
        }
    }

    private func updateMapCenter(_ coordinate: CLLocationCoordinate2D) {
        guard Self.isValidCoordinate(coordinate) else { return }
        mapCenter = coordinate

        guard let selectedNamedCoordinate else { return }
        let current = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        let selected = CLLocation(latitude: selectedNamedCoordinate.latitude, longitude: selectedNamedCoordinate.longitude)
        if current.distance(from: selected) > 100 {
            selectedLocationTitle = "지도 위치"
            self.selectedNamedCoordinate = nil
        }
    }

    private static func isValidCoordinate(_ coordinate: CLLocationCoordinate2D) -> Bool {
        CLLocationCoordinate2DIsValid(coordinate)
            && coordinate.latitude.isFinite
            && coordinate.longitude.isFinite
            && (-90...90).contains(coordinate.latitude)
            && (-180...180).contains(coordinate.longitude)
    }

    private func refreshMapState() {
        viewModel.refreshSharedState(allTasks: allTasks)
        locationService.syncMonitoredTasks(allTasks: allTasks)
    }
}

private struct MapFloatingActionButton: View {
    var title: String
    var systemImage: String
    var badgeText: String?
    var isActive: Bool
    var isPrimary: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: isPrimary ? 0 : 7) {
                Image(systemName: systemImage)
                    .font(.system(size: isPrimary ? 20 : 15, weight: .bold))

                if !isPrimary {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)

                    if let badgeText {
                        Text(badgeText)
                            .font(.caption2.weight(.black))
                            .monospacedDigit()
                            .foregroundStyle(isActive ? Color.white : Color.accentColor)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(isActive ? Color.accentColor : Color.accentColor.opacity(0.12), in: Capsule())
                    }
                }
            }
            .foregroundStyle(isPrimary ? Color.white : (isActive ? Color.accentColor : Color.primary))
            .frame(width: isPrimary ? 52 : 154, height: 52)
            .padding(.horizontal, isPrimary ? 0 : 14)
            .background(
                isPrimary
                    ? Color.accentColor
                    : (isActive ? Color.white.opacity(0.96) : Color.white.opacity(0.90)),
                in: Capsule()
            )
            .overlay {
                Capsule()
                    .stroke(isActive ? Color.accentColor.opacity(0.32) : Color.white.opacity(0.48), lineWidth: 1)
            }
            .shadow(color: Color.black.opacity(0.16), radius: 16, x: 0, y: 8)
            .transaction { transaction in
                transaction.animation = nil
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }
}

private struct LockTodoMapCenterMarker: View {
    var body: some View {
        VStack(spacing: -1) {
            ZStack {
                markerBody

                HStack(spacing: 5) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 22, height: 22)
                        .background(Color.accentColor, in: Circle())

                    VStack(alignment: .leading, spacing: 3) {
                        Capsule()
                            .fill(Color.primary.opacity(0.30))
                            .frame(width: 18, height: 3)

                        Capsule()
                            .fill(Color.primary.opacity(0.16))
                            .frame(width: 12, height: 3)
                    }
                }
            }

            Image(systemName: "arrowtriangle.down.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color.white)
                .shadow(color: Color.black.opacity(0.16), radius: 4, x: 0, y: 2)
                .offset(y: -2)

            Circle()
                .fill(Color.accentColor.opacity(0.22))
                .frame(width: 10, height: 10)
                .blur(radius: 1.2)
                .offset(y: -2)
        }
        .frame(width: 62, height: 72)
        .shadow(color: Color.black.opacity(0.18), radius: 16, x: 0, y: 8)
        .accessibilityHidden(true)
    }

    private var markerBody: some View {
        RoundedRectangle(cornerRadius: 19, style: .continuous)
            .fill(Color.white.opacity(0.96))
            .frame(width: 58, height: 42)
            .overlay {
                RoundedRectangle(cornerRadius: 19, style: .continuous)
                    .stroke(Color.accentColor.opacity(0.18), lineWidth: 1)
            }
            .overlay(alignment: .topLeading) {
                Capsule()
                    .fill(Color.white.opacity(0.86))
                    .frame(width: 20, height: 3)
                    .padding(.leading, 13)
                    .padding(.top, 7)
            }
    }
}

private struct MapLocationSearchResult: Identifiable {
    let completion: MKLocalSearchCompletion

    var id: String {
        "\(title)|\(subtitle)"
    }

    var title: String {
        completion.title
    }

    var subtitle: String {
        completion.subtitle
    }
}

private struct MapTodoRouteStop: Identifiable {
    let rank: Int
    let cluster: MapTaskCluster
    let distance: CLLocationDistance?

    var id: String {
        cluster.id
    }
}

private enum MapRouteTravelMode: String, CaseIterable, Identifiable {
    case walking
    case automobile

    var id: String { rawValue }

    var title: String {
        switch self {
        case .walking: "도보"
        case .automobile: "자동차"
        }
    }

    var systemImage: String {
        switch self {
        case .walking: "figure.walk"
        case .automobile: "car.fill"
        }
    }

    var transportType: MKDirectionsTransportType {
        switch self {
        case .walking: .walking
        case .automobile: .automobile
        }
    }
}

private struct InAppRouteStepSummary: Identifiable, Hashable {
    let id = UUID()
    var instruction: String
    var distanceText: String
    var latitude: Double?
    var longitude: Double?

    func distance(from location: CLLocation) -> CLLocationDistance? {
        guard let latitude, let longitude else { return nil }
        return location.distance(from: CLLocation(latitude: latitude, longitude: longitude))
    }
}

private struct InAppRouteSummary: Identifiable, Hashable {
    var id: UUID
    var title: String
    var distanceText: String
    var expectedTravelTimeText: String
    var travelModeTitle: String
    var startText: String
    var steps: [InAppRouteStepSummary]
}

private struct NavigationStepList: View {
    var steps: [InAppRouteStepSummary]

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 7) {
                ForEach(Array(steps.prefix(14).enumerated()), id: \.element.id) { index, step in
                    HStack(alignment: .top, spacing: 10) {
                        Text("\(index + 1)")
                            .font(.caption2.weight(.black))
                            .foregroundStyle(.white)
                            .frame(width: 22, height: 22)
                            .background(Color.accentColor, in: Circle())

                        VStack(alignment: .leading, spacing: 3) {
                            Text(step.instruction)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.primary)
                                .lineLimit(3)

                            if !step.distanceText.isEmpty {
                                Text(step.distanceText)
                                    .font(.caption2.weight(.bold))
                                    .foregroundStyle(.secondary)
                                    .monospacedDigit()
                            }
                        }

                        Spacer(minLength: 0)
                    }
                    .padding(9)
                    .background(Color.white.opacity(0.76), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                }
            }
        }
        .frame(maxHeight: 220)
    }
}

private struct InAppRouteSummaryView: View {
    var summary: InAppRouteSummary
    var isStepsExpanded: Bool
    var onToggleSteps: () -> Void
    var onFitRoute: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 8) {
                routeMetric(summary.expectedTravelTimeText, systemImage: "clock")
                routeMetric(summary.distanceText, systemImage: "point.topleft.down.curvedto.point.bottomright.up")
                routeMetric(summary.travelModeTitle, systemImage: "location.north.line")
            }

            HStack(spacing: 8) {
                Label(summary.startText, systemImage: "location.fill")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Spacer(minLength: 6)

                Button(action: onFitRoute) {
                    Label("전체 보기", systemImage: "arrow.up.left.and.arrow.down.right")
                        .font(.caption2.weight(.bold))
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)
            }

            if let nextStep = summary.steps.first {
                HStack(alignment: .top, spacing: 9) {
                    Image(systemName: "arrow.turn.up.right")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 26, height: 26)
                        .background(Color.accentColor, in: Circle())

                    VStack(alignment: .leading, spacing: 2) {
                        Text("다음 안내")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(Color.accentColor)

                        Text(nextStep.instruction)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(2)
                            .minimumScaleFactor(0.82)

                        if !nextStep.distanceText.isEmpty {
                            Text(nextStep.distanceText)
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                    }

                    Spacer(minLength: 0)
                }
                .padding(9)
                .background(Color.white.opacity(0.82), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
            }

            if !summary.steps.isEmpty {
                Button(action: onToggleSteps) {
                    HStack(spacing: 6) {
                        Label("경로 단계 \(summary.steps.count)개", systemImage: "list.bullet")
                            .font(.caption.weight(.semibold))
                        Spacer(minLength: 8)
                        Image(systemName: "chevron.up")
                            .font(.caption2.weight(.bold))
                            .rotationEffect(.degrees(isStepsExpanded ? 0 : 180))
                    }
                    .foregroundStyle(.primary)
                }
                .buttonStyle(.plain)

                if isStepsExpanded {
                    ScrollView(showsIndicators: false) {
                        VStack(spacing: 6) {
                            ForEach(Array(summary.steps.prefix(12).enumerated()), id: \.element.id) { index, step in
                                HStack(alignment: .top, spacing: 8) {
                                    Text("\(index + 1)")
                                        .font(.caption2.weight(.bold))
                                        .foregroundStyle(.white)
                                        .frame(width: 18, height: 18)
                                        .background(Color.accentColor, in: Circle())

                                    Text(step.instruction)
                                        .font(.caption2)
                                        .foregroundStyle(.primary)
                                        .lineLimit(3)

                                    Spacer(minLength: 6)

                                    if !step.distanceText.isEmpty {
                                        Text(step.distanceText)
                                            .font(.caption2.weight(.semibold))
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 6)
                                .background(Color.white.opacity(0.72), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                            }
                        }
                    }
                    .frame(maxHeight: 190)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
        }
    }

    private func routeMetric(_ text: String, systemImage: String) -> some View {
        Label(text, systemImage: systemImage)
            .font(.caption2.weight(.bold))
            .foregroundStyle(.primary)
            .lineLimit(1)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 8)
            .padding(.vertical, 7)
            .background(Color.white.opacity(0.78), in: Capsule())
    }
}

private struct MapRouteBriefing: Hashable {
    var placeCount: Int
    var taskCount: Int
    var importantCount: Int
    var estimatedDistanceText: String?
}

private struct MapRouteBriefingCard: View {
    var briefing: MapRouteBriefing
    var onStart: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "point.topleft.down.curvedto.point.bottomright.up")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(Color.accentColor)
                .frame(width: 32, height: 32)
                .background(Color.accentColor.opacity(0.10), in: Circle())

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Text("스마트 동선")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.primary)

                    Text(briefing.estimatedDistanceText ?? "위치 확인 중")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                HStack(spacing: 6) {
                    briefingMetric("\(briefing.placeCount)곳", systemImage: "mappin")
                    briefingMetric("\(briefing.taskCount)개", systemImage: "checklist")
                    if briefing.importantCount > 0 {
                        briefingMetric("중요 \(briefing.importantCount)", systemImage: "flag.fill")
                    }
                }
            }

            Spacer(minLength: 6)

            Button(action: onStart) {
                Image(systemName: "arrow.triangle.turn.up.right.diamond.fill")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(width: 32, height: 32)
                    .background(Color.accentColor, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("스마트 동선 시작")
        }
        .padding(10)
        .background(Color.white.opacity(0.88), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func briefingMetric(_ text: String, systemImage: String) -> some View {
        Label(text, systemImage: systemImage)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(Color.primary.opacity(0.05), in: Capsule())
    }
}

private struct MapArrivalCheckInPanel: View {
    var tasks: [TaskItem]
    var totalCount: Int
    var message: String?
    var distanceText: (TaskItem) -> String?
    var onCompleteTask: (TaskItem) -> Void
    var onCompleteAll: () -> Void
    var onFocus: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 9) {
                Image(systemName: "location.fill.viewfinder")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 30, height: 30)
                    .background(Color.green, in: Circle())

                VStack(alignment: .leading, spacing: 1) {
                    Text("도착 체크인")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)

                    Text("지금 위치에서 처리할 할 일 \(totalCount)개")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 8)

                Button(action: onFocus) {
                    Image(systemName: "location.viewfinder")
                        .font(.caption.weight(.bold))
                        .frame(width: 30, height: 30)
                        .background(Color.white.opacity(0.86), in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("근처 할 일 위치 보기")
            }

            VStack(spacing: 6) {
                ForEach(tasks.prefix(3)) { task in
                    Button {
                        onCompleteTask(task)
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "circle")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(Color(hex: task.safeColorHex))

                            Text(task.title)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.primary)
                                .lineLimit(1)

                            Spacer(minLength: 8)

                            if let distance = distanceText(task) {
                                Text(distance)
                                    .font(.caption2.weight(.medium))
                                    .foregroundStyle(.secondary)
                                    .monospacedDigit()
                            }
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(Color.white.opacity(0.76), in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(task.title) 완료")
                }

                if totalCount > 3 {
                    Text("+ \(totalCount - 3)개 더")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 10)
                }
            }

            HStack(spacing: 8) {
                Button(action: onCompleteAll) {
                    Label("근처 모두 완료", systemImage: "checkmark.circle.fill")
                        .font(.caption.weight(.bold))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)

                if let message {
                    Text(message)
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(Color.green)
                        .lineLimit(1)
                        .transition(.opacity.combined(with: .move(edge: .trailing)))
                }
            }
        }
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.green.opacity(0.22), lineWidth: 1)
        }
    }
}

private struct CompletedLocationTaskRow: View {
    let task: TaskItem
    let completedText: String
    let onFocus: () -> Void
    let onRestore: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 9) {
            Button(action: onFocus) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Color(hex: task.safeColorHex))
                    .frame(width: 28, height: 28)
                    .background(Color(hex: task.safeColorHex).opacity(0.10), in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(task.title) 위치 보기")

            Button(action: onFocus) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(task.title)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    Text("\(task.locationDisplayName) · \(completedText)")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)

            Button(action: onRestore) {
                Text("다시")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(Color.accentColor)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 6)
                    .background(Color.accentColor.opacity(0.10), in: Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(task.title) 다시 진행 중으로 변경")

            Button(role: .destructive, action: onDelete) {
                Image(systemName: "trash")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.red)
                    .frame(width: 28, height: 28)
                    .background(Color.red.opacity(0.10), in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(task.title) 삭제")
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 8)
        .background(Color.white.opacity(0.80), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

private struct MapRouteStopRow: View {
    let stop: MapTodoRouteStop
    let distanceText: String?
    let onFocus: () -> Void
    let onDirections: () -> Void
    let onDeleteTask: (TaskItem) -> Void
    let onDeleteCluster: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Button(action: onFocus) {
                Text("\(stop.rank)")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 28, height: 28)
                    .background(Color(hex: stop.cluster.tintColorHex), in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(stop.cluster.title) 지도에서 보기")

            Button(action: onDirections) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(stop.cluster.title)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(1)

                        if let distanceText {
                            Text(distanceText)
                                .font(.caption2.weight(.medium))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }

                    Text("\(stop.cluster.tasks.count)개 · \(stop.cluster.previewTitle)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(stop.cluster.title) 길안내")

            Button(action: onDirections) {
                Image(systemName: "arrow.triangle.turn.up.right.diamond.fill")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Color(hex: stop.cluster.tintColorHex))
                    .frame(width: 30, height: 30)
                    .background(Color.white.opacity(0.8), in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(stop.cluster.title) 길안내")

            Menu {
                ForEach(stop.cluster.tasks) { task in
                    Button(role: .destructive) {
                        onDeleteTask(task)
                    } label: {
                        Label(task.title, systemImage: "trash")
                    }
                }

                if stop.cluster.tasks.count > 1 {
                    Button(role: .destructive, action: onDeleteCluster) {
                        Label("이 위치 모두 삭제", systemImage: "trash.fill")
                    }
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 30, height: 30)
                    .background(Color.white.opacity(0.8), in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(stop.cluster.title) 더 보기")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .background(Color.white.opacity(0.92), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

private struct SwiftUITodoMapContainer: View {
    @Binding var cameraPosition: MapCameraPosition
    var clusters: [MapTaskCluster]
    var nearbyTaskIDs: Set<UUID>
    var routePolyline: MKPolyline?
    var onRegionChanged: (MKCoordinateRegion) -> Void
    var onClusterSelected: (MapTaskCluster) -> Void

    var body: some View {
        Map(position: $cameraPosition, interactionModes: [.pan, .zoom]) {
            UserAnnotation()

            if let routePolyline {
                MapPolyline(routePolyline)
                    .stroke(Color.accentColor.opacity(0.88), lineWidth: 6)
            }

            ForEach(clusters) { cluster in
                Annotation(cluster.title, coordinate: cluster.coordinate, anchor: .bottom) {
                    Button {
                        onClusterSelected(cluster)
                    } label: {
                        MapClusterBadge(
                            count: cluster.tasks.count,
                            title: cluster.title,
                            isNearby: cluster.tasks.contains { nearbyTaskIDs.contains($0.id) }
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(cluster.title) 위치 할 일 \(cluster.tasks.count)개")
                }
            }
        }
        .mapStyle(.standard(elevation: .flat))
        .mapControls {
            MapScaleView()
        }
        .onMapCameraChange(frequency: .onEnd) { context in
            onRegionChanged(context.region.normalizedForDisplay)
        }
        .background(Color.white)
    }
}

private struct NativeTodoMapContainer: View {
    @Binding var region: MKCoordinateRegion
    var clusters: [MapTaskCluster]
    var nearbyTaskIDs: Set<UUID>
    var routePolyline: MKPolyline?
    var routeID: UUID?
    var onVisibleRegionChanged: (MKCoordinateRegion) -> Void
    var onRegionChanged: (MKCoordinateRegion) -> Void
    var onClusterSelected: (MapTaskCluster) -> Void

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size.validMapSize

            NativeTodoMapView(
                viewSize: size,
                region: $region,
                clusters: clusters,
                nearbyTaskIDs: nearbyTaskIDs,
                routePolyline: routePolyline,
                routeID: routeID,
                onVisibleRegionChanged: onVisibleRegionChanged,
                onRegionChanged: onRegionChanged,
                onClusterSelected: onClusterSelected
            )
            .frame(width: size.width, height: size.height)
            .clipped()
        }
    }
}

private struct NativeTodoMapView: UIViewRepresentable {
    var viewSize: CGSize
    @Binding var region: MKCoordinateRegion
    var clusters: [MapTaskCluster]
    var nearbyTaskIDs: Set<UUID>
    var routePolyline: MKPolyline?
    var routeID: UUID?
    var onVisibleRegionChanged: (MKCoordinateRegion) -> Void
    var onRegionChanged: (MKCoordinateRegion) -> Void
    var onClusterSelected: (MapTaskCluster) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIView(context: Context) -> StableNativeMapHostView {
        let initialSize = viewSize.validMapSize
        let hostView = StableNativeMapHostView(frame: CGRect(origin: .zero, size: initialSize))
        let mapView = hostView.mapView
        mapView.delegate = context.coordinator
        mapView.backgroundColor = .white
        mapView.isOpaque = true
        mapView.register(MKMarkerAnnotationView.self, forAnnotationViewWithReuseIdentifier: Coordinator.markerReuseIdentifier)
        mapView.mapType = .standard
        mapView.pointOfInterestFilter = .includingAll
        mapView.showsCompass = false
        mapView.showsScale = true
        mapView.showsUserLocation = true
        mapView.isScrollEnabled = true
        mapView.isZoomEnabled = true
        mapView.isRotateEnabled = true
        mapView.isPitchEnabled = false
        mapView.isMultipleTouchEnabled = true
        mapView.tintColor = .systemBlue
        hostView.preferredContentSize = initialSize

        if #available(iOS 16.0, *) {
            let configuration = MKStandardMapConfiguration(elevationStyle: .flat)
            configuration.pointOfInterestFilter = .includingAll
            mapView.preferredConfiguration = configuration
        }

        hostView.onReadyForRegion = { [weak hostView, weak coordinator = context.coordinator] in
            guard let hostView, let coordinator else { return }
            let mapView = hostView.mapView
            coordinator.syncAnnotations(on: mapView)
            coordinator.syncRouteOverlay(on: mapView)
            coordinator.apply(region: coordinator.parent.region, to: mapView, animated: false)
        }
        return hostView
    }

    func updateUIView(_ hostView: StableNativeMapHostView, context: Context) {
        context.coordinator.parent = self
        hostView.preferredContentSize = viewSize.validMapSize
        hostView.setNeedsLayout()

        let mapView = hostView.mapView
        guard hostView.isReadyForMapRendering else {
            return
        }

        context.coordinator.syncAnnotations(on: mapView)
        context.coordinator.syncRouteOverlay(on: mapView)
        context.coordinator.apply(region: region, to: mapView, animated: context.transaction.animation != nil)
    }

    final class Coordinator: NSObject, MKMapViewDelegate {
        static let markerReuseIdentifier = "TaskClusterMarker"

        var parent: NativeTodoMapView
        private var annotationsByID: [String: MapTaskAnnotation] = [:]
        private var currentRouteID: UUID?
        private var routeOverlay: MKPolyline?
        private var isApplyingRegion = false
        private var lastVisibleRegionUpdate = Date.distantPast
        private var lastPublishedRegion: MKCoordinateRegion?

        init(_ parent: NativeTodoMapView) {
            self.parent = parent
        }

        func apply(region: MKCoordinateRegion, to mapView: MKMapView, animated: Bool) {
            guard mapView.isReadyForMapRendering else { return }
            guard !mapView.isUserChangingRegion else { return }

            let normalizedRegion = region.normalizedForDisplay
            guard !mapView.region.isClose(to: normalizedRegion) else { return }

            isApplyingRegion = true
            mapView.setRegion(normalizedRegion, animated: animated)

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
                self?.isApplyingRegion = false
            }
        }

        func syncRouteOverlay(on mapView: MKMapView) {
            guard mapView.isReadyForMapRendering else { return }
            guard currentRouteID != parent.routeID else { return }

            if let routeOverlay {
                mapView.removeOverlay(routeOverlay)
            }
            routeOverlay = nil
            currentRouteID = parent.routeID

            if let polyline = parent.routePolyline {
                routeOverlay = polyline
                mapView.addOverlay(polyline, level: .aboveRoads)
            }
        }

        func syncAnnotations(on mapView: MKMapView) {
            guard mapView.isReadyForMapRendering else { return }

            let nextIDs = Set(parent.clusters.map(\.id))
            let staleIDs = Set(annotationsByID.keys).subtracting(nextIDs)
            let staleAnnotations = staleIDs.compactMap { annotationsByID.removeValue(forKey: $0) }
            mapView.removeAnnotations(staleAnnotations)

            for cluster in parent.clusters {
                let isNearby = cluster.tasks.contains { parent.nearbyTaskIDs.contains($0.id) }

                if let annotation = annotationsByID[cluster.id] {
                    annotation.update(cluster: cluster, isNearby: isNearby)
                    if let view = mapView.view(for: annotation) as? MKMarkerAnnotationView {
                        configure(view, for: annotation)
                    }
                } else {
                    let annotation = MapTaskAnnotation(cluster: cluster, isNearby: isNearby)
                    annotationsByID[cluster.id] = annotation
                    mapView.addAnnotation(annotation)
                }
            }
        }

        func mapViewDidChangeVisibleRegion(_ mapView: MKMapView) {
            guard !isApplyingRegion else { return }

            let now = Date()
            guard now.timeIntervalSince(lastVisibleRegionUpdate) > 0.20 else { return }
            lastVisibleRegionUpdate = now
            publish(region: mapView.region, updatesBinding: false)
        }

        func mapView(_ mapView: MKMapView, regionDidChangeAnimated animated: Bool) {
            guard !isApplyingRegion else { return }
            publish(region: mapView.region, updatesBinding: true)
        }

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            guard let annotation = annotation as? MapTaskAnnotation else { return nil }

            let view = mapView.dequeueReusableAnnotationView(
                withIdentifier: Self.markerReuseIdentifier,
                for: annotation
            ) as? MKMarkerAnnotationView ?? MKMarkerAnnotationView(
                annotation: annotation,
                reuseIdentifier: Self.markerReuseIdentifier
            )

            configure(view, for: annotation)
            return view
        }

        func mapView(_ mapView: MKMapView, didSelect annotation: MKAnnotation) {
            guard let annotation = annotation as? MapTaskAnnotation else { return }
            mapView.deselectAnnotation(annotation, animated: true)
            parent.onClusterSelected(annotation.cluster)
        }

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            guard let polyline = overlay as? MKPolyline else {
                return MKOverlayRenderer(overlay: overlay)
            }

            let renderer = MKPolylineRenderer(polyline: polyline)
            renderer.strokeColor = UIColor.systemBlue.withAlphaComponent(0.88)
            renderer.lineWidth = 6
            renderer.lineJoin = .round
            renderer.lineCap = .round
            return renderer
        }

        private func configure(_ view: MKMarkerAnnotationView, for annotation: MapTaskAnnotation) {
            view.annotation = annotation
            view.canShowCallout = false
            view.markerTintColor = annotation.isNearby ? .systemGreen : UIColor(Color(hex: annotation.cluster.tintColorHex))
            view.glyphTintColor = .white
            view.glyphText = annotation.cluster.tasks.count > 99 ? "99+" : "\(annotation.cluster.tasks.count)"
            view.titleVisibility = .hidden
            view.subtitleVisibility = .hidden
            view.displayPriority = .required
            view.animatesWhenAdded = true
        }

        private func publish(region: MKCoordinateRegion, updatesBinding: Bool) {
            let normalizedRegion = region.normalizedForDisplay
            if !updatesBinding, let lastPublishedRegion, lastPublishedRegion.isClose(to: normalizedRegion) {
                return
            }

            if updatesBinding {
                parent.region = normalizedRegion
                parent.onRegionChanged(normalizedRegion)
            } else {
                lastPublishedRegion = normalizedRegion
                parent.onVisibleRegionChanged(normalizedRegion)
            }
        }
    }
}

private final class StableNativeMapHostView: UIView {
    let mapView: MKMapView
    var onReadyForRegion: (() -> Void)?
    var preferredContentSize = CGSize(width: 390, height: 700)
    private var didNotifyReady = false

    override init(frame: CGRect) {
        let safeFrame = CGRect(origin: .zero, size: frame.size.validMapSize)
        mapView = MKMapView(frame: safeFrame)
        super.init(frame: frame)
        backgroundColor = .white
        isOpaque = true
        clipsToBounds = true
        addSubview(mapView)
    }

    required init?(coder: NSCoder) {
        mapView = MKMapView(frame: CGRect(origin: .zero, size: CGSize(width: 390, height: 700)))
        super.init(coder: coder)
        backgroundColor = .white
        isOpaque = true
        clipsToBounds = true
        addSubview(mapView)
    }

    var isReadyForMapRendering: Bool {
        window != nil && mapView.bounds.width > 16 && mapView.bounds.height > 16
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let safeSize = bounds.size.validMapSize
        mapView.frame = CGRect(origin: .zero, size: safeSize)

        if window != nil, !didNotifyReady {
            didNotifyReady = true
            onReadyForRegion?()
        }
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()

        if window == nil {
            didNotifyReady = false
        } else if isReadyForMapRendering, !didNotifyReady {
            didNotifyReady = true
            onReadyForRegion?()
        }
    }
}

private extension MKMapView {
    var isReadyForMapRendering: Bool {
        window != nil && bounds.width > 16 && bounds.height > 16
    }

    var isUserChangingRegion: Bool {
        gestureRecognizers?.contains { recognizer in
            recognizer.state == .began || recognizer.state == .changed
        } ?? false
    }
}

private final class MapTaskAnnotation: NSObject, MKAnnotation {
    dynamic private(set) var coordinate: CLLocationCoordinate2D
    private(set) var cluster: MapTaskCluster
    private(set) var isNearby: Bool

    var title: String? {
        cluster.title
    }

    init(cluster: MapTaskCluster, isNearby: Bool) {
        self.coordinate = cluster.coordinate
        self.cluster = cluster
        self.isNearby = isNearby
        super.init()
    }

    func update(cluster: MapTaskCluster, isNearby: Bool) {
        self.cluster = cluster
        self.isNearby = isNearby

        if abs(coordinate.latitude - cluster.coordinate.latitude) > 0.000001
            || abs(coordinate.longitude - cluster.coordinate.longitude) > 0.000001 {
            coordinate = cluster.coordinate
        }
    }
}

@MainActor
private final class MapLocationSearchModel: NSObject, ObservableObject, MKLocalSearchCompleterDelegate {
    @Published var query = "" {
        didSet {
            updateCompleterQuery()
        }
    }
    @Published var results: [MapLocationSearchResult] = []
    @Published var isResolving = false
    @Published var message: String?

    private let completer = MKLocalSearchCompleter()
    private var activeSearch: MKLocalSearch?

    override init() {
        super.init()
        completer.delegate = self
        completer.resultTypes = [.address, .pointOfInterest]
    }

    func clear() {
        activeSearch?.cancel()
        query = ""
        results = []
        message = nil
        isResolving = false
    }

    func resolve(_ result: MapLocationSearchResult) async -> TaskLocationDraft? {
        activeSearch?.cancel()
        isResolving = true
        defer { isResolving = false }

        let request = MKLocalSearch.Request(completion: result.completion)
        return await resolve(request: request, fallbackTitle: result.title)
    }

    func resolveTypedQuery() async -> TaskLocationDraft? {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else { return nil }

        if let firstResult = results.first {
            return await resolve(firstResult)
        }

        activeSearch?.cancel()
        isResolving = true
        defer { isResolving = false }

        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = trimmedQuery
        return await resolve(request: request, fallbackTitle: trimmedQuery)
    }

    nonisolated func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        let nextResults = completer.results.map(MapLocationSearchResult.init(completion:))
        Task { @MainActor in
            results = nextResults
            if nextResults.isEmpty && !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                message = "검색 결과가 없습니다."
            } else if message == "검색 결과가 없습니다." {
                message = nil
            }
        }
    }

    nonisolated func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        Task { @MainActor in
            results = []
            message = "검색 결과를 불러올 수 없습니다."
        }
    }

    private func updateCompleterQuery() {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        message = nil

        guard !trimmedQuery.isEmpty else {
            completer.queryFragment = ""
            results = []
            return
        }

        completer.queryFragment = trimmedQuery
    }

    private func resolve(request: MKLocalSearch.Request, fallbackTitle: String) async -> TaskLocationDraft? {
        let search = MKLocalSearch(request: request)
        activeSearch = search

        do {
            let response = try await search.start()
            guard let mapItem = response.mapItems.first else {
                message = "위치를 찾을 수 없습니다."
                return nil
            }

            let draft = draft(from: mapItem, fallbackTitle: fallbackTitle)
            query = draft.title
            results = []
            message = nil
            return draft
        } catch {
            if (error as NSError).code != NSUserCancelledError {
                message = "위치를 찾을 수 없습니다."
            }
            return nil
        }
    }

    private func draft(from mapItem: MKMapItem, fallbackTitle: String) -> TaskLocationDraft {
        let title = mapItem.name?.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanFallback = fallbackTitle.trimmingCharacters(in: .whitespacesAndNewlines)

        return TaskLocationDraft(
            title: title?.isEmpty == false ? title! : cleanFallback,
            latitude: mapItem.placemark.coordinate.latitude,
            longitude: mapItem.placemark.coordinate.longitude,
            radius: 150
        )
    }
}

private struct MapClusterBadge: View {
    var count: Int
    var title: String
    var isNearby: Bool

    var body: some View {
        VStack(spacing: 4) {
            Text("\(count)")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 34, height: 34)
                .background(isNearby ? Color.green : Color.accentColor, in: Circle())
                .overlay {
                    Circle()
                        .stroke(Color.white, lineWidth: 3)
                }
                .shadow(color: .black.opacity(0.22), radius: 6, x: 0, y: 3)

            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(.regularMaterial, in: Capsule())
        }
        .frame(width: 92)
    }
}

private struct MapTaskClusterSheet: View {
    @Environment(\.modelContext) private var modelContext

    var cluster: MapTaskCluster
    @ObservedObject var viewModel: TaskViewModel
    var allTasks: [TaskItem]
    var onDirections: () -> Void
    var onDismiss: () -> Void
    var onDelete: (TaskItem) -> Void
    var onRefresh: () -> Void

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button(action: onDirections) {
                        Label("이 위치로 길찾기", systemImage: "arrow.triangle.turn.up.right.diamond.fill")
                            .font(.body.weight(.semibold))
                    }
                }

                Section {
                    ForEach(cluster.tasks) { task in
                        HStack(alignment: .top, spacing: 12) {
                            let taskColor = Color(hex: task.safeColorHex)

                            Button {
                                task.markCompleted(!task.isCompleted)
                                viewModel.update(task, context: modelContext)
                                onRefresh()
                            } label: {
                                Image(systemName: task.isCompleted ? "checkmark.circle.fill" : "circle")
                                    .font(.title3)
                                    .foregroundStyle(task.isCompleted ? taskColor : taskColor.opacity(0.72))
                            }
                            .buttonStyle(.plain)

                            VStack(alignment: .leading, spacing: 4) {
                                Text(task.title)
                                    .font(.body.weight(task.isImportant ? .semibold : .regular))
                                    .strikethrough(task.isCompleted)
                                    .foregroundStyle(task.isCompleted ? .secondary : .primary)

                                HStack(spacing: 8) {
                                    Label(task.locationDisplayName, systemImage: "mappin.circle")
                                    if let dueTime = task.dueTime {
                                        Label(dueTime.formatted(date: .omitted, time: .shortened), systemImage: "clock")
                                    }
                                }
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            }

                            Spacer(minLength: 8)

                            Menu {
                                ForEach(TaskTint.allCases) { tint in
                                    Button {
                                        task.colorHex = tint.rawValue
                                        viewModel.update(task, context: modelContext)
                                        onRefresh()
                                    } label: {
                                        Label(tint.title, systemImage: TaskTint.normalized(task.colorHex) == tint.rawValue ? "checkmark.circle.fill" : "circle.fill")
                                    }
                                }
                            } label: {
                                Image(systemName: "paintpalette.fill")
                                    .font(.subheadline.weight(.bold))
                                    .foregroundStyle(taskColor)
                                    .frame(width: 30, height: 30)
                                    .background(taskColor.opacity(0.12), in: Circle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("마커 색 변경")
                        }
                        .padding(.vertical, 4)
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) {
                                onDelete(task)
                            } label: {
                                Label("삭제", systemImage: "trash")
                            }
                        }
                        .contextMenu {
                            Button(role: .destructive) {
                                onDelete(task)
                            } label: {
                                Label("삭제", systemImage: "trash")
                            }
                        }
                    }
                } header: {
                    Text("\(cluster.tasks.count)개")
                }
            }
            .navigationTitle(cluster.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("닫기", action: onDismiss)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

struct MapTaskCluster: Identifiable {
    let id: String
    let coordinate: CLLocationCoordinate2D
    let tasks: [TaskItem]

    init(coordinate: CLLocationCoordinate2D, tasks: [TaskItem]) {
        self.id = Self.key(latitude: coordinate.latitude, longitude: coordinate.longitude)
        self.coordinate = coordinate
        self.tasks = tasks
    }

    var title: String {
        let names = Set(tasks.map(\.locationDisplayName))
        if names.count == 1, let name = names.first {
            return name
        }
        return "지도 위치"
    }

    var tintColorHex: String {
        tasks.first?.safeColorHex ?? TaskTint.defaultHex
    }

    var previewTitle: String {
        tasks
            .prefix(2)
            .map(\.title)
            .joined(separator: ", ")
    }

    static func key(latitude: Double, longitude: Double) -> String {
        "\(latitude.rounded(toPlaces: 5)):\(longitude.rounded(toPlaces: 5))"
    }
}

private extension Double {
    func rounded(toPlaces places: Int) -> Double {
        let divisor = pow(10.0, Double(places))
        return (self * divisor).rounded() / divisor
    }
}

private extension CGSize {
    var validMapSize: CGSize {
        CGSize(
            width: max(width.isFinite ? width : 0, 320),
            height: max(height.isFinite ? height : 0, 480)
        )
    }
}

private extension MKCoordinateRegion {
    var normalizedForDisplay: MKCoordinateRegion {
        let safeLatitude = center.latitude.isFinite ? min(max(center.latitude, -90), 90) : 37.5665
        let safeLongitude = center.longitude.isFinite ? min(max(center.longitude, -180), 180) : 126.9780
        let safeLatitudeDelta = span.latitudeDelta.isFinite ? max(abs(span.latitudeDelta), 0.001) : 0.04
        let safeLongitudeDelta = span.longitudeDelta.isFinite ? max(abs(span.longitudeDelta), 0.001) : 0.04

        return MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: safeLatitude, longitude: safeLongitude),
            span: MKCoordinateSpan(latitudeDelta: safeLatitudeDelta, longitudeDelta: safeLongitudeDelta)
        )
    }

    func isClose(to other: MKCoordinateRegion) -> Bool {
        abs(center.latitude - other.center.latitude) < 0.00001
            && abs(center.longitude - other.center.longitude) < 0.00001
            && abs(span.latitudeDelta - other.span.latitudeDelta) < 0.00001
            && abs(span.longitudeDelta - other.span.longitudeDelta) < 0.00001
    }

    func snapshotKey(size: CGSize) -> String {
        let normalized = normalizedForDisplay
        return String(
            format: "%.5f:%.5f:%.5f:%.5f:%d:%d",
            normalized.center.latitude,
            normalized.center.longitude,
            normalized.span.latitudeDelta,
            normalized.span.longitudeDelta,
            Int(size.width),
            Int(size.height)
        )
    }
}

private extension MKMapRect {
    var paddedForDisplay: MKMapRect {
        guard !isNull, size.width > 0, size.height > 0 else { return self }
        let horizontalPadding = max(size.width * 0.22, 420)
        let verticalPadding = max(size.height * 0.30, 520)
        return insetBy(dx: -horizontalPadding, dy: -verticalPadding)
    }
}

private extension MKCoordinateSpan {
    var clamped: MKCoordinateSpan {
        MKCoordinateSpan(
            latitudeDelta: min(max(abs(latitudeDelta), 0.001), 80),
            longitudeDelta: min(max(abs(longitudeDelta), 0.001), 160)
        )
    }
}
