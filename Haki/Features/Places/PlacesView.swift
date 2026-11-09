//
//  PlacesView.swift
//  Haki
//
//  "Eat nearby": restaurants, cafés and grocery stores around the person
//  (or any area they type) from Apple Maps search, on a map and in a list.
//  Picking a place opens its menu with Haki's healthy picks (`MenuView`).
//

import CoreLocation
import Foundation
import MapKit
import SwiftUI
import UIKit

struct PlacesView: View {
    @Environment(\.openURL) private var openURL

    @State private var locator = PlacesLocator()
    @State private var searchText = ""
    @State private var selectedShortcut: PlacesShortcut?
    @State private var results: [PlacesPlace] = []
    @State private var phase: PlacesSearchPhase = .idle
    @State private var resultsTitle = "Restaurants near you"
    @State private var displayMode: PlacesDisplayMode = .list
    @State private var position: MapCameraPosition = .userLocation(fallback: .automatic)
    @State private var visibleRegion: MKCoordinateRegion?
    @State private var selectedPlaceID: String?
    @State private var searchAttempt = 0
    /// The last search that ran to the end, so coming back from a menu
    /// doesn't search again.
    @State private var completedKey: PlacesSearchKey?
    /// How that search ended, restored if a newer search is abandoned part-way.
    @State private var completedPhase: PlacesSearchPhase = .idle
    /// Typed text already searched; a retry of the same text skips the debounce.
    @State private var lastSearchedText = ""

    var body: some View {
        VStack(spacing: 0) {
            header
            switch displayMode {
            case .list:
                listContent
            case .map:
                fullMap
            }
        }
        .background(Color.hakiBackground)
        .navigationTitle("Eat nearby")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(
            text: $searchText,
            placement: .navigationBarDrawer(displayMode: .always),
            prompt: "Food, a place or an area"
        )
        .onAppear { locator.start() }
        .task(id: searchKey) { await search(searchKey) }
        .onChange(of: searchText) { _, newValue in
            // Typing replaces the shortcut.
            let typed = !newValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            if typed, selectedShortcut != nil {
                selectedShortcut = nil
            }
        }
    }

    // MARK: Header

