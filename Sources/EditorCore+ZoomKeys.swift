extension EditorCore {
    /// The zoom a key asks for: = or + in, - out, and 0 to fit.
    static func zoomRequest(for character: Character) -> ZoomRequest? {
        switch character {
        case "=", "+": return .zoomIn
        case "-": return .zoomOut
        case "0": return .fit
        default: return nil
        }
    }
}
