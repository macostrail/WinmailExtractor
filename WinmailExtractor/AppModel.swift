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
        panel.title = "winmail.datを選択"
        panel.message = "展開するMicrosoft TNEFファイルを選んでください。"
        panel.prompt = "選択"
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
                addRecord(.init(
                    sourceName: sourceURL.lastPathComponent,
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
            addRecord(.init(
                sourceName: sourceURL.lastPathComponent,
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
        panel.title = "保存先を選択"
        panel.message = "\(attachmentCount)個の添付ファイルを保存するフォルダを選んでください。"
        panel.prompt = "ここに展開"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = sourceURL.deletingLastPathComponent()

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
        alert.messageText = "展開が完了しました"
        alert.informativeText = "\(files.count)個の添付ファイルを「\(destination.lastPathComponent)」に保存しました。"
        if !warnings.isEmpty {
            alert.informativeText += "\n\n注意: \(warnings.joined(separator: "\n"))"
        }
        alert.addButton(withTitle: "Finderで表示")
        alert.addButton(withTitle: "閉じる")

        if alert.runModal() == .alertFirstButtonReturn {
            NSWorkspace.shared.activateFileViewerSelecting(files)
        }
    }

    private func showError(sourceURL: URL, message: String) {
        let alert = NSAlert()
        alert.alertStyle = .critical
        alert.messageText = "\(sourceURL.lastPathComponent)を展開できませんでした"
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
            return "TNEFデータ内に展開可能な添付ファイルが見つかりませんでした。"
        case .downloadsDirectoryUnavailable:
            return "Downloadsフォルダを取得できませんでした。"
        }
    }
}
