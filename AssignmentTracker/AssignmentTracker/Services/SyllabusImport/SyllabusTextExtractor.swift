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
    static let maxFileSize: Int64 = 20_000_000
    static let docxType = UTType("org.openxmlformats.wordprocessingml.document") ?? .data
    static let supportedTypes: [UTType] = [.pdf, docxType, .plainText, .rtf, .image]

    /// Below this many characters a PDF page is treated as scanned and sent to OCR.
    private static let minimumPageText = 25

    @concurrent
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

    @concurrent
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

    /// Photo-library files, decoded here so large HEICs aren't decoded on the main actor.
    @concurrent
    func extract(photos: [Data], name: String) async throws -> ExtractedSyllabus {
        var images: [CGImage] = []
        for photo in photos {
            try Task.checkCancellation()
            if let image = Self.cgImage(from: photo) { images.append(image) }
        }
        guard !images.isEmpty else { throw SyllabusImportError.unreadable("The photos couldn’t be opened.") }
        return try await extract(images: images, name: name, originalData: photos)
    }

    /// Photos and document-camera scans.
    @concurrent
    /// `originalData` (the photo files) is used to recognize a repeat import; scans have none,
    /// so their recognized text stands in.
    func extract(images: [CGImage], name: String, originalData: [Data] = []) async throws -> ExtractedSyllabus {
        var pages: [String] = []
        for image in images {
            try Task.checkCancellation()
            pages.append(try await recognizeText(in: image))
        }
        let text = pages.joined(separator: "\n\n")
        guard text.trimmingCharacters(in: .whitespacesAndNewlines).count >= 40 else {
            throw SyllabusImportError.noTextFound
        }
        let fingerprint = Self.fingerprint(of: originalData.isEmpty ? [Data(text.utf8)] : originalData)
        return ExtractedSyllabus(
            text: text, sourceName: name, fingerprint: fingerprint,
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
            try Task.checkCancellation()
            guard let page = document.page(at: index) else { continue }
            let text = page.string ?? ""
            if text.trimmingCharacters(in: .whitespacesAndNewlines).count >= Self.minimumPageText {
                pages.append(Self.layoutText(of: page) ?? text)
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

    /// The page's text in visual reading order, with table columns kept apart. `page.string`
    /// scrambles tables with wrapped cells, so the page is rebuilt from PDFKit's positioned line
    /// runs. A run can still span several columns, so each word gets its own box and a
    /// column-sized gap splits the run.
    static func layoutText(of page: PDFPage) -> String? {
        guard let lines = page.selection(for: page.bounds(for: .mediaBox))?.selectionsByLine(), !lines.isEmpty
        else { return nil }
        let pageTop = page.bounds(for: .mediaBox).maxY
        let pageText = (page.string ?? "") as NSString
        func flipped(_ rect: CGRect) -> CGRect {
            CGRect(x: rect.minX, y: pageTop - rect.maxY, width: rect.width, height: rect.height)
        }

        var words: [TextFragment] = []
        for line in lines {
            guard let text = line.string, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
            let lineRect = flipped(line.bounds(for: page))
            let range = line.range(at: 0, on: page)
            // Word boxes need indexes into the page's text; fall back to the whole run otherwise.
            guard range.location != NSNotFound, range.upperBound <= pageText.length else {
                words.append(TextFragment(text: text, rect: lineRect))
                continue
            }
            let lineText = pageText.substring(with: range) as NSString
            var cursor = 0
            while cursor < lineText.length {
                let rest = NSRange(location: cursor, length: lineText.length - cursor)
                let wordRange = lineText.rangeOfCharacter(from: .whitespacesAndNewlines.inverted, options: [], range: rest)
                guard wordRange.location != NSNotFound else { break }
                let end = lineText.rangeOfCharacter(from: .whitespacesAndNewlines, options: [], range: NSRange(location: wordRange.location, length: lineText.length - wordRange.location))
                let length = (end.location == NSNotFound ? lineText.length : end.location) - wordRange.location
                let word = lineText.substring(with: NSRange(location: wordRange.location, length: length))
                let box = page.selection(for: NSRange(location: range.location + wordRange.location, length: length))?.bounds(for: page)
                if let box, box.width > 0 {
                    // Keep the line's height so words on one line share a baseline band.
                    let rect = flipped(box)
                    words.append(TextFragment(text: word, rect: CGRect(x: rect.minX, y: lineRect.minY, width: rect.width, height: lineRect.height)))
                } else {
                    words.append(TextFragment(text: word, rect: lineRect))
                }
                cursor = wordRange.location + length
            }
        }
        guard !words.isEmpty else { return nil }
        return TextLayout.reconstruct(TextLayout.fragments(fromWords: words))
    }

    /// Renders a PDF page at 2× on white, for OCR.
    private static func render(_ page: PDFPage) -> CGImage? {
        let bounds = page.bounds(for: .mediaBox)
        // 2× for a letter page, but capped so an oversized page can't exhaust memory.
        let scale = min(2, 3_000 / max(bounds.width, bounds.height, 1))
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

        // Vision boxes are normalized with a bottom-left origin; lay them out in pixels, top down.
        let width = CGFloat(image.width), height = CGFloat(image.height)
        let fragments: [TextFragment] = observations.compactMap { observation in
            guard let text = observation.topCandidates(1).first?.string else { return nil }
            let box = observation.boundingBox
            return TextFragment(text: text, rect: CGRect(
                x: box.origin.x * width,
                y: (1 - box.origin.y - box.height) * height,
                width: box.width * width,
                height: box.height * height
            ))
        }
        return TextLayout.reconstruct(fragments)
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

    static func fingerprint(of parts: [Data]) -> String {
        var hasher = SHA256()
        parts.forEach { hasher.update(data: $0) }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
