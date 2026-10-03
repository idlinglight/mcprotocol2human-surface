import AppKit
import os
import SwiftUI

@main
struct SurfaceApp: App {
    @State private var model: AppModel

    init() {
        let model = AppModel(store: ServerStore())
        _model = State(initialValue: model)
        let build = BuildInfo.current
        Log.app.notice("Launch: version \(build.version, privacy: .public) (\(build.build, privacy: .public)). \(build.summary, privacy: .public)")
        NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { model.store.flush() }
        }
        #if DEBUG
        DebugAids.apply(to: model)
        #endif
    }

    var body: some Scene {
        Window("mcprotocol2human-surface", id: "main") {
            MainWindow(model: model)
        }
        .defaultSize(width: 1180, height: 760)
        .commands {
            SidebarCommands()
            CommandGroup(replacing: .appInfo) {
                Button("About mcprotocol2human-surface") {
                    NSApp.orderFrontStandardAboutPanel(options: [
                        .credits: NSAttributedString(string: BuildInfo.current.summary),
                    ])
                }
            }
            CommandMenu("Server") {
                Button("Refresh") { model.refreshSelected() }
                    .keyboardShortcut("r")
                    .disabled(model.selectedServer == nil)
                Button("Refresh All") { model.refreshAll() }
                    .keyboardShortcut("r", modifiers: [.command, .shift])
            }
        }

        Settings {
            SettingsView(model: model)
        }
    }
}
