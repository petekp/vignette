import AppKit
import Combine
import SwiftUI

/// A debug window for trying setup as a new person sees it. It runs all of setup, or live ink's
/// pages alone, from any page, under conditions it sets: the permissions, the watch folder, macOS's
/// Save to, the agents and the menu bar icon. Each is this Mac's own until the lab sets it, and the
/// open window follows a change at once. Allow… on a simulated permission allows it here a moment
/// later, as macOS would. Closing the window plays the menu bar intro and records nothing: no
/// settings, login item, plugin or live ink choice. Opened from the tweak panel or
/// `vignette://setup-lab` (needs `debug`).
@MainActor
final class SetupLabController: NSObject, NSWindowDelegate {
    /// What setup reads from this Mac and asks of it.
    private let callbacks: () -> SetupWindowController.Callbacks
    /// This Mac's, made when the lab opens.
    private var mac = SetupWindowController.Callbacks()
    private var panel: NSPanel?
    private let model = SetupLabModel()
    /// The run in front, and the runs it replaced until their windows have closed.
    private var current: Run?
    private var replaced: [Run] = []
    /// Keeps the pickers' Real current while the lab is open.
    private var poll: Timer?
    private var tools: NSObjectProtocol?

    /// A run of setup, in a controller of its own, so a new run never waits for the one before it.
    @MainActor
    private final class Run {
        let setup = SetupWindowController()
        var window: NSWindow?
        /// Fading out, or flying into the menu bar icon, either of which closes the window.
        var closing = false
    }

    /// How long macOS takes to answer an Allow…, as the lab plays it.
    private static let beat: TimeInterval = 1
    private static let width: CGFloat = 440
    /// Tall enough for every condition without scrolling, where the screen has the room.
    private static let height: CGFloat = 900
    /// Between the lab and the window it runs, and the lab and the screen's edge.
    private static let gap: CGFloat = 12

    init(callbacks: @escaping () -> SetupWindowController.Callbacks) {
        self.callbacks = callbacks
        super.init()
    }

