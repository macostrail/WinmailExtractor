import AppKit
import Foundation
import UniformTypeIdentifiers

struct ExtractionRecord: Identifiable {
    enum Outcome {
        case success(count: Int, destination: URL)
        case failure(message: String)
        case cancelled
    }

    let id = UUID()
    let sourceName: String
    let date = Date()
    let outcome: Outcome
}

struct AutomaticExtractionFailure {
    let sourceName: String
    let message: String
}

struct AutomaticExtractionResult {
    var writtenFiles: [URL] = []
    var failures: [AutomaticExtractionFailure] = []
}

@MainActor
final class AppModel: ObservableObject {
    static let shared = AppModel()

    @Published private(set) var isProcessing = false
    @Published private(set) var records: [ExtractionRecord] = []

    private var queuedURLs: [URL] = []

    private init() {}

    func chooseFiles() {
        let panel = NSOpenPanel()
        panel.title = String(localized: "panel_title")
        panel.message = String(localized: "panel_msg")
        panel.prompt = String(localized: "panel_promt")
        panel.allowedContentTypes = [UTType(importedAs: "com.microsoft.tnef", conformingTo: .data)]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false

        guard panel.runModal() == .OK else { return }
        open(panel.urls)
    }

    func open(_ urls: [URL]) {
        queuedURLs.append(contentsOf: urls)
        guard !isProcessing else { return }
        processQueue()
    }

    func extractToDownloads(_ urls: [URL]) -> AutomaticExtractionResult {
        guard let downloadsDirectory = FileManager.default.urls(
            for: .downloadsDirectory,
            in: .userDomainMask
        ).first else {
            let message = ExtractionError.downloadsDirectoryUnavailable.localizedDescription
            return AutomaticExtractionResult(
                failures: urls.map {
                    AutomaticExtractionFailure(sourceName: $0.lastPathComponent, message: message)
                }
            )
        }

        return extractSilently(urls, to: downloadsDirectory)
    }

    @discardableResult
    func extractSilently(_ urls: [URL], to destination: URL) -> AutomaticExtractionResult {
        isProcessing = true
        defer { isProcessing = false }

        var result = AutomaticExtractionResult()
        for sourceURL in urls {
            do {
                let archive = try loadArchive(from: sourceURL)
                let writtenURLs = try write(archive, to: destination)
                result.writtenFiles.append(contentsOf: writtenURLs)
                
                var displayName = sourceURL.lastPathComponent
                if let firstFile = writtenURLs.first {
                    if writtenURLs.count > 1 {
                        displayName = "\(firstFile.lastPathComponent) (+ \(writtenURLs.count - 1))"
                    } else {
                        displayName = firstFile.lastPathComponent
                    }
                }
                
                addRecord(.init(
                    sourceName: displayName,
                    outcome: .success(count: writtenURLs.count, destination: destination)
                ))
            } catch {
                let message = errorMessage(for: error)
                result.failures.append(.init(sourceName: sourceURL.lastPathComponent, message: message))
                addRecord(.init(sourceName: sourceURL.lastPathComponent, outcome: .failure(message: message)))
            }
        }
        return result
    }

    private func processQueue() {
        guard !queuedURLs.isEmpty else {
            isProcessing = false
            return
        }

        isProcessing = true
        let sourceURL = queuedURLs.removeFirst()
        extract(sourceURL)
        processQueue()
    }

    private func extract(_ sourceURL: URL) {
        do {
            let archive = try loadArchive(from: sourceURL)

            guard let destination = chooseDestination(for: sourceURL, attachmentCount: archive.attachments.count) else {
                addRecord(.init(sourceName: sourceURL.lastPathComponent, outcome: .cancelled))
                return
            }

            let writtenURLs = try write(archive, to: destination)
 
            var displayName = sourceURL.lastPathComponent
            if let firstFile = writtenURLs.first {
                if writtenURLs.count > 1 {
                    displayName = "\(firstFile.lastPathComponent) (+ \(writtenURLs.count - 1))"
                } else {
                    displayName = firstFile.lastPathComponent
                }
            }
            
            addRecord(.init(
                sourceName: displayName,
                outcome: .success(count: writtenURLs.count, destination: destination)
            ))
            showSuccess(writtenURLs, destination: destination, warnings: archive.warnings)
        } catch {
            let message = errorMessage(for: error)
            addRecord(.init(sourceName: sourceURL.lastPathComponent, outcome: .failure(message: message)))
            showError(sourceURL: sourceURL, message: message)
        }
    }


    private func loadArchive(from sourceURL: URL) throws -> TNEFArchive {
        let didAccess = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if didAccess {
                sourceURL.stopAccessingSecurityScopedResource()
            }
        }

        let archive = try TNEFParser.parse(Data(contentsOf: sourceURL, options: .mappedIfSafe))
        guard !archive.attachments.isEmpty else {
            throw ExtractionError.noAttachments
        }
        return archive
    }

    private func write(_ archive: TNEFArchive, to destination: URL) throws -> [URL] {
        let didAccess = destination.startAccessingSecurityScopedResource()
        defer {
            if didAccess {
                destination.stopAccessingSecurityScopedResource()
            }
        }
        return try AttachmentWriter.write(archive.attachments, to: destination)
    }

    private func errorMessage(for error: Error) -> String {
        (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }

    private func chooseDestination(for sourceURL: URL, attachmentCount: Int) -> URL? {
        let panel = NSOpenPanel()
        panel.title = String(localized: "panel_title_choose_destination")
        panel.message = String(localized: "panel_message_choose_folder \(attachmentCount)")
        panel.prompt = String(localized: "panel_prompt_extract_here")
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = sourceURL.deletingLastPathComponent()
        panel.level = .modalPanel
        panel.makeKeyAndOrderFront(nil)

        return panel.runModal() == .OK ? panel.url : nil
    }


    private func addRecord(_ record: ExtractionRecord) {
        records.insert(record, at: 0)
        if records.count > 12 {
            records.removeLast(records.count - 12)
        }
    }

    private func showSuccess(_ files: [URL], destination: URL, warnings: [String]) {
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = String(localized: "alert_success_title")
        alert.informativeText = String(localized: "alert_success_body \(files.count) \(destination.lastPathComponent)")
        if !warnings.isEmpty {
            alert.informativeText += "\n\n" + String(localized: "alert_warning_prefix") + " \(warnings.joined(separator: "\n"))"
        }
        alert.addButton(withTitle: String(localized: "btn_show_in_finder"))
        alert.addButton(withTitle: String(localized: "btn_close"))

        if alert.runModal() == .alertFirstButtonReturn {
            NSWorkspace.shared.activateFileViewerSelecting(files)
        }
    }

    private func showError(sourceURL: URL, message: String) {
        let alert = NSAlert()
        alert.alertStyle = .critical
        alert.messageText = String(localized: "alert_error_title_failed_filename \(sourceURL.lastPathComponent)")
        alert.informativeText = message
        alert.runModal()
    }

}

enum ExtractionError: LocalizedError {
    case noAttachments
    case downloadsDirectoryUnavailable

    var errorDescription: String? {
        switch self {
        case .noAttachments:
            return String(localized: "error_description_no_attachments")
        case .downloadsDirectoryUnavailable:
            return String(localized: "error_description_downloads_unavailable")
        }
    }
}

