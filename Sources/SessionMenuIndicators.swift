import AppKit
import QuartzCore

extension SessionMenu {
    /// What a session's row says at its right edge.
    enum Activity: Equatable {
        /// The agent is running a turn.
        case working
        /// When the session was last active, as "2 hr ago".
        case lastActive(String)
    }

    static let working = "working"

    /// The least space between a row's text and the words at its right.
    static let indicatorGap: CGFloat = 24
    static let indicatorFont = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
    /// A section header's own font in AppKit, as `NSMenuItem.sectionHeader` draws it on macOS 27.
    static let headerFont = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize, weight: .semibold)

    /// A group's header, as written, in the secondary label grey. AppKit draws a section header's
    /// title in its tertiary grey, which replaces any of the system's label colours and greys set on
    /// it, but keeps a colour of the app's own.
    @MainActor
    static func header(_ text: String) -> NSMenuItem {
        let item = NSMenuItem.sectionHeader(title: text)
        item.attributedTitle = NSAttributedString(string: text, attributes: [.font: headerFont, .foregroundColor: own(.secondaryLabelColor)])
        return item
    }

    /// `color` at `share` of its own opacity, as a colour of the app's own that resolves it in
    /// whichever appearance draws it. Reading a system colour's opacity directly fixes it to the
    /// appearance current at the time.
    static func own(_ color: NSColor, opacity share: CGFloat = 1) -> NSColor {
        NSColor(name: nil) { appearance in
            var resolved = color
            appearance.performAsCurrentDrawingAppearance { resolved = color.usingColorSpace(.sRGB) ?? color }
            return resolved.withAlphaComponent(resolved.alphaComponent * share)
        }
    }

    /// How "working" shimmers: a soft band crosses the word in `passBeats`, then the word rests for
    /// `restBeats`. Its dot's glow is brightest as each pass starts and faintest as it ends. Both count beats of live ink's thinking light, on its clock
    /// (`LiveMarksLayer.thinkingPeriod`, `thinkingEpoch`), so the menu keeps time with the ink.
    struct Shimmer {
        let passBeats: Double
        let restBeats: Double
        /// The band's width, a little wider than the word, so the fade spreads across most of it.
        static let bandWidth: CGFloat = 52
        /// The word's opacity at the band's centre, as a share of its own.
        static let dip: CGFloat = 0.3

        /// Where the band's centre is at `time` on live ink's clock, from the word's left edge: from
        /// wholly before the word to wholly past it, or nil while the word rests.
        func bandCentre(at time: CFTimeInterval, wordWidth: CGFloat) -> CGFloat? {
            let beat = LiveMarksLayer.thinkingPeriod
            let pass = passBeats * beat, cycle = pass + restBeats * beat
            let into = time - (time / cycle).rounded(.down) * cycle
            guard into < pass else { return nil }
            let progress = CGFloat(into / pass)
            return -Self.bandWidth / 2 + (wordWidth + Self.bandWidth) * progress
        }

        /// 0 to 1: how bright the dot's glow is at `time`, along a cosine over one pass and its rest.
        func glow(at time: CFTimeInterval) -> CGFloat {
            let cycle = (passBeats + restBeats) * LiveMarksLayer.thinkingPeriod
            return CGFloat(0.5 + 0.5 * cos(2 * .pi * time / cycle))
        }

        /// A letter's opacity, as a share of its own, when its centre is at `x` and the band's at
        /// `centre`: a raised cosine, so the band has no edge.
        static func opacity(at x: CGFloat, bandCentre centre: CGFloat) -> CGFloat {
            let u = (x - centre) / bandWidth + 0.5
            guard u > 0, u < 1 else { return 1 }
            return 1 - (1 - dip) * (1 - cos(2 * .pi * u)) / 2
        }
    }

    static let shimmer = Shimmer(passBeats: 1, restBeats: 1)

    /// A row with words at its right edge: a session's activity, or a project's count of running
    /// sessions. They follow its title after a right tab stop, which `SessionMenuIndicators` sets to
    /// one place for every row of a menu, so the words end in one column.
    @MainActor
    final class IndicatorItem: NSMenuItem {
        enum Indicator: Equatable {
            case working
            case lastActive(String)
            case count(Int)
        }

        let indicator: Indicator
        let text: String
        var tabStop: CGFloat = 0
        /// Whether the row is drawn as the menu's highlighted row. The words after the tab carry
        /// colours of their own, so the highlight sets them.
        var drawsHighlighted = false
        /// The shimmer's band over "working", from the word's left edge, or nil while it rests.
        var band: CGFloat?
        /// How bright the dot's glow is, in steps up to `glowSteps`. 0 under Reduce Motion.
        var glow = 0

        init(title: String, indicator: Indicator) {
            self.indicator = indicator
            text = title
            super.init(title: title, action: nil, keyEquivalent: "")
            render()
        }

        required init(coder: NSCoder) { fatalError("init(coder:) is not used") }

        /// How wide the row's text is drawn.
        var textWidth: CGFloat {
            (text as NSString).size(withAttributes: [.font: NSFont.menuFont(ofSize: 0)]).width
        }

        var indicatorWidth: CGFloat {
            switch indicator {
            case .working: Self.glowPad + Self.dotWidth + Self.dotGap + Self.wordWidth
            case .lastActive(let text): (text as NSString).size(withAttributes: [.font: SessionMenu.indicatorFont]).width
            case .count(let count): ("\(count)" as NSString).size(withAttributes: [.font: SessionMenu.indicatorFont]).width
            }
        }

        /// Sets the title: the row's text, a tab, then its words as the row is now.
        func render() {
            let title = NSMutableAttributedString(string: text, attributes: [.font: NSFont.menuFont(ofSize: 0)])
            title.append(NSAttributedString(string: "\t"))
            let font = SessionMenu.indicatorFont
            let lit = NSColor.selectedMenuItemTextColor
            switch indicator {
            case .working:
                title.append(NSAttributedString(attachment: Self.dot(glow: glow, lit: drawsHighlighted)))
                let color = drawsHighlighted ? lit.withAlphaComponent(0.8) : .secondaryLabelColor
                for (letter, centre) in zip(SessionMenu.working, Self.letterCentres) {
                    let opacity = band.map { Shimmer.opacity(at: centre, bandCentre: $0) } ?? 1
                    let faded = opacity < 1 ? SessionMenu.own(color, opacity: opacity) : color
                    title.append(NSAttributedString(string: String(letter), attributes: [.font: font, .foregroundColor: faded]))
                }
            case .lastActive(let words):
                let color = drawsHighlighted ? lit.withAlphaComponent(0.8) : .secondaryLabelColor
                title.append(NSAttributedString(string: words, attributes: [.font: font, .foregroundColor: color]))
            case .count(let count):
                let color = drawsHighlighted ? lit.withAlphaComponent(0.8) : .secondaryLabelColor
                title.append(NSAttributedString(string: "\(count)", attributes: [.font: font, .foregroundColor: color]))
            }
            let paragraph = NSMutableParagraphStyle()
            paragraph.tabStops = [NSTextTab(textAlignment: .right, location: tabStop)]
            title.addAttribute(.paragraphStyle, value: paragraph, range: NSRange(location: 0, length: title.length))
            attributedTitle = title
        }

        static let dotWidth: CGFloat = 6
        static let dotGap: CGFloat = 5
        static let wordWidth = (SessionMenu.working as NSString).size(withAttributes: [.font: SessionMenu.indicatorFont]).width
        /// Each letter's centre in "working", from the word's left edge.
        static let letterCentres: [CGFloat] = SessionMenu.working.indices.map { index in
            let before = (String(SessionMenu.working[..<index]) as NSString).size(withAttributes: [.font: SessionMenu.indicatorFont]).width
            let through = (String(SessionMenu.working[...index]) as NSString).size(withAttributes: [.font: SessionMenu.indicatorFont]).width
            return (before + through) / 2
        }
        /// The glow's reach past the dot's edge, and the steps its brightness takes.
        static let glowPad: CGFloat = 3.5
        static let glowSteps = 24
        /// The glow's opacity at its brightest, at the dot's edge.
        static let glowOpacity: CGFloat = 0.225
        private static var dots: [Int: NSTextAttachment] = [:]

        static func dot(glow: Int, lit: Bool) -> NSTextAttachment {
            let key = glow * 2 + (lit ? 1 : 0)
            if let dot = dots[key] { return dot }
            let dot = dotAttachment(color: lit ? .selectedMenuItemTextColor : .systemGreen,
                                    glow: glowOpacity * CGFloat(glow) / CGFloat(glowSteps))
            dots[key] = dot
            return dot
        }

        /// The green dot before "working", in a soft glow of `glow` opacity, with room for the glow
        /// around it and the space after it, since text drawing ignores kerning on an attachment. Its
        /// centre sits on the middle of the word's x-height, where the eye centres a lower-case word
        /// with no capitals.
        private static func dotAttachment(color: NSColor, glow: CGFloat) -> NSTextAttachment {
            let size = NSSize(width: glowPad + dotWidth + dotGap, height: dotWidth + 2 * glowPad)
            let dot = CGRect(x: glowPad, y: glowPad, width: dotWidth, height: dotWidth)
            let image = NSImage(size: size, flipped: false) { _ in
                let rgb = color.usingColorSpace(.sRGB) ?? color
                if glow > 0, let context = NSGraphicsContext.current?.cgContext,
                   let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
                                             colors: [rgb.withAlphaComponent(glow).cgColor, rgb.withAlphaComponent(0).cgColor] as CFArray,
                                             locations: [dotWidth / 2 / (dotWidth / 2 + glowPad), 1]) {
                    let centre = CGPoint(x: dot.midX, y: dot.midY)
                    context.drawRadialGradient(gradient, startCenter: centre, startRadius: 0, endCenter: centre,
                                               endRadius: dotWidth / 2 + glowPad, options: [])
                }
                color.setFill()
                NSBezierPath(ovalIn: dot).fill()
                return true
            }
            let attachment = NSTextAttachment()
            attachment.image = image
            attachment.bounds = CGRect(origin: CGPoint(x: 0, y: SessionMenu.indicatorFont.xHeight / 2 - size.height / 2), size: size)
            return attachment
        }
    }

    /// How wide `item`'s subtitle is drawn, or 0 without one.
    @MainActor
    static func subtitleWidth(of item: NSMenuItem) -> CGFloat {
        guard #available(macOS 14.4, *), let line = item.subtitle else { return 0 }
        return (line as NSString).size(withAttributes: [.font: subtitleFont]).width
    }
}

