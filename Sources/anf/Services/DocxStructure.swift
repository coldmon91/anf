import Foundation

/// One visual block of a docx body — the docx analogue of MDBlock. Parsed
/// straight from word/document.xml so the inspector can render headings,
/// tables, lists and bold natively: instant and dark-mode native, unlike
/// Quick Look which re-renders the page image on every selection.
enum DocxBlock {
    case header(level: Int, text: String)
    case paragraph(runs: [(text: String, bold: Bool)])
    case listItem(text: String, level: Int)
    case table(rows: [[String]])
}

/// Streaming OOXML reader: w:p paragraphs (style/outline level → headings,
/// w:numPr → list items, w:b runs → bold), w:tbl/w:tr/w:tc → tables.
/// Good for the visual 95% of real documents; anything exotic just becomes a
/// plain paragraph. Pure and synchronous — callers run it off-main.
final class DocxStructure: NSObject, XMLParserDelegate {

    static func parse(docxAt url: URL) -> [DocxBlock] {
        guard let xml = unzipEntry(url, "word/document.xml") else { return [] }
        return parse(documentXML: xml)
    }

    static func parse(documentXML data: Data) -> [DocxBlock] {
        let reader = DocxStructure()
        let parser = XMLParser(data: data)
        parser.delegate = reader
        parser.parse()
        return reader.blocks
    }

    /// `unzip -p` one entry (binary-safe). docx/hwpx are plain zip containers.
    static func unzipEntry(_ url: URL, _ entry: String) -> Data? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        p.arguments = ["-p", url.path, entry]
        let out = Pipe()
        p.standardOutput = out
        p.standardError = FileHandle.nullDevice
        do { try p.run() } catch { return nil }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return p.terminationStatus == 0 && !data.isEmpty ? data : nil
    }

    // MARK: - Parser state

    private var blocks: [DocxBlock] = []

    private var inParagraph = false
    private var styleVal = ""
    private var outlineLevel: Int?
    private var isListItem = false
    private var listLevel = 0
    private var runs: [(text: String, bold: Bool)] = []
    private var runBold = false
    private var pendingBold = false      // w:b seen inside w:rPr
    private var inRunProps = false
    private var collectingText = false
    private var textBuffer = ""

    private var tableDepth = 0
    private var tableRows: [[String]] = []
    private var currentRow: [String] = []
    private var cellText = ""

    func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?,
                qualifiedName: String?, attributes attrs: [String: String]) {
        switch name {
        case "w:tbl":
            tableDepth += 1
            if tableDepth == 1 { tableRows = [] }
        case "w:tr": if tableDepth == 1 { currentRow = [] }
        case "w:tc": if tableDepth == 1 { cellText = "" }
        case "w:p":
            inParagraph = true
            styleVal = ""; outlineLevel = nil
            isListItem = false; listLevel = 0
            runs = []
        case "w:pStyle": styleVal = attrs["w:val"] ?? ""
        case "w:outlineLvl": outlineLevel = Int(attrs["w:val"] ?? "")
        case "w:numPr": if inParagraph { isListItem = true }
        case "w:ilvl": listLevel = Int(attrs["w:val"] ?? "") ?? 0
        case "w:r": runBold = false; pendingBold = false
        case "w:rPr": inRunProps = true
        case "w:b", "w:bCs":
            if inRunProps {
                let v = (attrs["w:val"] ?? "true").lowercased()
                pendingBold = !(v == "false" || v == "0" || v == "none")
            }
        case "w:t": collectingText = true; textBuffer = ""
        case "w:tab": appendText("\t")
        case "w:br", "w:cr": appendText("\n")
        default: break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if collectingText { textBuffer += string }
    }

    func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?,
                qualifiedName: String?) {
        switch name {
        case "w:rPr": inRunProps = false; runBold = pendingBold
        case "w:t":
            collectingText = false
            appendText(textBuffer)
        case "w:p":
            inParagraph = false
            if tableDepth > 0 {
                let text = runs.map(\.text).joined()
                if !cellText.isEmpty && !text.isEmpty { cellText += "\n" }
                cellText += text
            } else {
                flushParagraph()
            }
        case "w:tc": if tableDepth == 1 { currentRow.append(cellText.trimmingCharacters(in: .whitespacesAndNewlines)) }
        case "w:tr": if tableDepth == 1, !currentRow.isEmpty { tableRows.append(currentRow) }
        case "w:tbl":
            tableDepth -= 1
            if tableDepth == 0, !tableRows.isEmpty { blocks.append(.table(rows: tableRows)) }
        default: break
        }
    }

    private func appendText(_ s: String) {
        guard !s.isEmpty else { return }
        if runs.isEmpty || runs[runs.count - 1].bold != runBold {
            runs.append((s, runBold))
        } else {
            runs[runs.count - 1].text += s
        }
    }

    private func flushParagraph() {
        let text = runs.map(\.text).joined().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        if let level = headingLevel() {
            blocks.append(.header(level: level, text: text))
        } else if isListItem {
            blocks.append(.listItem(text: text, level: listLevel))
        } else {
            blocks.append(.paragraph(runs: runs))
        }
    }

    /// Word marks headings two ways: a paragraph style ID like "Heading1"
    /// ("제목 1" maps to the same IDs in OOXML) or an explicit outline level.
    private func headingLevel() -> Int? {
        let s = styleVal.lowercased()
        if s == "title" { return 1 }
        if s.hasPrefix("heading"), let n = Int(s.dropFirst("heading".count)) {
            return min(max(n, 1), 6)
        }
        if let o = outlineLevel { return min(max(o + 1, 1), 6) }
        return nil
    }
}
