import SwiftUI

/// A one-click switch whose symbol is the setting in effect, not an on/off highlight to decode. The tooltip
/// says the setting and what a click does; the same text serves accessibility.
struct StateButton: View {
    var symbol: String
    var state: String
    var action: String
    var perform: () -> Void

    var body: some View {
        Button(action: perform) {
            Image(systemName: symbol)
                .font(.body)
                // One box for every symbol, so every StateButton has the same size in either state.
                .frame(width: 18, height: 18)
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .help("\(state). Click to \(action).")
        .accessibilityLabel(state)
        .accessibilityHint("Click to \(action).")
    }
}
