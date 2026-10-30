extension ThumbnailController {
    /// How presented cards arrive: sliding in from the right edge, parked past it for a flight to
    /// start from, or already in place because a flight lands on them.
    enum Entrance { case slide, stayOffscreen, inPlace }
}
