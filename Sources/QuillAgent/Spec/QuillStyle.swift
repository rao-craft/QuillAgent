import Foundation

/// How a document looks, as far as the draft may say: the face, one accent colour, the paper, numbered headings and a
/// table of contents. Everything else (sizes, spacing, margins) is the kit's.
public struct QuillStyle: Codable, Sendable, Equatable {
    public var face: QuillFace?
    /// A colour for headings and rules, `#rrggbb`, or one of the named accents.
    public var accent: String?
    public var paper: QuillPaper?
    public var numbered: Bool?
    public var contents: Bool?

    public init(face: QuillFace? = nil, accent: String? = nil, paper: QuillPaper? = nil, numbered: Bool? = nil, contents: Bool? = nil) {
        self.face = face; self.accent = accent; self.paper = paper; self.numbered = numbered; self.contents = contents
    }

    private enum Key: String, CodingKey { case face, accent, paper, numbered, contents }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Key.self)
        face = QuillLoose.string(c, .face).flatMap { QuillFace(rawValue: $0.lowercased()) }
        accent = QuillLoose.text(c, .accent)
        paper = QuillLoose.string(c, .paper).flatMap { QuillPaper(rawValue: $0.lowercased().filter { $0.isLetter || $0.isNumber }) }
        numbered = QuillLoose.bool(c, .numbered)
        contents = QuillLoose.bool(c, .contents)
    }

    /// The named accents a draft may give instead of a hex colour.
    static let accents: [String: String] = [
        "ink": "#1d1d1f", "navy": "#1f3a5f", "blue": "#2a5db0", "teal": "#1f6f6b", "green": "#2f6b3a",
        "burgundy": "#7a1f2b", "red": "#a8322d", "orange": "#b85a1f", "gold": "#9a7a2c", "violet": "#5b3f8c",
        "slate": "#4a5563", "graphite": "#3a3a3c",
    ]

    /// The accent as `#rrggbb`: a hex the draft gave, a named one, or ink.
    var accentHex: String {
        guard let accent = accent?.lowercased().trimmingCharacters(in: .whitespaces) else { return "#1d1d1f" }
        if let named = Self.accents[accent] { return named }
        let hex = accent.hasPrefix("#") ? String(accent.dropFirst()) : accent
        guard hex.count == 6, hex.allSatisfy(\.isHexDigit) else { return "#1d1d1f" }
        return "#" + hex
    }
}
