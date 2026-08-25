import Foundation
import CoreFoundation

struct TNEFArchive {
    let attachments: [TNEFAttachment]
    let warnings: [String]
}

struct TNEFAttachment {
    let fileName: String
    let data: Data
    let mimeType: String?
}

enum TNEFParserError: LocalizedError, Equatable {
    case fileTooShort
    case invalidSignature
    case truncatedData(offset: Int)
    case unreasonableAttributeSize(Int)
    case invalidMAPIData

    var errorDescription: String? {
        switch self {
        case .fileTooShort:
            return "ファイルが短すぎるため、winmail.datとして認識できません。"
        case .invalidSignature:
            return "Microsoft TNEF形式ではありません。通常の.datファイルの可能性があります。"
        case let .truncatedData(offset):
            return "TNEFデータが途中で切れています（位置: \(offset)）。"
        case let .unreasonableAttributeSize(size):
            return "不正なサイズのTNEF属性が含まれています（\(size)バイト）。"
        case .invalidMAPIData:
            return "添付ファイル情報（MAPI）が壊れています。"
        }
    }
}

enum TNEFParser {
    private static let signature: UInt32 = 0x223E9F78
    private static let messageLevel: UInt8 = 0x01
    private static let attachmentLevel: UInt8 = 0x02
    private static let oemCodePageAttribute: UInt16 = 0x9007

    private enum Attribute: UInt16 {
        case attachData = 0x800F
        case attachTitle = 0x8010
        case attachTransportFilename = 0x9001
        case attachRendData = 0x9002
        case attachAttachment = 0x9005
    }

    static func parse(_ data: Data) throws -> TNEFArchive {
        guard data.count >= 6 else { throw TNEFParserError.fileTooShort }

        var cursor = ByteCursor(data)
        guard try cursor.readUInt32() == signature else {
            throw TNEFParserError.invalidSignature
        }
        _ = try cursor.readUInt16() // Legacy key; not needed for extraction.

        var builders: [AttachmentBuilder] = []
        var current: AttachmentBuilder?
        var warnings: [String] = []
        var attachmentNumber = 1
        var string8Encoding = String.Encoding.windowsCP1252

        while cursor.remaining > 0 {
            let attributeOffset = cursor.offset
            let level = try cursor.readUInt8()
            let rawName = try cursor.readUInt16()
            _ = try cursor.readUInt16() // Attribute type.
            let lengthValue = try cursor.readUInt32()

            guard lengthValue <= 1_073_741_824 else {
                throw TNEFParserError.unreasonableAttributeSize(Int(lengthValue))
            }
            let value = try cursor.readData(count: Int(lengthValue))
            let storedChecksum = try cursor.readUInt16()
            let calculatedChecksum = value.reduce(UInt16(0)) { partial, byte in
                partial &+ UInt16(byte)
            }
            if storedChecksum != calculatedChecksum {
                warnings.append("位置\(attributeOffset)のチェックサムが一致しません。可能な範囲で展開しました。")
            }

            if level == messageLevel, rawName == oemCodePageAttribute,
               let codePage = readCodePage(from: value),
               let encoding = encoding(forWindowsCodePage: codePage) {
                string8Encoding = encoding
            }

            guard level == attachmentLevel, let attribute = Attribute(rawValue: rawName) else {
                continue
            }

            if attribute == .attachRendData {
                if let existing = current, existing.hasContent {
                    builders.append(existing)
                    attachmentNumber += 1
                }
                current = AttachmentBuilder(number: attachmentNumber)
                continue
            }

            if current == nil {
                current = AttachmentBuilder(number: attachmentNumber)
            }

            switch attribute {
            case .attachTitle:
                current?.attributeFileName = decodeString8(value, encoding: string8Encoding)
            case .attachTransportFilename:
                current?.transportFileName = decodeString8(value, encoding: string8Encoding)
            case .attachData:
                current?.payload = value
            case .attachAttachment:
                if let properties = try? MAPIPropertyParser.parse(value, string8Encoding: string8Encoding) {
                    current?.apply(properties)
                } else {
                    warnings.append("添付ファイル\(attachmentNumber)の詳細なMAPI情報を一部読み取れませんでした。")
                }
            case .attachRendData:
                break
            }
        }

        if let current, current.hasContent {
            builders.append(current)
        }

        let attachments = builders.compactMap { $0.attachment }
        return TNEFArchive(attachments: attachments, warnings: warnings)
    }

