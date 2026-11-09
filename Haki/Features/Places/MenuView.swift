//
//  MenuView.swift
//  Haki
//
//  A place's menu as researched by Haki's AI: the best picks for what's left
//  of today's calories, filters and sorts (protein, calories, price, diet),
//  every dish with its nutrition, and logging a dish to the food log.
//

import Foundation
import SwiftData
import SwiftUI
import UIKit

struct MenuView: View {
    let place: PlacesPlace

    @Environment(FoodAIService.self) private var foodAI
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(HealthSettings.targetsKey) private var targetsData = Data()
    /// Yesterday and today; filtered to today in memory so it stays right past midnight.
    @Query private var recentEntries: [FoodEntry]
    /// When "today" was last checked; moving it on past midnight redraws the best picks.
    @State private var now = Date.now

    @State private var loadState: MenuLoadState = .loading
    @State private var loadRequest = MenuLoadRequest()
    /// The request that already finished, so returning to the screen doesn't ask again.
    @State private var completedRequestID = -1
    @State private var isRefreshing = false
    @State private var refreshError: String?
    @State private var selectedDish: MenuDishSelection?
    @State private var loggedCount = 0
    @State private var toast: String?
    /// The confirmation for a dish just logged in its sheet, shown once the sheet is gone.
    @State private var pendingToast: String?

