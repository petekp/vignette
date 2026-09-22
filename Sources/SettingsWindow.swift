import AppKit
import Combine
import SwiftUI

/// One tab of the Settings window: a toolbar item, the window title while it is up, and one form.
enum SettingsTab: String, CaseIterable {
    case general, screenshots, agents, developer

    var name: String {
        switch self {
        case .general: return "General"
        case .screenshots: return "Screenshots"
        case .agents: return "Agents"
        case .developer: return "Developer"
        }
    }

    var symbol: String {
        switch self {
        case .general: return "gearshape"
        case .screenshots: return "camera.viewfinder"
        case .agents: return "sparkles"
        case .developer: return "wrench.and.screwdriver"
        }
    }

    var itemIdentifier: NSToolbarItem.Identifier { NSToolbarItem.Identifier("settings.\(rawValue)") }

    init?(itemIdentifier: NSToolbarItem.Identifier) {
        guard let tab = SettingsTab.allCases.first(where: { $0.itemIdentifier == itemIdentifier }) else { return nil }
        self = tab
    }
}

/// A thin editor over settings.json. Every control writes straight to the file.
@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate, NSToolbarDelegate {
    /// The two actions the window asks for rather than performs: both are AppDelegate's own, and
    /// they already toast and log.
    struct Callbacks {
        var restoreAppleDefaults: () -> Void = {}
        var openTweaks: () -> Void = {}
        var installAgentSkill: (URL) -> Void = { _ in }
        var removeAgentSkill: (URL) -> Void = { _ in }
    }

    var callbacks = Callbacks()

    private let settings = Settings.shared
    private var window: NSWindow?
    private var hosting: NSHostingView<SettingsView>?
    private var tab: SettingsTab = .general
    private var watch: AnyCancellable?

    /// `tab` is the tab to open on, for a window opened to ask something; nil keeps the last one.
    /// `activating` is false for a window the user did not ask for: it comes up where they can see
    /// it without taking the keyboard from what they are doing.
    func show(tab: SettingsTab? = nil, activating: Bool = true) {
        let win = window ?? makeWindow()
        let wasVisible = win.isVisible
        select(tab ?? self.tab, animated: wasVisible)
        if !wasVisible { win.center() }
        if activating {
            win.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        } else {
            win.orderFront(nil)
        }
    }

    private func makeWindow() -> NSWindow {
        let win = NSWindow(contentRect: NSRect(x: 0, y: 0, width: SettingsView.width, height: 200),
                           styleMask: [.titled, .closable], backing: .buffered, defer: false)
        win.isReleasedWhenClosed = false
        win.delegate = self
        win.toolbarStyle = .preference
        let toolbar = NSToolbar(identifier: "settings")
        toolbar.delegate = self
        toolbar.allowsUserCustomization = false
        toolbar.displayMode = .iconAndLabel
        win.toolbar = toolbar
        window = win
        watch = settings.$data.sink { [weak self] data in
            guard let self else { return }
            self.debugChanged(data.debug)
            // The form is laid out after this notification, so the window follows a turn later.
            DispatchQueue.main.async { self.fit(animated: true) }
        }
        return win
    }

    /// The Developer tab exists only while `debug` is on, and the file can turn it off under a
    /// window that is showing that tab.
    private func debugChanged(_ debug: Bool) {
        guard let toolbar = window?.toolbar else { return }
        let identifier = SettingsTab.developer.itemIdentifier
        let index = toolbar.items.firstIndex { $0.itemIdentifier == identifier }
        if debug, index == nil {
            toolbar.insertItem(withItemIdentifier: identifier, at: toolbar.items.count)
        } else if !debug, let index {
            toolbar.removeItem(at: index)
            if tab == .developer { select(.general, animated: window?.isVisible == true) }
        }
    }

    private func select(_ tab: SettingsTab, animated: Bool) {
        guard let win = window else { return }
        self.tab = tab
        win.title = tab.name
        win.toolbar?.selectedItemIdentifier = tab.itemIdentifier
        let view = NSHostingView(rootView: SettingsView(tab: tab, callbacks: callbacks))
        hosting = view
        win.contentView = view
        fit(animated: animated)
    }

    /// The window is the height of the form it holds. That height changes with the tab and with
    /// the form's own contents: the recorder comes and goes with the kind of shortcut, and a
    /// caption with the menu bar icon.
    private func fit(animated: Bool) {
        guard let win = window, let hosting else { return }
        hosting.layoutSubtreeIfNeeded()
        // The window has no resize control, so a form taller than the screen would hang off the
        // bottom where nothing can reach it. Capped, the form scrolls inside the window instead.
        let screen = (win.screen ?? NSScreen.main)?.visibleFrame.height ?? .greatestFiniteMagnitude
        let height = min(hosting.fittingSize.height, screen - SettingsView.screenRoom)
        let frame = win.frameRect(forContentRect: NSRect(x: 0, y: 0, width: SettingsView.width, height: height))
        guard abs(frame.height - win.frame.height) > 0.5 else { return }
        // The top-left corner stays put: the title bar is what the eye is anchored on while the
        // window grows or shrinks.
        var target = win.frame
        target.origin.y = win.frame.maxY - frame.height
        target.size = frame.size
        win.setFrame(target, display: true, animate: animated)
    }

    private var tabs: [SettingsTab] {
        SettingsTab.allCases.filter { $0 != .developer || settings.data.debug }
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        tabs.map(\.itemIdentifier)
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        SettingsTab.allCases.map(\.itemIdentifier)
    }

    func toolbarSelectableItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        SettingsTab.allCases.map(\.itemIdentifier)
    }

    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier identifier: NSToolbarItem.Identifier,
                 willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        guard let tab = SettingsTab(itemIdentifier: identifier) else { return nil }
        let item = NSToolbarItem(itemIdentifier: identifier)
        item.label = tab.name
        item.image = NSImage(systemSymbolName: tab.symbol, accessibilityDescription: tab.name)
        item.target = self
        item.action = #selector(pickTab(_:))
        return item
    }

    @objc private func pickTab(_ sender: NSToolbarItem) {
        guard let tab = SettingsTab(itemIdentifier: sender.itemIdentifier) else { return }
        select(tab, animated: true)
    }

    func windowWillClose(_ notification: Notification) {
        DispatchQueue.main.async { FocusReturn.shared.restore(reason: "settings closed") }
    }
}

