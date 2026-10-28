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
    /// Plays the menu bar intro from a closing window. Its popover names what the conditions leave
    /// missing for someone who used live ink or not.
    private let introduce: (NSWindow, SetupConditions, _ usesLiveInk: Bool, _ close: @escaping () -> Void,
                            _ finished: @escaping () -> Void) -> Bool
    private var panel: NSPanel?
    private let model = SetupLabModel()
    /// Its own, so a run never meets the window a first launch opens.
    private let setup = SetupWindowController()
    private var changes: AnyCancellable?
    /// Keeps the pickers' Real current while the lab is open.
    private var poll: Timer?

    /// How long macOS takes to answer an Allow…, as the lab plays it.
    private static let beat: TimeInterval = 1
    private static let width: CGFloat = 440
    /// Tall enough for every condition without scrolling, where the screen has the room.
    private static let height: CGFloat = 900
    /// Between the lab and the window it runs, and the lab and the screen's edge.
    private static let gap: CGFloat = 12

    init(callbacks: @escaping () -> SetupWindowController.Callbacks,
         introduce: @escaping (NSWindow, SetupConditions, Bool, @escaping () -> Void, @escaping () -> Void) -> Bool) {
        self.callbacks = callbacks
        self.introduce = introduce
        super.init()
        // `objectWillChange` comes before the change, so the window looks a turn later.
        changes = model.objectWillChange.sink { [weak self] in
            DispatchQueue.main.async { self?.conditionsChanged() }
        }
    }

    func show() {
        let p = panel ?? make()
        readThisMac()
        poll = poll ?? Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.readThisMac() }
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
                                                             close: { [weak self] in self?.setup.closeRun {} }))
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
        setup.closeRun {}
        model.forget()
        DispatchQueue.main.async { FocusReturn.shared.restore(reason: "setup lab closed") }
    }

    /// What this Mac has, for the pickers' Real.
    private func readThisMac() {
        let mac = callbacks()
        let conditions = mac.conditions(), agents = mac.agents()
        if model.real != conditions { model.real = conditions }
        if model.realAgents != agents { model.realAgents = agents }
    }

    // MARK: A run

    /// Opens setup under the lab's conditions, closing a run already open first.
    private func run() {
        setup.closeRun { [weak self] in self?.open() }
    }

    private func open() {
        readThisMac()
        model.running = true
        Log.write("[setup-lab] run pages=\(model.scope) start=\(model.start) \(model.summary)")
        setup.run(callbacks: testCallbacks(), scope: model.scope, start: model.start) { [weak self] in self?.place($0) }
    }

    /// Beside the lab, on its left, where the lab leaves room; centred on the screen otherwise.
    private func place(_ window: NSWindow) {
        guard let panel, let visible = (panel.screen ?? NSScreen.main)?.visibleFrame else { return }
        let size = window.frame.size
        let x = panel.frame.minX - Self.gap - size.width
        guard x >= visible.minX else { return }
        window.setFrameOrigin(NSPoint(x: x, y: visible.midY - size.height / 2))
    }

    /// This Mac's callbacks, with the lab's conditions over its own and none of setup's records.
    private func testCallbacks() -> SetupWindowController.Callbacks {
        let mac = callbacks(), model = model
        var test = SetupWindowController.Callbacks()
        test.conditions = { [weak model] in model.map { $0.conditions(over: mac.conditions()) } ?? mac.conditions() }
        test.agents = { [weak model] in model.map { $0.agents(over: mac.agents()) } ?? mac.agents() }
        test.askFolder = { [weak self] in self?.askFolder(else: mac.askFolder) }
        test.openFolderSettings = { [weak self] in self?.allowFolderInSettings(else: mac.openFolderSettings) }
        test.askAccessibility = { [weak self] in self?.allow(\.trusted, "Accessibility", else: mac.askAccessibility) }
        test.askScreenRecording = { [weak self] in self?.allow(\.screenRecording, "Screen Recording", else: mac.askScreenRecording) }
        test.openScreenRecordingSettings = { [weak self] in
            self?.allow(\.screenRecording, "Screen Recording", else: mac.openScreenRecordingSettings)
        }
        test.saveToFolder = { [weak self] in self?.saveToFolder(else: mac.saveToFolder) }
        test.launchAtLogin = { [weak model] in model?.launchAtLogin ?? true }
        test.setLaunchAtLogin = { [weak model] on in
            model?.launchAtLogin = on
            Log.write("[setup-lab] open at login \(on ? "on" : "off"), in the lab only")
        }
        test.introduceMenuBar = { [weak self] window, close, finished in
            self?.introduceMenuBar(from: window, close: close, finished: finished) ?? false
        }
        test.closed = { [weak self] run in
            self?.model.running = false
            Log.write("[setup-lab] run closed on \(run.page); nothing recorded")
        }
        return test
    }

    /// With the icon hidden, the window closes as any window does, as it would on that Mac.
    private func introduceMenuBar(from window: NSWindow, close: @escaping () -> Void, finished: @escaping () -> Void) -> Bool {
        let conditions = model.conditions(over: callbacks().conditions())
        guard conditions.menuBarIconVisible else {
            Log.write("[setup-lab] no menu bar intro: the icon is hidden")
            return false
        }
        return introduce(window, conditions, setup.model?.usesLiveInk ?? false, close, finished)
    }

    private func conditionsChanged() {
        guard let run = setup.model else { return }
        run.readAgents()
        run.looksAgain.send()
    }

    // MARK: Simulated answers

    /// Allow… on a simulated permission: allowed a beat later, as if the person had answered macOS.
    /// On this Mac's own, macOS asks.
    private func allow(_ permission: ReferenceWritableKeyPath<SetupLabModel, Bool?>, _ name: String, else mac: () -> Void) {
        guard let allowed = model[keyPath: permission] else { return mac() }
        guard !allowed else { return }
        Log.write("[setup-lab] \(name) asked; allowed in \(Self.beat)s")
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.beat) { [weak self] in
            guard let self, self.model[keyPath: permission] == false else { return }
            self.model[keyPath: permission] = true
        }
    }

    /// macOS's prompt comes up, and a beat later it is answered as the lab says.
    private func askFolder(else mac: () -> Void) {
        guard let folder = model.folder else { return mac() }
        guard folder == .protected(.ask) else { return }
        model.folder = .protected(.waiting)
        Log.write("[setup-lab] folder prompt up; answered in \(Self.beat)s")
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.beat) { [weak self] in
            guard let self, self.model.folder == .protected(.waiting) else { return }
            self.model.folder = .protected(self.model.folderAnswer == .allow ? .granted : .refused)
        }
    }

    /// After a refusal, the folder allowed in System Settings a beat later.
    private func allowFolderInSettings(else mac: () -> Void) {
        guard let folder = model.folder else { return mac() }
        guard folder == .protected(.refused) else { return }
        Log.write("[setup-lab] folder allowed in settings in \(Self.beat)s")
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.beat) { [weak self] in
            guard let self, self.model.folder == .protected(.refused) else { return }
            self.model.folder = .protected(.granted)
        }
    }

    /// macOS writes Save to at once.
    private func saveToFolder(else mac: () -> Void) {
        guard model.saveTarget != nil else { return mac() }
        model.saveTarget = "file"
    }
}