    fileprivate static func decodeString8(_ data: Data, encoding: String.Encoding) -> String? {
        let trimmed = Data(data.prefix { $0 != 0 })
        guard !trimmed.isEmpty else { return nil }

        return String(data: trimmed, encoding: encoding)
            ?? String(data: trimmed, encoding: .utf8)
            ?? String(data: trimmed, encoding: .windowsCP1252)
            ?? String(data: trimmed, encoding: .isoLatin1)
    }

    private static func readCodePage(from data: Data) -> UInt32? {
        guard data.count >= 4 else { return nil }
        var cursor = ByteCursor(data)
        return try? cursor.readUInt32()
    }

    private static func encoding(forWindowsCodePage codePage: UInt32) -> String.Encoding? {
        let coreFoundationEncoding = CFStringConvertWindowsCodepageToEncoding(codePage)
        guard coreFoundationEncoding != kCFStringEncodingInvalidId else { return nil }
        let cocoaEncoding = CFStringConvertEncodingToNSStringEncoding(coreFoundationEncoding)
        return String.Encoding(rawValue: cocoaEncoding)
    }
}

private struct AttachmentBuilder {
    let number: Int
    var attributeFileName: String?
    var transportFileName: String?
    var mapiFileName: String?
    var payload: Data?
    var mimeType: String?

    var hasContent: Bool {
        payload != nil || attributeFileName != nil || transportFileName != nil || mapiFileName != nil
    }

    var attachment: TNEFAttachment? {
        guard let payload else { return nil }
        let proposedName = mapiFileName ?? transportFileName ?? attributeFileName ?? "attachment-\(number).bin"
        return TNEFAttachment(
            fileName: AttachmentWriter.safeFileName(proposedName, fallbackNumber: number),
            data: payload,
            mimeType: mimeType
        )
    }

    mutating func apply(_ properties: MAPIProperties) {
        if let fileName = properties.fileName, !fileName.isEmpty {
            mapiFileName = fileName
        }
        if let attachmentData = properties.attachmentData {
            payload = attachmentData
        }
        if let type = properties.mimeType, !type.isEmpty {
            mimeType = type
        }
    }
}

private struct ByteCursor {
    private let data: Data
    private(set) var offset = 0

    init(_ data: Data) {
        self.data = data
    }

    var remaining: Int { data.count - offset }

    mutating func readUInt8() throws -> UInt8 {
        try require(1)
        defer { offset += 1 }
        return data[data.startIndex + offset]
    }

    mutating func readUInt16() throws -> UInt16 {
        try require(2)
        defer { offset += 2 }
        let index = data.startIndex + offset
        return UInt16(data[index]) | (UInt16(data[index + 1]) << 8)
    }

    mutating func readUInt32() throws -> UInt32 {
        try require(4)
        defer { offset += 4 }
        let index = data.startIndex + offset
        return UInt32(data[index])
            | (UInt32(data[index + 1]) << 8)
            | (UInt32(data[index + 2]) << 16)
            | (UInt32(data[index + 3]) << 24)
    }

    mutating func readData(count: Int) throws -> Data {
        guard count >= 0 else { throw TNEFParserError.truncatedData(offset: offset) }
        try require(count)
        defer { offset += count }
        let start = data.startIndex + offset
        return data.subdata(in: start..<(start + count))
    }

    mutating func skip(_ count: Int) throws {
        guard count >= 0 else { throw TNEFParserError.truncatedData(offset: offset) }
        try require(count)
        offset += count
    }

    mutating func alignToFourBytes() throws {
        let padding = (4 - (offset % 4)) % 4
        try skip(padding)
    }

    private func require(_ byteCount: Int) throws {
        guard byteCount <= remaining else {
            throw TNEFParserError.truncatedData(offset: offset)
        }
    }
}

private struct MAPIProperties {
    var fileName: String?
    var attachmentData: Data?
    var mimeType: String?
}

private enum MAPIPropertyParser {
    private static let multiValueFlag: UInt16 = 0x1000
    private static let typeMask: UInt16 = 0x0FFF

    private static let displayName: UInt16 = 0x3001
    private static let attachData: UInt16 = 0x3701
    private static let attachFileName: UInt16 = 0x3704
    private static let attachLongFileName: UInt16 = 0x3707
    private static let attachMimeTag: UInt16 = 0x370E

