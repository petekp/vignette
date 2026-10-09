import AppKit

/// Live ink notes sent to a session this launch, by request id: writing the note card, storing the
/// request, waiting on the session's turn and making the result card
/// (docs/live-ink-note-cards-2026-10-08.md). `NoteCardWait` decides how each wait ends; this runs it.
@MainActor
final class LiveNoteCards {
    /// How the window looked round a note's ink as it went, which `look(again:)` compares with the
    /// window when the session's turn ends.
    struct Before {
        /// The part of the window compared, `region`, in points from the window's top-left corner;
        /// `ink`, the part under the ink, which decides; and the window's size then.
        let picture: CGImage
        let region: CGRect
        let ink: CGRect
        let windowSize: CGSize
        let windowID: CGWindowID
    }

    /// A note card sent to a session: the window it was on, where its ink was, in global top-left
    /// points, and how the window looked round it until the turn's end no longer needs it.
    private struct Note {
        let shot: Screenshot
        let destination: AgentDestination
        let window: CGWindowID?
        let ink: CGRect
        var before: Before?
        var wait: NoteCardWait
        /// The result card made when the turn ended, which an answer that comes later is drawn on.
        var resultCard: Capture?
    }

    /// A window as it was captured: its picture, its frame in global top-left points, and its pixels
    /// per point. A result card's file is its picture.
    private struct Capture {
        let image: CGImage
        let frame: CGRect
        let pointScale: CGFloat
        var file: URL?
    }

    private enum Input {
        case event(String, NoteCardWait.Event, at: Date)
        case looked(String, after: Capture?, replied: Bool, at: Date)
        case answer(ScreenshotRequests.Record, LiveAnswer, at: Date, done: ([Int]?) -> Void)
    }

    private let folder: FolderWrites
    private let drawings: Drawings
    private let requests: ScreenshotRequests
    private let cards: ThumbnailController
    private let connections: [AgentClient: any AgentConnection]
    private let addMarks: ([AgentMark], String?, URL, @escaping (Result<Int, Drawings.Failure>) -> Void) -> Void
    private var notes: [String: Note] = [:]
    private var timer: Timer?
    /// An effect can answer inside the input that asked for it, as a reply's card does.
    private let hold = EventHold<Input>()

    init(folder: FolderWrites, drawings: Drawings, requests: ScreenshotRequests, cards: ThumbnailController,
         connections: [AgentClient: any AgentConnection],
         addMarks: @escaping ([AgentMark], String?, URL, @escaping (Result<Int, Drawings.Failure>) -> Void) -> Void) {
        self.folder = folder
        self.drawings = drawings
        self.requests = requests
        self.cards = cards
        self.connections = connections
        self.addMarks = addMarks
    }

    /// The notes whose session's turn is being read: `[state] liveInk.watching`.
    var watching: Int { notes.values.filter { $0.wait.isWatching }.count }

    /// A live ink note sent to a session (`LiveInk.share`): the window without the ink lands in the
    /// watch folder with the ink and the words as its drawing, the request names that file, and its
    /// card shows the send as a send from the editor does. A send refused before it is stored takes
    /// the file and its drawing back, and the ink stays on the window, saying why.
    func send(_ note: LiveInk.NoteCard, to destination: AgentDestination, message: String,
              done: @escaping (Result<(request: String, carried: Bool), ScreenshotRequests.Refusal>) -> Void) {
        let refused = ScreenshotRequests.Refusal(reason: SubmissionOutcome.internalReason)
        let (capture, scale) = (note.capture, note.pointScale)
        folder.writeCard(named: "Live ink note", png: { LivePacket.screenshotPNG(capture, pointScale: scale) }, from: nil) { [weak self] url in
            guard let self, let url else { return done(.failure(refused)) }
            let pixels = PixelSize(width: note.capture.width, height: note.capture.height)
            let pointScale = min(max(note.pointScale, Drawing.pointScales.lowerBound), Drawing.pointScales.upperBound)
            let style = Settings.shared.data.ui.textStyle
            let marks = note.marks.compactMap { $0.placed(in: pixels, pointScale: pointScale, style: style) }
            let drawing = Drawing(key: url.path, pixels: pixels, pointScale: pointScale, marks: marks)
            drawings.write(drawing, reason: "built")
            let record: ScreenshotRequests.Record
            do {
                record = try requests.send(png: note.picture, source: url, to: destination, message: message,
                                           instructions: Settings.shared.data.sendInstructions)
            } catch {
                folder.takeBack(url)
                return done(.failure((error as? ScreenshotRequests.Refusal) ?? refused))
            }
            let shot = Screenshot(url: url)
            let wait = NoteCardWait(reportsTurns: connections[destination.address.client]?.reportsTurns ?? false,
                                    hasWindow: note.window != nil, canLookAgain: note.before != nil)
            notes[record.id] = Note(shot: shot, destination: destination, window: note.window, ink: note.ink,
                                    before: note.before, wait: wait)
            // The card flies from the window, carrying the ink, ahead of the watcher's report, which
            // then finds the card there.
            let origin = NSRect(x: note.frame.minX, y: StateReport.primaryHeight - note.frame.maxY,
                                width: note.frame.width, height: note.frame.height)
            let carried = cards.show(shot, flyingFrom: origin, image: NSImage(cgImage: note.capture, size: note.frame.size),
                                     drawing: drawing)
            folder.ready(url)
            cards.showSending(shot, request: record.id, to: destination)
            done(.success((record.id, carried)))
            hold.send(.event(record.id, .sent, at: Date())) { self.handle($0) }
        }
    }

