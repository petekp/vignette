import AppKit

// MARK: What an ask's picture is of

extension LiveInk {
    /// What the picture of an ask about `about` is of, from the windows on the screen now.
    func picturePlan(for about: [Mark]) -> LivePacket.Plan {
        let asked = about.filter { $0.kind != .text }.compactMap { mark in
            mark.shapeExtent.map { LivePacket.Asked(id: mark.id, box: $0, window: window(of: mark.id)) }
        }
        return LivePacket.plan(for: asked, windows: LivePacket.listedWindows(), screens: StateReport.screenFrames)
    }

    /// The window each of `marks` is on, for those on one.
    func inkWindows(of marks: [Mark]) -> [Mark.ID: CGWindowID] {
        Dictionary(uniqueKeysWithValues: marks.compactMap { mark in window(of: mark.id).map { (mark.id, $0) } })
    }

    /// The window a mark is on, or goes onto once the menu it was drawn over has closed.
    func window(of id: Mark.ID) -> CGWindowID? { windows.window(of: id) ?? pinsAfterMenus[id] }

    /// Where the pointer is, in global top-left points.
    static var pointer: CGPoint {
        let mouse = NSEvent.mouseLocation
        return CGPoint(x: mouse.x, y: StateReport.primaryHeight - mouse.y)
    }

    /// The box an answer is placed against: round the ink asked about, or for an ask with no ink, the
    /// square round the pointer's ring that a note by the pointer hangs from (`pointerPlace`).
    static func askedBox(_ about: [Mark], spot: CGPoint?) -> CGRect {
        let ink = about.compactMap(\.shapeExtent).reduce(CGRect.null) { $0.union($1) }
        guard ink.isNull, let spot else { return ink }
        let ring = CGPoint(x: spot.x + PointerFieldMotion.ringOffset.dx, y: spot.y + PointerFieldMotion.ringOffset.dy)
        let reach = max(Settings.shared.data.ui.liveInkNoteClearance, 1)
        return CGRect(x: ring.x - reach, y: ring.y - reach, width: reach * 2, height: reach * 2)
    }
}
