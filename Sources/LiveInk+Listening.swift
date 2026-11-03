import Foundation

extension LiveInk {
    /// Starts listening, with speech on, as the pointer field shows: the chord on its way to a shortcut
    /// shows no field, so it never turns the microphone on either.
    func listen() {
        guard listening == nil else { return }
        heardBeforeNote = nil
        let settings = Settings.shared.data
        guard settings.liveInkSpeech else { speechProblem = nil; return }
        guard SpeechPermission.granted else {
            Log.write("[speech] not listening: the microphone or speech recognition is not allowed")
            speechProblem = Self.speechNotice
            return
        }
        guard let transcriber = SpeechEngine.make() else {
            Log.write("[speech] error no recognizer for \(Locale.current.identifier)")
            speechProblem = AppleTranscriber.noModel
            return
        }
        speechProblem = nil
        let listening = LiveListening(transcriber: transcriber)
        listening.onWords = { [weak self] words in self?.heard(words) }
        listening.onFinished = { [weak self, weak listening] words in
            guard let self, let listening, self.listening === listening else { return }
            self.doneListening(words, began: listening.began)
        }
        listening.start { [weak self, weak listening] failure in
            Log.write("[speech] error \(failure.detail)")
            guard let self, let listening, self.listening === listening else { return }
            self.listening = nil
            self.speechProblem = failure.reason
        }
        self.listening = listening
        typedOver = note.map { !$0.isEmpty } ?? false
    }

    func heard(_ words: [SpokenWord]) {
        guard !typedOver else { return }
        note?.hear(LiveListening.text(of: words))
    }

    /// Listening ended: the final words replace the partial ones, and with `liveInkSendWhenQuiet` the
    /// ask goes. Words heard before the note opened wait for it.
    func doneListening(_ words: [SpokenWord], began: Date) {
        listening = nil
        heardBeforeNote = nil
        guard let note else { heardBeforeNote = (words, began); return }
        let text = LiveListening.text(of: words)
        guard !typedOver, !text.isEmpty else { return }
        spoken = (words, began)
        note.hear(text)
        if Settings.shared.data.liveInkSendWhenQuiet { note.send() }
    }

    /// A key typed in the note takes over from speech: listening ends, and the words stay the
    /// person's to edit.
    func typedInNote() {
        spoken = nil
        guard let listening, !typedOver else { return }
        typedOver = true
        listening.finish()
    }

    /// Stops listening and drops what was heard.
    func stopListening() {
        listening?.cancel()
        listening = nil
        heardBeforeNote = nil
    }
}
