import CoreGraphics
import XCTest

extension LiveAsksEnvironment {
    // MARK: Answering

    func showSay(for id: LiveAsks.Ask.ID) {
        let effects = send(.arrived(.replyCame, for: id))
        guard effects.contains(.showReply) else { return }
        run(effects)
        let reply: Mark
        if var shown = asks.ask(id)?.say, case .text(var words) = shown.geometry {
            words.text += " more"
            shown.geometry = .text(words)
            reply = shown
        } else {
            reply = note("It's", agent: true)
        }
        _ = send(.streamed(reply, for: id))
        put([reply])
    }

    func answered(for id: LiveAsks.Ask.ID) {
        let effects = send(.arrived(.answerCame, for: id))
        guard effects.contains(.drawAnswer) else { return }
        run(effects)
        let reply = asks.ask(id)?.say ?? note("It's a button.", agent: true)
        let shapes = (0..<Int.random(in: 0...3, using: &rng)).map { _ in shape(agent: true) }
        let held = shapes.filter { _ in chance(3) }
        let shown = [reply] + shapes.filter { shape in !held.contains { $0.id == shape.id } }
        _ = send(.answered(reply: reply, actions: chance(2) ? [] : [LiveAnswer.Action("Fix it")], findings: shapes.map { [$0.id] },
                           shown: Set(shown.map(\.id)), for: id))
        put(shown)
        // `pullFocus`
        if !held.isEmpty {
            letGoOfFocus()
            if chance(4) {
                _ = send(.answerShown(Set(held.map(\.id)), for: id))
                put(held)
            } else {
                for (n, stop) in held.enumerated() { owe(.focus([stop], id), in: (n + 1)...(n + 1)) }
            }
        }
    }

    func nextFocus(_ stop: [Mark], for id: LiveAsks.Ask.ID) {
        if let previous = focusShown { dropFocus(previous.stop) }
        focusShown = (stop, id)
        _ = send(.answerShown(Set(stop.map(\.id)), for: id))
        if chance(2), var reply = asks.ask(id)?.say, case .text(var words) = reply.geometry, asks.answer(of: reply.id) == id {
            words.origin.y += 40
            reply.geometry = .text(words)
            _ = send(.replyRedrawn(reply))
            put(stop + [reply])
        } else {
            put(stop)
        }
    }

    func letGoOfFocus() {
        owed.removeAll { $0.owed.isFocus }
        guard let shown = focusShown else { return }
        focusShown = nil
        dropFocus(shown.stop)
    }

    /// `letGoOfTour(of:)`: the focus goes only when it is that ask's.
    func letGoOfFocus(of id: LiveAsks.Ask.ID) {
        let ours = owed.contains { if case .focus(_, let owner) = $0.owed { owner == id } else { false } } || focusShown?.ask == id
        if ours { letGoOfFocus() }
    }

    func dropFocus(_ stop: [Mark]) {
        let ids = Set(stop.map(\.id)).intersection(asks.answerMarks)
        guard !ids.isEmpty else { return }
        remove(ids)
    }

    func failed(_ reason: String, for id: LiveAsks.Ask.ID) {
        run(send(.arrived(.failed(reason: reason, shown: shown), for: id)))
    }

    func run(_ effects: [LiveAsks.Effect]) {
        for effect in effects {
            switch effect {
            case .ended(let id): release(id)
            case .send(let id): responderTakes(id)
            case .interrupt: break
            case .removeAnswer(let id, let gone): removeAnswer(gone, of: id)
            case .setAside(let id, let ids): setAside(ids, of: id)
            case .restore(let reply, let reason, let brought, let followUp):
                if !brought.isEmpty { bringBack(brought) }
                if let followUp { release(followUp) }
                restoreAnswer(reply, saying: reason)
            case .say(let id, let reason): say(reason, for: id)
            case .notice(let reply, let reason): notice(reason, in: reply)
            case .remove(let ids): remove(ids)
            case .finish(let ids, _): owe(.timer(ids), in: 1...3)
            case .showReply, .drawAnswer, .share, .withdraw, .reopenNote: break
            }
        }
    }

    /// `release`: the focus and the buttons go when they are that ask's.
    func release(_ id: LiveAsks.Ask.ID) {
        letGoOfFocus(of: id)
        hideActions(of: id)
    }

    func notice(_ reason: String, in replyID: Mark.ID) {
        guard var reply = asks.ask(withReply: replyID)?.say else { return }
        reply.notice = reason
        _ = send(.replyRedrawn(reply))
        put([reply])
    }

    func restoreAnswer(_ replyID: Mark.ID, saying reason: String?) {
        guard let ask = asks.ask(withReply: replyID), var reply = ask.say else { return }
        reply.notice = reason
        _ = send(.replyRedrawn(reply))
        hideActions(of: ask.id)
        put([reply])
    }

    /// Reply's field, when it is open, reports its words as it hides, for the reply it was made for.
    func hideActions(of id: LiveAsks.Ask.ID) {
        guard chance(3) else { return }
        let reply = chance(4) ? made.filter { $0.agent && $0.kind == .text }.randomElement(using: &rng)?.id : asks.ask(id)?.say?.id
        _ = send(.drafted("half typed", reply: reply))
    }

    func say(_ words: String, for id: LiveAsks.Ask.ID) {
        guard let about = asks.ask(id)?.about else { return }
        guard screen.contains(where: { about.contains($0.id) && $0.shapeExtent != nil }) else { return }
        let note = note(words, agent: false)
        _ = send(.conversed(note, for: id))
        put([note])
    }

