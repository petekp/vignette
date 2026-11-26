import AppKit

// `vignette://show`: an agent points the person at screenshots they already have.
// `docs/agent-single-out-api-2026-11-25.md` is the design.

extension ThumbnailController {
    /// One `show` call, every file checked.
    struct ShowCall {
        let shots: [Screenshot]
        /// Nil for a call with neither `agent=` nor marks: the cards come up as `last` brings them.
        var shown: Shown?
        var marks: [ScreenshotKey: PendingMarks.Entry]
        /// `agent=` and the session as the answer logs them.
        let agent: String?
        let tag: String?
        let asked: CFTimeInterval
    }

    /// What the person's hand is doing in the corner, which a `show` waits for. Nil when it is free.
    var handInCorner: Shown.Wait? {
        if model.pressedCard != nil || flightPress.key != nil { return .press }
        if model.draggedCard != nil { return .drag }
        if model.sweepCard != nil { return .sweep }
        if model.swipe != 0 { return .swipe }
        if !model.forming.isEmpty { return .stitch }
        if model.slidingOut && !visible { return .slideOut }
        return nil
    }

    /// The card a `show` can make for `shot`: false when its header does not read.
    func canShow(_ shot: Screenshot) -> Bool {
        if case .unreadable = Thumbnailer.lookUp(shot.url) { return false }
        return true
    }

    /// Runs `call` once the person's hand has left the corner, after every call that came before it.
    func show(_ call: ShowCall) {
        showQueue.add(call)
        if let wait = handInCorner { Log.write("[show] waits for \(wait.rawValue)") }
        runWaitingShows()
    }

