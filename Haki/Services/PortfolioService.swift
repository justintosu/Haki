//
//  PortfolioService.swift
//  Haki
//
//  The signed-in user's linked brokerages (through Plaid, via the `plaid`
//  edge function) and the holdings, transactions and daily snapshots the
//  server syncs from them. Read-only: Haki never places trades or moves money.
//  Injected with `.environment(PortfolioService.live)`, read with
//  `@Environment(PortfolioService.self) private var portfolio`.
//

import Foundation
import Observation
import Supabase

@Observable final class PortfolioService {
    private(set) var connections: [BrokerageConnection] = []
    private(set) var accounts: [InvestmentAccount] = []
    private(set) var holdings: [BrokerageHolding] = []
    /// Newest first.
    private(set) var transactions: [InvestmentTransaction] = []
    /// Oldest first.
    private(set) var snapshots: [PortfolioSnapshot] = []
    private(set) var isLoading = false
    private(set) var isSyncing = false
    private(set) var lastLoaded: Date?
    var errorMessage: String?

    private let client: SupabaseClient?
    /// Bumped by every refresh and by `reset()`; only the latest refresh applies its results.
    @ObservationIgnored private var refreshGeneration = 0
    @ObservationIgnored private var refreshesInFlight = 0
    @ObservationIgnored private var syncsInFlight = 0
    /// Bumped by `reset()` (sign-out) only, so work started for the previous session stops.
    @ObservationIgnored private var sessionGeneration = 0
    /// When a sync (manual or automatic) last started, for throttling `syncIfDue()`.
    @ObservationIgnored private var lastSyncAttempt: Date?

    /// How long a connection may go without syncing before `syncIfDue()` pulls fresh data.
    private static let autoSyncAge: TimeInterval = 12 * 3600
    /// The least time between automatic attempts: a connection that keeps failing
    /// never advances `last_synced_at`, and mustn't call the brokerage on every refresh.
    private static let autoSyncRetryInterval: TimeInterval = 3 * 3600

    /// `nil` = preview mode with sample holdings.
    init(client: SupabaseClient?) {
        self.client = client
        if client == nil {
            connections = PortfolioPreviewSamples.connections
            accounts = PortfolioPreviewSamples.accounts
            holdings = PortfolioPreviewSamples.holdings
            transactions = PortfolioPreviewSamples.transactions
            snapshots = PortfolioPreviewSamples.snapshots
            lastLoaded = .now
        }
    }

    static let preview = PortfolioService(client: nil)
    static let live = PortfolioService(client: Backend.client)

    // MARK: Derived values

    var hasConnections: Bool { !connections.isEmpty }

    /// Holdings merged by symbol across accounts, largest first.
    var positions: [PortfolioPosition] { PortfolioMath.positions(holdings.map(\.input)) }

    var totals: PortfolioTotals { PortfolioMath.totals(holdings.map(\.input)) }

    /// Cost and return per position `symbol` (the keys of `positions`), counting
    /// only the holdings that report what was paid.
    var costBases: [String: PositionCostBasis] {
        Dictionary(grouping: holdings.filter { $0.value > 0 }) { holding -> String in
            // The same key `PortfolioMath.positions` merges by.
            if let ticker = holding.ticker?.trimmingCharacters(in: .whitespaces), !ticker.isEmpty {
                return ticker.uppercased()
            }
            return holding.name
        }
        .mapValues { PositionCostBasis(holdings: $0) }
    }

    /// By asset class, largest first.
    var allocation: [AllocationSlice] { PortfolioMath.allocation(holdings.map(\.input)) }

    /// Percentages-only snapshot for sharing: the top `limit` positions (cash excluded) plus "Other".
    func sharedPortfolio(limit: Int) -> SharedPortfolio {
        PortfolioMath.sharedPortfolio(holdings.map(\.input), limit: limit)
    }

    /// The position for a ticker (case-insensitive) or, for securities without one, its name.
    func position(for ticker: String) -> PortfolioPosition? {
        let symbol = Self.normalizedSymbol(ticker)
        guard !symbol.isEmpty else { return nil }
        return positions.first { $0.symbol.uppercased() == symbol || $0.symbol == ticker }
    }

    /// The holdings (one per account) behind a position's `symbol`.
    func holdings(for symbol: String) -> [BrokerageHolding] {
        let wanted = Self.normalizedSymbol(symbol)
        return holdings.filter { holding in
            let ticker = holding.ticker?.trimmingCharacters(in: .whitespaces) ?? ""
            if !ticker.isEmpty {
                return ticker.uppercased() == wanted
            }
            return holding.name == symbol
        }
    }

