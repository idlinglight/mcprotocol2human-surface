import Foundation

/// Reads the whitespace of agent-facing text (tool and parameter descriptions, server instructions) for
/// display to people (ADR-0008). Only whitespace is interpreted; every other character stays as it is.
///
/// Servers often send docstrings hard-wrapped to a line length. Within a paragraph those line breaks are
/// joined; blank lines separate paragraphs; list items keep their own lines and markers, with indented
/// continuation lines joined to them; fenced code blocks stay as they are. Spaces inside a pair of
/// backticks become no-break spaces, so a code span cannot be split across display lines.
nonisolated enum DescriptionFormat {
    enum Block: Equatable, Sendable {
        case paragraph(String)
        /// `marker` as written (`-`, `*`, `1.`, …); `level` counts indentation steps.
        case listItem(marker: String, text: String, level: Int)
        case code(String)
    }

    static func blocks(_ text: String) -> [Block] {
        var blocks: [Block] = []
        var paragraph: [String] = []
        var item: (marker: String, text: [String], level: Int)?
        var code: [String]?

        func flush() {
            if !paragraph.isEmpty {
                blocks.append(.paragraph(keepingCodeSpansTogether(joinWrapped(paragraph))))
                paragraph = []
            }
            if let current = item {
                blocks.append(.listItem(marker: current.marker, text: keepingCodeSpansTogether(joinWrapped(current.text)), level: current.level))
                item = nil
            }
        }

        for line in dedented(lines(of: text)) {
            if var lines = code {
                if line.trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                    blocks.append(.code(lines.joined(separator: "\n")))
                    code = nil
                } else {
                    lines.append(line)
                    code = lines
                }
                continue
            }
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            let indent = line.prefix { $0 == " " }.count
            if trimmed.isEmpty {
                flush()
            } else if trimmed.hasPrefix("```") {
                flush()
                code = []
            } else if let marker = listMarker(trimmed) {
                flush()
                let content = String(trimmed.dropFirst(marker.length)).trimmingCharacters(in: .whitespaces)
                item = (marker.display, [content], indent / 2)
            } else if var current = item, indent > 0 {
                // Indented lines continue the list item above them.
                current.text.append(trimmed)
                item = current
            } else {
                if item != nil { flush() }
                paragraph.append(line.hasSuffix("  ") ? line : trimmed)
            }
        }
        if let lines = code {
            // An unclosed fence: keep what was there as code rather than lose it.
            blocks.append(.code(lines.joined(separator: "\n")))
        }
        flush()
        return blocks
    }

    /// The first block's text, for one-glance places such as a tool's row; nil if there is none.
    static func summary(_ text: String) -> String? {
        switch blocks(text).first {
        case .paragraph(let text)?: text
        case .listItem(let marker, let text, _)?: "\(marker) \(text)"
        case .code(let code)?: code
        case nil: nil
        }
    }

    /// The text reflowed for places that show plain text only, such as tooltips.
    static func plainText(_ text: String) -> String {
        var result = ""
        var previousWasItem = false
        for block in blocks(text) {
            let isItem: Bool
            let piece: String
            switch block {
            case .paragraph(let text): (isItem, piece) = (false, text)
            case .listItem(let marker, let text, let level): (isItem, piece) = (true, String(repeating: "  ", count: level) + "\(marker) \(text)")
            case .code(let code): (isItem, piece) = (false, code)
            }
            if !result.isEmpty { result += isItem && previousWasItem ? "\n" : "\n\n" }
            result += piece
            previousWasItem = isItem
        }
        return result
    }

    // MARK: -

    private static func lines(of text: String) -> [String] {
        text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
            .split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
    }

    /// Removes the indentation all lines after the first share, as Python's `inspect.cleandoc` does, so an
    /// indented docstring does not look like one long indented block.
    private static func dedented(_ lines: [String]) -> [String] {
        guard lines.count > 1 else { return lines }
        let rest = lines.dropFirst().filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        let common = rest.map { line in line.prefix { $0 == " " }.count }.min() ?? 0
        guard common > 0 else { return lines }
        return [lines[0]] + lines.dropFirst().map { $0.count >= common ? String($0.dropFirst(common)) : $0.trimmingCharacters(in: .whitespaces) }
    }

    /// Joins hard-wrapped lines with spaces. A line ending in two spaces asks for a line break, as in Markdown.
    private static func joinWrapped(_ lines: [String]) -> String {
        var result = ""
        for (index, line) in lines.enumerated() {
            let keepsBreak = line.hasSuffix("  ")
            result += line.trimmingCharacters(in: .whitespaces)
            if index < lines.count - 1 { result += keepsBreak ? "\n" : " " }
        }
        return result
    }

    /// Spaces inside backtick code spans become no-break spaces. A span opens with a run of backticks and
    /// closes with the next run of the same length, as in CommonMark; an unclosed run stays as it is.
    static func keepingCodeSpansTogether(_ text: String) -> String {
        guard text.contains("`") else { return text }
        var characters = Array(text)
        var runs: [(start: Int, length: Int)] = []
        var index = 0
        while index < characters.count {
            guard characters[index] == "`" else { index += 1; continue }
            let start = index
            while index < characters.count, characters[index] == "`" { index += 1 }
            runs.append((start, index - start))
        }
        var runIndex = 0
        while runIndex < runs.count {
            let opening = runs[runIndex]
            guard let closingIndex = runs[(runIndex + 1)...].firstIndex(where: { $0.length == opening.length }) else {
                runIndex += 1
                continue
            }
            for position in (opening.start + opening.length)..<runs[closingIndex].start where characters[position] == " " {
                characters[position] = "\u{00A0}"
            }
            runIndex = closingIndex + 1
        }
        return String(characters)
    }

    /// `- `, `* `, `+ `, `• `, `1. ` or `1) ` at the start of a line.
    private static func listMarker(_ trimmed: String) -> (display: String, length: Int)? {
        for bullet in ["- ", "* ", "+ ", "• "] where trimmed.hasPrefix(bullet) {
            return (String(bullet.dropLast()), bullet.count)
        }
        let digits = trimmed.prefix { $0.isASCII && $0.isNumber }
        guard !digits.isEmpty, digits.count <= 3 else { return nil }
        let rest = trimmed.dropFirst(digits.count)
        guard let punctuation = rest.first, punctuation == "." || punctuation == ")", rest.dropFirst().first == " " else { return nil }
        return (digits + String(punctuation), digits.count + 2)
    }
}
