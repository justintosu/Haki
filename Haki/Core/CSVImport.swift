//
//  CSVImport.swift
//  Haki
//
//  Pure Foundation code (see Money.swift).
//

import Foundation

// MARK: - CSV parsing

nonisolated enum CSVParser {
    /// Parses RFC 4180-style CSV: quoted fields, `""` escapes, commas and line
    /// breaks inside quotes, and `\n`, `\r\n` or `\r` line endings. Blank lines
    /// are dropped. The delimiter (comma, semicolon or tab) is detected from
    /// the first line unless given.
    static func rows(from text: String, delimiter: Character? = nil) -> [[String]] {
        var source = text
        if source.hasPrefix("\u{FEFF}") { source.removeFirst() }
        let delimiterScalar = (delimiter ?? detectDelimiter(in: source)).unicodeScalars.first ?? ","

        var rows: [[String]] = []
        var row: [String] = []
        var field = String.UnicodeScalarView()
        var inQuotes = false
        var fieldWasQuoted = false

        // Iterate over Unicode scalars, not Characters: "\r\n" is a single
        // Character in Swift and would otherwise hide the line break.
        let scalars = Array(source.unicodeScalars)
        var index = 0

        func endField() {
            var value = String(field)
            if !fieldWasQuoted { value = value.trimmingCharacters(in: .whitespaces) }
            row.append(value)
            field = String.UnicodeScalarView()
            fieldWasQuoted = false
        }

        func endRow() {
            endField()
            if !(row.count == 1 && row[0].isEmpty) { rows.append(row) }
            row = []
        }

        while index < scalars.count {
            let scalar = scalars[index]
            if inQuotes {
                if scalar == "\"" {
                    if index + 1 < scalars.count, scalars[index + 1] == "\"" {
                        field.append("\"")
                        index += 1
                    } else {
                        inQuotes = false
                    }
                } else {
                    field.append(scalar)
                }
            } else if scalar == "\"" {
                // A quote only opens a quoted field at the start of the field.
                if String(field).trimmingCharacters(in: .whitespaces).isEmpty {
                    field = String.UnicodeScalarView()
                    inQuotes = true
                    fieldWasQuoted = true
                } else {
                    field.append(scalar)
                }
            } else if scalar == delimiterScalar {
                endField()
            } else if scalar == "\n" {
                endRow()
            } else if scalar == "\r" {
                endRow()
                if index + 1 < scalars.count, scalars[index + 1] == "\n" { index += 1 }
            } else {
                field.append(scalar)
            }
            index += 1
        }
        if !field.isEmpty || !row.isEmpty || fieldWasQuoted { endRow() }
        return rows
    }

    /// The most common of `,` `;` and tab outside quotes on the first line.
    static func detectDelimiter(in text: String) -> Character {
        var counts: [Character: Int] = [",": 0, ";": 0, "\t": 0]
        var inQuotes = false
        for scalar in text.unicodeScalars {
            if scalar == "\n" || scalar == "\r" { if !inQuotes { break } }
            if scalar == "\"" { inQuotes.toggle(); continue }
            guard !inQuotes else { continue }
            let character = Character(scalar)
            if counts[character] != nil { counts[character, default: 0] += 1 }
        }
        let best = counts.max { $0.value != $1.value ? $0.value < $1.value : $0.key != "," }
        return (best?.value ?? 0) > 0 ? best!.key : ","
    }
}

// MARK: - Mapping columns

/// How amounts in a single "Amount" column are signed.
nonisolated enum AmountSignConvention: String, CaseIterable, Identifiable, Hashable {
    /// Bank-statement style: purchases are negative, deposits positive.
    case negativeIsMoneyOut
    /// Aggregator-export style: purchases are positive (Haki's own convention).
    case positiveIsMoneyOut

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .negativeIsMoneyOut: "Purchases are negative"
        case .positiveIsMoneyOut: "Purchases are positive"
        }
    }

    /// Converts a file amount to Haki's convention (positive = money out).
    func toHaki(_ cents: Int) -> Int {
        self == .negativeIsMoneyOut ? -cents : cents
    }
}