    /// The client answered. Answers the note card the send notice goes on, or nil when the request is
    /// not a note card's or its client has answered already.
    func delivered(_ request: String, failed: Bool) -> Screenshot? {
        guard let note = notes[request] else { return nil }
        hold.send(.event(request, .delivered(failed: failed), at: Date())) { handle($0) }
        return note.wait.delivered ? nil : note.shot
    }

    /// `ScreenshotRequests.Callbacks.presentLive`: a session's answer to a note, as its result card.
    /// Answers nil, and the reply becomes a card on the picture the session was sent, for a request
    /// that is not a note card's this launch, or whose window cannot be captured afresh.
    func answer(_ record: ScreenshotRequests.Record, _ answer: LiveAnswer, done: @escaping ([Int]?) -> Void) {
        hold.send(.answer(record, answer, at: Date(), done: done)) { handle($0) }
    }

    // MARK: Running the waits

    private func handle(_ input: Input) {
        let id: String, event: NoteCardWait.Event, now: Date
        switch input {
        case .event(let request, let happened, let at): (id, event, now) = (request, happened, at)
        case .looked(let request, let after, let replied, let at):
            (id, event, now) = (request, .lookedAgain(changed: after != nil, replied: replied), at)
        case .answer(let record, _, let at, let done):
            guard notes[record.id] != nil else { return done(nil) }
            (id, event, now) = (record.id, .answer, at)
        }
        guard var note = notes[id] else { return }
        let effects = note.wait.handle(event, at: now)
        switch note.wait.phase {
        case .watching, .lookingAgain: break
        default: note.before = nil
        }
        notes[id] = note
        // A Codex note's wait ends with no input of its own, so every input lets the finished ones go.
        notes = notes.filter { !$0.value.wait.isFinished(at: now) }
        for effect in effects { run(effect, id, note, input) }
    }

