import Foundation

/// Markdown read as a draft, with no model: a document already written is laid out as written. The first `#` heading at
/// the top is the title and the rest move up a level; front matter (`title:`, `subtitle:`, `author:`, `date:`, `form:`)
/// fills the first page.
enum QuillMarkdownReader {
    static func read(_ markdown: String, form: QuillForm?, name: String) -> QuillDocument {
        var lines = markdown.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
        var meta: [String: String] = [:]
        if lines.first?.trimmingCharacters(in: .whitespaces) == "---", let end = lines.dropFirst().firstIndex(where: { $0.trimmingCharacters(in: .whitespaces) == "---" }) {
            for line in lines[1..<end] {
                guard let colon = line.firstIndex(of: ":") else { continue }
                let key = line[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
                let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
                if !value.isEmpty { meta[key] = value }
            }
            lines = Array(lines[(end + 1)...])
        }
        var blocks = parse(lines)

        // The title: front matter's, or a lone `#` heading at the top, whose followers move up a level.
        var title = meta["title"] ?? ""
        let topLevel = blocks.filter { $0.kind == .heading && $0.depth == 1 }.count
        if let first = blocks.first(where: { $0.kind != .rule }), first.kind == .heading, first.level == 1, topLevel == 1 || title.isEmpty,
           let index = blocks.firstIndex(of: first) {
            if title.isEmpty { title = first.text ?? "" }
            blocks.remove(at: index)
            if topLevel == 1 {
                blocks = blocks.map { block in
                    guard block.kind == .heading else { return block }
                    var moved = block
                    moved.level = max(1, (block.level ?? 1) - 1)
                    return moved
                }
            }
        }
        if title.isEmpty { title = name }
        // An italic line right under the title is its subtitle.
        var subtitle = meta["subtitle"]
        if subtitle == nil, let first = blocks.first, first.kind == .paragraph, let text = first.text,
           (text.hasPrefix("*") && text.hasSuffix("*") && !text.hasPrefix("**")) || (text.hasPrefix("_") && text.hasSuffix("_")) {
            subtitle = String(text.dropFirst().dropLast())
            blocks.removeFirst()
        }
        let chosen = form ?? meta["form"].flatMap(QuillForm.init(loose:)) ?? .report
        var style = QuillStyle()
        if let accent = meta["accent"] { style.accent = accent }
        if let contents = meta["contents"] { style.contents = ["true", "yes"].contains(contents.lowercased()) }
        return QuillDocument(form: chosen, title: title, subtitle: subtitle, author: meta["author"], date: meta["date"],
                             style: style, blocks: blocks)
    }

    /// The body's blocks.
    static func parse(_ lines: [String]) -> [QuillBlock] {
        var blocks: [QuillBlock] = []
        var paragraph: [String] = []
        var i = 0
        func flush() {
            let text = paragraph.joined(separator: " ").trimmingCharacters(in: .whitespaces)
            if !text.isEmpty { blocks.append(.paragraph(text)) }
            paragraph = []
        }
        while i < lines.count {
            let line = lines[i]
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { flush(); i += 1; continue }
            if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") {
                flush()
                let fence = String(trimmed.prefix(3))
                var code: [String] = []
                i += 1
                while i < lines.count, !lines[i].trimmingCharacters(in: .whitespaces).hasPrefix(fence) { code.append(lines[i]); i += 1 }
                blocks.append(QuillBlock(.code, text: code.joined(separator: "\n")))
                i += 1
                continue
            }
            if trimmed == QuillMarkdownWriter.pageBreak || trimmed == "\\pagebreak" || trimmed == "\\newpage" {
                flush(); blocks.append(QuillBlock(.break)); i += 1; continue
            }
            if let heading = heading(trimmed) {
                flush(); blocks.append(heading); i += 1; continue
            }
            if isRule(trimmed) {
                flush(); blocks.append(QuillBlock(.rule)); i += 1; continue
            }
            if let figure = figure(trimmed) {
                flush(); blocks.append(figure); i += 1; continue
            }
            if trimmed.hasPrefix(">") {
                flush()
                var quoted: [String] = []
                while i < lines.count, lines[i].trimmingCharacters(in: .whitespaces).hasPrefix(">") {
                    var inner = lines[i].trimmingCharacters(in: .whitespaces).dropFirst()
                    if inner.hasPrefix(" ") { inner = inner.dropFirst() }
                    quoted.append(String(inner))
                    i += 1
                }
                blocks.append(quote(quoted))
                continue
            }
            if trimmed.hasPrefix("|"), i + 1 < lines.count, isTableRule(lines[i + 1]) {
                flush()
                var rows = [cells(trimmed)]
                i += 2
                while i < lines.count, lines[i].trimmingCharacters(in: .whitespaces).hasPrefix("|") {
                    rows.append(cells(lines[i].trimmingCharacters(in: .whitespaces)))
                    i += 1
                }
                blocks.append(QuillBlock(.table, rows: rows))
                continue
            }
            if let first = item(trimmed) {
                flush()
                var items = [first.text]
                let ordered = first.ordered
                i += 1
                while i < lines.count {
                    let next = lines[i].trimmingCharacters(in: .whitespaces)
                    if let more = item(next) { items.append(more.text); i += 1; continue }
                    // A line indented under an item continues it.
                    if !next.isEmpty, lines[i].hasPrefix("  ") || lines[i].hasPrefix("\t") { items[items.count - 1] += " " + next; i += 1; continue }
                    break
                }
                blocks.append(QuillBlock(.list, items: items, ordered: ordered))
                continue
            }
            // Fields: a run of `**Label:** value` lines.
            if let field = field(trimmed), i + 1 < lines.count, self.field(lines[i + 1].trimmingCharacters(in: .whitespaces)) != nil {
                flush()
                var fields = [field]
                i += 1
                while i < lines.count, let more = self.field(lines[i].trimmingCharacters(in: .whitespaces)) { fields.append(more); i += 1 }
                blocks.append(QuillBlock(.fields, fields: fields))
                continue
            }
            paragraph.append(trimmed.hasSuffix("  ") ? trimmed : trimmed)
            i += 1
        }
        flush()
        return blocks
    }