/// The order of day and month in numeric dates such as `05/11/2026`.
nonisolated enum CSVDateOrder: String, CaseIterable, Identifiable, Hashable {
    /// `05/11/2026` is 5 November (the UK, Europe, Australia and most of the world).
    case dayFirst
    /// `05/11/2026` is May 11 (the US).
    case monthFirst

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .dayFirst: "Day first (DD/MM)"
        case .monthFirst: "Month first (MM/DD)"
        }
    }

    /// The order a locale writes short dates in: day first for en_GB or
    /// de_DE, month first for en_US (and for year-first locales such as ja_JP).
    static func preferred(in locale: Locale) -> CSVDateOrder {
        guard let format = DateFormatter.dateFormat(fromTemplate: "yMd", options: 0, locale: locale) else {
            return .monthFirst
        }
        var isQuoted = false
        for character in format {
            if character == "'" {
                isQuoted.toggle()
                continue
            }
            guard !isQuoted else { continue }
            if character == "d" { return .dayFirst }
            if character == "M" || character == "L" { return .monthFirst }
        }
        return .monthFirst
    }
}

/// Which column holds what. Indexes are into each row.
nonisolated struct CSVColumnMapping: Hashable {
    var date: Int
    var description: Int
    /// A single signed amount column...
    var amount: Int?
    /// ...or separate money-out / money-in columns.
    var debit: Int?
    var credit: Int?
    /// A "debit"/"credit" column that gives the direction of an unsigned amount (Mint exports).
    var transactionType: Int?
    var category: Int?
    var account: Int?
    var notes: Int?

    var hasAmount: Bool { amount != nil || debit != nil || credit != nil }
}

// MARK: - Import

nonisolated struct ImportedTransaction: Hashable, Identifiable {
    /// Noon local time on the transaction's day.
    var date: Date
    var rawDescription: String
    var merchantName: String
    /// Haki sign convention: positive = money out.
    var amountCents: Int
    var categoryName: String?
    var accountName: String?
    var notes: String?

    var id: String { fingerprint(calendar: .current) + "|" + rawDescription }

    /// Identifies the same transaction across imports: day, amount and merchant.
    func fingerprint(calendar: Calendar = .current) -> String {
        TransactionFingerprint.make(date: date, amountCents: amountCents,
                                    merchantKey: MerchantNormalizer.key(for: rawDescription), calendar: calendar)
    }
}

nonisolated enum TransactionFingerprint {
    static func make(date: Date, amountCents: Int, merchantKey: String, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        let day = String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
        return "\(day)|\(amountCents)|\(merchantKey)"
    }
}

nonisolated struct CSVSkippedRow: Hashable {
    /// 1-based line number in the file, counting the header as line 1.
    let line: Int
    let reason: String
}

nonisolated struct CSVImportResult: Hashable {
    var transactions: [ImportedTransaction]
    var skipped: [CSVSkippedRow]
    var mapping: CSVColumnMapping
    /// The convention used for a single amount column; `nil` when the file
    /// has debit/credit columns or a transaction-type column.
    var signConvention: AmountSignConvention?
    /// How numeric dates such as `05/11/2026` were read. `nil` when the file
    /// has none, or its dates contradict each other (each is then read on its own).
    var dateOrder: CSVDateOrder? = nil
    /// Whether nothing in the file shows the date order (no day is over 12),
    /// so `dateOrder` came from the region or the caller instead.
    var dateOrderIsAmbiguous = false
}

nonisolated enum CSVImportError: Error, LocalizedError, Hashable {
    case empty
    case missingColumns([String])

    var errorDescription: String? {
        switch self {
        case .empty:
            "The file has no rows."
        case .missingColumns(let names):
            "Couldn't find a column for \(names.joined(separator: ", ")). The first row should be a header with columns such as Date, Description and Amount."
        }
    }
}

