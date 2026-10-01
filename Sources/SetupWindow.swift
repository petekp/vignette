import AppKit
import Combine
import SwiftUI

extension Notification.Name {
    /// Posted when the recent-stack shortcut fires. The setup window is the only listener: it is
    /// how "try it" learns that the user's own hand worked, rather than that the stack appeared,
    /// which it does not on a Mac with no screenshots yet.
    static let hotKeyFired = Notification.Name("\(Identity.bundleID).hotkey.fired")
    /// Posted when the shortcut is held and lifts the newest screenshot into the editor.
    static let hotKeyHeld = Notification.Name("\(Identity.bundleID).hotkey.held")
}

/// Where macOS's permission for the watch folder stands, as the setup window shows it.
enum FolderAccess {
    /// Nothing has read the folder yet, so macOS has not asked.
    case ask
    /// Something has, and macOS's prompt is waiting for an answer.
    case waiting
    case granted
    case refused
}

/// The window a first launch opens: a page per step. Welcome, with the folder permission when macOS
/// protects the folder; the shortcut, with the Accessibility permission the double tap needs; and
/// the agent skill, when Claude Code or Codex is on this Mac.
///
/// It exists because of what the permissions cost. macOS gives an app few chances at each dialog,
/// and one raised during launch, before the user has seen the app, spends the chance on a question
/// nobody asked. Here each dialog answers a row that says why it is needed.
@MainActor
final class SetupWindowController: NSObject, NSWindowDelegate {
    /// What the window asks AppDelegate for rather than doing itself.
    struct Callbacks {
        /// Asked again on every look rather than read once: a folder filled while the window is
        /// open is the case the window is asking the user to create.
        var hasScreenshots: () -> Bool = { false }
        var folderAccess: () -> FolderAccess = { .granted }
        /// Starts the watcher, whose first read of a protected folder is what raises macOS's prompt.
        var askFolder: () -> Void = {}
        var installAgentPlugin: ([URL]) -> Void = { _ in }
        /// Whether the menu bar icon can be seen: it is off, or macOS found no room for it.
        var menuBarIconVisible: () -> Bool = { true }
        /// Flies the closing window into the menu bar icon, calls `close` once it may close, and
        /// `finished` once the intro has gone. False when there is no intro, and the window closes
        /// as any window does.
        var introduceMenuBar: (NSWindow, _ close: @escaping () -> Void, _ finished: @escaping () -> Void) -> Bool = { _, _, _ in false }
    }

    private let settings = Settings.shared
    private var window: NSWindow?
    private var model: SetupModel?
    /// Set when the app starts to quit. AppKit closes the window after `applicationWillTerminate`,
    /// and a quit is not an answer: nothing the window would apply on closing is applied.
    var quitting = false

    /// Whether a first launch should open this. Recorded as done when the window closes rather than
    /// when it opens, so a launch quit part way through asks again.
    ///
    /// The permissions it asks for belong to this Mac, and a settings.json synced from another Mac
    /// through dotfiles says `done` too. So this Mac keeps its own record in the app's defaults,
    /// which also stands in for a file that cannot be written. A setup finished before that record
    /// existed left the file's `done` and, from every launch, the Application Support folder. A test
    /// launch has only its scratch file to go by.
    var isUnasked: Bool {
        if Settings.isOverridden { return settings.data.setupChoice == .unasked }
        if UserDefaults.standard.bool(forKey: SetupWindowController.doneOnThisMacKey) { return false }
        return !(settings.data.setupChoice == .done && launchedHereBefore)
    }

    private static let doneOnThisMacKey = "setupDoneOnThisMac"
    /// Read before this launch creates the folder.
    private let launchedHereBefore = FileManager.default.fileExists(atPath: Identity.applicationSupportURL.path)

