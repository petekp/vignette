extension LiveInk {
    /// What a stroke did, as `[live-ink]` lines and `live-ink-stroke` answer it.
    enum Outcome {
        case drew(MarkKind)
        case erased(MarkKind)
        /// A tap on an answer's loop or arrow, which made it the person's.
        case picked(MarkKind)
        /// A tap on no mark.
        case missed
        /// A stroke that is no mark and no tap.
        case nothing

        var description: String {
            switch self {
            case .drew(let kind): "drew \(kind.rawValue)"
            case .erased(let kind): "erased \(kind.rawValue)"
            case .picked(let kind): "picked \(kind.rawValue)"
            case .missed: "tap on no mark"
            case .nothing: "nothing"
            }
        }
    }
}
