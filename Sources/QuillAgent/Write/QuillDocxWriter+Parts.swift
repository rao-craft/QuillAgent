import Foundation

extension QuillDocx {
    // MARK: - Head and foot

    /// A mark along the head or foot: words, the page number, the page count.
    enum Piece { case text(String), page, count }

    /// What runs along every page after the first, and along the first, as the PDF's marks do. Nothing on a document of
    /// one page.
    var marks: (header: [Piece]?, footer: [Piece]?, firstFooter: [Piece]?) {
        guard pages > 1 else { return (nil, nil, nil) }
        let title = QuillInline(document.title).plain
        let count: [Piece] = [.page, .text(" of "), .count]
        switch document.form {
        case .letter: return (nil, [.text("Page "), .page], nil)
        case .resume:
            let foot: [Piece] = title.isEmpty ? count : [.text("\(title) · ")] + count
            return (nil, foot, foot)
        case .report, .proposal, .contract, .worksheet: return (title.isEmpty ? nil : [.text(title)], count, count)
        case .memo, .onepager: return (nil, count, count)
        }
    }

    var headerID: String? { marks.header == nil ? nil : relate("header", "header1.xml") }
    var footerID: String? { marks.footer == nil ? nil : relate("footer", "footer1.xml") }
    var firstFooterID: String? { marks.firstFooter == nil ? nil : relate("footer", "footer2.xml") }

    func markPart(_ tag: String, _ pieces: [Piece], center: Bool) -> String {
        let runs = pieces.map { piece -> String in
            switch piece {
            case .text(let text): return run(text)
            case .page: return "<w:fldSimple w:instr=\" PAGE \">\(run("1"))</w:fldSimple>"
            case .count: return "<w:fldSimple w:instr=\" NUMPAGES \">\(run("1"))</w:fldSimple>"
            }
        }.joined()
        return """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <w:\(tag) xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main" \
        xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">\
        <w:p>\(QuillDocxP(style: "PageMark", center: center).xml)\(runs)</w:p></w:\(tag)>
        """
    }

    // MARK: - The package