    func show() {
        let p = panel ?? make()
        mac = callbacks()
        readConditions()
        readAgents()
        poll = poll ?? Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.readConditions() }
        }
        tools = tools ?? NotificationCenter.default.addObserver(forName: AgentTools.found, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.readAgents() }
        }
        p.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func make() -> NSPanel {
        let p = NSPanel(contentRect: NSRect(x: 0, y: 0, width: Self.width, height: Self.height),
                        styleMask: [.titled, .closable, .resizable, .utilityWindow], backing: .buffered, defer: false)
        p.title = "Setup Lab"
        p.isFloatingPanel = true
        p.level = .floating
        p.hidesOnDeactivate = false
        p.isReleasedWhenClosed = false
        p.delegate = self
        p.contentView = NSHostingView(rootView: SetupLabView(model: model, run: { [weak self] in self?.run() },
                                                             close: { [weak self] in self?.closeRun() }))
        // At the right of the screen, with setup's window beside it on the left.
        if let v = NSScreen.main?.visibleFrame {
            let height = min(Self.height, v.height - 2 * Self.gap)
            p.setFrame(NSRect(x: v.maxX - Self.width - Self.gap, y: v.midY - height / 2, width: Self.width, height: height), display: false)
        }
        panel = p
        return p
    }

    /// The conditions live only while the lab is open: closing it closes its run and lets them go.
    func windowWillClose(_ notification: Notification) {
        poll?.invalidate()
        poll = nil
        tools.map(NotificationCenter.default.removeObserver)
        tools = nil
        closeRun()
        model.forget()
        DispatchQueue.main.async { FocusReturn.shared.restore(reason: "setup lab closed") }
    }

    /// This Mac's conditions, for the pickers' Real and the runs.
    private func readConditions() {
        let conditions = mac.conditions()
        if model.real != conditions { model.real = conditions }
    }

    /// This Mac's agents, read only when they can have changed, since reading them reads their files.
    private func readAgents() {
        let agents = mac.agents()
        if model.realAgents != agents { model.realAgents = agents }
    }

    // MARK: A run

    /// Opens setup under the lab's conditions. A run already open fades out as the new one opens.
    private func run() {
        if let old = current {
            fadeOut(old)
            replaced.append(old)
        }
        readConditions()
        readAgents()
        let run = Run()
        current = run
        model.running = true
        Log.write("[setup-lab] run pages=\(model.scope) start=\(model.start) \(model.overrides.summary)")
        run.window = run.setup.run(callbacks: callbacks(for: run), scope: model.scope, start: model.start) { [weak self] in
            self?.place($0)
        }
    }

    /// Beside the lab, on its left, where the lab leaves room; centred on the screen otherwise.
    private func place(_ window: NSWindow) {
        guard let panel, let visible = (panel.screen ?? NSScreen.main)?.visibleFrame else { return }
        let size = window.frame.size
        let x = panel.frame.minX - Self.gap - size.width
        guard x >= visible.minX else { return }
        window.setFrameOrigin(NSPoint(x: x, y: visible.midY - size.height / 2))
    }

    private func closeRun() {
        current.map(fadeOut)
    }

    /// Closes a run's window without the intro. One already flying into the menu bar icon closes on its own.
    private func fadeOut(_ run: Run) {
        guard let window = run.window, !run.closing else { return }
        run.closing = true
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2 * Settings.shared.motionScale
            window.animator().alphaValue = 0
        } completionHandler: {
            MainActor.assumeIsolated { window.close() }
        }
    }

    /// This Mac's callbacks, with the lab's conditions over its own and none of setup's records.
    private func callbacks(for run: Run) -> SetupWindowController.Callbacks {
        let mac = mac, model = model
        var test = SetupWindowController.Callbacks()
        test.conditions = { model.conditions }
        test.agents = { model.agents }
        test.changes = model.changes
        test.askFolder = { [weak self] in self?.askFolder(else: mac.askFolder) }
        test.openFolderSettings = { [weak self] in self?.allowFolderInSettings(else: mac.openFolderSettings) }
        test.askAccessibility = { [weak self] in self?.allow(\.trusted, "Accessibility", else: mac.askAccessibility) }
        test.askScreenRecording = { [weak self] in self?.allow(\.screenRecording, "Screen Recording", else: mac.askScreenRecording) }
        test.openScreenRecordingSettings = { [weak self] in
            self?.allow(\.screenRecording, "Screen Recording", else: mac.openScreenRecordingSettings)
        }
        test.saveToFolder = { [weak self] in self?.saveToFolder(else: mac.saveToFolder) }
        test.introduceMenuBar = { [weak run] window, conditions, usesLiveInk, close, finished in
            let flies = mac.introduceMenuBar(window, conditions, usesLiveInk, close, finished)
            if flies { run?.closing = true }
            return flies
        }
        test.closed = { [weak self, weak run] setup in
            guard let self, let run else { return }
            if self.current === run {
                self.current = nil
                model.running = false
            }
            self.replaced.removeAll { $0 === run }
            Log.write("[setup-lab] run closed on \(setup.page); nothing recorded")
        }
        return test
    }

    // MARK: Simulated answers

    /// Allow… on a simulated permission: allowed a beat later, as if the person had answered macOS.
    /// On this Mac's own, macOS asks.
    private func allow(_ permission: WritableKeyPath<SetupLabModel.Overrides, Bool?>, _ name: String, else mac: () -> Void) {
        guard let allowed = model.overrides[keyPath: permission] else { return mac() }
        guard !allowed else { return }
        answerLater(permission, from: false, "\(name) asked; allowed in \(Self.beat)s") { true }
    }

    /// macOS's prompt comes up, and a beat later it is answered as the lab says.
    private func askFolder(else mac: () -> Void) {
        guard let folder = model.overrides.folder else { return mac() }
        guard folder == .protected(.ask) else { return }
        model.overrides.folder = .protected(.waiting)
        answerLater(\.folder, from: .protected(.waiting), "folder prompt up; answered in \(Self.beat)s") { [model] in
            .protected(model.folderAnswer == .allow ? .granted : .refused)
        }
    }

    /// After a refusal, the folder allowed in System Settings a beat later.
    private func allowFolderInSettings(else mac: () -> Void) {
        guard let folder = model.overrides.folder else { return mac() }
        guard folder == .protected(.refused) else { return }
        answerLater(\.folder, from: .protected(.refused), "folder allowed in settings in \(Self.beat)s") { .protected(.granted) }
    }

    /// A simulated answer from macOS: `condition` becomes `answer` a beat after `log`, unless it has
    /// changed from `asked` by then.
    private func answerLater<Value: Equatable>(_ condition: WritableKeyPath<SetupLabModel.Overrides, Value?>, from asked: Value,
                                               _ log: String, with answer: @escaping () -> Value) {
        Log.write("[setup-lab] \(log)")
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.beat) { [model] in
            guard model.overrides[keyPath: condition] == asked else { return }
            model.overrides[keyPath: condition] = answer()
        }
    }

    /// macOS writes Save to at once.
    private func saveToFolder(else mac: () -> Void) {
        guard model.overrides.saveTarget != nil else { return mac() }
        model.overrides.saveTarget = "file"
    }
}

