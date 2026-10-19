import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var mainWindow: NSWindow?
    private var didFinishLaunching = false
    private var receivedFilesDuringLaunch = false
    private var pendingFileURLs: [URL] = []
    private var pendingOpenRequiresReply = false

    func applicationWillFinishLaunching(_ notification: Notification) {
        // Avoid showing a Dock icon while a double-clicked .dat file is handled.
        NSApp.setActivationPolicy(.accessory)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        didFinishLaunching = true
        if receivedFilesDuringLaunch {
            let urls = pendingFileURLs
            let requiresReply = pendingOpenRequiresReply
            pendingFileURLs.removeAll()
            pendingOpenRequiresReply = false
            processOpenedFiles(urls, sender: NSApp, requiresReply: requiresReply)
        } else {
            showMainWindow()
        }
    }

    func applicationShouldOpenUntitledFile(_ sender: NSApplication) -> Bool {
        true
    }

    func applicationOpenUntitledFile(_ sender: NSApplication) -> Bool {
        showMainWindow()
        return true
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        handleOpenedFiles(urls, sender: application, requiresReply: false)
    }

    func application(_ sender: NSApplication, openFiles filenames: [String]) {
        handleOpenedFiles(
            filenames.map { URL(fileURLWithPath: $0) },
            sender: sender,
            requiresReply: true
        )
    }

    private func handleOpenedFiles(
        _ urls: [URL],
        sender: NSApplication,
        requiresReply: Bool
    ) {
        if !didFinishLaunching {
            receivedFilesDuringLaunch = true
            pendingFileURLs.append(contentsOf: urls)
            pendingOpenRequiresReply = pendingOpenRequiresReply || requiresReply
            return
        }

        processOpenedFiles(urls, sender: sender, requiresReply: requiresReply)
    }

    private func processOpenedFiles(
        _ urls: [URL],
        sender: NSApplication,
        requiresReply: Bool
    ) {
   
        let result = AppModel.shared.extractToDownloads(urls)

        if requiresReply {
            sender.reply(toOpenOrPrint: result.failures.isEmpty ? .success : .failure)
        }
        
        if !result.failures.isEmpty {
            showAutomaticExtractionErrors(result.failures)
        }

        DispatchQueue.main.async {
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            NSApp.windows.first?.makeKeyAndOrderFront(nil)
        }
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    private func showMainWindow() {
        NSApp.setActivationPolicy(.regular)

        if let mainWindow {
            mainWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let rootView = ContentView()
            .environmentObject(AppModel.shared)
            .frame(width: 680, height: 620)

        let hostingController = NSHostingController(rootView: rootView)
        
        let window = NSWindow(
            contentViewController: hostingController
        )
        
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        window.title = "Winmail Extractor"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        
        window.setFrameAutosaveName("WinmailExtractorMainWindow_V2")
        window.center()

        mainWindow = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }



    private func showAutomaticExtractionErrors(_ failures: [AutomaticExtractionFailure]) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)

        let alert = NSAlert()
        alert.alertStyle = .critical
        alert.messageText = String(localized: "alert_error_title_failed_extraction")
        alert.informativeText = failures
            .map { "\($0.sourceName): \($0.message)" }
            .joined(separator: "\n")
        alert.runModal()
    }


    static func automaticExtractionMessage(for files: [URL]) -> String {
        guard let firstFile = files.first else {
            return String(localized: "msg_extracted_zero")
        }

        if files.count == 1 {
            return String(localized: "msg_extracted_one \(firstFile.lastPathComponent)")
        }

        let remainingCount = files.count - 1
        return String(localized: "msg_extracted_multiple \(firstFile.lastPathComponent) \(remainingCount)")
    }
}
