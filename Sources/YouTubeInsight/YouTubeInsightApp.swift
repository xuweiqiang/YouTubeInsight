import AppKit
import SwiftUI

@main
struct YouTubeInsightApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            ContentView(model: model)
                .frame(minWidth: 980, minHeight: 680)
                .background(WindowMaximizer())
        }
        .windowStyle(.titleBar)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button(L10n.string("action.focusURL", fallback: "Focus URL field")) {
                    NotificationCenter.default.post(name: .focusURLField, object: nil)
                }
                .keyboardShortcut("l", modifiers: [.command])
            }
        }

        Settings {
            SettingsView(model: model)
        }
    }
}

private struct WindowMaximizer: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        MaximizingView()
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

private final class MaximizingView: NSView {
    private var didMaximize = false

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard !didMaximize, let window else {
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self, weak window] in
            guard let self, !didMaximize, let window else {
                return
            }
            didMaximize = true
            guard let screen = window.screen ?? NSScreen.main else {
                return
            }
            window.setFrame(screen.visibleFrame, display: true, animate: false)
        }
    }
}

extension Notification.Name {
    static let focusURLField = Notification.Name("YouTubeInsight.focusURLField")
}
