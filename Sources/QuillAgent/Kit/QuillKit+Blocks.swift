import Foundation

extension QuillKit {
    /// The body, one element per block, each marked `data-q="<index>"` so the pages can be measured block by block. A
    /// block after a `break`, or one the layout pushed, starts a new page.
    static func blocks(_ document: QuillDocument, layout: QuillLayout, pictures: [Int: String]) -> String {
        var html = ""
        var breakNext = false
        for (index, block) in document.blocks.enumerated() {
            if block.kind == .break { breakNext = true; continue }
            let push = breakNext || layout.pushed.contains(index)
            breakNext = false
            html += element(block, index: index, push: push, picture: pictures[index])
        }
        return html
    }

    static func element(_ block: QuillBlock, index: Int, push: Bool, picture: String?) -> String {
        let mark = "data-q=\"\(index)\" id=\"b\(index)\"" + (push ? " class=\"push\"" : "")
        let text = block.text.map(QuillHTML.inline) ?? ""
        switch block.kind {
        case .heading:
            let tag = "h\(block.depth)"
            return "<\(tag) \(mark)>\(text)</\(tag)>"
        case .paragraph:
            return text.isEmpty ? "" : "<p \(mark)>\(text)</p>"
        case .list:
            guard !block.items.isEmpty else { return "" }
            let tag = block.ordered == true ? "ol" : "ul"
            return "<\(tag) \(mark)>" + block.items.map { "<li>\(QuillHTML.inline($0))</li>" }.joined() + "</\(tag)>"
        case .table:
            guard let header = block.rows.first else { return "" }
            let width = block.rows.map(\.count).max() ?? header.count
            func cells(_ row: [String], tag: String) -> String {
                (0..<width).map { "<\(tag)>\(QuillHTML.inline($0 < row.count ? row[$0] : ""))</\(tag)>" }.joined()
            }
            let body = block.rows.dropFirst().map { "<tr>\(cells($0, tag: "td"))</tr>" }.joined()
            return "<table \(mark)><thead><tr>\(cells(header, tag: "th"))</tr></thead><tbody>\(body)</tbody></table>"
        case .quote:
            guard !text.isEmpty else { return "" }
            let cite = block.by.map { "<cite>— \(QuillHTML.escape($0))</cite>" } ?? ""
            return "<blockquote \(mark)><p>\(text)</p>\(cite)</blockquote>"
        case .callout:
            guard !text.isEmpty || block.title != nil else { return "" }
            let title = block.title.map { "<strong class=\"title\">\(QuillHTML.inline($0))</strong>" } ?? ""
            return "<aside \(mark)>\(title)\(text.isEmpty ? "" : "<p>\(text)</p>")</aside>"
        case .figure:
            guard let picture else {
                // A figure whose picture is not there keeps its place, so the page reads as it will.
                let caption = text.isEmpty ? "" : " — \(text)"
                return "<aside \(mark)><strong class=\"title\">Figure</strong><p>[\(QuillHTML.escape(block.path ?? "picture"))]\(caption)</p></aside>"
            }
            let caption = text.isEmpty ? "" : "<figcaption>\(text)</figcaption>"
            return "<figure \(mark)><img src=\"\(picture)\" alt=\"\(QuillHTML.escape(block.text.map { QuillInline($0).plain } ?? ""))\">\(caption)</figure>"
        case .fields:
            guard !block.fields.isEmpty else { return "" }
            let rows = block.fields.map { field in
                let value = field.value.isEmpty ? "<dd class=\"blank\"></dd>" : "<dd>\(QuillHTML.inline(field.value))</dd>"
                return "<dt>\(QuillHTML.inline(field.label))</dt>\(value)"
            }
            return "<dl class=\"fields\" \(mark)>\(rows.joined())</dl>"
        case .signature:
            let by = block.by.map { "<div class=\"by\">\(QuillHTML.escape($0))</div>" } ?? ""
            return "<div class=\"sign\" \(mark)><div class=\"line\"></div><div>\(text)</div>\(by)</div>"
        case .code:
            return "<pre \(mark)><code>\(QuillHTML.escape(block.text ?? ""))</code></pre>"
        case .rule:
            return "<hr \(mark)>"
        case .break:
            return ""
        }
    }
}