@MainActor
struct SettingsView: View {
    /// Every tab is this wide; the window takes its height from the form.
    static let width: CGFloat = 480
    /// Title bar plus a margin: how much of the screen's visible height a form may not use.
    static let screenRoom: CGFloat = 60

    let tab: SettingsTab
    let callbacks: SettingsWindowController.Callbacks

    @ObservedObject private var settings = Settings.shared
    /// What is on disk for each agent, read on show and after every settings change.
    @State private var agentRows = SkillInstaller.statuses(home: FileManager.default.homeDirectoryForCurrentUser)

    var body: some View {
        Form {
            switch tab {
            case .general: general
            case .screenshots: screenshots
            case .agents: agents
            case .developer: developer
            }
        }
        .formStyle(.grouped)
        .frame(width: SettingsView.width)
    }

    // MARK: General

    @ViewBuilder private var general: some View {
        Section {
            ShortcutSetting()
            if settings.data.usesDoubleTap, !ModifierTap.trusted(prompt: false) {
                caption("Needs Accessibility permission.")
                Button("Open System Settings") { Accessibility.openSystemSettings() }
            }
        }
        Section {
            LabeledContent("Keep recent screenshots") {
                HStack(spacing: 4) {
                    TextField("", value: recentCount, format: .number)
                        .labelsHidden()
                        .textFieldStyle(.roundedBorder)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 44)
                    Stepper("", value: recentCount, in: 1...100).labelsHidden()
                }
            }
            LabeledContent("Show a new screenshot for") {
                HStack {
                    Slider(value: binding(\.ui.thumbnailSeconds), in: 2...15, step: 1)
                    Text("\(Int(settings.data.ui.thumbnailSeconds))s").monospacedDigit().frame(width: 30)
                }
            }
            Toggle("Launch at login", isOn: binding(\.launchAtLogin))
            Toggle("Show in menu bar", isOn: menuBarIcon)
            if settings.data.hideMenuBarIcon {
                caption("Reopen Settings with open vignette://settings in Terminal.")
            }
        }
    }

    // MARK: Screenshots

    @ViewBuilder private var screenshots: some View {
        Section {
            LabeledContent("Save to") {
                HStack {
                    Text(settings.data.screenshotsFolder).lineLimit(1).truncationMode(.middle)
                    Button("Choose…", action: chooseFolder)
                }
            }
            Toggle("Save macOS screenshots here", isOn: binding(\.syncAppleSaveLocation))
            Picker("Format", selection: binding(\.format)) {
                Text("PNG").tag("png")
                Text("JPEG").tag("jpg")
            }
            Toggle("Show the macOS thumbnail", isOn: binding(\.appleThumbnail))
            caption("With it off, the file is saved right away and Vignette's thumbnail is the only one.")
            Toggle("Shadow on window screenshots", isOn: binding(\.windowShadow))
        }
        Section("After a screenshot") {
            Toggle("Copy to the clipboard", isOn: binding(\.copyOnCapture))
            Toggle("Open it to draw", isOn: binding(\.annotateOnCapture))
            caption("Instead of showing a thumbnail.")
        }
        Section("When you finish drawing") {
            Picker("When you finish drawing", selection: binding(\.quickAnnotate)) {
                Text("Return to the stack").tag(false)
                Text("Copy and close").tag(true)
            }
            .pickerStyle(.radioGroup)
            .labelsHidden()
        }
        Section("macOS") {
            Button("Restore macOS Screenshot Settings…") { callbacks.restoreAppleDefaults() }
                .disabled(settings.data.appleOriginal == nil)
            caption("Puts back the save location, thumbnail, shadow, and format macOS used before Vignette changed them.")
        }
    }

    // MARK: Agents

    @ViewBuilder private var agents: some View {
        Section {
            Text("Vignette can teach your coding agents to show you an image and read back what you draw on it.")
        }
        Section {
            if agentRows.isEmpty {
                Text("No coding agent found on this Mac. Vignette looks for Claude Code and Codex.")
            } else {
                ForEach(agentRows) { row in
                    LabeledContent {
                        HStack {
                            Text(row.status)
                                .multilineTextAlignment(.leading)
                                .fixedSize(horizontal: false, vertical: true)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            if row.installed {
                                Button("Remove") { callbacks.removeAgentSkill(row.root); refreshAgents() }
                            } else {
                                Button("Install") { callbacks.installAgentSkill(row.root); refreshAgents() }
                                    .buttonStyle(.borderedProminent)
                            }
                        }
                    } label: {
                        Text(row.name)
                    }
                }
            }
        }
        .onAppear(perform: refreshAgents)
    }

    private func refreshAgents() {
        agentRows = SkillInstaller.statuses(home: FileManager.default.homeDirectoryForCurrentUser)
    }

    // MARK: Developer

    private var developer: some View {
        Section {
            HStack {
                Button("Tweak UI…") { callbacks.openTweaks() }
                Button("Open Log") { NSWorkspace.shared.open(Log.url) }
                Button("Reveal settings.json") { NSWorkspace.shared.activateFileViewerSelecting([Settings.fileURL]) }
            }
            caption("Shown because debug is on in settings.json.")
        }
    }

    // MARK: Bindings

    private func binding<T>(_ path: WritableKeyPath<SettingsData, T>) -> Binding<T> {
        Binding(get: { settings.data[keyPath: path] }, set: { v in settings.update { $0[keyPath: path] = v } })
    }

    /// The field takes any number typed; the stack holds 1 to 100.
    private var recentCount: Binding<Int> {
        Binding(get: { settings.data.recentCount }, set: { n in settings.update { $0.recentCount = min(max(n, 1), 100) } })
    }

    private var menuBarIcon: Binding<Bool> {
        Binding(get: { !settings.data.hideMenuBarIcon }, set: { on in settings.update { $0.hideMenuBarIcon = !on } })
    }

    private func caption(_ text: String) -> some View {
        Text(text).font(.caption).foregroundStyle(.secondary)
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.directoryURL = settings.data.folderURL
        if panel.runModal() == .OK, let url = panel.url {
            let home = FileManager.default.homeDirectoryForCurrentUser.path
            let path = url.path.hasPrefix(home) ? "~" + url.path.dropFirst(home.count) : url.path
            settings.update { $0.screenshotsFolder = path }
        }
    }
}

