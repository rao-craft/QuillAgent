import AppKit
import Foundation
import XCTest
@testable import QuillAgent

/// The Word file: a zip Word and Pages open, every part well-formed XML, the same draft the same bytes, and the text,
/// styles, lists, tables, page setup and pictures the PDF has.
@MainActor
final class QuillDocxTests: XCTestCase {
    func testAReportIsWrittenAsAWordFileWithRealStylesAndReadsBack() async throws {
        let folder = try Fixture.folder()
        try Fixture.write(Fixture.report.replacingOccurrences(of: "## Costs", with: "![The floor plan, ground level](plan.png)\n\n1. Survey\n2. Order\n\n## Costs"),
                          to: "notes/renovation.md", in: folder)
        try Self.picture(width: 400, height: 240).write(to: folder.appendingPathComponent("notes/plan.png"))
        // The figure's path is the project's: notes/plan.png.
        let text = try String(contentsOf: folder.appendingPathComponent("notes/renovation.md"), encoding: .utf8)
        try text.replacingOccurrences(of: "](plan.png)", with: "](notes/plan.png)").write(to: folder.appendingPathComponent("notes/renovation.md"), atomically: true, encoding: .utf8)

        let answer = try await Fixture.perform(["sources": ["notes/renovation.md"]], in: folder)
        let paths = try XCTUnwrap(answer["paths"] as? [String])
        XCTAssertEqual(paths.map { URL(fileURLWithPath: $0).pathExtension }, ["pdf", "docx", "json"], "a PDF and a Word file when no format is named")
        let docx = URL(fileURLWithPath: paths[1])
        Fixture.keep(paths, as: "report-docx")
        XCTAssertTrue((answer["problems"] as? [[String: Any]] ?? []).isEmpty, "\(answer["problems"] ?? "")")

        // Every part is well-formed XML.
        let parts = try Self.parts(of: docx)
        for required in ["[Content_Types].xml", "_rels/.rels", "word/document.xml", "word/styles.xml", "word/numbering.xml",
                         "word/settings.xml", "word/_rels/document.xml.rels", "docProps/core.xml", "word/footer1.xml", "word/header1.xml",
                         "word/media/image1.png"] {
            XCTAssertNotNil(parts[required], "the Word file has \(required)")
        }
        for (name, data) in parts where name.hasSuffix(".xml") || name.hasSuffix(".rels") {
            XCTAssertNoThrow(try XMLDocument(data: data), "\(name) is well-formed")
        }
        let body = try XCTUnwrap(parts["word/document.xml"].flatMap { String(data: $0, encoding: .utf8) })
        for words in ["<w:pStyle w:val=\"Title\"/>", "<w:pStyle w:val=\"Heading1\"/>", "<w:pStyle w:val=\"Quote\"/>", "<w:pStyle w:val=\"Callout\"/>",
                      "<w:tblHeader/>", "<w:numId w:val=\"1\"/>", "<w:numId w:val=\"2\"/>", "<w:pageBreakBefore/>",
                      "<w:pgSz w:w=\"12240\" w:h=\"15840\"/>", "<w:titlePg/>", "<w:b/><w:bCs/></w:rPr><w:t xml:space=\"preserve\">18 percent</w:t>",
                      "<wp:inline", "Ines Calder · November 2026"] {
            XCTAssertTrue(body.contains(words), "document.xml has \(words)")
        }
        let footer = try XCTUnwrap(parts["word/footer1.xml"].flatMap { String(data: $0, encoding: .utf8) })
        XCTAssertTrue(footer.contains("w:instr=\" PAGE \"") && footer.contains("w:instr=\" NUMPAGES \""), "live page numbers")
        let styles = try XCTUnwrap(parts["word/styles.xml"].flatMap { String(data: $0, encoding: .utf8) })
        XCTAssertTrue(styles.contains("w:ascii=\"Charter\""), "the face the PDF is set in")

        // macOS's own Word reader reads it, every block's words in it.
        let read = try NSAttributedString(url: docx, options: [.documentType: NSAttributedString.DocumentType.officeOpenXML], documentAttributes: nil).string
        for words in ["Harbor Library Renovation", "A plan for the reading room", "Why now", "18 percent", "Replace the lighting", "Survey",
                      "the town's memory", "— Ines Calder", "one wing at a time", "The floor plan, ground level", "Item 36", "$45000", "Appendix"] {
            XCTAssertTrue(read.contains(words), "the Word file reads back with \(words)")
        }
    }

