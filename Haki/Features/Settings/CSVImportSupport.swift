//
//  CSVImportSupport.swift
//  Haki
//
//  Plain values behind the CSV import screen: reading a picked file, the
//  parsed preview with its derived numbers, and where imported transactions go.
//

import Foundation

// MARK: - Reading the file

nonisolated enum CSVImportFileContents {
    case text(String)
    /// A message to show the user.
    case failure(String)
}

nonisolated enum CSVImportFileReader {
    /// Reads a file picked with `.fileImporter`, with security-scoped access.
    /// Decodes UTF-8 (or UTF-16 with a byte-order mark) and falls back to Latin-1.
    static func read(_ url: URL) -> CSVImportFileContents {
        let didAccess = url.startAccessingSecurityScopedResource()
        defer {
            if didAccess { url.stopAccessingSecurityScopedResource() }
        }

        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            return .failure("Haki couldn't open the file. \(error.localizedDescription)")
        }
        guard !data.isEmpty else {
            return .failure("The file is empty.")
        }

        let bytes = [UInt8](data.prefix(2))
        if bytes == [0xFF, 0xFE] || bytes == [0xFE, 0xFF], let text = String(data: data, encoding: .utf16) {
            return .text(text)
        }
        if let text = String(data: data, encoding: .utf8) {
            return .text(text)
        }
        if let text = String(data: data, encoding: .isoLatin1) {
            return .text(text)
        }
        return .failure("The file isn't readable text. Export it from your bank as CSV and try again.")
    }
}

// MARK: - Destination

/// Where imported transactions are filed.
nonisolated enum CSVImportDestination: Hashable {
    /// An existing account, by id.
    case existing(UUID)
    /// The account named in each row (the file has an Account column).
    case fileAccounts
    /// A new account created right before importing.
    case newAccount
}

// MARK: - Preview

/// One of the first transactions, shown before importing.
nonisolated struct CSVImportPreviewRow: Identifiable {
    let id: Int
    let transaction: ImportedTransaction
}

/// A parsed file plus everything the preview shows about it, computed once.
nonisolated struct CSVImportPreview {
    static let previewLimit = 20

    let fileName: String
    /// The decoded file, kept so it can be re-parsed with another sign convention.
    let text: String
    let result: CSVImportResult
    /// Transactions that aren't in the app yet.
    let newCount: Int
    /// Transactions that are already in the app and will be skipped.
    let duplicateCount: Int
    let firstDate: Date?
    let lastDate: Date?
    let moneyOutCents: Int
    /// Positive.
    let moneyInCents: Int
    /// Distinct account names in the file, in order of first appearance.
    let fileAccountNames: [String]
    /// The kinds of columns Haki recognized, e.g. ["Date", "Description", "Amount"].
    let columnNames: [String]

    init(fileName: String, text: String, result: CSVImportResult, existingFingerprints: [String]) {
        self.fileName = fileName
        self.text = text
        self.result = result

        let transactions = result.transactions
        let deduplicated = ImportDeduplicator.newTransactions(transactions, existingFingerprints: existingFingerprints)
        newCount = deduplicated.new.count
        duplicateCount = deduplicated.duplicateCount

        let dates = transactions.map(\.date)
        firstDate = dates.min()
        lastDate = dates.max()

        var moneyOut = 0
        var moneyIn = 0
        var seenNames = Set<String>()
        var names: [String] = []
        for transaction in transactions {
            if transaction.amountCents > 0 {
                moneyOut += transaction.amountCents
            } else {
                moneyIn -= transaction.amountCents
            }
            if let name = transaction.accountName, !name.isEmpty, seenNames.insert(name.lowercased()).inserted {
                names.append(name)
            }
        }
        moneyOutCents = moneyOut
        moneyInCents = moneyIn
        fileAccountNames = names
        columnNames = Self.columnNames(for: result.mapping)
    }

    var transactionCount: Int { result.transactions.count }

    var hasAccountColumn: Bool { result.mapping.account != nil }

    /// The first 20 transactions.
    var previewRows: [CSVImportPreviewRow] {
        result.transactions.prefix(Self.previewLimit).enumerated().map { offset, transaction in
            CSVImportPreviewRow(id: offset, transaction: transaction)
        }
    }

    /// A purchase from the file, for checking the sign convention.
    var spentExample: ImportedTransaction? {
        result.transactions.first { $0.amountCents > 0 }
    }

    /// Money received in the file, for checking the sign convention.
    var receivedExample: ImportedTransaction? {
        result.transactions.first { $0.amountCents < 0 }
    }

    /// "Jul 1, 2026 – Sep 30, 2026", or one date.
    var dateRangeText: String? {
        guard let firstDate, let lastDate else { return nil }
        let style = Date.FormatStyle.dateTime.month(.abbreviated).day().year()
        let start = firstDate.formatted(style)
        let end = lastDate.formatted(style)
        return start == end ? start : start + " – " + end
    }

    static func columnNames(for mapping: CSVColumnMapping) -> [String] {
        var names = ["Date", "Description"]
        if mapping.amount != nil { names.append("Amount") }
        if mapping.debit != nil { names.append("Debit") }
        if mapping.credit != nil { names.append("Credit") }
        if mapping.transactionType != nil { names.append("Type") }
        if mapping.category != nil { names.append("Category") }
        if mapping.account != nil { names.append("Account") }
        if mapping.notes != nil { names.append("Notes") }
        return names
    }

    /// A reasonable account kind for an account named in a file.
    static func suggestedKind(forAccountName name: String) -> AccountKind {
        let lowered = name.lowercased()
        if ["credit", "card", "visa", "mastercard", "amex"].contains(where: { lowered.contains($0) }) {
            return .creditCard
        }
        if lowered.contains("saving") { return .savings }
        if ["brokerage", "invest", "401k", "retirement"].contains(where: { lowered.contains($0) }) {
            return .investment
        }
        if lowered.contains("loan") || lowered.contains("mortgage") { return .loan }
        return .checking
    }
}
