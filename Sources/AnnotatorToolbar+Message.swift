import AppKit

// MARK: The message field's words

extension AnnotatorToolbar.Model {
    /// Nothing was typed in the field since the image opened: it holds the words it opened with.
    var messageAsOpened: Bool { message == messageOnOpen }

    /// The message field took the keys on its own and is still empty, or holds only the words the
    /// image opened with, so nothing typed now asks to send: Return and Esc do what they do on
    /// the image.
    var fieldUntouched: Bool { tookKeysOnOpen && (fieldEmpty || messageAsOpened) }

    /// What Return in the message field does. In an untouched field, what it does on the image,
    /// which never sends to a session Vignette picked.
    var fieldReturn: EditorCore.Finish { fieldUntouched ? offer.finishes.returnKey : .send }

    /// Esc in an untouched field closes the editor, as on the image. Otherwise it hands the keys back.
    var fieldEscCloses: Bool { fieldUntouched }

    /// The most characters the message holds, as for a text mark.
    static let messageLimit = MarkFields.maxTextLength

    /// The message as it joins the line Send puts in the session, which is one line: its words with
    /// one space between each, whatever line breaks, tabs or spaces were there. Nil when there are none.
    var sentMessage: String? {
        let line = message.asOneLine
        return line.isEmpty ? nil : line
    }
}
