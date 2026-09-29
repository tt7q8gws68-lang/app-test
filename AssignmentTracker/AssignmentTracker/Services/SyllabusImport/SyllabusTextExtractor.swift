import CoreGraphics
import CryptoKit
import Foundation
import ImageIO
import PDFKit
import UIKit
import UniformTypeIdentifiers
import Vision

nonisolated enum SyllabusImportError: LocalizedError, Equatable {
    case unsupportedType(String)
    case fileTooLarge(bytes: Int64)
    case emptyFile
    case unreadable(String)
    case passwordProtected
    case noTextFound

    var errorDescription: String? {
        switch self {
        case .unsupportedType(let name):
            "“\(name)” isn’t a supported file type."
        case .fileTooLarge(let bytes):
            "This file is \(ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)). Syllabus files must be \(ByteCountFormatter.string(fromByteCount: SyllabusTextExtractor.maxFileSize, countStyle: .file)) or smaller."
        case .emptyFile:
            "This file is empty."
        case .unreadable(let detail):
            "The file couldn’t be read. \(detail)"
        case .passwordProtected:
            "This PDF is password-protected."
        case .noTextFound:
            "No readable text was found in this syllabus."
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .unsupportedType:
            "Use a PDF, Word (.docx), plain-text or RTF file, or a photo of the syllabus."
        case .fileTooLarge:
            "Try exporting just the syllabus pages, or take photos of them instead."
        case .emptyFile, .unreadable:
            "Try downloading the syllabus again, or export it as a PDF."
        case .passwordProtected:
            "Remove the password in another app and import it again."
        case .noTextFound:
            "If it’s a scan or photo, try a sharper, well-lit, straight-on image."
        }
    }
}

/// The text of a syllabus plus details the review screen uses.
nonisolated struct ExtractedSyllabus: Sendable {
    var text: String
    var sourceName: String
    /// SHA-256 of the original file or images, used to spot repeat imports.
    var fingerprint: String
    var pageCount: Int
    /// Pages (or images) that were read with on-device text recognition.
    var recognizedPageCount: Int
}

