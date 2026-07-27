import SwiftUI

@main
struct YouTubeInsightApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            ContentView(model: model)
                .frame(minWidth: 980, minHeight: 680)
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
            SettingsView()
        }
    }
}

extension Notification.Name {
    static let focusURLField = Notification.Name("YouTubeInsight.focusURLField")
}
