import Foundation

extension QuillDocx {
    /// The first page's head, by form, as the pages carry it.
    func head() -> String {
        let accentBorder = "<w:bottom w:val=\"single\" w:sz=\"12\" w:space=\"8\" w:color=\"\(accent)\"/>"
        func lines(_ lines: [String], after: Int) -> String {
            lines.enumerated().map { offset, line in
                paragraph(QuillDocxP(style: "BodyText", after: offset == lines.count - 1 ? after : 0), runs(line))
            }.joined()
        }
        let gap = twips(layout.size * 1.4)
        switch document.form {
        case .letter:
            var xml = lines(document.from, after: gap)
            if let date = document.date { xml += paragraph(QuillDocxP(style: "BodyText", after: gap), run(date)) }
            xml += lines(document.to, after: gap)
            if !document.title.isEmpty { xml += paragraph(QuillDocxP(style: "BodyText", after: gap), runs(document.title, QuillDocxR(bold: true))) }
            return xml
        case .memo:
            var rows: [(String, String)] = []
            if !document.to.isEmpty { rows.append(("TO", document.to.joined(separator: ", "))) }
            if !document.from.isEmpty { rows.append(("FROM", document.from.joined(separator: ", "))) }
            else if let author = document.author { rows.append(("FROM", author)) }
            if let date = document.date { rows.append(("DATE", date)) }
            if !document.title.isEmpty { rows.append(("SUBJECT", document.title)) }
            var xml = paragraph(QuillDocxP(style: "Title"), run("Memo"))
            xml += rows.enumerated().map { offset, row in
                let last = offset == rows.count - 1
                return paragraph(QuillDocxP(style: "MemoLine", border: last ? accentBorder : nil, after: last ? twips(layout.size * 1.4) : 40),
                                 run(row.0 + "\t", QuillDocxR(bold: true, color: "6E6E73", size: half(0.82))) + runs(row.1))
            }.joined()
            return xml
        case .resume:
            var xml = paragraph(QuillDocxP(style: "Title"), runs(document.title))
            if let subtitle = document.subtitle { xml += paragraph(QuillDocxP(style: "Subtitle"), runs(subtitle)) }
            let contact = document.from.joined(separator: " · ")
            xml += paragraph(QuillDocxP(style: "Byline", border: accentBorder, after: twips(layout.size)), runs(contact))
            return xml
        case .worksheet:
            var xml = paragraph(QuillDocxP(style: "Title"), runs(document.title))
            if let subtitle = document.subtitle { xml += paragraph(QuillDocxP(style: "Subtitle"), runs(subtitle)) }
            xml += paragraph(QuillDocxP(style: "BodyText", before: twips(layout.size), after: twips(layout.size * 1.4)),
                             run("Name  ______________________________   Date  ____________"))
            return xml
        case .onepager:
            let shade = accent
            var xml = paragraph(QuillDocxP(style: "Title", shade: shade, leftIndent: 120, rightIndent: 120), runs(document.title, QuillDocxR(color: "FFFFFF")))
            if let subtitle = document.subtitle {
                xml += paragraph(QuillDocxP(style: "Subtitle", shade: shade, leftIndent: 120, rightIndent: 120), runs(subtitle, QuillDocxR(color: "FFFFFF")))
            }
            let byline = [document.author, document.date].compactMap { $0 }.joined(separator: " · ")
            xml += paragraph(QuillDocxP(style: "Byline", shade: shade, after: twips(layout.size * 1.2), leftIndent: 120, rightIndent: 120),
                             run(byline.isEmpty ? " " : byline, QuillDocxR(color: "FFFFFF")))
            return xml
        case .report, .proposal, .contract:
            var parts: [String] = [paragraph(QuillDocxP(style: "Title"), runs(document.title))]
            if let subtitle = document.subtitle { parts.append(paragraph(QuillDocxP(style: "Subtitle"), runs(subtitle))) }
            if !document.to.isEmpty { parts.append(paragraph(QuillDocxP(style: "Byline"), runs("Prepared for " + document.to.joined(separator: ", ")))) }
            let byline = [document.author, document.date].compactMap { $0 }.joined(separator: " · ")
            parts.append(paragraph(QuillDocxP(style: "Byline", border: accentBorder, after: twips(layout.size * 1.6)), run(byline.isEmpty ? " " : byline)))
            return parts.joined() + contents()
        }
    }

    /// A table of contents Word fills in (its TOC field over the heading styles), when the style asks for one.
    func contents() -> String {
        guard document.style.contents == true, document.blocks.filter({ $0.kind == .heading && $0.depth <= 2 }).count >= 2 else { return "" }
        let entries = document.blocks.filter { $0.kind == .heading && $0.depth <= 2 }.map { block in
            paragraph(QuillDocxP(style: "TOC\(block.depth)"), runs(block.text ?? ""))
        }.joined()
        return paragraph(QuillDocxP(style: "TOCHeading"), run("Contents"))
            + "<w:p><w:pPr><w:pStyle w:val=\"TOC1\"/></w:pPr><w:r><w:fldChar w:fldCharType=\"begin\" w:dirty=\"true\"/></w:r>"
            + "<w:r><w:instrText xml:space=\"preserve\"> TOC \\o \"1-2\" \\h \\z \\u </w:instrText></w:r><w:r><w:fldChar w:fldCharType=\"separate\"/></w:r></w:p>"
            + entries
            + "<w:p><w:r><w:fldChar w:fldCharType=\"end\"/></w:r></w:p>"
    }

    /// The page's size and margins, as the PDF was laid out; head and foot on every page after the first, and the
    /// first page's own (none for a letter, no title for a long form).
    func sectionProperties() -> String {
        let (w, h) = document.paper.twips
        var references = ""
        if let header = headerID { references += "<w:headerReference w:type=\"default\" r:id=\"\(header)\"/>" }
        if let footer = footerID { references += "<w:footerReference w:type=\"default\" r:id=\"\(footer)\"/>" }
        if let first = firstFooterID { references += "<w:footerReference w:type=\"first\" r:id=\"\(first)\"/>" }
        let titlePage = pages > 1 ? "<w:titlePg/>" : ""
        let x = twips(layout.marginX), y = twips(layout.marginY), edge = twips(max(layout.marginY / 2 - 6, 18))
        return "<w:sectPr>\(references)<w:pgSz w:w=\"\(w)\" w:h=\"\(h)\"/>"
            + "<w:pgMar w:top=\"\(y)\" w:right=\"\(x)\" w:bottom=\"\(y)\" w:left=\"\(x)\" w:header=\"\(edge)\" w:footer=\"\(edge)\" w:gutter=\"0\"/>"
            + "\(titlePage)</w:sectPr>"
    }
}
