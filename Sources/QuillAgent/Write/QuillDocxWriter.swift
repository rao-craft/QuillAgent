import Foundation

/// The draft as a Word file, written as WordprocessingML from the same blocks the pages were laid out from: named styles
/// (Title, Heading 1–3, Quote, Caption…) a person restyles in one place, real lists and tables (a table's header row
/// repeats on every page), the paper and margins the PDF was laid out on, a footer with live page numbers, links, images.
///
/// PIN: ORDER IS THE SCHEMA'S. Word refuses a file whose properties are out of order, so paragraph and run properties
/// are built by `QuillDocxP` and `QuillDocxR`, which write their elements in the schema's sequence.
/// PIN: THE SAME DRAFT, THE SAME BYTES. No dates, no random ids, stored zip entries at a fixed time.
enum QuillDocxWriter {
    static func write(_ document: QuillDocument, layout: QuillLayout, pictures: QuillPictures, pages: Int) throws -> Data {
        let writer = QuillDocx(document: document, layout: layout, pictures: pictures, pages: pages)
        return writer.package()
    }
}

/// One Word file being written: its relationships, media and list numbering gathered as the body is.
final class QuillDocx {
    let document: QuillDocument
    let layout: QuillLayout
    let pictures: QuillPictures
    let pages: Int

    struct Relationship { let id: String; let type: String; let target: String; let external: Bool }
    private(set) var relationships: [Relationship] = []
    private(set) var media: [(name: String, data: Data)] = []
    /// Numbering instances for ordered lists, each restarting at one; instance 1 is every bullet list.
    private(set) var orderedLists = 0
    private var drawings = 0

    init(document: QuillDocument, layout: QuillLayout, pictures: QuillPictures, pages: Int) {
        self.document = document; self.layout = layout; self.pictures = pictures; self.pages = pages
    }

    static let relBase = "http://schemas.openxmlformats.org/officeDocument/2006/relationships"

    func relate(_ type: String, _ target: String, external: Bool = false) -> String {
        if let existing = relationships.first(where: { $0.type == type && $0.target == target }) { return existing.id }
        let id = "rId\(relationships.count + 1)"
        relationships.append(Relationship(id: id, type: "\(Self.relBase)/\(type)", target: target, external: external))
        return id
    }

    // MARK: - Measures

    var face: String { document.face == .serif ? "Charter" : "Helvetica Neue" }
    static let mono = "Menlo"
    var accent: String { String(document.style.accentHex.dropFirst()).uppercased() }
    /// Half-points.
    func half(_ em: Double) -> Int { Int((layout.size * em * 2).rounded()) }
    /// Twentieths of a point.
    func twips(_ points: Double) -> Int { Int((points * 20).rounded()) }
    var gapAfter: Int { twips(layout.gap * layout.size) }
    var columnWidth: Double { document.paper.width - 2 * layout.marginX }

    // MARK: - The body

    func body() -> String {
        var xml = head()
        var pageBreak = false
        var numbers = [0, 0]
        for (index, block) in document.blocks.enumerated() {
            if block.kind == .break { pageBreak = true; continue }
            xml += element(block, index: index, pageBreak: pageBreak, numbers: &numbers)
            pageBreak = false
        }
        xml += sectionProperties()
        return """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main" \
        xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" \
        xmlns:wp="http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing" \
        xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" \
        xmlns:pic="http://schemas.openxmlformats.org/drawingml/2006/picture"><w:body>\(xml)</w:body></w:document>
        """
    }

