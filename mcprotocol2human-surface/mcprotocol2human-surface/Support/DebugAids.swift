#if DEBUG
import AppKit
import os
import ScreenCaptureKit

/// Development aids, compiled into Debug builds only, so the app can be driven and inspected from a shell
/// session where nobody looks at the screen. All of them are switched on by environment variables:
///
/// - `M2H_SELECT=<server name>`: select that server at launch, which starts its discovery.
/// - `M2H_SELECT_PAGE=overview|traffic|<tool name>`: once the run has finished, show that page.
/// - `M2H_WINDOW_SIZE=<width>x<height>`: resize the main window at launch.
/// - `M2H_DEFAULTS_SUITE=<name>`: keep preferences in a scratch store instead of the installed app's;
///   `M2H_DEFAULTS='{"key": value}'` seeds it. See `Preferences`.
/// - `M2H_FLIP_DESCRIPTIONS=1` (with a scratch store): before the snapshot, switch the tool rows between
///   names only and names with description, as the eye button does, to see the list after the switch.
/// - `M2H_FILTER=<text>`: set the tool filter's text, taken as it is. `M2H_FILTER_NAMES_ONLY=1` and
///   `M2H_FILTER_INVERT=1` switch its two settings.
/// - `M2H_SNAPSHOT=/path/to/file.png`: once the selected server's run has finished (or after the delay),
///   write an image of the main window there and a text dump next to it (`file.txt`) with the model's
///   state and the view hierarchy. `M2H_SNAPSHOT_DELAY=<seconds>` is the longest wait (default 30);
///   `M2H_SNAPSHOT_QUIT=1` quits afterwards; `M2H_SNAPSHOT_SETTINGS=1` captures the Settings window instead.
///   The app activates itself first, taking the focus from whatever app has it.
///   The image comes from ScreenCaptureKit when the app may already record the screen (it never asks),
///   otherwise from drawing the window's views, which can miss materials such as the sidebar's.
///
/// `M2H_SERVERS_FILE` (not debug-only) points the app at another servers file.
///
///     M2H_SERVERS_FILE=/tmp/servers.json M2H_SELECT=example M2H_SNAPSHOT=/tmp/main.png M2H_SNAPSHOT_QUIT=1 \
///         path/to/mcprotocol2human-surface.app/Contents/MacOS/mcprotocol2human-surface
@MainActor
enum DebugAids {
    static var environment: [String: String] { ProcessInfo.processInfo.environment }

    static func apply(to model: AppModel) {
        if let size = environment["M2H_WINDOW_SIZE"]?.split(separator: "x").compactMap({ Double($0) }), size.count == 2 {
            Task {
                try? await Task.sleep(for: .milliseconds(200))
                NSApp.windows.first { $0.isVisible }?.setContentSize(NSSize(width: size[0], height: size[1]))
            }
        }
        if let text = environment["M2H_FILTER"] {
            model.toolFilter = ToolFilter(
                text: text,
                namesOnly: environment["M2H_FILTER_NAMES_ONLY"] == "1",
                inverted: environment["M2H_FILTER_INVERT"] == "1")
        }
        if let server = environment["M2H_SELECT"] {
            Task {
                // Let the window come up first, so the selection drives the views as a click would.
                try? await Task.sleep(for: .milliseconds(300))
                model.selectedServer = server
                await waitForRun(of: server, in: model)
                selectPage(in: model)
            }
        }
        scheduleSnapshotIfRequested(model: model)
    }

    private static func waitForRun(of server: String, in model: AppModel) async {
        let limit = Double(environment["M2H_SNAPSHOT_DELAY"] ?? "") ?? 30
        let deadline = Date.now.addingTimeInterval(limit)
        while model.run(for: server) == nil || model.isRunning(server), Date.now < deadline {
            try? await Task.sleep(for: .milliseconds(200))
        }
    }

    private static func selectPage(in model: AppModel) {
        guard let page = environment["M2H_SELECT_PAGE"], let server = model.selectedServer else { return }
        switch page {
        case "overview": model.selectedPage = .overview
        case "traffic": model.selectedPage = .traffic
        default:
            if let tool = model.run(for: server)?.result?.tools.first(where: { $0.name == page }) {
                model.selectedPage = .tool(tool.position)
            }
        }
    }

    private static func scheduleSnapshotIfRequested(model: AppModel) {
        guard let path = environment["M2H_SNAPSHOT"] else { return }
        Task {
            try? await Task.sleep(for: .milliseconds(300))
            // Snapshot an active window: inactive ones grey out accents, such as a toggle that is on.
            NSApp.activate()
            if let server = environment["M2H_SELECT"] {
                await waitForRun(of: server, in: model)
            }
            if environment["M2H_SNAPSHOT_SETTINGS"] == "1" {
                SettingsOpener.request()
            }
            if environment["M2H_FLIP_DESCRIPTIONS"] == "1" {
                if Preferences.store === UserDefaults.standard {
                    Log.app.error("M2H_FLIP_DESCRIPTIONS needs M2H_DEFAULTS_SUITE; not touching the real preferences")
                } else {
                    try? await Task.sleep(for: .seconds(1))
                    let key = "showsToolDescriptions"
                    Preferences.store.set(!(Preferences.store.object(forKey: key) as? Bool ?? true), forKey: key)
                }
            }
            // Give the views a moment to lay out what just arrived.
            try? await Task.sleep(for: .seconds(1))
            await write(to: path, model: model)
            if environment["M2H_SNAPSHOT_QUIT"] == "1" {
                NSApp.terminate(nil)
            }
        }
    }

