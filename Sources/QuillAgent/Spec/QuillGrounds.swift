import Foundation

/// What the person gave: the brief, their own words, the sources, an earlier draft, and today's date. A name, a contact
/// line, a date or a figure in a draft stands only when it is here.
///
/// PIN: THE KIT REPLACES, THE MODEL REWRITES. A sender's or recipient's line, an author, a signature or a quote's speaker
/// that is not here is replaced by a bracketed place before the pages are laid out: a person reading the letter must
/// never see a stranger's address as theirs. A figure in the body that is not here goes back to the model to remove.
struct QuillGrounds {
    let words: Set<String>
    let numbers: Set<String>

    init(_ texts: [String]) {
        var words = Set<String>(), numbers = Set<String>()
        for text in texts {
            for token in Self.tokens(text) {
                words.insert(token.lowercased())
                let digits = Self.digits(token)
                if !digits.isEmpty { numbers.insert(digits) }
            }
        }
        self.words = words
        self.numbers = numbers
    }

    static func tokens(_ text: String) -> [String] {
        text.split { $0.isWhitespace || ",;:()\"“”[]{}<>|/".contains($0) }
            .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: ".!?'’*_`")) }
            .filter { !$0.isEmpty }
    }

    static func digits(_ token: String) -> String { token.filter(\.isNumber) }

    /// Words a letter may address or sign with that name no one: "Hiring Manager", "To Whom It May Concern".
    static let generic: Set<String> = [
        "dear", "to", "whom", "it", "may", "concern", "the", "a", "an", "of", "and", "for", "hiring", "manager", "managers", "team",
        "committee", "department", "office", "human", "resources", "board", "members", "member", "council", "sir", "madam",
        "recruiting", "recruiter", "admissions", "customer", "service", "editor", "director", "all", "staff", "everyone",
        "colleagues", "friends", "neighbors", "neighbours", "parents", "families", "residents", "applicant", "candidate",
    ]

    /// Whether every name and number in `line` is given: each capitalised word and each token with a digit.
    func grounds(_ line: String) -> Bool {
        let plain = QuillInline(line).plain
        if plain.hasPrefix("[") && plain.hasSuffix("]") { return true }
        for token in Self.tokens(plain) {
            let digits = Self.digits(token)
            if !digits.isEmpty {
                if !numbers.contains(digits) { return false }
                continue
            }
            let lower = token.lowercased()
            // An email or a web address stands only as given.
            if token.contains("@") || (token.contains(".") && token.contains { $0.isLetter }) {
                if !words.contains(lower) { return false }
                continue
            }
            // A capitalised word, or an initial, names someone or somewhere.
            let named = token.first?.isUppercase == true && (token.count > 1 || !["I", "A"].contains(token))
            if named, !words.contains(lower), !Self.generic.contains(lower) { return false }
        }
        return true
    }

    /// Figures in body text that are not given: tokens of two digits or more, or any with a currency or percent sign.
    func inventedFigures(in text: String) -> [String] {
        let plain = QuillInline(text).plain
        var found: [String] = []
        for token in Self.tokens(plain) where !(token.hasPrefix("[")) {
            let digits = Self.digits(token)
            guard !digits.isEmpty else { continue }
            let marked = token.contains("$") || token.contains("%") || token.contains("€") || token.contains("£")
            guard digits.count >= 2 || marked else { continue }
            if !numbers.contains(digits), !found.contains(token) { found.append(token) }
        }
        return found
    }
}

extension QuillDocument {
    /// The draft with every ungiven contact line, author, signature and speaker replaced by a bracketed place, and what
    /// was replaced, as findings the answer lists.
    func grounded(by grounds: QuillGrounds) -> (QuillDocument, [QuillFinding]) {
        var document = self
        var findings: [QuillFinding] = []
        func place(_ line: String, first: Bool, sender: Bool) -> String {
            if line.contains("@") { return "[Email]" }
            if line.filter(\.isNumber).count >= 7 { return "[Phone]" }
            if first { return sender ? "[Your Name]" : "[Recipient Name]" }
            return sender ? "[Your Address]" : "[Recipient Address]"
        }
        func ground(_ lines: [String], sender: Bool, role: String) -> [String] {
            var out: [String] = []
            for (offset, line) in lines.enumerated() {
                if grounds.grounds(line) { out.append(line); continue }
                let replaced = place(line, first: offset == 0, sender: sender)
                findings.append(QuillFinding(.replaced, "\(role) line \"\(QuillInline(line).plain)\" is not in the brief: written as \(replaced)"))
                if !out.contains(replaced) { out.append(replaced) }
            }
            return out
        }
        document.from = ground(from, sender: true, role: "the sender's")
        document.to = ground(to, sender: false, role: "the recipient's")
        if let author, !grounds.grounds(author) {
            findings.append(QuillFinding(.replaced, "the author \"\(author)\" is not in the brief: written as [Your Name]"))
            document.author = "[Your Name]"
        }
        if let date, !grounds.grounds(date) {
            findings.append(QuillFinding(.replaced, "the date \"\(date)\" is not in the brief: written as [Date]"))
            document.date = "[Date]"
        }
        if form == .resume, !title.isEmpty, !grounds.grounds(title) {
            findings.append(QuillFinding(.replaced, "the name \"\(title)\" is not in the brief: written as [Your Name]"))
            document.title = "[Your Name]"
        }
        for (index, block) in blocks.enumerated() {
            if block.kind == .signature, let name = block.text, !grounds.grounds(name) {
                findings.append(QuillFinding(.replaced, block: index, "the signature's name \"\(name)\" is not in the brief: written as [Your Name]"))
                document.blocks[index].text = "[Your Name]"
            }
            if block.kind == .signature, let title = block.by, !grounds.grounds(title) {
                document.blocks[index].by = "[Title]"
            }
            if block.kind == .quote, let by = block.by, !grounds.grounds(by) {
                findings.append(QuillFinding(.replaced, block: index, "the quote's speaker \"\(by)\" is not in the brief or sources: left unnamed"))
                document.blocks[index].by = nil
            }
        }
        return (document, findings)
    }

    /// Figures the body gives that the person did not, one finding per block, for the model to remove.
    func inventions(by grounds: QuillGrounds) -> [QuillFinding] {
        var findings: [QuillFinding] = []
        for (index, block) in blocks.enumerated() where block.kind != .code {
            let texts = [block.text, block.title].compactMap { $0 } + block.items + block.rows.flatMap { $0 } + block.fields.map(\.value)
            let invented = texts.flatMap { grounds.inventedFigures(in: $0) }
            guard !invented.isEmpty else { continue }
            let list = Array(Set(invented)).sorted().prefix(4).joined(separator: ", ")
            findings.append(QuillFinding(.invented, block: index,
                                         "\(QuillPaging.describe(self, index)) gives \(list), which the brief and sources do not: remove it or write [figure]"))
        }
        return findings
    }

    /// Words of the prompt's example the draft carries and the person's own words do not.
    func echoes(by grounds: QuillGrounds) -> [QuillFinding] {
        let words = Set(QuillGrounds.tokens(([title, subtitle ?? ""] + from + to + blocks.flatMap(\.words)).joined(separator: " ")).map { $0.lowercased() })
        let echoed = QuillPrompt.exampleWords.filter { words.contains($0) && !grounds.words.contains($0) }
        guard !echoed.isEmpty else { return [] }
        return [QuillFinding(.echo, "it copies the example's words (\(echoed.joined(separator: ", "))): write only about the person's subject")]
    }
}