    func element(_ block: QuillBlock, index: Int, pageBreak: Bool, numbers: inout [Int]) -> String {
        let text = block.text ?? ""
        switch block.kind {
        case .heading:
            var label = text
            if document.numbered, block.depth <= 2 {
                if block.depth == 1 { numbers[0] += 1; numbers[1] = 0; label = "\(numbers[0]). " + text }
                else { numbers[1] += 1; label = "\(max(numbers[0], 1)).\(numbers[1]) " + text }
            }
            return paragraph(QuillDocxP(style: "Heading\(block.depth)", pageBreakBefore: pageBreak), runs(label))
        case .paragraph:
            guard !text.isEmpty else { return "" }
            return paragraph(QuillDocxP(style: "BodyText", pageBreakBefore: pageBreak), runs(text))
        case .list:
            let instance: Int
            if block.ordered == true { orderedLists += 1; instance = orderedLists + 1 } else { instance = 1 }
            return block.items.enumerated().map { offset, item in
                paragraph(QuillDocxP(style: "ListParagraph", pageBreakBefore: pageBreak && offset == 0, numbering: instance), runs(item))
            }.joined()
        case .table:
            return table(block, pageBreak: pageBreak)
        case .quote:
            guard !text.isEmpty else { return "" }
            let by = block.by.map { paragraph(QuillDocxP(style: "QuoteBy"), run("— \($0)")) } ?? ""
            return paragraph(QuillDocxP(style: "Quote", pageBreakBefore: pageBreak), runs(text)) + by
        case .callout:
            var inner = ""
            if let title = block.title { inner += runs(title, QuillDocxR(bold: true, color: accent)) }
            if !text.isEmpty { inner += (inner.isEmpty ? "" : "<w:r><w:br/></w:r>") + runs(text) }
            return inner.isEmpty ? "" : paragraph(QuillDocxP(style: "Callout", pageBreakBefore: pageBreak), inner)
        case .figure:
            guard let picture = pictures.pictures[index] else {
                return paragraph(QuillDocxP(style: "Callout", pageBreakBefore: pageBreak),
                                 run("[\(block.path ?? "picture")]" + (text.isEmpty ? "" : " — \(QuillInline(text).plain)")))
            }
            let caption = text.isEmpty ? "" : paragraph(QuillDocxP(style: "Caption"), runs(text))
            return paragraph(QuillDocxP(style: "Figure", pageBreakBefore: pageBreak), drawing(picture, alt: QuillInline(text).plain)) + caption
        case .fields:
            return fields(block, pageBreak: pageBreak)
        case .signature:
            let width = twips(columnWidth / 2)
            let line = paragraph(QuillDocxP(style: "SignatureLine", pageBreakBefore: pageBreak, rightIndent: twips(columnWidth) - width), "")
            let name = text.isEmpty ? "" : paragraph(QuillDocxP(style: "Signature"), runs(text))
            let by = block.by.map { paragraph(QuillDocxP(style: "SignatureTitle"), run($0)) } ?? ""
            return line + name + by
        case .code:
            let lines = (block.text ?? "").components(separatedBy: "\n")
            let inner = lines.enumerated().map { ($0.offset > 0 ? "<w:r><w:br/></w:r>" : "") + run($0.element) }.joined()
            return paragraph(QuillDocxP(style: "Code", pageBreakBefore: pageBreak), inner)
        case .rule:
            return paragraph(QuillDocxP(style: "Rule", pageBreakBefore: pageBreak), "")
        case .break:
            return ""
        }
    }

    func paragraph(_ properties: QuillDocxP, _ runs: String) -> String { "<w:p>\(properties.xml)\(runs)</w:p>" }

    /// One run of plain text.
    func run(_ text: String, _ properties: QuillDocxR = QuillDocxR()) -> String {
        "<w:r>\(properties.xml)<w:t xml:space=\"preserve\">\(QuillDocx.escape(text))</w:t></w:r>"
    }

    /// A block's text with its marks: bold, italic, code and links.
    func runs(_ text: String, _ base: QuillDocxR = QuillDocxR()) -> String {
        QuillInline(text).runs.map { part in
            var properties = base
            if part.bold { properties.bold = true }
            if part.italic { properties.italic = true }
            if part.code { properties.font = QuillDocx.mono; properties.shade = "F2F1ED"; properties.size = half(0.88) }
            guard let link = part.link, QuillHTML.isSafe(link), !link.hasPrefix("#") else { return run(part.text, properties) }
            properties.style = "Hyperlink"
            let id = relate("hyperlink", link, external: true)
            return "<w:hyperlink r:id=\"\(id)\">\(run(part.text, properties))</w:hyperlink>"
        }.joined()
    }

    // MARK: - Tables

    func table(_ block: QuillBlock, pageBreak: Bool) -> String {
        guard let header = block.rows.first else { return "" }
        let width = max(block.rows.map(\.count).max() ?? header.count, 1)
        let total = twips(columnWidth)
        let column = total / width
        var xml = pageBreak ? paragraph(QuillDocxP(pageBreakBefore: true, after: 0), "") : ""
        xml += "<w:tbl><w:tblPr><w:tblW w:w=\"\(total)\" w:type=\"dxa\"/><w:tblLayout w:type=\"fixed\"/>"
        xml += "<w:tblCellMar><w:top w:w=\"60\" w:type=\"dxa\"/><w:left w:w=\"0\" w:type=\"dxa\"/><w:bottom w:w=\"60\" w:type=\"dxa\"/><w:right w:w=\"120\" w:type=\"dxa\"/></w:tblCellMar>"
        xml += "<w:tblLook w:val=\"0020\" w:firstRow=\"1\" w:lastRow=\"0\" w:firstColumn=\"0\" w:lastColumn=\"0\" w:noHBand=\"1\" w:noVBand=\"1\"/></w:tblPr>"
        xml += "<w:tblGrid>" + String(repeating: "<w:gridCol w:w=\"\(column)\"/>", count: width) + "</w:tblGrid>"
        for (offset, row) in block.rows.enumerated() {
            let isHeader = offset == 0
            xml += "<w:tr><w:trPr><w:cantSplit/>\(isHeader ? "<w:tblHeader/>" : "")</w:trPr>"
            for cell in 0..<width {
                let text = cell < row.count ? row[cell] : ""
                let border = isHeader ? "<w:bottom w:val=\"single\" w:sz=\"8\" w:space=\"0\" w:color=\"\(accent)\"/>"
                    : "<w:bottom w:val=\"single\" w:sz=\"4\" w:space=\"0\" w:color=\"D4D2CC\"/>"
                xml += "<w:tc><w:tcPr><w:tcW w:w=\"\(column)\" w:type=\"dxa\"/><w:tcBorders>\(border)</w:tcBorders></w:tcPr>"
                xml += paragraph(QuillDocxP(style: "TableText"), runs(text, QuillDocxR(bold: isHeader)))
                xml += "</w:tc>"
            }
            xml += "</w:tr>"
        }
        xml += "</w:tbl>"
        // A table is followed by a paragraph, as Word's own are: the space after it.
        return xml + paragraph(QuillDocxP(style: "TableAfter"), "")
    }

