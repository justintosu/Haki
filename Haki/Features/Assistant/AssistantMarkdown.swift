//
//  AssistantMarkdown.swift
//  Haki
//
//  Renders the assistant's answers: inline Markdown (bold, italics, code,
//  links) through `AttributedString`, and the block parts Claude uses most
//  (paragraphs, "- " bullet lists, "1. " numbered lists, "## " headings)
//  as separate rows.
//

import Foundation
import SwiftUI

/// One paragraph, heading or list row of an answer.
nonisolated struct AssistantMarkdownBlock: Identifiable, Equatable {
    nonisolated enum Kind: Equatable {
        case paragraph
        case heading
        /// 0 = top level, 1 and 2 = nested.
        case bullet(level: Int)
        /// "1."
        case numbered(marker: String)
    }

    let id: Int
    let kind: Kind
    let text: AttributedString

    /// The text without Markdown marks.
    var plainText: String { String(text.characters) }
}

nonisolated enum AssistantMarkdown {
    /// Splits `source` into blocks; each block's text keeps its inline Markdown.
    static func blocks(from source: String) -> [AssistantMarkdownBlock] {
        var blocks: [AssistantMarkdownBlock] = []
        var paragraph: [String] = []

        func add(_ kind: AssistantMarkdownBlock.Kind, _ text: String) {
            blocks.append(AssistantMarkdownBlock(id: blocks.count, kind: kind, text: inline(text)))
        }

        func flushParagraph() {
            guard !paragraph.isEmpty else { return }
            add(.paragraph, paragraph.joined(separator: "\n"))
            paragraph.removeAll()
        }

        let lines = source
            .replacingOccurrences(of: "\r\n", with: "\n")
            .components(separatedBy: "\n")

        for rawLine in lines {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("```") || isRule(line) {
                flushParagraph()
                continue
            }
            if let heading = headingText(line) {
                flushParagraph()
                add(.heading, heading)
                continue
            }
            if let item = bulletText(line) {
                flushParagraph()
                add(.bullet(level: min(indentation(of: rawLine) / 2, 2)), item)
                continue
            }
            if let item = numberedItem(line) {
                flushParagraph()
                add(.numbered(marker: item.marker), item.text)
                continue
            }
            if let row = tableRow(line) {
                paragraph.append(row)
                continue
            }
            paragraph.append(line)
        }
        flushParagraph()
        return blocks
    }

    /// The answer as plain text on one line (for history previews).
    static func plainText(_ source: String) -> String {
        blocks(from: source)
            .map(\.plainText)
            .joined(separator: " ")
            .replacingOccurrences(of: "\n", with: " ")
    }

    /// Inline Markdown (bold, italics, code, links), keeping line breaks.
    static func inline(_ text: String) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        if let parsed = try? AttributedString(markdown: text, options: options) {
            return parsed
        }
        return AttributedString(text)
    }

    // MARK: Line kinds

    private static func indentation(of line: String) -> Int {
        var count = 0
        for character in line {
            if character == " " {
                count += 1
            } else if character == "\t" {
                count += 4
            } else {
                break
            }
        }
        return count
    }

    /// "- item", "* item", "• item", "+ item".
    private static func bulletText(_ line: String) -> String? {
        for marker in ["- ", "* ", "• ", "+ "] where line.hasPrefix(marker) {
            let rest = String(line.dropFirst(marker.count)).trimmingCharacters(in: .whitespaces)
            return rest.isEmpty ? nil : rest
        }
        return nil
    }

    /// "1. item" or "1) item".
    private static func numberedItem(_ line: String) -> (marker: String, text: String)? {
        let digits = String(line.prefix(while: { $0.isASCII && $0.isNumber }))
        guard !digits.isEmpty, digits.count <= 3 else { return nil }
        let rest = line.dropFirst(digits.count)
        guard let delimiter = rest.first, delimiter == "." || delimiter == ")" else { return nil }
        let afterDelimiter = rest.dropFirst()
        guard afterDelimiter.first == " " else { return nil }
        let text = String(afterDelimiter).trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return nil }
        return (marker: digits + ".", text: text)
    }

    /// "## Heading" (any level).
    private static func headingText(_ line: String) -> String? {
        let hashes = line.prefix(while: { $0 == "#" }).count
        guard hashes > 0, hashes <= 6 else { return nil }
        let rest = line.dropFirst(hashes)
        guard rest.first == " " else { return nil }
        let text = String(rest).trimmingCharacters(in: .whitespaces)
        return text.isEmpty ? nil : text
    }

    /// "---", "***", "___" and table separator rows ("|---|:--|").
    private static func isRule(_ line: String) -> Bool {
        let compact = line.filter { $0 != " " }
        if compact.count >= 3, let first = compact.first, "-*_".contains(first), compact.allSatisfy({ $0 == first }) {
            return true
        }
        if compact.hasPrefix("|"), compact.contains("-"), compact.allSatisfy({ "|-:".contains($0) }) {
            return true
        }
        return false
    }

    /// "| a | b |" → "a · b".
    private static func tableRow(_ line: String) -> String? {
        guard line.hasPrefix("|"), line.hasSuffix("|"), line.count > 1 else { return nil }
        let cells = line
            .split(separator: "|")
            .map { String($0).trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        guard !cells.isEmpty else { return nil }
        return cells.joined(separator: " · ")
    }
}

/// An answer's blocks, stacked.
struct AssistantMarkdownView: View {
    let blocks: [AssistantMarkdownBlock]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(blocks) { block in
                AssistantMarkdownBlockView(block: block)
            }
        }
    }
}

private struct AssistantMarkdownBlockView: View {
    let block: AssistantMarkdownBlock

    var body: some View {
        switch block.kind {
        case .paragraph:
            Text(block.text)
                .fixedSize(horizontal: false, vertical: true)
        case .heading:
            Text(block.text)
                .font(.headline)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
        case .bullet(let level):
            AssistantListRow(marker: level == 0 ? "•" : "◦", text: block.text)
                .padding(.leading, CGFloat(level) * 16)
        case .numbered(let marker):
            AssistantListRow(marker: marker, text: block.text)
        }
    }
}

private struct AssistantListRow: View {
    let marker: String
    let text: AttributedString

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(verbatim: marker)
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text(text)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

#Preview {
    ScrollView {
        AssistantMarkdownView(blocks: AssistantMarkdown.blocks(from: """
        ## This month
        You've spent **$1,284** so far, about *$90 less* than last month.

        - Groceries: $412
        - Restaurants: $212
          - Mostly weekends
        1. Set a dining budget
        2. Review subscriptions
        """))
        .padding()
    }
    .previewEnvironment()
}
