import Foundation

/// Reading a model's JSON loosely: a number written as a string, a boolean as "yes", a list written as one line per
/// item, an element of a list that does not decode dropped rather than the whole list. A local model's JSON is loose; a
/// document should not be lost to a stray quote.
enum QuillLoose {
    /// A value that decodes, or nothing, never a thrown error: one bad element of a list is dropped alone.
    struct Element<T: Decodable>: Decodable {
        let value: T?
        init(from decoder: Decoder) throws { value = try? T(from: decoder) }
    }

    static func string<K: CodingKey>(_ c: KeyedDecodingContainer<K>, _ key: K) -> String? {
        if let text = try? c.decodeIfPresent(String.self, forKey: key) { return text }
        if let number = try? c.decodeIfPresent(Int.self, forKey: key) { return String(number) }
        if let number = try? c.decodeIfPresent(Double.self, forKey: key) { return String(number) }
        return nil
    }

    /// A string with something in it, trimmed; nil when empty.
    static func text<K: CodingKey>(_ c: KeyedDecodingContainer<K>, _ key: K) -> String? {
        guard let text = string(c, key)?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }
        return text
    }

    static func int<K: CodingKey>(_ c: KeyedDecodingContainer<K>, _ key: K) -> Int? {
        if let number = try? c.decodeIfPresent(Int.self, forKey: key) { return number }
        if let number = try? c.decodeIfPresent(Double.self, forKey: key) { return Int(number) }
        if let text = try? c.decodeIfPresent(String.self, forKey: key) { return Int(text.trimmingCharacters(in: .whitespaces)) }
        return nil
    }

    static func bool<K: CodingKey>(_ c: KeyedDecodingContainer<K>, _ key: K) -> Bool? {
        if let flag = try? c.decodeIfPresent(Bool.self, forKey: key) { return flag }
        if let text = try? c.decodeIfPresent(String.self, forKey: key) { return ["true", "yes", "1"].contains(text.lowercased()) }
        if let number = try? c.decodeIfPresent(Int.self, forKey: key) { return number != 0 }
        return nil
    }

    static func list<K: CodingKey, T: Decodable>(_ c: KeyedDecodingContainer<K>, _ key: K, of type: T.Type) -> [T] {
        ((try? c.decodeIfPresent([Element<T>].self, forKey: key)) ?? nil)?.compactMap(\.value) ?? []
    }

    /// Lines: a list of strings, or one string with a line each; empty lines dropped.
    static func lines<K: CodingKey>(_ c: KeyedDecodingContainer<K>, _ key: K) -> [String] {
        var found = list(c, key, of: String.self)
        if found.isEmpty, let text = string(c, key) { found = text.components(separatedBy: .newlines) }
        return found.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    /// A table cell: text, or a number or flag read as text.
    struct Cell: Decodable {
        let text: String
        init(from decoder: Decoder) throws {
            let one = try decoder.singleValueContainer()
            if let text = try? one.decode(String.self) { self.text = text }
            else if let number = try? one.decode(Int.self) { text = String(number) }
            else if let number = try? one.decode(Double.self) { text = String(number) }
            else if let flag = try? one.decode(Bool.self) { text = flag ? "yes" : "no" }
            else { text = "" }
        }
    }

    /// Rows of cells: a list of lists of strings (numbers read as text).
    static func rows<K: CodingKey>(_ c: KeyedDecodingContainer<K>, _ key: K) -> [[String]] {
        let rows = ((try? c.decodeIfPresent([Element<[Cell]>].self, forKey: key)) ?? nil)?.compactMap(\.value) ?? []
        return rows.map { $0.map { $0.text.trimmingCharacters(in: .whitespaces) } }.filter { !$0.isEmpty }
    }

    /// A file name made from a title: lowercase letters and digits, words joined by `-`, at most eight words.
    static func slug(_ text: String) -> String {
        let words = text.lowercased().split { !$0.isLetter && !$0.isNumber }.prefix(8)
        return words.isEmpty ? "document" : words.joined(separator: "-")
    }
}
