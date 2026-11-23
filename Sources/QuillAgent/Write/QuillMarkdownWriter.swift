import Foundation

/// The draft as Markdown: the same blocks, in the markup a draft's text already uses. `QuillMarkdownReader` reads it
/// back to the same blocks.
enum QuillMarkdownWriter {
    static let pageBreak = "<!-- pagebreak -->"

    static func write(_ document: QuillDocument) -> String {
        var parts: [String] = []
        switch document.form {
        case .letter:
            if !document.from.isEmpty { parts.append(lines(document.from)) }
            if let date = document.date { parts.append(date) }
            if !document.to.isEmpty { parts.append(lines(document.to)) }
            if !document.title.isEmpty { parts.append("**\(document.title)**") }
        case .memo:
            parts.append("# \(document.title.isEmpty ? "Memo" : document.title)")
            var rows: [String] = []
            if !document.to.isEmpty { rows.append("**To:** " + document.to.joined(separator: ", ")) }
            if !document.from.isEmpty { rows.append("**From:** " + document.from.joined(separator: ", ")) }
            else if let author = document.author { rows.append("**From:** \(author)") }
            if let date = document.date { rows.append("**Date:** \(date)") }
            if !rows.isEmpty { parts.append(rows.joined(separator: "  \n")) }
        default:
            // The byline rides front matter, so the Markdown reads back to the same draft.
            var meta = ["form: \(document.form.rawValue)"]
            if let author = document.author { meta.append("author: \(author)") }
            if let date = document.date { meta.append("date: \(date)") }
            parts.append((["---"] + meta + ["---"]).joined(separator: "\n"))
            if !document.title.isEmpty { parts.append("# \(document.title)") }
            if let subtitle = document.subtitle { parts.append("*\(subtitle)*") }
            if document.form == .resume, !document.from.isEmpty { parts.append(document.from.joined(separator: " · ")) }
            if !document.to.isEmpty, document.form != .resume { parts.append("Prepared for " + document.to.joined(separator: ", ")) }
        }
        for block in document.blocks {
            if let text = markdown(block) { parts.append(text) }
        }
        return parts.joined(separator: "\n\n") + "\n"
    }

    static func lines(_ lines: [String]) -> String { lines.joined(separator: "  \n") }

    static func markdown(_ block: QuillBlock) -> String? {
        let text = block.text ?? ""
        switch block.kind {
        case .heading: return String(repeating: "#", count: block.depth + 1) + " " + text
        case .paragraph: return text.isEmpty ? nil : text
        case .list:
            guard !block.items.isEmpty else { return nil }
            return block.items.enumerated().map { (block.ordered == true ? "\($0.offset + 1). " : "- ") + $0.element }.joined(separator: "\n")
        case .table:
            guard let header = block.rows.first else { return nil }
            let width = block.rows.map(\.count).max() ?? header.count
            func row(_ cells: [String]) -> String {
                "| " + (0..<width).map { $0 < cells.count ? cells[$0].replacingOccurrences(of: "|", with: "\\|") : "" }.joined(separator: " | ") + " |"
            }
            return ([row(header), "| " + Array(repeating: "---", count: width).joined(separator: " | ") + " |"]
                    + block.rows.dropFirst().map(row)).joined(separator: "\n")
        case .quote:
            guard !text.isEmpty else { return nil }
            return "> \(text)" + (block.by.map { "\n>\n> — \($0)" } ?? "")
        case .callout:
            let title = block.title.map { "> **\($0)**" }
            return ([title] + (text.isEmpty ? [] : ["> \(text)"])).compactMap { $0 }.joined(separator: "\n>\n")
        case .figure:
            return "![\(text)](\(block.path ?? ""))"
        case .fields:
            guard !block.fields.isEmpty else { return nil }
            return block.fields.map { "**\($0.label):** " + ($0.value.isEmpty ? "______________________" : $0.value) }.joined(separator: "  \n")
        case .signature:
            return (["______________________________", text] + (block.by.map { [$0] } ?? [])).filter { !$0.isEmpty }.joined(separator: "  \n")
        case .code:
            return "```\n\(text)\n```"
        case .rule:
            return "---"
        case .break:
            return pageBreak
        }
    }
}