/// The words at the right of the session menu's rows: where they end, how they look on the
/// highlighted row, and the shimmer on "working". It is the delegate of the menu and its submenus,
/// and must stay alive while the menu is open.
@MainActor
final class SessionMenuIndicators: NSObject, NSMenuDelegate {
    private let menu: NSMenu
    private var working: [SessionMenu.IndicatorItem] = []
    private var timer: Timer?

    init(menu: NSMenu) {
        self.menu = menu
        super.init()
    }

    /// Lines up the words of every row in the menu and its submenus, and starts the shimmer when a
    /// row says working. Call it after the rows change.
    func refresh() {
        working = []
        align(menu)
        if working.isEmpty { stopShimmer() } else { startShimmer() }
    }

    /// Sets one tab stop for `menu`'s rows: past the widest row's text and its words, or at the right
    /// of the widest item without words, so the words end at the menu's right.
    private func align(_ menu: NSMenu) {
        menu.delegate = self
        let rows = menu.items.compactMap { $0 as? SessionMenu.IndicatorItem }
        let others = menu.items.filter { !($0 is SessionMenu.IndicatorItem) && $0.view == nil }.map { item in
            max(item.attributedTitle?.size().width ?? (item.title as NSString).size(withAttributes: [.font: NSFont.menuFont(ofSize: 0)]).width,
                SessionMenu.subtitleWidth(of: item))
        }
        let stop = max(rows.map { $0.textWidth + SessionMenu.indicatorGap + $0.indicatorWidth }.max() ?? 0, others.max() ?? 0)
        for row in rows {
            row.tabStop = stop
            row.render()
        }
        let holdsAView = menu.items.contains { $0.view != nil }
        if holdsAView { menu.minimumWidth = Self.widthWithoutViews(of: menu) }
        working += rows.filter { $0.indicator == .working }
        for case let submenu? in menu.items.map(\.submenu) { align(submenu) }
    }