    func fields(_ block: QuillBlock, pageBreak: Bool) -> String {
        guard !block.fields.isEmpty else { return "" }
        let total = twips(columnWidth)
        let labelWidth = min(total / 3, twips(150))
        var xml = pageBreak ? paragraph(QuillDocxP(pageBreakBefore: true, after: 0), "") : ""
        xml += "<w:tbl><w:tblPr><w:tblW w:w=\"\(total)\" w:type=\"dxa\"/><w:tblLayout w:type=\"fixed\"/>"
        xml += "<w:tblCellMar><w:top w:w=\"80\" w:type=\"dxa\"/><w:left w:w=\"0\" w:type=\"dxa\"/><w:bottom w:w=\"40\" w:type=\"dxa\"/><w:right w:w=\"160\" w:type=\"dxa\"/></w:tblCellMar>"
        xml += "<w:tblLook w:val=\"0000\" w:firstRow=\"0\" w:lastRow=\"0\" w:firstColumn=\"0\" w:lastColumn=\"0\" w:noHBand=\"1\" w:noVBand=\"1\"/></w:tblPr>"
        xml += "<w:tblGrid><w:gridCol w:w=\"\(labelWidth)\"/><w:gridCol w:w=\"\(total - labelWidth)\"/></w:tblGrid>"
        for field in block.fields {
            xml += "<w:tr><w:trPr><w:cantSplit/></w:trPr>"
            xml += "<w:tc><w:tcPr><w:tcW w:w=\"\(labelWidth)\" w:type=\"dxa\"/></w:tcPr>\(paragraph(QuillDocxP(style: "TableText"), runs(field.label, QuillDocxR(bold: true))))</w:tc>"
            let blank = field.value.isEmpty ? "<w:tcBorders><w:bottom w:val=\"single\" w:sz=\"6\" w:space=\"0\" w:color=\"8A8A8E\"/></w:tcBorders>" : ""
            xml += "<w:tc><w:tcPr><w:tcW w:w=\"\(total - labelWidth)\" w:type=\"dxa\"/>\(blank)</w:tcPr>\(paragraph(QuillDocxP(style: "TableText"), runs(field.value)))</w:tc>"
            xml += "</w:tr>"
        }
        xml += "</w:tbl>"
        return xml + paragraph(QuillDocxP(style: "TableAfter"), "")
    }

    // MARK: - Pictures

    func drawing(_ picture: QuillPictures.Picture, alt: String) -> String {
        drawings += 1
        let name = "image\(drawings).\(picture.type == "jpeg" ? "jpeg" : picture.type)"
        media.append((name, picture.data))
        let id = relate("image", "media/\(name)")
        // Fitted as the page fits it: the column's width at most, three fifths of its height at most, never enlarged.
        let columnHeight = document.paper.height - 2 * layout.marginY
        let natural = (w: Double(picture.width) * 0.75, h: Double(picture.height) * 0.75)
        let scale = min(1, columnWidth / max(natural.w, 1), columnHeight * 0.6 / max(natural.h, 1))
        let cx = Int(natural.w * scale * 12700), cy = Int(natural.h * scale * 12700)
        return """
        <w:r><w:drawing><wp:inline distT="0" distB="0" distL="0" distR="0"><wp:extent cx="\(cx)" cy="\(cy)"/>\
        <wp:docPr id="\(drawings)" name="Picture \(drawings)" descr="\(QuillDocx.escape(alt))"/>\
        <wp:cNvGraphicFramePr><a:graphicFrameLocks noChangeAspect="1"/></wp:cNvGraphicFramePr>\
        <a:graphic><a:graphicData uri="http://schemas.openxmlformats.org/drawingml/2006/picture"><pic:pic>\
        <pic:nvPicPr><pic:cNvPr id="\(drawings)" name="\(name)"/><pic:cNvPicPr/></pic:nvPicPr>\
        <pic:blipFill><a:blip r:embed="\(id)"/><a:stretch><a:fillRect/></a:stretch></pic:blipFill>\
        <pic:spPr><a:xfrm><a:off x="0" y="0"/><a:ext cx="\(cx)" cy="\(cy)"/></a:xfrm><a:prstGeom prst="rect"><a:avLst/></a:prstGeom></pic:spPr>\
        </pic:pic></a:graphicData></a:graphic></wp:inline></w:drawing></w:r>
        """
    }

