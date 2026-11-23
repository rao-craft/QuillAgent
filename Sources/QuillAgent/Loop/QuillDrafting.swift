import Foundation
import GraniteAgents

/// A draft and its pages, as a round left them.
struct QuillDrafted {
    let document: QuillDocument
    let paged: QuillPaged
    let pictures: QuillPictures
    let findings: [QuillFinding]
    let rounds: Int

    /// What the model could still fix: the measure a round is kept by.
    var modelFindings: Int { findings.filter(\.isTheModels).count }
}

/// The model's part: a draft from the brief and sources (an outline first, then a section at a time, for a long form),
/// grounded, checked, laid out, and rewritten for what the checks and the pages found, round by round. The best round is
/// kept: the fewest findings the model could fix, the later on a tie.
///
/// PIN: THE KIT FIXES THE PAGE, THE MODEL FIXES THE WORDS. A revise is asked only for findings the model can act on
/// (pages over, too wide, too tall, a limit, an invented figure, a copied example); a line left alone or a missing
/// picture is never sent back.
struct QuillDrafting {
    let loop: QuillLoop
    let brief: String?
    let sources: QuillSources
    let earlier: QuillDocument?

    var host: AgentHost { loop.host }

    static var today: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "MMMM d, yyyy"
        return formatter.string(from: Date())
    }

    var form: QuillForm {
        loop.input.form ?? earlier?.form ?? QuillForm.guessed(from: [brief, host.ask].compactMap { $0 }.joined(separator: " "))
    }

    var grounds: QuillGrounds {
        var texts = [brief, host.ask, Self.today].compactMap { $0 } + sources.sources.map(\.text)
        if let earlier, let encoded = try? earlier.encoded() { texts.append(String(decoding: encoded, as: UTF8.self)) }
        return QuillGrounds(texts)
    }

    func run() async throws -> QuillDrafted {
        let model = try host.model(for: QuillAgent.word)
        let form = self.form
        let today = Self.today
        let grounds = self.grounds
        let system = QuillPrompt.system(form, today: today)

        // The first draft.
        var document: QuillDocument
        if let earlier {
            host.note("changing “\(earlier.title.isEmpty ? earlier.form.rawValue : earlier.title)” as asked")
            document = try await revise(earlier, findings: [], change: brief, model: model, system: system)
        } else if form.isLong {
            document = try await longDraft(form: form, model: model, system: system)
        } else {
            host.note("drafting a \(form.rawValue)")
            document = try await ask(model, schema: QuillPrompt.documentSchema, system: system,
                                     user: QuillPrompt.draft(form: form, brief: brief, ask: host.ask, sources: sources.digest,
                                                             pages: loop.input.pages, paper: loop.input.paper),
                                     tokens: 3_000, as: QuillDocument.self)
        }

        var best: QuillDrafted?
        var round = 1
        while true {
            try Task.checkCancellation()
            document = prepared(document, form: form)
            loop.yield(.drafted(round: round, blocks: document.blocks.count))
            let (drawn, placed) = document.grounded(by: grounds)
            let checks = drawn.check() + drawn.inventions(by: grounds) + drawn.echoes(by: grounds) + placed
            let laid = try await Self.laidOut(drawn, loop: loop, rounds: round, extra: checks)
            if best == nil || laid.modelFindings <= best!.modelFindings { best = laid }
            let toFix = laid.findings.filter(\.isTheModels)
            if toFix.isEmpty {
                host.note("round \(round): measured clean, \(laid.paged.raw.pages) page\(laid.paged.raw.pages == 1 ? "" : "s")")
                break
            }
            host.note("round \(round): \(toFix.count) to fix — \(toFix[0].sentence)")
            guard round < loop.rounds else { break }
            round += 1
            host.note("revising the \(form.rawValue)")
            // The model rewrites the draft it wrote, not the grounded copy: a placeholder the kit put in stays the kit's.
            guard let revised = try? await revise(drawn, findings: toFix, change: nil, model: model, system: system),
                  prepared(revised, form: form) != document else { break }
            document = revised
        }
        guard let best else { throw QuillError.nothing }
        return best
    }

    /// A draft as the call asked for it: the form, paper and page limit's own; headings cleared; empty blocks gone.
    func prepared(_ document: QuillDocument, form: QuillForm) -> QuillDocument {
        var document = loop.overriding(document.cleaned())
        if loop.input.form != nil || earlier == nil { document.form = form }
        return document
    }

    /// A report, proposal or contract: its outline, then each section.
    func longDraft(form: QuillForm, model: any AgentHostModel, system: String) async throws -> QuillDocument {
        host.note("outlining a \(form.rawValue)")
        var outline = try await ask(model, schema: QuillPrompt.outlineSchema, system: system,
                                    user: QuillPrompt.outline(form: form, brief: brief, ask: host.ask, sources: sources.digest, pages: loop.input.pages),
                                    tokens: 1_200, as: QuillOutline.self)
        outline.form = form
        guard !outline.sections.isEmpty else { throw AgentHostError.answer("the outline has no sections") }
        var blocks: [QuillBlock] = []
        let digest = sources.digest
        for (index, section) in outline.sections.enumerated() {
            try Task.checkCancellation()
            host.note("writing section \(index + 1) of \(outline.sections.count): \(section.heading)")
            blocks.append(.heading(section.heading, level: 1))
            do {
                let written = try await ask(model, schema: QuillPrompt.blocksSchema, system: system,
                                            user: QuillPrompt.section(index, of: outline, brief: brief, sources: digest),
                                            tokens: 1_600, as: QuillSectionBlocks.self)
                // A section's own blocks: a repeated top heading dropped, the rest kept.
                blocks += written.blocks.filter { !($0.kind == .heading && $0.depth == 1) }
            } catch let error as AgentHostError {
                // One section the model could not write keeps its place, said as its points.
                host.note("section \(index + 1) was not written (\(error)): its points are kept")
                blocks.append(QuillBlock(.list, items: section.points))
            }
        }
        return QuillDocument(form: form, title: outline.title, subtitle: outline.subtitle, author: outline.author, date: outline.date,
                             to: outline.to, blocks: blocks)
    }

    func revise(_ document: QuillDocument, findings: [QuillFinding], change: String?, model: any AgentHostModel, system: String) async throws -> QuillDocument {
        let user = try QuillPrompt.revise(document, findings: findings, change: change)
        let size = (try? document.encoded().count) ?? 4_000
        let tokens = min(8_000, max(3_000, size / 2))
        return try await ask(model, schema: QuillPrompt.documentSchema, system: system + "\n\n" + QuillPrompt.reviseRules, user: user,
                             tokens: tokens, as: QuillDocument.self)
    }

    /// One ask of the model, decoded loosely.
    func ask<T: Decodable>(_ model: any AgentHostModel, schema: Data, system: String, user: String, tokens: Int, as type: T.Type) async throws -> T {
        let data = try await model.object(schema: schema, system: system, user: user, maxTokens: tokens, seconds: 60 + Double(tokens) / 25)
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            throw AgentHostError.answer("the draft did not decode: \(error)")
        }
    }

    /// A draft laid out as it is: its pictures read, its pages laid out and measured.
    static func laidOut(_ document: QuillDocument, loop: QuillLoop, rounds: Int, extra: [QuillFinding] = []) async throws -> QuillDrafted {
        let pictures = QuillPictures.read(document, in: loop.folder)
        let compute = loop.compute
        let urls = pictures.dataURLs
        let limit = loop.input.pages
        let paged = try await MainActor.run { compute.page }.lay(document, pictures: urls, limit: limit)
        var findings = extra + paged.findings
        for index in pictures.missing {
            findings.append(QuillFinding(.picture, block: index, "\(QuillPaging.describe(document, index)) names \(document.blocks[index].path ?? "no picture"), which is not a picture in the project"))
        }
        loop.yield(.measured(round: rounds, pages: paged.raw.pages, findings: findings.count))
        return QuillDrafted(document: document, paged: paged, pictures: pictures, findings: findings, rounds: rounds)
    }
}

extension QuillRenderer {
    func lay(_ document: QuillDocument, pictures: [Int: String], limit: Int?) async throws -> QuillPaged {
        try await QuillPaging.lay(document, pictures: pictures, limit: limit, renderer: self)
    }
}