    private func run(_ effect: NoteCardWait.Effect, _ id: String, _ note: Note, _ input: Input) {
        switch effect {
        case .watchTurn:
            guard timer == nil else { return }
            timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.tick() }
            }
        case .turnEnded:
            Log.write("[live-ink] session's turn ended request=\(id)")
        case .stopWaiting:
            Log.write("[live-ink] stopped waiting on the session request=\(id)")
        case .replyIsTheResult:
            Log.write("[live-ink] the session's reply is the result request=\(id)")
        case .lookAgain:
            guard let before = note.before else { return }
            Task { @MainActor [weak self] in
                let seen = await Self.look(again: before)
                var after: Capture?
                switch seen {
                case .some((.changed(let share, _), let window)):
                    Log.write("[live-ink] landed changed=\(String(format: "%.3f", share))")
                    after = window
                case .some((.unchanged(let share), _)):
                    Log.write("[live-ink] nothing changed under the ink changed=\(String(format: "%.3f", share))")
                case .none:
                    break
                }
                guard let self else { return }
                hold.send(.looked(id, after: after, replied: requests.hasReply(to: id), at: Date())) { self.handle($0) }
            }
        case .makeResultCard:
            guard case .looked(_, let after?, _, _) = input else { return }
            addResult(after.image, pointScale: after.pointScale, marks: [], from: note.destination) { [weak self] url in
                guard let url else { return }
                var card = after
                card.file = url
                self?.notes[id]?.resultCard = card
            }
        case .sayDone:
            guard FileManager.default.fileExists(atPath: note.shot.url.path) else { return }
            Log.write("[live-ink] done with no result card request=\(id)")
            cards.finished(note.shot, request: id, in: note.destination)
        case .drawReplyOnFreshCapture:
            guard case .answer(let record, let answer, _, let done) = input else { return }
            drawFresh(answer, for: record, on: note, done: done)
        case .drawReplyOnResultCard:
            guard case .answer(_, let answer, _, let done) = input else { return }
            drawOnResultCard(answer, for: id, on: note, done: done)
        case .drawReplyOnSentPicture:
            guard case .answer(_, _, _, let done) = input else { return }
            done(nil)
        }
    }

    /// Reads the session's turn on each note twice a second, until none is watched. Nothing on the
    /// screen waits on it, so clearing the ink or a new note leaves it running.
    private func tick() {
        let now = Date()
        for id in Array(notes.keys) {
            guard let note = notes[id], note.wait.isWatching else { continue }
            let turn = connections[note.destination.address.client]?.turn(of: note.destination)
            hold.send(.event(id, .turn(turn, replied: requests.hasReply(to: id)), at: now)) { handle($0) }
        }
        notes = notes.filter { !$0.value.wait.isFinished(at: now) }
        if !notes.values.contains(where: { $0.wait.isWatching }) {
            timer?.invalidate()
            timer = nil
        }
    }

    // MARK: Whether it landed

    /// The window round `ink`, a rect in global top-left points, as the packet captured it: the
    /// ink's shapes with `LiveChange.reach` round them, inside the web page when there is one. Nil
    /// for a packet of no one window.
    static func before(_ packet: LivePacket, ink: CGRect) -> Before? {
        guard let window = packet.windowID, !ink.isNull else { return nil }
        let room = packet.page.map { $0.intersection(packet.frame) } ?? packet.frame
        guard let under = LiveChange.region(around: ink, in: room),
              let region = LiveChange.region(around: ink, in: room, margin: LiveChange.reach),
              let picture = LiveChange.crop(packet.capture, frame: packet.frame, to: region) else { return nil }
        let origin = CGVector(dx: -packet.frame.minX, dy: -packet.frame.minY)
        return Before(picture: picture, region: region.offsetBy(dx: origin.dx, dy: origin.dy),
                      ink: under.offsetBy(dx: origin.dx, dy: origin.dy), windowSize: packet.frame.size, windowID: window)
    }

    /// The window round the ink now, twice `LiveChange.settle` apart, against `before`, with the
    /// window as it is now. Nil when the window is gone or changed size.
    private static func look(again before: Before) async -> (LiveChange.Outcome, Capture)? {
        do {
            let after = try await LivePacket.capture(window: before.windowID)
            try await Task.sleep(nanoseconds: UInt64(LiveChange.settle * 1_000_000_000))
            let again = try await LivePacket.capture(window: before.windowID)
            guard abs(after.frame.width - before.windowSize.width) < 1, abs(after.frame.height - before.windowSize.height) < 1 else {
                Log.write("[live-ink] can't tell whether it landed: the window changed size")
                return nil
            }
            let region = before.region.offsetBy(dx: after.frame.minX, dy: after.frame.minY)
            let regionAgain = before.region.offsetBy(dx: again.frame.minX, dy: again.frame.minY)
            let ink = before.ink.offsetBy(dx: -before.region.minX, dy: -before.region.minY)
            return await Task.detached(priority: .userInitiated) { () -> (LiveChange.Outcome, Capture)? in
                guard let now = LiveChange.crop(after.image, frame: after.frame, to: region) else { return nil }
                let later = LiveChange.crop(again.image, frame: again.frame, to: regionAgain)
                return (LiveChange.compare(before: before.picture, after: now, again: later, size: region.size, ink: ink),
                        Capture(image: again.image, frame: again.frame, pointScale: CGFloat(again.image.width) / again.frame.width))
            }.value
        } catch {
            Log.write("[live-ink] can't tell whether it landed: \(error)")
            return nil
        }
    }

    // MARK: Result cards

    /// A session's answer to a note, as its result card: the note's window captured afresh, with the
    /// answer drawn on it as a card draws one, each mark at the words it names in that capture, since
    /// the session has likely changed what the window shows. Answers nil when the window cannot be
    /// captured, and the reply then becomes a card on the picture the session was sent.
    private func drawFresh(_ answer: LiveAnswer, for record: ScreenshotRequests.Record, on note: Note,
                           done: @escaping ([Int]?) -> Void) {
        guard let window = note.window else { return done(nil) }
        let request = record.id
        let destination = AgentDestination(id: record.destinationID, name: record.destinationName, address: record.address)
        let ui = Settings.shared.data.ui
        Task { @MainActor [weak self] in
            do {
                let packet = try await LivePacket.build(at: CGPoint(x: note.ink.midX, y: note.ink.midY), window: window, ink: [],
                                                        style: ui.textStyle, markStyle: ui.markStyle)
                // A window off the screen, minimized or closed, is not captured: `build` takes the
                // window under the point then, which is another app's.
                guard packet.windowID == window else {
                    Log.write("[live-ink] no result capture for request=\(request): its window is not on the screen")
                    return done(nil)
                }
                let card = ResultCard(frame: packet.frame, pixels: PixelSize(width: packet.capture.width, height: packet.capture.height),
                                      pointScale: packet.scale, page: packet.page, lines: packet.lines)
                let drawn = card.marks(for: answer, about: note.ink, style: ui.textStyle, agent: note.destination.client.rawValue)
                Log.write("[live-ink] result for request=\(request) marks=\(answer.marks.count) notFound=\(drawn.notDrawn.count)")
                guard let self else { return done(nil) }
                addResult(packet.capture, pointScale: packet.scale, marks: drawn.marks, from: destination) { url in
                    done(url == nil ? nil : drawn.notDrawn)
                }
            } catch {
                Log.write("[live-ink] no result capture for request=\(request): \(error)")
                done(nil)
            }
        }
    }

    /// A session's answer that came after its note's result card was made, drawn on that card, each
    /// mark at the words it names in the card's picture. Answers nil when there is no such card, and
    /// the reply then becomes a card on the picture the session was sent.
    private func drawOnResultCard(_ answer: LiveAnswer, for request: String, on note: Note, done: @escaping ([Int]?) -> Void) {
        guard let made = note.resultCard, let file = made.file, FileManager.default.fileExists(atPath: file.path) else {
            return done(nil)
        }
        let style = Settings.shared.data.ui.textStyle
        let agent = note.destination.client.rawValue
        Task { @MainActor [weak self] in
            let image = made.image
            let lines = await Task.detached(priority: .userInitiated) { LivePacket.read(image) }.value
            // The page is not known here, so the words may go anywhere on the picture.
            let card = ResultCard(frame: made.frame, pixels: PixelSize(width: image.width, height: image.height),
                                  pointScale: made.pointScale, page: nil, lines: lines)
            let drawn = card.marks(for: answer, about: note.ink, style: style, agent: agent)
            Log.write("[live-ink] result for request=\(request) marks=\(answer.marks.count) notFound=\(drawn.notDrawn.count) on \(file.lastPathComponent)")
            guard let self else { return done(nil) }
            guard !drawn.marks.isEmpty else { return done(drawn.notDrawn) }
            addMarks(drawn.marks, agent, file) { result in
                guard case .failure(let failure) = result else { return done(drawn.notDrawn) }
                Log.write("[live-ink] error result marks \(file.lastPathComponent): \(failure)")
                done(nil)
            }
        }
    }

    /// A live ink note's result, as a card from the session it went to: `window`, the note's window
    /// as it was when the result came, with `marks` from the session's answer. It carries the agent
    /// and the session as a push with `add` does, so it wears the agent's tab and Reply on it goes
    /// back to that session. Answers the card's file, or nil when it was not made.
    private func addResult(_ window: CGImage, pointScale: CGFloat, marks: [AgentMark], from destination: AgentDestination,
                           done: @escaping (URL?) -> Void) {
        folder.writeCard(named: "Live ink result", png: { LivePacket.screenshotPNG(window, pointScale: pointScale) },
                         from: destination) { [weak self] url in
            guard let self, let url else { return done(nil) }
            let name = url.lastPathComponent
            let agent = destination.client.rawValue
            let show = { [weak self] in
                guard let self else { return }
                Log.write("[live-ink] result card \(name) agent=\(agent) marks=\(marks.count)")
                folder.ready(url)
                done(url)
            }
            guard !marks.isEmpty else { return show() }
            addMarks(marks, agent, url) { result in
                if case .failure(let failure) = result { Log.write("[live-ink] error result marks \(name): \(failure)") }
                show()
            }
        }
    }
}
