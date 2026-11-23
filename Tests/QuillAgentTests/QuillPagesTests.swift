import Foundation
import XCTest
@testable import QuillAgent

/// The Pages file, saved by Pages from the Word file. Gated (`QUILL_PAGES=1`): it launches Pages hidden, and the first
/// run asks for permission to drive it (System Settings › Privacy & Security › Automation).
@MainActor
final class QuillPagesTests: XCTestCase {
    func testPagesSavesTheWordFileAsAPagesFile() async throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["QUILL_PAGES"] == "1", "set QUILL_PAGES=1 to have Pages save a file")
        let folder = try Fixture.folder()
        try Fixture.write(Fixture.report, to: "renovation.md", in: folder)
        let answer = try await Fixture.perform(["sources": ["renovation.md"], "formats": ["pages"]], in: folder)
        let paths = try XCTUnwrap(answer["paths"] as? [String])
        Fixture.keep(paths, as: "pages")
        XCTAssertEqual(paths.map { URL(fileURLWithPath: $0).pathExtension }, ["pdf", "json", "pages"],
                       "the Word file made only for Pages does not stay: \(answer["problems"] ?? "")")
        XCTAssertTrue((answer["problems"] as? [[String: Any]] ?? []).isEmpty, "\(answer["problems"] ?? "")")
        let made = try XCTUnwrap(answer["made"] as? [[String: Any]])
        XCTAssertEqual(made.compactMap { $0["name"] as? String }, ["harbor-library-renovation.pdf", "harbor-library-renovation.pages"])
        XCTAssertTrue(FileManager.default.fileExists(atPath: paths[2]))
    }

    func testWhyPagesFailedIsSaidAsAFix() {
        XCTAssertTrue(QuillPagesWriter.reason("execution error: Not authorized to send Apple events to Pages. (-1743)").contains("Automation"))
        XCTAssertTrue(QuillPagesWriter.reason("(-1712)").contains("did not answer in time"))
        XCTAssertTrue(QuillPagesWriter.reason("something else").hasSuffix("open the Word file in Pages"))
    }
}