    func account(id: UUID) -> InvestmentAccount? {
        accounts.first { $0.id == id }
    }

    // MARK: Loading

    /// Reloads every table from the database, then starts a background sync
    /// when the brokerages are due for one (see `syncIfDue()`).
    func refresh() async {
        guard let client else {
            lastLoaded = .now
            return
        }
        refreshGeneration += 1
        let generation = refreshGeneration
        refreshesInFlight += 1
        isLoading = true
        defer {
            refreshesInFlight -= 1
            isLoading = refreshesInFlight > 0
        }

        do {
            // Its own task, so leaving the screen that started the refresh doesn't
            // cancel it: other screens skip loading while one is in flight, so it
            // has to end with either data or an error.
            let tables = try await Task { try await PortfolioService.fetchTables(client) }.value
            guard generation == refreshGeneration else { return }
            connections = tables.connections
            accounts = tables.accounts
            holdings = tables.holdings
            transactions = tables.transactions
            snapshots = tables.snapshots
            lastLoaded = .now
            errorMessage = nil
            syncIfDue()
        } catch {
            guard generation == refreshGeneration, !Backend.isCancellation(error) else { return }
            errorMessage = Backend.userFacingError(error, fallback: "Couldn't load your investments. Pull to refresh.")
                .localizedDescription
        }
    }

    func createLinkToken() async throws -> String {
        guard let client else {
            throw BackendError(code: "preview", message: "Connecting a brokerage isn't available in previews.")
        }
        do {
            let response: PortfolioLinkTokenResponse = try await client.functions.invoke(
                "plaid",
                options: FunctionInvokeOptions(body: PortfolioPlaidRequest(action: "link_token"))
            )
            return response.linkToken
        } catch {
            throw Self.plaidError(error)
        }
    }

    /// Exchanges the public token (edge function), then refreshes. Refreshes on
    /// failure too: the server may have saved the connection before its reply
    /// was lost, and it should show up rather than invite linking it twice.
    func completeLink(publicToken: String, institutionID: String?, institutionName: String?) async throws {
        guard client != nil else { return }
        let knownConnectionIDs: Set<UUID>? = lastLoaded == nil ? nil : Set(connections.map(\.id))
        lastSyncAttempt = .now
        beginSync()
        defer { endSync() }
        let request = PortfolioPlaidRequest(
            action: "exchange",
            publicToken: publicToken,
            institutionID: institutionID,
            institutionName: institutionName
        )
        do {
            try await invokePlaid(request)
        } catch {
            await refresh()
            scheduleFollowUpSync(knownConnectionIDs: knownConnectionIDs)
            throw error
        }
        await refresh()
        scheduleFollowUpSync(knownConnectionIDs: knownConnectionIDs)
    }

    /// Pulls fresh data from the brokerages (edge function), then refreshes.
    func sync() async throws {
        try await performSync(reportsErrors: true)
    }

    /// Starts a background sync when a connection hasn't synced for about half
    /// a day, so holdings stay current and the performance history gains a
    /// point each day Haki is used. Returns right away; the sync's errors
    /// aren't reported (the connection rows show their status).
    func syncIfDue() {
        guard client != nil, !isSyncing, isSyncDue(now: .now) else { return }
        lastSyncAttempt = .now
        let session = sessionGeneration
        // Unstructured, so leaving the screen doesn't cancel the edge-function call.
        Task {
            guard session == self.sessionGeneration else { return }
            try? await self.performSync(reportsErrors: false)
        }
    }

    func removeConnection(_ connection: BrokerageConnection) async throws {
        if client != nil {
            let request = PortfolioPlaidRequest(action: "remove", connectionID: connection.id.uuidString.lowercased())
            do {
                try await invokePlaid(request)
            } catch let error as BackendError where error.code == "not_found" {
                // Already gone on the server (removed on another device, or an
                // earlier attempt whose reply was lost): finish removing it here.
            }
        }
        removeLocally(connection.id)
        if client != nil {
            await refresh()
        }
    }

    /// Clears everything (on sign-out).
    func reset() {
        refreshGeneration += 1
        sessionGeneration += 1
        lastSyncAttempt = nil
        connections = []
        accounts = []
        holdings = []
        transactions = []
        snapshots = []
        lastLoaded = nil
        errorMessage = nil
    }

