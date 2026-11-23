import AppKit
import Foundation
import PDFKit

/// The files a document is drawn from, read as text: Markdown and plain text as written, Word, RTF and HTML through
/// AppKit's own readers, a PDF's text through PDFKit. A folder gives its text files, one level down.
struct QuillSources {
    struct Source: Equatable {
        let path: String
        let url: URL
        let text: String
        var isMarkdown: Bool { ["md", "markdown"].contains(url.pathExtension.lowercased()) }
        var name: String { url.deletingPathExtension().lastPathComponent }
    }

    let sources: [Source]

    /// Each source's share of a model's prompt, and the whole digest's, in characters.
    static let perSource = 12_000
    static let total = 30_000
    static let textTypes: Set<String> = ["md", "markdown", "txt", "text", "csv", "tsv", "json", "yaml", "yml", "xml", "swift", "py",
                                         "js", "ts", "rb", "go", "rs", "java", "kt", "c", "h", "m", "cpp", "sh", "toml", "ini", "log", "tex"]
    static let richTypes: Set<String> = ["docx", "doc", "rtf", "rtfd", "html", "htm", "odt", "webarchive"]

    static func read(_ paths: [String], in folder: URL) throws -> QuillSources {
        var sources: [Source] = []
        for path in paths where !path.trimmingCharacters(in: .whitespaces).isEmpty {
            let url = QuillPictures.url(path, in: folder)
            var isFolder: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isFolder) else { throw QuillError.noSource(path) }
            if isFolder.boolValue {
                let inside = (try? FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? []
                for file in inside.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }).prefix(24) {
                    let type = file.pathExtension.lowercased()
                    guard textTypes.contains(type) || richTypes.contains(type) || type == "pdf", let text = text(of: file) else { continue }
                    sources.append(Source(path: path + "/" + file.lastPathComponent, url: file, text: text))
                }
                continue
            }
            guard let text = text(of: url) else { throw QuillError.unreadableSource(path) }
            sources.append(Source(path: path, url: url, text: text))
        }
        return QuillSources(sources: sources)
    }

    static func text(of url: URL) -> String? {
        let type = url.pathExtension.lowercased()
        if type == "pdf" {
            guard let document = PDFDocument(url: url) else { return nil }
            return document.string?.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if richTypes.contains(type) {
            guard let read = try? NSAttributedString(url: url, options: [:], documentAttributes: nil) else { return nil }
            return read.string.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard let data = try? Data(contentsOf: url), let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else { return nil }
        // A binary file read as text is not a source.
        if text.contains("\u{0}") { return nil }
        return text
    }

    /// The sources as one block of text for a model, each under its path, cut to fit.
    var digest: String {
        var left = Self.total
        var parts: [String] = []
        for source in sources where left > 200 {
            let share = min(Self.perSource, left)
            var text = source.text
            if text.count > share { text = String(text.prefix(share)) + "\n[… cut: \(source.text.count - share) more characters]" }
            left -= text.count
            parts.append("=== \(source.path) ===\n\(text)")
        }
        return parts.joined(separator: "\n\n")
    }

    /// The one Markdown source a call with no brief lays out as written.
    var markdown: Source? { sources.count == 1 && sources[0].isMarkdown ? sources[0] : nil }
}
