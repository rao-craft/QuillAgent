import Foundation

/// What a call says as it goes: the sources read, each draft, each round's measure, and the written answer.
public enum QuillFrame: Sendable {
    case read(sources: Int, characters: Int)
    case drafted(round: Int, blocks: Int)
    case measured(round: Int, pages: Int, findings: Int)
    case written(QuillResult)

    var result: QuillResult? {
        if case .written(let result) = self { return result }
        return nil
    }
}
