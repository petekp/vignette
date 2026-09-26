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
    /// What the window asks AppDelegate for rather than doing itself: its own actions, which
    /// already log, and the watcher's answer about the folder.
    struct Callbacks {
        var restoreAppleDefaults: () -> Void = {}
        var openTweaks: () -> Void = {}
        var installAgentSkill: (URL) -> [SkillInstaller.Result] = { _ in [] }
        var removeAgentSkill: (URL) -> [SkillInstaller.Result] = { _ in [] }
        var folderDenied: () -> Bool = { false }
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
        // AppKit gives a new window's first text field the keyboard, which outlines the count and
        // selects it; nothing here is waiting to be typed, and Tab still reaches the field.
        if !wasVisible { DispatchQueue.main.async { win.makeFirstResponder(nil) } }
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
        // A newly set form measures 2 pt short after its first layout pass and settles on the
        // second, so a window fitted after one pass left General and Screenshots scrolling by 2 pt.
        hosting.layoutSubtreeIfNeeded()
        hosting.needsLayout = true
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
    /// The Agents footer, and the line under the setup page's heading.
    static let agentsLine = "Adds a skill that lets your coding agents show you images and reply to drawings you send them."
    /// macOS's Accessibility alert gives no reason, so the row gives it, and the way around it.
    static let accessibilityReason = "Lets Vignette notice the double tap in any app. A key combination doesn't need it."

    let tab: SettingsTab
    let callbacks: SettingsWindowController.Callbacks

    @ObservedObject private var settings = Settings.shared
    /// What is on disk for each agent, read on show and after every switch.
    @State private var agentRows = SkillInstaller.statuses(home: FileManager.default.homeDirectoryForCurrentUser)
    /// Why the last install or removal failed, by agent directory. The switch shows what is on disk,
    /// so after a failure it is back where it was, and this says why.
    @State private var agentFailures: [URL: String] = [:]
    @State private var trusted = ModifierTap.trusted(prompt: false)
    @State private var folderDenied = false
    /// Neither the Accessibility grant nor macOS's folder permission announces a change, so the
    /// rows that show them look again while the window is up.
    private let poll = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

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
        // A grouped form's scroll view bounces even when everything fits. This keeps it still
        // unless the form is taller than the window, which happens only under fit's screen cap.
        .scrollBounceBehavior(.basedOnSize)
        .frame(width: SettingsView.width)
        .onAppear(perform: look)
        .onReceive(poll) { _ in look() }
    }

    private func look() {
        trusted = ModifierTap.trusted(prompt: false)
        folderDenied = callbacks.folderDenied()
    }

    // MARK: General

    @ViewBuilder private var general: some View {
        Section {
            ShortcutSetting()
            // Here the shortcut is not working yet, so it reads as a warning, where setup's lock
            // reads as a step still to take.
            if settings.data.usesDoubleTap, !trusted {
                PermissionRow(symbol: "lock.fill", title: "Needs Accessibility permission",
                              reason: SettingsView.accessibilityReason, status: .refused) { Accessibility.request() }
            }
        } footer: {
            // Under the title, the wide pop-up would leave the caption half the row's width.
            footer(ShortcutSetting.caption(doubleTap: settings.data.usesDoubleTap))
        }
        Section("Recent screenshots") {
            LabeledContent("How many to show") {
                HStack(spacing: 4) {
                    TextField("", value: recentCount, format: .number)
                        .labelsHidden()
                        .textFieldStyle(.roundedBorder)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 44)
                    Stepper("", value: recentCount, in: 1...100).labelsHidden()
                }
            }
            Toggle("Close after copying a drawing", isOn: binding(\.quickAnnotate))
        }
        Section("System") {
            Toggle("Open at login", isOn: binding(\.launchAtLogin))
            Toggle(isOn: menuBarIcon) {
                Text("Show in menu bar")
                if settings.data.hideMenuBarIcon {
                    Text("Open Vignette again to get back to Settings.")
                }
            }
        }
    }

    // MARK: Screenshots

    @ViewBuilder private var screenshots: some View {
        Section {
            SaveToPicker()
            if folderDenied {
                PermissionRow(symbol: "folder", title: "Vignette doesn't have access to this folder", status: .refused) {
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_FilesAndFolders")!)
                }
            }
            Picker("Format", selection: binding(\.format)) {
                Text("PNG").tag("png")
                Text("JPEG").tag("jpg")
            }
            Toggle("Shadow on window screenshots", isOn: binding(\.windowShadow))
        }
        Section("After a screenshot") {
            Toggle("Copy to the clipboard", isOn: binding(\.copyOnCapture))
            Toggle(isOn: binding(\.annotateOnCapture)) {
                Text("Open it to draw")
                Text("Instead of showing a thumbnail.")
            }
            // Visible with "Open it to draw" on too: a thumbnail that comes back from the editor
            // without a copy, after Send for example, stays this long.
            LabeledContent("Show the thumbnail for") {
                HStack {
                    Slider(value: thumbnailSeconds, in: 2...15).labelsHidden().frame(width: 150)
                    Text("\(Int(settings.data.ui.thumbnailSeconds)) seconds").monospacedDigit()
                        .frame(width: 72, alignment: .trailing)
                }
            }
        }
        Section {
            LabeledContent("macOS screenshot settings") {
                Button("Restore…") { callbacks.restoreAppleDefaults() }
                    .disabled(settings.data.appleOriginal == nil)
            }
        } footer: {
            footer("Vignette replaces the macOS thumbnail. Restore puts back the thumbnail and the folder, format and shadow macOS used before.")
        }
    }

    // MARK: Agents

    @ViewBuilder private var agents: some View {
        Section {
            if agentRows.isEmpty {
                Text("No coding agent found on this Mac. Vignette looks for Claude Code and Codex.")
            } else {
                ForEach(agentRows) { row in
                    Toggle(isOn: installed(row)) {
                        AgentName(row: row, failure: agentFailures[row.root])
                    }
                }
            }
        } footer: {
            if !agentRows.isEmpty { footer(SettingsView.agentsLine) }
        }
        .onAppear(perform: refreshAgents)
        if !agentRows.isEmpty {
            Section {
                Toggle(isOn: binding(\.sendWithReturn)) {
                    Text("Send with Return")
                    Text("Return in the message box sends the drawing. ⌘Return always does.")
                }
            }
        }
    }

    /// On installs the skill and off removes whatever is at `<root>/skills/vignette`. The switch
    /// reads the disk, so a failed install leaves it off.
    private func installed(_ row: AgentSkillStatus) -> Binding<Bool> {
        Binding(get: { row.installed }, set: { on in
            let results = on ? callbacks.installAgentSkill(row.root) : callbacks.removeAgentSkill(row.root)
            if let failed = results.first(where: { $0.outcome == .failed }) {
                agentFailures[row.root] = "Couldn't \(on ? "install" : "remove"): \(failed.detail)"
            } else {
                agentFailures[row.root] = nil
            }
            refreshAgents()
        })
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
        } footer: {
            Text("This tab shows because debug is on in settings.json.").font(.caption).foregroundStyle(.secondary)
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

    /// Whole seconds, rounded here rather than by the slider's `step`, which draws a tick for each.
    private var thumbnailSeconds: Binding<Double> {
        Binding(get: { settings.data.ui.thumbnailSeconds },
                set: { v in settings.update { $0.ui.thumbnailSeconds = v.rounded() } })
    }

    private var menuBarIcon: Binding<Bool> {
        Binding(get: { !settings.data.hideMenuBarIcon }, set: { on in settings.update { $0.hideMenuBarIcon = !on } })
    }

    private func footer(_ text: String) -> some View {
        Text(text).font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Where screenshots are saved, as macOS's own ⌘⇧5 Options menu offers it: the folder in use, the
/// Desktop and Documents, and Other…. The choice is macOS's save location too.
@MainActor
struct SaveToPicker: View {
    @ObservedObject private var settings = Settings.shared
    private static let desktop = "~/Desktop"
    private static let documents = "~/Documents"
    private static let other = "other"

    var body: some View {
        Picker("Save to", selection: choice) {
            if !isCommon(settings.data.screenshotsFolder) {
                item(settings.data.screenshotsFolder).tag(settings.data.screenshotsFolder)
            }
            item(SaveToPicker.desktop).tag(SaveToPicker.desktop)
            item(SaveToPicker.documents).tag(SaveToPicker.documents)
            Divider()
            Text("Other…").tag(SaveToPicker.other)
        }
    }

    private func isCommon(_ path: String) -> Bool {
        [SaveToPicker.desktop, SaveToPicker.documents].contains { AppleScreencapture.samePath($0, path) }
    }

    private func item(_ path: String) -> some View {
        let url = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
        let icon = NSWorkspace.shared.icon(forFile: url.path)
        icon.size = NSSize(width: 16, height: 16)
        return Label { Text(FileManager.default.displayName(atPath: url.path)) } icon: { Image(nsImage: icon) }
    }

    private var choice: Binding<String> {
        Binding(get: {
            let current = settings.data.screenshotsFolder
            return [SaveToPicker.desktop, SaveToPicker.documents].first { AppleScreencapture.samePath($0, current) } ?? current
        }, set: { picked in
            // The panel runs its own modal loop, so it opens after the menu's pick has been handled.
            if picked == SaveToPicker.other { DispatchQueue.main.async { chooseFolder() } } else { settings.update { $0.screenshotsFolder = picked } }
        })
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Choose"
        panel.directoryURL = settings.data.folderURL
        guard panel.runModal() == .OK, let url = panel.url else { return }
        settings.update { $0.screenshotsFolder = (url.standardizedFileURL.path as NSString).abbreviatingWithTildeInPath }
    }
}

/// One row for every permission, in setup and in Settings: a symbol, what is needed, why, and
/// Allow…. A check replaces the button once it is granted. A refusal swaps the symbol for a
/// warning, and Allow… then opens Privacy & Security, since macOS doesn't ask twice.
struct PermissionRow: View {
    enum Status { case ask, refused, granted }
    let symbol: String
    let title: String
    var reason: String?
    let status: Status
    /// Setup gives the window's default button to the next step still to take.
    var isDefault = false
    /// macOS's own prompt is up and has not been answered.
    var busy = false
    let allow: () -> Void

    var body: some View {
        LabeledContent {
            if status == .granted {
                Image(systemName: "checkmark.circle.fill").font(.title3).foregroundStyle(Color.installed)
                    .accessibilityLabel("Allowed")
            } else {
                Button("Allow…", action: allow).keyboardShortcut(isDefault && !busy ? .defaultAction : nil).disabled(busy)
            }
        } label: {
            Label {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                    if let reason {
                        Text(reason).font(.subheadline).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            } icon: {
                if status == .refused {
                    Image(systemName: "exclamationmark.triangle.fill").symbolRenderingMode(.multicolor)
                } else {
                    Image(systemName: symbol).foregroundStyle(.secondary)
                }
            }
        }
    }
}

/// An agent's logo and name, and why its last install failed.
struct AgentName: View {
    let row: AgentSkillStatus
    var failure: String?

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            if let image = Agent.logo(for: row.logoKey) {
                Image(nsImage: image).renderingMode(image.isTemplate ? .template : .original)
                    .resizable().aspectRatio(contentMode: .fit).frame(width: 18, height: 18)
                    .alignmentGuide(.firstTextBaseline) { $0[.bottom] - 4 }
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(row.name)
                if let failure {
                    Label { Text(failure) } icon: {
                        Image(systemName: "exclamationmark.triangle.fill").symbolRenderingMode(.multicolor)
                    }
                    .font(.subheadline).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

/// The shortcut field: it reads the shortcut as glyphs, and takes one typed in.
private struct ShortcutRecorder: NSViewRepresentable {
    let text: String
    /// Starts listening as the view appears, for a recorder the user just asked for.
    var recordNow = false
    let onCommit: (String) -> Void

    func makeNSView(context: Context) -> ShortcutRecorderView {
        let view = ShortcutRecorderView()
        view.recordOnWindow = recordNow
        return view
    }

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
    var recordOnWindow = false

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

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard recordOnWindow, let window else { return }
        recordOnWindow = false
        window.makeFirstResponder(self)
        begin()
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

/// The shortcut: a pop-up of double taps, then Key Combination…, which shows a recorder labelled
/// Keys. macOS's own Dictation and Siri shortcut settings work this way. Shared by the Settings
/// window's General tab and the setup window, which say different things about Accessibility
/// below it, so the permission row is not part of this. Each says what the shortcut does in its
/// own place: Settings under the box, setup under its page's heading.
@MainActor
struct ShortcutSetting: View {
    @ObservedObject private var settings = Settings.shared
    /// Set by picking Key Combination…: the ellipsis promised a question, so the recorder that
    /// appears starts listening.
    @State private var recordNow = false

    static let doubleTaps = ["double-rshift", "double-lshift", "double-rcmd", "double-ropt"]
    private static let combination = "combination"

    /// What the shortcut does. With a double tap, "hold it" leaves open which press to hold.
    static func caption(doubleTap: Bool) -> String {
        "Shows your recent screenshots. " + (doubleTap ? "Hold the second tap to draw on the newest one." : "Hold it to draw on the newest one.")
    }

    var body: some View {
        Picker("Shortcut", selection: choice) {
            ForEach(options, id: \.self) { value in
                Text(ShortcutSetting.title(of: value)).tag(value)
            }
            Divider()
            Text(settings.data.usesDoubleTap ? "Key Combination…" : "Key Combination").tag(ShortcutSetting.combination)
        }
        if !settings.data.usesDoubleTap {
            LabeledContent("Keys") {
                ShortcutRecorder(text: HotKeySpec.parse(settings.data.recentHotkey)?.glyphs ?? settings.data.recentHotkey,
                                 recordNow: recordNow) { shortcut in
                    settings.update { $0.recentHotkey = shortcut }
                }
                .frame(width: 150, height: 24)
                // An AppKit view has no text baseline, so the row would line the label up with its
                // bottom edge. This is where the text it draws sits.
                .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + 4 }
            }
        }
    }

    /// The double taps offered, and the one in the file when settings.json names another.
    private var options: [String] {
        guard let current = currentDoubleTap, !ShortcutSetting.doubleTaps.contains(current) else { return ShortcutSetting.doubleTaps }
        return ShortcutSetting.doubleTaps + [current]
    }

    /// The file's double tap, written the one way the pop-up's tags are.
    private var currentDoubleTap: String? {
        guard case let .doubleTap(code)? = HotKeySpec.parse(settings.data.recentHotkey) else { return nil }
        return HotKeySpec.doubleTapText(forKeyCode: code)
    }

    static func title(of value: String) -> String {
        guard let key = HotKeySpec.parse(value)?.doubleTapKey else { return value }
        return "Press \(key.label) Twice"
    }

    /// Picking Key Combination… writes a working combination straight away, so the setting is never
    /// a choice the file does not hold.
    private var choice: Binding<String> {
        Binding(get: { currentDoubleTap ?? ShortcutSetting.combination },
                set: { value in
                    if value == ShortcutSetting.combination {
                        guard settings.data.usesDoubleTap else { return }
                        recordNow = true
                        settings.update { $0.recentHotkey = SettingsData.defaultKeyCombination }
                    } else {
                        recordNow = false
                        settings.update { $0.recentHotkey = value }
                    }
                })
    }
}

/// The one Accessibility pane, and the one place that opens it.
enum Accessibility {
    static func openSystemSettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }

    /// Asks for trust the way macOS offers it: its own alert, which lists the app in the pane and
    /// whose button opens it. The pane is opened here only when that alert has not come up by
    /// `alertWait`. Opening both at once put the pane in front of the alert, which then waited
    /// behind it and outlived the grant.
    @MainActor
    static func request() {
        _ = ModifierTap.trusted(prompt: true)
        Task { @MainActor in
            let deadline = ContinuousClock.now + alertWait
            while ContinuousClock.now < deadline {
                if alertIsUp { return }
                try? await Task.sleep(for: .milliseconds(100))
            }
            if !alertIsUp { openSystemSettings() }
        }
    }

    /// Measured: the alert was up within half a second of the request.
    private static let alertWait: Duration = .milliseconds(1500)

    /// The alert belongs to macOS's `universalAccessAuthWarn` process. Window owner names need no
    /// Screen Recording permission. If Apple renames the process, this reads false and the pane
    /// opens as well, which is how this worked before.
    private static var alertIsUp: Bool {
        let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
        return windows.contains { $0[kCGWindowOwnerName as String] as? String == "universalAccessAuthWarn" }
    }
}

extension Color {
    /// System green is too light to read as text on a light row (2:1 against white), so light mode
    /// takes Apple's increased-contrast green, 4.4:1. Dark mode keeps system green.
    static let installed = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            ? .systemGreen
            : NSColor(srgbRed: 36 / 255, green: 138 / 255, blue: 61 / 255, alpha: 1)
    })
}