    // MARK: - Helpers

    private func performSync(reportsErrors: Bool) async throws {
        guard client != nil else { return }
        let session = sessionGeneration
        // Before the refresh below, which would otherwise start an automatic sync too.
        lastSyncAttempt = .now
        if lastLoaded == nil {
            await refresh()
        }
        // Nothing to pull from: don't bother the server (or Plaid).
        guard !connections.isEmpty else { return }

        beginSync()
        defer { endSync() }
        do {
            try await invokePlaid(PortfolioPlaidRequest(action: "sync"))
        } catch {
            if reportsErrors, session == sessionGeneration, !Backend.isCancellation(error) {
                errorMessage = error.localizedDescription
            }
            throw error
        }
        // Signed out meanwhile: don't load the next session's data as this one's.
        guard session == sessionGeneration else { return }
        await refresh()
    }

    /// Whether a connection that can sync hasn't for `autoSyncAge`, and no sync
    /// was attempted recently.
    private func isSyncDue(now: Date) -> Bool {
        if let lastSyncAttempt, now.timeIntervalSince(lastSyncAttempt) < Self.autoSyncRetryInterval {
            return false
        }
        // These wait for the user (sign in again, relink); syncing won't fix them.
        let syncable = connections.filter { $0.status != "needs_attention" }
        return syncable.contains { connection in
            guard let last = connection.lastSyncedAt else { return true }
            return now.timeIntervalSince(last) >= Self.autoSyncAge
        }
    }

    /// Right after linking, Plaid often isn't ready with holdings or
    /// transactions yet (the server skips them until it is). If the new
    /// connection came back without them, sync once more a little later.
    private func scheduleFollowUpSync(knownConnectionIDs: Set<UUID>?) {
        let added = Set(connections.map(\.id)).subtracting(knownConnectionIDs ?? Set<UUID>())
        guard !added.isEmpty else { return }
        let addedAccountIDs = Set(accounts.filter { added.contains($0.connectionID) }.map(\.id))
        let hasHoldings = holdings.contains { addedAccountIDs.contains($0.accountID) }
        let hasTransactions = transactions.contains { addedAccountIDs.contains($0.accountID) }
        guard !hasHoldings || !hasTransactions else { return }

        let session = sessionGeneration
        Task {
            try? await Task.sleep(for: .seconds(90))
            guard session == self.sessionGeneration, self.hasConnections, !self.isSyncing else { return }
            try? await self.performSync(reportsErrors: false)
        }
    }

    private func beginSync() {
        syncsInFlight += 1
        isSyncing = true
    }

    private func endSync() {
        syncsInFlight = max(0, syncsInFlight - 1)
        isSyncing = syncsInFlight > 0
    }

    private func removeLocally(_ connectionID: UUID) {
        let accountIDs = Set(accounts.filter { $0.connectionID == connectionID }.map(\.id))
        connections.removeAll { $0.id == connectionID }
        accounts.removeAll { accountIDs.contains($0.id) }
        holdings.removeAll { accountIDs.contains($0.accountID) }
        transactions.removeAll { accountIDs.contains($0.accountID) }
    }

    private func invokePlaid(_ request: PortfolioPlaidRequest) async throws {
        guard let client else { return }
        do {
            try await client.functions.invoke("plaid", options: FunctionInvokeOptions(body: request))
        } catch {
            throw Self.plaidError(error)
        }
    }

