import Foundation

/// The bracketed places a draft leaves for the person to fill in (`[Hiring Manager's Name]`, `[Date]`), found wherever
/// the document shows text. A Markdown link's words are not one.
enum QuillPlaceholders {
    static func find(in document: QuillDocument) -> [String] {
        var texts = [document.title, document.subtitle, document.author, document.date].compactMap { $0 } + document.from + document.to
        for block in document.blocks {
            texts += [block.text, block.title, block.by].compactMap { $0 } + block.items + block.rows.flatMap { $0 }
            texts += block.fields.flatMap { [$0.label, $0.value] }
        }
        var found: [String] = []
        for text in texts {
            for place in places(in: text) where !found.contains(place) { found.append(place) }
        }
        return found
    }

    static func places(in text: String) -> [String] {
        var found: [String] = []
        let chars = Array(text)
        var i = 0
        while i < chars.count {
            guard chars[i] == "[", let close = chars[(i + 1)...].firstIndex(of: "]") else { i += 1; continue }
            let inner = String(chars[(i + 1)..<close])
            let isLink = close + 1 < chars.count && chars[close + 1] == "("
            if !isLink, !inner.isEmpty, inner.count <= 60, !inner.contains("["), inner.first?.isLetter == true || inner.first == "$" {
                found.append("[\(inner)]")
            }
            i = close + 1
        }
        return found
    }
}
