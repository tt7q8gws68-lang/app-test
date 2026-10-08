import Compression
import Foundation

/// Minimal read-only ZIP reader, enough to pull `word/document.xml` out of a .docx.
/// Supports stored and deflated entries (the only methods Word uses); no ZIP64 or encryption.
nonisolated struct ZipArchive {
    enum ZipError: Error, Equatable {
        case notAZipFile
        case corrupt
        case unsupportedCompression(UInt16)
        case entryNotFound(String)
    }

    private struct Entry {
        let method: UInt16
        let compressedSize: Int
        let uncompressedSize: Int
        let localHeaderOffset: Int
    }

    /// Largest entry this reader will unpack. The declared size comes from the file itself,
    /// so a tiny damaged or hostile archive could otherwise claim gigabytes.
    static let maxEntrySize = 50_000_000

    private let data: Data
    private let entries: [String: Entry]

    init(data: Data) throws {
        self.data = data
        self.entries = try Self.readCentralDirectory(data)
    }

    var entryNames: [String] { Array(entries.keys) }

    func contents(of name: String) throws -> Data {
        guard let entry = entries[name] else { throw ZipError.entryNotFound(name) }
        guard entry.uncompressedSize <= Self.maxEntrySize else { throw ZipError.corrupt }
        let local = entry.localHeaderOffset
        guard data.uint32(at: local) == 0x0403_4B50,
              let nameLength = data.uint16(at: local + 26),
              let extraLength = data.uint16(at: local + 28)
        else { throw ZipError.corrupt }

        let start = local + 30 + Int(nameLength) + Int(extraLength)
        guard start + entry.compressedSize <= data.count else { throw ZipError.corrupt }
        let compressed = data.subdata(in: start..<(start + entry.compressedSize))

        switch entry.method {
        case 0:
            return compressed
        case 8:
            return try Self.inflate(compressed, expectedSize: entry.uncompressedSize)
        default:
            throw ZipError.unsupportedCompression(entry.method)
        }
    }

    private static func readCentralDirectory(_ data: Data) throws -> [String: Entry] {
        // The end-of-central-directory record sits in the last 22 bytes plus an optional comment.
        let minimum = 22
        guard data.count >= minimum else { throw ZipError.notAZipFile }
        let searchStart = max(0, data.count - minimum - 0xFFFF)
        var eocd: Int?
        var index = data.count - minimum
        while index >= searchStart {
            if data.uint32(at: index) == 0x0605_4B50 { eocd = index; break }
            index -= 1
        }
        guard let eocd,
              let count = data.uint16(at: eocd + 10),
              let directoryOffset = data.uint32(at: eocd + 16)
        else { throw ZipError.notAZipFile }

        var entries: [String: Entry] = [:]
        var cursor = Int(directoryOffset)
        for _ in 0..<count {
            guard data.uint32(at: cursor) == 0x0201_4B50,
                  let method = data.uint16(at: cursor + 10),
                  let compressedSize = data.uint32(at: cursor + 20),
                  let uncompressedSize = data.uint32(at: cursor + 24),
                  let nameLength = data.uint16(at: cursor + 28),
                  let extraLength = data.uint16(at: cursor + 30),
                  let commentLength = data.uint16(at: cursor + 32),
                  let localOffset = data.uint32(at: cursor + 42),
                  cursor + 46 + Int(nameLength) <= data.count
            else { throw ZipError.corrupt }

            let nameData = data.subdata(in: (cursor + 46)..<(cursor + 46 + Int(nameLength)))
            if let name = String(data: nameData, encoding: .utf8) {
                entries[name] = Entry(
                    method: method,
                    compressedSize: Int(compressedSize),
                    uncompressedSize: Int(uncompressedSize),
                    localHeaderOffset: Int(localOffset)
                )
            }
            cursor += 46 + Int(nameLength) + Int(extraLength) + Int(commentLength)
        }
        return entries
    }

    private static func inflate(_ compressed: Data, expectedSize: Int) throws -> Data {
        guard expectedSize > 0 else { return Data() }
        // A damaged entry can claim content but carry no compressed bytes.
        guard !compressed.isEmpty else { throw ZipError.corrupt }
        var output = Data(count: expectedSize)
        let written = output.withUnsafeMutableBytes { destination in
            compressed.withUnsafeBytes { source in
                // COMPRESSION_ZLIB is raw DEFLATE, which is what ZIP stores.
                compression_decode_buffer(
                    destination.bindMemory(to: UInt8.self).baseAddress!, expectedSize,
                    source.bindMemory(to: UInt8.self).baseAddress!, compressed.count,
                    nil, COMPRESSION_ZLIB
                )
            }
        }
        guard written == expectedSize else { throw ZipError.corrupt }
        return output
    }
}

private extension Data {
    nonisolated func uint16(at offset: Int) -> UInt16? {
        guard offset >= 0, offset + 2 <= count else { return nil }
        return UInt16(self[startIndex + offset]) | UInt16(self[startIndex + offset + 1]) << 8
    }

    nonisolated func uint32(at offset: Int) -> UInt32? {
        guard offset >= 0, offset + 4 <= count else { return nil }
        return (0..<4).reduce(UInt32(0)) { $0 | UInt32(self[startIndex + offset + $1]) << (8 * $1) }
    }
}
