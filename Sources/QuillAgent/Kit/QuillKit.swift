import Foundation

/// The house style: a draft composed as one HTML page. `paged` lays the body in columns one page wide and one page tall,
/// so WebKit breaks it into pages the PDF is cut from; `reading` is the same document as one flowing page, the HTML file
/// a person opens or prints.
///
/// PIN: ONE CSS PIXEL IS ONE POINT. A Letter page is 612 by 792 and type is set in pixels meaning points, so the PDF's
/// pages are the paper's size and an 11 here is 11 pt in Word.
/// PIN: FACES EVERY MAC HAS. Charter, Helvetica Neue and Menlo, with Georgia, Arial and Consolas behind them: the PDF,
/// the Word file and the Pages file name the same faces, and nothing is bundled.
enum QuillKit {
    enum Mode { case paged, reading }

    static let serif = "Charter, 'Iowan Old Style', Georgia, serif"
    static let sans = "'Helvetica Neue', Helvetica, Arial, sans-serif"
    static let mono = "Menlo, 'SF Mono', Consolas, monospace"

    /// The whole page. `pictures` holds each figure's image as a data URL, by block index.
    static func page(_ document: QuillDocument, layout: QuillLayout, mode: Mode, pictures: [Int: String] = [:]) -> String {
        let body = head(document) + contents(document, mode: mode) + blocks(document, layout: layout, pictures: pictures)
        let flow = mode == .paged ? "<div id=\"flow\">\(body)</div>" : "<main id=\"flow\">\(body)</main>"
        return """
        <!doctype html><html lang="en"><head><meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <title>\(QuillHTML.escape(document.title.isEmpty ? document.form.rawValue.capitalized : document.title))</title>
        <style>\(style(document, layout: layout, mode: mode))</style></head>
        <body class="\(document.form.rawValue) \(document.face.rawValue)\(document.numbered ? " numbered" : "")">\(flow)</body></html>
        """
    }