    func testTheSameDraftIsTheSameBytes() throws {
        let document = QuillMarkdownReader.read(Fixture.report, form: nil, name: "x")
        let layout = QuillLayout.of(document)
        let none = QuillPictures(pictures: [:], missing: [])
        let one = try QuillDocxWriter.write(document, layout: layout, pictures: none, pages: 4)
        let two = try QuillDocxWriter.write(document, layout: layout, pictures: none, pages: 4)
        XCTAssertEqual(one, two)
        XCTAssertEqual(one.prefix(4), Data([0x50, 0x4B, 0x03, 0x04]), "a zip")
    }

    func testEveryFormAndBlockWritesAWellFormedWordFile() throws {
        for form in QuillForm.allCases {
            let document = QuillDocument(form: form, title: "Spring Fair & <Market>", subtitle: "On the green", author: "Ada Moss", date: "May 3",
                                         from: ["ada@example.com"], to: ["Parents"], style: QuillStyle(contents: true),
                                         blocks: [.heading("One"), .heading("Two", level: 2), .paragraph("A [link](https://example.com) and `code`."),
                                                  QuillBlock(.list, items: ["a", "b"], ordered: true), QuillBlock(.list, items: ["c"], ordered: true),
                                                  QuillBlock(.table, rows: [["A", "B"], ["1"]]), QuillBlock(.quote, text: "Hi", by: "Ada"),
                                                  QuillBlock(.callout, text: "Note", title: "Tip"), QuillBlock(.figure, text: "Missing", path: "none.png"),
                                                  QuillBlock(.fields, fields: [.init(label: "Name")]), QuillBlock(.signature, text: "Ada Moss", by: "Chair"),
                                                  QuillBlock(.code, text: "let x = 1\n  let y = 2"), QuillBlock(.rule), QuillBlock(.break), .paragraph("End.")])
            let data = try QuillDocxWriter.write(document, layout: QuillLayout.of(document), pictures: QuillPictures(pictures: [:], missing: [8]), pages: 2)
            let folder = try Fixture.folder()
            let url = folder.appendingPathComponent("\(form.rawValue).docx")
            try data.write(to: url)
            for (name, part) in try Self.parts(of: url) where name.hasSuffix(".xml") || name.hasSuffix(".rels") {
                XCTAssertNoThrow(try XMLDocument(data: part), "\(form): \(name)")
            }
            let numbering = try XCTUnwrap(try Self.parts(of: url)["word/numbering.xml"].flatMap { String(data: $0, encoding: .utf8) })
            XCTAssertTrue(numbering.contains("w:numId=\"3\""), "\(form): each ordered list counts from one")
            let read = try NSAttributedString(url: url, options: [.documentType: NSAttributedString.DocumentType.officeOpenXML], documentAttributes: nil).string
            XCTAssertTrue(read.contains("End."), "\(form)")
            XCTAssertTrue(read.contains("Spring Fair & <Market>") || form == .letter || form == .memo, "\(form): the title, escaped and read back")
        }
    }

    // MARK: -

    /// A Word file's parts, read with the system's unzip.
    static func parts(of url: URL) throws -> [String: Data] {
        let list = try run("/usr/bin/unzip", ["-Z1", url.path])
        var parts: [String: Data] = [:]
        for name in String(decoding: list, as: UTF8.self).split(separator: "\n").map(String.init) where !name.isEmpty {
            // unzip reads a name as a pattern: its brackets are escaped.
            let pattern = name.replacingOccurrences(of: "[", with: "\\[").replacingOccurrences(of: "]", with: "\\]")
            parts[name] = try run("/usr/bin/unzip", ["-p", url.path, pattern])
        }
        return parts
    }

    static func run(_ tool: String, _ arguments: [String]) throws -> Data {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw NSError(domain: "unzip", code: Int(process.terminationStatus)) }
        return data
    }

    static func picture(width: Int, height: Int) -> Data {
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height, bitsPerSample: 8, samplesPerPixel: 4,
                                   hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSColor(calibratedRed: 0.12, green: 0.23, blue: 0.37, alpha: 1).setFill()
        NSRect(x: 0, y: 0, width: width, height: height).fill()
        NSColor.white.setFill()
        NSRect(x: width / 4, y: height / 4, width: width / 2, height: height / 2).fill()
        NSGraphicsContext.restoreGraphicsState()
        return rep.representation(using: .png, properties: [:])!
    }
}