/// The lab's conditions, over this Mac's own.
@MainActor
final class SetupLabModel: ObservableObject {
    enum Folder: Hashable {
        case notProtected
        /// On the Desktop, which macOS protects.
        case protected(FolderAccess)

        var name: String {
            switch self {
            case .notProtected: "not-protected"
            case .protected(let access): "desktop-\(access)"
            }
        }
    }

    enum Answer: Hashable { case allow, refuse }

    enum AgentState: Hashable, CaseIterable {
        case absent, notInstalled, installed, noTool

        init(_ status: AgentPluginStatus?) {
            guard let status else { self = .absent; return }
            self = status.installed ? .installed : status.hasTool ? .notInstalled : .noTool
        }
    }

    /// What the lab sets. Each is nil while it is this Mac's own.
    struct Overrides: Equatable {
        /// A home no agent has, so nothing a run does can reach the person's own folders.
        static let home = URL(fileURLWithPath: "/setup-lab")
        /// What a simulated protected folder is called: the Desktop, where macOS saves screenshots
        /// until someone picks another folder.
        static let protectedArea = ScreenshotWatcher.protectedArea(of: home.appendingPathComponent("Desktop"), home: home)

        var trusted: Bool?
        var screenRecording: Bool?
        var folder: Folder?
        var hasScreenshots: Bool?
        var saveTarget: String?
        var menuBarIcon: Bool?
        var claude: AgentState?
        var codex: AgentState?

        func conditions(over mac: SetupConditions) -> SetupConditions {
            var conditions = mac
            if let trusted { conditions.trusted = trusted }
            if let screenRecording { conditions.screenRecording = screenRecording }
            switch folder {
            case nil: break
            case .notProtected:
                conditions.protectedArea = nil
                conditions.folder = .granted
            case .protected(let access):
                conditions.protectedArea = Self.protectedArea
                conditions.folder = access
            }
            if let hasScreenshots { conditions.hasScreenshots = hasScreenshots }
            if let saveTarget { conditions.saveTarget = saveTarget }
            if let menuBarIcon { conditions.menuBarIconVisible = menuBarIcon }
            return conditions
        }

        func agents(over mac: [AgentPluginStatus]) -> [AgentPluginStatus] {
            AgentClient.allCases.compactMap { client in
                guard let state = client == .claude ? claude : codex else { return mac.first { $0.client == client } }
                guard state != .absent else { return nil }
                // With no environment, since CLAUDE_CONFIG_DIR or CODEX_HOME would name a real folder.
                let root = AgentPlugin.root(of: client, home: Self.home, environment: [:])
                return AgentPluginStatus(root: root, client: client, installed: state == .installed, hasTool: state != .noTool)
            }
        }

