import Foundation
@testable import anf

/// Structured docx preview: headings, bold runs, list items and tables parsed
/// from word/document.xml (built as a real zip fixture via /usr/bin/zip).
func runDocxStructureTests() {
    let xml = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
    <w:body>
      <w:p><w:pPr><w:pStyle w:val="Heading1"/></w:pPr><w:r><w:t>이력서</w:t></w:r></w:p>
      <w:p><w:r><w:t>plain </w:t></w:r><w:r><w:rPr><w:b/></w:rPr><w:t>bold</w:t></w:r></w:p>
      <w:p><w:pPr><w:numPr><w:ilvl w:val="0"/><w:numId w:val="1"/></w:numPr></w:pPr>
        <w:r><w:t>first item</w:t></w:r></w:p>
      <w:tbl>
        <w:tr><w:tc><w:p><w:r><w:t>이름</w:t></w:r></w:p></w:tc>
              <w:tc><w:p><w:r><w:t>박성일</w:t></w:r></w:p></w:tc></w:tr>
        <w:tr><w:tc><w:p><w:r><w:t>메일</w:t></w:r></w:p></w:tc>
              <w:tc><w:p><w:r><w:t>z@g.com</w:t></w:r></w:p></w:tc></w:tr>
      </w:tbl>
      <w:p><w:pPr><w:outlineLvl w:val="1"/></w:pPr><w:r><w:t>outline heading</w:t></w:r></w:p>
    </w:body>
    </w:document>
    """

    T.group("DocxStructure.parse(documentXML:)") {
        let blocks = DocxStructure.parse(documentXML: Data(xml.utf8))
        T.equal(blocks.count, 5, "five blocks (got \(blocks.count))")
        if case .header(let l, let t) = blocks[0] {
            T.equal(l, 1, "Heading1 style → h1"); T.equal(t, "이력서", "heading text")
        } else { T.expect(false, "block 0 is a header") }
        if case .paragraph(let runs) = blocks[1] {
            T.equal(runs.count, 2, "bold split into its own run")
            T.expect(runs[0].bold == false && runs[1].bold == true, "bold flag per run")
            T.equal(runs[1].text, "bold", "bold run text")
        } else { T.expect(false, "block 1 is a paragraph") }
        if case .listItem(let t, let lv) = blocks[2] {
            T.equal(t, "first item", "list text"); T.equal(lv, 0, "list level")
        } else { T.expect(false, "block 2 is a list item") }
        if case .table(let rows) = blocks[3] {
            T.equal(rows.count, 2, "two rows")
            T.equal(rows[0], ["이름", "박성일"], "row 1 cells")
            T.equal(rows[1], ["메일", "z@g.com"], "row 2 cells")
        } else { T.expect(false, "block 3 is a table") }
        if case .header(let l, _) = blocks[4] {
            T.equal(l, 2, "outlineLvl 1 → h2")
        } else { T.expect(false, "block 4 is a header") }
    }

    T.group("DocxStructure.parse(docxAt:) via a real zip") {
        let fm = FileManager.default
        let dir = fm.temporaryDirectory.appendingPathComponent("anfdocx-\(UUID().uuidString)")
        defer { try? fm.removeItem(at: dir) }
        try? fm.createDirectory(at: dir.appendingPathComponent("word"), withIntermediateDirectories: true)
        try? xml.write(to: dir.appendingPathComponent("word/document.xml"), atomically: true, encoding: .utf8)
        let docx = dir.appendingPathComponent("t.docx")
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        p.arguments = ["-q", "-r", docx.path, "word"]
        p.currentDirectoryURL = dir
        try? p.run(); p.waitUntilExit()
        let blocks = DocxStructure.parse(docxAt: docx)
        T.equal(blocks.count, 5, "zip round-trip parses the same blocks")
        T.expect(DocxStructure.parse(docxAt: dir.appendingPathComponent("none.docx")).isEmpty,
                 "missing file → empty (text fallback), no crash")
    }
}
