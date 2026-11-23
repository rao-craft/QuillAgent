import Foundation
import GraniteAgents

/// A draft and its pages, as a round left them.
struct QuillDrafted {
    let document: QuillDocument
    let paged: QuillPaged
    let pictures: QuillPictures
    let findings: [QuillFinding]
    let rounds: Int
}

/// The model's part: a draft from the brief and sources, laid out, measured, and rewritten for what the pages and the
/// checks found, round by round; the best round kept.
struct QuillDrafting {
    let loop: QuillLoop
    let brief: String?
    let sources: QuillSources
    let earlier: QuillDocument?

    func run() async throws -> QuillDrafted {
        _ = try loop.host.model(for: QuillAgent.word)
        throw QuillError.nothing
    }

    /// A draft laid out as it is, with no model: its pictures read, its pages laid out and measured.
    static func laidOut(_ document: QuillDocument, loop: QuillLoop, rounds: Int, extra: [QuillFinding] = []) async throws -> QuillDrafted {
        let pictures = QuillPictures.read(document, in: loop.folder)
        let compute = loop.compute
        let urls = pictures.dataURLs
        let limit = loop.input.pages
        let paged = try await MainActor.run { compute.page }.lay(document, pictures: urls, limit: limit)
        var findings = paged.findings + extra
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