    func removeAnswer(_ gone: Set<Mark.ID>, of id: LiveAsks.Ask.ID) {
        letGoOfFocus(of: id)
        hideActions(of: id)
        if !gone.isEmpty { remove(gone) }
    }

    func setAside(_ ids: Set<Mark.ID>, of id: LiveAsks.Ask.ID) {
        letGoOfFocus(of: id)
        hideActions(of: id)
        aside[id, default: []] += screen.filter { ids.contains($0.id) }
        screen.removeAll { ids.contains($0.id) }
    }

    func bringBack(_ ids: Set<Mark.ID>) {
        for id in aside.keys {
            screen += (aside[id] ?? []).filter { ids.contains($0.id) }
            aside[id]?.removeAll { ids.contains($0.id) }
        }
    }

    // MARK: Exits

    /// Esc on the newest ask Esc can stop.
    func cancel() {
        guard let id = asks.cancellable(sendsWait: chance(2)) else { return }
        owed.removeAll { $0.owed.heldBy == id && asks.ask(id)?.phase == .asking }
        run(send(.cancelled(id, shown: shown)))
    }

    /// The × over an answer's reply, which shows on any ask with its reply up, while it offers one.
    func dismissAnswer() {
        let replies = asks.asks.filter { ask in
            guard asks.offersDismiss(ask.id), let said = ask.say else { return false }
            return screen.contains { $0.id == said.id } && asks.answer(of: said.id) == ask.id && !asks.isFinishing(said.id)
        }
        guard let ask = replies.randomElement(using: &rng) else { return }
        if ask.phase == .asking { owed.removeAll { $0.owed.heldBy == ask.id } }
        run(send(.dismissed(ask.id)))
    }

    /// Esc with no ask to stop.
    func closeAnswer() {
        guard asks.cancellable(sendsWait: false) == nil, let id = asks.newestAnswerToClose else { return }
        run(send(.dismissed(id)))
    }

    func finished(_ ids: Set<Mark.ID>) {
        run(send(.finished(ids)))
    }

    /// `clear()`, which takes the marks off first, or `setOn(false)`, which takes them off after.
    func clear() {
        let marksFirst = chance(2)
        if marksFirst { screen = [] }
        letGoOfFocus()
        run(send(.cleared))
        // `responder.stop()` drops the ask it holds, with no answer and no failure.
        owed.removeAll { $0.owed.heldBy != nil }
        screen = []
        aside = [:]
    }

    // MARK: Trace

    func name(_ id: Mark.ID?) -> String { id.map { names[$0] ?? "?" } ?? "nil" }

    func list(_ ids: Set<Mark.ID>) -> String { "[" + ids.map { name($0) }.sorted().joined(separator: " ") + "]" }

    func describe(_ ask: LiveAsks.Ask) -> String {
        "#\(ask.id) \(ask.phase)\(ask.toSession ? " session" : "") about=\(list(ask.about)) say=\(name(ask.say?.id))\(ask.picked == nil ? "" : " picked")"
    }

    func describe(_ event: LiveAsks.Event) -> String {
        switch event {
        case .drew(let id): "drew \(name(id))"
        case .noteDiscarded: "noteDiscarded"
        case .removed(let ids): "removed \(list(ids))"
        case .windowGone(let ids): "windowGone \(list(ids))"
        case .arrived(let arrival, let id): "\(describe(arrival)) #\(id)"
        case .conversed(let mark, let id): "conversed \(name(mark.id)) #\(id)"
        case .pictureSent(let fresh, let id): "pictureSent \(fresh) #\(id)"
        case .streamed(let mark, let id): "streamed \(name(mark.id)) #\(id)"
        case .answered(let reply, _, _, let shown, let id): "answered \(name(reply?.id)) shown=\(list(shown)) #\(id)"
        case .drafted(_, let reply): "drafted \(name(reply))"
        case .replyRedrawn(let reply): "replyRedrawn \(name(reply.id))"
        case .answerShown(let ids, let id): "answerShown \(list(ids)) #\(id)"
        case .dismissed(let id): "dismissed #\(id)"
        case .cancelled(let id, _): "cancelled #\(id)"
        case .finished(let ids): "finished \(list(ids))"
        case .cleared: "cleared"
        }
    }

    func describe(_ arrival: LiveAsks.Arrival) -> String {
        switch arrival {
        case .packetCame: "packetCame"
        case .replyCame: "replyCame"
        case .answerCame: "answerCame"
        case .failed(let reason, _): "failed \"\(reason)\""
        case .sentToSession(let ink): "sentToSession ink=\(list(ink))"
        }
    }

    func describe(_ effect: LiveAsks.Effect) -> String {
        switch effect {
        case .ended(let id): "ended #\(id)"
        case .send(let id): "send #\(id)"
        case .interrupt: "interrupt"
        case .share(let about): "share \(list(about))"
        case .showReply: "showReply"
        case .drawAnswer: "drawAnswer"
        case .restore(let reply, _, let aside, _): "restore \(name(reply)) aside=\(list(aside))"
        case .say(let id, _): "say #\(id)"
        case .notice(let reply, _): "notice \(name(reply))"
        case .remove(let ids): "remove \(list(ids))"
        case .withdraw: "withdraw"
        case .reopenNote(let words): "reopenNote \"\(words)\""
        case .removeAnswer(let id, let gone): "removeAnswer #\(id) \(list(gone))"
        case .setAside(let id, let ids): "setAside #\(id) \(list(ids))"
        case .finish(let ids, let how): "finish \(list(ids)) \(how)"
        }
    }
}