    private var header: some View {
        VStack(spacing: 10) {
            shortcutBar
            locationNotice
            Picker("Show places as", selection: $displayMode) {
                ForEach(PlacesDisplayMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
        }
        .padding(.top, 8)
        .padding(.bottom, 10)
    }

    private var shortcutBar: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(PlacesShortcut.allCases) { shortcut in
                    PlacesChipButton(
                        title: shortcut.title,
                        systemImage: shortcut.systemImage,
                        isSelected: selectedShortcut == shortcut
                    ) {
                        toggle(shortcut)
                    }
                }
            }
            .padding(.horizontal)
        }
        .scrollIndicators(.hidden)
    }

    @ViewBuilder
    private var locationNotice: some View {
        if locator.isDenied {
            PlacesNoticeCard(
                systemImage: "location.slash.fill",
                title: "Location is off for Haki",
                message: "Turn it on in Settings to see places near you, or search for a place or an area.",
                actionTitle: "Open Settings",
                action: { openSettings() }
            )
        } else if let message = locator.errorMessage {
            PlacesNoticeCard(
                systemImage: "location.magnifyingglass",
                title: "Location unavailable",
                message: message,
                actionTitle: "Try again",
                action: { locator.requestLocation() }
            )
        }
    }

    // MARK: List

    private var listContent: some View {
        ScrollView {
            VStack(spacing: 16) {
                mapPreview
                resultsContent
                footnote
            }
            .padding(.horizontal)
            .padding(.bottom)
        }
    }

    private var mapPreview: some View {
        Map(position: $position, interactionModes: []) {
            // Small dots: full pins would pile up in the 180 pt frame. The
            // expand button opens the full map, which has the tappable pins.
            UserAnnotation()
            ForEach(results, id: \.id) { place in
                Annotation(place.name, coordinate: place.coordinate) {
                    PlacesMapDot(isSelected: place.id == selectedPlaceID)
                }
                .annotationTitles(.hidden)
            }
        }
        .frame(height: 180)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .onMapCameraChange(frequency: .onEnd) { context in
            visibleRegion = context.region
        }
        .overlay(alignment: .topTrailing) {
            Button {
                withAnimation(.snappy) { displayMode = .map }
            } label: {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .padding(10)
                    .background(.regularMaterial, in: Circle())
            }
            .buttonStyle(.plain)
            .padding(10)
            .accessibilityLabel("Show full map")
        }
    }

    @ViewBuilder
    private var resultsContent: some View {
        if results.isEmpty {
            emptyContent
        } else {
            resultsCard
        }
    }

    private var resultsCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                CardHeader(resultsTitle)
                if phase == .searching {
                    ProgressView()
                        .controlSize(.small)
                        .accessibilityLabel("Searching")
                }
            }
            Text(countText)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .padding(.top, 2)
                .padding(.bottom, 4)
            ForEach(Array(results.enumerated()), id: \.offset) { index, place in
                if index > 0 {
                    Divider()
                        .padding(.leading, 52)
                }
                NavigationLink {
                    MenuView(place: place)
                } label: {
                    PlacesResultRow(place: place)
                }
                .buttonStyle(.plain)
            }
        }
        .hakiCard()
    }

    private var countText: String {
        let count = results.count == 1 ? "1 place" : "\(results.count) places"
        return locator.location == nil ? count : "\(count) · nearest first"
    }

    @ViewBuilder
    private var emptyContent: some View {
        switch phase {
        case .searching:
            PlacesStatusView(message: "Searching nearby…")
        case .failed(let message):
            ContentUnavailableView {
                Label("Couldn't search right now", systemImage: "wifi.exclamationmark")
            } description: {
                Text(message)
            } actions: {
                Button("Try again") {
                    searchAttempt += 1
                }
                .buttonStyle(.borderedProminent)
            }
        case .loaded:
            ContentUnavailableView {
                Label("No places found", systemImage: "fork.knife")
            } description: {
                Text("Nothing matched here. Try another search, or move the map and search that area.")
            }
        case .idle:
            idleContent
        }
    }

    @ViewBuilder
    private var idleContent: some View {
        if locator.isLocating {
            PlacesStatusView(message: "Finding places near you…")
        } else {
            ContentUnavailableView {
                Label("Find healthy food nearby", systemImage: "fork.knife.circle")
            } description: {
                Text("Search for a restaurant, a dish or an area, like “salads in Austin”, or pick a shortcut above.")
            }
        }
    }

    private var footnote: some View {
        Text("Places come from Apple Maps. Menus, calories and protein come from Haki's AI and are estimates.")
            .font(.footnote)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(.top, 4)
    }

    // MARK: Map

    /// The full map's tappable pins (the list-mode preview draws dots instead).
    @MapContentBuilder
    private var mapAnnotations: some MapContent {
        UserAnnotation()
        ForEach(results, id: \.id) { place in
            Annotation(place.name, coordinate: place.coordinate) {
                PlacesMapPin(
                    name: place.name,
                    systemImage: place.systemImage,
                    isSelected: place.id == selectedPlaceID
                ) {
                    select(place)
                }
            }
        }
    }

    private var fullMap: some View {
        Map(position: $position) {
            mapAnnotations
        }
        .mapControls {
            MapUserLocationButton()
            MapCompass()
            MapScaleView()
        }
        .onMapCameraChange(frequency: .onEnd) { context in
            visibleRegion = context.region
        }
        .overlay(alignment: .top) {
            searchAreaButton
        }
        .safeAreaInset(edge: .bottom) {
            mapFooter
        }
    }

    @ViewBuilder
    private var searchAreaButton: some View {
        if canSearchArea {
            Button {
                searchAttempt += 1
            } label: {
                HStack(spacing: 6) {
                    if phase == .searching {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(systemName: "arrow.clockwise")
                            .accessibilityHidden(true)
                    }
                    Text("Search this area")
                }
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(.regularMaterial, in: Capsule())
            }
            .buttonStyle(.plain)
            .disabled(phase == .searching)
            .padding(.top, 10)
        }
    }

    @ViewBuilder
    private var mapFooter: some View {
        if let place = selectedPlace {
            NavigationLink {
                MenuView(place: place)
            } label: {
                PlacesResultRow(place: place)
            }
            .buttonStyle(.plain)
            .hakiCard(padding: 12)
            .shadow(color: Color.black.opacity(0.15), radius: 10, y: 2)
            .padding(.horizontal)
            .padding(.bottom, 8)
        } else if !results.isEmpty {
            Text("Tap a pin to see that place's menu")
                .font(.footnote.weight(.medium))
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(.regularMaterial, in: Capsule())
                .padding(.bottom, 8)
        } else if let message = failureMessage {
            Text(message)
                .font(.footnote.weight(.medium))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(.regularMaterial, in: Capsule())
                .padding(.horizontal)
                .padding(.bottom, 8)
        }
    }

    /// Something to search for, or a map area small enough to look for
    /// restaurants in (also when location is off).
    private var canSearchArea: Bool {
        if plan(for: searchKey) != nil { return true }
        guard let visibleRegion else { return false }
        return visibleRegion.span.latitudeDelta > 0 && visibleRegion.span.latitudeDelta < 1.5
    }

    private var failureMessage: String? {
        if case .failed(let message) = phase { return message }
        return nil
    }

    private var selectedPlace: PlacesPlace? {
        guard let selectedPlaceID else { return nil }
        return results.first { $0.id == selectedPlaceID }
    }

    // MARK: Actions

    private func toggle(_ shortcut: PlacesShortcut) {
        if selectedShortcut == shortcut {
            selectedShortcut = nil
        } else {
            selectedShortcut = shortcut
            searchText = ""
        }
    }

    private func select(_ place: PlacesPlace) {
        withAnimation(.snappy) {
            selectedPlaceID = place.id
            displayMode = .map
        }
    }

    private func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        openURL(url)
    }

    // MARK: Search

    private var searchKey: PlacesSearchKey {
        PlacesSearchKey(
            text: searchText.trimmingCharacters(in: .whitespacesAndNewlines),
            shortcut: selectedShortcut,
            hasLocation: locator.location != nil,
            attempt: searchAttempt
        )
    }

    /// What to search for: typed text first, then the shortcut, then
    /// restaurants around the person once their location is known.
    private func plan(for key: PlacesSearchKey) -> PlacesSearchPlan? {
        if !key.text.isEmpty {
            return PlacesSearchPlan(query: key.text, title: "Results for “\(key.text)”", categories: PlacesShortcut.foodCategories)
        }
        if let shortcut = key.shortcut {
            return PlacesSearchPlan(query: shortcut.query, title: shortcut.resultsTitle, categories: shortcut.categories)
        }
        if key.hasLocation || key.attempt > 0 {
            // A tap on "Search this area" (or "Try again") works without the
            // person's location too: it searches the map's visible area.
            let title = key.attempt > 0 ? "Restaurants in this area" : "Restaurants near you"
            return PlacesSearchPlan(query: "restaurants", title: title, categories: PlacesShortcut.foodCategories)
        }
        return nil
    }

    private func search(_ key: PlacesSearchKey) async {
        guard key != completedKey else {
            // A newer search was abandoned part-way (its results never
            // replaced these); show how this one ended again.
            if phase == .searching {
                phase = completedPhase
            }
            return
        }
        guard let searchPlan = plan(for: key) else {
            results = []
            selectedPlaceID = nil
            phase = .idle
            completedKey = key
            completedPhase = .idle
            return
        }
        if !key.text.isEmpty, key.text != lastSearchedText {
            // Debounce typing; a newer keystroke cancels this task.
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
        }

        phase = .searching
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = searchPlan.query
        request.resultTypes = .pointOfInterest
        request.pointOfInterestFilter = MKPointOfInterestFilter(including: searchPlan.categories)
        if let region = searchRegion() {
            request.region = region
        }
        let userLocation = locator.location

        do {
            let response = try await MKLocalSearch(request: request).start()
            // A newer search replaced this one; drop its results.
            guard !Task.isCancelled else { return }
            let found: [PlacesPlace] = response.mapItems.map { PlacesPlace(mapItem: $0, userLocation: userLocation) }
            var seen = Set<String>()
            let unique = found.filter { seen.insert($0.id).inserted }
            let nearestFirst = unique.sorted { lhs, rhs in
                (lhs.distanceMeters ?? Double.greatestFiniteMagnitude) < (rhs.distanceMeters ?? Double.greatestFiniteMagnitude)
            }
            show(Array(nearestFirst.prefix(25)), title: searchPlan.title)
        } catch {
            guard !Task.isCancelled else { return }
            if PlacesSearchError.isNoResults(error) {
                show([], title: searchPlan.title)
            } else {
                results = []
                selectedPlaceID = nil
                phase = .failed(PlacesSearchError.message(for: error))
            }
        }
        lastSearchedText = key.text
        completedKey = key
        completedPhase = phase
    }

    private func show(_ places: [PlacesPlace], title: String) {
        results = places
        resultsTitle = title
        phase = .loaded
        if let current = selectedPlaceID, !places.contains(where: { $0.id == current }) {
            selectedPlaceID = nil
        }
        if let region = PlacesMapFraming.region(fitting: places) {
            withAnimation(.snappy) {
                position = .region(region)
            }
        }
    }

    /// The visible map area when it's a sensible size, else around the person.
    private func searchRegion() -> MKCoordinateRegion? {
        if let visibleRegion, visibleRegion.span.latitudeDelta > 0, visibleRegion.span.latitudeDelta < 1.5 {
            // The small list-mode map shows a narrow area; search at least a few km.
            let span = MKCoordinateSpan(
                latitudeDelta: max(visibleRegion.span.latitudeDelta, 0.04),
                longitudeDelta: max(visibleRegion.span.longitudeDelta, 0.04)
            )
            return MKCoordinateRegion(center: visibleRegion.center, span: span)
        }
        if let location = locator.location {
            return MKCoordinateRegion(center: location.coordinate, latitudinalMeters: 8_000, longitudinalMeters: 8_000)
        }
        return nil
    }
}