    /// A gesture ends when the person lets go, so the wait looks again on a short timer until then.
    private func runWaitingShows() {
        showWait?.invalidate()
        showWait = nil
        for call in showQueue.take(busy: handInCorner) { place(call) }
        guard !showQueue.isEmpty else { return }
        showWait = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.runWaitingShows() }
        }
    }

    private func place(_ call: ShowCall) {
        for (key, entry) in call.marks { pendingMarks.set(entry, on: key) }
        var joined: [Card] = [], inColumn: [Card] = [], inEditor = 0
        for shot in call.shots {
            if run.key == shot.key { inEditor += 1 }
            else if visible, let card = card(for: shot) { inColumn.append(card) }
            else if let card = makeCard(shot) { joined.append(card) }
        }
        for card in joined { send(.newShot(card.shot.key)) }
        if visible { joined.forEach { insert($0) } } else if !joined.isEmpty { present(cards: joined.reversed()) }
        let dwell = ui.thumbnailSeconds * 2
        if let shown = call.shown, !(joined + inColumn).isEmpty {
            for card in joined + inColumn {
                if model.shown[card.id] != nil { Log.write("[show] ended \(card.shot.url.lastPathComponent) by=replaced") }
                model.shown[card.id] = shown
                post(.shown(shown), on: card.shot, comesUp: false)
            }
            model.dimsUnshown = true
            dimTimer?.invalidate()
            dimTimer = Timer.scheduledTimer(withTimeInterval: dwell, repeats: false) { [weak self] _ in
                MainActor.assumeIsolated { self?.model.dimsUnshown = false }
            }
            NSAccessibility.post(element: NSApp as Any, notification: .announcementRequested, userInfo: [
                .announcement: Shown.announcement(agent: shown.agent, sender: shown.sender, count: joined.count + inColumn.count),
                .priority: NSAccessibilityPriorityLevel.high.rawValue,
            ])
        }
        if joined.isEmpty, model.isStack { revealFirst(of: inColumn) }
        leaveCorner(after: dwell)
        let names = call.shots.map(\.url.lastPathComponent)
        let files = (try? JSONSerialization.data(withJSONObject: names, options: [.withoutEscapingSlashes])).flatMap { String(data: $0, encoding: .utf8) } ?? "[]"
        var detail = "files=\(files)"
        if let agent = call.agent { detail += " agent=\(agent)" }
        if let session = call.shown?.session { detail += " session=\(session.id)" }
        detail += " joined=\(joined.count) inColumn=\(inColumn.count) inEditor=\(inEditor)"
        detail += " marks=\(call.marks.values.map(\.drawing.marks.count).reduce(0, +))"
        let pins = call.marks.values.map(\.pins.count).reduce(0, +)
        if pins > 0 { detail += " pins=\(pins)" }
        detail += " after=\(Int((CACurrentMediaTime() - call.asked) * 1000))ms"
        if let tag = call.tag { detail += " tag=\(tag)" }
        Commands.ok("show", detail)
    }

    /// The session list named `session`, after its `show` came: its calls still waiting, the cards it
    /// showed, their notices and the marks it brought say the name, where they have none yet.
    func named(_ sender: String, of session: AgentAddress) {
        showQueue.update { call in
            guard var shown = call.shown, shown.session == session, shown.sender == nil else { return }
            shown.sender = sender
            call.shown = shown
            for (key, entry) in call.marks where entry.session == session && entry.sender == nil { call.marks[key]?.sender = sender }
        }
        for (id, shown) in model.shown where shown.session == session && shown.sender == nil {
            var named = shown
            named.sender = sender
            model.shown[id] = named
        }
        model.notices.name(sender, of: session)
        pendingMarks.name(sender, of: session)
    }

    /// A keyed stack showing none of `cards` scrolls to the first of them, as a focus move does.
    private func revealFirst(of cards: [Card]) {
        let indices = cards.compactMap { card in model.cards.firstIndex { $0.id == card.id } }
        let inView = indices.contains { index in
            let span = layout.cardSpan(index: index, cards: cardSizes)
            return span.top - model.scroll > 0 && span.bottom - model.scroll < model.viewport
        }
        if !inView, let first = indices.first { scrollToReveal(first) }
    }

    /// `card` opens in the annotator, which ends its shown state. The opening keeps the session that
    /// showed it, for its Send, until the next opening.
    func shownCardOpens(_ card: Card, opening: Opening) {
        model.openedShown = nil
        guard let shown = model.shown.removeValue(forKey: card.id) else { return }
        if let session = shown.session { model.openedShown = (opening, session) }
        _ = model.notices.post(.unshown, on: card.shot.key, seen: true, noticeHold: 0)
        if model.shown.isEmpty { model.dimsUnshown = false }
        Log.write("[show] ended \(card.shot.url.lastPathComponent) by=opened")
    }

    /// The shortcut keeps the cards an agent showed, at the bottom of the column under the recent ones.
    func keptShown() -> [Card] { model.cards.filter { model.shown[$0.id] != nil } }

    func shownCard(of shot: Screenshot) -> Card? {
        model.cards.first { $0.shot.key == shot.key && model.shown[$0.id] != nil }
    }

    /// The agent's marks for `key` drawn over a card `size` across, nil when it has none.
    func agentMarkLayers(for key: ScreenshotKey, size: NSSize) -> Card.AgentMarksDrawn? {
        guard let entry = pendingMarks[key] else { return nil }
        let layers = MarkLayers(pixels: entry.drawing.pixels, queue: MarkLayers.cardQueue)
        layers.setScale(screen.backingScaleFactor)
        layers.show(entry.drawing, filling: size, backingScale: screen.backingScaleFactor, style: ui.textStyle, markStyle: ui.markStyle)
        return Card.AgentMarksDrawn(agent: entry.agent, sender: entry.sender, layers: layers)
    }

    /// The agent's marks on `key` came, were kept or were cleared: its card draws what is left.
    func agentMarksChanged(_ key: ScreenshotKey) {
        guard let index = model.cards.firstIndex(where: { $0.shot.key == key }) else { return }
        model.cards[index].agentMarks?.layers.clear()
        model.cards[index].agentMarks = agentMarkLayers(for: key, size: model.cards[index].size)
    }

    nonisolated static func shownJSON(_ shown: Shown) -> [String: Any] {
        ["agent": shown.agent, "session": shown.session?.id as Any, "sender": shown.sender as Any, "message": shown.message as Any,
         "at": ISO8601DateFormatter().string(from: shown.at)]
    }
}
