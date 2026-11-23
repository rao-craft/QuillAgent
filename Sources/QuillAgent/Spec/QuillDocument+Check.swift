import Foundation

extension QuillDocument {
    /// The limits a draft is held to before it is laid out.
    enum Limits {
        static let title = 100
        static let paragraph = 1_600
        static let items = 24
        static let rows = 60
        static let columns = 7
        static let blocks = 160
    }

    /// What the draft breaks before any page is laid out, as findings for the model.
    func check() -> [QuillFinding] {
        var found: [QuillFinding] = []
        let body = blocks.filter { $0.kind != .rule && $0.kind != .break }
        if body.isEmpty { found.append(QuillFinding(.limit, "the document has no body: write its blocks")) }
        if title.count > Limits.title { found.append(QuillFinding(.limit, "the title is \(title.count) characters: at most \(Limits.title)")) }
        if form == .letter, !body.contains(where: { $0.kind == .paragraph }) {
            found.append(QuillFinding(.limit, "a letter needs paragraphs: a salutation, the body and a closing"))
        }
        if form == .letter, blocks.contains(where: { $0.kind == .heading }) {
            found.append(QuillFinding(.limit, "a letter has no headings: write them as paragraphs"))
        }
        if blocks.count > Limits.blocks { found.append(QuillFinding(.limit, "\(blocks.count) blocks: at most \(Limits.blocks)")) }
        for (index, block) in blocks.enumerated() {
            let name = QuillPaging.describe(self, index)
            if let text = block.text, block.kind == .paragraph, text.count > Limits.paragraph {
                found.append(QuillFinding(.limit, block: index, "\(name) is \(text.count) characters: split it in two"))
            }
            if block.items.count > Limits.items { found.append(QuillFinding(.limit, block: index, "\(name) has \(block.items.count) items: at most \(Limits.items)")) }
            if block.rows.count > Limits.rows { found.append(QuillFinding(.limit, block: index, "\(name) has \(block.rows.count) rows: at most \(Limits.rows)")) }
            if let width = block.rows.map(\.count).max(), width > Limits.columns {
                found.append(QuillFinding(.limit, block: index, "\(name) has \(width) columns: at most \(Limits.columns)"))
            }
            if block.kind == .heading, (block.text ?? "").isEmpty { found.append(QuillFinding(.limit, block: index, "\(name) is a heading with no words")) }
            if block.kind == .heading, let text = block.text, text.hasPrefix("#") {
                found.append(QuillFinding(.limit, block: index, "\(name) starts with #: a heading's text is its words alone"))
            }
        }
        return found
    }

    /// The draft as it can be drawn: headings cleared of Markdown marks, empty blocks dropped.
    func cleaned() -> QuillDocument {
        var document = self
        document.blocks = blocks.compactMap { block in
            var block = block
            if block.kind == .heading, let text = block.text {
                block.text = text.trimmingCharacters(in: CharacterSet(charactersIn: "# ")).nilIfEmpty
            }
            switch block.kind {
            case .paragraph, .heading, .quote, .code: return block.text == nil ? nil : block
            case .list: return block.items.isEmpty ? nil : block
            case .table: return block.rows.isEmpty ? nil : block
            case .fields: return block.fields.isEmpty ? nil : block
            case .callout: return block.text == nil && block.title == nil ? nil : block
            default: return block
            }
        }
        return document
    }
}
