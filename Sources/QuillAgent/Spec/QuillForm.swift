import Foundation

/// The kind of document: what its first page carries and the house style it is set in.
public enum QuillForm: String, Codable, Sendable, CaseIterable {
    case letter, memo, report, resume, proposal, contract, worksheet, onepager

    /// Read loosely from a model or a person: a synonym, any case; nil when it names none.
    public init?(loose text: String) {
        let word = text.lowercased().filter { $0.isLetter }
        if let form = QuillForm(rawValue: word) { self = form; return }
        switch word {
        case "coverletter", "email", "note", "invitation", "thankyou", "recommendation": self = .letter
        case "memorandum", "brief", "update", "announcement", "minutes": self = .memo
        case "paper", "whitepaper", "essay", "article", "guide", "handbook", "manual", "plan", "summary", "notes": self = .report
        case "cv", "curriculumvitae", "resumé", "résumé": self = .resume
        case "pitch", "rfp", "quote", "estimate", "sow", "statementofwork": self = .proposal
        case "agreement", "nda", "terms", "policy", "lease", "waiver": self = .contract
        case "form", "checklist", "quiz", "exercise", "handout", "sheet": self = .worksheet
        case "flyer", "factsheet", "datasheet", "poster", "onesheet", "page": self = .onepager
        default: return nil
        }
    }

    /// A long form is drafted as an outline first, then one section at a time.
    var isLong: Bool { self == .report || self == .proposal || self == .contract }

    /// The face it is set in when the draft names none.
    var face: QuillFace {
        switch self {
        case .letter, .report, .proposal, .contract: return .serif
        case .memo, .resume, .worksheet, .onepager: return .sans
        }
    }

    /// Which form a brief most likely asks for, by the words in it; a report when nothing says.
    static func guessed(from brief: String) -> QuillForm {
        let words = brief.lowercased().split { !$0.isLetter }.map(String.init)
        for (index, word) in words.enumerated() {
            let joined = index + 1 < words.count ? word + words[index + 1] : word
            if let form = QuillForm(loose: joined) { return form }
        }
        for word in words { if let form = QuillForm(loose: word) { return form } }
        return .report
    }
}

/// The type a document is set in.
public enum QuillFace: String, Codable, Sendable, CaseIterable {
    case serif, sans
}
