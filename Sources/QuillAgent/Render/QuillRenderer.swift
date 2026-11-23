import Foundation
import WebKit

/// The document in WebKit, with no window: one `WebPage`, one page of HTML loaded at a time.
///
/// PIN: PAGES ARE COLUMNS. The body flows through columns one page wide and one page tall, so WebKit itself breaks it
/// into pages (break-inside, break-before, break-after); each column is cut out as one PDF page by its rectangle.
/// Spike, 2026-11-22: five Letter pages at 612 × 792 pt with selectable text, a kept block moved whole, no table row cut,
/// a forced break honoured; `widows` was not, which is why the layout pushes a paragraph itself.
@MainActor
final class QuillRenderer {
    private let page = WebPage()

    func load(_ html: String) async throws {
        do {
            for try await event in page.load(html: html) where event == .finished { return }
        } catch {
            throw QuillError.render("the page did not load: \(error)")
        }
    }

    /// The pages laid out from `html` and measured.
    func measure(_ html: String, paper: QuillPaper, layout: QuillLayout) async throws -> QuillMeasure.Raw {
        try await load(html)
        let json: String
        do {
            json = try await page.callJavaScript(QuillMeasure.script(paper: paper, layout: layout)) as? String ?? "{}"
        } catch {
            throw QuillError.render("the pages could not be measured: \(error)")
        }
        return try QuillMeasure.decode(json)
    }

    /// The loaded page finished (marks, contents' page numbers) and cut into one PDF per page.
    func export(paper: QuillPaper, layout: QuillLayout, pages: Int, marks: [(head: String?, foot: String?)],
                starts: [Int: Int]) async throws -> [Data] {
        do {
            _ = try await page.callJavaScript(QuillMeasure.finishScript(paper: paper, layout: layout, pages: pages, marks: marks, starts: starts))
        } catch {
            throw QuillError.render("the pages could not be finished: \(error)")
        }
        var cut: [Data] = []
        for index in 0..<pages {
            let rect = CGRect(x: Double(index) * paper.width, y: 0, width: paper.width, height: paper.height)
            do {
                cut.append(try await page.exported(as: .pdf(region: .rect(rect))))
            } catch {
                throw QuillError.render("page \(index + 1) could not be exported: \(error)")
            }
        }
        return cut
    }
}