    private static func normalizedSymbol(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "$"))
            .uppercased()
    }

    private static func plaidError(_ error: any Error) -> any Error {
        if Backend.isCancellation(error) { return error }
        if let body = Backend.functionErrorBody(error) {
            switch body.code {
            case "plaid_not_configured":
                return BackendError(code: "plaid_not_configured", message: "Brokerage connections aren't set up on the server yet.")
            case "unauthorized":
                return BackendError(code: "unauthorized", message: "Your session has expired. Sign in again.")
            case "not_found":
                return BackendError(code: "not_found", message: body.message ?? "That brokerage connection no longer exists.")
            case "plaid_error":
                return BackendError(code: "plaid_error", message: body.message ?? "Your brokerage couldn't be reached. Try again later.")
            case "bad_request":
                return BackendError(code: "bad_request", message: body.message ?? "The server couldn't handle that request.")
            case "server_error":
                return BackendError(code: "server_error", message: "Haki's server ran into a problem. Try again in a moment.")
            default:
                if body.status == 404 {
                    // The function itself isn't deployed.
                    return BackendError(code: "plaid_not_configured", message: "Brokerage connections aren't set up on the server yet.")
                }
            }
        }
        return Backend.userFacingError(error, fallback: "Couldn't reach your brokerage. Try again.")
    }

    private static func fetchTables(_ client: SupabaseClient) async throws -> PortfolioTables {
        async let connections: [BrokerageConnection] = client
            .from("brokerage_connections")
            .select("id,institution_name,status,error_message,last_synced_at,created_at")
            .order("created_at", ascending: true)
            .execute()
            .value
        async let accounts: [InvestmentAccount] = client
            .from("investment_accounts")
            .select("id,connection_id,name,official_name,mask,type,subtype,current_balance,currency")
            .order("name", ascending: true)
            .execute()
            .value
        async let holdings: [BrokerageHolding] = client
            .from("holdings")
            .select("id,account_id,security_id,ticker,name,security_type,quantity,price,price_as_of,value,cost_basis,currency,updated_at")
            .order("value", ascending: false)
            .execute()
            .value
        async let transactions: [InvestmentTransaction] = client
            .from("investment_transactions")
            .select("id,account_id,date,name,ticker,security_name,type,subtype,quantity,price,amount,fees,currency")
            .order("date", ascending: false)
            .limit(500)
            .execute()
            .value
        // Newest ~13 months (the chart's widest range is a year), put back in
        // chronological order below.
        async let recentSnapshots: [PortfolioSnapshot] = client
            .from("portfolio_snapshots")
            .select("date,total_value,cost_basis")
            .order("date", ascending: false)
            .limit(400)
            .execute()
            .value

        return PortfolioTables(
            connections: try await connections,
            accounts: try await accounts,
            holdings: try await holdings,
            transactions: try await transactions,
            snapshots: try await recentSnapshots.reversed()
        )
    }
}

// MARK: - Cost basis

/// A position's cost and return counting only the holdings that report what
/// was paid, as `PortfolioTotals` does. (`PortfolioPosition.gain` compares
/// the whole position's value with that partial cost, so lots without a cost
/// basis would count as pure gain.)
nonisolated struct PositionCostBasis: Hashable {
    /// What was paid for the holdings that report it; `nil` when none does.
    let costBasis: Double?
    /// Shares (or units) of the holdings that report a cost basis.
    let quantity: Double
    /// Value of the holdings that report a cost basis.
    let value: Double
    /// Shares of the whole position.
    let totalQuantity: Double
    /// Value of the whole position.
    let totalValue: Double

    /// One position's holdings (any account). Holdings worth nothing are
    /// skipped, as in `PortfolioMath.positions`.
    init(holdings: [BrokerageHolding]) {
        var cost = 0.0
        var quantity = 0.0
        var value = 0.0
        var totalQuantity = 0.0
        var totalValue = 0.0
        var hasCost = false
        for holding in holdings where holding.value > 0 {
            totalQuantity += holding.quantity
            totalValue += holding.value
            if let basis = holding.costBasis, basis > 0 {
                hasCost = true
                cost += basis
                quantity += holding.quantity
                value += holding.value
            }
        }
        self.costBasis = hasCost ? cost : nil
        self.quantity = quantity
        self.value = value
        self.totalQuantity = totalQuantity
        self.totalValue = totalValue
    }

    /// When the holdings aren't known: the position's own (all-or-nothing) figures.
    init(position: PortfolioPosition) {
        let hasCost = (position.costBasis ?? 0) > 0
        costBasis = hasCost ? position.costBasis : nil
        quantity = hasCost ? position.quantity : 0
        value = hasCost ? position.value : 0
        totalQuantity = position.quantity
        totalValue = position.value
    }

    var gain: Double? { costBasis.map { value - $0 } }

    /// Return on cost, in percent.
    var gainPct: Double? {
        guard let costBasis, costBasis > 0 else { return nil }
        return (value - costBasis) / costBasis * 100
    }

    /// Cost per share of the holdings that report one.
    var averageCost: Double? {
        guard let costBasis, quantity > 0 else { return nil }
        return costBasis / quantity
    }

    /// Some of the position (by value) has no reported cost basis.
    var isPartial: Bool { costBasis != nil && value + 0.005 < totalValue }
}

// MARK: - Request and response bodies

