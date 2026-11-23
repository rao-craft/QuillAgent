import Foundation
import GraniteAgents

/// A call's files, written all or none: each is written beside its place under a hidden name first, and only when every
/// one is written are they moved into place. A file already there with the same bytes is left as it is.
struct QuillFiles {
    struct Written: Equatable {
        let url: URL
        let state: AgentMade.State
    }

    private var staged: [(url: URL, data: Data)] = []

    mutating func stage(_ data: Data, at url: URL) { staged.append((url, data)) }

    /// Every staged file in place, or none of them and the reason.
    func commit() throws -> [Written] {
        let manager = FileManager.default
        var temporary: [(from: URL, to: URL, state: AgentMade.State)] = []
        var written: [Written] = []
        do {
            for (url, data) in staged {
                try manager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                if let old = try? Data(contentsOf: url), old == data {
                    written.append(Written(url: url, state: .unchanged))
                    continue
                }
                let state: AgentMade.State = manager.fileExists(atPath: url.path) ? .rewritten : .written
                let hidden = url.deletingLastPathComponent().appendingPathComponent(".\(url.lastPathComponent).quill-\(UUID().uuidString.prefix(6))")
                try data.write(to: hidden)
                temporary.append((hidden, url, state))
            }
        } catch {
            for item in temporary { try? manager.removeItem(at: item.from) }
            throw QuillError.unwritable("\(error.localizedDescription)")
        }
        for item in temporary {
            do {
                if manager.fileExists(atPath: item.to.path) {
                    _ = try manager.replaceItemAt(item.to, withItemAt: item.from)
                } else {
                    try manager.moveItem(at: item.from, to: item.to)
                }
                written.append(Written(url: item.to, state: item.state))
            } catch {
                throw QuillError.unwritable("\(item.to.path): \(error.localizedDescription)")
            }
        }
        // In the order staged.
        return staged.compactMap { entry in written.first { $0.url == entry.url } }
    }
}
