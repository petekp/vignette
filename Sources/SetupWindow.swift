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

/// What the setup window reacts to, read together each time it looks: the permissions, the watch
/// folder and macOS's own screenshot settings. Setup reads them from this Mac, and the Setup Lab
/// sets them.
struct SetupConditions: Equatable {
    /// Trusted for Accessibility, which the double tap and live ink need.
    var trusted: Bool
    /// Allowed to record the screen, which live ink's asks need.
    var screenRecording: Bool
    /// The folder macOS will ask about, as setup names it ("your Desktop"), or nil when it won't
    /// ask, which leaves the welcome page without a folder row.
    var protectedArea: String?
    var folder: FolderAccess
    var hasScreenshots: Bool
    /// ⌘⇧5's Save to: `file`, or where else macOS sends screenshots (`AppleScreencapture.target`).
    var saveTarget: String
    /// Whether the menu bar icon can be seen: it is off, or macOS found no room for it.
    var menuBarIconVisible: Bool
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
        if Launch.isTest { return settings.data.setupChoice == .unasked }
        if UserDefaults.standard.bool(forKey: SetupWindowController.doneOnThisMacKey) { return false }
        return !(settings.data.setupChoice == .done && launchedHereBefore)
    }

    private static let doneOnThisMacKey = "setupDoneOnThisMac"
    /// Read before this launch creates the folder.
    private let launchedHereBefore = FileManager.default.fileExists(atPath: Identity.applicationSupportURL.path)

    /// Setup for a first launch, which records what it was told when it closes.
    func show(callbacks: Callbacks) {
        var callbacks = callbacks
        callbacks.choseLiveInk = { use in Settings.shared.update { $0.liveInk = use } }
        // macOS asks to quit and reopen, and the next launch's setup opens on live ink's permissions.
        callbacks.askedForScreenRecording = { SetupModel.returnsToLiveInkSetup = true }
        callbacks.closed = { [weak self] model in self?.record(model) }
        let data = settings.data
        let reopened = data.liveInk && SetupModel.returnsToLiveInkSetup
        if reopened { Log.write("[setup] reopened on live ink's permissions") }
        open(callbacks: callbacks, scope: .whole, start: reopened ? .liveInkSetup : .welcome)
    }

    /// Setup as a new person sees it, for the Setup Lab (`vignette://setup-lab`, needs `debug`), in
    /// the window it answers. The lab's callbacks record nothing. `place` puts the window where it
    /// opens, beside the lab.
    func run(callbacks: Callbacks, scope: SetupModel.Scope, start: SetupModel.Page, place: @escaping (NSWindow) -> Void) -> NSWindow {
        open(callbacks: callbacks, scope: scope, start: start, place: place)
    }

    /// `place` is a test run's: it puts the window where it opens, and the window fades in, since it
    /// opens over whatever is on the screen.
    @discardableResult
    private func open(callbacks: Callbacks, scope: SetupModel.Scope, start: SetupModel.Page,
                      place: ((NSWindow) -> Void)? = nil) -> NSWindow {
        if let win = window {
            win.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return win
        }
        let model = SetupModel(callbacks: callbacks, scope: scope, start: start)
        model.granted = { [weak self] in self?.granted() }
        model.folderAnswered = { [weak self] access in self?.folderAnswered(access) }
        model.dropFocus = { [weak self] in self?.window?.makeFirstResponder(nil) }
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
        place?(win)
        window = win
        let area = model.seen.protectedArea
        Log.write("[setup] shown\(place != nil ? " test pages=\(scope) start=\(model.page)" : "") folder=\(area.map { "\"\($0)\"" } ?? "none") agents=\(model.agents.count)")
        let fades = place != nil && settings.motionScale > 0
        if fades { win.alphaValue = 0 }
        win.makeKeyAndOrderFront(nil)
        if fades {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.25 * settings.motionScale
                win.animator().alphaValue = 1
            }
        }
        // A window asking for a permission has to be the frontmost thing, or the dialog it raises
        // arrives behind whatever the user was doing.
        NSApp.activate(ignoringOtherApps: true)
        return win
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
        introducing = model.callbacks.introduceMenuBar(sender, model.seen, model.usesLiveInk, { sender.close() }) {}
        return !introducing
    }

    private var introducing = false
    /// Registers the login item as the setting asks. Setup's close calls it whether or not the switch
    /// moved, since the launch left the login item alone while setup was unasked.
    var applyLoginItem: () -> Void = {}

    func windowWillClose(_ notification: Notification) {
        guard let model else { return }
        model.inkPlayer.stop()
        model.callbacks.closed(model)
        self.model = nil
        // The view's poll would otherwise keep running in the closed window. Let go after this
        // turn, since AppKit is still closing the window.
        DispatchQueue.main.async {
            self.window?.contentViewController = nil
            self.window = nil
        }
    }

    /// Records setup as done and applies the switches the window shows, unless the app is quitting.
    private func record(_ model: SetupModel) {
        if quitting {
            Log.write("[setup] quit before it was done; asks again at the next launch")
            return
        }
        // Vignette can't work without the folder, so a window closed before it asked asks now.
        if model.seen.folder == .ask { model.callbacks.askFolder() }
        settings.update {
            $0.setup = SetupState.done.rawValue
            if model.sawLiveInk { $0.liveInkOffered = true }
            if let choice = model.launchAtLoginChoice { $0.launchAtLogin = choice }
        }
        UserDefaults.standard.set(true, forKey: SetupWindowController.doneOnThisMacKey)
        SetupModel.returnsToLiveInkSetup = false
        // The plugin is installed only for someone who saw the page offering it. Closed earlier, the
        // offer is left unmade, and the next launch makes it in the Settings window.
        var skill = "not-offered"
        if model.sawAgents {
            let roots = model.agents.filter { !$0.installed && model.chosen.contains($0.root) }.map(\.root)
            if !roots.isEmpty { model.callbacks.installAgentPlugin(roots) }
            // An install brings Claude Code's permission with it (`AppDelegate.turnOnAgents`); a plugin
            // already in gets it here, since nothing is installed for it.
            if let claude = model.claude, claude.installed { ClaudeReadRule.apply(true, in: claude.root) }
            settings.update { $0.agentSkill = AgentSkill.off.rawValue }
            skill = roots.isEmpty ? "none" : roots.map(\.lastPathComponent).joined(separator: ",")
        }
        Log.write("[setup] done hotkey=\(settings.data.recentHotkey) trusted=\(ModifierTap.trusted(prompt: false)) launchAtLogin=\(settings.data.launchAtLogin) skill=\(skill)")
        applyLoginItem()
        DispatchQueue.main.async { FocusReturn.shared.restore(reason: "setup closed") }
    }
}