    static func parse(_ data: Data, string8Encoding: String.Encoding) throws -> MAPIProperties {
        var cursor = ByteCursor(data)
        let propertyCount = try cursor.readUInt32()
        guard propertyCount <= 10_000 else { throw TNEFParserError.invalidMAPIData }

        var result = MAPIProperties()
        var fileNamePriority = 0

        for _ in 0..<propertyCount {
            let rawType = try cursor.readUInt16()
            let propertyID = try cursor.readUInt16()

            if propertyID >= 0x8000 {
                try skipNamedPropertyIdentifier(cursor: &cursor)
            }

            let baseType = rawType & typeMask
            let hasEncodedCount = (rawType & multiValueFlag) != 0 || isVariableLength(baseType)
            let valueCount = hasEncodedCount ? try cursor.readUInt32() : 1
            guard valueCount <= 100_000 else { throw TNEFParserError.invalidMAPIData }

            for valueIndex in 0..<valueCount {
                let value = try readValue(type: baseType, cursor: &cursor, string8Encoding: string8Encoding)
                guard valueIndex == 0 else { continue }

                switch propertyID {
                case attachLongFileName:
                    if let string = value.stringValue, !string.isEmpty, fileNamePriority < 3 {
                        result.fileName = string
                        fileNamePriority = 3
                    }
                case attachFileName:
                    if let string = value.stringValue, !string.isEmpty, fileNamePriority < 2 {
                        result.fileName = string
                        fileNamePriority = 2
                    }
                case displayName:
                    if let string = value.stringValue, !string.isEmpty, fileNamePriority < 1 {
                        result.fileName = string
                        fileNamePriority = 1
                    }
                case attachData:
                    if case let .binary(bytes) = value {
                        result.attachmentData = bytes
                    }
                case attachMimeTag:
                    result.mimeType = value.stringValue
                default:
                    break
                }
            }
        }

        return result
    }

    private static func skipNamedPropertyIdentifier(cursor: inout ByteCursor) throws {
        try cursor.skip(16) // Property set GUID.
        let kind = try cursor.readUInt32()
        switch kind {
        case 0:
            try cursor.skip(4) // Numeric LID.
        case 1:
            let byteCount = try cursor.readUInt32()
            try cursor.skip(Int(byteCount))
            try cursor.alignToFourBytes()
        default:
            throw TNEFParserError.invalidMAPIData
        }
    }

    private enum Value {
        case binary(Data)
        case string(String)
        case ignored

        var stringValue: String? {
            if case let .string(value) = self { return value }
            return nil
        }
    }

    private static func isVariableLength(_ type: UInt16) -> Bool {
        type == 0x000D || type == 0x001E || type == 0x001F || type == 0x0102
    }

    private static func readValue(
        type: UInt16,
        cursor: inout ByteCursor,
        string8Encoding: String.Encoding
    ) throws -> Value {
        switch type {
        case 0x0000, 0x0001: // Unspecified, null.
            return .ignored
        case 0x0002, 0x000B: // 16-bit integer, Boolean.
            try cursor.skip(2)
            try cursor.alignToFourBytes()
            return .ignored
        case 0x0003, 0x0004, 0x000A: // 32-bit integer, float, error.
            try cursor.skip(4)
            return .ignored
        case 0x0005, 0x0006, 0x0007, 0x0014, 0x0040: // 64-bit scalar and FILETIME.
            try cursor.skip(8)
            return .ignored
        case 0x0048: // GUID.
            try cursor.skip(16)
            return .ignored
        case 0x000D: // Embedded object.
            _ = try readVariableBytes(cursor: &cursor)
            return .ignored
        case 0x001E: // PtypString8.
            return .string(try readVariableData(cursor: &cursor, encoding: string8Encoding))
        case 0x001F: // PtypString (UTF-16LE).
            return .string(try readVariableData(cursor: &cursor, encoding: .utf16LittleEndian))
        case 0x0102: // PtypBinary.
            return .binary(try readVariableBytes(cursor: &cursor))
        default:
            throw TNEFParserError.invalidMAPIData
        }
    }

    private static func readVariableBytes(cursor: inout ByteCursor) throws -> Data {
        let byteCount = try cursor.readUInt32()
        guard byteCount <= 1_073_741_824 else {
            throw TNEFParserError.invalidMAPIData
        }
        let bytes = try cursor.readData(count: Int(byteCount))
        try cursor.alignToFourBytes()
        return bytes
    }

    private static func readVariableData(cursor: inout ByteCursor, encoding: String.Encoding) throws -> String {
        let bytes = try readVariableBytes(cursor: &cursor)
        let string = String(data: bytes, encoding: encoding)
            ?? String(data: bytes, encoding: .windowsCP1252)
            ?? String(data: bytes, encoding: .isoLatin1)
            ?? ""
        return string.trimmingCharacters(in: CharacterSet(charactersIn: "\0"))
    }
}