    static func style(_ document: QuillDocument, layout: QuillLayout, mode: Mode) -> String {
        let paper = document.paper
        let columnWidth = paper.width - 2 * layout.marginX
        let columnHeight = paper.height - 2 * layout.marginY
        let face = document.face == .serif ? serif : sans
        let frame: String
        switch mode {
        case .paged:
            frame = """
            html, body { margin: 0; padding: 0; background: #fff; }
            body { width: \(n(paper.width))px; height: \(n(paper.height))px; }
            #flow { position: absolute; left: \(n(layout.marginX))px; top: \(n(layout.marginY))px;
              width: \(n(columnWidth))px; height: \(n(columnHeight))px;
              column-width: \(n(columnWidth))px; column-gap: \(n(2 * layout.marginX))px; column-fill: auto; }
            .push { break-before: column; }
            .page-mark { position: absolute; font: 8.5px/1 \(sans); color: #8a8a8e; letter-spacing: 0.02em; white-space: nowrap; }
            figure img { max-height: \(n(columnHeight * 0.6))px; }
            """
        case .reading:
            frame = """
            html { background: #f4f3ef; }
            body { margin: 0; padding: 48px 16px; }
            #flow { box-sizing: border-box; max-width: \(n(columnWidth + 2 * 56))px; margin: 0 auto; padding: 64px 56px;
              background: #fff; box-shadow: 0 1px 3px rgba(0,0,0,0.12); }
            @page { size: \(document.paper == .letter ? "letter" : "A4"); margin: \(n(layout.marginY))px \(n(layout.marginX))px; }
            @media print { html { background: #fff; } body { padding: 0; } #flow { box-shadow: none; padding: 0; max-width: none; }
              .push { break-before: page; } }
            @media (max-width: 640px) { #flow { padding: 32px 20px; } }
            figure img { max-height: 70vh; }
            """
        }
        return """
        :root { --accent: \(document.style.accentHex); --size: \(n(layout.size))px; --lead: \(layout.lead); --gap: \(layout.gap)em; }
        \(frame)
        #flow { font: var(--size)/var(--lead) \(face); color: #1d1d1f; widows: 2; orphans: 2;
          -webkit-font-smoothing: antialiased; font-kerning: normal; hyphens: manual; overflow-wrap: break-word; }
        p { margin: 0 0 var(--gap); }
        h1, h2, h3 { color: var(--accent); break-after: avoid; break-inside: avoid; line-height: 1.2; }
        h1 { font-size: 1.45em; margin: 1.1em 0 0.4em; font-weight: 700; }
        h2 { font-size: 1.18em; margin: 0.95em 0 0.3em; font-weight: 700; }
        h3 { font-size: 1em; margin: 0.8em 0 0.2em; font-weight: 700; font-style: italic; }
        .numbered #flow { counter-reset: h1; }
        .numbered h1 { counter-increment: h1; counter-reset: h2; }
        .numbered h2 { counter-increment: h2; }
        .numbered h1::before { content: counter(h1) ". "; }
        .numbered h2::before { content: counter(h1) "." counter(h2) " "; }
        ul, ol { margin: 0 0 var(--gap); padding-left: 1.4em; }
        li { margin: 0 0 0.2em; }
        li::marker { color: var(--accent); }
        a { color: var(--accent); text-decoration: underline; text-decoration-thickness: 0.5px; text-underline-offset: 1.5px; }
        code { font: 0.88em \(mono); background: #f2f1ed; padding: 0 0.2em; border-radius: 2px; }
        pre { font: 0.82em/1.45 \(mono); background: #f6f5f1; padding: 0.7em 0.9em; margin: 0 0 var(--gap);
          white-space: pre-wrap; break-inside: avoid; border-radius: 3px; }
        pre code { background: none; padding: 0; font-size: 1em; }
        table { border-collapse: collapse; width: 100%; margin: 0.2em 0 var(--gap); font-size: 0.92em; }
        th { text-align: left; font-weight: 700; border-bottom: 1px solid var(--accent); padding: 0.3em 0.5em 0.3em 0; }
        td { border-bottom: 0.5px solid #d4d2cc; padding: 0.3em 0.5em 0.3em 0; vertical-align: top; }
        tr { break-inside: avoid; }
        blockquote { margin: 0.4em 0 var(--gap); padding: 0.1em 0 0.1em 1em; border-left: 2px solid var(--accent);
          font-style: italic; break-inside: avoid; }
        blockquote p { margin: 0 0 0.3em; }
        blockquote cite { display: block; font-style: normal; font-size: 0.9em; color: #6e6e73; }
        aside { margin: 0.3em 0 var(--gap); padding: 0.6em 0.8em; background: #f4f2ec; border-left: 3px solid var(--accent);
          break-inside: avoid; }
        aside strong.title { display: block; margin-bottom: 0.2em; color: var(--accent); }
        aside p { margin: 0; }
        figure { margin: 0.4em 0 var(--gap); break-inside: avoid; text-align: center; }
        figure img { max-width: 100%; object-fit: contain; }
        figcaption { font-size: 0.85em; color: #6e6e73; margin-top: 0.3em; }
        hr { border: 0; border-top: 0.75px solid #c8c6c0; margin: 0.8em 0; }
        dl.fields { margin: 0.2em 0 var(--gap); display: grid; grid-template-columns: max-content 1fr; column-gap: 1em; row-gap: 0.45em; }
        dl.fields dt { font-weight: 700; }
        dl.fields dd { margin: 0; min-height: 1.2em; }
        dl.fields dd.blank { border-bottom: 0.75px solid #8a8a8e; }
        .sign { margin: 2.2em 0 var(--gap); width: 50%; break-inside: avoid; }
        .sign .line { border-top: 0.75px solid #1d1d1f; margin-bottom: 0.3em; }
        .sign .by { color: #6e6e73; font-size: 0.9em; }
        .contents { margin: 0 0 1.4em; break-inside: avoid; }
        .contents .entry { display: flex; gap: 0.4em; margin: 0.15em 0; }
        .contents .entry.l2 { padding-left: 1.2em; }
        .contents .entry .dots { flex: 1; border-bottom: 0.75px dotted #a8a6a0; transform: translateY(-0.3em); }
        .contents .entry a { color: inherit; text-decoration: none; }
        \(QuillKit.formStyle(document))
        """
    }

    /// A table of contents of the level 1 and 2 headings, when the style asks for one; page numbers are filled in after
    /// the pages are laid out.
    static func contents(_ document: QuillDocument, mode: Mode) -> String {
        guard document.style.contents == true else { return "" }
        let entries = document.blocks.enumerated().filter { $0.element.kind == .heading && $0.element.depth <= 2 && $0.element.text != nil }
        guard entries.count >= 2 else { return "" }
        let rows = entries.map { index, block in
            let label = QuillHTML.inline(block.text ?? "")
            let page = mode == .paged ? "<span class=\"page\" data-for=\"\(index)\"></span>" : ""
            return "<div class=\"entry l\(block.depth)\"><a href=\"#b\(index)\">\(label)</a><span class=\"dots\"></span>\(page)</div>"
        }
        return "<nav class=\"contents\"><h2>Contents</h2>\(rows.joined())</nav>"
    }

    /// A number for CSS: no trailing zeros.
    static func n(_ value: Double) -> String {
        let rounded = (value * 100).rounded() / 100
        return rounded == rounded.rounded() ? String(Int(rounded)) : String(rounded)
    }
}