/// The page shown, and what the window hands back when it closes.
@MainActor
final class SetupModel: ObservableObject {
    /// `liveInkSetup`, live ink's permissions, follows Use Live Ink on the live ink page and shares its dot.
    enum Page { case welcome, shortcut, liveInk, liveInkSetup, agents }
    /// Which pages the window holds: all of setup, or live ink's pages alone, to try them.
    enum Scope { case whole, liveInk }

    /// The conditions as the last look found them.
    @Published private(set) var seen: SetupConditions
    @Published private(set) var agents: [AgentPluginStatus]
    let callbacks: SetupWindowController.Callbacks
    var granted: () -> Void = {}
    var folderAnswered: (FolderAccess) -> Void = { _ in }
    var done: () -> Void = {}
    let scope: Scope
    /// The live ink page's demo, kept here so going back to the page shows where it rested.
    let inkPlayer = SetupInkPlayer()
    let inkGuide = SetupInkGuide()
    /// Use Live Ink was pressed, which brings in the page for its permissions.
    @Published private(set) var usesLiveInk = false
    /// Open at login. Saved with setup's other choices when the window closes (`record`).
    @Published var launchAtLogin: Bool
    private let launchAtLoginAtOpen: Bool
    /// The switch's value when the person moved it here, or nil. The Settings window's switch is
    /// reachable while setup is up and saves at once, so setup saves only a change of its own.
    var launchAtLoginChoice: Bool? { launchAtLogin == launchAtLoginAtOpen ? nil : launchAtLogin }
    /// Takes the keyboard focus off the window's controls. A focused button that leaves with its page
    /// keeps its focus ring on the screen, at full strength, until it has faded out.
    var dropFocus: () -> Void = {}

    @Published var page = Page.welcome {
        didSet { reached(page) }
    }
    /// Whether the last move was forward, which decides the side the pages slide to.
    @Published var forward = true
    /// The agents whose switch is on. All that can take the plugin to start: the user installed
    /// Vignette to work with them, and a switch they can see is still their choice.
    @Published var chosen: Set<URL>
    private(set) var sawAgents = false
    /// Whether live ink's page was shown, which makes its offer: a setup closed before it leaves the
    /// offer for the Settings window.
    private(set) var sawLiveInk = false

