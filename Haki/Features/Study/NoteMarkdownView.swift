//
//  NoteMarkdownView.swift
//  Haki
//
//  A note's text rendered as Markdown for the editor's Preview: headings,
//  bulleted, numbered and checkbox lists, quotes, code blocks and dividers,
//  with bold, italics, code and links inside each line. Line breaks are kept,
//  so a note reads the way it was typed.
//

import Foundation
import SwiftUI

struct NoteMarkdownView: View {
    let text: String

    var body: some View {
        let blocks = NoteMarkdownParser.blocks(from: text)
        VStack(alignment: .leading, spacing: 8) {
            ForEach(blocks) { block in
                NoteMarkdownBlockView(block: block)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .textSelection(.enabled)
    }
}

// MARK: - Blocks

/// One line (or code block) of a note, ready to draw.
struct NoteMarkdownBlock: Identifiable {
    enum Kind {
        /// Level 1...6 and the heading text.
        case heading(Int, String)
        case paragraph(String)
        /// Text and indent level.
        case bullet(String, Int)
        /// Text, marker ("1.") and indent level.
        case numbered(String, String, Int)
        /// Text, whether it's ticked, and indent level.
        case task(String, Bool, Int)
        case quote(String)
        case code(String)
        case divider
        /// A blank line between blocks.
        case spacer

        var isSpacer: Bool {
            if case .spacer = self { return true }
            return false
        }
    }

    let id: Int
    let kind: Kind
}

/// Splits a note's text into blocks. Forgiving: anything it doesn't
/// recognize is a plain line.
enum NoteMarkdownParser {
    static func blocks(from text: String) -> [NoteMarkdownBlock] {
        var kinds: [NoteMarkdownBlock.Kind] = []
        var codeLines: [String] = []
        var isInCode = false

        for rawLine in text.components(separatedBy: .newlines) {
            let line = rawLine.replacingOccurrences(of: "\t", with: "    ")
            let content = line.trimmingCharacters(in: .whitespaces)
            if content.hasPrefix("```") {
                if isInCode {
                    kinds.append(.code(codeLines.joined(separator: "\n")))
                    codeLines = []
                    isInCode = false
                } else {
                    isInCode = true
                }
                continue
            }
            if isInCode {
                codeLines.append(line)
                continue
            }
            if content.isEmpty {
                if let last = kinds.last, !last.isSpacer {
                    kinds.append(.spacer)
                }
                continue
            }
            let indent = min(3, line.prefix(while: { $0 == " " }).count / 2)
            kinds.append(kind(for: content, indent: indent))
        }
        if isInCode {
            kinds.append(.code(codeLines.joined(separator: "\n")))
        }
        while let last = kinds.last, last.isSpacer {
            kinds.removeLast()
        }
        var blocks: [NoteMarkdownBlock] = []
        for (index, kind) in kinds.enumerated() {
            blocks.append(NoteMarkdownBlock(id: index, kind: kind))
        }
        return blocks
    }

    private static func kind(for line: String, indent: Int) -> NoteMarkdownBlock.Kind {
        if let heading = heading(line) { return heading }
        if isDivider(line) { return .divider }
        if line.hasPrefix(">") {
            return .quote(String(line.dropFirst()).trimmingCharacters(in: .whitespaces))
        }
        let taskMarkers = ["- [ ] ", "* [ ] ", "- [x] ", "- [X] ", "* [x] ", "* [X] "]
        for marker in taskMarkers where line.hasPrefix(marker) {
            let isDone = marker.contains("x") || marker.contains("X")
            return .task(String(line.dropFirst(marker.count)), isDone, indent)
        }
        for marker in ["- ", "* ", "+ ", "• "] where line.hasPrefix(marker) {
            return .bullet(String(line.dropFirst(marker.count)), indent)
        }
        if let numbered = numbered(line, indent: indent) { return numbered }
        return .paragraph(line)
    }

    /// "# Title" ... "###### Title".
    private static func heading(_ line: String) -> NoteMarkdownBlock.Kind? {
        let hashes = line.prefix(while: { $0 == "#" }).count
        guard hashes >= 1, hashes <= 6 else { return nil }
        let rest = line.dropFirst(hashes)
        guard rest.hasPrefix(" ") else { return nil }
        let title = rest.trimmingCharacters(in: .whitespaces)
        guard !title.isEmpty else { return nil }
        return .heading(hashes, title)
    }

    /// "---", "***" or "___" (spaces allowed between).
    private static func isDivider(_ line: String) -> Bool {
        let marks = line.filter { $0 != " " }
        guard marks.count >= 3, let first = marks.first, first == "-" || first == "*" || first == "_" else { return false }
        return marks.allSatisfy { $0 == first }
    }

    /// "1. Text" or "1) Text".
    private static func numbered(_ line: String, indent: Int) -> NoteMarkdownBlock.Kind? {
        let digits = line.prefix(while: { $0.isASCII && $0.isNumber })
        guard !digits.isEmpty, digits.count <= 3 else { return nil }
        let rest = line.dropFirst(digits.count)
        guard let mark = rest.first, mark == "." || mark == ")" else { return nil }
        let afterMark = rest.dropFirst()
        guard afterMark.hasPrefix(" ") else { return nil }
        return .numbered(afterMark.trimmingCharacters(in: .whitespaces), "\(digits).", indent)
    }
}

/// Inline Markdown (bold, italics, code, links) for one line.
enum NoteMarkdownInline {
    static func attributed(_ text: String) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        if let parsed = try? AttributedString(markdown: text, options: options) {
            return parsed
        }
        return AttributedString(text)
    }
}

// MARK: - Drawing

private struct NoteMarkdownBlockView: View {
    let block: NoteMarkdownBlock