    /// How wide AppKit makes `menu` without its rows that are views, such as the search row. A menu
    /// that holds a view leaves the checkmark's column out of its width (10 pt on macOS 15.7, 14 pt
    /// on 27.2), so with a checked row the titles get less room than they are measured to need. On
    /// macOS 15 the words after a row's tab then wrap under its title.
    private static func widthWithoutViews(of menu: NSMenu) -> CGFloat {
        let standIn = NSMenu()
        standIn.font = menu.font
        standIn.showsStateColumn = menu.showsStateColumn
        for item in menu.items where item.view == nil {
            let copy: NSMenuItem
            if item.isSeparatorItem {
                copy = .separator()
            } else if item.isSectionHeader {
                copy = .sectionHeader(title: item.title)
            } else {
                copy = NSMenuItem(title: item.title, action: nil, keyEquivalent: item.keyEquivalent)
                copy.keyEquivalentModifierMask = item.keyEquivalentModifierMask
                copy.state = item.state
                copy.indentationLevel = item.indentationLevel
                if item.submenu != nil { copy.submenu = NSMenu() }
                if #available(macOS 14.4, *) { copy.subtitle = item.subtitle }
            }
            copy.attributedTitle = item.attributedTitle
            copy.image = item.image
            if #available(macOS 27.0, *) { copy.preferredImageVisibility = item.preferredImageVisibility }
            copy.isHidden = item.isHidden
            standIn.addItem(copy)
        }
        return standIn.size.width
    }

