//
//  CSVImportView.swift
//  Haki
//
//  Imports transactions from a CSV export in three steps: choose a file,
//  check the preview (sign convention, destination account, first rows),
//  then import and see what happened. Pushed; presenters that show it in a
//  sheet wrap it in a NavigationStack.
//

import Foundation
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

struct CSVImportView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(AppRouter.self) private var router

    @Query(sort: [SortDescriptor(\Account.sortOrder), SortDescriptor(\Account.name)])
    private var accounts: [Account]

    @State private var showsFileImporter = false
    @State private var preview: CSVImportPreview?
    @State private var convention: AmountSignConvention = .negativeIsMoneyOut
    @State private var dateOrder: CSVDateOrder = .monthFirst
    @State private var destination: CSVImportDestination = .newAccount
    @State private var newAccountName = ""
    @State private var newAccountKind: AccountKind = .checking
    @State private var createsMissingAccounts = true
    @State private var showsSkippedRows = false
    @State private var summary: ImportSummary?
    @State private var importedDestinationName: String?
    @State private var errorMessage: String?
    @State private var errorFileName: String?
    @State private var completedImports = 0

    init() {}

    /// Starts on the preview step with already-decoded text. Used by previews.
    fileprivate init(fileName: String, sampleText: String) {
        if let result = try? CSVTransactionImporter.parse(sampleText) {
            let parsed = CSVImportPreview(fileName: fileName, text: sampleText, result: result, existingFingerprints: [])
            _preview = State(initialValue: parsed)
            let initialConvention: AmountSignConvention = result.signConvention ?? .negativeIsMoneyOut
            let initialDateOrder: CSVDateOrder = result.dateOrder ?? .monthFirst
            let initialDestination: CSVImportDestination = parsed.hasAccountColumn ? .fileAccounts : .newAccount
            _convention = State(initialValue: initialConvention)
            _dateOrder = State(initialValue: initialDateOrder)
            _destination = State(initialValue: initialDestination)
        }
    }

    var body: some View {
        content
            .navigationTitle("Import CSV")
            .navigationBarTitleDisplayMode(.inline)
            .fileImporter(
                isPresented: $showsFileImporter,
                allowedContentTypes: [.commaSeparatedText, .tabSeparatedText, .plainText]
            ) { result in
                handlePickedFile(result)
            }
            .onChange(of: convention) { _, newValue in
                reparse(with: newValue)
            }
            .onChange(of: dateOrder) { _, newValue in
                reparse(dateOrder: newValue)
            }
            .sensoryFeedback(.success, trigger: completedImports)
    }

    @ViewBuilder
    private var content: some View {
        if let summary {
            CSVImportDoneView(
                summary: summary,
                destinationName: importedDestinationName,
                onReview: { reviewImported() },
                onImportAnother: { importAnotherFile() }
            )
        } else if let preview {
            previewList(preview)
        } else {
            CSVImportIntroView(
                errorMessage: errorMessage,
                errorFileName: errorFileName,
                onChooseFile: { chooseFile() }
            )
        }
    }

    // MARK: - Preview step

    private func previewList(_ preview: CSVImportPreview) -> some View {
        List {
            fileSection(preview)
            signSection(preview)
            dateOrderSection(preview)
            if preview.transactionCount > 0 {
                destinationSection(preview)
            }
            transactionsSection(preview)
        }
        .listStyle(.insetGrouped)
        .scrollDismissesKeyboard(.interactively)
        .safeAreaInset(edge: .bottom) {
            importBar(preview)
        }
    }

    private func fileSection(_ preview: CSVImportPreview) -> some View {
        Section {
            CSVImportFileHeader(fileName: preview.fileName, columnNames: preview.columnNames)

            LabeledContent("Transactions") {
                Text(preview.transactionCount.formatted())
                    .monospacedDigit()
            }
            if let range = preview.dateRangeText {
                LabeledContent("Dates", value: range)
            }
            if preview.transactionCount > 0 {
                LabeledContent("Money out") {
                    TransactionAmountText(cents: preview.moneyOutCents)
                }
                LabeledContent("Money in") {
                    TransactionAmountText(cents: -preview.moneyInCents)
                }
            }
            if preview.duplicateCount > 0 {
                LabeledContent("Already in Haki") {
                    Text(preview.duplicateCount.formatted())
                        .monospacedDigit()
                }
            }
            if !preview.result.skipped.isEmpty {
                skippedRowsGroup(preview.result.skipped)
            }

            Button {
                chooseFile()
            } label: {
                Label("Choose a different file", systemImage: "arrow.triangle.2.circlepath")
            }
        } header: {
            Text("File")
        } footer: {
            if preview.duplicateCount > 0 {
                Text("Transactions already in Haki (same day, amount and merchant) are skipped, so importing an overlapping export is safe.")
            }
        }
    }

    private func skippedRowsGroup(_ skipped: [CSVSkippedRow]) -> some View {
        DisclosureGroup(isExpanded: $showsSkippedRows) {
            ForEach(Array(skipped.prefix(100)), id: \.self) { row in
                CSVImportSkippedRowView(row: row)
            }
            if skipped.count > 100 {
                Text("and \(SettingsFormat.count(skipped.count - 100, "more row", "more rows"))")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        } label: {
            Label {
                Text(SettingsFormat.count(skipped.count, "row skipped", "rows skipped"))
            } icon: {
                Image(systemName: "exclamationmark.circle.fill")
                    .foregroundStyle(Color.hakiWarning)
            }
        }
    }

    @ViewBuilder
    private func signSection(_ preview: CSVImportPreview) -> some View {
        if preview.result.signConvention != nil {
            Section {
                Picker("Amounts in this file", selection: $convention) {
                    ForEach(AmountSignConvention.allCases) { option in
                        Text(option.displayName).tag(option)
                    }
                }
                .pickerStyle(.inline)
                .labelsHidden()

                if let example = preview.spentExample {
                    CSVImportSignExampleRow(transaction: example)
                }
                if let example = preview.receivedExample {
                    CSVImportSignExampleRow(transaction: example)
                }
            } header: {
                Text("Amount signs")
            } footer: {
                Text("Haki guessed this from the file. Check the examples: a purchase should read as spent. If it reads as received, choose the other option.")
            }
        }
    }

    /// Shown only when every date in the file would read either way, e.g.
    /// 05/11/2026 in a file with no day after the 12th.
    @ViewBuilder
    private func dateOrderSection(_ preview: CSVImportPreview) -> some View {
        if preview.result.dateOrder != nil && preview.result.dateOrderIsAmbiguous {
            Section {
                Picker("Dates in this file", selection: $dateOrder) {
                    ForEach(CSVDateOrder.allCases) { option in
                        Text(option.displayName).tag(option)
                    }
                }
                .pickerStyle(.inline)
                .labelsHidden()
            } header: {
                Text("Date order")
            } footer: {
                Text("Haki couldn't tell from the file whether a date like 05/11 is 5 November or May 11, so it went by your region. Check the dates in the preview; if they're in the wrong months, choose the other option.")
            }
        }
    }

    private func destinationSection(_ preview: CSVImportPreview) -> some View {
        Section {
            Picker("Add to", selection: $destination) {
                ForEach(accounts) { account in
                    Label(account.name, systemImage: account.kind.systemImage)
                        .tag(CSVImportDestination.existing(account.id))
                }
                if preview.hasAccountColumn {
                    Label("Use account names from the file", systemImage: "doc.text")
                        .tag(CSVImportDestination.fileAccounts)
                }
                Label("New account", systemImage: "plus.circle")
                    .tag(CSVImportDestination.newAccount)
            }
            destinationDetails(preview)
        } header: {
            Text("Destination")
        } footer: {
            Text(destinationFooter(preview))
        }
    }

    @ViewBuilder
    private func destinationDetails(_ preview: CSVImportPreview) -> some View {
        switch destination {
        case .newAccount:
            TextField("Account name", text: $newAccountName, prompt: Text("Account name, e.g. Everyday Checking"))
                .textInputAutocapitalization(.words)
                .submitLabel(.done)
            Picker("Type", selection: $newAccountKind) {
                ForEach(AccountKind.allCases) { kind in
                    Label(kind.displayName, systemImage: kind.systemImage)
                        .tag(kind)
                }
            }
        case .fileAccounts:
            fileAccountRows(preview)
        case .existing:
            EmptyView()
        }
    }

    @ViewBuilder
    private func fileAccountRows(_ preview: CSVImportPreview) -> some View {
        let missing = missingAccountNames(preview)
        if preview.fileAccountNames.isEmpty {
            Text("The file's account column is empty, so these transactions won't be filed under an account.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        } else {
            ForEach(preview.fileAccountNames, id: \.self) { name in
                CSVImportFileAccountRow(name: name, isNew: missing.contains(name))
            }
            if !missing.isEmpty {
                Toggle(isOn: $createsMissingAccounts) {
                    Text(createAccountsTitle(count: missing.count))
                }
            }
        }
    }

    private func transactionsSection(_ preview: CSVImportPreview) -> some View {
        Section {
            if preview.transactionCount == 0 {
                CSVImportNoTransactionsRow()
            } else {
                ForEach(preview.previewRows) { row in
                    CSVImportTransactionRow(transaction: row.transaction)
                }
            }
        } header: {
            Text("Preview")
        } footer: {
            if preview.transactionCount > CSVImportPreview.previewLimit {
                Text("Showing the first \(CSVImportPreview.previewLimit.formatted()) of \(preview.transactionCount.formatted()) transactions.")
            }
        }
    }

    private func importBar(_ preview: CSVImportPreview) -> some View {
        VStack(spacing: 6) {
            Button {
                performImport()
            } label: {
                Text(importButtonTitle(preview))
                    .font(.headline)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(!canImport(preview))

            if let hint = importHint(preview) {
                Text(hint)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(.horizontal)
        .padding(.top, 10)
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity)
        .background(.bar)
    }

    // MARK: - Derived values

    private var trimmedNewAccountName: String {
        newAccountName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func createAccountsTitle(count: Int) -> String {
        count == 1 ? "Create the new account" : "Create \(count.formatted()) new accounts"
    }

    private func missingAccountNames(_ preview: CSVImportPreview) -> [String] {
        let existing = Set(accounts.map { $0.name.lowercased() })
        return preview.fileAccountNames.filter { !existing.contains($0.lowercased()) }
    }

    private func isDestinationReady() -> Bool {
        switch destination {
        case .existing(let id):
            return accounts.contains { $0.id == id }
        case .fileAccounts:
            return true
        case .newAccount:
            return !trimmedNewAccountName.isEmpty
        }
    }

    private func canImport(_ preview: CSVImportPreview) -> Bool {
        preview.newCount > 0 && isDestinationReady()
    }

    private func importButtonTitle(_ preview: CSVImportPreview) -> String {
        if preview.transactionCount == 0 { return "No transactions to import" }
        if preview.newCount == 0 { return "Already imported" }
        return "Import " + SettingsFormat.count(preview.newCount, "transaction", "transactions")
    }

    private func importHint(_ preview: CSVImportPreview) -> String? {
        if preview.transactionCount == 0 { return nil }
        if preview.newCount == 0 { return "Every transaction in this file is already in Haki." }
        if !isDestinationReady() {
            return destination == .newAccount ? "Name the new account to continue." : "Choose where to add these transactions."
        }
        if preview.duplicateCount > 0 {
            return SettingsFormat.count(preview.duplicateCount, "duplicate", "duplicates") + " will be skipped."
        }
        return "Imported transactions are marked for review."
    }

    private func destinationFooter(_ preview: CSVImportPreview) -> String {
        switch destination {
        case .existing:
            return "Transactions are added to this account. Its balance isn't changed."
        case .fileAccounts:
            if missingAccountNames(preview).isEmpty || createsMissingAccounts {
                return "Each transaction goes to the account with the same name as in the file."
            }
            return "Transactions for accounts you don't have yet are added without an account."
        case .newAccount:
            return "The account starts with a $0 balance. You can set its balance later in Accounts."
        }
    }

    // MARK: - Actions

    private func chooseFile() {
        showsFileImporter = true
    }

    private func handlePickedFile(_ result: Result<URL, any Error>) {
        switch result {
        case .success(let url):
            readPickedFile(url)
        case .failure(let error):
            showError(error.localizedDescription, fileName: nil)
        }
    }

    private func readPickedFile(_ url: URL) {
        let fileName = url.lastPathComponent
        switch CSVImportFileReader.read(url) {
        case .text(let text):
            load(text, fileName: fileName, convention: nil)
        case .failure(let message):
            showError(message, fileName: fileName)
        }
    }

    /// Parses the text and shows the preview. With neither a convention nor
    /// a date order (a newly chosen file), both are inferred and the defaults reset.
    private func load(
        _ text: String,
        fileName: String,
        convention chosen: AmountSignConvention?,
        dateOrder chosenDateOrder: CSVDateOrder? = nil
    ) {
        let isNewFile = chosen == nil && chosenDateOrder == nil
        let result: CSVImportResult
        do {
            result = try CSVTransactionImporter.parse(text, signConvention: chosen, dateOrder: chosenDateOrder)
        } catch {
            showError(error.localizedDescription, fileName: fileName)
            return
        }

        let existing = (try? modelContext.fetch(FetchDescriptor<TransactionRecord>())) ?? []
        let parsed = CSVImportPreview(
            fileName: fileName,
            text: text,
            result: result,
            existingFingerprints: existing.map(\.importFingerprint)
        )

        withAnimation(.snappy) {
            errorMessage = nil
            errorFileName = nil
            summary = nil
            preview = parsed
            if isNewFile {
                destination = defaultDestination(for: parsed)
                createsMissingAccounts = true
                showsSkippedRows = parsed.transactionCount == 0
            }
        }
        if isNewFile {
            // Set after `preview`, so the change handlers see they're already applied.
            convention = result.signConvention ?? .negativeIsMoneyOut
            dateOrder = result.dateOrder ?? .monthFirst
        }
    }

    private func reparse(with newConvention: AmountSignConvention) {
        guard let preview, let current = preview.result.signConvention, current != newConvention else { return }
        load(preview.text, fileName: preview.fileName, convention: newConvention, dateOrder: preview.result.dateOrder)
    }

    private func reparse(dateOrder newDateOrder: CSVDateOrder) {
        guard let preview, let current = preview.result.dateOrder, current != newDateOrder else { return }
        load(preview.text, fileName: preview.fileName, convention: preview.result.signConvention, dateOrder: newDateOrder)
    }

    private func defaultDestination(for preview: CSVImportPreview) -> CSVImportDestination {
        if preview.hasAccountColumn && !preview.fileAccountNames.isEmpty { return .fileAccounts }
        if case .existing(let id) = destination, accounts.contains(where: { $0.id == id }) { return destination }
        if let first = accounts.first { return .existing(first.id) }
        return .newAccount
    }

    private func showError(_ message: String, fileName: String?) {
        withAnimation(.snappy) {
            preview = nil
            summary = nil
            errorMessage = message
            errorFileName = fileName
        }
    }

    private func performImport() {
        guard let preview, canImport(preview) else { return }

        let account: Account?
        let destinationName: String?
        switch destination {
        case .existing(let id):
            account = accounts.first { $0.id == id }
            destinationName = account?.name
        case .fileAccounts:
            if createsMissingAccounts {
                for name in missingAccountNames(preview) {
                    LedgerStore.addAccount(in: modelContext, name: name,
                                           kind: CSVImportPreview.suggestedKind(forAccountName: name), balanceCents: 0)
                }
            }
            account = nil
            destinationName = fileAccountsDescription(preview)
        case .newAccount:
            let name = trimmedNewAccountName
            account = LedgerStore.addAccount(in: modelContext, name: name, kind: newAccountKind, balanceCents: 0)
            destinationName = name
        }

        let outcome = LedgerStore.importTransactions(preview.result.transactions, into: account, in: modelContext)
        withAnimation(.snappy) {
            importedDestinationName = destinationName
            summary = outcome
        }
        completedImports += 1
    }

    private func fileAccountsDescription(_ preview: CSVImportPreview) -> String? {
        let names = preview.fileAccountNames
        guard !names.isEmpty else { return nil }
        if names.count <= 2 { return names.joined(separator: " and ") }
        return SettingsFormat.count(names.count, "account", "accounts")
    }

    private func reviewImported() {
        router.showTransactions(.needsReview)
        // Pops this screen, or closes the sheet it's the root of.
        dismiss()
    }

    private func importAnotherFile() {
        withAnimation(.snappy) {
            summary = nil
            preview = nil
            errorMessage = nil
            errorFileName = nil
            importedDestinationName = nil
        }
        showsFileImporter = true
    }
}

// MARK: - Intro step

private struct CSVImportIntroView: View {
    let errorMessage: String?
    let errorFileName: String?
    let onChooseFile: () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                if let errorMessage {
                    errorCard(errorMessage)
                }
                heroCard
                supportedCard
                tipCard
            }
            .padding(.horizontal)
            .padding(.top, 8)
            .padding(.bottom)
        }
        .background(Color.hakiBackground)
    }

    private var heroCard: some View {
        VStack(spacing: 14) {
            SettingsIconTile(systemImage: "tray.and.arrow.down.fill", tint: .accentColor, size: 60)
            Text("Bring in your transactions")
                .font(.system(.title2, design: .rounded).weight(.bold))
                .multilineTextAlignment(.center)
                .accessibilityAddTraits(.isHeader)
            Text("Export a CSV file from your bank or another finance app, then choose it here. You'll see a preview before anything is added.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Button {
                onChooseFile()
            } label: {
                Label("Choose file", systemImage: "doc.badge.plus")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        .hakiCard(padding: 20)
    }

    private var supportedCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            CardHeader("What works", systemImage: "checklist")
            CSVImportBullet(
                systemImage: "tablecells",
                text: "Exports from most banks and finance apps with Date, Description and Amount columns."
            )
            CSVImportBullet(
                systemImage: "arrow.left.arrow.right",
                text: "Files with separate Debit and Credit (money out and money in) columns."
            )
            CSVImportBullet(
                systemImage: "tag",
                text: "Category, Account and Notes columns are used when they're there."
            )
            CSVImportBullet(
                systemImage: "doc.on.doc",
                text: "Transactions you've already imported are skipped, so overlapping exports are fine."
            )
            Text(verbatim: "Date,Description,Amount\n2026-11-03,SQ *CORNER CAFE,-5.25\n2026-11-01,PAYROLL DIRECT DEP,2400.00")
                .font(.system(.footnote, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(Color.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .accessibilityLabel("Example file: a header row with Date, Description and Amount, then one row per transaction.")
        }
        .hakiCard()
    }

    private var tipCard: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "lightbulb.fill")
                .font(.title3)
                .foregroundStyle(Color.hakiWarning)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text("Where to find it")
                    .font(.subheadline.weight(.semibold))
                Text("On your bank's website, open an account's activity and look for Download or Export, then pick CSV. A few months at a time works well.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
        .hakiCard()
    }

    private func errorCard(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label {
                Text("Couldn't import that file")
                    .font(.headline)
            } icon: {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(Color.hakiNegative)
            }
            if let errorFileName {
                Text(errorFileName)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(2)
            }
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button {
                onChooseFile()
            } label: {
                Label("Try again", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.bordered)
        }
        .hakiCard()
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(Color.hakiNegative.opacity(0.35), lineWidth: 1)
        }
    }
}

private struct CSVImportBullet: View {
    let systemImage: String
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: systemImage)
                .font(.body.weight(.semibold))
                .foregroundStyle(Color.accentColor)
                .frame(minWidth: 24)
                .accessibilityHidden(true)
            Text(text)
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - Preview rows

private struct CSVImportFileHeader: View {
    let fileName: String
    let columnNames: [String]

    var body: some View {
        HStack(spacing: 12) {
            SettingsIconTile(systemImage: "doc.text.fill", tint: .accentColor, size: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text(fileName)
                    .font(.body.weight(.semibold))
                    .lineLimit(2)
                Text("Columns: " + columnNames.joined(separator: " · "))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }
}

private struct CSVImportSkippedRowView: View {
    let row: CSVSkippedRow

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Line " + String(row.line))
                .font(.subheadline.weight(.medium))
                .monospacedDigit()
            Text(row.reason)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }
}

/// "Corner Cafe: $5.25 spent", so the user can tell whether signs are right.
private struct CSVImportSignExampleRow: View {
    let transaction: ImportedTransaction

    private var isSpent: Bool { transaction.amountCents > 0 }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: isSpent ? "arrow.up.right.circle.fill" : "arrow.down.left.circle.fill")
                .font(.title3)
                .foregroundStyle(isSpent ? Color.secondary : Color.hakiPositive)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(sentence)
                    .font(.subheadline.weight(.medium))
                Text(transaction.rawDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var sentence: String {
        let amount = Money.format(abs(transaction.amountCents))
        return "\(transaction.merchantName): \(amount) \(isSpent ? "spent" : "received")"
    }
}

private struct CSVImportFileAccountRow: View {
    let name: String
    let isNew: Bool

    var body: some View {
        LabeledContent {
            Text(isNew ? "New" : "Matched")
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(isNew ? Color.hakiWarning.opacity(0.18) : Color.accentColor.opacity(0.15), in: Capsule())
                .foregroundStyle(isNew ? Color.hakiWarning : Color.accentColor)
        } label: {
            Label(name, systemImage: "building.columns")
        }
        .accessibilityElement(children: .combine)
    }
}

private struct CSVImportTransactionRow: View {
    let transaction: ImportedTransaction

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(transaction.merchantName)
                    .font(.body.weight(.medium))
                    .lineLimit(1)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            TransactionAmountText(cents: transaction.amountCents)
                .font(.body.weight(.medium))
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }

    private var subtitle: String {
        var parts = [transaction.date.formatted(.dateTime.month(.abbreviated).day().year())]
        if let category = transaction.categoryName { parts.append(category) }
        if let account = transaction.accountName { parts.append(account) }
        return parts.joined(separator: " · ")
    }
}

private struct CSVImportNoTransactionsRow: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label("No transactions found", systemImage: "questionmark.folder")
                .font(.headline)
            Text("Every row was skipped. Open the skipped rows above to see why, then export the file again or choose another one.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Done step

private struct CSVImportDoneView: View {
    let summary: ImportSummary
    let destinationName: String?
    let onReview: () -> Void
    let onImportAnother: () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                resultCard
                actions
            }
            .padding(.horizontal)
            .padding(.top, 8)
            .padding(.bottom)
        }
        .background(Color.hakiBackground)
    }

    private var didImport: Bool { summary.inserted > 0 }

    private var resultCard: some View {
        VStack(spacing: 16) {
            VStack(spacing: 8) {
                Image(systemName: didImport ? "checkmark.circle.fill" : "equal.circle.fill")
                    .font(.largeTitle)
                    .imageScale(.large)
                    .foregroundStyle(didImport ? Color.accentColor : Color.secondary)
                    .accessibilityHidden(true)
                Text(didImport ? "Import complete" : "Nothing new to import")
                    .font(.system(.title2, design: .rounded).weight(.bold))
                    .accessibilityAddTraits(.isHeader)
                if let destinationName, didImport {
                    Text("Added to " + destinationName)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
            .frame(maxWidth: .infinity)

            Divider()

            VStack(alignment: .leading, spacing: 14) {
                CSVImportStatRow(
                    systemImage: "checkmark",
                    tint: .accentColor,
                    text: "Imported " + SettingsFormat.count(summary.inserted, "transaction", "transactions")
                )
                CSVImportStatRow(
                    systemImage: "doc.on.doc",
                    tint: .gray,
                    text: "Skipped " + SettingsFormat.count(summary.duplicatesSkipped, "duplicate", "duplicates")
                )
                CSVImportStatRow(
                    systemImage: "wand.and.stars",
                    tint: .indigo,
                    text: "Auto-categorized " + summary.autoCategorized.formatted()
                )
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if didImport {
                Text("New transactions are marked for review so you can check their categories.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("Everything in this file is already in Haki.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .hakiCard(padding: 20)
    }

    private var actions: some View {
        VStack(spacing: 10) {
            if didImport {
                Button {
                    onReview()
                } label: {
                    Label("Review them", systemImage: "checklist")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
            Button {
                onImportAnother()
            } label: {
                Text("Import another file")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
        }
    }
}

private struct CSVImportStatRow: View {
    let systemImage: String
    let tint: Color
    let text: String

    var body: some View {
        HStack(spacing: 12) {
            SettingsIconTile(systemImage: systemImage, tint: tint, size: 26)
            Text(text)
                .font(.body)
                .monospacedDigit()
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Previews

private enum CSVImportPreviewSample {
    static let fileName = "everyday-checking-export.csv"
    static let text = """
    Date,Description,Amount,Category
    2026-11-06,SQ *CORNER CAFE SAN FRANCISCO CA,-5.25,
    2026-11-05,TRADER JOE'S #552,-64.18,Groceries
    2026-11-04,NETFLIX.COM,-15.49,
    2026-11-03,UBER   *TRIP HELP.UBER.COM,-18.70,
    2026-11-01,PAYROLL DIRECT DEP NORTHWIND LABS,2400.00,
    2026-10-31,AMAZON.COM*2K4AB1C23 AMZN.COM/BILLWA,-42.99,Shopping
    not a date,SOMETHING ODD,-1.00,
    """
}

#Preview("Choose a file") {
    NavigationStack {
        CSVImportView()
    }
    .previewEnvironment()
}

#Preview("Preview step") {
    NavigationStack {
        CSVImportView(fileName: CSVImportPreviewSample.fileName, sampleText: CSVImportPreviewSample.text)
    }
    .previewEnvironment()
}

#Preview("Done") {
    NavigationStack {
        CSVImportDoneView(
            summary: ImportSummary(inserted: 128, duplicatesSkipped: 3, autoCategorized: 97),
            destinationName: "Everyday Checking",
            onReview: {},
            onImportAnother: {}
        )
        .navigationTitle("Import CSV")
        .navigationBarTitleDisplayMode(.inline)
    }
    .previewEnvironment()
}
