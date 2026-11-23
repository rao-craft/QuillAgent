import Foundation
import PDFKit

/// The pages cut from WebKit, one PDF each, bound into one PDF with the document's title and author.
enum QuillPDFWriter {
    static func write(_ pages: [Data], document: QuillDocument) throws -> Data {
        let bound = PDFDocument()
        for (index, data) in pages.enumerated() {
            guard let one = PDFDocument(data: data), one.pageCount > 0 else { throw QuillError.render("page \(index + 1) is not a PDF") }
            for page in 0..<one.pageCount {
                if let cut = one.page(at: page) { bound.insert(cut, at: bound.pageCount) }
            }
        }
        var attributes: [PDFDocumentAttribute: Any] = [.creatorAttribute: "Quill", .producerAttribute: "Quill"]
        let title = QuillInline(document.title).plain
        if !title.isEmpty { attributes[.titleAttribute] = title }
        if let author = document.author { attributes[.authorAttribute] = author }
        if let subtitle = document.subtitle { attributes[.subjectAttribute] = QuillInline(subtitle).plain }
        bound.documentAttributes = attributes
        guard let data = bound.dataRepresentation() else { throw QuillError.render("the PDF could not be bound") }
        return data
    }
}