nonisolated private struct PortfolioTables {
    var connections: [BrokerageConnection]
    var accounts: [InvestmentAccount]
    var holdings: [BrokerageHolding]
    var transactions: [InvestmentTransaction]
    var snapshots: [PortfolioSnapshot]
}

/// Body of a `plaid` edge-function call; `nil` fields aren't sent.
nonisolated private struct PortfolioPlaidRequest: Encodable {
    let action: String
    var publicToken: String? = nil
    var institutionID: String? = nil
    var institutionName: String? = nil
    var connectionID: String? = nil

    enum CodingKeys: String, CodingKey {
        case action
        case publicToken = "public_token"
        case institutionID = "institution_id"
        case institutionName = "institution_name"
        case connectionID = "connection_id"
    }
}

nonisolated private struct PortfolioLinkTokenResponse: Decodable {
    let linkToken: String

    enum CodingKeys: String, CodingKey {
        case linkToken = "link_token"
    }
}

// MARK: - Preview data

/// Sample brokerage data for preview mode: two connections (one needing
/// attention), a taxable account and an IRA, and four months of history.
private enum PortfolioPreviewSamples {
    static let brokerageConnectionID = sampleID(1)
    static let retirementConnectionID = sampleID(2)
    static let brokerageAccountID = sampleID(11)
    static let iraAccountID = sampleID(12)

    static let connections: [BrokerageConnection] = [
        BrokerageConnection(
            id: brokerageConnectionID,
            institutionName: "Northwind Investing",
            status: "active",
            errorMessage: nil,
            lastSyncedAt: Date.now.addingTimeInterval(-2 * 3600),
            createdAt: Date.now.addingTimeInterval(-90 * 86_400)
        ),
        BrokerageConnection(
            id: retirementConnectionID,
            institutionName: "Harbor Retirement",
            status: "needs_attention",
            errorMessage: "Sign in to Harbor Retirement again to keep syncing.",
            lastSyncedAt: Date.now.addingTimeInterval(-3 * 86_400),
            createdAt: Date.now.addingTimeInterval(-60 * 86_400)
        ),
    ]

    static let accounts: [InvestmentAccount] = [
        InvestmentAccount(
            id: brokerageAccountID,
            connectionID: brokerageConnectionID,
            name: "Individual Brokerage",
            officialName: "Northwind Individual Brokerage Account",
            mask: "4821",
            type: "investment",
            subtype: "brokerage",
            currentBalance: 51_760,
            currency: "USD"
        ),
        InvestmentAccount(
            id: iraAccountID,
            connectionID: retirementConnectionID,
            name: "Roth IRA",
            officialName: nil,
            mask: "0937",
            type: "investment",
            subtype: "roth",
            currentBalance: 11_600,
            currency: "USD"
        ),
    ]

    static let holdings: [BrokerageHolding] = [
        holding(1, account: brokerageAccountID, ticker: "VTI", name: "Vanguard Total Stock Market ETF", type: "etf", quantity: 70, price: 290, cost: 16_900),
        holding(2, account: brokerageAccountID, ticker: "VXUS", name: "Vanguard Total International Stock ETF", type: "etf", quantity: 120, price: 66, cost: 7_300),
        holding(3, account: brokerageAccountID, ticker: "AAPL", name: "Apple Inc.", type: "equity", quantity: 25, price: 228, cost: 4_200),
        holding(4, account: brokerageAccountID, ticker: "NVDA", name: "NVIDIA Corporation", type: "equity", quantity: 30, price: 140, cost: 2_100),
        holding(5, account: brokerageAccountID, ticker: "BND", name: "Vanguard Total Bond Market ETF", type: "etf", quantity: 60, price: 73, cost: 4_500),
        holding(6, account: brokerageAccountID, ticker: "MSFT", name: "Microsoft Corporation", type: "equity", quantity: 8, price: 420, cost: 2_900),
        holding(7, account: brokerageAccountID, ticker: "BTC", name: "Bitcoin", type: "cryptocurrency", quantity: 0.05, price: 68_000, cost: 2_000),
        holding(8, account: brokerageAccountID, ticker: "CUR:USD", name: "U.S. Dollar", type: "cash", quantity: 2_500, price: 1, cost: nil),
        holding(9, account: iraAccountID, ticker: "VTI", name: "Vanguard Total Stock Market ETF", type: "etf", quantity: 40, price: 290, cost: 9_800),
    ]