/// The shortcut field: it reads the shortcut as glyphs, and takes one typed in.
private struct ShortcutRecorder: NSViewRepresentable {
    let text: String
    let onCommit: (String) -> Void

    func makeNSView(context: Context) -> ShortcutRecorderView { ShortcutRecorderView() }

    func updateNSView(_ view: ShortcutRecorderView, context: Context) {
        view.text = text
        view.onCommit = onCommit
    }
}

/// An NSView because the press has to be caught before anything else sees it: a combination with
/// ⌘ arrives as a key equivalent, which the main menu would take (⌘W closes the window) and which
/// SwiftUI's key handling never reports at all.
private final class ShortcutRecorderView: NSView {
    var text = "" { didSet { if text != oldValue { needsDisplay = true } } }
    var onCommit: (String) -> Void = { _ in }

    private var recording = false { didSet { needsDisplay = true } }
    private var outsideClick: Any?

    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    isolated deinit {
        if let outsideClick { NSEvent.removeMonitor(outsideClick) }
    }

    override func draw(_ dirtyRect: NSRect) {
        let box = bounds.insetBy(dx: 1, dy: 1)
        let path = NSBezierPath(roundedRect: box, xRadius: 6, yRadius: 6)
        NSColor.textBackgroundColor.setFill()
        path.fill()
        path.lineWidth = recording ? 2 : 1
        (recording ? NSColor.controlAccentColor : NSColor.separatorColor).setStroke()
        path.stroke()
        let shown = recording ? "Type a shortcut…" : text
        let style = NSMutableParagraphStyle()
        style.alignment = .center
        style.lineBreakMode = .byTruncatingTail
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: NSFont.systemFontSize),
            .foregroundColor: recording ? NSColor.secondaryLabelColor : NSColor.labelColor,
            .paragraphStyle: style,
        ]
        let height = (shown as NSString).size(withAttributes: attributes).height
        (shown as NSString).draw(in: NSRect(x: box.minX, y: box.midY - height / 2, width: box.width, height: height),
                                 withAttributes: attributes)
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        begin()
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard recording else { return false }
        take(event)
        return true
    }

    override func keyDown(with event: NSEvent) {
        guard recording else { return super.keyDown(with: event) }
        take(event)
    }

    override func resignFirstResponder() -> Bool {
        stop()
        return true
    }

    private func begin() {
        guard !recording else { return }
        recording = true
        // A click on a part of the form that takes no focus leaves this view first responder, so
        // the press itself is what says the user has moved on.
        outsideClick = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
            guard let self, event.window === self.window else { return event }
            if !self.bounds.contains(self.convert(event.locationInWindow, from: nil)) { self.stop() }
            return event
        }
    }

    private func stop() {
        recording = false
        if let outsideClick { NSEvent.removeMonitor(outsideClick) }
        outsideClick = nil
    }

    /// Esc keeps the old shortcut; so does a press with no ⌘⌥⌃ or a key no shortcut can name.
    private func take(_ event: NSEvent) {
        if event.keyCode == 53 { stop(); return }
        let flags = event.modifierFlags.intersection([.command, .option, .control, .shift])
        guard flags.contains(.command) || flags.contains(.option) || flags.contains(.control),
              let shortcut = HotKeySpec.text(keyCode: UInt32(event.keyCode), modifiers: HotKeySpec.carbonModifiers(flags)) else {
            NSSound.beep()
            stop()
            return
        }
        stop()
        window?.makeFirstResponder(nil)
        onCommit(shortcut)
    }
}