    /// `protectedArea` names the folder macOS will ask about ("your Desktop"), or is nil when it
    /// won't ask, which leaves the welcome page without a folder row.
    func show(protectedArea: String?, callbacks: Callbacks) {
        if let win = window {
            win.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let model = SetupModel(protectedArea: protectedArea,
                               agents: AgentPlugin.statuses(home: FileManager.default.homeDirectoryForCurrentUser),
                               callbacks: callbacks)
        model.granted = { [weak self] in self?.granted() }
        model.folderAnswered = { [weak self] access in self?.folderAnswered(access) }
        // Not `performClose`: it shows the close button pressed while it simulates the click, and
        // the intro's picture of the window would carry that pressed button into the menu bar.
        model.done = { [weak self] in
            guard let self, let window = self.window, self.windowShouldClose(window) else { return }
            window.close()
        }
        self.model = model
        let host = NSHostingController(rootView: SetupView(model: model))
        let win = NSWindow(contentViewController: host)
        // A welcome window rather than a form: no title bar across the top, and the app's icon and
        // name inside instead. The title still names the window for VoiceOver and Mission Control.
        win.styleMask = [.titled, .closable, .fullSizeContentView]
        win.titlebarAppearsTransparent = true
        win.titleVisibility = .hidden
        win.isMovableByWindowBackground = true
        win.title = "Welcome to \(Identity.name)"
        win.isReleasedWhenClosed = false
        win.delegate = self
        win.setContentSize(NSSize(width: SetupView.width, height: SetupView.height))
        win.center()
        window = win
        Log.write("[setup] shown folder=\(protectedArea.map { "\"\($0)\"" } ?? "none") agents=\(model.agents.count)")
        win.makeKeyAndOrderFront(nil)
        // A window asking for a permission has to be the frontmost thing, or the dialog it raises
        // arrives behind whatever the user was doing.
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Brings the window forward while it is open, for a reopen of the app during setup.
    func bringToFront() -> Bool {
        guard let window, window.isVisible else { return false }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        return true
    }

    /// The grant is made in System Settings, which leaves this window behind it. What comes next,
    /// trying the keys, is asked here, so the window comes back.
    private func granted() {
        Log.write("[setup] Accessibility granted")
        comeBack()
    }

    /// macOS's folder prompt takes the focus, and answering it hands the focus to the app that had
    /// it before Vignette, which covers this window. Vignette has no Dock icon to bring it back by.
    private func folderAnswered(_ access: FolderAccess) {
        Log.write("[setup] folder \(access == .granted ? "granted" : "refused") active=\(NSApp.isActive)")
        comeBack()
    }

    private func comeBack() {
        guard model != nil else { return }   // closed: a grant made later must not reopen it
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Closing is where the menu bar icon is introduced: the window flies into it, and closes once
    /// its picture covers it (`MenuBarIntro`). A second close while that waits changes nothing.
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard !quitting, let model else { return true }
        if introducing { return false }
        introducing = model.callbacks.introduceMenuBar(sender, { sender.close() }) { [weak self] in
            self?.afterIntro?()
            self?.afterIntro = nil
        }
        return !introducing
    }

    private var introducing = false
    private var afterIntro: (() -> Void)?

    func windowWillClose(_ notification: Notification) {
        guard let model else { return }
        if quitting {
            Log.write("[setup] quit before it was done; asks again at the next launch")
            self.model = nil
            return
        }
        // Vignette can't work without the folder, so a window closed before it asked asks now.
        if model.callbacks.folderAccess() == .ask { model.callbacks.askFolder() }
        settings.update { $0.setup = SetupState.done.rawValue }
        UserDefaults.standard.set(true, forKey: SetupWindowController.doneOnThisMacKey)
        // The plugin is installed only for someone who saw the page offering it. Closed earlier, the
        // offer is left unmade, and the next launch makes it in the Settings window.
        var skill = "not-offered"
        if model.sawAgents {
            let roots = model.agents.filter { !$0.installed && model.chosen.contains($0.root) }.map(\.root)
            if !roots.isEmpty { model.callbacks.installAgentPlugin(roots) }
            if let claude = model.claudeWithoutReadRule, model.claudeReads { ClaudeReadRule.apply(true, in: claude) }
            settings.update { $0.agentSkill = AgentSkill.off.rawValue }
            skill = roots.isEmpty ? "none" : roots.map(\.lastPathComponent).joined(separator: ",")
        }
        Log.write("[setup] done hotkey=\(settings.data.recentHotkey) trusted=\(ModifierTap.trusted(prompt: false)) launchAtLogin=\(settings.data.launchAtLogin) skill=\(skill)")
        // macOS announces a new login item in the top-right corner, where the intro's popover is,
        // so the registration waits for it. A quit before then loses nothing: every later launch
        // registers the item the setting asks for.
        if introducing {
            afterIntro = { LoginItem.apply(Settings.shared.data.launchAtLogin) }
        } else {
            LoginItem.apply(settings.data.launchAtLogin)
        }
        DispatchQueue.main.async { FocusReturn.shared.restore(reason: "setup closed") }
        self.model = nil
        // The view's poll would otherwise keep running in the closed window. Let go after this
        // turn, since AppKit is still closing the window.
        DispatchQueue.main.async { [weak self] in
            self?.window?.contentViewController = nil
            self?.window = nil
        }
    }
}

/// The page shown, and what the window hands back when it closes.
@MainActor
final class SetupModel: ObservableObject {
    enum Page { case welcome, shortcut, agents }

