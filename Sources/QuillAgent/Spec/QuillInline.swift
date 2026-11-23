import Foundation

/// A block's text read as runs: plain, bold, italic, code and links. The one inline markup a draft may use, read the
/// same way by every writer so a word bold in the PDF is bold in Word and in Markdown.
///
/// PIN: MARKS HUG THEIR WORDS. As in CommonMark, `*` or `**` opens only before a non-space and closes only after one, so
/// "5 * 3" stays arithmetic; a mark with no partner is kept as written.
struct QuillInline: Equatable {
    struct Run: Equatable {
        var text: String
        var bold = false
        var italic = false
        var code = false
        var link: String?
    }

    var runs: [Run]

    init(_ text: String) {
        let chars = Array(text)
        var runs: [Run] = []
        var plain = ""
        var bold = false, italic = false
        var i = 0

        func flush() {
            if !plain.isEmpty { runs.append(Run(text: plain, bold: bold, italic: italic)); plain = "" }
        }
        func isSpace(_ index: Int) -> Bool { index < 0 || index >= chars.count || chars[index].isWhitespace }
        func at(_ index: Int, _ mark: [Character]) -> Bool {
            index >= 0 && index + mark.count <= chars.count && Array(chars[index..<index + mark.count]) == mark
        }
        /// A closing `mark` after `start`: preceded by a non-space, and (for `*`) not half of a `**`.
        func closer(_ mark: [Character], after start: Int) -> Bool {
            var j = start
            while j < chars.count {
                if at(j, mark), !isSpace(j - 1) {
                    if mark.count == 1, mark[0] == "*", at(j + 1, ["*"]) || at(j - 1, ["*"]) { j += 1; continue }
                    return true
                }
                j += 1
            }
            return false
        }
        /// The link's `)` that balances its `(`.
        func linkEnd(from open: Int) -> Int? {
            var depth = 0
            var j = open
            while j < chars.count {
                if chars[j] == "(" { depth += 1 }
                if chars[j] == ")" { depth -= 1; if depth == 0 { return j } }
                j += 1
            }
            return nil
        }

        while i < chars.count {
            let c = chars[i]
            if c == "`", let end = chars[(i + 1)...].firstIndex(of: "`") {
                flush()
                runs.append(Run(text: String(chars[(i + 1)..<end]), bold: bold, italic: italic, code: true))
                i = end + 1
                continue
            }
            if c == "[", let close = chars[(i + 1)...].firstIndex(of: "]"), close + 1 < chars.count, chars[close + 1] == "(",
               let end = linkEnd(from: close + 1) {
                flush()
                runs.append(Run(text: String(chars[(i + 1)..<close]), bold: bold, italic: italic,
                                link: String(chars[(close + 2)..<end]).trimmingCharacters(in: .whitespaces)))
                i = end + 1
                continue
            }
            if at(i, ["*", "*"]) {
                if bold, !isSpace(i - 1) { flush(); bold = false; i += 2; continue }
                if !bold, !isSpace(i + 2), closer(["*", "*"], after: i + 3) { flush(); bold = true; i += 2; continue }
            }
            if c == "*" || c == "_", !at(i, ["*", "*"]) || (!bold && italic) {
                let inWord = c == "_" && !isSpace(i - 1) && !isSpace(i + 1) && chars[i - 1].isLetter && chars[i + 1].isLetter
                if !inWord {
                    if italic, !isSpace(i - 1) { flush(); italic = false; i += 1; continue }
                    if !italic, !isSpace(i + 1), closer([c], after: i + 2) { flush(); italic = true; i += 1; continue }
                }
            }
            plain.append(c)
            i += 1
        }
        flush()
        self.runs = runs
    }

    /// The text with every mark taken out.
    var plain: String { runs.map(\.text).joined() }
}
