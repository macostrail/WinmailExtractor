import SwiftUI

@main
struct WinmailExtractorApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // The main window is created by AppDelegate only for a normal app launch.
        // A document launch therefore remains completely headless.
        Settings {
            EmptyView()
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("winmail.datを開く…") {
                    AppModel.shared.chooseFiles()
                }
                .keyboardShortcut("o")
            }
        }
    }
}