// MARK: - Search model

private enum PlacesSearchPhase: Equatable {
    case idle
    case searching
    case loaded
    case failed(String)
}

private enum PlacesDisplayMode: String, CaseIterable, Identifiable {
    case list, map

    var id: String { rawValue }

    var title: String {
        switch self {
        case .list: "List"
        case .map: "Map"
        }
    }
}

/// Everything that should start a new search when it changes.
private struct PlacesSearchKey: Equatable {
    var text: String
    var shortcut: PlacesShortcut?
    var hasLocation: Bool
    var attempt: Int
}

private struct PlacesSearchPlan {
    var query: String
    var title: String
    var categories: [MKPointOfInterestCategory]
}

/// One-tap searches above the results.
private enum PlacesShortcut: String, CaseIterable, Identifiable {
    case healthy, salads, proteinBowls, coffee, groceries, fastFood

    var id: String { rawValue }

    /// Every kind of food place Haki searches by default.
    static let foodCategories: [MKPointOfInterestCategory] = [.restaurant, .cafe, .bakery, .foodMarket, .brewery, .winery]

    var title: String {
        switch self {
        case .healthy: "Healthy"
        case .salads: "Salads"
        case .proteinBowls: "Protein bowls"
        case .coffee: "Coffee"
        case .groceries: "Groceries"
        case .fastFood: "Fast food"
        }
    }