    let protectedArea: String?
    @Published private(set) var agents: [AgentPluginStatus]
    let callbacks: SetupWindowController.Callbacks
    var granted: () -> Void = {}
    var folderAnswered: (FolderAccess) -> Void = { _ in }
    var done: () -> Void = {}

    @Published var page = Page.welcome
    /// Whether the last move was forward, which decides the side the pages slide to.
    @Published var forward = true
    /// The agents whose switch is on. All that can take the plugin to start: the user installed
    /// Vignette to work with them, and a switch they can see is still their choice.
    @Published var chosen: Set<URL>
    /// Claude Code's directory when its settings lack `ClaudeReadRule`, which this page then offers,
    /// on to start for the same reason as the skill.
    let claudeWithoutReadRule: URL?
    @Published var claudeReads = true
    private(set) var sawAgents = false

    init(protectedArea: String?, agents: [AgentPluginStatus], callbacks: SetupWindowController.Callbacks) {
        self.protectedArea = protectedArea
        self.agents = agents
        self.callbacks = callbacks
        chosen = Set(agents.filter(\.hasTool).map(\.root))
        claudeWithoutReadRule = agents.first { $0.logoKey == AgentClient.claude.rawValue }
            .map(\.root).flatMap { ClaudeReadRule.isSet(in: $0) ? nil : $0 }
        tools = NotificationCenter.default.addObserver(forName: AgentTools.found, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.toolsFound() }
        }
    }

    deinit { tools.map(NotificationCenter.default.removeObserver) }

    private var tools: NSObjectProtocol?

    /// The login shell found a tool the folders did not: its switch comes on, as it would have.
    private func toolsFound() {
        let before = Set(agents.filter(\.hasTool).map(\.root))
        agents = AgentPlugin.statuses(home: FileManager.default.homeDirectoryForCurrentUser)
        chosen.formUnion(agents.filter { $0.hasTool && !before.contains($0.root) }.map(\.root))
    }

    /// Whether Claude Code's switch is on for an install, which leaves the sessions already open
    /// without the plugin until they reload.
    var installsIntoClaude: Bool {
        agents.contains { $0.client == .claude && !$0.installed && chosen.contains($0.root) }
    }

    var pages: [Page] { agents.isEmpty ? [.welcome, .shortcut] : [.welcome, .shortcut, .agents] }
    var index: Int { pages.firstIndex(of: page) ?? 0 }
    var isLast: Bool { index == pages.count - 1 }

    /// The side is set a turn before the page changes: SwiftUI takes the leaving page's transition
    /// from the last time it drew that page, so a side set in the same turn reaches only the new one.
    func go(by step: Int, animation: Animation) {
        let target = pages[min(max(index + step, 0), pages.count - 1)]
        guard target != page else { return }
        forward = step > 0
        DispatchQueue.main.async {
            withAnimation(animation) { self.page = target }
            if target == .agents { self.sawAgents = true }
        }
    }
}

@MainActor
struct SetupView: View {
    static let width: CGFloat = 480
    /// One height for every page, so the buttons along the bottom never move between pages.
    static let height: CGFloat = 470

