import AppKit
import Foundation
import GraniteAgents

/// The Word file saved as a Pages file, by Pages itself: there is no public Pages format to write. Pages is handed the
/// .docx the way Finder hands it a file (Launch Services, hidden, not brought to the front), then told through
/// AppleScript to save that document as a .pages and close it. When Pages was not running, it is quit again after.
///
/// PIN: OPENED BY LAUNCH SERVICES, NOT BY APPLESCRIPT. Pages 15 is sandboxed, and a file named in an AppleScript `open`
/// carries no permission to read it ("can't be opened right now"). A file opened through Launch Services does. Saving
/// through AppleScript into any folder works.
///
/// Two apps answer to "Pages": Pages Creator Studio (`com.apple.Pages`, 15 and later) and the older Pages
/// (`com.apple.iWork.Pages`, 14). The newer is asked first. Pages 14 beside 15 opens a dialog saying it is out of date
/// and answers nothing until someone clicks it, so it is asked only when it is the only Pages on the Mac.
///
/// PIN: A PROBLEM, NEVER A REFUSAL. Pages missing, or not allowed to be driven, leaves the Word file in place and says so;
/// the document is still written.
enum QuillPagesWriter {
    static let bundles = ["com.apple.Pages", "com.apple.iWork.Pages"]

    struct Failure: Error, CustomStringConvertible {
        let description: String
        init(_ description: String) { self.description = description }
    }

    /// Waits for the document Launch Services opened (by name, the file's stem), saves it, and closes it.
    static func script(_ bundle: String) -> String { """
        on run argv
            set theName to item 1 of argv
            set outPath to item 2 of argv
            with timeout of 120 seconds
                tell application id "\(bundle)"
                    repeat 120 times
                        if exists (first document whose name is theName) then exit repeat
                        delay 0.5
                    end repeat
                    set theDocument to first document whose name is theName
                    save theDocument in (POSIX file outPath)
                    close theDocument saving no
                end tell
            end timeout
        end run
        """ }

    static func write(docx: URL, to pages: URL) -> Result<AgentMade.State, Failure> {
        guard let (bundle, app) = bundles.lazy.compactMap({ id in NSWorkspace.shared.urlForApplication(withBundleIdentifier: id).map { (id, $0) } }).first else {
            return .failure(Failure("Pages is not on this Mac: the Word file opens in Pages, or install Pages from the App Store"))
        }
        let existed = FileManager.default.fileExists(atPath: pages.path)
        let wasRunning = !NSRunningApplication.runningApplications(withBundleIdentifier: bundle).isEmpty
        defer { if !wasRunning { quit(bundle) } }
        if let error = openHidden(docx, in: app) {
            return .failure(Failure("Pages could not be handed the Word file (\(error.localizedDescription)): open the Word file in Pages"))
        }

        // The staged name keeps the .pages extension, so Pages saves it under exactly this name.
        let staged = pages.deletingLastPathComponent().appendingPathComponent(".quill-\(UUID().uuidString.prefix(6))-\(pages.lastPathComponent)")
        let (status, error) = osascript(script(bundle), arguments: [docx.deletingPathExtension().lastPathComponent, staged.path])
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
        if error.contains("-1712") { return "Pages did not answer in time (a dialog in Pages may be waiting): open the Word file in Pages" }
        let said = error.trimmingCharacters(in: .whitespacesAndNewlines)
        return "Pages could not save the file\(said.isEmpty ? "" : " (\(said.prefix(160)))"): open the Word file in Pages"
    }

    /// The file handed to Pages through Launch Services, Pages launched hidden if it is not running.
    static func openHidden(_ file: URL, in app: URL) -> Error? {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        configuration.hides = true
        configuration.addsToRecentItems = false
        let done = DispatchSemaphore(value: 0)
        nonisolated(unsafe) var failed: Error?
        NSWorkspace.shared.open([file], withApplicationAt: app, configuration: configuration) { _, error in
            failed = error
            done.signal()
        }
        done.wait()
        return failed
    }

    static func quit(_ bundle: String) {
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