    /// Opens on `start`, or on the first page when `start` is not among them. Starting on live ink's
    /// permissions is starting after Use Live Ink, as a reopen after asking for Screen Recording does.
    init(callbacks: SetupWindowController.Callbacks, scope: Scope = .whole, start: Page = .welcome) {
        self.callbacks = callbacks
        self.scope = scope
        seen = callbacks.conditions()
        let agents = callbacks.agents()
        self.agents = agents
        usesLiveInk = start == .liveInkSetup
        launchAtLoginAtOpen = callbacks.launchAtLogin()
        launchAtLogin = launchAtLoginAtOpen
        chosen = Set(agents.filter(\.hasTool).map(\.root))
        page = pages.contains(start) ? start : pages[0]
        if page == .agents { sawAgents = true }
        changes = callbacks.changes.sink { [weak self] in
            MainActor.assumeIsolated { self?.look(includingAgents: true) }
        }
        // Live ink's agents decide a button and words on setup's pages too.
        responderChanges = callbacks.responders.objectWillChange.sink { [weak self] _ in
            MainActor.assumeIsolated { self?.objectWillChange.send() }
        }
        // `page`'s observer does not run in `init`.
        reached(page)
    }

    private var changes: AnyCancellable?
    private var responderChanges: AnyCancellable?

    /// Reads the conditions again, and moves a row that changed on setup's spring. The agents are read
    /// too only `includingAgents`, on `Callbacks.changes`: reading them reads files, too much for every
    /// poll. A switch comes on when its agent's tool turns up, as it would have at the start, and goes
    /// off when its tool goes. A window showing the agents page when the last agent goes steps back.
    func look(includingAgents: Bool = false) {
        let before = seen
        let now = callbacks.conditions()
        let agentsNow = includingAgents ? callbacks.agents() : agents
        let agentsChanged = agentsNow != agents
        if now != before || agentsChanged {
            let hadTool = Set(agents.filter(\.hasTool).map(\.root))
            let withTool = Set(agentsNow.filter(\.hasTool).map(\.root))
            withAnimation(SetupView.spring) {
                seen = now
                agents = agentsNow
                chosen.formUnion(withTool.subtracting(hadTool))
                chosen.formIntersection(withTool)
            }
            if agentsChanged, !pages.contains(page), let last = pages.last { show(last, forward: false, animation: SetupView.spring) }
        }
        if seen.trusted, !before.trusted { granted() }
        pointGuide()
        // After an answer to macOS's prompt, or a change made in System Settings after a refusal.
        // Not from `.ask`: a folder already allowed answers at once, with no prompt to cover us.
        let folder = seen.folder
        if before.folder != .ask, before.folder != folder, folder == .granted || folder == .refused { folderAnswered(folder) }
    }

    /// Points live ink's guide at the next step, while its page shows, as the agent setup names.
    func pointGuide() {
        guard page == .liveInkSetup else { return }
        let responders = callbacks.responders
        inkGuide.point(at: SetupInkGuide.Pointing(trusted: seen.trusted, screenRecording: seen.screenRecording,
                                                  codexSignIn: responders.codexSignInLeft, signingIn: responders.signIn == .waiting),
                       as: responders.namedAgent)
    }

    var claude: AgentPluginStatus? { agents.first { $0.client == .claude } }

    /// Whether Claude Code's plugin is in or its switch is on. Closing the window then also gives it
    /// `ClaudeReadRule`: someone using Vignette with Claude Code wants it to open what they send.
    var claudeOn: Bool { claude.map { $0.installed || chosen.contains($0.root) } ?? false }

    /// Whether Claude Code's switch is on for an install, which leaves the sessions already open
    /// without the plugin until they reload.
    var installsIntoClaude: Bool { claude.map { !$0.installed && chosen.contains($0.root) } ?? false }

    /// Live ink's pages record the offer as made, and its first page asks which agent can answer.
    private func reached(_ page: Page) {
        if page == .liveInk || page == .liveInkSetup { sawLiveInk = true }
        if page == .liveInk { callbacks.responders.look() }
    }

    var pages: [Page] {
        Self.pages(scope: scope, usesLiveInk: usesLiveInk, hasAgents: !agents.isEmpty)
    }

