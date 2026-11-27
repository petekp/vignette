import AppKit

extension PinPopover {
    /// The rows over the field: who resolved the pin, its comments but the one being edited, with a
    /// line between two, and the agent at work. A row whose comment is still there stays and moves.
    func showComments(of pin: Pin, editing: Int?, over duration: Double) {
        let ui = Settings.shared.data.ui
        var rows: [PinPopoverColumn.Row] = []
        var rowsNow: [UUID: CommentRow] = [:]
        var separatorsNow: [String: NSView] = [:]
        func separator(_ key: String) {
            let line = separators[key] ?? Self.separator(width: Self.rowWidth)
            separatorsNow[key] = line
            rows.append(.init(key: key, view: line))
        }
        if pin.isResolved { rows.append(.init(key: "resolved", view: resolveControls.resolvedLine)) }
        firstRow = nil
        for (index, comment) in pin.comments.enumerated() where index != editing {
            if !rowsNow.isEmpty { separator("line \(comment.id)") }
            let author = PinHoverCard.Words.writer(comment, capitalized: true)
            let row = commentRows[comment.id].flatMap { $0.author == author ? $0 : nil } ?? makeRow(comment, author: author)
            row.press = { [weak self] in self?.send(.edit(index)) }
            row.delete = { [weak self] in self?.send(.delete(index)) }
            row.resolve = { [weak self] in self?.resolvePressed() }
            let first = rowsNow.isEmpty
            if first { firstRow = row }
            let words = rowWords(comment)
            row.show(words: words.text, color: words.color, status: words.status, note: words.note,
                     resolve: first ? resolveAction : nil, over: duration)
            row.setAccessibilityLabel(([author, PinHoverCard.Words.ago(comment, now: opened)].compactMap { $0 }.filter { !$0.isEmpty }
                                       + [words.status, words.note].compactMap { $0 }).joined(separator: ", ") + ": \(comment.text)")
            rowsNow[comment.id] = row
            rows.append(.init(key: "comment \(comment.id)", view: row))
        }
        if let client = live.working {
            if !rowsNow.isEmpty { separator("line working") }
            let row = working.flatMap { $0.client == client ? $0.row : nil }
                ?? Self.workingRow(client, avatarSize: ui.pinAvatarSize, gap: ui.pinNameGap)
            working = (client, row)
            rows.append(.init(key: "working", view: row))
        } else {
            working = nil
        }
        commentRows = rowsNow
        separators = separatorsNow
        self.rows = rows
    }

    /// A comment's words, in the secondary label colour on a resolved pin, whose comments are done
    /// with; and what its delivery says.
    private func rowWords(_ comment: Pin.Comment) -> (text: String, color: NSColor, status: String?, note: String?) {
        let delivery = live.shown[comment.id]
        return (comment.text, shownState?.resolved == nil ? .labelColor : .secondaryLabelColor, delivery?.words, delivery?.note)
    }

    var firstRowWords: (text: String, color: NSColor, status: String?, note: String?) {
        guard let firstRow, let comment = shown?.comments.first(where: { commentRows[$0.id] === firstRow }) else {
            return ("", .labelColor, nil, nil)
        }
        return rowWords(comment)
    }

    /// A comment's row: a line with the writer's avatar, as the pin's hover card shows it, their name,
    /// "You" or the agent's as "Claude", and how long ago they wrote, and under it their words, all in
    /// the system's face.
    private func makeRow(_ comment: Pin.Comment, author: String) -> CommentRow {
        let ui = Settings.shared.data.ui
        let avatar = NSImageView()
        avatar.imageScaling = .scaleProportionallyUpOrDown
        avatar.wantsLayer = true
        avatar.layer?.cornerRadius = ui.pinAvatarSize / 2
        avatar.layer?.masksToBounds = true
        PinHoverCard.paint(avatar, as: comment.writer)
        let small = NSFont.preferredFont(forTextStyle: .subheadline)
        let name = NSTextField(labelWithString: author)
        name.font = .systemFont(ofSize: small.pointSize, weight: .semibold)
        name.textColor = .labelColor
        name.lineBreakMode = .byTruncatingTail
        let time = NSTextField(labelWithString: PinHoverCard.Words.ago(comment, now: opened) ?? "")
        time.font = small
        time.textColor = .secondaryLabelColor
        time.lineBreakMode = .byTruncatingTail
        let words = NSTextField(wrappingLabelWithString: "")
        words.font = .preferredFont(forTextStyle: .body)
        words.isSelectable = false
        words.preferredMaxLayoutWidth = Self.rowWidth - Self.wordsIndent
        return CommentRow(author: author, avatar: avatar, name: name, time: time, words: words, width: Self.rowWidth,
                          avatarSize: ui.pinAvatarSize, deleteSize: ui.pinDeleteSize,
                          gaps: (name: ui.pinNameGap, words: ui.pinWordsGap, trash: ui.pinPopoverSpacing))
    }
}