    @ObservedObject var model: SetupModel
    @ObservedObject private var settings = Settings.shared
    @State private var trusted = ModifierTap.trusted(prompt: false)
    /// How many times the shortcut has fired on this page; each one presses the keycap again.
    @State private var fires = 0
    @State private var held = false
    @State private var hasShots = true
    @State private var folder = FolderAccess.ask
    @State private var iconVisible = true
    /// Neither the Accessibility grant nor macOS's folder prompt announces its answer, so the
    /// window looks.
    private let poll = Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .top) {
                page(model.page)
                    .id(model.page)
                    .transition(.asymmetric(insertion: .move(edge: model.forward ? .trailing : .leading),
                                            removal: .move(edge: model.forward ? .leading : .trailing)))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .clipped()
            // Closing flies the window into the icon and points at it. With no icon to point at,
            // the last page says where the settings are instead.
            if model.isLast, !iconVisible {
                Text("\(Identity.name)'s icon isn't showing in the menu bar. To get back to its settings, open \(Identity.name) again.")
                    .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    .frame(maxWidth: 400).padding(.bottom, 12)
            }
            buttons
        }
        .frame(width: SetupView.width, height: SetupView.height)
        .onAppear(perform: look)
        .onReceive(poll) { _ in look() }
        .onReceive(NotificationCenter.default.publisher(for: .hotKeyFired)) { _ in fires += 1 }
        .onReceive(NotificationCenter.default.publisher(for: .hotKeyHeld)) { _ in held = true }
        .onChange(of: settings.data.recentHotkey) { fires = 0; held = false }
    }

    private func look() {
        let now = ModifierTap.trusted(prompt: false)
        if now, !trusted { model.granted() }
        trusted = now
        hasShots = model.callbacks.hasScreenshots()
        iconVisible = model.callbacks.menuBarIconVisible()
        let before = folder
        folder = model.callbacks.folderAccess()
        // After an answer to macOS's prompt, or a change made in System Settings after a refusal.
        // Not from `.ask`: a folder already allowed answers at once, with no prompt to cover us.
        if before != .ask, before != folder, folder == .granted || folder == .refused { model.folderAnswered(folder) }
    }

    @ViewBuilder private func page(_ page: SetupModel.Page) -> some View {
        switch page {
        case .welcome: welcome
        case .shortcut: shortcut
        case .agents: agents
        }
    }

    // MARK: Pages

    private var welcome: some View {
        VStack(spacing: 14) {
            Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 96, height: 96)
                .padding(.top, 44)
                .accessibilityHidden(true)
            heading("Welcome to \(Identity.name)",
                    "Take screenshots with ⌘⇧3, 4 or 5, as before. Vignette keeps the recent ones one shortcut away, ready to draw on.")
            form {
                if let area = model.protectedArea {
                    Section { folderRow(area) }
                }
                Section { Toggle("Open at login", isOn: binding(\.launchAtLogin)) }
            }
        }
    }

    /// A permission, not a choice of folder: the folder is macOS's, and the row is here only
    /// because macOS protects it. So it says why Vignette needs it.
    @ViewBuilder private func folderRow(_ area: String) -> some View {
        let reason = "macOS saves your screenshots there."
        switch folder {
        case .ask, .waiting:
            PermissionRow(symbol: "folder", title: "Vignette needs access to \(area)", reason: reason, status: .ask,
                          isDefault: true, busy: folder == .waiting) { askFolder() }
        case .refused:
            PermissionRow(symbol: "folder", title: "Vignette doesn't have access to \(area)", reason: reason,
                          status: .refused, isDefault: true) {
                // macOS doesn't ask twice, so the answer is changed where it keeps it.
                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_FilesAndFolders")!)
            }
        case .granted:
            PermissionRow(symbol: "folder", title: "Vignette has access to \(area)", status: .granted) {}
        }
    }

    private var shortcut: some View {
        let spec = HotKeySpec.parse(settings.data.recentHotkey)
        return VStack(spacing: 14) {
            KeyPicture(spec: spec, fires: fires, motion: settings.motionScale).padding(.top, 60).padding(.bottom, 6)
            heading(shortcutHeading(spec), ShortcutSetting.caption(doubleTap: settings.data.usesDoubleTap))
            form {
                Section {
                    ShortcutSetting()
                    status(spec)
                }
            }
        }
    }

    private func shortcutHeading(_ spec: HotKeySpec?) -> String {
        spec?.instruction ?? "Press \(settings.data.recentHotkey)"
    }

    /// One row that changes in place, rather than rows that come and go: the user is watching this
    /// spot for the answer. Only the symbol takes a colour, so the line never reads as a link.
    @ViewBuilder private func status(_ spec: HotKeySpec?) -> some View {
        if settings.data.usesDoubleTap, !trusted {
            // A step to take, not a fault: nothing has gone wrong on a fresh install.
            PermissionRow(symbol: "lock.fill", title: "Needs Accessibility permission",
                          reason: SettingsView.accessibilityReason, status: .ask, isDefault: true) { Accessibility.request() }
        } else if folder != .granted {
            // Nothing can appear until Vignette can read the folder, so that comes before trying the keys.
            folderRow(model.protectedArea ?? "your screenshots folder")
        } else if settings.appleTarget != "file" {
            // A capture made now would never reach the folder, so the try below would fail.
            CaptureTargetRow(isDefault: true)
        } else if !hasShots {
            // Ahead of `fired`: with nothing in the folder the shortcut opens nothing, so saying
            // it worked would be saying so about an empty corner.
            line("Take a screenshot with ⌘⇧4 first.", symbol: "camera", tint: .accentColor)
        } else if held {
            line("That's the whole trick.", symbol: "checkmark.circle.fill", tint: .installed)
        } else if fires > 0 {
            // The stack has just come up beside this window, so the line points at it, then asks for
            // the hold, the half of the shortcut the caption describes and people miss.
            let hold = spec?.doubleTapKey != nil ? "holding the second tap" : "holding \(spec?.glyphs ?? settings.data.recentHotkey)"
            line("There they are. Now try \(hold).", symbol: "checkmark.circle.fill", tint: .installed, bounce: fires)
        } else if let key = spec?.doubleTapKey {
            line("Try it now: tap \(key.label) twice.", symbol: "hand.tap", tint: .accentColor)
        } else {
            line("Try it now: press \(spec?.glyphs ?? settings.data.recentHotkey).", symbol: "hand.tap", tint: .accentColor)
        }
    }

    private var agents: some View {
        VStack(spacing: 14) {
            HStack(spacing: 18) {
                ForEach(model.agents) { row in
                    if let image = Agent.logo(for: row.logoKey) {
                        Image(nsImage: image).renderingMode(image.isTemplate ? .template : .original)
                            .resizable().aspectRatio(contentMode: .fit).frame(width: 44, height: 44)
                    }
                }
            }
            .padding(.top, 60).padding(.bottom, 6)
            .accessibilityHidden(true)
            heading("Your coding agents", SettingsView.agentsLine)
            form {
                Section {
                    ForEach(model.agents) { row in
                        // Setup only adds. Removing stays in the Settings window's Agents tab.
                        if row.installed {
                            LabeledContent {
                                Label("Installed", systemImage: "checkmark.circle.fill").foregroundStyle(Color.installed)
                            } label: {
                                AgentName(row: row)
                            }
                        } else {
                            Toggle(isOn: chosen(row.root)) { AgentName(row: row) }
                                .disabled(!row.hasTool)
                        }
                    }
                } footer: {
                    if model.installsIntoClaude {
                        Text("Claude Code sessions already open need `/reload-plugins` to use it.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                if model.claudeWithoutReadRule != nil {
                    Section {
                        Toggle(isOn: $model.claudeReads) {
                            Text(ClaudeReadRule.title)
                            Text(ClaudeReadRule.explanation)
                        }
                    }
                }
            }
        }
    }

    // MARK: Buttons

    /// Back, the page dots and Continue. The dots are laid over the buttons rather than between
    /// them, so they sit on the window's centre line whether or not there is a Back button, and
    /// however wide the buttons are.
    private var buttons: some View {
        ZStack {
            HStack(spacing: 7) {
                ForEach(model.pages.indices, id: \.self) { i in
                    Circle().fill(Color.primary.opacity(i == model.index ? 0.7 : 0.2)).frame(width: 7, height: 7)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Page \(model.index + 1) of \(model.pages.count)")
            HStack {
                if model.index > 0 { Button("Back") { model.go(by: -1, animation: slide) } }
                Spacer()
                Button(model.isLast ? "Done" : "Continue", action: next)
                    .keyboardShortcut(pageIsDone ? .defaultAction : nil)
            }
        }
        .frame(height: 28)
        .padding(.horizontal, 20).padding(.bottom, 20)
    }

    /// Whether this page has nothing left to allow, so Continue or Done is the next thing to press
    /// and carries the window's one default button. Until then the Allow… still to press carries it.
    private var pageIsDone: Bool {
        switch model.page {
        case .welcome: return model.protectedArea == nil || folder == .granted
        case .shortcut: return (!settings.data.usesDoubleTap || trusted) && folder == .granted && settings.appleTarget == "file"
        case .agents: return true
        }
    }

    private func next() {
        // Moving on without Allow still asks: the prompt then comes up over the next page, with
        // the reason still fresh, rather than later over nothing.
        if model.page == .welcome, model.protectedArea != nil, folder == .ask { askFolder() }
        if model.isLast { model.done() } else { model.go(by: 1, animation: slide) }
    }

    private func askFolder() {
        Log.write("[setup] asking for the folder")
        model.callbacks.askFolder()
        look()
    }

    private var slide: Animation { Anim.spring(0.45 * settings.motionScale) }

    // MARK: Pieces

    private func heading(_ title: String, _ text: String) -> some View {
        VStack(spacing: 6) {
            Text(title).font(.title).bold()
            Text(text).multilineTextAlignment(.center).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true).frame(maxWidth: 400)
        }
    }

    private func form<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        Form { content() }.formStyle(.grouped).scrollDisabled(true).fixedSize(horizontal: false, vertical: true)
    }

    private func line(_ text: String, symbol: String, tint: Color, bounce: Int = 0) -> some View {
        Label { Text(text).fixedSize(horizontal: false, vertical: true) } icon: {
            Image(systemName: symbol).foregroundStyle(tint)
                .symbolEffect(.bounce, value: settings.motionScale > 0 ? bounce : 0)
        }
    }

    private func chosen(_ root: URL) -> Binding<Bool> {
        Binding(get: { model.chosen.contains(root) },
                set: { on in if on { model.chosen.insert(root) } else { model.chosen.remove(root) } })
    }

    private func binding<T>(_ path: WritableKeyPath<SettingsData, T>) -> Binding<T> {
        Binding(get: { settings.data[keyPath: path] }, set: { v in settings.update { $0[keyPath: path] = v } })
    }
}

/// The shortcut as keys on a keyboard: one wide keycap marked ×2 for a double tap, or a keycap for
/// each key of a combination. A modifier's keycap goes down while the person holds that key, so
/// the picture answers their hand before the shortcut works. Each time the shortcut fires, the ×2
/// turns into a check.
struct KeyPicture: View {
    let spec: HotKeySpec?
    var fires = 0
    /// `Settings.motionScale`: 0 with Reduce Motion, and then a held key darkens without moving.
    var motion = 1.0
    @StateObject private var held = HeldModifiers()

    var body: some View {
        Group {
            if let key = spec?.doubleTapKey, case let .doubleTap(code)? = spec {
                // A right-hand modifier has its label on the right, as Apple's keyboards print it.
                keycap(width: 118, down: held.codes.contains(code)) {
                    VStack(alignment: key.isRight ? .trailing : .leading) {
                        Text(key.glyph).font(.system(size: 17))
                        Spacer()
                        Text(key.word).font(.system(size: 12))
                    }
                    .frame(maxWidth: .infinity, alignment: key.isRight ? .trailing : .leading)
                }
                // The badge takes the corner the label leaves free.
                .overlay(alignment: key.isRight ? .topLeading : .topTrailing) {
                    badge.offset(x: key.isRight ? -10 : 10, y: -10)
                }
            } else {
                let modifiers = spec?.keycapModifiers ?? []
                HStack(spacing: 8) {
                    ForEach(Array((spec?.keycaps ?? []).enumerated()), id: \.offset) { index, cap in
                        let modifier = index < modifiers.count ? modifiers[index] : []
                        keycap(width: 56, down: !modifier.isEmpty && held.flags.contains(modifier)) {
                            Text(cap).font(.system(size: 20)).frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                    }
                }
                .overlay(alignment: .topTrailing) {
                    if fires > 0 { badge.offset(x: 10, y: -10).transition(.scale.combined(with: .opacity)) }
                }
                // The combination's own key never reaches the window, since the hotkey takes it, so
                // its firing is what presses the picture.
                .keyframeAnimator(initialValue: 1.0, trigger: fires) { content, scale in
                    content.scaleEffect(scale)
                } keyframes: { _ in
                    CubicKeyframe(motion > 0 ? 0.94 : 1, duration: 0.07)
                    SpringKeyframe(1, duration: 0.35 * max(motion, 0.01), spring: .bouncy)
                }
            }
        }
        .animation(Anim.spring(0.3 * motion), value: fires > 0)
        .onAppear { held.start() }
        .onDisappear { held.stop() }
        .accessibilityHidden(true)
    }

    /// ×2 until the shortcut has worked, then a check in the colour setup uses for done.
    private var badge: some View {
        ZStack {
            if fires > 0 {
                Image(systemName: "checkmark").font(.system(size: 12, weight: .bold))
                    .transition(.scale.combined(with: .opacity))
            } else {
                Text("×2").font(.system(size: 13, weight: .semibold))
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .foregroundStyle(.white)
        .frame(minWidth: 18, minHeight: 17)
        .padding(.horizontal, 7).padding(.vertical, 3)
        .background(Capsule().fill(fires > 0 ? Color.installed : Color.accentColor))
    }

    /// A keycap, raised on its shadow, or `down`: sunk onto the surface, a shade darker and a little
    /// smaller. It goes down at once, as a key does, and springs back up.
    private func keycap<Content: View>(width: CGFloat, down: Bool, @ViewBuilder _ content: () -> Content) -> some View {
        let moves = motion > 0
        return content()
            .foregroundStyle(.secondary)
            .padding(8)
            .frame(width: width, height: 56)
            .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Color(nsColor: .controlColor))
                .brightness(down ? -0.08 : 0)
                .shadow(color: .black.opacity(down ? 0 : 0.25), radius: 1, y: down ? 0 : 1))
            .scaleEffect(down && moves ? 0.95 : 1)
            .offset(y: down && moves ? 1 : 0)
            .animation(down ? Anim.spring(0.06 * motion) : Anim.spring(0.3 * motion, bounce: 0.4), value: down)
    }
}

/// Which modifier keys the person is holding, by key code, so a picture of a key can go down with
/// it. It hears them while a Vignette window is key, and anywhere once Vignette is trusted for
/// Accessibility, which is also when a double tap starts to work. It reads a key as `ModifierTap`
/// does: the key's code, and whether its modifier is still set.
@MainActor
final class HeldModifiers: ObservableObject {
    @Published private(set) var codes: Set<UInt16> = []
    var flags: NSEvent.ModifierFlags { codes.reduce(into: []) { $0.insert(ModifierTap.flag(forKeyCode: $1)) } }
    private var monitors: [Any] = []

    func start() {
        guard monitors.isEmpty else { return }
        let changed: (NSEvent) -> Void = { [weak self] event in MainActor.assumeIsolated { self?.changed(event) } }
        monitors = [NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { changed($0); return $0 },
                    NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged, handler: changed)].compactMap { $0 }
    }

    func stop() {
        monitors.forEach(NSEvent.removeMonitor)
        monitors = []
        codes = []
    }

    private func changed(_ event: NSEvent) {
        guard HotKeySpec.modifierCodes.values.contains(event.keyCode) else { return }
        if event.modifierFlags.contains(ModifierTap.flag(forKeyCode: event.keyCode)) {
            codes.insert(event.keyCode)
        } else {
            codes.remove(event.keyCode)
        }
    }
}
