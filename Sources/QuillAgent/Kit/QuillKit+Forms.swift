import Foundation

extension QuillKit {
    /// What the first page carries before the body, by form: a letter's addresses and date, a memo's To and From, a
    /// resume's name and contact line, a report's title block.
    static func head(_ document: QuillDocument) -> String {
        let title = QuillHTML.inline(document.title)
        let subtitle = document.subtitle.map { "<div class=\"subtitle\">\(QuillHTML.inline($0))</div>" } ?? ""
        func lines(_ lines: [String], _ cls: String) -> String {
            lines.isEmpty ? "" : "<div class=\"\(cls)\">" + lines.map { "<div>\(QuillHTML.inline($0))</div>" }.joined() + "</div>"
        }
        let date = document.date.map { "<div class=\"date\">\(QuillHTML.escape($0))</div>" } ?? ""
        switch document.form {
        case .letter:
            let subject = document.title.isEmpty ? "" : "<div class=\"subject\">\(title)</div>"
            return "<header class=\"head\">\(lines(document.from, "from"))\(date)\(lines(document.to, "to"))\(subject)</header>"
        case .memo:
            var rows: [(String, String)] = []
            if !document.to.isEmpty { rows.append(("To", document.to.map(QuillHTML.inline).joined(separator: ", "))) }
            if !document.from.isEmpty { rows.append(("From", document.from.map(QuillHTML.inline).joined(separator: ", "))) }
            else if let author = document.author { rows.append(("From", QuillHTML.inline(author))) }
            if let day = document.date { rows.append(("Date", QuillHTML.escape(day))) }
            if !document.title.isEmpty { rows.append(("Subject", title)) }
            let table = rows.map { "<dt>\($0.0)</dt><dd>\($0.1)</dd>" }.joined()
            return "<header class=\"head\"><div class=\"word\">Memo</div><dl class=\"memo\">\(table)</dl></header>"
        case .resume:
            let contact = document.from.isEmpty ? "" : "<div class=\"contact\">" + document.from.map(QuillHTML.inline).joined(separator: " · ") + "</div>"
            return "<header class=\"head\"><div class=\"title\">\(title)</div>\(subtitle)\(contact)</header>"
        case .worksheet:
            let blanks = "<div class=\"blanks\"><span>Name</span><span class=\"blank\"></span><span>Date</span><span class=\"blank short\"></span></div>"
            return "<header class=\"head\"><div class=\"title\">\(title)</div>\(subtitle)\(blanks)</header>"
        case .report, .proposal, .contract, .onepager:
            let byline = [document.author, document.date].compactMap { $0 }.map(QuillHTML.escape).joined(separator: " · ")
            let by = byline.isEmpty ? "" : "<div class=\"byline\">\(byline)</div>"
            let to = document.to.isEmpty ? "" : "<div class=\"prepared\">Prepared for " + document.to.map(QuillHTML.inline).joined(separator: ", ") + "</div>"
            return "<header class=\"head\"><div class=\"title\">\(title)</div>\(subtitle)\(to)\(by)</header>"
        }
    }

    /// Each form's first page.
    static func formStyle(_ document: QuillDocument) -> String {
        let common = """
        .head { break-inside: avoid; }
        .head .title { font-weight: 700; color: var(--accent); line-height: 1.12; }
        .head .subtitle { color: #4a4a4f; margin-top: 0.3em; }
        """
        switch document.form {
        case .letter:
            return common + """
            .head { margin-bottom: 1.6em; }
            .head .from { margin-bottom: 1.4em; }
            .head .date { margin-bottom: 1.4em; }
            .head .to { margin-bottom: 1.4em; }
            .head .subject { font-weight: 700; }
            """
        case .memo:
            return common + """
            .head { margin-bottom: 1.4em; padding-bottom: 0.9em; border-bottom: 1.5px solid var(--accent); }
            .head .word { font-size: 2.3em; font-weight: 700; color: var(--accent); letter-spacing: -0.01em; margin-bottom: 0.4em; }
            dl.memo { display: grid; grid-template-columns: max-content 1fr; column-gap: 1.2em; row-gap: 0.25em; margin: 0; }
            dl.memo dt { font-weight: 700; color: #6e6e73; text-transform: uppercase; font-size: 0.82em; letter-spacing: 0.06em; padding-top: 0.15em; }
            dl.memo dd { margin: 0; }
            """
        case .resume:
            return common + """
            .head { margin-bottom: 1em; padding-bottom: 0.7em; border-bottom: 1px solid var(--accent); }
            .head .title { font-size: 2.2em; letter-spacing: -0.01em; }
            .head .subtitle { font-size: 1.1em; }
            .head .contact { margin-top: 0.5em; color: #4a4a4f; font-size: 0.92em; }
            h1 { font-size: 0.92em; text-transform: uppercase; letter-spacing: 0.1em; margin: 1.2em 0 0.45em;
              padding-bottom: 0.2em; border-bottom: 0.5px solid #c8c6c0; }
            h2 { font-size: 1.02em; margin: 0.7em 0 0.1em; color: #1d1d1f; }
            h3 { font-size: 0.95em; font-style: normal; font-weight: 400; color: #6e6e73; margin: 0 0 0.3em; }
            """
        case .worksheet:
            return common + """
            .head { margin-bottom: 1.4em; }
            .head .title { font-size: 1.9em; }
            .head .blanks { display: flex; gap: 0.6em; align-items: flex-end; margin-top: 1em; }
            .head .blanks .blank { flex: 1; border-bottom: 0.75px solid #1d1d1f; height: 1.1em; }
            .head .blanks .blank.short { flex: 0 0 22%; }
            """
        case .onepager:
            return common + """
            .head { margin: 0 0 1.2em; padding: 1.1em 1.2em; background: var(--accent); color: #fff; border-radius: 3px; }
            .head .title { color: #fff; font-size: 2.2em; }
            .head .subtitle { color: rgba(255,255,255,0.86); font-size: 1.1em; }
            .head .byline, .head .prepared { color: rgba(255,255,255,0.75); margin-top: 0.5em; font-size: 0.9em; }
            """
        case .report, .proposal, .contract:
            return common + """
            .head { margin-bottom: 1.6em; padding-bottom: 1em; border-bottom: 1.5px solid var(--accent); }
            .head .title { font-size: 2.3em; letter-spacing: -0.01em; }
            .head .subtitle { font-size: 1.15em; }
            .head .prepared { margin-top: 0.8em; color: #4a4a4f; }
            .head .byline { margin-top: 0.4em; color: #6e6e73; font-size: 0.92em; }
            """
        }
    }

    /// What runs along a page's foot (and, for long forms, its head), page `page` of `pages`: nothing on a one-page
    /// document's only page.
    static func marks(_ document: QuillDocument, page: Int, pages: Int) -> (head: String?, foot: String?) {
        guard pages > 1 else { return (nil, nil) }
        let title = QuillInline(document.title).plain
        switch document.form {
        case .letter:
            return (nil, page == 1 ? nil : "Page \(page)")
        case .resume:
            return (nil, title.isEmpty ? "\(page) of \(pages)" : "\(title) · \(page) of \(pages)")
        case .report, .proposal, .contract, .worksheet:
            return (page == 1 || title.isEmpty ? nil : title, "\(page) of \(pages)")
        case .memo, .onepager:
            return (nil, "\(page) of \(pages)")
        }
    }
}
