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
}
