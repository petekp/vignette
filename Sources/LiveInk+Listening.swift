import Foundation

extension LiveInk {
    /// Starts listening, with speech on, as the pointer field shows: the chord on its way to a shortcut
    /// shows no field, so it never turns the microphone on either.
    func listen() {
        // A listening still finishing that heard nothing ends now, so this hold is heard from its start.
        // One that heard words is waited for, since they may be the note's.
        if let listening, listening.finishing, listening.words.isEmpty { stopListening() }
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
        let listening = LiveListening(transcriber: transcriber, keysDown: keysDown)
        listening.onWords = { [weak self] words in self?.heard(words) }
        listening.onLevels = { [weak self] levels in self?.hearLevels(levels) }
        listening.onFinished = { [weak self, weak listening] words in
            guard let self, let listening, self.listening === listening else { return }
            self.doneListening(words, began: listening.began, listensAgain: listening.pressedWhileFinishing)
        }
        listening.start { [weak self, weak listening] failure in
            Log.write("[speech] error \(failure.detail)")
            guard let self, let listening, self.listening === listening else { return }
            self.listening = nil
            self.tailMayOpenNote = false
            self.note?.stopListening()
            self.speechProblem = failure.reason
        }
        self.listening = listening
        typedOver = note.map { !$0.isEmpty } ?? false
        if !typedOver { note?.startListening() }
    }

    /// While live ink listens, a stroke ending opens the note without the keys, or moves it to the new
    /// ink, so the words show as they are said. The chord's release gives it the keys. A menu still
    /// open waits for the release, which closes it first.
    func showNoteWhileListening() {
        guard isInking, listening != nil, releaseWatch == nil, LiveMenus.open().isEmpty else { return }
        showNote(takingKeys: false)
    }

    /// A note opened while live ink listens shows what was said so far, with the waveform.
    func listen(into panel: LiveNotePopover) {
        guard let listening, !typedOver else { return }
        panel.startListening()
        if !listening.words.isEmpty { panel.hear(listening.text) }
    }

    /// The chord was let go and the note settled: what is said goes into the note. With no note,
    /// listening stops, unless `keepingTail`: then words heard by the tail's end open one.
    func listenOnceLetGo(keepingTail: Bool = false) {
        tailMayOpenNote = note == nil && keepingTail && listening != nil
        if note != nil || tailMayOpenNote { listening?.released() } else { stopListening() }
        if note != nil, let heard = heardBeforeNote { doneListening(heard.words, began: heard.began) }
    }

    /// Words heard: the first opens the note by the pointer while the chord is held and no note is up.
    func heard(_ words: [SpokenWord]) {
        guard !typedOver else { return }
        if note == nil, !words.isEmpty { showNoteOnTheVoice() }
        note?.hear(LiveListening.text(of: words))
    }

    /// The input's level, for the note's waveform and for the pointer field, which shows the voice
    /// from the moment listening starts.
    func hearLevels(_ levels: [Float]) {
        note?.hearLevels(levels)
        surfaces.forEach { $0.overlay.hearVoice(levels) }
    }

    /// Words were heard since listening began: in the listening under way, or in one that ended
    /// before the note opened.
    var heardWords: Bool { !(listening?.words.isEmpty ?? true) || !(heardBeforeNote?.words.isEmpty ?? true) }

    /// Listening ended: the final words replace the partial ones, and with `liveInkSendWhenQuiet` the
    /// ask goes, when the note has ink to ask about. Words heard before the note opened wait for it.
    /// With `listensAgain`, a hold began while they were finishing, and it listens once they are in the
    /// note. With no note, it does not: listening again would drop the words waiting for one.
    func doneListening(_ words: [SpokenWord], began: Date, listensAgain: Bool = false) {
        listening = nil
        heardBeforeNote = nil
        let opensNote = tailMayOpenNote && !isInking && !words.isEmpty
        tailMayOpenNote = false
        guard let note else {
            heardBeforeNote = (words, began)
            if opensNote { settleInking(opensNote: true) }
            return
        }
        defer {
            note.stopListening()
            if listensAgain, isInking, chordShowsField { listen() }
        }
        let text = LiveListening.text(of: words)
        guard !typedOver, !text.isEmpty else { return }
        spoken = (words, began)
        note.hear(text)
        guard Settings.shared.data.liveInkSendWhenQuiet, !asks.noteInk.isEmpty else { return }
        sendingOnRelease = true
        note.send()
        sendingOnRelease = false
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
        note?.stopListening()
        listening?.cancel()
        listening = nil
        heardBeforeNote = nil
        tailMayOpenNote = false
    }
}
