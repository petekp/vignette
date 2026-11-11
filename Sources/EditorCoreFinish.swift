extension EditorCore {
    /// What finishing the drawing does: copy it and close (Done), or hand it to an agent session (Send).
    enum Finish: Equatable { case done, send }

    /// What Return and Cmd+Return finish with. The host sets them from what its bar offers: Send
    /// needs a session to go to, and Return sends only to a session the image itself names.
    struct Finishes: Equatable {
        var returnKey = Finish.done
        var commandReturn = Finish.done
    }
}