        /// The simulated conditions, for the log.
        var summary: String {
            var parts: [String] = []
            if let trusted { parts.append("accessibility=\(trusted)") }
            if let screenRecording { parts.append("screenRecording=\(screenRecording)") }
            if let folder { parts.append("folder=\(folder.name)") }
            if let hasScreenshots { parts.append("screenshots=\(hasScreenshots)") }
            if let saveTarget { parts.append("saveTo=\(saveTarget)") }
            if let menuBarIcon { parts.append("icon=\(menuBarIcon)") }
            if let claude { parts.append("claude=\(claude)") }
            if let codex { parts.append("codex=\(codex)") }
            return parts.isEmpty ? "conditions=real" : parts.joined(separator: " ")
        }
    }

    @Published var overrides = Overrides() { didSet { keepStart() } }
    /// How macOS's folder prompt is answered, when the folder is simulated.
    @Published var folderAnswer = Answer.allow
    @Published var scope = SetupModel.Scope.whole { didSet { keepStart() } }
    @Published var start = SetupModel.Page.welcome
    @Published var running = false
    /// This Mac's own, for the pickers' Real and under the overrides.
    @Published var real = SetupWindowController.Callbacks().conditions()
    @Published var realAgents: [AgentPluginStatus] = [] { didSet { keepStart() } }

    /// What a run reads.
    var conditions: SetupConditions { overrides.conditions(over: real) }
    var agents: [AgentPluginStatus] { overrides.agents(over: realAgents) }

    /// Sends when what a run reads changes. `@Published` sends before the change lands, so this sends
    /// a turn later, once for every change made in that turn.
    var changes: AnyPublisher<Void, Never> {
        Publishers.Merge3($overrides.dropFirst().map { _ in }, $real.dropFirst().map { _ in }, $realAgents.dropFirst().map { _ in })
            .debounce(for: .zero, scheduler: DispatchQueue.main)
            .eraseToAnyPublisher()
    }

    /// The pages a run can start on: those the run will hold.
    var startPages: [SetupModel.Page] {
        SetupModel.pages(scope: scope, offersLiveInk: Settings.shared.data.debug, usesLiveInk: true, hasAgents: !agents.isEmpty)
    }

    private func keepStart() {
        if !startPages.contains(start) { start = startPages[0] }
    }

    /// Back to this Mac's own, as the lab closes.
    func forget() {
        overrides = Overrides()
        folderAnswer = .allow
    }
}

@MainActor
private struct SetupLabView: View {
    @ObservedObject var model: SetupLabModel
    let run: () -> Void
    let close: () -> Void

