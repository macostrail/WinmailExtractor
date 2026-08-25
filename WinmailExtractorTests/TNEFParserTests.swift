import XCTest
@testable import WinmailExtractor

final class TNEFParserTests: XCTestCase {
    func testExtractsAttachmentFromClassicAttributes() throws {
        let payload = Data("quarterly report\n".utf8)
        let data = makeTNEF(attributes: [
            attribute(name: 0x9002, value: Data()),
            attribute(name: 0x8010, value: Data("Report.txt\0".utf8)),
            attribute(name: 0x800F, value: payload),
        ])

        let archive = try TNEFParser.parse(data)

        XCTAssertEqual(archive.attachments.count, 1)
        XCTAssertEqual(archive.attachments[0].fileName, "Report.txt")
        XCTAssertEqual(archive.attachments[0].data, payload)
        XCTAssertTrue(archive.warnings.isEmpty)
    }

    func testReadsLongUnicodeNameAndPayloadFromMAPIProperties() throws {
        let payload = Data([0x25, 0x50, 0x44, 0x46])
        var properties = Data()
        properties.appendLE(UInt32(2))

        properties.appendLE(UInt16(0x001F))
        properties.appendLE(UInt16(0x3707))
        properties.appendLE(UInt32(1))
        properties.appendVariable("請求書.pdf\0".data(using: .utf16LittleEndian)!)

        properties.appendLE(UInt16(0x0102))
        properties.appendLE(UInt16(0x3701))
        properties.appendLE(UInt32(1))
        properties.appendVariable(payload)

        let data = makeTNEF(attributes: [
            attribute(name: 0x9002, value: Data()),
            attribute(name: 0x9005, value: properties),
        ])

        let archive = try TNEFParser.parse(data)

        XCTAssertEqual(archive.attachments.count, 1)
        XCTAssertEqual(archive.attachments[0].fileName, "請求書.pdf")
        XCTAssertEqual(archive.attachments[0].data, payload)
    }

    func testReportsChecksumMismatchButStillExtracts() throws {
        var brokenAttribute = attribute(name: 0x800F, value: Data("hello".utf8))
        brokenAttribute[brokenAttribute.index(before: brokenAttribute.endIndex)] ^= 0xFF
        let data = makeTNEF(attributes: [
            attribute(name: 0x9002, value: Data()),
            attribute(name: 0x8010, value: Data("note.txt\0".utf8)),
            brokenAttribute,
        ])

        let archive = try TNEFParser.parse(data)

        XCTAssertEqual(archive.attachments.count, 1)
        XCTAssertEqual(archive.warnings.count, 1)
    }

    func testDecodesClassicFileNameUsingDeclaredWindowsCodePage() throws {
        var codePage = Data()
        codePage.appendLE(UInt32(932))
        codePage.appendLE(UInt32(0))
        let shiftJISName = "資料.txt\0".data(using: .shiftJIS)!

        let data = makeTNEF(attributes: [
            attribute(level: 0x01, name: 0x9007, value: codePage),
            attribute(name: 0x9002, value: Data()),
            attribute(name: 0x8010, value: shiftJISName),
            attribute(name: 0x800F, value: Data("content".utf8)),
        ])

        let archive = try TNEFParser.parse(data)

        XCTAssertEqual(archive.attachments.first?.fileName, "資料.txt")
    }

    func testRejectsNonTNEFData() {
        XCTAssertThrowsError(try TNEFParser.parse(Data("not tnef".utf8))) { error in
            XCTAssertEqual(error as? TNEFParserError, .invalidSignature)
        }
    }

    func testSanitizesWindowsPaths() {
        XCTAssertEqual(
            AttachmentWriter.safeFileName("C:\\Users\\alice\\..\\secret/report.pdf", fallbackNumber: 1),
            "report.pdf"
        )
        XCTAssertEqual(AttachmentWriter.safeFileName("..", fallbackNumber: 4), "attachment-4.bin")
    }

    @MainActor
    func testAutomaticExtractionConfirmationUsesWrittenFileNames() {
        XCTAssertEqual(
            AppDelegate.automaticExtractionMessage(for: [URL(fileURLWithPath: "/tmp/Report.pdf")]),
            "「Report.pdf」をDownloadsに保存しました"
        )
        XCTAssertEqual(
            AppDelegate.automaticExtractionMessage(for: [
                URL(fileURLWithPath: "/tmp/Report.pdf"),
                URL(fileURLWithPath: "/tmp/Photo.jpg"),
            ]),
            "「Report.pdf」など2個のファイルをDownloadsに保存しました"
        )
    }

    @MainActor
    func testSilentExtractionWritesWithoutReplacingExistingFile() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("WinmailExtractorTests-\(UUID().uuidString)", isDirectory: true)
        let destination = root.appendingPathComponent("Downloads", isDirectory: true)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let originalPayload = Data("existing".utf8)
        let extractedPayload = Data("new attachment".utf8)
        try originalPayload.write(to: destination.appendingPathComponent("Report.txt"))

        let tnefData = makeTNEF(attributes: [
            attribute(name: 0x9002, value: Data()),
            attribute(name: 0x8010, value: Data("Report.txt\0".utf8)),
            attribute(name: 0x800F, value: extractedPayload),
        ])
        let source = root.appendingPathComponent("winmail.dat")
        try tnefData.write(to: source)

        let result = AppModel.shared.extractSilently([source], to: destination)

        XCTAssertTrue(result.failures.isEmpty)
        XCTAssertEqual(result.writtenFiles.map(\.lastPathComponent), ["Report (2).txt"])
        XCTAssertEqual(try Data(contentsOf: destination.appendingPathComponent("Report.txt")), originalPayload)
        XCTAssertEqual(try Data(contentsOf: destination.appendingPathComponent("Report (2).txt")), extractedPayload)
    }

    private func makeTNEF(attributes: [Data]) -> Data {
        var data = Data()
        data.appendLE(UInt32(0x223E9F78))
        data.appendLE(UInt16(0x1234))
        attributes.forEach { data.append($0) }
        return data
    }

    private func attribute(level: UInt8 = 0x02, name: UInt16, value: Data) -> Data {
        var data = Data()
        data.append(level)
        data.appendLE(name)
        data.appendLE(UInt16(0x0006))
        data.appendLE(UInt32(value.count))
        data.append(value)
        let checksum = value.reduce(UInt16(0)) { $0 &+ UInt16($1) }
        data.appendLE(checksum)
        return data
    }
}

private extension Data {
    mutating func appendLE<T: FixedWidthInteger>(_ value: T) {
        var littleEndian = value.littleEndian
        Swift.withUnsafeBytes(of: &littleEndian) { append(contentsOf: $0) }
    }

    mutating func appendVariable(_ value: Data) {
        appendLE(UInt32(value.count))
        append(value)
        while count % 4 != 0 {
            append(0)
        }
    }
}