    static let transactions: [InvestmentTransaction] = [
        transaction(1, daysAgo: 2, name: "Buy Vanguard Total Stock Market ETF", ticker: "VTI", type: "buy", subtype: "buy", quantity: 2, price: 288.5, amount: 577),
        transaction(2, daysAgo: 5, name: "Dividend: Apple Inc.", ticker: "AAPL", type: "cash", subtype: "dividend", quantity: nil, price: nil, amount: -6.25),
        transaction(3, daysAgo: 9, name: "Sell NVIDIA Corporation", ticker: "NVDA", type: "sell", subtype: "sell", quantity: -5, price: 138, amount: -690),
        transaction(4, daysAgo: 15, name: "Account maintenance fee", ticker: nil, type: "fee", subtype: "account fee", quantity: nil, price: nil, amount: 1.5),
        transaction(5, daysAgo: 20, name: "Deposit from checking", ticker: nil, type: "transfer", subtype: "deposit", quantity: nil, price: nil, amount: -500),
        transaction(6, daysAgo: 28, name: "Buy Microsoft Corporation", ticker: "MSFT", type: "buy", subtype: "buy", quantity: 1, price: 415, amount: 415),
        transaction(7, daysAgo: 41, name: "Dividend: Vanguard Total International Stock ETF", ticker: "VXUS", type: "cash", subtype: "dividend", quantity: nil, price: nil, amount: -38.4),
        transaction(8, daysAgo: 55, name: "Buy Vanguard Total Bond Market ETF", ticker: "BND", type: "buy", subtype: "buy", quantity: 10, price: 72.9, amount: 729),
    ]

    static let snapshots: [PortfolioSnapshot] = {
        let total = holdings.reduce(0) { $0 + $1.value }
        let cost = holdings.reduce(0) { $0 + ($1.costBasis ?? 0) }
        let days = 120
        return (0..<days).map { index in
            let progress = Double(index) / Double(days - 1)
            let isLast = index == days - 1
            let value = isLast ? total : 55_000 + (total - 55_000) * progress + 900 * sin(Double(index) / 6)
            let basis = cost - 3_000 * (1 - progress)
            return PortfolioSnapshot(
                date: dayString(daysAgo: days - 1 - index),
                totalValue: (value * 100).rounded() / 100,
                costBasis: (basis * 100).rounded() / 100
            )
        }
    }()

    private static func sampleID(_ number: Int) -> UUID {
        let suffix = String(number)
        let padded = String(repeating: "0", count: max(0, 12 - suffix.count)) + suffix
        return UUID(uuidString: "5B3C2D1E-0000-4000-8000-\(padded)") ?? UUID()
    }

    private static func dayString(daysAgo: Int) -> String {
        let calendar = Calendar.current
        let date = calendar.date(byAdding: .day, value: -daysAgo, to: .now) ?? .now
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        func pad(_ value: Int?, _ width: Int) -> String {
            let text = String(value ?? 1)
            return String(repeating: "0", count: max(0, width - text.count)) + text
        }
        return "\(pad(parts.year, 4))-\(pad(parts.month, 2))-\(pad(parts.day, 2))"
    }

    private static func holding(
        _ number: Int,
        account: UUID,
        ticker: String,
        name: String,
        type: String,
        quantity: Double,
        price: Double,
        cost: Double?
    ) -> BrokerageHolding {
        BrokerageHolding(
            id: sampleID(100 + number),
            accountID: account,
            securityID: "sec-\(number)",
            ticker: ticker,
            name: name,
            securityType: type,
            quantity: quantity,
            price: price,
            priceAsOf: dayString(daysAgo: 1),
            value: quantity * price,
            costBasis: cost,
            currency: "USD",
            updatedAt: Date.now.addingTimeInterval(-2 * 3600)
        )
    }

    private static func transaction(
        _ number: Int,
        daysAgo: Int,
        name: String,
        ticker: String?,
        type: String,
        subtype: String?,
        quantity: Double?,
        price: Double?,
        amount: Double
    ) -> InvestmentTransaction {
        InvestmentTransaction(
            id: sampleID(200 + number),
            accountID: number == 8 ? iraAccountID : brokerageAccountID,
            date: dayString(daysAgo: daysAgo),
            name: name,
            ticker: ticker,
            securityName: ticker == nil ? nil : name,
            type: type,
            subtype: subtype,
            quantity: quantity,
            price: price,
            amount: amount,
            fees: type == "fee" ? amount : 0,
            currency: "USD"
        )
    }
}