    var body: some View {
        Form {
            Section {
                Picker("Pages", selection: $model.scope) {
                    Text("All").tag(SetupModel.Scope.whole)
                    Text("Live Ink Only").tag(SetupModel.Scope.liveInk)
                }
                .pickerStyle(.segmented)
                Picker("Start on", selection: $model.start) {
                    ForEach(model.startPages, id: \.self) { Text(Self.name(of: $0)).tag($0) }
                }
            } footer: {
                note("Setup opens as it does for someone new and changes nothing on this Mac. The shortcut is your real one, so Try it now works.")
            }
            Section {
                Picker("Accessibility", selection: $model.overrides.trusted) {
                    choices(real: model.real.trusted, on: "Allowed", off: "Not allowed")
                }
                Picker("Screen Recording", selection: $model.overrides.screenRecording) {
                    choices(real: model.real.screenRecording, on: "Allowed", off: "Not allowed")
                }
            } footer: {
                note("Allow… in setup allows a permission set here a second later, without asking macOS.")
            }
            Section {
                Picker("Folder", selection: $model.overrides.folder) {
                    Text("Real (\(Self.folderName(model.real)))").tag(SetupLabModel.Folder?.none)
                    Text("Not protected").tag(SetupLabModel.Folder?.some(.notProtected))
                    ForEach([FolderAccess.ask, .waiting, .granted, .refused], id: \.self) { access in
                        Text("Desktop, \(Self.accessName(access))").tag(SetupLabModel.Folder?.some(.protected(access)))
                    }
                }
                Picker("Folder prompt answer", selection: $model.folderAnswer) {
                    Text("Allow").tag(SetupLabModel.Answer.allow)
                    Text("Don't Allow").tag(SetupLabModel.Answer.refuse)
                }
                .disabled(!folderIsSimulatedProtected)
                Picker("Folder contents", selection: $model.overrides.hasScreenshots) {
                    choices(real: model.real.hasScreenshots, on: "Screenshots", off: "Empty")
                }
                Picker("Save to", selection: $model.overrides.saveTarget) {
                    Text("Real (\(Self.targetName(model.real.saveTarget)))").tag(String?.none)
                    ForEach(["file", "clipboard", "mail", "preview"], id: \.self) { Text(Self.targetName($0)).tag(String?.some($0)) }
                }
                Picker("Claude Code", selection: $model.overrides.claude) { agentStates(.claude) }
                Picker("Codex", selection: $model.overrides.codex) { agentStates(.codex) }
                Picker("Menu bar icon", selection: $model.overrides.menuBarIcon) {
                    choices(real: model.real.menuBarIconVisible, on: "Showing", off: "Hidden")
                }
            }
        }
        .formStyle(.grouped)
        // The run's buttons stay in view however far the conditions scroll.
        .safeAreaInset(edge: .bottom) {
            HStack {
                Spacer()
                Button("Close Setup", action: close).disabled(!model.running)
                Button(model.running ? "Run Again" : "Run Setup", action: run).keyboardShortcut(.defaultAction)
            }
            .padding(12)
            .background(.bar)
        }
        .frame(minWidth: 420, minHeight: 480)
    }

    private var folderIsSimulatedProtected: Bool {
        if case .protected? = model.overrides.folder { return true }
        return false
    }

    @ViewBuilder private func choices(real: Bool, on: String, off: String) -> some View {
        Text("Real (\(real ? on : off))").tag(Bool?.none)
        Text(on).tag(Bool?.some(true))
        Text(off).tag(Bool?.some(false))
    }

    @ViewBuilder private func agentStates(_ client: AgentClient) -> some View {
        let real = SetupLabModel.AgentState(model.realAgents.first { $0.client == client })
        Text("Real (\(Self.agentName(real)))").tag(SetupLabModel.AgentState?.none)
        ForEach(SetupLabModel.AgentState.allCases, id: \.self) { Text(Self.agentName($0)).tag(SetupLabModel.AgentState?.some($0)) }
    }

    private func note(_ text: String) -> some View {
        Text(text).font(.caption).foregroundStyle(.secondary)
            .multilineTextAlignment(.leading).frame(maxWidth: .infinity, alignment: .leading)
    }

    private static func name(of page: SetupModel.Page) -> String {
        switch page {
        case .welcome: "Welcome"
        case .shortcut: "Shortcut"
        case .liveInk: "Live Ink"
        case .liveInkSetup: "Live Ink Permissions, after reopening"
        case .agents: "Agents"
        }
    }

    private static func folderName(_ conditions: SetupConditions) -> String {
        guard let area = conditions.protectedArea else { return "Not protected" }
        return "\(area), \(accessName(conditions.folder))"
    }

    private static func accessName(_ access: FolderAccess) -> String {
        switch access {
        case .ask: "not asked yet"
        case .waiting: "prompt showing"
        case .granted: "allowed"
        case .refused: "refused"
        }
    }

    private static func targetName(_ target: String) -> String {
        switch target {
        case "file": "Folder"
        case "clipboard": "Clipboard"
        default: AppleScreencapture.targetName(target)
        }
    }

    private static func agentName(_ state: SetupLabModel.AgentState) -> String {
        switch state {
        case .absent: "Not on this Mac"
        case .notInstalled: "Plugin not installed"
        case .installed: "Plugin installed"
        case .noTool: "Command missing"
        }
    }
}
