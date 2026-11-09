//
//  AssistantToolExecutor.swift
//  Haki
//
//  Runs the "Ask Haki" assistant's device tools (`DEVICE_TOOLS` in the
//  haki-ai edge function, `AssistantTool` in Core). Each tool looks up the
//  person's data on this iPhone (the SwiftData models, the brokerage and
//  social services) and answers with compact JSON. Totals come from the same
//  Core analytics the screens use, so the assistant's numbers match the app.
//
//  Conventions in every result: money is a decimal amount in the currency
//  (12.5), with the currency code once at the top; spending is positive;
//  days are "YYYY-MM-DD" and times "YYYY-MM-DDTHH:MM" (local). Long lists are
//  capped and say "truncated": true. Photos and other binary data never
//  leave the device.
//

import Foundation
import SwiftData

private typealias J = AssistantToolData

@MainActor
struct AssistantToolExecutor {
    let context: ModelContext
    let portfolio: PortfolioService
    let social: SocialService
    let auth: AuthService
    let now: Date
    let calendar: Calendar

    init(context: ModelContext, portfolio: PortfolioService, social: SocialService, auth: AuthService, now: Date = .now) {
        self.context = context
        self.portfolio = portfolio
        self.social = social
        self.auth = auth
        self.now = now
        self.calendar = Calendar.current
    }

    /// Looks up what `use` asks for. Never throws: unknown tools and
    /// failures come back as error results the assistant can read.
    func run(_ use: AssistantToolUse) async -> AssistantToolResult {
        guard let tool = AssistantTool(rawValue: use.name) else {
            return AssistantToolResult(
                toolUseID: use.id,
                content: "Haki has no tool called \"\(J.clipped(use.name, limit: 60))\".",
                isError: true
            )
        }
        do {
            let output = try await lookUp(tool, use: use)
            return AssistantToolResult(toolUseID: use.id, content: J.fitted(output), isError: false)
        } catch {
            let reason = J.clipped(error.localizedDescription, limit: 200)
            return AssistantToolResult(
                toolUseID: use.id,
                content: "Couldn't look up \(tool.dataTitle.lowercased()) on this iPhone. \(reason)",
                isError: true
            )
        }
    }

    private func lookUp(_ tool: AssistantTool, use: AssistantToolUse) async throws -> [String: JSONValue] {
        switch tool {
        case .overview: return try await overview()
        case .spending: return try spending(use)
        case .transactions: return try searchTransactions(use)
        case .budgets: return try budgets(use)
        case .bills: return try recurringBills()
        case .accounts: return try accounts()
        case .investments: return await investments()
        case .nutrition: return try nutrition(use)
        case .workouts: return try workouts(use)
        case .notes: return try searchNotes(use)
        case .flashcards: return try flashcards(use)
        case .wardrobe: return try wardrobe(use)
        case .social: return await socialProfile()
        }
    }

    private var currency: String { Money.defaultCurrencyCode }

    // MARK: - Fetching

    /// Transactions dated in `start ..< end` (open-ended when nil), newest first.
    private func fetchTransactions(from start: Date? = nil, to end: Date? = nil) throws -> [TransactionRecord] {
        guard start != nil || end != nil else {
            return try context.fetch(FetchDescriptor<TransactionRecord>(sortBy: [SortDescriptor(\TransactionRecord.date, order: .reverse)]))
        }
        let lower = start ?? Date.distantPast
        let upper = end ?? Date.distantFuture
        let descriptor = FetchDescriptor<TransactionRecord>(
            predicate: #Predicate<TransactionRecord> { $0.date >= lower && $0.date < upper },
            sortBy: [SortDescriptor(\TransactionRecord.date, order: .reverse)]
        )
        return try context.fetch(descriptor)
    }

    private func fetchCategories() throws -> [TransactionCategory] {
        let descriptor = FetchDescriptor<TransactionCategory>(
            sortBy: [SortDescriptor(\TransactionCategory.sortOrder), SortDescriptor(\TransactionCategory.name)]
        )
        return try context.fetch(descriptor)
    }

    private func fetchAccounts() throws -> [Account] {
        let descriptor = FetchDescriptor<Account>(
            sortBy: [SortDescriptor(\Account.sortOrder), SortDescriptor(\Account.name)]
        )
        return try context.fetch(descriptor)
    }

    private func fetchRecurringItems() throws -> [RecurringItem] {
        try context.fetch(FetchDescriptor<RecurringItem>(sortBy: [SortDescriptor(\RecurringItem.anchorDate)]))
    }

    /// Food eaten in `start ..< end`, oldest first.
    private func fetchFood(from start: Date, to end: Date) throws -> [FoodEntry] {
        let lower = start
        let upper = end
        let descriptor = FetchDescriptor<FoodEntry>(
            predicate: #Predicate<FoodEntry> { $0.eatenAt >= lower && $0.eatenAt < upper },
            sortBy: [SortDescriptor(\FoodEntry.eatenAt)]
        )
        return try context.fetch(descriptor)
    }

    /// Every finished workout, newest first.
    private func fetchFinishedWorkouts() throws -> [WorkoutRecord] {
        let descriptor = FetchDescriptor<WorkoutRecord>(
            predicate: #Predicate<WorkoutRecord> { $0.endedAt != nil },
            sortBy: [SortDescriptor(\WorkoutRecord.startedAt, order: .reverse)]
        )
        return try context.fetch(descriptor)
    }

    private func fetchDecks() throws -> [FlashcardDeck] {
        try context.fetch(FetchDescriptor<FlashcardDeck>(sortBy: [SortDescriptor(\FlashcardDeck.name)]))
    }

    // MARK: - Shared pieces

    private func readMonth(_ use: AssistantToolUse, default fallback: MonthInterval, notes: inout [String]) -> MonthInterval {
        guard let raw = use.string("month") else { return fallback }
        if let month = J.parseMonth(raw) { return month }
        notes.append("\"\(J.clipped(raw, limit: 20))\" isn't a month like \(J.monthString(fallback)), so this is \(fallback.title(calendar: calendar)).")
        return fallback
    }

    private func categoryNames(_ categories: [TransactionCategory]) -> [String: String] {
        var names: [String: String] = [:]
        for category in categories {
            names[category.ledgerID] = category.name
        }
        return names
    }

    private func categoryName(_ id: String?, names: [String: String]) -> String {
        guard let id else { return "Uncategorized" }
        return names[id] ?? "Uncategorized"
    }

    private func categoryAmounts(_ totals: [CategoryTotal], names: [String: String], limit: Int) -> JSONValue {
        let lines = totals.filter { $0.cents > 0 }.prefix(limit).map { total -> [String: JSONValue] in
            ["category": .string(categoryName(total.categoryID, names: names)), "amount": J.money(total.cents)]
        }
        return J.objects(lines)
    }

    /// The targets the Health tab uses, and whether they're the defaults.
    private func nutritionTargets() -> (targets: NutritionTargets, isDefault: Bool) {
        let data = UserDefaults.standard.data(forKey: HealthSettings.targetsKey) ?? Data()
        return (targets: HealthSettings.targets(from: data), isDefault: data.isEmpty)
    }

    private func weightUnit() -> WeightUnit {
        HealthSettings.weightUnit(from: UserDefaults.standard.string(forKey: HealthSettings.weightUnitKey) ?? "")
    }

    private func distanceUnit() -> DistanceUnit {
        HealthSettings.distanceUnit(from: UserDefaults.standard.string(forKey: HealthSettings.distanceUnitKey) ?? "")
    }

    private func withNotes(_ fields: [String: JSONValue], _ notes: [String]) -> [String: JSONValue] {
        guard !notes.isEmpty else { return fields }
        var result = fields
        result["notes"] = J.strings(notes)
        return result
    }

    // MARK: - get_overview