/// The shortcut picker and its recorder, shared by the Settings window's General tab and the
/// first-run setup window. What each of those says about Accessibility below it differs, so the
/// permission line is not part of this.
@MainActor
struct ShortcutSetting: View {
    @ObservedObject private var settings = Settings.shared

    enum Kind { case combination, doubleTap }

    var body: some View {
        Picker("Shortcut", selection: kind) {
            Text("Double-tap Right Shift").tag(Kind.doubleTap)
            Text("Key combination").tag(Kind.combination)
        }
        .pickerStyle(.segmented)
        if !settings.data.usesDoubleTap {
            HStack {
                Spacer()
                ShortcutRecorder(text: HotKeySpec.parse(settings.data.recentHotkey)?.glyphs ?? settings.data.recentHotkey) { shortcut in
                    settings.update { $0.recentHotkey = shortcut }
                }
                .frame(width: 140, height: 24)
            }
        }
        Text("Shows your recent screenshots. Hold it to draw on the newest one.")
            .font(.caption).foregroundStyle(.secondary)
    }

    /// Which kind of shortcut is in the file. Choosing the other kind writes a working value of it
    /// straight away, so the setting is never a choice the file does not hold.
    private var kind: Binding<Kind> {
        Binding(get: { settings.data.usesDoubleTap ? .doubleTap : .combination },
                set: { kind in
                    switch kind {
                    case .doubleTap:
                        settings.update { $0.recentHotkey = "double-rshift" }
                    case .combination:
                        if settings.data.usesDoubleTap {
                            settings.update { $0.recentHotkey = SettingsData.defaultKeyCombination }
                        }
                    }
                })
    }
}

/// The one Accessibility pane, and the one place that opens it.
enum Accessibility {
    static func openSystemSettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }
}
