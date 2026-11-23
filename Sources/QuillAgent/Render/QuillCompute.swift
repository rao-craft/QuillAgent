import Foundation

/// What every document is laid out with: one WebKit page, made on the first call and kept.
///
/// PIN: NOTHING AT BOOTSTRAP. An app that links the package and never asks for a document makes no page; the first call
/// makes it, on main, where WebKit lives.
@MainActor
public final class QuillCompute {
    private var renderer: QuillRenderer?

    public init() {}

    var page: QuillRenderer {
        if let renderer { return renderer }
        let made = QuillRenderer()
        renderer = made
        return made
    }
}