nonisolated enum CSVTransactionImporter {
    /// Parses a CSV export into transactions.
    ///
    /// The day/month order of numeric dates and the decimal separator of
    /// amounts are decided once for the whole file, so a DD/MM/YYYY or a
    /// decimal-comma export is read consistently.
    /// - Parameters:
    ///   - signConvention: how a single amount column is signed. `nil`
    ///     infers it: most transactions are purchases, so the more common sign
    ///     is taken to mean money out.
    ///   - dateOrder: how to read numeric dates such as `05/11/2026`. `nil`
    ///     infers it from the file (any day over 12 settles it), falling back
    ///     to `locale` when every date would work either way.
    static func parse(
        _ text: String,
        signConvention: AmountSignConvention? = nil,
        dateOrder: CSVDateOrder? = nil,
        locale: Locale = .current,
        calendar: Calendar = .current
    ) throws -> CSVImportResult {
        let rows = CSVParser.rows(from: text)
        guard let header = rows.first, rows.count > 1 else { throw CSVImportError.empty }

        guard let mapping = detectMapping(header: header) else {
            let normalized = header.map(normalizeHeader)
            var missing: [String] = []
            if firstIndex(in: normalized, of: dateHeaders) == nil { missing.append("Date") }
            if firstIndex(in: normalized, of: descriptionHeaders) == nil { missing.append("Description") }
            if firstIndex(in: normalized, of: amountHeaders + debitHeaders + creditHeaders) == nil { missing.append("Amount") }
            throw CSVImportError.missingColumns(missing.isEmpty ? ["Date", "Description", "Amount"] : missing)
        }

        struct Parsed {
            let line: Int
            let date: Date
            let description: String
            let rawCents: Int
            let directionKnown: Bool
            let row: [String]
        }

        let dataRows = rows.dropFirst()
        func columnCells(_ index: Int?) -> [String] {
            guard let index else { return [] }
            return dataRows.compactMap { row in
                index < row.count ? row[index].trimmingCharacters(in: .whitespacesAndNewlines) : nil
            }
        }

        // Decided once per file: reading each row on its own would mix
        // 05/11 (as May 11) with 20/11 (as 20 November) in one export.
        let evidence = dateOrderEvidence(columnCells(mapping.date))
        let dateOrderIsAmbiguous = evidence.hasNumericDates && !evidence.dayFirst && !evidence.monthFirst
        let resolvedDateOrder: CSVDateOrder?
        if !evidence.hasNumericDates {
            resolvedDateOrder = nil
        } else if let dateOrder {
            resolvedDateOrder = dateOrder
        } else if evidence.dayFirst != evidence.monthFirst {
            resolvedDateOrder = evidence.dayFirst ? .dayFirst : .monthFirst
        } else if dateOrderIsAmbiguous {
            resolvedDateOrder = .preferred(in: locale)
        } else {
            resolvedDateOrder = nil
        }
        let textDateFormatters = makeTextDateFormatters(calendar: calendar)

        let decimalSeparator = detectDecimalSeparator(
            in: columnCells(mapping.amount) + columnCells(mapping.debit) + columnCells(mapping.credit))

        var parsed: [Parsed] = []
        var skipped: [CSVSkippedRow] = []

        for (offset, row) in dataRows.enumerated() {
            let line = offset + 2
            func cell(_ index: Int?) -> String {
                guard let index, index < row.count else { return "" }
                return row[index].trimmingCharacters(in: .whitespacesAndNewlines)
            }

            guard let date = parseDate(cell(mapping.date), calendar: calendar, order: resolvedDateOrder,
                                       textFormatters: textDateFormatters) else {
                skipped.append(CSVSkippedRow(line: line, reason: "Unreadable date \"\(cell(mapping.date))\""))
                continue
            }
            let description = cell(mapping.description)
            guard !description.isEmpty else {
                skipped.append(CSVSkippedRow(line: line, reason: "Missing description"))
                continue
            }

            var cents: Int?
            var directionKnown = false
            if let amountIndex = mapping.amount,
               let value = Money.parseCents(cell(amountIndex), decimalSeparator: decimalSeparator) {
                cents = value
                if let typeIndex = mapping.transactionType {
                    let type = cell(typeIndex).lowercased()
                    if type.hasPrefix("debit") { cents = abs(value); directionKnown = true }
                    if type.hasPrefix("credit") { cents = -abs(value); directionKnown = true }
                }
            }
            if cents == nil, mapping.debit != nil || mapping.credit != nil {
                let debit = Money.parseCents(cell(mapping.debit), decimalSeparator: decimalSeparator).map(abs)
                let credit = Money.parseCents(cell(mapping.credit), decimalSeparator: decimalSeparator).map(abs)
                if let debit, debit != 0 {
                    cents = debit; directionKnown = true
                } else if let credit, credit != 0 {
                    cents = -credit; directionKnown = true
                } else if debit != nil || credit != nil {
                    cents = 0; directionKnown = true
                }
            }
            guard let cents else {
                // Text that isn't a number, or one too large to be an amount.
                let unreadable = [cell(mapping.amount), cell(mapping.debit), cell(mapping.credit)].first { !$0.isEmpty }
                skipped.append(CSVSkippedRow(line: line, reason: unreadable.map { "Unreadable amount \"\($0)\"" } ?? "Missing amount"))
                continue
            }
            parsed.append(Parsed(line: line, date: date, description: description, rawCents: cents,
                                 directionKnown: directionKnown, row: row))
        }

        let undirected = parsed.filter { !$0.directionKnown }.map(\.rawCents)
        let convention: AmountSignConvention? = undirected.isEmpty
            ? nil
            : (signConvention ?? inferSignConvention(amounts: undirected))

        let transactions = parsed.map { item -> ImportedTransaction in
            let cents = item.directionKnown ? item.rawCents : (convention ?? .negativeIsMoneyOut).toHaki(item.rawCents)
            func optionalCell(_ index: Int?) -> String? {
                guard let index, index < item.row.count else { return nil }
                let value = item.row[index].trimmingCharacters(in: .whitespacesAndNewlines)
                return value.isEmpty ? nil : value
            }
            return ImportedTransaction(
                date: item.date,
                rawDescription: item.description,
                merchantName: MerchantNormalizer.displayName(for: item.description),
                amountCents: cents,
                categoryName: optionalCell(mapping.category),
                accountName: optionalCell(mapping.account),
                notes: optionalCell(mapping.notes)
            )
        }

        return CSVImportResult(transactions: transactions, skipped: skipped, mapping: mapping,
                               signConvention: convention, dateOrder: resolvedDateOrder,
                               dateOrderIsAmbiguous: dateOrderIsAmbiguous)
    }

    /// Finds columns by common header names. Returns `nil` without date,
    /// description and some amount column.
    static func detectMapping(header: [String]) -> CSVColumnMapping? {
        let names = header.map(normalizeHeader)
        guard let date = firstIndex(in: names, of: dateHeaders),
              let description = firstIndex(in: names, of: descriptionHeaders)
        else { return nil }

        var mapping = CSVColumnMapping(
            date: date,
            description: description,
            amount: firstIndex(in: names, of: amountHeaders),
            debit: firstIndex(in: names, of: debitHeaders),
            credit: firstIndex(in: names, of: creditHeaders),
            transactionType: firstIndex(in: names, of: typeHeaders),
            category: firstIndex(in: names, of: categoryHeaders),
            account: firstIndex(in: names, of: accountHeaders),
            notes: firstIndex(in: names, of: notesHeaders)
        )
        if mapping.notes == mapping.description { mapping.notes = nil }
        return mapping.hasAmount ? mapping : nil
    }

    /// Most transactions are purchases, so whichever sign is more common means money out.
    static func inferSignConvention(amounts: [Int]) -> AmountSignConvention {
        let negatives = amounts.filter { $0 < 0 }.count
        let positives = amounts.filter { $0 > 0 }.count
        return negatives > positives ? .negativeIsMoneyOut : .positiveIsMoneyOut
    }

    // MARK: Amounts

    /// The decimal separator a file's amounts use. An amount votes for the
    /// last "." or "," in it when exactly one or two digits follow it (then
    /// only a sign, currency or parenthesis): `"-5,25"` and `"1.250,00"` vote
    /// ",", `"2,500.00"` votes ".", and `"1,250"` doesn't vote. Returns ","
    /// only when every vote is for it.
    static func detectDecimalSeparator(in amounts: [String]) -> Character {
        var commaVotes = 0
        var periodVotes = 0
        for amount in amounts {
            guard let index = amount.lastIndex(where: { $0 == "." || $0 == "," }) else { continue }
            let after = amount[amount.index(after: index)...]
            let fraction = after.prefix { $0.isASCII && $0.isNumber }
            guard (1...2).contains(fraction.count),
                  !after.dropFirst(fraction.count).contains(where: \.isNumber)
            else { continue }
            if amount[index] == "," { commaVotes += 1 } else { periodVotes += 1 }
        }
        return commaVotes > 0 && periodVotes == 0 ? "," : "."
    }

    // MARK: Dates

    /// Parses `2026-07-14`, `2026-07-14T09:30:00Z`, `07/14/2026`, `7/14/26`,
    /// `14/07/2026` (when the first number can't be a month), `2026/07/14`,
    /// `14.07.2026`, `Jul 14, 2026` and `14 Jul 2026`. Returns noon local time.
    /// - Parameter order: how to read `05/11/2026`. `nil` reads it month
    ///   first, unless the first number can't be a month.
    static func parseDate(_ text: String, calendar: Calendar = .current, order: CSVDateOrder? = nil) -> Date? {
        parseDate(text, calendar: calendar, order: order, textFormatters: makeTextDateFormatters(calendar: calendar))
    }

    private static func parseDate(
        _ text: String,
        calendar: Calendar,
        order: CSVDateOrder?,
        textFormatters: [DateFormatter]
    ) -> Date? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        // ISO 8601, optionally with a time part.
        if trimmed.count >= 10 {
            let datePart = String(trimmed.prefix(10))
            let pieces = datePart.split(separator: "-")
            if pieces.count == 3, pieces[0].count == 4,
               let year = Int(pieces[0]), let month = Int(pieces[1]), let day = Int(pieces[2]) {
                return calendar.noon(year: year, month: month, day: day)
            }
        }

        if let parts = numericDateParts(trimmed) {
            let (a, b, c) = (parts.a, parts.b, parts.c)
            if parts.firstPieceLength == 4 {
                return calendar.noon(year: a, month: b, day: c)
            }
            let year = parts.lastPieceLength <= 2 ? 2000 + c : c
            if parts.separator == "." {
                return calendar.noon(year: year, month: b, day: a)
            }
            // The file's order when known; otherwise US month/day first,
            // unless the first number can't be a month.
            let dayFirst = order.map { $0 == .dayFirst } ?? (a > 12)
            return dayFirst
                ? calendar.noon(year: year, month: b, day: a)
                : calendar.noon(year: year, month: a, day: b)
        }

        for formatter in textFormatters {
            if let date = formatter.date(from: trimmed) {
                return calendar.noon(on: date)
            }
        }
        return nil
    }

    /// A numeric date such as `07/14/2026`, `14.07.26` or `5-11-2026` split
    /// into its three numbers, ignoring a trailing time such as `09:30`.
    private static func numericDateParts(
        _ text: String
    ) -> (separator: Character, a: Int, b: Int, c: Int, firstPieceLength: Int, lastPieceLength: Int)? {
        let numericPart = String(text.split(whereSeparator: \.isWhitespace).first ?? "")
        for separator: Character in ["/", ".", "-"] {
            let pieces = numericPart.split(separator: separator).map(String.init)
            guard pieces.count == 3, let a = Int(pieces[0]), let b = Int(pieces[1]), let c = Int(pieces[2]) else {
                continue
            }
            return (separator, a, b, c, pieces[0].count, pieces[2].count)
        }
        return nil
    }

    /// What a file's `/` and `-` dates say about day/month order: a first
    /// number of 13–31 can only be a day, and so can a second one.
    /// Year-first and dotted dates don't count; their order is fixed.
    private static func dateOrderEvidence(
        _ cells: [String]
    ) -> (hasNumericDates: Bool, dayFirst: Bool, monthFirst: Bool) {
        var evidence = (hasNumericDates: false, dayFirst: false, monthFirst: false)
        for cell in cells {
            guard let parts = numericDateParts(cell.trimmingCharacters(in: .whitespacesAndNewlines)),
                  parts.separator != ".", parts.firstPieceLength != 4
            else { continue }
            evidence.hasNumericDates = true
            if (13...31).contains(parts.a), (1...12).contains(parts.b) { evidence.dayFirst = true }
            if (13...31).contains(parts.b), (1...12).contains(parts.a) { evidence.monthFirst = true }
        }
        return evidence
    }

    private static let textDateFormats = ["MMM d, yyyy", "MMMM d, yyyy", "d MMM yyyy", "d MMMM yyyy", "MMM d yyyy"]

    /// One formatter per text format, made once per file rather than per row.
    private static func makeTextDateFormatters(calendar: Calendar) -> [DateFormatter] {
        textDateFormats.map { format in
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.calendar = calendar
            formatter.timeZone = calendar.timeZone
            formatter.dateFormat = format
            return formatter
        }
    }

    // MARK: Header names

    static func normalizeHeader(_ header: String) -> String {
        String(header.lowercased().unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }.map(Character.init))
    }

    private static func firstIndex(in names: [String], of candidates: [String]) -> Int? {
        for candidate in candidates {
            if let index = names.firstIndex(of: candidate) { return index }
        }
        return nil
    }

    private static let dateHeaders = ["date", "transactiondate", "posteddate", "postingdate", "transdate", "bookingdate", "posted"]
    private static let descriptionHeaders = ["description", "name", "merchant", "payee", "merchantname", "transactiondescription", "details", "originaldescription", "memo"]
    private static let amountHeaders = ["amount", "transactionamount", "amountusd", "value"]
    private static let debitHeaders = ["debit", "debitamount", "withdrawal", "withdrawals", "moneyout", "paidout"]
    private static let creditHeaders = ["credit", "creditamount", "deposit", "deposits", "moneyin", "paidin"]
    private static let typeHeaders = ["transactiontype", "type", "debitcredit"]
    private static let categoryHeaders = ["category", "categoryname"]
    private static let accountHeaders = ["account", "accountname"]
    private static let notesHeaders = ["notes", "note", "memo"]
}

// MARK: - De-duplication

nonisolated enum ImportDeduplicator {
    /// Drops incoming transactions that already exist.
    ///
    /// Counts are compared per fingerprint, so a file with two identical $5
    /// coffees on one day imports both — unless the app already has two.
    static func newTransactions(
        _ incoming: [ImportedTransaction],
        existingFingerprints: [String],
        calendar: Calendar = .current
    ) -> (new: [ImportedTransaction], duplicateCount: Int) {
        var remaining: [String: Int] = [:]
        for fingerprint in existingFingerprints { remaining[fingerprint, default: 0] += 1 }

        var fresh: [ImportedTransaction] = []
        var duplicates = 0
        for transaction in incoming {
            let fingerprint = transaction.fingerprint(calendar: calendar)
            if let count = remaining[fingerprint], count > 0 {
                remaining[fingerprint] = count - 1
                duplicates += 1
            } else {
                fresh.append(transaction)
            }
        }
        return (fresh, duplicates)
    }
}