/// Pulls text out of syllabus files: PDFKit for PDFs (falling back to Vision OCR for pages
/// with no text layer), Vision for images, a small ZIP/XML reader for .docx, and Foundation
/// for plain text and RTF.
nonisolated struct SyllabusTextExtractor {
    static let maxFileSize: Int64 = 20 * 1024 * 1024
    static let docxType = UTType("org.openxmlformats.wordprocessingml.document") ?? .data
    static let supportedTypes: [UTType] = [.pdf, docxType, .plainText, .rtf, .image]

    /// Below this many characters a PDF page is treated as scanned and sent to OCR.
    private static let minimumPageText = 25

    func extract(from url: URL) async throws -> ExtractedSyllabus {
        let isScoped = url.startAccessingSecurityScopedResource()
        defer { if isScoped { url.stopAccessingSecurityScopedResource() } }

        let values = try? url.resourceValues(forKeys: [.contentTypeKey, .fileSizeKey])
        let type = values?.contentType ?? UTType(filenameExtension: url.pathExtension) ?? .data
        let name = url.lastPathComponent

        guard Self.supportedTypes.contains(where: { type.conforms(to: $0) }) else {
            throw SyllabusImportError.unsupportedType(name)
        }
        if let size = values?.fileSize, Int64(size) > Self.maxFileSize {
            throw SyllabusImportError.fileTooLarge(bytes: Int64(size))
        }

        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw SyllabusImportError.unreadable(error.localizedDescription)
        }
        return try await extract(data: data, type: type, name: name)
    }

    func extract(data: Data, type: UTType, name: String) async throws -> ExtractedSyllabus {
        guard !data.isEmpty else { throw SyllabusImportError.emptyFile }
        guard Int64(data.count) <= Self.maxFileSize else {
            throw SyllabusImportError.fileTooLarge(bytes: Int64(data.count))
        }
        let fingerprint = Self.fingerprint(of: [data])

        var result: ExtractedSyllabus
        if type.conforms(to: .pdf) {
            result = try await extractPDF(data, name: name)
        } else if type.conforms(to: Self.docxType) {
            do {
                result = ExtractedSyllabus(text: try DocxTextReader.text(from: data), sourceName: name, fingerprint: "", pageCount: 1, recognizedPageCount: 0)
            } catch {
                throw SyllabusImportError.unreadable("It doesn’t look like a valid Word document.")
            }
        } else if type.conforms(to: .rtf) {
            guard let string = try? NSAttributedString(data: data, options: [.documentType: NSAttributedString.DocumentType.rtf], documentAttributes: nil).string
            else { throw SyllabusImportError.unreadable("The RTF file is damaged.") }
            result = ExtractedSyllabus(text: string, sourceName: name, fingerprint: "", pageCount: 1, recognizedPageCount: 0)
        } else if type.conforms(to: .plainText) {
            let string = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) ?? ""
            result = ExtractedSyllabus(text: string, sourceName: name, fingerprint: "", pageCount: 1, recognizedPageCount: 0)
        } else if type.conforms(to: .image) {
            guard let image = Self.cgImage(from: data) else { throw SyllabusImportError.unreadable("The image is damaged.") }
            result = try await extract(images: [image], name: name)
        } else {
            throw SyllabusImportError.unsupportedType(name)
        }

        result.fingerprint = fingerprint
        guard result.text.trimmingCharacters(in: .whitespacesAndNewlines).count >= 40 else {
            throw SyllabusImportError.noTextFound
        }
        return result
    }

    /// Photos and document-camera scans.
    func extract(images: [CGImage], name: String) async throws -> ExtractedSyllabus {
        var pages: [String] = []
        for image in images {
            pages.append(try await recognizeText(in: image))
        }
        let text = pages.joined(separator: "\n\n")
        guard text.trimmingCharacters(in: .whitespacesAndNewlines).count >= 40 else {
            throw SyllabusImportError.noTextFound
        }
        let pngData = images.compactMap(Self.pngData)
        return ExtractedSyllabus(
            text: text, sourceName: name, fingerprint: Self.fingerprint(of: pngData),
            pageCount: images.count, recognizedPageCount: images.count
        )
    }

    // MARK: - PDF

    private func extractPDF(_ data: Data, name: String) async throws -> ExtractedSyllabus {
        guard let document = PDFDocument(data: data) else {
            throw SyllabusImportError.unreadable("It may be damaged or not really a PDF.")
        }
        if document.isLocked { throw SyllabusImportError.passwordProtected }

        var pages: [String] = []
        var recognized = 0
        for index in 0..<document.pageCount {
            guard let page = document.page(at: index) else { continue }
            let text = page.string ?? ""
            if text.trimmingCharacters(in: .whitespacesAndNewlines).count >= Self.minimumPageText {
                pages.append(text)
            } else if let image = Self.render(page) {
                pages.append(try await recognizeText(in: image))
                recognized += 1
            }
        }
        return ExtractedSyllabus(
            text: pages.joined(separator: "\n\n"), sourceName: name, fingerprint: "",
            pageCount: document.pageCount, recognizedPageCount: recognized
        )
    }

    /// Renders a PDF page at 2× on white, for OCR.
    private static func render(_ page: PDFPage) -> CGImage? {
        let bounds = page.bounds(for: .mediaBox)
        let scale: CGFloat = 2
        let width = Int(bounds.width * scale), height = Int(bounds.height * scale)
        guard width > 0, height > 0,
              let context = CGContext(
                data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
              )
        else { return nil }
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.scaleBy(x: scale, y: scale)
        context.translateBy(x: -bounds.minX, y: -bounds.minY)
        page.draw(with: .mediaBox, to: context)
        return context.makeImage()
    }

    // MARK: - OCR

    /// On-device text recognition. Lines that sit side by side (table columns) are joined
    /// with " | " so each schedule row stays on one line.
    private func recognizeText(in image: CGImage) async throws -> String {
        var request = RecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        let observations = try await request.perform(on: image)

        struct Line { var midY: Double; var height: Double; var x: Double; var text: String }
        let lines: [Line] = observations.compactMap { observation in
            guard let text = observation.topCandidates(1).first?.string else { return nil }
            let box = observation.boundingBox
            return Line(midY: box.origin.y + box.height / 2, height: box.height, x: box.origin.x, text: text)
        }
        // Vision's origin is bottom-left: read top to bottom, grouping lines on the same row.
        var rows: [[Line]] = []
        for line in lines.sorted(by: { $0.midY > $1.midY }) {
            if let last = rows.last?.first, abs(last.midY - line.midY) < max(last.height, line.height) * 0.5 {
                rows[rows.count - 1].append(line)
            } else {
                rows.append([line])
            }
        }
        return rows
            .map { $0.sorted { $0.x < $1.x }.map(\.text).joined(separator: " | ") }
            .joined(separator: "\n")
    }

    // MARK: - Helpers

    static func cgImage(from data: Data) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        // Apply EXIF orientation so photos taken sideways read correctly.
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 4000,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    private static func pngData(_ image: CGImage) -> Data? {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image, nil)
        return CGImageDestinationFinalize(destination) ? data as Data : nil
    }

    static func fingerprint(of parts: [Data]) -> String {
        var hasher = SHA256()
        parts.forEach { hasher.update(data: $0) }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
