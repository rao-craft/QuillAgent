import Foundation

/// A file a document is written as. Every call writes the PDF, so a host can show the pages whatever else was asked.
public enum QuillFormat: String, Codable, Sendable, CaseIterable {
    case pdf, docx, pages, html, md

    var fileExtension: String { rawValue }

    /// What a person calls it.
    var name: String {
        switch self {
        case .pdf: return "PDF"
        case .docx: return "Word"
        case .pages: return "Pages"
        case .html: return "HTML"
        case .md: return "Markdown"
        }
    }

    /// The formats a call writes: the PDF first, then the rest asked, once each, in this enum's order. Left out, a PDF
    /// and a Word file.
    static func chosen(_ asked: [QuillFormat]?) -> [QuillFormat] {
        let asked = Set(asked ?? [.docx])
        return allCases.filter { $0 == .pdf || asked.contains($0) }
    }
}

/// The paper a document is laid out on, in points (one CSS pixel on the page is one point).
public enum QuillPaper: String, Codable, Sendable, CaseIterable {
    case letter, a4

    var width: Double { self == .letter ? 612 : 595.28 }
    var height: Double { self == .letter ? 792 : 841.89 }
    /// Word's page size, in twentieths of a point.
    var twips: (width: Int, height: Int) { self == .letter ? (12240, 15840) : (11906, 16838) }
}