    /// Under Reduce Motion or `ui.motion` 0 the word and its dot stay still, with no glow.
    private func startShimmer() {
        guard timer == nil, !working.isEmpty, Settings.shared.motionScale > 0 else { return }
        let timer = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] timer in
            MainActor.assumeIsolated {
                guard let self else { return timer.invalidate() }
                self.tick()
            }
        }
        // The common modes include the menu's own tracking, which a default-mode timer waits out.
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func tick() {
        let time = CACurrentMediaTime() - LiveMarksLayer.thinkingEpoch
        let band = SessionMenu.shimmer.bandCentre(at: time, wordWidth: SessionMenu.IndicatorItem.wordWidth)
        let steps = SessionMenu.IndicatorItem.glowSteps
        let glow = Int((SessionMenu.shimmer.glow(at: time) * CGFloat(steps)).rounded())
        for row in working where band != nil || row.band != nil || row.glow != glow {
            row.band = band
            row.glow = glow
            row.render()
        }
    }

    func menu(_ menu: NSMenu, willHighlight item: NSMenuItem?) {
        for row in menu.items.compactMap({ $0 as? SessionMenu.IndicatorItem }) where row.drawsHighlighted != (row === item) {
            row.drawsHighlighted = row === item
            row.render()
        }
    }

    func menuDidClose(_ menu: NSMenu) {
        self.menu(menu, willHighlight: nil)
        if menu === self.menu { stopShimmer() }
    }

    private func stopShimmer() {
        timer?.invalidate()
        timer = nil
    }
}