    init(place: PlacesPlace) {
        self.place = place
        let calendar = Calendar.current
        let todayStart = calendar.startOfDay(for: .now)
        let since = calendar.date(byAdding: .day, value: -1, to: todayStart) ?? todayStart
        _recentEntries = Query(
            filter: #Predicate<FoodEntry> { $0.eatenAt >= since },
            sort: \FoodEntry.eatenAt,
            order: .forward
        )
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                MenuPlaceHeaderCard(place: place, cuisine: currentMenu?.cuisine)
                content
            }
            .padding(.horizontal)
            .padding(.bottom)
        }
        .background(Color.hakiBackground)
        .navigationTitle(place.name)
        .navigationBarTitleDisplayMode(.inline)
        .task(id: loadRequest) { await perform(loadRequest) }
        .sheet(item: $selectedDish, onDismiss: showPendingToast) { selection in
            MenuDishSheet(dish: selection.dish, placeName: place.name, currency: currency) { mealType in
                didLog(selection.dish, mealType: mealType)
            }
            .presentationDetents([.medium, .large])
        }
        .sensoryFeedback(.success, trigger: loggedCount)
        .overlay(alignment: .top) { toastView }
        .task(id: toast) { await hideToastLater() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { followToday() }
        }
        .task {
            followToday()
            for await _ in NotificationCenter.default.notifications(named: .NSCalendarDayChanged) {
                followToday()
            }
        }
    }

    // MARK: Content

    @ViewBuilder
    private var content: some View {
        switch loadState {
        case .loading:
            MenuLoadingCard()
        case .failed(let message):
            failedCard(message)
        case .loaded(let report):
            if report.foundMenu {
                MenuReportContent(
                    report: report,
                    remainingCalories: remainingCalories,
                    isRefreshing: isRefreshing,
                    refreshError: refreshError,
                    onSelect: { dish in selectedDish = MenuDishSelection(dish: dish) },
                    onRefresh: { refresh() }
                )
            } else {
                notFoundCard(report)
            }
        }
    }

    private func failedCard(_ message: String) -> some View {
        ContentUnavailableView {
            Label("Couldn't load the menu", systemImage: "exclamationmark.triangle")
        } description: {
            Text(message)
        } actions: {
            Button("Try again") { retry() }
                .buttonStyle(.borderedProminent)
        }
        .hakiCard()
    }

    private func notFoundCard(_ report: MenuReport) -> some View {
        VStack(spacing: 16) {
            ContentUnavailableView {
                Label("Couldn't find a menu for this place", systemImage: "menucard")
            } description: {
                Text(report.notes.isEmpty ? "Haki looked for this place's menu online but couldn't find one with enough detail." : report.notes)
            } actions: {
                Button("Search again") { refresh() }
                    .buttonStyle(.bordered)
            }
            .hakiCard()
            MenuDisclaimer()
                .padding(.horizontal, 4)
        }
    }

    @ViewBuilder
    private var toastView: some View {
        if let toast {
            Label(toast, systemImage: "checkmark.circle.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(.regularMaterial, in: Capsule())
                .shadow(color: Color.black.opacity(0.12), radius: 8, y: 2)
                .padding(.top, 8)
                .padding(.horizontal)
                .transition(.move(edge: .top).combined(with: .opacity))
                .onTapGesture {
                    withAnimation(.snappy) { self.toast = nil }
                }
        }
    }

    // MARK: Derived

    private var currentMenu: MenuReport? {
        guard case .loaded(let report) = loadState, report.foundMenu else { return nil }
        return report
    }

    private var currency: String {
        MenuFormat.currencyCode(currentMenu?.currency ?? "")
    }

    /// Today's calorie target minus what's logged today (negative when over).
    private var remainingCalories: Int {
        let calendar = Calendar.current
        let today = recentEntries.filter { calendar.isDate($0.eatenAt, inSameDayAs: now) }
        let consumed = Macros.total(today.map(\.macros))
        let targets = HealthSettings.targets(from: targetsData)
        return NutritionProgress(consumed: consumed, targets: targets).remainingCalories
    }

    /// Moves `now` on once the day has changed, so the best picks use today's calories.
    private func followToday() {
        let current = Date.now
        if !Calendar.current.isDate(current, inSameDayAs: now) { now = current }
    }

    // MARK: Loading

    private func retry() {
        loadRequest = MenuLoadRequest(id: loadRequest.id + 1, refresh: false)
    }

    private func refresh() {
        loadRequest = MenuLoadRequest(id: loadRequest.id + 1, refresh: true)
    }

    private func perform(_ request: MenuLoadRequest) async {
        guard request.id != completedRequestID else { return }
        let query = place.query
        if !request.refresh, let cached = foodAI.cachedMenu(for: query) {
            loadState = .loaded(cached)
            completedRequestID = request.id
            return
        }
        // A refresh keeps the current menu on screen until the new one arrives.
        let keepsMenu = request.refresh && currentMenu != nil
        if keepsMenu {
            isRefreshing = true
        } else {
            loadState = .loading
        }
        refreshError = nil
        do {
            let report = try await foodAI.menu(for: query, refresh: request.refresh)
            if keepsMenu, !report.foundMenu {
                refreshError = "Haki couldn't find a newer menu, so this one stays."
            } else {
                loadState = .loaded(report)
            }
            completedRequestID = request.id
        } catch {
            if Backend.isCancellation(error) || Task.isCancelled {
                isRefreshing = false
                return
            }
            if keepsMenu {
                refreshError = error.localizedDescription
            } else {
                loadState = .failed(error.localizedDescription)
            }
            completedRequestID = request.id
        }
        isRefreshing = false
    }

    // MARK: Logging

    private func didLog(_ dish: MenuDish, mealType: MealType) {
        loggedCount += 1
        // Shown from the sheet's onDismiss: set now, the toast would sit behind the
        // closing sheet (hidden from VoiceOver) for part of its 2.5 s, and the sheet
        // closing would cut the announcement off.
        pendingToast = "Logged \(dish.name) to \(mealType.title.lowercased())"
    }

    /// Shows and announces the "Logged …" confirmation once the dish sheet is fully gone.
    private func showPendingToast() {
        guard let message = pendingToast else { return }
        pendingToast = nil
        withAnimation(.snappy) { toast = message }
        // High priority, so VoiceOver reading the uncovered screen doesn't interrupt it.
        let announcement = NSAttributedString(
            string: message,
            attributes: [.accessibilitySpeechAnnouncementPriority: UIAccessibilityPriority.high]
        )
        UIAccessibility.post(notification: .announcement, argument: announcement)
    }

    private func hideToastLater() async {
        guard toast != nil else { return }
        try? await Task.sleep(for: .seconds(2.5))
        guard !Task.isCancelled else { return }
        withAnimation(.snappy) { toast = nil }
    }
}

