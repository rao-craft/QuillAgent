import Foundation

/// The draft as a Word file. Written in Phase 2.
enum QuillDocxWriter {
    static func write(_ document: QuillDocument, layout: QuillLayout, pictures: QuillPictures) throws -> Data {
        throw QuillError.unwritable("Word files are not written yet")
    }
}