    static func pages(scope: Scope, usesLiveInk: Bool, hasAgents: Bool) -> [Page] {
        let liveInk: [Page] = [.liveInk] + (usesLiveInk ? [.liveInkSetup] : [])
        switch scope {
        case .liveInk: return liveInk
        case .whole: return [.welcome, .shortcut] + liveInk + (hasAgents ? [.agents] : [])
        }
    }
    var index: Int { pages.firstIndex(of: page) ?? 0 }
    var isLast: Bool { index == pages.count - 1 }

    /// The steps the page dots stand for: live ink's two pages are one.
    var steps: [Page] { pages.filter { $0 != .liveInkSetup } }
    var stepIndex: Int { steps.firstIndex(of: page == .liveInkSetup ? .liveInk : page) ?? 0 }

    /// The live ink page's answer. Use Live Ink turns it on and goes on to its permissions; Not Now
    /// leaves it off and skips them, and closes the window when no page follows.
    func useLiveInk(_ use: Bool, animation: Animation) {
        usesLiveInk = use
        callbacks.choseLiveInk(use)
        Log.write("[setup] live ink \(use ? "used" : "not now")")
        if !use, isLast { return done() }
        go(by: 1, animation: animation)
    }

    func go(by step: Int, animation: Animation) {
        show(pages[min(max(index + step, 0), pages.count - 1)], forward: step > 0, animation: animation)
    }

    /// The side is set a turn before the page changes: SwiftUI takes the leaving page's transition
    /// from the last time it drew that page, so a side set in the same turn reaches only the new one.
    private func show(_ target: Page, forward: Bool, animation: Animation) {
        guard target != page else { return }
        self.forward = forward
        dropFocus()
        DispatchQueue.main.async {
            withAnimation(animation) { self.page = target }
            if target == .agents { self.sawAgents = true }
        }
    }

    /// Set until setup is done, so a quit and reopen part way through comes back to live ink's permissions.
    static var returnsToLiveInkSetup: Bool {
        get { UserDefaults.standard.bool(forKey: returnsToLiveInkSetupKey) }
        set { UserDefaults.standard.set(newValue, forKey: returnsToLiveInkSetupKey) }
    }
    private static let returnsToLiveInkSetupKey = "setupReturnsToLiveInkPermissions"
}

@MainActor
struct SetupView: View {
    static let width: CGFloat = 480
    /// One height for every page, so the buttons along the bottom never move between pages.
    static let height: CGFloat = 470

    @ObservedObject var model: SetupModel
    @ObservedObject private var settings = Settings.shared
    /// How many times the shortcut has fired on this page; each one presses the keycap again.
    @State private var fires = 0
    @State private var banter = SetupBanter()
    /// Neither the grants nor macOS's folder prompt announce their answers, so the window looks.
    private let poll = Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()