// MARK: - State

private enum MenuLoadState {
    case loading
    case loaded(MenuReport)
    case failed(String)
}

private struct MenuLoadRequest: Equatable {
    var id = 0
    var refresh = false
}

/// The dish whose sheet is open (a fresh id each time, since dish ids can repeat).
private struct MenuDishSelection: Identifiable {
    let id = UUID()
    let dish: MenuDish
}

private struct MenuDishGroup {
    let title: String
    let dishes: [MenuDish]
}

/// Quick filters above the dish list.
private enum MenuQuickFilter: String, CaseIterable, Identifiable {
    case highProtein, under600, underPrice, vegetarian, vegan, lowCarb, glutenFree

    var id: String { rawValue }

    /// The "Under …" limit in whole units of the menu's currency, or nil to
    /// hide the chip (15 yen or rupees would leave nothing on the list).
    static func priceLimit(currency: String) -> Double? {
        switch currency {
        case "USD", "EUR", "GBP", "CAD", "AUD", "NZD", "CHF", "SGD": 15
        case "JPY": 1_500
        case "KRW": 15_000
        case "INR": 500
        default: nil
        }
    }

    func title(currency: String) -> String {
        switch self {
        case .highProtein: "High protein"
        case .under600: "Under 600 kcal"
        case .underPrice: "Under \(MenuFormat.wholePrice(Self.priceLimit(currency: currency) ?? 15, currency: currency))"
        case .vegetarian: MenuTag.vegetarian.title
        case .vegan: MenuTag.vegan.title
        case .lowCarb: MenuTag.lowCarb.title
        case .glutenFree: MenuTag.glutenFree.title
        }
    }

    var systemImage: String? {
        switch self {
        case .highProtein: "bolt.fill"
        case .under600: "flame"
        case .underPrice: "tag"
        case .vegetarian, .vegan, .lowCarb, .glutenFree: nil
        }
    }

    /// The menu tag this filter requires, if it's a diet filter.
    var tag: MenuTag? {
        switch self {
        case .vegetarian: MenuTag.vegetarian
        case .vegan: MenuTag.vegan
        case .lowCarb: MenuTag.lowCarb
        case .glutenFree: MenuTag.glutenFree
        case .highProtein, .under600, .underPrice: nil
        }
    }
}

// MARK: - Header

private struct MenuPlaceHeaderCard: View {
    let place: PlacesPlace
    let cuisine: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                PlacesCategoryIcon(systemImage: place.systemImage, size: 52)
                VStack(alignment: .leading, spacing: 4) {
                    Text(place.name)
                        .font(.title2.weight(.bold))
                        .accessibilityAddTraits(.isHeader)
                    if let detail {
                        Text(detail)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    if let address = place.address {
                        Text(address)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
            }
            actions
        }
        .hakiCard()
    }

