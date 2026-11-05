import AppKit

/// What live ink hears, shown in the note: the words, and the waveform while it listens.
extension LiveNotePopover {
    /// Shows what the person is saying, until they type: a word typed is theirs to keep. While the
    /// waveform shows, the words come a letter at a time.
    func hear(_ words: String) {
        guard let voice, !sent, !closing else { return put(words) }
        voice.hear(words)
    }

    /// Live ink is listening into the empty note: the waveform stands where the words will go, and the
    /// prompt fades for it.
    func startListening() {
        guard voice == nil, !sent, !closing, isEmpty else { return }
        let voice = NoteVoice(content: content)
        voice.onResize = { [weak self] in self?.refit() }
        voice.onDone = { [weak self, weak voice] in
            guard let self, let voice, self.voice === voice else { return }
            self.voice = nil
            self.content.showsListening(false, duration: Self.focusFade * Settings.shared.motionScale)
            self.showPlaceholder()
        }
        self.voice = voice
        content.showsListening(true, duration: Self.focusFade * Settings.shared.motionScale)
        showPlaceholder()
    }

    /// The input's level while live ink listens, for the waveform.
    func hearLevels(_ levels: [Float]) { voice?.add(levels: levels) }

    /// Listening ended: the last words show, and the waveform folds into the caret.
    func stopListening() { voice?.end() }

    func dropVoice() {
        voice?.cancel()
        voice = nil
    }

    /// Puts `words` in the field, the caret after them.
    func put(_ words: String) {
        guard !sent, !closing else { return }
        content.field.stringValue = words
        // The caret follows the words, so typing after them adds to the end.
        (content.field.currentEditor() as? NSTextView)?.setSelectedRange(NSRange(location: (words as NSString).length, length: 0))
        refit()
    }
}
