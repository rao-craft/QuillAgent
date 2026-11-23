import AppKit
import Foundation
import GraniteAgents

/// The Word file saved as a Pages file, by Pages itself: there is no public Pages format to write, so Pages opens the
/// .docx and saves it, through AppleScript. Pages is launched hidden when it is not running, and quit again after.
///
/// PIN: A PROBLEM, NEVER A REFUSAL. Pages missing, or not allowed to be driven, leaves the Word file in place and says so;
/// the document is still written.
enum QuillPagesWriter {
    static let bundle = "com.apple.iWork.Pages"

    struct Failure: Error, CustomStringConvertible {
        let description: String
        init(_ description: String) { self.description = description }
    }

    static let script = """
        on run argv
            set inPath to item 1 of argv
            set outPath to item 2 of argv
            tell application id "com.apple.iWork.Pages"
                set theDocument to open (POSIX file inPath)
                save theDocument in (POSIX file outPath)
                close theDocument saving no
            end tell
        end run
        """

    static func write(docx: URL, to pages: URL) -> Result<AgentMade.State, Failure> {
        guard let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundle) else {
            return .failure(Failure("Pages is not on this Mac: the Word file opens in Pages, or install Pages from the App Store"))
        }
        let existed = FileManager.default.fileExists(atPath: pages.path)
        let wasRunning = !NSRunningApplication.runningApplications(withBundleIdentifier: bundle).isEmpty
        if !wasRunning { launchHidden(app) }
        defer { if !wasRunning { quit() } }

        let staged = pages.deletingLastPathComponent().appendingPathComponent(".\(pages.lastPathComponent).quill-\(UUID().uuidString.prefix(6))")
        let (status, error) = osascript(script, arguments: [docx.path, staged.path])
        guard status == 0, FileManager.default.fileExists(atPath: staged.path) else {
            try? FileManager.default.removeItem(at: staged)
            return .failure(Failure(reason(error)))
        }
        do {
            if existed { _ = try FileManager.default.replaceItemAt(pages, withItemAt: staged) }
            else { try FileManager.default.moveItem(at: staged, to: pages) }
        } catch {
            try? FileManager.default.removeItem(at: staged)
            return .failure(Failure("the Pages file could not be put in place: \(error.localizedDescription)"))
        }
        return .success(existed ? .rewritten : .written)
    }

    /// What went wrong, as the person can fix it.
    static func reason(_ error: String) -> String {
        if error.contains("-1743") || error.lowercased().contains("not authorized") || error.contains("-10004") {
            return "Pages may not be driven from here: allow it in System Settings › Privacy & Security › Automation, or open the Word file in Pages"
        }
        if error.contains("-1712") { return "Pages did not answer in time: open the Word file in Pages" }
        let said = error.trimmingCharacters(in: .whitespacesAndNewlines)
        return "Pages could not save the file\(said.isEmpty ? "" : " (\(said.prefix(160)))"): open the Word file in Pages"
    }

    static func launchHidden(_ app: URL) {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        configuration.hides = true
        configuration.addsToRecentItems = false
        let done = DispatchSemaphore(value: 0)
        NSWorkspace.shared.openApplication(at: app, configuration: configuration) { _, _ in done.signal() }
        done.wait()
    }

    static func quit() {
        _ = osascript("tell application id \"\(bundle)\" to quit saving no", arguments: [])
    }

    static func osascript(_ source: String, arguments: [String]) -> (Int32, String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", source] + arguments
        let errors = Pipe()
        process.standardError = errors
        process.standardOutput = Pipe()
        do { try process.run() } catch { return (-1, "\(error)") }
        let said = errors.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (process.terminationStatus, String(decoding: said, as: UTF8.self))
    }
}