    /// "Restaurant · Bowls and salads · 450 m away"
    private var detail: String? {
        var parts: [String] = []
        if let category = place.categoryTitle {
            parts.append(category)
        }
        if let cuisine {
            let trimmed = cuisine.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty, trimmed.lowercased() != place.categoryTitle?.lowercased() {
                parts.append(trimmed)
            }
        }
        if let distance = place.distanceText {
            parts.append("\(distance) away")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private var actions: some View {
        HStack(spacing: 10) {
            Button {
                place.openDirections()
            } label: {
                MenuActionLabel(title: "Directions", systemImage: "arrow.triangle.turn.up.right.diamond.fill")
            }
            .accessibilityHint("Opens Apple Maps with directions")
            if let url = place.url {
                Link(destination: url) {
                    MenuActionLabel(title: "Website", systemImage: "safari")
                }
                .accessibilityHint("Opens the place's website")
            }
            if let phoneURL = place.phoneURL {
                Link(destination: phoneURL) {
                    MenuActionLabel(title: "Call", systemImage: "phone.fill")
                }
                .accessibilityHint(place.phone ?? "")
            }
        }
        .buttonStyle(.plain)
    }
}

private struct MenuActionLabel: View {
    let title: String
    let systemImage: String

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: systemImage)
                .font(.body.weight(.semibold))
                .accessibilityHidden(true)
            Text(title)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .foregroundStyle(Color.accentColor)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

// MARK: - Loading

private struct MenuLoadingCard: View {
    var body: some View {
        VStack(spacing: 14) {
            ProgressView()
                .controlSize(.large)
            Text("Haki is reading this place's menu and nutrition info…")
                .font(.headline)
                .multilineTextAlignment(.center)
            Text("This can take up to a minute the first time. It's quicker after that.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
        .hakiCard()
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Menu

/// Everything shown once a menu is found. Keeps the filters and sort across refreshes.
private struct MenuReportContent: View {
    let report: MenuReport
    let remainingCalories: Int
    let isRefreshing: Bool
    let refreshError: String?
    let onSelect: (MenuDish) -> Void
    let onRefresh: () -> Void

    @State private var activeFilters: Set<MenuQuickFilter> = []
    @State private var dishQuery = ""
    @State private var sort: MenuSort = .healthiest

    var body: some View {
        let picks = MenuRanking.healthyPicks(report.items, remainingCalories: remainingCalories)
        let dishes = MenuRanking.apply(report.items, filter: filter, sort: sort)
        VStack(spacing: 16) {
            if !picks.isEmpty {
                MenuPicksCard(
                    picks: picks,
                    remainingCalories: remainingCalories,
                    currency: currency,
                    onSelect: onSelect
                )
            }
            filtersCard
            dishesContent(dishes)
            MenuSourcesCard(
                report: report,
                isRefreshing: isRefreshing,
                refreshError: refreshError,
                onRefresh: onRefresh
            )
        }
    }

    private var currency: String {
        MenuFormat.currencyCode(report.currency)
    }

    private var filter: MenuFilter {
        var filter = MenuFilter()
        filter.query = dishQuery
        if activeFilters.contains(.highProtein) { filter.minProteinG = 30 }
        if activeFilters.contains(.under600) { filter.maxCalories = 600 }
        if activeFilters.contains(.underPrice), let limit = MenuQuickFilter.priceLimit(currency: currency) {
            filter.maxPriceCents = Int((limit * 100).rounded())
        }
        var tags = Set<MenuTag>()
        for item in activeFilters {
            if let tag = item.tag { tags.insert(tag) }
        }
        filter.requiredTags = tags
        return filter
    }

    // MARK: Filters

    private var filtersCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            CardHeader("Find a dish", systemImage: "line.3.horizontal.decrease.circle")
            searchField
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach(quickFilters) { item in
                        PlacesChipButton(
                            title: item.title(currency: currency),
                            systemImage: item.systemImage,
                            isSelected: activeFilters.contains(item)
                        ) {
                            toggle(item)
                        }
                    }
                }
            }
            .scrollIndicators(.hidden)
            HStack(spacing: 8) {
                Text("Sort by")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 8)
                Picker("Sort by", selection: $sort) {
                    ForEach(MenuSort.allCases) { option in
                        Text(option.title).tag(option)
                    }
                }
                .pickerStyle(.menu)
            }
        }
        .hakiCard()
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            TextField("Search dishes", text: $dishQuery)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
            if !dishQuery.isEmpty {
                Button {
                    dishQuery = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    /// The chips to show: no price chip for a currency without a sensible limit.
    private var quickFilters: [MenuQuickFilter] {
        let hasPriceLimit = MenuQuickFilter.priceLimit(currency: currency) != nil
        return MenuQuickFilter.allCases.filter { $0 != .underPrice || hasPriceLimit }
    }

    private func toggle(_ item: MenuQuickFilter) {
        if activeFilters.contains(item) {
            activeFilters.remove(item)
        } else {
            activeFilters.insert(item)
        }
    }

    private func clearFilters() {
        activeFilters = []
        dishQuery = ""
    }

    // MARK: Dishes

    @ViewBuilder
    private func dishesContent(_ dishes: [MenuDish]) -> some View {
        if dishes.isEmpty {
            noMatchesCard
        } else if sort == .menuOrder {
            ForEach(Array(groups(of: dishes).enumerated()), id: \.offset) { _, group in
                dishCard(title: group.title, subtitle: countText(group.dishes.count), dishes: group.dishes)
            }
        } else {
            dishCard(
                title: "Sorted by \(sort.title.lowercased())",
                subtitle: countText(dishes.count),
                dishes: dishes
            )
        }
    }

    private func dishCard(title: String, subtitle: String, dishes: [MenuDish]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            CardHeader(title)
            Text(subtitle)
                .font(.footnote)
                .foregroundStyle(.secondary)
            ForEach(Array(dishes.enumerated()), id: \.offset) { index, dish in
                if index > 0 {
                    Divider()
                }
                Button {
                    onSelect(dish)
                } label: {
                    MenuDishRow(dish: dish, currency: currency)
                }
                .buttonStyle(.plain)
            }
        }
        .hakiCard()
    }

    private var noMatchesCard: some View {
        VStack(spacing: 10) {
            Image(systemName: report.items.isEmpty ? "menucard" : "magnifyingglass")
                .font(.title2)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text(report.items.isEmpty ? "No dishes listed" : "No dishes match")
                .font(.headline)
            Text(report.items.isEmpty ? "Haki found this place but not its dishes. Try refreshing the menu." : "Try fewer filters or a different search.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            if !report.items.isEmpty {
                Button("Clear filters") { clearFilters() }
                    .buttonStyle(.bordered)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .hakiCard()
    }

    private func countText(_ count: Int) -> String {
        count == 1 ? "1 dish" : "\(count) dishes"
    }

    /// Dishes grouped by menu section, in the order sections first appear.
    private func groups(of dishes: [MenuDish]) -> [MenuDishGroup] {
        var order: [String] = []
        var bySection: [String: [MenuDish]] = [:]
        for dish in dishes {
            let trimmed = dish.section.trimmingCharacters(in: .whitespacesAndNewlines)
            let section = trimmed.isEmpty ? "Menu" : trimmed
            if bySection[section] == nil {
                order.append(section)
            }
            bySection[section, default: []].append(dish)
        }
        return order.map { MenuDishGroup(title: $0, dishes: bySection[$0] ?? []) }
    }
}

// MARK: - Best picks

private struct MenuPicksCard: View {
    let picks: [MenuDish]
    let remainingCalories: Int
    let currency: String
    let onSelect: (MenuDish) -> Void

    @ScaledMetric(relativeTo: .subheadline) private var rankSize: CGFloat = 28

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            CardHeader("Best picks for you", systemImage: "star.fill")
            Text(intro)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            ForEach(Array(picks.enumerated()), id: \.offset) { index, dish in
                if index > 0 {
                    Divider()
                }
                Button {
                    onSelect(dish)
                } label: {
                    row(rank: index + 1, dish: dish)
                }
                .buttonStyle(.plain)
            }
        }
        .hakiCard()
    }

    private var intro: String {
        if remainingCalories > 0 {
            return "You have \(MenuFormat.kcal(Double(remainingCalories))) left today. These healthy, protein-rich dishes fit."
        }
        return "You've reached today's calorie target, so these are simply the healthiest dishes here."
    }

    private func row(rank: Int, dish: MenuDish) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(rank)")
                .font(.subheadline.weight(.bold))
                .monospacedDigit()
                .foregroundStyle(Color.white)
                .frame(width: rankSize, height: rankSize)
                .background(Color.accentColor, in: Circle())
                .accessibilityLabel("Pick \(rank)")
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(dish.name)
                        .font(.headline)
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.leading)
                    Spacer(minLength: 8)
                    if let price = dish.price, price > 0 {
                        Text(MenuFormat.price(price, currency: currency))
                            .font(.subheadline.weight(.semibold))
                            .monospacedDigit()
                            .foregroundStyle(.primary)
                    }
                }
                Text(reason(for: dish))
                    .font(.subheadline)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                HStack(spacing: 8) {
                    MenuScoreBadge(score: dish.healthScore)
                    MenuNutritionMarker(isOfficial: dish.isOfficialNutrition)
                }
            }
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityHint("Shows details and lets you log it")
    }

    /// "48 g protein · 610 kcal · fits your remaining 900 kcal"
    private func reason(for dish: MenuDish) -> String {
        var text = "\(MenuFormat.grams(dish.proteinG)) protein · \(MenuFormat.kcal(dish.calories))"
        guard remainingCalories > 0 else { return text }
        let remaining = MenuFormat.kcal(Double(remainingCalories))
        if dish.calories <= Double(remainingCalories) {
            text += " · fits your remaining \(remaining)"
        } else {
            text += " · more than your remaining \(remaining)"
        }
        return text
    }
}

