import Foundation
import XCTest
@testable import QuillAgent

/// The draft as a model writes it, read loosely, and the text inside it.
final class QuillSpecTests: XCTestCase {
    func testALooseDraftIsReadAndABadBlockIsDroppedAlone() throws {
        let json = """
        {"form": "Cover Letter", "title": "Data Analyst", "from": "Dana Reyes\\n4 Elm St", "style": {"face": "SANS", "accent": "navy", "paper": "A4"},
         "blocks": [
           {"kind": "Heading", "text": "Hello", "level": "2"},
           {"kind": "bullets", "items": "one\\ntwo\\n\\nthree"},
           {"kind": "grid", "rows": [["Year", "Sales"], [2025, 1.5], ["2026", true]]},
           {"kind": "spaceship", "text": "read as a paragraph"},
           {"kind": "form", "fields": [{"label": "Name"}, {"label": "Age", "value": 9}, {"value": "no label"}]},
           {"kind": "quote", "text": "Be kind.", "by": "— Mira"},
           7
         ]}
        """
        let document = try JSONDecoder().decode(QuillDocument.self, from: Data(json.utf8))
        XCTAssertEqual(document.form, .letter)
        XCTAssertEqual(document.from, ["Dana Reyes", "4 Elm St"])
        XCTAssertEqual(document.style.face, .sans)
        XCTAssertEqual(document.style.paper, .a4)
        XCTAssertEqual(document.style.accentHex, "#1f3a5f")
        XCTAssertEqual(document.blocks.map(\.kind), [.heading, .list, .table, .paragraph, .fields, .quote], "the 7 is dropped alone")
        XCTAssertEqual(document.blocks[0].depth, 2)
        XCTAssertEqual(document.blocks[1].items, ["one", "two", "three"])
        XCTAssertEqual(document.blocks[2].rows, [["Year", "Sales"], ["2025", "1.5"], ["2026", "yes"]])
        XCTAssertEqual(document.blocks[4].fields, [.init(label: "Name"), .init(label: "Age", value: "9")])
        XCTAssertEqual(document.blocks[5].by, "Mira")
        // Kept and read again, it is the same draft.
        let again = try JSONDecoder().decode(QuillDocument.self, from: document.encoded())
        XCTAssertEqual(again, document)
        XCTAssertEqual(String(data: try document.encoded(), encoding: .utf8)?.contains("\"format\" : \"quill-document/1\""), true)
    }

    func testInlineMarksAreReadTheSameEverywhere() {
        let runs = QuillInline("Plain **bold** and *it* and `code` and [a link](https://example.com) and snake_case_name.").runs
        XCTAssertEqual(runs.map(\.text), ["Plain ", "bold", " and ", "it", " and ", "code", " and ", "a link", " and snake_case_name."])
        XCTAssertEqual(runs[1].bold, true)
        XCTAssertEqual(runs[3].italic, true)
        XCTAssertEqual(runs[5].code, true)
        XCTAssertEqual(runs[7].link, "https://example.com")
        XCTAssertEqual(QuillInline("5 * 3 = 15 and **unclosed").plain, "5 * 3 = 15 and **unclosed", "an unclosed mark is kept as written")
        XCTAssertEqual(QuillHTML.inline("<b> & [x](javascript:alert(1))"), "&lt;b&gt; &amp; x", "no markup through, no unsafe link")
    }

    func testPlaceholdersAreTheBracketedPlacesNotLinks() {
        let document = QuillDocument(form: .letter, title: "", to: ["[Hiring Manager's Name]", "Northwind"],
                                     blocks: [.paragraph("I saw the role on [the careers page](https://example.com) on [Date]."),
                                              .paragraph("Again [Date], and a [1] footnote.")])
        XCTAssertEqual(QuillPlaceholders.find(in: document), ["[Hiring Manager's Name]", "[Date]"])
    }

    func testTheMarkdownReaderReadsWhatPeopleWrite() {
        let document = QuillMarkdownReader.read(Fixture.report, form: nil, name: "fallback")
        XCTAssertEqual(document.title, "Harbor Library Renovation")
        XCTAssertEqual(document.subtitle, "A plan for the reading room and the archive")
        XCTAssertEqual(document.author, "Ines Calder")
        XCTAssertEqual(document.date, "November 2026")
        XCTAssertEqual(document.form, .report)
        let kinds = document.blocks.map(\.kind)
        XCTAssertEqual(kinds.first, .heading)
        XCTAssertEqual(document.blocks.first?.depth, 1, "`##` under a lone `#` title is a level 1 heading")
        XCTAssertTrue(kinds.contains(.list) && kinds.contains(.quote) && kinds.contains(.callout) && kinds.contains(.table) && kinds.contains(.break))
        let quote = document.blocks.first { $0.kind == .quote }
        XCTAssertEqual(quote?.by, "Ines Calder")
        let callout = document.blocks.first { $0.kind == .callout }
        XCTAssertEqual(callout?.title, "Note")
        XCTAssertEqual(document.blocks.first { $0.kind == .table }?.rows.count, 37)
        XCTAssertEqual(QuillMarkdownReader.read("Just a line.", form: .memo, name: "Notes").title, "Notes", "no heading: the file's name")
    }
}