    func package() -> Data {
        let body = body()
        let marks = self.marks
        _ = relate("styles", "styles.xml")
        _ = relate("numbering", "numbering.xml")
        _ = relate("settings", "settings.xml")

        var zip = QuillZip()
        zip.add("[Content_Types].xml", contentTypes(marks: marks))
        zip.add("_rels/.rels", """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">\
        <Relationship Id="rId1" Type="\(Self.relBase)/officeDocument" Target="word/document.xml"/>\
        <Relationship Id="rId2" Type="http://schemas.openxmlformats.org/package/2006/relationships/metadata/core-properties" Target="docProps/core.xml"/>\
        <Relationship Id="rId3" Type="\(Self.relBase)/extended-properties" Target="docProps/app.xml"/></Relationships>
        """)
        zip.add("docProps/core.xml", core())
        zip.add("docProps/app.xml", """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Properties xmlns="http://schemas.openxmlformats.org/officeDocument/2006/extended-properties"><Application>Quill</Application><Pages>\(pages)</Pages></Properties>
        """)
        zip.add("word/document.xml", body)
        zip.add("word/styles.xml", stylesPart())
        zip.add("word/numbering.xml", numberingPart())
        zip.add("word/settings.xml", """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <w:settings xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">\
        \(document.style.contents == true ? "<w:updateFields w:val=\"true\"/>" : "")<w:defaultTabStop w:val="720"/>\
        <w:characterSpacingControl w:val="doNotCompress"/><w:compat><w:compatSetting w:name="compatibilityMode" \
        w:uri="http://schemas.microsoft.com/office/word" w:val="15"/></w:compat></w:settings>
        """)
        if let header = marks.header { zip.add("word/header1.xml", markPart("hdr", header, center: false)) }
        if let footer = marks.footer { zip.add("word/footer1.xml", markPart("ftr", footer, center: true)) }
        if let first = marks.firstFooter { zip.add("word/footer2.xml", markPart("ftr", first, center: true)) }
        for item in media { zip.add("word/media/\(item.name)", item.data) }
        zip.add("word/_rels/document.xml.rels", "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>\n"
                + "<Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\">"
                + relationships.map { rel in
                    "<Relationship Id=\"\(rel.id)\" Type=\"\(rel.type)\" Target=\"\(QuillDocx.escape(rel.target))\"\(rel.external ? " TargetMode=\"External\"" : "")/>"
                }.joined() + "</Relationships>")
        return zip.data
    }

    func contentTypes(marks: (header: [Piece]?, footer: [Piece]?, firstFooter: [Piece]?)) -> String {
        let main = "application/vnd.openxmlformats-officedocument.wordprocessingml"
        var overrides = [
            ("/word/document.xml", "\(main).document.main+xml"),
            ("/word/styles.xml", "\(main).styles+xml"),
            ("/word/numbering.xml", "\(main).numbering+xml"),
            ("/word/settings.xml", "\(main).settings+xml"),
            ("/docProps/core.xml", "application/vnd.openxmlformats-package.core-properties+xml"),
            ("/docProps/app.xml", "application/vnd.openxmlformats-officedocument.extended-properties+xml"),
        ]
        if marks.header != nil { overrides.append(("/word/header1.xml", "\(main).header+xml")) }
        if marks.footer != nil { overrides.append(("/word/footer1.xml", "\(main).footer+xml")) }
        if marks.firstFooter != nil { overrides.append(("/word/footer2.xml", "\(main).footer+xml")) }
        return "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>\n"
            + "<Types xmlns=\"http://schemas.openxmlformats.org/package/2006/content-types\">"
            + "<Default Extension=\"rels\" ContentType=\"application/vnd.openxmlformats-package.relationships+xml\"/>"
            + "<Default Extension=\"xml\" ContentType=\"application/xml\"/>"
            + "<Default Extension=\"png\" ContentType=\"image/png\"/><Default Extension=\"jpeg\" ContentType=\"image/jpeg\"/>"
            + "<Default Extension=\"gif\" ContentType=\"image/gif\"/>"
            + overrides.map { "<Override PartName=\"\($0.0)\" ContentType=\"\($0.1)\"/>" }.joined()
            + "</Types>"
    }

    func core() -> String {
        let title = QuillInline(document.title).plain
        return """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <cp:coreProperties xmlns:cp="http://schemas.openxmlformats.org/package/2006/metadata/core-properties" \
        xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:dcterms="http://purl.org/dc/terms/" \
        xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">\
        \(title.isEmpty ? "" : "<dc:title>\(QuillDocx.escape(title))</dc:title>")\
        \(document.author.map { "<dc:creator>\(QuillDocx.escape($0))</dc:creator>" } ?? "")\
        <cp:keywords>\(document.form.rawValue)</cp:keywords></cp:coreProperties>
        """
    }

    // MARK: - Styles and numbering

    func stylesPart() -> String {
        let gray = "6E6E73"
        func style(_ id: String, _ name: String, type: String = "paragraph", basedOn: String? = "Normal", next: String? = nil,
                   p: String = "", r: String = "", outline: Int? = nil) -> String {
            var xml = "<w:style w:type=\"\(type)\" w:styleId=\"\(id)\"><w:name w:val=\"\(name)\"/>"
            if let basedOn { xml += "<w:basedOn w:val=\"\(basedOn)\"/>" }
            if let next { xml += "<w:next w:val=\"\(next)\"/>" }
            xml += "<w:qFormat/>"
            let outlineXML = outline.map { "<w:outlineLvl w:val=\"\($0)\"/>" } ?? ""
            if !p.isEmpty || outline != nil { xml += "<w:pPr>\(p)\(outlineXML)</w:pPr>" }
            if !r.isEmpty { xml += "<w:rPr>\(r)</w:rPr>" }
            return xml + "</w:style>"
        }
        let line = Int((layout.lead * 240).rounded())
        let accentColor = "<w:color w:val=\"\(accent)\"/>"
        let monoFont = "<w:rFonts w:ascii=\"\(Self.mono)\" w:hAnsi=\"\(Self.mono)\" w:cs=\"\(Self.mono)\"/>"
        func size(_ em: Double) -> String { "<w:sz w:val=\"\(half(em))\"/><w:szCs w:val=\"\(half(em))\"/>" }
        let resume = document.form == .resume
        let titleSize = resume ? 2.2 : document.form == .worksheet ? 1.9 : document.form == .memo ? 2.3 : document.form == .onepager ? 2.2 : 2.3
        let h1 = resume ? "<w:caps/>" : ""
        let h1Size = resume ? 0.92 : 1.45
        let h1Border = resume ? "<w:pBdr><w:bottom w:val=\"single\" w:sz=\"4\" w:space=\"2\" w:color=\"C8C6C0\"/></w:pBdr>" : ""
        let quoteBorder = "<w:pBdr><w:left w:val=\"single\" w:sz=\"12\" w:space=\"8\" w:color=\"\(accent)\"/></w:pBdr>"
        let calloutBorder = "<w:pBdr><w:left w:val=\"single\" w:sz=\"18\" w:space=\"6\" w:color=\"\(accent)\"/></w:pBdr>"

        let styles = [
            style("Normal", "Normal", basedOn: nil, p: "<w:spacing w:after=\"0\" w:line=\"\(line)\" w:lineRule=\"auto\"/>",
                  r: "<w:rFonts w:ascii=\"\(face)\" w:hAnsi=\"\(face)\" w:cs=\"\(face)\"/>"),
            style("BodyText", "Body Text", next: "BodyText", p: "<w:spacing w:after=\"\(gapAfter)\"/>"),
            style("Title", "Title", next: "Subtitle", p: "<w:keepNext/><w:spacing w:after=\"60\" w:line=\"240\" w:lineRule=\"auto\"/>",
                  r: "<w:b/><w:bCs/>\(accentColor)\(size(titleSize))"),
            style("Subtitle", "Subtitle", next: "BodyText", p: "<w:keepNext/><w:spacing w:after=\"60\"/>", r: "<w:color w:val=\"4A4A4F\"/>\(size(1.12))"),
            style("Byline", "Byline", next: "BodyText", p: "<w:spacing w:after=\"40\"/>", r: "<w:color w:val=\"\(gray)\"/>\(size(0.92))"),
            style("Heading1", "heading 1", next: "BodyText",
                  p: "<w:keepNext/><w:keepLines/>\(h1Border)<w:spacing w:before=\"\(twips(layout.size * h1Size * (resume ? 1.2 : 1.1)))\" w:after=\"\(twips(layout.size * h1Size * 0.4))\" w:line=\"240\" w:lineRule=\"auto\"/>",
                  r: "<w:b/><w:bCs/>\(h1)\(accentColor)\(resume ? "<w:spacing w:val=\"20\"/>" : "")\(size(h1Size))", outline: 0),
            style("Heading2", "heading 2", next: "BodyText",
                  p: "<w:keepNext/><w:keepLines/><w:spacing w:before=\"\(twips(layout.size * 1.1))\" w:after=\"\(twips(layout.size * 0.35))\" w:line=\"240\" w:lineRule=\"auto\"/>",
                  r: "<w:b/><w:bCs/>\(resume ? "<w:color w:val=\"1D1D1F\"/>" : accentColor)\(size(resume ? 1.02 : 1.18))", outline: 1),
            style("Heading3", "heading 3", next: "BodyText",
                  p: "<w:keepNext/><w:keepLines/><w:spacing w:before=\"\(twips(layout.size * 0.8))\" w:after=\"\(twips(layout.size * 0.2))\"/>",
                  r: resume ? "<w:color w:val=\"\(gray)\"/>\(size(0.95))" : "<w:b/><w:bCs/><w:i/><w:iCs/>\(accentColor)", outline: 2),
            style("ListParagraph", "List Paragraph", p: "<w:spacing w:after=\"\(twips(layout.size * 0.2))\"/><w:ind w:left=\"\(twips(layout.size * 1.4))\" w:hanging=\"\(twips(layout.size * 1.1))\"/>"),
            style("Quote", "Quote", next: "BodyText", p: "<w:keepLines/>\(quoteBorder)<w:spacing w:before=\"\(twips(layout.size * 0.4))\" w:after=\"\(twips(layout.size * 0.3))\"/><w:ind w:left=\"\(twips(layout.size))\"/>",
                  r: "<w:i/><w:iCs/>"),
            style("QuoteBy", "Quote Speaker", basedOn: "Quote", next: "BodyText", p: "<w:spacing w:before=\"0\" w:after=\"\(gapAfter)\"/>",
                  r: "<w:i w:val=\"0\"/><w:iCs w:val=\"0\"/><w:color w:val=\"\(gray)\"/>\(size(0.9))"),
            style("Callout", "Callout", next: "BodyText", p: "<w:keepLines/>\(calloutBorder)<w:shd w:val=\"clear\" w:color=\"auto\" w:fill=\"F4F2EC\"/><w:spacing w:before=\"\(twips(layout.size * 0.3))\" w:after=\"\(gapAfter)\"/><w:ind w:left=\"\(twips(layout.size * 0.8))\" w:right=\"\(twips(layout.size * 0.8))\"/>"),
            style("Figure", "Figure", next: "Caption", p: "<w:keepNext/><w:spacing w:before=\"\(twips(layout.size * 0.4))\" w:after=\"60\"/><w:jc w:val=\"center\"/>"),
            style("Caption", "caption", next: "BodyText", p: "<w:spacing w:after=\"\(gapAfter)\"/><w:jc w:val=\"center\"/>", r: "<w:color w:val=\"\(gray)\"/>\(size(0.85))"),
            style("Code", "Code", next: "BodyText", p: "<w:keepLines/><w:shd w:val=\"clear\" w:color=\"auto\" w:fill=\"F6F5F1\"/><w:spacing w:after=\"\(gapAfter)\" w:line=\"240\" w:lineRule=\"auto\"/><w:ind w:left=\"120\" w:right=\"120\"/>",
                  r: "\(monoFont)\(size(0.82))"),
            style("TableText", "Table Text", p: "<w:spacing w:after=\"0\" w:line=\"240\" w:lineRule=\"auto\"/>", r: size(0.92)),
            style("TableAfter", "Table Spacer", p: "<w:spacing w:after=\"\(gapAfter)\" w:line=\"120\" w:lineRule=\"auto\"/>", r: size(0.5)),
            style("SignatureLine", "Signature Line", next: "Signature", p: "<w:keepNext/><w:pBdr><w:bottom w:val=\"single\" w:sz=\"6\" w:space=\"1\" w:color=\"1D1D1F\"/></w:pBdr><w:spacing w:before=\"\(twips(layout.size * 2.6))\" w:after=\"60\"/>"),
            style("Signature", "Signature", next: "BodyText", p: "<w:keepNext/>"),
            style("SignatureTitle", "Signature Title", next: "BodyText", p: "<w:spacing w:after=\"\(gapAfter)\"/>", r: "<w:color w:val=\"\(gray)\"/>\(size(0.9))"),
            style("Rule", "Rule", next: "BodyText", p: "<w:pBdr><w:bottom w:val=\"single\" w:sz=\"6\" w:space=\"1\" w:color=\"C8C6C0\"/></w:pBdr><w:spacing w:before=\"\(twips(layout.size * 0.4))\" w:after=\"\(twips(layout.size * 0.8))\" w:line=\"120\" w:lineRule=\"auto\"/>"),
            style("MemoLine", "Memo Line", p: "<w:tabs><w:tab w:val=\"left\" w:pos=\"1080\"/></w:tabs>"),
            style("PageMark", "Page Mark", r: "<w:rFonts w:ascii=\"Helvetica Neue\" w:hAnsi=\"Helvetica Neue\" w:cs=\"Helvetica Neue\"/><w:color w:val=\"8A8A8E\"/><w:sz w:val=\"17\"/><w:szCs w:val=\"17\"/>"),
            style("TOCHeading", "TOC Heading", basedOn: "Heading2", next: "TOC1"),
            style("TOC1", "toc 1", p: "<w:tabs><w:tab w:val=\"right\" w:leader=\"dot\" w:pos=\"\(twips(columnWidth))\"/></w:tabs><w:spacing w:after=\"40\"/>"),
            style("TOC2", "toc 2", p: "<w:tabs><w:tab w:val=\"right\" w:leader=\"dot\" w:pos=\"\(twips(columnWidth))\"/></w:tabs><w:spacing w:after=\"40\"/><w:ind w:left=\"\(twips(layout.size * 1.2))\"/>"),
            style("Hyperlink", "Hyperlink", type: "character", basedOn: nil, r: "\(accentColor)<w:u w:val=\"single\"/>"),
        ]
        return """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <w:styles xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"><w:docDefaults><w:rPrDefault><w:rPr>\
        <w:rFonts w:ascii="\(face)" w:hAnsi="\(face)" w:eastAsia="\(face)" w:cs="\(face)"/><w:color w:val="1D1D1F"/>\
        <w:sz w:val="\(half(1))"/><w:szCs w:val="\(half(1))"/><w:lang w:val="en-US"/></w:rPr></w:rPrDefault>\
        <w:pPrDefault><w:pPr><w:widowControl/><w:spacing w:after="0" w:line="\(line)" w:lineRule="auto"/></w:pPr></w:pPrDefault></w:docDefaults>\
        \(styles.joined())</w:styles>
        """
    }

    /// One bullet list definition and one numbered; each ordered list is an instance of its own, so each counts from one.
    func numberingPart() -> String {
        let indent = twips(layout.size * 1.4), hanging = twips(layout.size * 1.1)
        func level(_ format: String, _ text: String, font: String? = nil) -> String {
            let rPr = "<w:rPr>" + (font.map { "<w:rFonts w:ascii=\"\($0)\" w:hAnsi=\"\($0)\" w:hint=\"default\"/>" } ?? "") + "<w:color w:val=\"\(accent)\"/></w:rPr>"
            return "<w:lvl w:ilvl=\"0\"><w:start w:val=\"1\"/><w:numFmt w:val=\"\(format)\"/><w:lvlText w:val=\"\(text)\"/><w:lvlJc w:val=\"left\"/>"
                + "<w:pPr><w:ind w:left=\"\(indent)\" w:hanging=\"\(hanging)\"/></w:pPr>\(rPr)</w:lvl>"
        }
        var xml = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <w:numbering xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">\
        <w:abstractNum w:abstractNumId="0"><w:multiLevelType w:val="singleLevel"/>\(level("bullet", "•"))</w:abstractNum>\
        <w:abstractNum w:abstractNumId="1"><w:multiLevelType w:val="singleLevel"/>\(level("decimal", "%1."))</w:abstractNum>\
        <w:num w:numId="1"><w:abstractNumId w:val="0"/></w:num>
        """
        for list in 0..<orderedLists {
            xml += "<w:num w:numId=\"\(list + 2)\"><w:abstractNumId w:val=\"1\"/><w:lvlOverride w:ilvl=\"0\"><w:startOverride w:val=\"1\"/></w:lvlOverride></w:num>"
        }
        return xml + "</w:numbering>"
    }
}
