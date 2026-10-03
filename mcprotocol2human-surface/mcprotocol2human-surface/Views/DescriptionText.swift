import AppKit
import SwiftUI

/// The ways agent-facing text can be displayed (ADR-0008). None of them is what the model sees; they are
/// on trial, to find out which reads best.
enum DescriptionDisplay: String, CaseIterable, Identifiable {
    /// Whitespace interpreted (see `DescriptionFormat`), every other character as it is.
    case reflowed
    /// As `reflowed`, with inline Markdown rendered: `code` in monospace, emphasis, links.
    case markdown
    /// Each original line kept as a unit and wrapped to the width, with a small gap between lines and a
    /// larger one between paragraphs: for text that breaks lines by meaning (semantic line breaks).
    case wrappedLines
    /// The original line breaks, in monospace, without wrapping.
    case originalLines

    var id: Self { self }

    var label: String {
        switch self {
        case .reflowed: "Reflowed"
        case .markdown: "Markdown"
        case .wrappedLines: "Wrapped lines"
        case .originalLines: "Original lines"
        }
    }

    static let preferenceKey = "descriptionDisplay"
}

/// Agent-facing text, in the display chosen in a tool's Description header. That choice applies to every
/// description and to server instructions.
struct DescriptionText: View {
    var text: String
    @AppStorage(DescriptionDisplay.preferenceKey, store: Preferences.store) private var display = DescriptionDisplay.reflowed

    var body: some View {
        switch display {
        case .originalLines:
            MonospaceBlock(text: text)
        case .reflowed, .markdown, .wrappedLines:
            let keepsLines = display == .wrappedLines
            VStack(alignment: .leading, spacing: keepsLines ? 14 : 8) {
                ForEach(Array(DescriptionFormat.blocks(text, lines: keepsLines ? .kept : .joined).enumerated()), id: \.offset) { _, block in
                    switch block {
                    case .paragraph(let text):
                        lines(text, kept: keepsLines)
                    case .listItem(let marker, let text, let level):
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text(verbatim: marker)
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                            lines(text, kept: keepsLines)
                        }
                        .padding(.leading, CGFloat(level) * 16)
                    case .code(let code):
                        Text(verbatim: code)
                            .font(.callout.monospaced())
                            .padding(8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(RoundedRectangle(cornerRadius: 6).fill(Color.secondary.opacity(0.08)))
                    }
                }
            }
            .textSelection(.enabled)
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// A paragraph's or list item's text: one wrapped run, or with kept lines one wrapped unit per line,
    /// spaced a little apart.
    @ViewBuilder private func lines(_ text: String, kept: Bool) -> some View {
        if kept {
            VStack(alignment: .leading, spacing: 5) {
                ForEach(Array(text.split(separator: "\n", omittingEmptySubsequences: false).enumerated()), id: \.offset) { _, unit in
                    Text(verbatim: String(unit))
                }
            }
        } else {
            display == .markdown ? Text(Self.inline(text)) : Text(verbatim: text)
        }
    }

    /// Inline Markdown: `code` in monospace, emphasis, links. Text that is not valid Markdown shows as it is.
    nonisolated static func inline(_ text: String) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        return (try? AttributedString(markdown: text, options: options)) ?? AttributedString(text)
    }
}

/// The switch between displays, for a Description header.
struct DescriptionDisplayPicker: View {
    @AppStorage(DescriptionDisplay.preferenceKey, store: Preferences.store) private var display = DescriptionDisplay.reflowed

    var body: some View {
        Picker("Display", selection: $display) {
            ForEach(DescriptionDisplay.allCases) { Text($0.label).tag($0) }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .controlSize(.small)
        .fixedSize()
        .help("How descriptions are displayed. None of these is what the model sees; see ADR-0008.")
    }
}

/// Text in monospace with its line breaks and leading spaces as they are, scrolling sideways rather than
/// wrapping. Used for JSON and for the "Original lines" display.
struct MonospaceBlock: View {
    var text: String

    var body: some View {
        ScrollView(.horizontal) {
            Text(verbatim: text)
                .font(.callout.monospaced())
                .textSelection(.enabled)
                .fixedSize()
                .padding(8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 6).fill(Color.secondary.opacity(0.06)))
    }
}

/// The one copy button: copies text exactly as given, highlights on hover like a toolbar button, and shows
/// a check mark for a moment after copying.
struct CopyButton: View {
    var text: String
    var help: String
    @State private var copied = false

    var body: some View {
        Button {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
            copied = true
            Task {
                try? await Task.sleep(for: .seconds(1.5))
                copied = false
            }
        } label: {
            Image(systemName: copied ? "checkmark" : "doc.on.doc")
                .frame(width: 16, height: 16)
        }
        .buttonStyle(HoverButtonStyle())
        .help(copied ? "Copied" : help)
        .accessibilityLabel(help)
    }
}

/// Borderless until the pointer is over it; then a light rounded background, darker while pressed.
struct HoverButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        HoverBody(configuration: configuration)
    }

    private struct HoverBody: View {
        let configuration: Configuration
        @State private var hovering = false

        var body: some View {
            configuration.label
                .foregroundStyle(.secondary)
                .padding(4)
                .background(
                    RoundedRectangle(cornerRadius: 5)
                        .fill(Color.primary.opacity(configuration.isPressed ? 0.16 : hovering ? 0.08 : 0)))
                .contentShape(Rectangle())
                .onHover { hovering = $0 }
        }
    }
}
