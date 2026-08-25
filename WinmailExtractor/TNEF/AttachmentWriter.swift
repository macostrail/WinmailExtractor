import Foundation

enum AttachmentWriter {
    static func write(_ attachments: [TNEFAttachment], to directory: URL) throws -> [URL] {
        let fileManager = FileManager.default
        var reservedNames = Set(
            (try? fileManager.contentsOfDirectory(atPath: directory.path))?
                .map { $0.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current) }
                ?? []
        )
        var outputURLs: [URL] = []

        for (index, attachment) in attachments.enumerated() {
            let baseName = safeFileName(attachment.fileName, fallbackNumber: index + 1)
            let uniqueName = availableName(baseName, reservedNames: &reservedNames)
            let outputURL = directory.appendingPathComponent(uniqueName, isDirectory: false)
            try attachment.data.write(to: outputURL, options: [.atomic])
            outputURLs.append(outputURL)
        }

        return outputURLs
    }

    static func safeFileName(_ proposedName: String, fallbackNumber: Int) -> String {
        let windowsPathNormalized = proposedName.replacingOccurrences(of: "\\", with: "/")
        let lastComponent = windowsPathNormalized.split(separator: "/", omittingEmptySubsequences: true).last.map(String.init) ?? ""
        let forbidden = CharacterSet(charactersIn: "/:\0").union(.controlCharacters)
        let cleanedScalars = lastComponent.unicodeScalars.map { scalar -> Character in
            forbidden.contains(scalar) ? "_" : Character(String(scalar))
        }
        var result = String(cleanedScalars).trimmingCharacters(in: .whitespacesAndNewlines)

        if result == "." || result == ".." || result.isEmpty {
            result = "attachment-\(fallbackNumber).bin"
        }

        while result.utf8.count > 240, !result.isEmpty {
            result.remove(at: result.index(before: result.endIndex))
        }
        return result.isEmpty ? "attachment-\(fallbackNumber).bin" : result
    }

    private static func availableName(_ fileName: String, reservedNames: inout Set<String>) -> String {
        let nsName = fileName as NSString
        let fileExtension = nsName.pathExtension
        let stem = nsName.deletingPathExtension
        var candidate = fileName
        var counter = 2

        while reservedNames.contains(fold(candidate)) {
            candidate = fileExtension.isEmpty
                ? "\(stem) (\(counter))"
                : "\(stem) (\(counter)).\(fileExtension)"
            counter += 1
        }

        reservedNames.insert(fold(candidate))
        return candidate
    }

    private static func fold(_ name: String) -> String {
        name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
    }
}