    static var spring: Animation { Anim.spring(0.45 * Settings.shared.motionScale) }

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
            if model.isLast, !model.seen.menuBarIconVisible {
                Text("\(Identity.name)'s icon isn't showing in the menu bar. To get back to its settings, open \(Identity.name) again.")
                    .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    .frame(maxWidth: 400).padding(.bottom, 12)
            }
            buttons
        }
        .frame(width: SetupView.width, height: SetupView.height)
        // Not a look: the model read the conditions as it opened.
        .onAppear { model.pointGuide() }
        .onReceive(poll) { _ in model.look() }
        .onReceive(NotificationCenter.default.publisher(for: .hotKeyFired)) { _ in fires += 1 }
        .answersHolds($banter, on: model.page, rowReady: { model.page == .shortcut && pageIsDone && model.seen.hasScreenshots },
                      moveOn: next)
        .onChange(of: settings.data.recentHotkey) { fires = 0; banter.shortcutChanged() }
    }

    @ViewBuilder private func page(_ page: SetupModel.Page) -> some View {
        switch page {
        case .welcome: welcome
        case .shortcut: shortcut
        case .liveInk: LiveInkPage(player: model.inkPlayer, responders: model.callbacks.responders)
        case .liveInkSetup:
            LiveInkSetupPage(guide: model.inkGuide, trusted: model.seen.trusted, screenRecording: model.seen.screenRecording,
                             callbacks: model.callbacks, responders: model.callbacks.responders)
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
                if let area = model.seen.protectedArea {
                    Section { folderRow(area) }
                }
                Section { Toggle("Open at login", isOn: $model.launchAtLogin) }
            }
        }
    }

    /// A permission, not a choice of folder: the folder is macOS's, and the row is here only
    /// because macOS protects it. So it says why Vignette needs it.
    @ViewBuilder private func folderRow(_ area: String) -> some View {
        let reason = "macOS saves your screenshots there."
        switch model.seen.folder {
        case .ask, .waiting:
            PermissionRow(symbol: "folder", title: "Vignette needs access to \(area)", reason: reason, status: .ask,
                          isDefault: true, busy: model.seen.folder == .waiting) { askFolder() }
        case .refused:
            PermissionRow(symbol: "folder", title: "Vignette doesn't have access to \(area)", reason: reason,
                          status: .refused, isDefault: true, allow: model.callbacks.openFolderSettings)
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
        if settings.data.usesDoubleTap, !model.seen.trusted {
            // A step to take, not a fault: nothing has gone wrong on a fresh install.
            PermissionRow(symbol: "lock.fill", title: "Needs Accessibility permission",
                          reason: SettingsView.accessibilityReason, status: .ask, isDefault: true) { model.callbacks.askAccessibility() }
        } else if model.seen.folder != .granted {
            // Nothing can appear until Vignette can read the folder, so that comes before trying the keys.
            folderRow(model.seen.protectedArea ?? "your screenshots folder")
        } else if model.seen.saveTarget != "file" {
            // A capture made now would never reach the folder, so the try below would fail.
            CaptureTargetRow(target: model.seen.saveTarget, isDefault: true, saveToFolder: model.callbacks.saveToFolder)
        } else if !model.seen.hasScreenshots {
            // Ahead of `fired`: with nothing in the folder the shortcut opens nothing, so saying
            // it worked would be saying so about an empty corner.
            line("Take a screenshot with ⌘⇧4 first.", symbol: "camera", tint: .accentColor)
        } else if let said = banter.line {
            SetupBanterLine(line: said, bounce: settings.motionScale > 0 ? banter.bounce : 0)
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
                    if model.claudeOn {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(ClaudeReadRule.setupNote)
                            if model.installsIntoClaude {
                                Text("Claude Code sessions already open need `/reload-plugins` to use it.")
                            }
                        }
                        .font(.caption).foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
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
            if model.steps.count > 1 {
                HStack(spacing: 7) {
                    ForEach(model.steps.indices, id: \.self) { i in
                        Circle().fill(Color.primary.opacity(i == model.stepIndex ? 0.7 : 0.2)).frame(width: 7, height: 7)
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Page \(model.stepIndex + 1) of \(model.steps.count)")
            }
            HStack {
                if model.index > 0 { Button("Back") { model.go(by: -1, animation: Self.spring) } }
                Spacer()
                if model.page == .liveInk {
                    Button("Not Now") { model.useLiveInk(false, animation: Self.spring) }
                    Button("Use Live Ink") { model.useLiveInk(true, animation: Self.spring) }
                        .keyboardShortcut(.defaultAction)
                } else {
                    Button(model.isLast ? "Done" : "Continue", action: next)
                        .keyboardShortcut(pageIsDone ? .defaultAction : nil)
                }
            }
        }
        .frame(height: 28)
        .padding(.horizontal, 20).padding(.bottom, 20)
    }

    /// Whether this page has nothing left to allow, so Continue or Done is the next thing to press
    /// and carries the window's one default button. Until then the Allow… still to press carries it.
    private var pageIsDone: Bool {
        let seen = model.seen
        switch model.page {
        case .welcome: return seen.protectedArea == nil || seen.folder == .granted
        case .shortcut: return (!settings.data.usesDoubleTap || seen.trusted) && seen.folder == .granted && seen.saveTarget == "file"
        case .liveInk: return true
        case .liveInkSetup: return seen.trusted && seen.screenRecording && !model.callbacks.responders.codexSignInLeft
        case .agents: return true
        }
    }

    private func next() {
        // Moving on without Allow still asks: the prompt then comes up over the next page, with
        // the reason still fresh, rather than later over nothing.
        if model.page == .welcome, model.seen.protectedArea != nil, model.seen.folder == .ask { askFolder() }
        if model.isLast { model.done() } else { model.go(by: 1, animation: Self.spring) }
    }

    private func askFolder() {
        Log.write("[setup] asking for the folder")
        model.callbacks.askFolder()
        // Asking changes the folder's state at once, so the row shows the prompt coming up now rather
        // than at the next poll.
        model.look()
    }

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
}
