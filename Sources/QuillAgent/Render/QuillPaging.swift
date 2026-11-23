import Foundation

/// A draft laid out in pages: the kit's own fixes made, what is left said as findings, and the pages cut as PDFs.
struct QuillPaged {
    let layout: QuillLayout
    let raw: QuillMeasure.Raw
    let pages: [Data]
    let findings: [QuillFinding]
}

/// The kit's layout loop. It owns everything about the page a model cannot fix with words: a paragraph that would leave
/// one line alone is pushed to the next page, a heading left at a page's foot goes with its text, and a document over its
/// page limit (or with a last page of a few lines) is set tighter, one step at a time, down to the floors.
///
/// PIN: THE KIT FIXES THE PAGE, THE MODEL FIXES THE WORDS. What tightening cannot fit is a finding that names how many
/// pages over, so the model cuts words rather than the kit shrinking type past the floor.
@MainActor
enum QuillPaging {
    /// Passes of pushes per layout: each push can move what follows it.
    static let pushPasses = 4

    static func lay(_ document: QuillDocument, pictures: [Int: String], limit: Int?, renderer: QuillRenderer) async throws -> QuillPaged {
        let paper = document.paper
        var layout = QuillLayout.of(document)
        var raw = try await settle(document, pictures: pictures, layout: &layout, renderer: renderer)

        // Over the limit, or a last page of a few lines: tighter, while it helps.
        let target = limit ?? (raw.pages > 1 && raw.lastFill < 0.12 ? raw.pages - 1 : nil)
        if let target, raw.pages > target {
            var trial = layout
            while let next = trial.tighter() {
                trial = next
                trial.pushed = []
                let measured = try await settle(document, pictures: pictures, layout: &trial, renderer: renderer)
                if measured.pages <= target {
                    layout = trial; raw = measured
                    break
                }
                // Over a limit the person set, keep the tightest so far; a last page that will not come back keeps the form's own.
                if limit != nil, measured.pages < raw.pages { layout = trial; raw = measured }
            }
        }
        // The page in WebKit must be the layout kept.
        raw = try await renderer.measure(QuillKit.page(document, layout: layout, mode: .paged, pictures: pictures), paper: paper, layout: layout)

        var starts: [Int: Int] = [:]
        for start in raw.starts { starts[start.q] = start.page }
        let marks = (1...raw.pages).map { QuillKit.marks(document, page: $0, pages: raw.pages) }
        let pages = try await renderer.export(paper: paper, layout: layout, pages: raw.pages, marks: marks, starts: starts)
        return QuillPaged(layout: layout, raw: raw, pages: pages, findings: findings(document, raw: raw, limit: limit))
    }

    /// The layout's pushes found: lay out, push what leaves a line alone or a heading stranded, and again.
    static func settle(_ document: QuillDocument, pictures: [Int: String], layout: inout QuillLayout,
                       renderer: QuillRenderer) async throws -> QuillMeasure.Raw {
        var raw = try await renderer.measure(QuillKit.page(document, layout: layout, mode: .paged, pictures: pictures),
                                             paper: document.paper, layout: layout)
        for _ in 0..<pushPasses {
            var push = Set(raw.stranded)
            for alone in raw.alone where !alone.top { push.insert(alone.q) }
            push.subtract(layout.pushed)
            guard !push.isEmpty else { break }
            layout.pushed.formUnion(push)
            raw = try await renderer.measure(QuillKit.page(document, layout: layout, mode: .paged, pictures: pictures),
                                             paper: document.paper, layout: layout)
        }
        return raw
    }

    /// What the pages still do not do, in sentences.
    nonisolated static func findings(_ document: QuillDocument, raw: QuillMeasure.Raw, limit: Int?) -> [QuillFinding] {
        var found: [QuillFinding] = []
        if let limit, raw.pages > limit {
            let over = raw.pages - limit
            let words = document.words
            let cut = max(20, Int(Double(words) * Double(over) / Double(raw.pages)))
            found.append(QuillFinding(.pages, "the document is \(raw.pages) pages and must be \(limit): cut about \(cut) of its \(words) words, the least needed first"))
        }
        for wide in raw.wide {
            found.append(QuillFinding(.wide, block: wide.q, "\(describe(document, wide.q)) is wider than the page: fewer columns or shorter cells"))
        }
        for tall in raw.tall {
            found.append(QuillFinding(.tall, block: tall.q, "\(describe(document, tall.q)) is taller than a page: split it in two"))
        }
        for alone in raw.alone where !alone.top {
            found.append(QuillFinding(.alone, block: alone.q, "\(describe(document, alone.q)) leaves one line alone on a page"))
        }
        return found
    }

    /// A block named as a person reads it: "block 4 (the table under Figures)".
    nonisolated static func describe(_ document: QuillDocument, _ index: Int) -> String {
        guard document.blocks.indices.contains(index) else { return "block \(index + 1)" }
        let block = document.blocks[index]
        let heading = document.blocks[..<index].last { $0.kind == .heading }?.text.map { QuillInline($0).plain }
        let under = heading.map { " under \"\($0)\"" } ?? ""
        return "block \(index + 1) (the \(block.kind.rawValue)\(under))"
    }
}