    static func heading(_ line: String) -> QuillBlock? {
        let hashes = line.prefix { $0 == "#" }.count
        guard (1...6).contains(hashes), line.dropFirst(hashes).hasPrefix(" ") else { return nil }
        let text = line.dropFirst(hashes).trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "#")).trimmingCharacters(in: .whitespaces)
        return .heading(text, level: min(hashes, 4))
    }

    static func isRule(_ line: String) -> Bool {
        let marks = line.filter { !$0.isWhitespace }
        guard marks.count >= 3, let first = marks.first, "-*_".contains(first) else { return false }
        return marks.allSatisfy { $0 == first }
    }

    static func figure(_ line: String) -> QuillBlock? {
        guard line.hasPrefix("!["), line.hasSuffix(")"), let close = line.range(of: "](") else { return nil }
        let caption = String(line[line.index(line.startIndex, offsetBy: 2)..<close.lowerBound])
        var path = String(line[close.upperBound..<line.index(before: line.endIndex)])
        if let space = path.firstIndex(of: " ") { path = String(path[..<space]) }
        return QuillBlock(.figure, text: caption.isEmpty ? nil : caption, path: path)
    }

    /// A quote, or a callout when it opens with `[!NOTE]` or a bold line alone.
    static func quote(_ lines: [String]) -> QuillBlock {
        var lines = lines
        if let first = lines.first?.trimmingCharacters(in: .whitespaces) {
            if first.hasPrefix("[!"), let close = first.firstIndex(of: "]") {
                let title = first[first.index(first.startIndex, offsetBy: 2)..<close].lowercased().capitalized
                let rest = (String(first[first.index(after: close)...]).trimmingCharacters(in: .whitespaces)
                            + " " + lines.dropFirst().joined(separator: " ")).trimmingCharacters(in: .whitespaces)
                return QuillBlock(.callout, text: rest.isEmpty ? nil : rest, title: title)
            }
            if first.hasPrefix("**"), first.hasSuffix("**"), first.count > 4, lines.count > 1 {
                let title = String(first.dropFirst(2).dropLast(2))
                let rest = lines.dropFirst().map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }.joined(separator: " ")
                return QuillBlock(.callout, text: rest, title: title)
            }
        }
        var by: String?
        if let last = lines.last?.trimmingCharacters(in: .whitespaces), last.hasPrefix("—") || last.hasPrefix("-- ") || last.hasPrefix("– ") {
            by = last.trimmingCharacters(in: CharacterSet(charactersIn: "—–- "))
            lines.removeLast()
        }
        let text = lines.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }.joined(separator: " ")
        return QuillBlock(.quote, text: text, by: by)
    }

    static func isTableRule(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        return trimmed.hasPrefix("|") && trimmed.contains("-") && trimmed.allSatisfy { "|-: ".contains($0) }
    }

    static func cells(_ line: String) -> [String] {
        var inner = line
        if inner.hasPrefix("|") { inner.removeFirst() }
        if inner.hasSuffix("|") { inner.removeLast() }
        var cells: [String] = [], current = ""
        var escaped = false
        for c in inner {
            if escaped { current.append(c); escaped = false; continue }
            if c == "\\" { escaped = true; continue }
            if c == "|" { cells.append(current.trimmingCharacters(in: .whitespaces)); current = ""; continue }
            current.append(c)
        }
        cells.append(current.trimmingCharacters(in: .whitespaces))
        return cells
    }

    static func item(_ line: String) -> (text: String, ordered: Bool)? {
        for mark in ["- ", "* ", "+ "] where line.hasPrefix(mark) {
            var text = String(line.dropFirst(2))
            if text.hasPrefix("[ ] ") || text.hasPrefix("[x] ") { text = String(text.dropFirst(4)) }
            return (text, false)
        }
        let digits = line.prefix { $0.isNumber }
        if !digits.isEmpty, digits.count <= 3 {
            let rest = line.dropFirst(digits.count)
            if rest.hasPrefix(". ") || rest.hasPrefix(") ") { return (String(rest.dropFirst(2)), true) }
        }
        return nil
    }

    static func field(_ line: String) -> QuillBlock.Field? {
        guard line.hasPrefix("**"), let close = line.range(of: ":**") ?? line.range(of: "**:") else { return nil }
        let label = String(line[line.index(line.startIndex, offsetBy: 2)..<close.lowerBound])
        guard !label.isEmpty, label.count <= 40 else { return nil }
        var value = line[close.upperBound...].trimmingCharacters(in: .whitespaces)
        if value.allSatisfy({ $0 == "_" }) { value = "" }
        return QuillBlock.Field(label: label, value: value)
    }
}
