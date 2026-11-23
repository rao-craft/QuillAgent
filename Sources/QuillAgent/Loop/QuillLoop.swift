import Foundation
import GraniteAgents

/// One call, start to end: the draft found (a spec, a Markdown source as written, or the model's), laid out and fixed
/// round by round, then every format written from it, all or none.
struct QuillLoop {
    let input: QuillAgent.Input
    let host: AgentHost
    let compute: QuillCompute
    let yield: @Sendable (QuillFrame) -> Void

    var folder: URL {
        URL(fileURLWithPath: ((input.directory ?? host.directory ?? FileManager.default.currentDirectoryPath) as NSString).expandingTildeInPath,
            isDirectory: true)
    }

    var rounds: Int { min(max(input.rounds ?? 3, 1), 6) }

    func run() async throws -> QuillResult {
        if let pages = input.pages, pages < 1 { throw QuillError.badPages(pages) }
        let brief = input.brief?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        let sources = try QuillSources.read(input.sources ?? [], in: folder)
        if !sources.sources.isEmpty {
            yield(.read(sources: sources.sources.count, characters: sources.sources.map(\.text.count).reduce(0, +)))
            host.note("read \(sources.sources.count) source\(sources.sources.count == 1 ? "" : "s")")
        }
        let earlier = try input.spec.map(readSpec)
        guard brief != nil || !sources.sources.isEmpty || earlier != nil else { throw QuillError.nothing }

        var outcome: QuillDrafted
        if let earlier, brief == nil {
            host.note("writing \(earlier.title.isEmpty ? "the draft" : "“\(earlier.title)”") again from its spec")
            outcome = try await QuillDrafting.laidOut(overriding(earlier), loop: self, rounds: 0)
        } else if brief == nil, let markdown = sources.markdown {
            host.note("laying out \(markdown.path) as written")
            let read = QuillMarkdownReader.read(markdown.text, form: input.form, name: markdown.name)
            outcome = try await QuillDrafting.laidOut(overriding(read), loop: self, rounds: 0)
        } else {
            outcome = try await QuillDrafting(loop: self, brief: brief, sources: sources, earlier: earlier).run()
        }
        return try write(outcome)
    }

    /// The call's own choices laid over a draft: its form and paper.
    func overriding(_ document: QuillDocument) -> QuillDocument {
        var document = document
        if let form = input.form { document.form = form }
        if let paper = input.paper { document.style.paper = paper }
        return document
    }

    func readSpec(_ path: String) throws -> QuillDocument {
        let url = QuillPictures.url(path, in: folder)
        guard let data = try? Data(contentsOf: url),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              object["format"] as? String == QuillDocument.format,
              let document = try? JSONDecoder().decode(QuillDocument.self, from: data) else { throw QuillError.badSpec(path) }
        return document
    }

    // MARK: - Where it is written

    /// The folder and file name a call writes to, and the formats it writes.
    func destination(for document: QuillDocument) -> (folder: URL, stem: String, formats: [QuillFormat]) {
        var asked = input.formats ?? []
        if let output = input.output?.trimmingCharacters(in: .whitespaces).nilIfEmpty {
            let url = QuillPictures.url(output, in: folder)
            if let format = QuillFormat(rawValue: url.pathExtension.lowercased()) {
                if !asked.contains(format) { asked.append(format) }
                return (url.deletingLastPathComponent(), url.deletingPathExtension().lastPathComponent, QuillFormat.chosen(asked))
            }
            return (url, document.slug, QuillFormat.chosen(input.formats))
        }
        return (folder.appendingPathComponent("quill").appendingPathComponent(document.slug), document.slug, QuillFormat.chosen(input.formats))
    }

    // MARK: - Writing

    func write(_ outcome: QuillDrafted) throws -> QuillResult {
        let document = outcome.document
        let (target, stem, formats) = destination(for: document)
        func url(_ ext: String) -> URL { target.appendingPathComponent("\(stem).\(ext)") }
        var files = QuillFiles()
        var problems: [AgentProblem] = []
        var notes: [String] = []

        files.stage(try QuillPDFWriter.write(outcome.paged.pages, document: document), at: url("pdf"))
        let pictures = outcome.pictures
        if formats.contains(.docx) || formats.contains(.pages) {
            files.stage(try QuillDocxWriter.write(document, layout: outcome.paged.layout, pictures: pictures, pages: outcome.paged.raw.pages), at: url("docx"))
        }
        if formats.contains(.html) {
            let html = QuillKit.page(document, layout: QuillLayout.of(document), mode: .reading, pictures: pictures.dataURLs)
            files.stage(Data(html.utf8), at: url("html"))
        }
        if formats.contains(.md) { files.stage(Data(QuillMarkdownWriter.write(document).utf8), at: url("md")) }
        let specURL = target.appendingPathComponent("\(stem).quill.json")
        files.stage(try document.encoded(), at: specURL)
        var written = try files.commit()

        if formats.contains(.pages) {
            host.note("saving the Pages file")
            switch QuillPagesWriter.write(docx: url("docx"), to: url("pages")) {
            case .success(let state): written.append(QuillFiles.Written(url: url("pages"), state: state))
            case .failure(let reason): problems.append(AgentProblem(kind: "pages", text: reason.description))
            }
            // A Word file nobody asked for, made only for Pages to open, does not stay.
            if !formats.contains(.docx), !(input.formats ?? []).contains(.docx), written.contains(where: { $0.url == url("pages") }) {
                try? FileManager.default.removeItem(at: url("docx"))
                written.removeAll { $0.url == url("docx") }
            }
        }

        let documents = written.filter { $0.url != specURL }
        let made = documents.map { AgentMade(kind: "document", name: $0.url.lastPathComponent, path: $0.url.path, state: $0.state) }
        let expected = formats.map { AgentExpected(kind: "document", name: "\(stem).\($0.fileExtension)") }
        let pdf = url("pdf").path

        let findings = outcome.findings
        for finding in findings where finding.kind != .placeholder {
            problems.append(AgentProblem(kind: finding.kind.rawValue, text: finding.sentence))
        }
        let placeholders = QuillPlaceholders.find(in: document)
        if !placeholders.isEmpty {
            problems.append(AgentProblem(kind: "placeholder", text: "left for the person to fill in: " + placeholders.joined(separator: ", ")))
        }
        let pages = outcome.paged.raw.pages
        notes.append("\(document.form.rawValue.capitalized), \(pages) page\(pages == 1 ? "" : "s"), \(document.words) words, written as "
                     + documents.map { QuillFormat(rawValue: $0.url.pathExtension)?.name ?? $0.url.pathExtension }.joined(separator: ", ") + ".")
        if outcome.paged.layout.tightened > 0 {
            notes.append("Set \(outcome.paged.layout.tightened) step\(outcome.paged.layout.tightened == 1 ? "" : "s") tighter than the form's own measures to fit its pages.")
        }
        notes.append("The draft is kept at \(specURL.path): give it as `spec` to write the document again or change it.")

        return QuillResult(path: pdf, paths: written.map(\.url.path), spec: specURL.path, title: document.title, form: document.form,
                           formats: formats, pages: pages, words: document.words, rounds: outcome.rounds,
                           tightened: outcome.paged.layout.tightened, findings: findings.map(\.sentence), placeholders: placeholders,
                           notes: notes, made: made, expected: expected, problems: problems,
                           interactions: [.preview([pdf], title: document.title.isEmpty ? nil : QuillInline(document.title).plain)])
    }
}

extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
