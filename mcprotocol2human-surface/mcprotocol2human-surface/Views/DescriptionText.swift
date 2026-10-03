import AppKit
import SwiftUI

/// Description text rendered for reading (see `DescriptionFormat`): paragraphs and list items in the body
/// font, wrapped to the width; `code` and code blocks in monospace.
struct DescriptionText: View {
    var text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(DescriptionFormat.blocks(text).enumerated()), id: \.offset) { _, block in
                switch block {
                case .paragraph(let text):
                    Text(Self.inline(text))
                case .listItem(let marker, let text, let level):
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(marker)
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                        Text(Self.inline(text))
                    }
                    .padding(.leading, CGFloat(level) * 16)
                case .code(let code):
                    Text(code)
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

    /// Inline Markdown: `code` in monospace, emphasis, links. Text that is not valid Markdown shows as it is.
    nonisolated static func inline(_ text: String) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        return (try? AttributedString(markdown: text, options: options)) ?? AttributedString(text)
    }
}

/// A small button that copies text exactly as given and shows a check mark for a moment.
struct CopyRawButton: View {
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
        .buttonStyle(.borderless)
        .help(copied ? "Copied" : help)
        .accessibilityLabel(help)
    }
}
