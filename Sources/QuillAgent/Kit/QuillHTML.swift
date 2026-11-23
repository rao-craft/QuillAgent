import Foundation

/// Text made safe for HTML, and a block's inline runs as HTML.
enum QuillHTML {
    static func escape(_ text: String) -> String {
        var out = ""
        out.reserveCapacity(text.count)
        for c in text {
            switch c {
            case "&": out += "&amp;"
            case "<": out += "&lt;"
            case ">": out += "&gt;"
            case "\"": out += "&quot;"
            default: out.append(c)
            }
        }
        return out
    }

    /// The runs of `text` as HTML: bold, italic, code and links; a link only to http, https or mailto.
    static func inline(_ text: String) -> String {
        QuillInline(text).runs.map { run in
            var html = escape(run.text)
            if run.code { html = "<code>\(html)</code>" }
            if run.italic { html = "<em>\(html)</em>" }
            if run.bold { html = "<strong>\(html)</strong>" }
            if let link = run.link, isSafe(link) { html = "<a href=\"\(escape(link))\">\(html)</a>" }
            return html
        }.joined()
    }

    static func isSafe(_ link: String) -> Bool {
        let lower = link.lowercased()
        return lower.hasPrefix("https://") || lower.hasPrefix("http://") || lower.hasPrefix("mailto:") || lower.hasPrefix("#")
    }
}
