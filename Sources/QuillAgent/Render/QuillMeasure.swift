import Foundation

/// What the laid-out pages say about themselves: how many there are, and every place the layout fell short, by block.
enum QuillMeasure {
    struct Raw: Decodable, Equatable {
        /// A paragraph split across two pages with one line alone on either side.
        struct Alone: Decodable, Equatable { let q: Int; let before: Int; let after: Int; let top: Bool }
        struct Block: Decodable, Equatable { let q: Int; let page: Int }
        struct Sized: Decodable, Equatable { let q: Int; let size: Double; let room: Double }

        let pages: Int
        let alone: [Alone]
        /// Headings left at a page's foot, their next block on the page after.
        let stranded: [Int]
        let tall: [Sized]
        let wide: [Sized]
        /// How full the last page is, 0 to 1.
        let lastFill: Double
        /// The page each block starts on, 1-based.
        let starts: [Block]

        func page(of block: Int) -> Int? { starts.first { $0.q == block }?.page }
    }

    /// The script run once a page is laid out: it waits for the faces, then reads every block's line boxes.
    static func script(paper: QuillPaper, layout: QuillLayout) -> String {
        let columnHeight = paper.height - 2 * layout.marginY
        return """
        await document.fonts.ready;
        const W = \(paper.width), MX = \(layout.marginX), MY = \(layout.marginY), CH = \(columnHeight);
        const flow = document.getElementById('flow');
        const pages = Math.max(1, Math.round((flow.scrollWidth + 2 * MX) / W));
        const pageOf = x => Math.max(0, Math.floor(x / W));
        const lines = el => {
          const range = document.createRange(); range.selectNodeContents(el);
          const seen = new Map();
          for (const r of range.getClientRects()) {
            if (r.width < 0.5 || r.height < 0.5) continue;
            const page = pageOf(r.left + 1);
            const key = page + ':' + Math.round(r.top / 4);
            if (!seen.has(key)) seen.set(key, page);
          }
          const per = new Map();
          for (const page of seen.values()) per.set(page, (per.get(page) || 0) + 1);
          return [...per.entries()].sort((a, b) => a[0] - b[0]);
        };
        const out = { pages, alone: [], stranded: [], tall: [], wide: [], lastFill: 0, starts: [] };
        const blocks = [...flow.querySelectorAll('[data-q]')];
        let lastBottom = 0;
        blocks.forEach((el, i) => {
          const q = +el.dataset.q;
          const rects = [...el.getClientRects()].filter(r => r.height > 0.5);
          if (!rects.length) return;
          const first = rects[0];
          out.starts.push({ q, page: pageOf(first.left + 1) + 1 });
          for (const r of rects) if (pageOf(r.left + 1) === pages - 1) lastBottom = Math.max(lastBottom, r.bottom - MY);
          const height = rects.reduce((s, r) => s + r.height, 0);
          const tag = el.tagName;
          if (tag === 'P' || tag === 'BLOCKQUOTE') {
            const per = lines(el);
            if (per.length >= 2) {
              const before = per[0][1], after = per[per.length - 1][1];
              const top = Math.abs(first.top - MY) < 2;
              if ((before < 2 || after < 2) && height < CH * 0.8) out.alone.push({ q, before, after, top });
            }
          }
          if (/^H[1-3]$/.test(tag)) {
            const next = blocks[i + 1];
            const nr = next ? [...next.getClientRects()].filter(r => r.height > 0.5)[0] : null;
            if (nr && pageOf(nr.left + 1) > pageOf(first.left + 1)) out.stranded.push(q);
          }
          if ((tag === 'PRE' || tag === 'FIGURE' || tag === 'ASIDE') && rects.length === 1 && first.height > CH - 1)
            out.tall.push({ q, size: first.height, room: CH });
          if ((tag === 'TABLE' || tag === 'PRE' || tag === 'DL') && el.scrollWidth > el.clientWidth + 1)
            out.wide.push({ q, size: el.scrollWidth, room: el.clientWidth });
        });
        out.lastFill = Math.min(1, Math.max(0, lastBottom / CH));
        return JSON.stringify(out);
        """
    }

    /// The script that finishes the pages once they are settled: the page marks along each page's head and foot, the
    /// contents' page numbers, and the body as wide as every page, so each one can be cut out.
    static func finishScript(paper: QuillPaper, layout: QuillLayout, pages: Int, marks: [(head: String?, foot: String?)],
                             starts: [Int: Int]) -> String {
        struct Mark: Encodable { let page: Int; let head: String?; let foot: String? }
        let list = marks.enumerated().map { Mark(page: $0.offset, head: $0.element.head, foot: $0.element.foot) }
        let marksJSON = (try? String(data: JSONEncoder().encode(list), encoding: .utf8)) ?? "[]"
        let startsJSON = (try? String(data: JSONEncoder().encode(starts.reduce(into: [String: Int]()) { $0[String($1.key)] = $1.value }),
                                      encoding: .utf8)) ?? "{}"
        return """
        const W = \(paper.width), H = \(paper.height), MX = \(layout.marginX), MY = \(layout.marginY);
        const marks = \(marksJSON), starts = \(startsJSON);
        for (const span of document.querySelectorAll('.contents .page')) span.textContent = starts[span.dataset.for] || '';
        const put = (text, page, top, align) => {
          const d = document.createElement('div'); d.className = 'page-mark'; d.textContent = text;
          d.style.top = top + 'px'; d.style.left = (page * W + MX) + 'px'; d.style.width = (W - 2 * MX) + 'px';
          d.style.textAlign = align; document.body.appendChild(d);
        };
        for (const m of marks) {
          if (m.head) put(m.head, m.page, Math.max(18, MY / 2 - 4), 'left');
          if (m.foot) put(m.foot, m.page, H - Math.max(22, MY / 2), 'center');
        }
        document.body.style.width = (\(pages) * W) + 'px';
        return 1;
        """
    }

    static func decode(_ json: String) throws -> Raw {
        do { return try JSONDecoder().decode(Raw.self, from: Data(json.utf8)) }
        catch { throw QuillError.render("the pages could not be measured: \(error)") }
    }
}
