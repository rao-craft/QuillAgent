import Foundation

/// The measures the kit may change to fit a document to its pages: type size, leading, the space between blocks, the
/// margins, and the blocks pushed to the next page. A draft never sets these.
struct QuillLayout: Equatable, Sendable {
    /// Body type, in points.
    var size: Double
    var lead: Double
    /// Space after a paragraph, in ems.
    var gap: Double
    /// Margins, in points.
    var marginX: Double
    var marginY: Double
    /// Blocks (by index) that start a new page so no paragraph leaves a line alone.
    var pushed: Set<Int> = []
    /// How many steps tighter than the form's own measures.
    var tightened = 0

    /// The form's own measures.
    static func of(_ document: QuillDocument) -> QuillLayout {
        let size: Double = document.face == .serif ? 11 : 10
        switch document.form {
        case .resume, .onepager: return QuillLayout(size: size, lead: 1.4, gap: 0.6, marginX: 60, marginY: 54)
        case .worksheet: return QuillLayout(size: size, lead: 1.45, gap: 0.7, marginX: 66, marginY: 60)
        default: return QuillLayout(size: size, lead: 1.45, gap: 0.75, marginX: 72, marginY: 72)
        }
    }

    /// The floors no tightening passes: type a reader can still read, margins a printer can still print.
    static let floorSize = 9.0, floorLead = 1.3, floorGap = 0.4, floorMarginX = 50.0, floorMarginY = 44.0
    static let steps = 4

    /// One step tighter, or nil at the floors: first the space between blocks, then leading, then margins, then type.
    func tighter() -> QuillLayout? {
        guard tightened < Self.steps else { return nil }
        var next = self
        next.tightened += 1
        switch next.tightened {
        case 1: next.gap = max(gap * 0.75, Self.floorGap); next.lead = max(lead - 0.05, Self.floorLead)
        case 2: next.marginX = max(marginX - 12, Self.floorMarginX); next.marginY = max(marginY - 14, Self.floorMarginY)
        case 3: next.size = max(size - 0.5, Self.floorSize); next.lead = max(next.lead - 0.05, Self.floorLead)
        default: next.size = max(size - 0.5, Self.floorSize); next.gap = max(next.gap * 0.8, Self.floorGap)
        }
        return next
    }
}