    static func write(to path: String, model: AppModel) async {
        var report = "== Model ==\n\(model.debugSummary)\n\n== Windows ==\n"
        for window in NSApp.windows {
            report += "\(type(of: window)) \"\(window.title)\" visible=\(window.isVisible) key=\(window.isKeyWindow) frame=\(window.frame)\n"
        }
        let wantsSettings = environment["M2H_SNAPSHOT_SETTINGS"] == "1"
        let target = wantsSettings
            ? NSApp.windows.first { $0.isVisible && $0.identifier?.rawValue.contains("Settings") == true }
                ?? NSApp.windows.first { $0.isVisible && $0.title.contains("Settings") }
            : NSApp.windows.first { $0.isVisible && $0.identifier?.rawValue == "main" }
                ?? NSApp.mainWindow ?? NSApp.windows.first(where: \.isVisible)
        var image: CGImage?
        if let window = target {
            if let frameView = window.contentView?.superview {
                report += "\n== View hierarchy of \"\(window.title)\" ==\n"
                dump(frameView, depth: 0, into: &report)
            }
            if CGPreflightScreenCaptureAccess() {
                do {
                    image = try await captureWithScreenCaptureKit(window)
                    report += "\nImage: ScreenCaptureKit\n"
                } catch {
                    report += "\nScreenCaptureKit failed: \(error.localizedDescription)\n"
                }
            }
            if image == nil {
                image = renderViews(of: window)
                report += "\nImage: view drawing\n"
            }
        } else {
            report += "\nNo matching visible window.\n"
        }
        if let image, let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) {
            try? png.write(to: URL(fileURLWithPath: path))
        }
        let textPath = (path as NSString).deletingPathExtension + ".txt"
        try? report.write(toFile: textPath, atomically: true, encoding: .utf8)
        Log.app.info("Snapshot written to \(path, privacy: .public)")
    }

    /// One line per view: class, frame, and what a table, text field or button holds.
    private static func dump(_ view: NSView, depth: Int, into report: inout String) {
        guard depth < 40 else { return }
        var parts = ["\(type(of: view))"]
        let frame = view.frame
        parts.append("[\(Int(frame.minX)),\(Int(frame.minY)) \(Int(frame.width))x\(Int(frame.height))]")
        if view.isHidden { parts.append("hidden") }
        if let table = view as? NSTableView {
            parts.append("rows=\(table.numberOfRows) selected=\(Array(table.selectedRowIndexes))")
        }
        if let field = view as? NSTextField, !field.stringValue.isEmpty {
            parts.append("text=\"\(field.stringValue.prefix(80))\"")
        }
        if let button = view as? NSButton, !button.title.isEmpty {
            parts.append("title=\"\(button.title)\"")
        }
        report += String(repeating: "  ", count: depth) + parts.joined(separator: " ") + "\n"
        for subview in view.subviews {
            dump(subview, depth: depth + 1, into: &report)
        }
    }

    /// The window as the window server shows it. Needs screen-recording permission, which is not requested.
    private static func captureWithScreenCaptureKit(_ window: NSWindow) async throws -> CGImage {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let target = content.windows.first(where: { $0.windowID == CGWindowID(window.windowNumber) }) else {
            throw CocoaError(.fileNoSuchFile, userInfo: [NSLocalizedDescriptionKey: "window not listed as shareable"])
        }
        let filter = SCContentFilter(desktopIndependentWindow: target)
        let configuration = SCStreamConfiguration()
        let scale = window.backingScaleFactor
        configuration.width = Int(target.frame.width * scale)
        configuration.height = Int(target.frame.height * scale)
        configuration.showsCursor = false
        configuration.captureResolution = .best
        return try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
    }

    /// Fallback: asks the window's views to draw themselves into a bitmap.
    private static func renderViews(of window: NSWindow) -> CGImage? {
        guard let view = window.contentView?.superview,
              let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds)
        else { return nil }
        view.cacheDisplay(in: view.bounds, to: bitmap)
        return bitmap.cgImage
    }
}

/// Lets debug code open the Settings window, which SwiftUI only opens from inside a view.
@MainActor
enum SettingsOpener {
    static var action: (() -> Void)?
    static var pending = false

    static func request() {
        if let action { action() } else { pending = true }
    }
}
#endif