    static func escape(_ text: String) -> String {
        var out = ""
        for scalar in text.unicodeScalars {
            switch scalar {
            case "&": out += "&amp;"
            case "<": out += "&lt;"
            case ">": out += "&gt;"
            case "\"": out += "&quot;"
            // Characters XML 1.0 does not allow are dropped.
            case _ where scalar.value < 0x20 && scalar != "\t" && scalar != "\n" && scalar != "\r": continue
            default: out.unicodeScalars.append(scalar)
            }
        }
        return out
    }
}

/// A paragraph's properties, written in the schema's order.
struct QuillDocxP {
    var style: String?
    var keepNext = false
    var pageBreakBefore = false
    /// A numbering instance: 1 for bullets, 2 and up for each ordered list.
    var numbering: Int?
    var border: String?
    var shade: String?
    var before: Int?
    var after: Int?
    var leftIndent: Int?
    var rightIndent: Int?
    var center = false

    init(style: String? = nil, keepNext: Bool = false, pageBreakBefore: Bool = false, numbering: Int? = nil, border: String? = nil,
         shade: String? = nil, before: Int? = nil, after: Int? = nil, leftIndent: Int? = nil, rightIndent: Int? = nil, center: Bool = false) {
        self.style = style; self.keepNext = keepNext; self.pageBreakBefore = pageBreakBefore; self.numbering = numbering
        self.border = border; self.shade = shade; self.before = before; self.after = after
        self.leftIndent = leftIndent; self.rightIndent = rightIndent; self.center = center
    }

    var xml: String {
        var xml = ""
        if let style { xml += "<w:pStyle w:val=\"\(style)\"/>" }
        if keepNext { xml += "<w:keepNext/>" }
        if pageBreakBefore { xml += "<w:pageBreakBefore/>" }
        if let numbering { xml += "<w:numPr><w:ilvl w:val=\"0\"/><w:numId w:val=\"\(numbering)\"/></w:numPr>" }
        if let border { xml += "<w:pBdr>\(border)</w:pBdr>" }
        if let shade { xml += "<w:shd w:val=\"clear\" w:color=\"auto\" w:fill=\"\(shade)\"/>" }
        if before != nil || after != nil {
            xml += "<w:spacing" + (before.map { " w:before=\"\($0)\"" } ?? "") + (after.map { " w:after=\"\($0)\"" } ?? "") + "/>"
        }
        if leftIndent != nil || rightIndent != nil {
            xml += "<w:ind" + (leftIndent.map { " w:left=\"\($0)\"" } ?? "") + (rightIndent.map { " w:right=\"\($0)\"" } ?? "") + "/>"
        }
        if center { xml += "<w:jc w:val=\"center\"/>" }
        return xml.isEmpty ? "" : "<w:pPr>\(xml)</w:pPr>"
    }
}

/// A run's properties, written in the schema's order.
struct QuillDocxR {
    var style: String?
    var font: String?
    var bold = false
    var italic = false
    var color: String?
    /// Half-points.
    var size: Int?
    var shade: String?

    init(style: String? = nil, font: String? = nil, bold: Bool = false, italic: Bool = false, color: String? = nil, size: Int? = nil, shade: String? = nil) {
        self.style = style; self.font = font; self.bold = bold; self.italic = italic; self.color = color; self.size = size; self.shade = shade
    }

    var xml: String {
        var xml = ""
        if let style { xml += "<w:rStyle w:val=\"\(style)\"/>" }
        if let font { xml += "<w:rFonts w:ascii=\"\(font)\" w:hAnsi=\"\(font)\" w:cs=\"\(font)\"/>" }
        if bold { xml += "<w:b/><w:bCs/>" }
        if italic { xml += "<w:i/><w:iCs/>" }
        if let color { xml += "<w:color w:val=\"\(color)\"/>" }
        if let size { xml += "<w:sz w:val=\"\(size)\"/><w:szCs w:val=\"\(size)\"/>" }
        if let shade { xml += "<w:shd w:val=\"clear\" w:color=\"auto\" w:fill=\"\(shade)\"/>" }
        return xml.isEmpty ? "" : "<w:rPr>\(xml)</w:rPr>"
    }
}