    var body: some View {
        switch block.kind {
        case .heading(let level, let text):
            heading(text, level: level)
        case .paragraph(let text):
            Text(NoteMarkdownInline.attributed(text))
                .fixedSize(horizontal: false, vertical: true)
        case .bullet(let text, let indent):
            listRow(marker: "•", text: text, indent: indent)
        case .numbered(let text, let marker, let indent):
            listRow(marker: marker, text: text, indent: indent)
        case .task(let text, let isDone, let indent):
            taskRow(text: text, isDone: isDone, indent: indent)
        case .quote(let text):
            quote(text)
        case .code(let code):
            codeBlock(code)
        case .divider:
            Divider()
                .padding(.vertical, 4)
        case .spacer:
            Color.clear
                .frame(height: 4)
                .accessibilityHidden(true)
        }
    }

    private func heading(_ text: String, level: Int) -> some View {
        Text(NoteMarkdownInline.attributed(text))
            .font(headingFont(level))
            .padding(.top, level <= 2 ? 6 : 2)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityAddTraits(.isHeader)
    }

    private func headingFont(_ level: Int) -> Font {
        switch level {
        case 1: return .title2.weight(.bold)
        case 2: return .title3.weight(.bold)
        case 3: return .headline
        default: return .subheadline.weight(.semibold)
        }
    }

    private func listRow(marker: String, text: String, indent: Int) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(marker)
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .accessibilityHidden(marker == "•")
            Text(NoteMarkdownInline.attributed(text))
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.leading, CGFloat(indent) * 18)
    }

    private func taskRow(text: String, isDone: Bool, indent: Int) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: isDone ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(isDone ? Color.accentColor : Color.secondary)
                .accessibilityHidden(true)
            Text(NoteMarkdownInline.attributed(text))
                .strikethrough(isDone)
                .foregroundStyle(isDone ? Color.secondary : Color.primary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.leading, CGFloat(indent) * 18)
        .accessibilityElement(children: .combine)
        .accessibilityValue(isDone ? "Done" : "Not done")
    }

    private func quote(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(Color.accentColor.opacity(0.6))
                .frame(width: 3)
                .accessibilityHidden(true)
            Text(NoteMarkdownInline.attributed(text))
                .italic()
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private func codeBlock(_ code: String) -> some View {
        Text(code)
            .font(.system(.callout, design: .monospaced))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

#Preview {
    ScrollView {
        NoteMarkdownView(text: """
        # Cell biology
        **Mitochondria** make ATP, the cell's *energy*.
        - Photosynthesis happens in the chloroplasts.
          - Inside the `thylakoids`.
        1. DNA carries genetic information.
        2. RNA reads it.
        - [x] Read chapter 3
        - [ ] Make flashcards
        > Osmosis: water moves toward the higher solute concentration.
        ---
        Learn more at [the library](https://example.com).
        """)
        .padding()
    }
    .previewEnvironment()
}