// MARK: - Sources

private struct MenuSourceLink {
    let title: String
    let url: URL
}

private struct MenuSourcesCard: View {
    let report: MenuReport
    let isRefreshing: Bool
    let refreshError: String?
    let onRefresh: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            CardHeader("About this menu", systemImage: "info.circle")
            if !report.notes.isEmpty {
                Text(report.notes)
                    .font(.subheadline)
            }
            sources
            if let updatedText {
                Text(updatedText)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            if let refreshError {
                Label(refreshError, systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote)
                    .foregroundStyle(Color.hakiWarning)
            }
            refreshButton
            Divider()
            MenuDisclaimer()
        }
        .hakiCard()
    }

    @ViewBuilder
    private var sources: some View {
        let links = sourceLinks
        if !links.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Sources")
                    .font(.subheadline.weight(.semibold))
                ForEach(Array(links.enumerated()), id: \.offset) { _, link in
                    Link(destination: link.url) {
                        Label(link.title, systemImage: "link")
                            .font(.subheadline)
                            .multilineTextAlignment(.leading)
                    }
                }
            }
        }
    }

    private var refreshButton: some View {
        Button(action: onRefresh) {
            HStack(spacing: 8) {
                if isRefreshing {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(systemName: "arrow.clockwise")
                        .accessibilityHidden(true)
                }
                Text(isRefreshing ? "Refreshing menu…" : "Refresh menu")
            }
            .font(.subheadline.weight(.semibold))
        }
        .disabled(isRefreshing)
        .accessibilityHint("Asks Haki to look up this menu again")
    }

    private var sourceLinks: [MenuSourceLink] {
        report.sources.compactMap { (source: MenuSource) -> MenuSourceLink? in
            guard let url = URL(string: source.url),
                  let scheme = url.scheme?.lowercased(),
                  scheme == "https" || scheme == "http"
            else { return nil }
            let title = source.title.trimmingCharacters(in: .whitespacesAndNewlines)
            return MenuSourceLink(title: title.isEmpty ? (url.host() ?? source.url) : title, url: url)
        }
    }

    private var updatedText: String? {
        guard let date = report.generatedDate else { return nil }
        return "Updated " + date.formatted(.relative(presentation: .named))
    }
}

private struct MenuDisclaimer: View {
    var body: some View {
        Label {
            Text("Menus, prices and nutrition are estimates from public information and may be out of date. Check with the restaurant, especially for allergies.")
        } icon: {
            Image(systemName: "exclamationmark.shield")
                .accessibilityHidden(true)
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
    }
}

#Preview {
    NavigationStack {
        MenuView(place: .preview)
    }
    .previewEnvironment()
}