/// The lab's conditions. Each is nil while it is this Mac's own.
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
    }

    @Published var trusted: Bool?
    @Published var screenRecording: Bool?
    @Published var folder: Folder?
    /// How macOS's folder prompt is answered, when the folder is simulated.
    @Published var folderAnswer = Answer.allow
    @Published var hasScreenshots: Bool?
    @Published var saveTarget: String?
    @Published var menuBarIcon: Bool?
    @Published var claude: AgentState? { didSet { keepStart() } }
    @Published var codex: AgentState? { didSet { keepStart() } }
    /// A run's Open at login, on as a new settings file has it.
    @Published var launchAtLogin = true
    @Published var scope = SetupModel.Scope.whole { didSet { keepStart() } }
    @Published var start = SetupModel.Page.welcome
    @Published var running = false
    /// This Mac's own, for the pickers' Real.
    @Published var real = SetupWindowController.Callbacks().conditions()
    @Published var realAgents: [AgentPluginStatus] = [] { didSet { keepStart() } }

    /// What a simulated protected folder is called: the Desktop, where macOS saves screenshots
    /// until someone picks another folder.
    static let protectedArea = "your Desktop"

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
            guard let state = state(of: client) else { return mac.first { $0.client == client } }
            // A folder no agent has, so nothing a run does can reach the person's own.
            let root = URL(fileURLWithPath: "/setup-lab").appendingPathComponent(client == .claude ? ".claude" : ".codex")
            switch state {
            case .absent: return nil
            case .notInstalled: return AgentPluginStatus(root: root, client: client, installed: false, hasTool: true)
            case .installed: return AgentPluginStatus(root: root, client: client, installed: true, hasTool: true)
            case .noTool: return AgentPluginStatus(root: root, client: client, installed: false, hasTool: false)
            }
        }
    }

    func state(of client: AgentClient) -> AgentState? {
        client == .claude ? claude : codex
    }

    /// The pages a run can start on: those the run will hold.
    var startPages: [SetupModel.Page] {
        let liveInk: [SetupModel.Page] = [.liveInk, .liveInkSetup]
        switch scope {
        case .liveInk: return liveInk
        case .whole:
            let agentsPage: [SetupModel.Page] = agents(over: realAgents).isEmpty ? [] : [.agents]
            return [.welcome, .shortcut] + (Settings.shared.data.debug ? liveInk : []) + agentsPage
        }
    }

    private func keepStart() {
        if !startPages.contains(start) { start = startPages[0] }
    }

    /// Back to this Mac's own, as the lab closes.
    func forget() {
        trusted = nil
        screenRecording = nil
        folder = nil
        folderAnswer = .allow
        hasScreenshots = nil
        saveTarget = nil
        menuBarIcon = nil
        claude = nil
        codex = nil
        launchAtLogin = true
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
                Toggle("Setup's Open at login", isOn: $model.launchAtLogin)
            } footer: {
                note("Setup opens as it does for someone new and changes nothing on this Mac. The shortcut is your real one, so Try it now works.")
            }
            Section {
                Picker("Accessibility", selection: $model.trusted) { allowed(real: model.real.trusted) }
                Picker("Screen Recording", selection: $model.screenRecording) { allowed(real: model.real.screenRecording) }
            } footer: {
                note("Allow… in setup allows a permission set here a second later, without asking macOS.")
            }
            Section {
                Picker("Folder", selection: $model.folder) {
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
                Picker("Folder contents", selection: $model.hasScreenshots) {
                    Text("Real (\(model.real.hasScreenshots ? "Screenshots" : "Empty"))").tag(Bool?.none)
                    Text("Screenshots").tag(Bool?.some(true))
                    Text("Empty").tag(Bool?.some(false))
                }
                Picker("Save to", selection: $model.saveTarget) {
                    Text("Real (\(Self.targetName(model.real.saveTarget)))").tag(String?.none)
                    ForEach(["file", "clipboard", "mail", "preview"], id: \.self) { Text(Self.targetName($0)).tag(String?.some($0)) }
                }
                Picker("Claude Code", selection: $model.claude) { agentStates(.claude) }
                Picker("Codex", selection: $model.codex) { agentStates(.codex) }
                Picker("Menu bar icon", selection: $model.menuBarIcon) {
                    Text("Real (\(model.real.menuBarIconVisible ? "Showing" : "Hidden"))").tag(Bool?.none)
                    Text("Showing").tag(Bool?.some(true))
                    Text("Hidden").tag(Bool?.some(false))
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
        if case .protected? = model.folder { return true }
        return false
    }

    @ViewBuilder private func allowed(real: Bool) -> some View {
        Text("Real (\(real ? "Allowed" : "Not allowed"))").tag(Bool?.none)
        Text("Allowed").tag(Bool?.some(true))
        Text("Not allowed").tag(Bool?.some(false))
    }

    @ViewBuilder private func agentStates(_ client: AgentClient) -> some View {
        let real = model.realAgents.first { $0.client == client }
        Text("Real (\(Self.agentName(real.map(Self.state) ?? .absent)))").tag(SetupLabModel.AgentState?.none)
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

    private static func state(_ status: AgentPluginStatus) -> SetupLabModel.AgentState {
        status.installed ? .installed : status.hasTool ? .notInstalled : .noTool
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