    var systemImage: String {
        switch self {
        case .healthy: "leaf.fill"
        case .salads: "carrot.fill"
        case .proteinBowls: "bolt.fill"
        case .coffee: "cup.and.saucer.fill"
        case .groceries: "cart.fill"
        case .fastFood: "takeoutbag.and.cup.and.straw.fill"
        }
    }

    var query: String {
        switch self {
        case .healthy: "healthy food"
        case .salads: "salads"
        case .proteinBowls: "protein bowls"
        case .coffee: "coffee"
        case .groceries: "grocery store"
        case .fastFood: "fast food"
        }
    }

    var resultsTitle: String {
        switch self {
        case .healthy: "Healthy food nearby"
        case .salads: "Salads nearby"
        case .proteinBowls: "Protein bowls nearby"
        case .coffee: "Coffee nearby"
        case .groceries: "Groceries nearby"
        case .fastFood: "Fast food nearby"
        }
    }

    var categories: [MKPointOfInterestCategory] {
        switch self {
        case .healthy, .salads, .proteinBowls: [.restaurant, .cafe, .foodMarket]
        case .coffee: [.cafe, .bakery]
        case .groceries: [.foodMarket]
        case .fastFood: [.restaurant]
        }
    }
}

private enum PlacesSearchError {
    /// Apple Maps reports "no results" as an error (MKError.placemarkNotFound).
    static func isNoResults(_ error: any Error) -> Bool {
        let nsError = error as NSError
        return nsError.domain == "MKErrorDomain" && nsError.code == 4
    }