    private func overview() async throws -> [String: JSONValue] {
        // The only suspension comes first: models fetched below are read
        // without any await in between, so none can be deleted mid-use.
        await loadPortfolioIfNeeded()
        let investing = investmentSummary()
        let month = MonthInterval.current(calendar: calendar, now: now)
        let recent = try fetchTransactions(from: month.previous.start(in: calendar))
        let categories = try fetchCategories()
        let unreviewed = try context.fetchCount(FetchDescriptor<TransactionRecord>(predicate: #Predicate<TransactionRecord> { !$0.isReviewed }))
        let bills = try overviewBills(recent)
        let netWorth = try overviewNetWorth()
        let food = try overviewFood()
        let training = try overviewWorkouts()
        let study = try overviewStudy()
        let closet = try overviewWardrobe()

        return [
            "currency": .string(currency),
            "today": J.day(now, calendar: calendar),
            "spending_this_month": .object(overviewSpending(recent, categories: categories, month: month)),
            "budgets_this_month": overviewBudgets(recent, categories: categories, month: month),
            "transactions_to_review": J.int(unreviewed),
            "upcoming_bills": bills,
            "net_worth": .object(netWorth),
            "investments": .object(investing),
            "food_today": .object(food),
            "workouts": .object(training),
            "notes_and_flashcards": .object(study),
            "wardrobe": .object(closet),
        ]
    }

    private func overviewSpending(_ recent: [TransactionRecord], categories: [TransactionCategory], month: MonthInterval) -> [String: JSONValue] {
        let interval = month.dateInterval(in: calendar)
        let days = month.numberOfDays(in: calendar)
        let today = max(1, min(days, calendar.component(.day, from: now)))
        let lastMonth = month.previous
        let lastMonthDaily = SpendingAnalytics.cumulativeDailySpending(recent, month: lastMonth, calendar: calendar)
        let compareDay = min(today, lastMonth.numberOfDays(in: calendar))
        let lastMonthSamePoint = lastMonthDaily.first(where: { $0.day == compareDay })?.cents ?? 0
        let spent = SpendingAnalytics.spending(recent, in: interval)
        return [
            "month": .string(J.monthString(month)),
            "day_of_month": J.int(today),
            "days_in_month": J.int(days),
            "spent": J.money(spent),
            "income": J.money(SpendingAnalytics.income(recent, in: interval)),
            "last_month_same_point": J.money(lastMonthSamePoint),
            "last_month_total": J.money(lastMonthDaily.last?.cents ?? 0),
            "top_categories": categoryAmounts(
                SpendingAnalytics.spendingByCategory(recent, in: interval),
                names: categoryNames(categories),
                limit: 4
            ),
        ]
    }

    private func overviewBudgets(_ recent: [TransactionRecord], categories: [TransactionCategory], month: MonthInterval) -> JSONValue {
        let budgeted = categories.filter { $0.kind == .expense && $0.hasBudget }
        guard !budgeted.isEmpty else {
            return .string("No budgets set. Budgets are set per category in the Budgets tab.")
        }
        let interval = month.dateInterval(in: calendar)
        var spentByID: [String: Int] = [:]
        for total in SpendingAnalytics.spendingByCategory(recent, in: interval) {
            if let id = total.categoryID { spentByID[id] = total.cents }
        }
        var totalBudget = 0
        var totalSpent = 0
        var over: [String] = []
        for category in budgeted {
            let budget = category.monthlyBudgetCents ?? 0
            let spent = spentByID[category.ledgerID] ?? 0
            totalBudget += budget
            totalSpent += spent
            if spent > budget { over.append(category.name) }
        }
        let progress = BudgetProgress(budgetCents: totalBudget, spentCents: totalSpent)
        let fields: [String: JSONValue] = [
            "total_budget": J.money(totalBudget),
            "spent_in_budgeted_categories": J.money(totalSpent),
            "left": J.money(progress.remainingCents),
            "used_pct": J.percent(progress.fractionUsed),
            "budgets": J.int(budgeted.count),
            "over_budget": J.strings(over),
        ]
        return .object(fields)
    }

    /// Active bills due in the next 14 days, and ones from the last week
    /// that went unpaid (as on the Overview tab).
    private func overviewBills(_ recent: [TransactionRecord]) throws -> JSONValue {
        let items = try fetchRecurringItems()
        guard !items.isEmpty else { return .string("No recurring bills tracked.") }
        let todayStart = calendar.startOfDay(for: now)
        let lateStart = calendar.date(byAdding: .day, value: -7, to: todayStart) ?? todayStart
        var bills: [(date: Date, fields: [String: JSONValue])] = []
        for item in items where item.isActive {
            let pastDue = item.schedule.occurrences(in: DateInterval(start: lateStart, end: todayStart), calendar: calendar)
            for due in pastDue {
                let status = RecurringMatcher.status(
                    dueDate: due, merchantKey: item.merchantKey, frequency: item.frequency,
                    entries: recent, now: now, calendar: calendar
                )
                guard case .late = status else { continue }
                bills.append((date: due, fields: billOccurrence(item, due: due, status: status)))
            }
            let due = item.nextDueDate(onOrAfter: now, calendar: calendar)
            let daysUntil = calendar.daysBetween(now, due)
            guard daysUntil >= 0, daysUntil <= 14 else { continue }
            let status = RecurringMatcher.status(
                dueDate: due, merchantKey: item.merchantKey, frequency: item.frequency,
                entries: recent, now: now, calendar: calendar
            )
            bills.append((date: due, fields: billOccurrence(item, due: due, status: status)))
        }
        guard !bills.isEmpty else { return .string("Nothing due in the next 14 days.") }
        bills.sort { $0.date < $1.date }
        return J.objects(bills.prefix(6).map { $0.fields })
    }

    private func billOccurrence(_ item: RecurringItem, due: Date, status: RecurringOccurrenceStatus) -> [String: JSONValue] {
        var fields = J.occurrence(dueDate: due, status: status, calendar: calendar)
        fields["name"] = J.text(item.name, limit: 80)
        fields["amount"] = J.money(item.amountCents)
        fields["days_until"] = J.int(calendar.daysBetween(now, due))
        return fields
    }

    private func overviewNetWorth() throws -> [String: JSONValue] {
        let accounts = try fetchAccounts()
        guard !accounts.isEmpty else {
            return ["accounts": J.int(0), "message": .string("No accounts added yet.")]
        }
        let netWorth = accounts.reduce(0) { $0 + $1.netWorthContributionCents }
        var fields: [String: JSONValue] = ["total": J.money(netWorth), "accounts": J.int(accounts.count)]
        if let change = netWorthChangeSinceMonthAgo(accounts, netWorth: netWorth) {
            fields["change_last_month"] = J.money(change)
        }
        return fields
    }

    /// Change in net worth since a month ago, as on the Overview tab (recorded
    /// balances only); nil without history that old. get_overview and
    /// get_accounts both use it, so "change_last_month" is the same in each.
    private func netWorthChangeSinceMonthAgo(_ accounts: [Account], netWorth: Int) -> Int? {
        let observations = accounts.filter { $0.includeInNetWorth }.flatMap { $0.balanceObservations }
        guard let monthAgo = calendar.date(byAdding: .month, value: -1, to: now),
              observations.contains(where: { $0.date <= monthAgo }),
              let start = NetWorthCalculator.series(observations: observations, at: [monthAgo]).first
        else { return nil }
        return netWorth - start.netCents
    }

    private func overviewFood() throws -> [String: JSONValue] {
        let todayStart = calendar.startOfDay(for: now)
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: todayStart) ?? now
        let todays = try fetchFood(from: todayStart, to: tomorrow)
        let progress = NutritionProgress(consumed: Macros.total(todays.map { $0.macros }), targets: nutritionTargets().targets)
        return [
            "entries": J.int(todays.count),
            "calories": J.number(progress.consumed.calories, places: 0),
            "calorie_target": J.int(progress.targets.calories),
            "calories_left": J.int(progress.remainingCalories),
            "protein_g": J.number(progress.consumed.proteinG),
            "protein_target_g": J.int(progress.targets.proteinG),
            "protein_left_g": J.int(progress.remainingProteinG),
        ]
    }

    private func overviewWorkouts() throws -> [String: JSONValue] {
        let finished = try fetchFinishedWorkouts()
        let unit = weightUnit()
        let week = calendar.dateInterval(of: .weekOfYear, for: now)
        let thisWeek = finished.filter { week?.contains($0.startedAt) ?? false }
        var fields: [String: JSONValue] = [
            "weight_unit": .string(unit.symbol),
            "this_week": J.int(thisWeek.count),
            "volume_this_week": J.weight(thisWeek.reduce(0.0) { $0 + $1.volumeKg }, unit: unit),
            "week_streak": J.int(WorkoutMath.weekStreak(workoutDates: finished.map { $0.startedAt }, now: now, calendar: calendar)),
        ]
        if let last = finished.first {
            fields["last_workout"] = .object([
                "title": J.text(last.title, limit: 80),
                "date": J.day(last.startedAt, calendar: calendar),
            ])
        }
        let active = try context.fetchCount(FetchDescriptor<WorkoutRecord>(predicate: #Predicate<WorkoutRecord> { $0.endedAt == nil }))
        if active > 0 { fields["workout_in_progress"] = .bool(true) }
        return fields
    }

    private func overviewStudy() throws -> [String: JSONValue] {
        let notes = try context.fetchCount(FetchDescriptor<Note>())
        let decks = try fetchDecks()
        let dueNow = decks.reduce(0) { $0 + $1.dueCount(now: now) }
        let toStudy = decks.reduce(0) { $0 + StudyStore.studyQueue(for: $1, now: now, calendar: calendar).count }
        return [
            "notes": J.int(notes),
            "decks": J.int(decks.count),
            "cards_due_now": J.int(dueNow),
            "cards_to_study_now": J.int(toStudy),
        ]
    }

    private func overviewWardrobe() throws -> [String: JSONValue] {
        let items = try context.fetch(FetchDescriptor<ClothingItem>())
        let outfits = try context.fetchCount(FetchDescriptor<Outfit>())
        let forgotten = WardrobeStats.forgotten(items.map { $0.wearInfo }, days: 90, now: now)
        return [
            "pieces": J.int(items.count),
            "outfits": J.int(outfits),
            "not_worn_in_90_days": J.int(forgotten.count),
        ]
    }

    // MARK: - get_spending

    private func spending(_ use: AssistantToolUse) throws -> [String: JSONValue] {
        var notes: [String] = []
        let current = MonthInterval.current(calendar: calendar, now: now)
        let month = readMonth(use, default: current, notes: &notes)
        let monthsBack = J.clamped(J.integer(use.input["months_back"]), to: 0...11, default: 2)
        let months = MonthInterval.trailing(monthsBack + 1, endingAt: month)
        let earlier = Array(months.dropLast().reversed())
        let oldest = min(months.first ?? month, month.previous)
        let all = try fetchTransactions(from: oldest.start(in: calendar), to: month.end(in: calendar))
        let categories = try fetchCategories()
        let names = categoryNames(categories)

        var result: [String: JSONValue] = [
            "currency": .string(currency),
            "month": .string(J.monthString(month)),
            "month_name": .string(month.title(calendar: calendar)),
        ]

        // Optional category filter.
        var scoped = all
        var filterName: String?
        if let wanted = use.string("category") {
            if J.folded(wanted).contains("uncategori") {
                scoped = all.filter { $0.category == nil }
                filterName = "Uncategorized"
            } else if let index = J.bestMatch(wanted, in: categories.map { $0.name }) {
                let category = categories[index]
                let id = category.ledgerID
                scoped = all.filter { $0.ledgerCategoryID == id }
                filterName = category.name
                if category.hasBudget { result["category_budget"] = J.money(category.monthlyBudgetCents ?? 0) }
            } else {
                result["error"] = .string("No category called \"\(J.clipped(wanted, limit: 40))\".")
                result["categories"] = J.strings(categories.map { $0.name })
                return withNotes(result, notes)
            }
        }
        let isFiltered = filterName != nil
        if let filterName { result["category"] = .string(filterName) }

        let interval = month.dateInterval(in: calendar)
        let monthEntries = SpendingAnalytics.entries(scoped, in: interval)
        let spent = SpendingAnalytics.spending(monthEntries, in: interval)
        let income = SpendingAnalytics.income(monthEntries, in: interval)
        result["spending"] = J.money(spent)
        if !isFiltered || income != 0 { result["income"] = J.money(income) }
        if !isFiltered { result["saved"] = J.money(income - spent) }
        result["spending_transactions"] = J.int(monthEntries.filter { $0.ledgerFlow == .spending }.count)

        if month == current {
            let elapsed = month.elapsedDays(asOf: now, calendar: calendar)
            let projected = SpendingAnalytics.projectedSpending(scoped, month: month, asOf: now, calendar: calendar)
            let previousDaily = SpendingAnalytics.cumulativeDailySpending(scoped, month: month.previous, calendar: calendar)
            let compareDay = min(elapsed, month.previous.numberOfDays(in: calendar))
            result["is_current_month"] = .bool(true)
            result["day_of_month"] = J.int(elapsed)
            result["days_in_month"] = J.int(month.numberOfDays(in: calendar))
            result["projected_month_spending"] = J.money(max(spent, projected))
            result["last_month_same_point"] = J.money(previousDaily.first(where: { $0.day == compareDay })?.cents ?? 0)
        } else if month > current {
            notes.append("That month hasn't started yet.")
        }

        if !isFiltered {
            result["by_category"] = spendingByCategory(monthEntries, interval: interval, categories: categories, spent: spent)
            result["income_by_category"] = incomeByCategory(monthEntries, interval: interval, names: names)
        }
        let merchants = J.topMerchants(monthEntries, limit: 10).map { merchant -> [String: JSONValue] in
            ["merchant": .string(merchant.name), "amount": J.money(merchant.cents), "transactions": J.int(merchant.count)]
        }
        result["top_merchants"] = J.objects(merchants)

        if !earlier.isEmpty {
            let lines = earlier.map { previous -> [String: JSONValue] in
                monthTotals(previous, entries: scoped, names: names, includeCategories: !isFiltered)
            }
            result["earlier_months"] = J.objects(lines)
            result["average_spending_earlier_months"] = J.money(
                SpendingAnalytics.averageMonthlySpending(scoped, months: earlier, calendar: calendar)
            )
        }
        return withNotes(result, notes)
    }

    private func spendingByCategory(_ entries: [TransactionRecord], interval: DateInterval, categories: [TransactionCategory], spent: Int) -> JSONValue {
        var budgets: [String: Int] = [:]
        var names: [String: String] = [:]
        for category in categories {
            names[category.ledgerID] = category.name
            if category.kind == .expense, category.hasBudget {
                budgets[category.ledgerID] = category.monthlyBudgetCents ?? 0
            }
        }
        let lines = SpendingAnalytics.spendingByCategory(entries, in: interval).prefix(25).map { total -> [String: JSONValue] in
            var line: [String: JSONValue] = [
                "category": .string(categoryName(total.categoryID, names: names)),
                "amount": J.money(total.cents),
            ]
            if spent > 0 { line["share_pct"] = J.percent(Double(total.cents) / Double(spent)) }
            if let id = total.categoryID, let budget = budgets[id] { line["budget"] = J.money(budget) }
            return line
        }
        return J.objects(lines)
    }

    private func incomeByCategory(_ entries: [TransactionRecord], interval: DateInterval, names: [String: String]) -> JSONValue {
        let incomeEntries = entries.filter { $0.ledgerFlow == .income }
        let groups = Dictionary(grouping: incomeEntries, by: { $0.ledgerCategoryID ?? "" })
        var totals: [(name: String, cents: Int)] = []
        for (id, group) in groups {
            let cents = SpendingAnalytics.income(group, in: interval)
            guard cents != 0 else { continue }
            totals.append((name: id.isEmpty ? "Uncategorized" : (names[id] ?? "Uncategorized"), cents: cents))
        }
        totals.sort { $0.cents != $1.cents ? $0.cents > $1.cents : $0.name < $1.name }
        let lines = totals.prefix(8).map { total -> [String: JSONValue] in
            ["category": .string(total.name), "amount": J.money(total.cents)]
        }
        return J.objects(lines)
    }

    private func monthTotals(_ month: MonthInterval, entries: [TransactionRecord], names: [String: String], includeCategories: Bool) -> [String: JSONValue] {
        let interval = month.dateInterval(in: calendar)
        let monthEntries = SpendingAnalytics.entries(entries, in: interval)
        let income = SpendingAnalytics.income(monthEntries, in: interval)
        var line: [String: JSONValue] = [
            "month": .string(J.monthString(month)),
            "spending": J.money(SpendingAnalytics.spending(monthEntries, in: interval)),
        ]
        if includeCategories || income != 0 { line["income"] = J.money(income) }
        if includeCategories {
            line["top_categories"] = categoryAmounts(
                SpendingAnalytics.spendingByCategory(monthEntries, in: interval), names: names, limit: 6
            )
        }
        return line
    }

    // MARK: - search_transactions

    private func searchTransactions(_ use: AssistantToolUse) throws -> [String: JSONValue] {
        var notes: [String] = []
        let words = J.searchWords(use.string("query"))
        var fromDay = J.parseDay(use.string("from"), calendar: calendar)
        var toDay = J.parseDay(use.string("to"), calendar: calendar)
        if let raw = use.string("from"), fromDay == nil {
            notes.append("\"from\" (\(J.clipped(raw, limit: 30))) isn't a date like \(J.dayString(now, calendar: calendar)), so it was ignored.")
        }
        if let raw = use.string("to"), toDay == nil {
            notes.append("\"to\" (\(J.clipped(raw, limit: 30))) isn't a date like \(J.dayString(now, calendar: calendar)), so it was ignored.")
        }
        if let start = fromDay, let end = toDay, start > end {
            fromDay = end
            toDay = start
            notes.append("\"from\" was after \"to\", so they were swapped.")
        }
        let limit = J.clamped(J.integer(use.input["limit"]), to: 1...50, default: 20)
        let minimum = J.decimal(use.input["min_amount"]).flatMap { J.cents(fromAmount: $0) }
        let upper = toDay.flatMap { calendar.date(byAdding: .day, value: 1, to: $0) }
        let records = try fetchTransactions(from: fromDay, to: upper)

        var result: [String: JSONValue] = [
            "currency": .string(currency),
            "amount_sign": .string("positive = money out (spending), negative = money in"),
        ]
        var filters: [String: JSONValue] = [:]
        if let query = use.string("query") { filters["query"] = J.text(query, limit: 80) }
        if let fromDay { filters["from"] = J.day(fromDay, calendar: calendar) }
        if let toDay { filters["to"] = J.day(toDay, calendar: calendar) }
        if let minimum { filters["min_amount"] = J.money(minimum) }

        var categoryID: String?
        var onlyUncategorized = false
        if let wanted = use.string("category") {
            let categories = try fetchCategories()
            if J.folded(wanted).contains("uncategori") {
                onlyUncategorized = true
                filters["category"] = .string("Uncategorized")
            } else if let index = J.bestMatch(wanted, in: categories.map { $0.name }) {
                categoryID = categories[index].ledgerID
                filters["category"] = .string(categories[index].name)
            } else {
                result["error"] = .string("No category called \"\(J.clipped(wanted, limit: 40))\".")
                result["categories"] = J.strings(categories.map { $0.name })
                return withNotes(result, notes)
            }
        }
        result["filters"] = .object(filters)

        let matched = records.filter { record in
            if onlyUncategorized, record.category != nil { return false }
            if let categoryID, record.ledgerCategoryID != categoryID { return false }
            if let minimum, abs(record.amountCents) < minimum { return false }
            return J.matches(words, in: [record.merchant, record.originalDescription, record.notes])
        }
        let everything = DateInterval(start: Date.distantPast, end: Date.distantFuture)
        result["matches"] = J.int(matched.count)
        result["net_spending"] = J.money(SpendingAnalytics.spending(matched, in: everything))
        result["income"] = J.money(SpendingAnalytics.income(matched, in: everything))
        result["transactions"] = J.objects(matched.prefix(limit).map { transactionFields($0) })
        if matched.count > limit {
            result["truncated"] = .bool(true)
            result["showing"] = J.int(limit)
        }
        if matched.isEmpty {
            notes.append(records.isEmpty ? "There are no transactions in that period." : "No transactions match.")
        }
        return withNotes(result, notes)
    }

    private func transactionFields(_ record: TransactionRecord) -> [String: JSONValue] {
        var fields: [String: JSONValue] = [
            "date": J.day(record.date, calendar: calendar),
            "merchant": J.text(record.merchant, limit: 80),
            "amount": J.money(record.amountCents),
            "category": .string(record.category?.name ?? "Uncategorized"),
            "counts_as": .string(J.flowName(record.flow)),
        ]
        if let account = record.account { fields["account"] = J.text(account.name, limit: 60) }
        let description = record.originalDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        if !description.isEmpty, J.folded(description) != J.folded(record.merchant) {
            fields["description"] = J.text(description, limit: 80)
        }
        if !record.notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            fields["notes"] = J.text(record.notes, limit: 200)
        }
        if record.isPending { fields["pending"] = .bool(true) }
        if !record.isReviewed { fields["reviewed"] = .bool(false) }
        return fields
    }

    // MARK: - get_budgets

    private func budgets(_ use: AssistantToolUse) throws -> [String: JSONValue] {
        var notes: [String] = []
        let current = MonthInterval.current(calendar: calendar, now: now)
        let month = readMonth(use, default: current, notes: &notes)
        let interval = month.dateInterval(in: calendar)
        let isCurrent = month == current
        let elapsed = month.elapsedDays(asOf: now, calendar: calendar)
        let days = month.numberOfDays(in: calendar)
        let all = try fetchTransactions(from: month.previous.start(in: calendar), to: interval.end)
        let entries = SpendingAnalytics.entries(all, in: interval)
        let categories = try fetchCategories()

        var spentByID: [String: Int] = [:]
        var uncategorized = 0
        for total in SpendingAnalytics.spendingByCategory(entries, in: interval) {
            if let id = total.categoryID {
                spentByID[id] = total.cents
            } else {
                uncategorized = total.cents
            }
        }

        var result: [String: JSONValue] = [
            "currency": .string(currency),
            "month": .string(J.monthString(month)),
            "month_name": .string(month.title(calendar: calendar)),
            "days_in_month": J.int(days),
            "days_elapsed": J.int(elapsed),
            "total_spending": J.money(SpendingAnalytics.spending(entries, in: interval)),
        ]

        let budgeted = categories.filter { $0.kind == .expense && $0.hasBudget }
        if budgeted.isEmpty {
            notes.append("No budgets set yet. Budgets are set per category in the Budgets tab.")
        } else {
            result["budgets"] = budgetLines(budgeted, spentByID: spentByID, isCurrent: isCurrent, elapsed: elapsed, days: days)
            result["overall"] = .object(overallBudget(
                budgeted, spentByID: spentByID, all: all, month: month, isCurrent: isCurrent, elapsed: elapsed, days: days
            ))
        }

        let unbudgeted = categories
            .filter { $0.kind == .expense && !$0.hasBudget && (spentByID[$0.ledgerID] ?? 0) != 0 }
            .sorted { (spentByID[$0.ledgerID] ?? 0) > (spentByID[$1.ledgerID] ?? 0) }
        var unbudgetedLines = unbudgeted.prefix(10).map { category -> [String: JSONValue] in
            ["category": .string(category.name), "spent": J.money(spentByID[category.ledgerID] ?? 0)]
        }
        if uncategorized != 0 {
            unbudgetedLines.append(["category": .string("Uncategorized"), "spent": J.money(uncategorized)])
        }
        result["spending_without_budget"] = J.objects(unbudgetedLines)
        return withNotes(result, notes)
    }

    private func budgetLines(_ budgeted: [TransactionCategory], spentByID: [String: Int], isCurrent: Bool, elapsed: Int, days: Int) -> JSONValue {
        let remainingDays = max(1, days - elapsed + 1)
        let lines = budgeted.map { category -> [String: JSONValue] in
            let progress = BudgetProgress(budgetCents: category.monthlyBudgetCents ?? 0, spentCents: spentByID[category.ledgerID] ?? 0)
            var line: [String: JSONValue] = [
                "category": .string(category.name),
                "budget": J.money(progress.budgetCents),
                "spent": J.money(progress.spentCents),
                "left": J.money(progress.remainingCents),
                "used_pct": J.percent(progress.fractionUsed),
                "status": .string(J.paceName(progress.pace(elapsedDays: elapsed, daysInMonth: days))),
            ]
            if isCurrent, progress.remainingCents > 0 {
                line["left_per_day"] = J.money(progress.remainingCents / remainingDays)
            }
            return line
        }
        return J.objects(lines)
    }

    /// All budgets together, with the Budgets screen's month-end projection
    /// and pace (spending ahead of an even pace isn't flagged while the
    /// projection stays within budget).
    private func overallBudget(
        _ budgeted: [TransactionCategory],
        spentByID: [String: Int],
        all: [TransactionRecord],
        month: MonthInterval,
        isCurrent: Bool,
        elapsed: Int,
        days: Int
    ) -> [String: JSONValue] {
        let totalBudget = budgeted.reduce(0) { $0 + ($1.monthlyBudgetCents ?? 0) }
        let totalSpent = budgeted.reduce(0) { $0 + (spentByID[$1.ledgerID] ?? 0) }
        let overall = BudgetProgress(budgetCents: totalBudget, spentCents: totalSpent)
        var projected = totalSpent
        if isCurrent {
            let ids = Set(budgeted.map { $0.ledgerID })
            let budgetedEntries = all.filter { record in
                guard let id = record.ledgerCategoryID else { return false }
                return ids.contains(id)
            }
            projected = max(projected, SpendingAnalytics.projectedSpending(budgetedEntries, month: month, asOf: now, calendar: calendar))
        }
        var pace = overall.pace(elapsedDays: elapsed, daysInMonth: days)
        if pace == .aheadOfPace, isCurrent, projected <= totalBudget {
            pace = .onTrack
        }
        var fields: [String: JSONValue] = [
            "budget": J.money(totalBudget),
            "spent": J.money(totalSpent),
            "left": J.money(overall.remainingCents),
            "used_pct": J.percent(overall.fractionUsed),
            "status": .string(J.paceName(pace)),
            "over_budget_count": J.int(budgeted.filter { (spentByID[$0.ledgerID] ?? 0) > ($0.monthlyBudgetCents ?? 0) }.count),
        ]
        if isCurrent { fields["projected_month_end"] = J.money(projected) }
        return fields
    }

    // MARK: - get_recurring_bills

    private func recurringBills() throws -> [String: JSONValue] {
        let items = try fetchRecurringItems()
        let month = MonthInterval.current(calendar: calendar, now: now)
        var result: [String: JSONValue] = [
            "currency": .string(currency),
            "today": J.day(now, calendar: calendar),
            "month": .string(J.monthString(month)),
        ]
        let all = try fetchTransactions()
        if items.isEmpty {
            result["message"] = .string("No recurring bills tracked yet. Add them in the Recurring tab.")
        } else {
            result.merge(trackedBills(items, transactions: all, month: month)) { _, new in new }
        }
        let suggestions = untrackedRecurring(items, transactions: all)
        if !suggestions.isEmpty {
            result["looks_recurring_but_not_tracked"] = J.objects(suggestions)
        }
        return result
    }

    /// Bills and this month's due dates, as on the Recurring screen.
    private func trackedBills(_ items: [RecurringItem], transactions: [TransactionRecord], month: MonthInterval) -> [String: JSONValue] {
        let interval = month.dateInterval(in: calendar)
        let windowStart = calendar.date(byAdding: .day, value: -7, to: interval.start) ?? interval.start
        let windowEnd = calendar.date(byAdding: .day, value: 7, to: interval.end) ?? interval.end
        let nearby = transactions.filter { $0.date >= windowStart && $0.date < windowEnd }

        var monthly = 0
        var yearly = 0
        var paidCents = 0
        var remainingCents = 0
        var paidCount = 0
        var upcomingCount = 0
        var lateCount = 0
        var bills: [(next: Date, fields: [String: JSONValue])] = []
        var paused: [[String: JSONValue]] = []

        for item in items {
            let next = item.nextDueDate(onOrAfter: now, calendar: calendar)
            var fields: [String: JSONValue] = [
                "name": J.text(item.name, limit: 80),
                "amount": J.money(item.amountCents),
                "frequency": .string(item.frequency.displayName),
                "monthly_cost": J.money(item.monthlyCostCents),
            ]
            if let category = item.category { fields["category"] = .string(category.name) }
            if !item.notes.isEmpty { fields["notes"] = J.text(item.notes, limit: 150) }
            guard item.isActive else {
                paused.append(fields)
                continue
            }
            monthly += item.monthlyCostCents
            yearly += item.frequency.yearlyCents(item.amountCents)
            fields["next_due"] = J.day(next, calendar: calendar)
            fields["days_until_next_due"] = J.int(calendar.daysBetween(now, next))

            let charges = nearby.filter { Categorizer.ruleMatches(ruleKey: item.merchantKey, merchantKey: $0.merchantKey) }
            var dueDates: [[String: JSONValue]] = []
            for due in item.schedule.occurrences(in: interval, calendar: calendar) {
                let status = RecurringMatcher.status(
                    dueDate: due, merchantKey: item.merchantKey, frequency: item.frequency,
                    entries: charges, now: now, calendar: calendar
                )
                switch status {
                case .paid(on: _, amountCents: let cents):
                    paidCents += cents
                    paidCount += 1
                case .upcoming:
                    remainingCents += item.amountCents
                    upcomingCount += 1
                case .late:
                    remainingCents += item.amountCents
                    lateCount += 1
                }
                dueDates.append(J.occurrence(dueDate: due, status: status, calendar: calendar))
            }
            fields["this_month"] = J.objects(dueDates)
            bills.append((next: next, fields: fields))
        }
        bills.sort { $0.next < $1.next }

        var result: [String: JSONValue] = [
            "bills": J.objects(bills.map { $0.fields }),
            "monthly_total": J.money(monthly),
            "yearly_total": J.money(yearly),
            "this_month": .object([
                "paid": J.money(paidCents),
                "still_due": J.money(remainingCents),
                "paid_count": J.int(paidCount),
                "upcoming_count": J.int(upcomingCount),
                "late_count": J.int(lateCount),
            ]),
        ]
        if !paused.isEmpty { result["paused"] = J.objects(paused) }
        return result
    }

    /// Merchants charged like a bill that aren't tracked (or dismissed) yet.
    private func untrackedRecurring(_ items: [RecurringItem], transactions: [TransactionRecord]) -> [[String: JSONValue]] {
        let trackedKeys = items.map { $0.merchantKey }
        let dismissed = (UserDefaults.standard.string(forKey: "dismissedRecurringSuggestions") ?? "")
            .split(separator: "\n")
            .map { String($0) }
        let excluded = Set(trackedKeys).union(dismissed)
        let candidates = RecurringDetector.candidates(from: transactions, now: now, calendar: calendar, excludingMerchantKeys: excluded)
            .filter { candidate in
                !trackedKeys.contains { Categorizer.ruleMatches(ruleKey: $0, merchantKey: candidate.merchantKey) }
            }
            .sorted { $0.typicalAmountCents > $1.typicalAmountCents }
        return candidates.prefix(8).map { candidate -> [String: JSONValue] in
            [
                "merchant": J.text(candidate.displayName, limit: 80),
                "amount": J.money(candidate.typicalAmountCents),
                "frequency": .string(candidate.frequency.displayName),
                "last_charged": J.day(candidate.lastDate, calendar: calendar),
                "next_expected": J.day(candidate.nextExpectedDate, calendar: calendar),
            ]
        }
    }

    // MARK: - get_accounts

    private func accounts() throws -> [String: JSONValue] {
        let accounts = try fetchAccounts()
        var result: [String: JSONValue] = [
            "currency": .string(currency),
            "today": J.day(now, calendar: calendar),
        ]
        guard !accounts.isEmpty else {
            result["accounts"] = .array([])
            result["message"] = .string("No accounts added yet. Add them in the Accounts tab.")
            return result
        }

        var assets = 0
        var liabilities = 0
        var observations: [BalanceObservation] = []
        for account in accounts where account.includeInNetWorth {
            if account.isLiability {
                liabilities += account.balanceCents
            } else {
                assets += account.balanceCents
            }
            let recorded = account.balanceObservations
            if recorded.isEmpty {
                // No history: the current balance has been known since its last update.
                observations.append(BalanceObservation(
                    accountID: account.id.uuidString,
                    date: min(account.balanceUpdatedAt, now),
                    balanceCents: account.balanceCents,
                    isLiability: account.isLiability
                ))
            } else {
                observations.append(contentsOf: recorded)
            }
        }
        let netWorth = accounts.reduce(0) { $0 + $1.netWorthContributionCents }
        result["net_worth"] = J.money(netWorth)
        result["assets"] = J.money(assets)
        result["liabilities"] = J.money(liabilities)
        result["balance_note"] = .string("For credit cards and loans, balance is the amount owed.")
        result["accounts"] = J.objects(accounts.map { accountFields($0) })
        result["by_group"] = accountGroups(accounts)
        result.merge(netWorthHistory(observations, netWorth: netWorth)) { _, new in new }
        if let change = netWorthChangeSinceMonthAgo(accounts, netWorth: netWorth) {
            result["change_last_month"] = J.money(change)
        }
        return result
    }

    private func accountFields(_ account: Account) -> [String: JSONValue] {
        var fields: [String: JSONValue] = [
            "name": J.text(account.name, limit: 60),
            "type": .string(account.kind.displayName),
            "balance": J.money(account.balanceCents),
            "balance_updated": J.day(account.balanceUpdatedAt, calendar: calendar),
        ]
        if !account.institution.isEmpty { fields["institution"] = J.text(account.institution, limit: 60) }
        if account.isLiability { fields["is_liability"] = .bool(true) }
        if !account.includeInNetWorth { fields["in_net_worth"] = .bool(false) }
        return fields
    }

    private func accountGroups(_ accounts: [Account]) -> JSONValue {
        var totals: [AccountGroup: Int] = [:]
        for account in accounts where account.includeInNetWorth {
            totals[account.kind.group, default: 0] += account.balanceCents
        }
        let lines = AccountGroup.allCases.compactMap { group -> [String: JSONValue]? in
            guard let cents = totals[group] else { return nil }
            return ["group": .string(group.title), "total": J.money(cents), "is_liability": .bool(group.isLiability)]
        }
        return J.objects(lines)
    }

    /// Net worth over the last six months (weekly, as on the Accounts tab's
    /// 6M chart), ending at today's balances.
    private func netWorthHistory(_ observations: [BalanceObservation], netWorth: Int) -> [String: JSONValue] {
        guard let earliest = observations.map({ $0.date }).min() else { return [:] }
        let dates = ChartRange.sixMonths.sampleDates(now: now, calendar: calendar)
        var history: [(date: Date, cents: Int)] = []
        for point in NetWorthCalculator.series(observations: observations, at: dates) where point.date >= earliest {
            history.append((date: point.date, cents: point.netCents))
        }
        if let last = history.last {
            history[history.count - 1] = (date: last.date, cents: netWorth)
        }
        var fields: [String: JSONValue] = [
            "net_worth_history": J.objects(history.map { point -> [String: JSONValue] in
                ["date": J.day(point.date, calendar: calendar), "net_worth": J.money(point.cents)]
            }),
        ]
        if history.count >= 2, let first = history.first {
            fields["change_over_history"] = J.money(netWorth - first.cents)
            fields["history_starts"] = J.day(first.date, calendar: calendar)
        }
        return fields
    }

    // MARK: - get_investments

    private func loadPortfolioIfNeeded() async {
        guard portfolio.lastLoaded == nil, !portfolio.isLoading, auth.userID != nil else { return }
        await portfolio.refresh()
    }

    /// Why there's nothing to show, or nil when there are holdings.
    private func portfolioUnavailable() -> [String: JSONValue]? {
        guard !portfolio.hasConnections, portfolio.holdings.isEmpty else { return nil }
        let message: String
        if portfolio.isLoading {
            message = "Investments are still loading. Try again in a moment."
        } else if portfolio.lastLoaded == nil, let error = portfolio.errorMessage {
            message = "Couldn't load investments: \(J.clipped(error, limit: 150))"
        } else if auth.userID == nil {
            message = "No brokerage connected (investing needs signing in to Haki)."
        } else {
            message = "No brokerage connected. Connect one in the Invest tab to see holdings here."
        }
        return ["connected": .bool(false), "message": .string(message)]
    }

    private func portfolioCurrency() -> String {
        portfolio.holdings.first?.currency ?? portfolio.accounts.first?.currency ?? "USD"
    }

    /// The overview's investing line.
    private func investmentSummary() -> [String: JSONValue] {
        if let unavailable = portfolioUnavailable() { return unavailable }
        let totals = portfolio.totals
        var fields: [String: JSONValue] = [
            "connected": .bool(true),
            "currency": .string(portfolioCurrency()),
            "total_value": J.dollars(totals.value),
            "positions": J.int(portfolio.positions.count),
        ]
        if let gainPct = totals.gainPct { fields["gain_pct"] = J.number(gainPct) }
        if portfolio.connections.contains(where: { $0.needsAttention }) { fields["a_brokerage_needs_attention"] = .bool(true) }
        return fields
    }

    private func investments() async -> [String: JSONValue] {
        await loadPortfolioIfNeeded()
        if let unavailable = portfolioUnavailable() { return unavailable }
        let totals = portfolio.totals
        let positions = portfolio.positions
        let costBases = portfolio.costBases

        var result: [String: JSONValue] = [
            "connected": .bool(true),
            "currency": .string(portfolioCurrency()),
            "total_value": J.dollars(totals.value),
            "positions_count": J.int(positions.count),
            "activity_amount_sign": .string("positive = cash spent (buys, fees), negative = cash received (sells, dividends, deposits)"),
        ]
        if totals.costBasis > 0 {
            result["cost_basis"] = J.dollars(totals.costBasis)
            result["gain"] = J.dollars(totals.gain)
            if let gainPct = totals.gainPct { result["gain_pct"] = J.number(gainPct) }
            if totals.valueWithCostBasis + 0.005 < totals.value {
                result["gain_note"] = .string("Gain counts only the holdings that report what was paid.")
            }
        }
        if let loaded = portfolio.lastLoaded { result["as_of"] = J.dateTime(loaded, calendar: calendar) }

        result["positions"] = J.objects(positions.prefix(30).map { position -> [String: JSONValue] in
            positionFields(position, costBasis: costBases[position.symbol])
        })
        if positions.count > 30 {
            result["truncated"] = .bool(true)
            result["other_positions_value"] = J.dollars(positions.dropFirst(30).reduce(0.0) { $0 + $1.value })
        }
        result["allocation"] = J.objects(portfolio.allocation.map { slice -> [String: JSONValue] in
            [
                "asset_class": .string(slice.assetClass.displayName),
                "value": J.dollars(slice.value),
                "weight_pct": J.number(slice.weightPct),
            ]
        })
        result["performance"] = .object(portfolioPerformance())
        result["brokerages"] = brokerageConnections()
        result["accounts"] = investmentAccounts()
        result["recent_activity"] = J.objects(portfolio.transactions.prefix(15).map { investmentActivity($0) })
        return result
    }

    private func positionFields(_ position: PortfolioPosition, costBasis: PositionCostBasis?) -> [String: JSONValue] {
        var fields: [String: JSONValue] = [
            "symbol": .string(position.symbol),
            "name": J.text(position.name, limit: 80),
            "asset_class": .string(AssetClass(plaidType: position.securityType).displayName),
            "quantity": J.number(position.quantity, places: 4),
            "value": J.dollars(position.value),
            "weight_pct": J.number(position.weightPct),
        ]
        if let cost = position.costBasis { fields["cost_basis"] = J.dollars(cost) }
        if let gain = position.gain { fields["gain"] = J.dollars(gain) }
        if let gainPct = position.gainPct { fields["gain_pct"] = J.number(gainPct) }
        if let average = costBasis?.averageCost { fields["average_cost"] = J.dollars(average) }
        if position.isCostBasisPartial { fields["cost_basis_partial"] = .bool(true) }
        return fields
    }

    /// Change in total value from the daily snapshots (includes deposits and withdrawals).
    private func portfolioPerformance() -> [String: JSONValue] {
        let points = portfolio.snapshots.compactMap { snapshot -> (date: Date, value: Double)? in
            guard let day = snapshot.day else { return nil }
            return (date: day, value: snapshot.totalValue)
        }
        guard let latest = points.last, let first = points.first else {
            return ["note": .string("No daily history yet.")]
        }
        var fields: [String: JSONValue] = [
            "latest_date": J.day(latest.date, calendar: calendar),
            "latest_value": J.dollars(latest.value),
            "history_starts": J.day(first.date, calendar: calendar),
            "note": .string("Value changes include deposits and withdrawals."),
        ]
        let spans: [(key: String, months: Int)] = [(key: "1_month", months: 1), (key: "3_months", months: 3), (key: "1_year", months: 12)]
        for span in spans {
            guard let target = calendar.date(byAdding: .month, value: -span.months, to: latest.date),
                  let past = points.last(where: { $0.date <= target })
            else { continue }
            fields["value_\(span.key)_ago"] = J.dollars(past.value)
            if let change = PortfolioMath.changePct(from: past.value, to: latest.value) {
                fields["change_pct_\(span.key)"] = J.number(change)
            }
        }
        return fields
    }

    private func brokerageConnections() -> JSONValue {
        let lines = portfolio.connections.map { connection -> [String: JSONValue] in
            var fields: [String: JSONValue] = [
                "institution": J.text(connection.institutionName, limit: 60),
                "status": .string(connection.status),
            ]
            if let synced = connection.lastSyncedAt { fields["last_synced"] = J.dateTime(synced, calendar: calendar) }
            if connection.needsAttention, let message = connection.errorMessage {
                fields["problem"] = J.text(message, limit: 200)
            }
            return fields
        }
        return J.objects(lines)
    }

    private func investmentAccounts() -> JSONValue {
        let lines = portfolio.accounts.map { account -> [String: JSONValue] in
            var fields: [String: JSONValue] = [
                "name": J.text(account.name, limit: 60),
                "type": .string(account.subtype ?? account.type),
            ]
            if let balance = account.currentBalance { fields["balance"] = J.dollars(balance) }
            if let connection = portfolio.connections.first(where: { $0.id == account.connectionID }) {
                fields["institution"] = J.text(connection.institutionName, limit: 60)
            }
            return fields
        }
        return J.objects(lines)
    }

    private func investmentActivity(_ transaction: InvestmentTransaction) -> [String: JSONValue] {
        var fields: [String: JSONValue] = [
            "date": .string(transaction.date),
            "type": .string(transaction.type),
            "name": J.text(transaction.name, limit: 80),
        ]
        if let subtype = transaction.subtype { fields["subtype"] = .string(subtype) }
        if let ticker = transaction.ticker { fields["ticker"] = .string(ticker) }
        if let quantity = transaction.quantity { fields["quantity"] = J.number(quantity, places: 4) }
        if let price = transaction.price { fields["price"] = J.dollars(price) }
        if let amount = transaction.amount { fields["amount"] = J.dollars(amount) }
        return fields
    }

    // MARK: - get_nutrition

    private func nutrition(_ use: AssistantToolUse) throws -> [String: JSONValue] {
        let range = J.dayRange(from: use.string("from"), to: use.string("to"), defaultDays: 7, maxDays: 92, now: now, calendar: calendar)
        let entries = try fetchFood(from: range.start, to: range.end)
        let (targets, isDefault) = nutritionTargets()

        var result: [String: JSONValue] = [
            "from": J.day(range.firstDay, calendar: calendar),
            "to": J.day(range.lastDay, calendar: calendar),
            "units": .string("calories in kcal, macros in grams"),
            "targets": .object([
                "calories": J.int(targets.calories),
                "protein_g": J.int(targets.proteinG),
                "carbs_g": J.int(targets.carbsG),
                "fat_g": J.int(targets.fatG),
                "fiber_g": J.int(targets.fiberG),
            ]),
            "targets_are_defaults": .bool(isDefault),
        ]

        var byDay: [String: [FoodEntry]] = [:]
        for entry in entries {
            byDay[J.dayString(entry.eatenAt, calendar: calendar), default: []].append(entry)
        }
        var days: [[String: JSONValue]] = []
        var loggedDays = 0
        var proteinDays = 0
        var overDays = 0
        var day = range.firstDay
        var guardCount = 0
        while day < range.end, guardCount < 400 {
            guardCount += 1
            let key = J.dayString(day, calendar: calendar)
            let dayEntries = byDay[key] ?? []
            if dayEntries.isEmpty {
                days.append(["date": .string(key), "entries": J.int(0)])
            } else {
                let progress = NutritionProgress(consumed: Macros.total(dayEntries.map { $0.macros }), targets: targets)
                loggedDays += 1
                if progress.hasHitProtein { proteinDays += 1 }
                if progress.isOverCalories { overDays += 1 }
                days.append(dayFields(key, progress: progress, count: dayEntries.count))
            }
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        result["days"] = J.objects(days)

        let streakStart = calendar.date(byAdding: .day, value: -180, to: calendar.startOfDay(for: now)) ?? now
        let streakEntries = try fetchFood(from: streakStart, to: Date.distantFuture)
        var summary: [String: JSONValue] = [
            "days_logged": J.int(loggedDays),
            "days_protein_goal_met": J.int(proteinDays),
            "days_over_calories": J.int(overDays),
            "logging_streak_days": J.int(NutritionStats.loggingStreak(entryDates: streakEntries.map { $0.eatenAt }, now: now, calendar: calendar)),
        ]
        let dated = entries.map { (date: $0.eatenAt, macros: $0.macros) }
        if let average = NutritionStats.averagePerLoggedDay(dated, calendar: calendar) {
            summary["average_per_logged_day"] = .object(macroFields(average))
        }
        result["summary"] = .object(summary)

        let newestFirst = Array(entries.reversed())
        result["entries"] = J.objects(newestFirst.prefix(80).map { foodFields($0) })
        if newestFirst.count > 80 { result["truncated"] = .bool(true) }
        if entries.isEmpty { result["message"] = .string("Nothing logged in the food log for these days.") }
        return withNotes(result, range.notes)
    }

    private func dayFields(_ day: String, progress: NutritionProgress, count: Int) -> [String: JSONValue] {
        var fields = macroFields(progress.consumed)
        fields["date"] = .string(day)
        fields["entries"] = J.int(count)
        if progress.remainingCalories < 0 {
            fields["calories_over_target"] = J.int(-progress.remainingCalories)
        } else {
            fields["calories_under_target"] = J.int(progress.remainingCalories)
        }
        fields["protein_goal_met"] = .bool(progress.hasHitProtein)
        return fields
    }

    private func macroFields(_ macros: Macros) -> [String: JSONValue] {
        [
            "calories": J.number(macros.calories, places: 0),
            "protein_g": J.number(macros.proteinG),
            "carbs_g": J.number(macros.carbsG),
            "fat_g": J.number(macros.fatG),
            "fiber_g": J.number(macros.fiberG),
        ]
    }

    private func foodFields(_ entry: FoodEntry) -> [String: JSONValue] {
        var fields = macroFields(entry.macros)
        fields["eaten_at"] = J.dateTime(entry.eatenAt, calendar: calendar)
        fields["meal"] = .string(entry.mealType.title)
        fields["name"] = J.text(entry.name, limit: 80)
        if !entry.portion.isEmpty { fields["portion"] = J.text(entry.portion, limit: 120) }
        if entry.servings != 1 { fields["servings"] = J.number(entry.servings, places: 2) }
        if entry.source.isAIEstimate { fields["ai_estimate"] = .bool(true) }
        if let place = entry.placeName, !place.isEmpty { fields["place"] = J.text(place, limit: 60) }
        if !entry.notes.isEmpty { fields["notes"] = J.text(entry.notes, limit: 150) }
        return fields
    }

    // MARK: - get_workouts

    private func workouts(_ use: AssistantToolUse) throws -> [String: JSONValue] {
        let unit = weightUnit()
        let distance = distanceUnit()
        let finished = try fetchFinishedWorkouts()
        if let exercise = use.string("exercise") {
            return exerciseHistory(exercise, use: use, finished: finished, weightUnit: unit, distanceUnit: distance)
        }
        let range = J.dayRange(from: use.string("from"), to: use.string("to"), defaultDays: 28, maxDays: 366, now: now, calendar: calendar)
        let inRange = finished.filter { $0.startedAt >= range.start && $0.startedAt < range.end }

        var result: [String: JSONValue] = [
            "from": J.day(range.firstDay, calendar: calendar),
            "to": J.day(range.lastDay, calendar: calendar),
            "weight_unit": .string(unit.symbol),
            "workouts_count": J.int(inRange.count),
            "total_volume": J.weight(inRange.reduce(0.0) { $0 + $1.volumeKg }, unit: unit),
            "total_sets": J.int(inRange.reduce(0) { $0 + $1.completedSetCount }),
            "total_time": .string(WorkoutMath.formatDuration(seconds: inRange.reduce(0) { $0 + $1.durationSeconds })),
            "week_streak": J.int(WorkoutMath.weekStreak(workoutDates: finished.map { $0.startedAt }, now: now, calendar: calendar)),
        ]
        let currentWeek = calendar.dateInterval(of: .weekOfYear, for: now)
        let thisWeek = finished.filter { currentWeek?.contains($0.startedAt) ?? false }
        result["this_week"] = .object([
            "workouts": J.int(thisWeek.count),
            "volume": J.weight(thisWeek.reduce(0.0) { $0 + $1.volumeKg }, unit: unit),
        ])

        // Every calendar week the range touches, so the weeks add up to the total.
        let lastMoment = min(now, range.end.addingTimeInterval(-1))
        let firstWeek = calendar.dateInterval(of: .weekOfYear, for: range.firstDay)?.start ?? range.firstDay
        let lastWeek = calendar.dateInterval(of: .weekOfYear, for: lastMoment)?.start ?? lastMoment
        let weekCount = max(1, min(54, calendar.daysBetween(firstWeek, lastWeek) / 7 + 1))
        let perWeek = WorkoutMath.workoutsPerWeek(
            workoutDates: inRange.map { $0.startedAt }, weeks: weekCount, now: lastMoment, calendar: calendar
        )
        result["per_week"] = J.objects(perWeek.map { entry -> [String: JSONValue] in
            ["week_of": J.day(entry.weekStart, calendar: calendar), "workouts": J.int(entry.count)]
        })
        result["sets_per_muscle"] = setsPerMuscle(inRange)
        result["personal_records"] = personalRecords(inRange, range: range, weightUnit: unit)

        let active = try context.fetch(FetchDescriptor<WorkoutRecord>(predicate: #Predicate<WorkoutRecord> { $0.endedAt == nil }))
        if let current = active.first {
            result["in_progress"] = .object([
                "title": J.text(current.title, limit: 80),
                "started_at": J.dateTime(current.startedAt, calendar: calendar),
            ])
        }

        result["workouts"] = J.objects(inRange.prefix(30).map { workout -> [String: JSONValue] in
            workoutFields(workout, weightUnit: unit, distanceUnit: distance)
        })
        if inRange.count > 30 { result["truncated"] = .bool(true) }
        if inRange.isEmpty { result["message"] = .string("No finished workouts in these days.") }
        return withNotes(result, range.notes)
    }

    private func setsPerMuscle(_ workouts: [WorkoutRecord]) -> JSONValue {
        var input: [(muscle: MuscleGroup, sets: [SetValues])] = []
        for workout in workouts {
            for exercise in workout.exercises {
                input.append((muscle: exercise.primaryMuscle, sets: exercise.setValues))
            }
        }
        let sorted = WorkoutMath.setsPerMuscle(input).sorted { lhs, rhs in
            if lhs.value != rhs.value { return lhs.value > rhs.value }
            return lhs.key.title < rhs.key.title
        }
        return J.objects(sorted.map { item -> [String: JSONValue] in
            ["muscle": .string(item.key.title), "sets": J.int(item.value)]
        })
    }

    /// All-time records for the exercises done most in the range, and which
    /// records were beaten during it.
    private func personalRecords(_ workouts: [WorkoutRecord], range: AssistantToolDayRange, weightUnit: WeightUnit) -> JSONValue {
        var frequency: [String: Int] = [:]
        var names: [String: String] = [:]
        var kinds: [String: ExerciseKind] = [:]
        for workout in workouts {
            for exercise in workout.exercises where !exercise.exerciseKey.isEmpty {
                frequency[exercise.exerciseKey, default: 0] += 1
                if names[exercise.exerciseKey] == nil {
                    names[exercise.exerciseKey] = exercise.name
                    kinds[exercise.exerciseKey] = exercise.kind
                }
            }
        }
        let keys = frequency
            .sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }
            .prefix(12)
            .map { $0.key }
        var lines: [[String: JSONValue]] = []
        for key in keys {
            let countsWeight = (kinds[key] ?? .weightReps).countsWeightForRecords
            let performances = WorkoutStore.performances(exerciseKey: key, in: context)
            let before = WorkoutMath.records(performances.filter { $0.date < range.start }, countsWeight: countsWeight)
            let through = WorkoutMath.records(performances.filter { $0.date < range.end }, countsWeight: countsWeight)
            var fields = J.records(WorkoutMath.records(performances, countsWeight: countsWeight), unit: weightUnit)
            fields["exercise"] = J.text(names[key] ?? key, limit: 80)
            fields["times_in_range"] = J.int(frequency[key] ?? 0)
            let improved = J.improvedRecords(before: before, after: through)
            if !improved.isEmpty { fields["new_records_in_range"] = J.strings(improved.map { $0.title }) }
            lines.append(fields)
        }
        return J.objects(lines)
    }

    private func workoutFields(_ workout: WorkoutRecord, weightUnit: WeightUnit, distanceUnit: DistanceUnit) -> [String: JSONValue] {
        var fields: [String: JSONValue] = [
            "date": J.dateTime(workout.startedAt, calendar: calendar),
            "title": J.text(workout.title, limit: 80),
            "duration": .string(WorkoutMath.formatDuration(seconds: workout.durationSeconds)),
            "volume": J.weight(workout.volumeKg, unit: weightUnit),
            "sets": J.int(workout.completedSetCount),
        ]
        if workout.source == .hevy { fields["from_hevy"] = .bool(true) }
        if !workout.notes.isEmpty { fields["notes"] = J.text(workout.notes, limit: 200) }
        fields["exercises"] = J.objects(workout.orderedExercises.prefix(15).map { exercise -> [String: JSONValue] in
            exerciseFields(exercise, weightUnit: weightUnit, distanceUnit: distanceUnit)
        })
        return fields
    }

    private func exerciseFields(_ exercise: WorkoutExerciseRecord, weightUnit: WeightUnit, distanceUnit: DistanceUnit) -> [String: JSONValue] {
        let sets = exercise.setValues
        var fields: [String: JSONValue] = [
            "name": J.text(exercise.name, limit: 80),
            "muscle": .string(exercise.primaryMuscle.title),
            "sets": J.strings(sets.prefix(12).map { J.setText($0, weightUnit: weightUnit, distanceUnit: distanceUnit) }),
        ]
        if exercise.kind.countsWeightForRecords, let best = WorkoutMath.bestSet(sets), let oneRepMax = best.estimatedOneRepMaxKg {
            fields["best_set"] = .string(J.setText(best, weightUnit: weightUnit, distanceUnit: distanceUnit))
            fields["estimated_1rm"] = J.weight(oneRepMax, unit: weightUnit)
        }
        if !exercise.notes.isEmpty { fields["notes"] = J.text(exercise.notes, limit: 120) }
        return fields
    }

    /// Every session of one exercise (matched by name), newest first, with records.
    private func exerciseHistory(
        _ query: String,
        use: AssistantToolUse,
        finished: [WorkoutRecord],
        weightUnit: WeightUnit,
        distanceUnit: DistanceUnit
    ) -> [String: JSONValue] {
        var counts: [String: Int] = [:]
        var display: [String: String] = [:]
        for workout in finished {
            for exercise in workout.exercises {
                let key = J.folded(exercise.name.trimmingCharacters(in: .whitespacesAndNewlines))
                guard !key.isEmpty else { continue }
                counts[key, default: 0] += 1
                if display[key] == nil { display[key] = exercise.name }
            }
        }
        let known = counts
            .sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }
            .map { $0.key }
        var result: [String: JSONValue] = ["weight_unit": .string(weightUnit.symbol)]
        guard let index = J.bestMatch(query, in: known) else {
            result["message"] = .string("No logged exercise called \"\(J.clipped(query, limit: 60))\".")
            result["logged_exercises"] = J.strings(known.prefix(40).map { display[$0] ?? $0 })
            return result
        }
        let wanted = known[index]

        var notes: [String] = []
        var lower = Date.distantPast
        var upper = Date.distantFuture
        if use.string("from") != nil || use.string("to") != nil {
            let range = J.dayRange(from: use.string("from"), to: use.string("to"), defaultDays: 365, maxDays: 3_660, now: now, calendar: calendar)
            lower = range.start
            upper = range.end
            notes = range.notes
            result["from"] = J.day(range.firstDay, calendar: calendar)
            result["to"] = J.day(range.lastDay, calendar: calendar)
        }

        var sessions: [(workout: WorkoutRecord, exercise: WorkoutExerciseRecord)] = []
        for workout in finished where workout.startedAt >= lower && workout.startedAt < upper {
            for exercise in workout.orderedExercises
            where J.folded(exercise.name.trimmingCharacters(in: .whitespacesAndNewlines)) == wanted {
                sessions.append((workout: workout, exercise: exercise))
            }
        }
        let countsWeight = sessions.first?.exercise.kind.countsWeightForRecords ?? true
        let performances = sessions.map { ExercisePerformance(date: $0.workout.startedAt, sets: $0.exercise.setValues) }

        result["exercise"] = .string(display[wanted] ?? wanted)
        result["sessions_count"] = J.int(sessions.count)
        result["records"] = .object(J.records(WorkoutMath.records(performances, countsWeight: countsWeight), unit: weightUnit))
        if let last = sessions.first { result["last_done"] = J.day(last.workout.startedAt, calendar: calendar) }
        if let first = sessions.last { result["first_done"] = J.day(first.workout.startedAt, calendar: calendar) }
        result["sessions"] = J.objects(sessions.prefix(40).map { session -> [String: JSONValue] in
            sessionFields(session.workout, exercise: session.exercise, countsWeight: countsWeight, weightUnit: weightUnit, distanceUnit: distanceUnit)
        })
        if sessions.count > 40 { result["truncated"] = .bool(true) }
        if sessions.isEmpty { notes.append("It wasn't done in these days.") }
        return withNotes(result, notes)
    }

    private func sessionFields(
        _ workout: WorkoutRecord,
        exercise: WorkoutExerciseRecord,
        countsWeight: Bool,
        weightUnit: WeightUnit,
        distanceUnit: DistanceUnit
    ) -> [String: JSONValue] {
        let sets = exercise.setValues
        var fields: [String: JSONValue] = [
            "date": J.day(workout.startedAt, calendar: calendar),
            "workout": J.text(workout.title, limit: 80),
            "sets": J.strings(sets.prefix(15).map { J.setText($0, weightUnit: weightUnit, distanceUnit: distanceUnit) }),
        ]
        if countsWeight {
            fields["volume"] = J.weight(WorkoutMath.volumeKg(sets), unit: weightUnit)
            if let best = WorkoutMath.bestSet(sets), let oneRepMax = best.estimatedOneRepMaxKg {
                fields["best_set"] = .string(J.setText(best, weightUnit: weightUnit, distanceUnit: distanceUnit))
                fields["estimated_1rm"] = J.weight(oneRepMax, unit: weightUnit)
            }
        }
        return fields
    }

    // MARK: - search_notes

    private func searchNotes(_ use: AssistantToolUse) throws -> [String: JSONValue] {
        let notes = try context.fetch(FetchDescriptor<Note>(sortBy: [SortDescriptor(\Note.updatedAt, order: .reverse)]))
        let limit = J.clamped(J.integer(use.input["limit"]), to: 1...10, default: 5)
        let query = use.string("query")
        let words = J.searchWords(query)

        var result: [String: JSONValue] = ["total_notes": J.int(notes.count)]
        if let query { result["query"] = J.text(query, limit: 80) }
        guard !notes.isEmpty else {
            result["notes"] = .array([])
            result["message"] = .string("No notes yet. Notes are in the You tab under Notes & Flashcards.")
            return result
        }

        let matching = notes.filter { J.matches(words, in: [$0.title, $0.body]) }
        let ordered: [Note]
        if words.isEmpty {
            // Pinned first, then the most recently edited (as in Notes).
            ordered = matching.filter { $0.isPinned } + matching.filter { !$0.isPinned }
        } else {
            // Notes whose title matches come first.
            ordered = matching.filter { J.matches(words, in: [$0.title]) } + matching.filter { !J.matches(words, in: [$0.title]) }
        }

        let decks = try fetchDecks()
        var decksByNote: [UUID: [String]] = [:]
        for deck in decks {
            if let noteID = deck.sourceNoteID { decksByNote[noteID, default: []].append(deck.name) }
        }

        result["matches"] = J.int(ordered.count)
        let textLimit = limit <= 5 ? 2_500 : 1_500
        result["notes"] = J.objects(ordered.prefix(limit).map { note -> [String: JSONValue] in
            noteFields(note, decks: decksByNote[note.id] ?? [], textLimit: textLimit)
        })
        if ordered.count > limit {
            result["truncated"] = .bool(true)
            result["showing"] = J.int(limit)
        }
        if ordered.isEmpty { result["message"] = .string("No notes match.") }
        return result
    }

    private func noteFields(_ note: Note, decks: [String], textLimit: Int) -> [String: JSONValue] {
        var fields: [String: JSONValue] = [
            "title": J.text(note.displayTitle, limit: 120),
            "updated": J.day(note.updatedAt, calendar: calendar),
            "created": J.day(note.createdAt, calendar: calendar),
            "text": J.text(note.body, limit: textLimit),
        ]
        if note.body.count > textLimit {
            fields["text_truncated"] = .bool(true)
            fields["full_length_characters"] = J.int(note.body.count)
        }
        if note.isPinned { fields["pinned"] = .bool(true) }
        if !decks.isEmpty { fields["flashcard_decks"] = J.strings(decks) }
        return fields
    }

    // MARK: - get_flashcards

    private func flashcards(_ use: AssistantToolUse) throws -> [String: JSONValue] {
        let decks = try fetchDecks()
        var result: [String: JSONValue] = ["now": J.dateTime(now, calendar: calendar)]
        guard !decks.isEmpty else {
            result["decks"] = .array([])
            result["message"] = .string("No flashcard decks yet. Decks are in the You tab under Notes & Flashcards.")
            return result
        }
        if let wanted = use.string("deck") {
            if let index = J.bestMatch(wanted, in: decks.map { $0.name }) {
                return deckDetail(decks[index])
            }
            result["message"] = .string("No deck called \"\(J.clipped(wanted, limit: 60))\"; here are all decks.")
        }

        result["total_cards"] = J.int(decks.reduce(0) { $0 + $1.cards.count })
        result["cards_due_now"] = J.int(decks.reduce(0) { $0 + $1.dueCount(now: now) })
        result["cards_to_study_now"] = J.int(decks.reduce(0) { $0 + StudyStore.studyQueue(for: $1, now: now, calendar: calendar).count })
        result["decks"] = J.objects(decks.prefix(40).map { deckSummary($0) })
        if decks.count > 40 { result["truncated"] = .bool(true) }

        var forgotten: [(card: Flashcard, deck: String)] = []
        for deck in decks {
            for card in deck.cards where card.lapses > 0 {
                forgotten.append((card: card, deck: deck.name))
            }
        }
        forgotten.sort { lhs, rhs in
            if lhs.card.lapses != rhs.card.lapses { return lhs.card.lapses > rhs.card.lapses }
            return lhs.card.ease < rhs.card.ease
        }
        result["most_forgotten"] = J.objects(forgotten.prefix(10).map { item -> [String: JSONValue] in
            cardFields(item.card, deckName: item.deck)
        })
        return result
    }

    private func deckSummary(_ deck: FlashcardDeck) -> [String: JSONValue] {
        let cards = deck.cards
        var fields: [String: JSONValue] = [
            "name": J.text(deck.name, limit: 80),
            "cards": J.int(cards.count),
            "due_now": J.int(deck.dueCount(now: now)),
            "new": J.int(deck.newCount),
            "to_study_now": J.int(StudyStore.studyQueue(for: deck, now: now, calendar: calendar).count),
            "new_cards_per_day": J.int(deck.newCardsPerDay),
            "mature": J.int(cards.filter { $0.schedule.isMature }.count),
        ]
        if !deck.details.isEmpty { fields["details"] = J.text(deck.details, limit: 200) }
        if let last = deck.lastStudiedAt { fields["last_studied"] = J.day(last, calendar: calendar) }
        let upcoming = cards.compactMap { card -> Date? in
            guard !card.schedule.isNew, let due = card.dueAt, due > now else { return nil }
            return due
        }
        if let next = upcoming.min() { fields["next_review"] = J.dateTime(next, calendar: calendar) }
        return fields
    }

    private func deckDetail(_ deck: FlashcardDeck) -> [String: JSONValue] {
        var result = deckSummary(deck)
        result["now"] = J.dateTime(now, calendar: calendar)
        let cards = deck.orderedCards
        result["card_list"] = J.objects(cards.prefix(150).map { cardFields($0, deckName: nil) })
        if cards.count > 150 { result["truncated"] = .bool(true) }
        return result
    }

    private func cardFields(_ card: Flashcard, deckName: String?) -> [String: JSONValue] {
        let schedule = card.schedule
        var fields: [String: JSONValue] = [
            "front": J.text(card.front, limit: 300),
            "back": J.text(card.back, limit: 300),
        ]
        if schedule.isNew {
            fields["status"] = .string("new")
        } else {
            fields["status"] = .string(SpacedRepetition.isDue(schedule, now: now) ? "due" : "scheduled")
            if let due = schedule.dueAt { fields["next_review"] = J.dateTime(due, calendar: calendar) }
            fields["interval"] = .string(SpacedRepetition.intervalText(days: schedule.intervalDays))
            fields["correct_in_a_row"] = J.int(schedule.repetitions)
        }
        if schedule.lapses > 0 { fields["times_forgotten"] = J.int(schedule.lapses) }
        if let deckName { fields["deck"] = J.text(deckName, limit: 80) }
        return fields
    }

    // MARK: - get_wardrobe

    private func wardrobe(_ use: AssistantToolUse) throws -> [String: JSONValue] {
        let items = try context.fetch(FetchDescriptor<ClothingItem>(sortBy: [SortDescriptor(\ClothingItem.createdAt, order: .reverse)]))
        let outfits = try context.fetch(FetchDescriptor<Outfit>(sortBy: [SortDescriptor(\Outfit.createdAt, order: .reverse)]))
        var result: [String: JSONValue] = [
            "currency": .string(currency),
            "today": J.day(now, calendar: calendar),
            "current_season": .string(ClothingSeason.current(on: now, calendar: calendar).title),
            "scales": .string("formality 1 (very casual) to 5 (black tie); warmth 1 (very light) to 5 (very warm)"),
        ]
        guard !items.isEmpty || !outfits.isEmpty else {
            result["pieces"] = .array([])
            result["message"] = .string("The wardrobe is empty. Pieces are added in the You tab under Wardrobe.")
            return result
        }

        var notes: [String] = []
        var filters: [String: JSONValue] = [:]
        let category = readFilter(use.string("category"), name: "category", parse: { J.clothingCategory($0) }, notes: &notes)
        let color = readFilter(use.string("color"), name: "color", parse: { ClothingColor.guess($0) }, notes: &notes)
        let season = readFilter(use.string("season"), name: "season", parse: { J.clothingSeason($0) }, notes: &notes)
        let style = readFilter(use.string("style"), name: "style", parse: { J.clothingStyle($0) }, notes: &notes)
        if let category { filters["category"] = .string(category.title) }
        if let color { filters["color"] = .string(color.title) }
        if let season { filters["season"] = .string(season.title) }
        if let style { filters["style"] = .string(style.title) }
        let isFiltered = !filters.isEmpty

        let pieces = items.filter { item in
            if let category, item.category != category { return false }
            if let color, !item.colors.contains(color) { return false }
            if let season, !item.seasons.isEmpty, !item.seasons.contains(season) { return false }
            if let style, !item.styles.contains(style) { return false }
            return true
        }

        result["stats"] = .object(wardrobeStats(items, outfitCount: outfits.count))
        if isFiltered {
            result["filters"] = .object(filters)
            result["matching_pieces"] = J.int(pieces.count)
        }
        result["pieces"] = J.objects(pieces.prefix(120).map { clothingFields($0) })
        if pieces.count > 120 { result["truncated"] = .bool(true) }

        // With filters, the outfits that use a matching piece.
        let matchingIDs = Set(pieces.map { $0.id })
        var shownOutfits = outfits
        if isFiltered {
            shownOutfits = outfits.filter { outfit in
                outfit.items.contains(where: { matchingIDs.contains($0.id) })
            }
        }
        result["outfits"] = J.objects(shownOutfits.prefix(40).map { outfitFields($0) })
        if shownOutfits.count > 40 { result["truncated"] = .bool(true) }
        if isFiltered, pieces.isEmpty { notes.append("No pieces match those filters.") }
        return withNotes(result, notes)
    }

    /// A filter value, or nil (with a note when the text wasn't understood).
    private func readFilter<Value>(_ text: String?, name: String, parse: (String) -> Value?, notes: inout [String]) -> Value? {
        guard let text else { return nil }
        if let value = parse(text) { return value }
        notes.append("Didn't recognize the \(name) \"\(J.clipped(text, limit: 40))\", so it wasn't used.")
        return nil
    }

    private func wardrobeStats(_ items: [ClothingItem], outfitCount: Int) -> [String: JSONValue] {
        let wear = items.map { $0.wearInfo }
        let byID = Dictionary(items.map { ($0.id.uuidString, $0) }, uniquingKeysWith: { first, _ in first })
        let mostWorn = WardrobeStats.mostWorn(wear, limit: 5).compactMap { byID[$0] }
        let forgotten = WardrobeStats.forgotten(wear, days: 90, now: now).compactMap { byID[$0] }
        var counts: [ClothingCategory: Int] = [:]
        for item in items {
            counts[item.category, default: 0] += 1
        }
        let byCategory = ClothingCategory.allCases.compactMap { kind -> [String: JSONValue]? in
            guard let count = counts[kind], count > 0 else { return nil }
            return ["category": .string(kind.title), "pieces": J.int(count)]
        }
        var fields: [String: JSONValue] = [
            "pieces": J.int(items.count),
            "outfits": J.int(outfitCount),
            "by_category": J.objects(byCategory),
            "favorites": J.int(items.filter { $0.isFavorite }.count),
            "never_worn": J.int(items.filter { $0.timesWorn == 0 }.count),
            "most_worn": J.strings(mostWorn.map { "\($0.name) (\($0.timesWorn)×)" }),
            "not_worn_in_90_days": J.int(forgotten.count),
            "not_worn_in_90_days_examples": J.strings(forgotten.prefix(10).map { $0.name }),
        ]
        let totalValue = items.reduce(0) { $0 + ($1.priceCents ?? 0) }
        if totalValue > 0 { fields["total_value"] = J.money(totalValue) }
        return fields
    }

    private func clothingFields(_ item: ClothingItem) -> [String: JSONValue] {
        var fields: [String: JSONValue] = [
            "name": J.text(item.name, limit: 80),
            "category": .string(item.category.singularTitle),
            "colors": J.strings(item.colors.map { $0.title }),
            "seasons": item.seasons.isEmpty ? JSONValue.string("any") : J.strings(item.seasons.map { $0.title }),
            "styles": J.strings(item.styles.map { $0.title }),
            "formality": J.int(item.formality),
            "warmth": J.int(item.warmth),
            "times_worn": J.int(item.timesWorn),
            "added": J.day(item.createdAt, calendar: calendar),
        ]
        if !item.pattern.isEmpty { fields["pattern"] = J.text(item.pattern, limit: 40) }
        if !item.brand.isEmpty { fields["brand"] = J.text(item.brand, limit: 60) }
        if let last = item.lastWornAt { fields["last_worn"] = J.day(last, calendar: calendar) }
        if let price = item.priceCents { fields["price"] = J.money(price) }
        if let costPerWear = WardrobeStats.costPerWearCents(priceCents: item.priceCents, timesWorn: item.timesWorn) {
            fields["cost_per_wear"] = J.money(costPerWear)
        }
        if item.isFavorite { fields["favorite"] = .bool(true) }
        if !item.notes.isEmpty { fields["notes"] = J.text(item.notes, limit: 120) }
        return fields
    }

    private func outfitFields(_ outfit: Outfit) -> [String: JSONValue] {
        let pieces = outfit.items
        let categories = pieces.map { $0.category }
        var fields: [String: JSONValue] = [
            "name": J.text(outfit.name, limit: 80),
            "pieces": J.strings(pieces.map { $0.name }),
            "complete": .bool(OutfitRules.isComplete(categories)),
            "times_worn": J.int(outfit.timesWorn),
        ]
        if let hint = OutfitRules.hint(categories) { fields["missing"] = .string(hint) }
        if !outfit.occasion.isEmpty { fields["occasion"] = J.text(outfit.occasion, limit: 60) }
        if let last = outfit.lastWornAt { fields["last_worn"] = J.day(last, calendar: calendar) }
        if outfit.isFavorite { fields["favorite"] = .bool(true) }
        if outfit.isAISuggested { fields["from_ai_idea"] = .bool(true) }
        if !outfit.notes.isEmpty { fields["notes"] = J.text(outfit.notes, limit: 150) }
        return fields
    }

    // MARK: - get_social

    private func socialProfile() async -> [String: JSONValue] {
        guard let userID = auth.userID else {
            return [
                "signed_in": .bool(false),
                "message": .string("Not signed in to Haki, so there's no profile or feed."),
            ]
        }
        var result: [String: JSONValue] = ["signed_in": .bool(true)]
        if let profile = auth.profile {
            result["username"] = .string(profile.username)
            result["display_name"] = J.text(profile.name, limit: 80)
            result["shares_portfolio"] = .bool(profile.sharePortfolio)
            if !profile.bio.isEmpty { result["bio"] = J.text(profile.bio, limit: 300) }
        }
        do {
            let stats = try await social.profile(id: userID)
            result["username"] = .string(stats.username)
            result["display_name"] = J.text(stats.name, limit: 80)
            result["followers"] = J.int(stats.followerCount)
            result["following"] = J.int(stats.followingCount)
            result["posts"] = J.int(stats.postCount)
            result["joined"] = J.day(stats.createdAt, calendar: calendar)
        } catch {
            result["counts_unavailable"] = J.text(error.localizedDescription, limit: 150)
        }
        do {
            let posts = try await social.posts(byAuthor: userID, before: nil, limit: 10)
            result["recent_posts"] = J.objects(posts.map { postFields($0) })
        } catch {
            result["posts_unavailable"] = J.text(error.localizedDescription, limit: 150)
        }
        return result
    }

    private func postFields(_ post: FeedPost) -> [String: JSONValue] {
        var fields: [String: JSONValue] = [
            "date": J.dateTime(post.createdAt, calendar: calendar),
            "kind": .string(post.kind.rawValue),
            "likes": J.int(post.likeCount),
            "comments": J.int(post.commentCount),
        ]
        if !post.caption.isEmpty { fields["caption"] = J.text(post.caption, limit: 300) }
        if let ticker = post.ticker { fields["ticker"] = .string(ticker) }
        if let side = post.tradeSide { fields["trade_side"] = .string(side.rawValue) }
        if post.imagePath != nil { fields["has_photo"] = .bool(true) }
        if let shared = post.attachment {
            fields["shared_portfolio"] = J.objects(shared.holdings.map { holding -> [String: JSONValue] in
                ["ticker": .string(holding.ticker), "weight_pct": J.number(holding.weightPct)]
            })
            if let gain = shared.totalGainPct { fields["shared_total_gain_pct"] = J.number(gain) }
        }
        return fields
    }
}
