import Foundation

/// Reads the plain text of a Word .docx: paragraphs become lines and table cells are
/// separated by tabs, so schedule tables keep their columns for the parser.
nonisolated enum DocxTextReader {
    static func text(from data: Data) throws -> String {
        let archive = try ZipArchive(data: data)
        let xml = try archive.contents(of: "word/document.xml")
        let collector = Collector()
        let parser = XMLParser(data: xml)
        parser.delegate = collector
        guard parser.parse() else {
            throw parser.parserError ?? ZipArchive.ZipError.corrupt
        }
        return collector.text
    }

    private final class Collector: NSObject, XMLParserDelegate {
        private(set) var text = ""
        private var isInTextRun = false

        func parser(
            _ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
            qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]
        ) {
            switch elementName {
            case "w:t": isInTextRun = true
            case "w:tab": text += "\t"
            case "w:br", "w:cr": text += "\n"
            default: break
            }
        }

        func parser(
            _ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?,
            qualifiedName qName: String?
        ) {
            switch elementName {
            case "w:t": isInTextRun = false
            case "w:tc":
                // Cell paragraphs end in a newline; join cells on the same row instead.
                if text.hasSuffix("\n") { text.removeLast() }
                text += "\t"
            case "w:tr":
                if text.hasSuffix("\t") { text.removeLast() }
                text += "\n"
            case "w:p": text += "\n"
            default: break
            }
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) {
            if isInTextRun { text += string }
        }
    }
}