    static func message(for error: any Error) -> String {
        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain {
            return "You're offline. Check your connection and try again."
        }
        if nsError.domain == "MKErrorDomain" && nsError.code == 3 {
            // MKError.loadingThrottled
            return "That's a lot of searches in a row. Wait a moment and try again."
        }
        return "Apple Maps search isn't responding. Try again in a moment."
    }
}

private enum PlacesMapFraming {
    /// A region showing every place, with a little margin.
    static func region(fitting places: [PlacesPlace]) -> MKCoordinateRegion? {
        guard let first = places.first else { return nil }
        var minLatitude = first.latitude
        var maxLatitude = first.latitude
        var minLongitude = first.longitude
        var maxLongitude = first.longitude
        for place in places.dropFirst() {
            minLatitude = min(minLatitude, place.latitude)
            maxLatitude = max(maxLatitude, place.latitude)
            minLongitude = min(minLongitude, place.longitude)
            maxLongitude = max(maxLongitude, place.longitude)
        }
        let center = CLLocationCoordinate2D(
            latitude: (minLatitude + maxLatitude) / 2,
            longitude: (minLongitude + maxLongitude) / 2
        )
        let span = MKCoordinateSpan(
            latitudeDelta: min(max((maxLatitude - minLatitude) * 1.4, 0.01), 90),
            longitudeDelta: min(max((maxLongitude - minLongitude) * 1.4, 0.01), 180)
        )
        return MKCoordinateRegion(center: center, span: span)
    }
}

// MARK: - Rows and states

private struct PlacesResultRow: View {
    let place: PlacesPlace

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            PlacesCategoryIcon(systemImage: place.systemImage)
            VStack(alignment: .leading, spacing: 3) {
                Text(place.name)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.leading)
                if let detail = place.detailLine {
                    Text(detail)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                if let address = place.address {
                    Text(address)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            Spacer(minLength: 8)
            Image(systemName: "chevron.right")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.tertiary)
                .padding(.top, 4)
                .accessibilityHidden(true)
        }
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityHint("Shows the menu with calories, protein and healthy picks")
    }
}

/// A spinner with a short explanation.
private struct PlacesStatusView: View {
    let message: String

    var body: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
        .accessibilityElement(children: .combine)
    }
}

/// A compact banner about location access, with one action.
private struct PlacesNoticeCard: View {
    let systemImage: String
    let title: String
    let message: String
    let actionTitle: String
    let action: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: systemImage)
                .font(.title3)
                .foregroundStyle(Color.hakiWarning)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Button(actionTitle, action: action)
                    .font(.footnote.weight(.semibold))
                    .padding(.top, 2)
            }
            Spacer(minLength: 0)
        }
        .hakiCard(padding: 12)
        .padding(.horizontal)
    }
}

#Preview {
    NavigationStack {
        PlacesView()
    }
    .previewEnvironment()
}
