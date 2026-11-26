import AppKit

@main
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, Actions {
    static func main() {
        // The skill's scripts/reply runs this binary as `<executable> reply …`. It answers and exits
        // here, before an NSApplication exists, so it never starts the app.
        let arguments = CommandLine.arguments.dropFirst()
        if arguments.first == "reply" { ReplyCommand.run(Array(arguments.dropFirst())) }
        let app = NSApplication.shared
        AppLocation.offerMove()
        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
    }

    var statusItem: NSStatusItem?
    /// The dot on the status item while an update waits (Updater).
    var updateDot: NSView?
    var dotExit: DotExit?
    private let menuBarIntro = MenuBarIntro()
    var updater: Updater?
    var watcher: ScreenshotWatcher?
    var captureOrigin: CaptureOrigin?
    /// True on a first launch whose folder macOS protects, until setup asks for it.
    private var watcherWaitsForSetup = false
    /// Why the last plugin install failed, by agent directory, for the Agents tab.
    private var pluginFailures: [URL: String] = [:]
    private var wakeObserver: Any?
    private var terminateSignal: DispatchSourceSignal?
    private var screenObserver: Any?
    private var hotKey: HotKey?
    private var pressDismissed = false      // the last hotkey press closed the stack
    private var holdTarget: Screenshot?     // the card focused at that press
    private var modifierTap: ModifierTap?
    let thumbnail = ThumbnailController()
    let annotator = AnnotationController()
    private lazy var liveInk = LiveInk(mayInk: { [weak self] in !(self?.thumbnail.holdsScreen ?? true) })
    let settingsWindow = SettingsWindowController()
    /// Whether the Settings window is showing live ink's one-time offer.
    var liveInkOfferOpen = false
    private let setupWindow = SetupWindowController()
    private lazy var debugPanel = DebugPanelController(previews: .init(
        thumbnail: { [weak self] in self?.openLast() },
        stack: { [weak self] in self?.toggleRecent() },
        annotator: { [weak self] in self?.annotateLast() },
        intro: { [weak self] in self?.introLab.show() },
        check: { [weak self] in self?.checkLab.show() },
        setup: { [weak self] in self?.setupLab.show() }))
    private lazy var introLab = IntroLabController(
        play: { [weak self] window in
            guard let self else { return false }
            return self.introduceMenuBar(from: window, conditions: self.setupConditions(protectedArea: nil),
                                         usesLiveInk: self.settings.data.liveInk, close: { window.close() }, finished: {})
        },
        iconFrame: { [weak self] in
            self?.visibleStatusButton.flatMap { button in button.window?.convertToScreen(button.convert(button.bounds, to: nil)) }
        })
    private let checkLab = CheckLabController()
    private lazy var setupLab = SetupLabController(
        callbacks: { [unowned self] in self.setupCallbacks(protectedArea: ScreenshotWatcher.protectedArea(of: self.watchFolder)) })
    let settings = Settings.shared
    var watchFolder: URL { settings.data.folderURL }
    /// One map, so Send submits through the same connections it lists.
    static let connections: [AgentClient: any AgentConnection] = [.claude: ClaudeCodeConnection(), .codex: CodexConnection()]
    /// Sending drawings to agent sessions and taking their drawings back. See ScreenshotRequests.
    let requests = ScreenshotRequests(root: ScreenshotRequests.defaultRoot, connections: AppDelegate.connections)
    /// The agent sessions Send can go to. See SessionListing.
    lazy var sessions = SessionListing(connections: AppDelegate.connections, sends: { [unowned self] in requests.sendHistory() },
                                               startable: { StartableSessions().destinations() })
    private let agentPlugins = AgentPlugins()
    /// The screenshot each request Send sent from the editor this launch was made from, until its
    /// client answers. A note card's is LiveNoteCards'.
    var sentShots: [String: Screenshot] = [:]
    /// Live ink notes sent to a session: their note cards, their waits and their result cards.
    private lazy var noteCards = LiveNoteCards(
        folder: folderWrites, drawings: drawings, requests: requests, cards: thumbnail, connections: AppDelegate.connections,
        addMarks: { [weak self] marks, agent, url, done in
            guard let self else { return }
            addMarks(AgentAdditions(marks: marks, agent: agent), to: url, rule: settings.data.ui.liveInkMarkScaleRule) { done($0.map(\.marks)) }
        })
    private var watcherGeneration = 0

    func applicationDidFinishLaunching(_ notification: Notification) {
        let replacing = replaceOlderInstances()
        captureOrigin = CaptureOrigin()
        // `kill` and `killall` send SIGTERM, which would end the process without
        // `applicationWillTerminate`: no settings flush, and Apple's thumbnail left off.
        signal(SIGTERM, SIG_IGN)
        terminateSignal = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
        terminateSignal?.setEventHandler { NSApp.terminate(nil) }
        terminateSignal?.resume()
        AppLocation.ejectDiskImageIfAsked()
        NSApp.setActivationPolicy(.accessory)
        NSApp.mainMenu = MainMenu.make()
        let settingsSource = Launch.isTest ? " (VIGNETTE_SETTINGS) screencapture=\(AppleScreencapture.domainName)" : ""
        Log.writeLaunch("[app] launched \(BuildInfo.current.description) watching \(watchFolder.path) settings \(Settings.fileURL.path)\(settingsSource)")
        if let type = AppleScreencapture.string("type"), !ScreenshotWatcher.isCandidate("screenshot.\(type)") {
            Log.write("[settings] warning Apple screencapture type=\(type) is a format the watcher ignores")
        }
        // The login shell's answer may take seconds; setup and the Agents tab refresh when it comes.
        AgentTools.start()
        updateStatusItem()
        startUpdater()
        // It records the frontmost app from the moment it exists, which has to be before the first
        // window of ours can take the focus.
        _ = FocusReturn.shared
        thumbnail.actions = self
        connectUndo()
        thumbnail.recentListing = { [unowned self] in
            let index = recentShots(limit: settings.data.recentCount)
            watcher?.rescan(reason: "recent")   // keeps the index honest for the next open; nothing waits for it
            return (index.recent.map(Screenshot.init(key:)), "files=\(index.files) ")
        }
        listOlderShots()
        connectAnnotator()
        thumbnail.onTakesScreen = { [weak self] in self?.liveInk.standAside() }
        liveInk.listSessions = { [weak self] answer in self?.sessions.list(answer) }
        liveInk.sendNote = { [weak self] note, destination, title, message, done in
            guard let self else { return done(.failure(ScreenshotRequests.Refusal(reason: SubmissionOutcome.internalReason))) }
            noteCards.send(note, to: destination, titled: title, message: message, done: done)
        }
        liveInk.unsendNote = { [weak self] request in self?.noteCards.unsend(request: request) }
        annotator.onTakesEvents = { [weak self] opening in self?.thumbnail.annotatorTakesEvents(opening) }
        annotator.onFinished = { [weak self] shot, drawing in self?.finishAnnotation(shot, drawing) }
        annotator.onClosed = { [weak self] in self?.thumbnail.annotationEnded($0, $1) }
        annotator.onLoaded = { [weak self] opening in self?.thumbnail.editorLoaded(opening) }
        annotator.onPage = { [weak self] page, isRepeat in self?.thumbnail.page(page, isRepeat: isRepeat) }
        annotator.storedDrawing = { [weak self] key, pixels in
            guard let self else { return nil }
            return drawings.read(key, pixels: pixels, style: settings.data.ui.textStyle)
        }
        annotator.onSend = { [weak self] shot, drawing, destination, title, message in
            self?.sendDrawing(drawing, of: shot, to: destination, titled: title, message: message)
        }
        annotator.onCopyDrawing = { [weak self] shot, drawing in self?.copyDrawing(drawing, of: shot) }
        thumbnail.drags = DragItems(drawings: drawings)
        settingsWindow.callbacks = SettingsWindowController.Callbacks(
            openTweaks: { [weak self] in self?.debugPanel.toggle() },
            installAgentPlugin: { [weak self] root, done in self?.turnOnAgents([root]) { done($0) } },
            removeAgentPlugin: { [weak self] root, done in self?.removeAgentPlugin(from: root, completion: done) },
            folderDenied: { [weak self] in self?.watcher?.isDenied ?? false },
            agentFailures: { [weak self] in self?.pluginFailures ?? [:] },
            liveInkOffered: { [weak self] in self?.liveInkOfferOpen ?? false },
            answerLiveInkOffer: { [weak self] on in self?.answerLiveInkOffer(on) })
        // Before the watcher, so a capture taken during launch already lands the way Vignette needs.
        settings.reconcileApple()
        Leftovers.removeAtLaunch()
        startDrawings()
        startRequests(clearingUnsent: !replacing)
        // A first launch leaves a folder macOS protects alone until setup has said why Vignette
        // needs it: the watcher's first read is what raises macOS's prompt.
        let protectedArea = setupWindow.asksForFolder ? ScreenshotWatcher.protectedArea(of: watchFolder) : nil
        watcherWaitsForSetup = protectedArea != nil
        if watcherWaitsForSetup {
            Log.write("[watcher] waiting for setup to ask for \(watchFolder.path)")
        } else {
            startWatching()
        }
        registerHotKey()
        liveInk.setOn(settings.data.liveInk)
        settings.onChange = { [weak self] old, new in self?.settingsChanged(old, new) }
        // Setup comes first and has the launch to itself: two windows competing for a first-time
        // user is worse than the plugin offer waiting until the next launch.
        if setupWindow.isUnasked {
            // The login item and the plugin wait for the window to close, which applies the
            // switches it shows.
            setupWindow.applyLoginItem = { [weak self] in self?.applyLoginItem() }
            setupWindow.show(callbacks: setupCallbacks(protectedArea: protectedArea))
        } else {
            // The setting is the user's wish; macOS may have lost the registration (the app moved) or kept one the file no longer asks for.
            // A removal in System Settings is a wish too, and turns the setting off instead.
            if settings.data.launchAtLogin, LoginItem.removedByPerson {
                Log.write("[login] removed in System Settings; Open at login is off")
                settings.update { $0.launchAtLogin = false }
            } else {
                applyLoginItem()
            }
            // The Settings window shows one tab, so one offer a launch: live ink's waits for the next.
            if !startAgentPlugin() { offerLiveInk() }
        }
        sessions.refreshKeptLists()
        CheckCoin.compileShaders()
        // The contract for agents: after this line every command answers.
        Log.write("[app] ready pid=\(ProcessInfo.processInfo.processIdentifier) build=\(BuildInfo.current.build) watching=\(watchFolder.path)")
    }

    /// Opening Vignette again, from Finder, Spotlight or the Dock, opens Settings. With the menu bar
    /// icon hidden it is the one way back to them.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        Log.write("[app] reopened")
        if !setupWindow.bringToFront() { settingsWindow.show() }
        return false
    }

    func applicationWillTerminate(_ notification: Notification) {
        setupWindow.quitting = true
        annotator.storeForQuit()
        settings.flush()
        // A newer launch replacing this one has already turned Apple's thumbnail off for itself.
        let replaced = NSRunningApplication.runningApplications(withBundleIdentifier: Identity.bundleID)
            .contains { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }
        if !replaced { settings.handBackAppleThumbnail() }
        Log.write("[app] terminating pid=\(ProcessInfo.processInfo.processIdentifier)")
        // Last, and for at most 2 s: a newer launch forces this copy out after 3 s.
        requests.releaseHeld()
    }

    /// The newer launch wins: any running copy of this bundle id is asked to quit, and forced after
    /// a grace period. Two copies would both watch the folder, write settings, and register the hotkey.
    /// Answers whether there was one.
    @discardableResult
    private func replaceOlderInstances() -> Bool {
        let me = ProcessInfo.processInfo.processIdentifier
        let older = NSRunningApplication.runningApplications(withBundleIdentifier: Identity.bundleID).filter { $0.processIdentifier != me }
        guard !older.isEmpty else { return false }
        for app in older {
            Log.write("[app] replacing older instance pid=\(app.processIdentifier)")
            app.terminate()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            for app in older where !app.isTerminated {
                Log.write("[app] older instance pid=\(app.processIdentifier) did not quit; forcing")
                app.forceTerminate()
            }
        }
        return true
    }

    private func settingsChanged(_ old: SettingsData, _ new: SettingsData) {
        if new.ui != old.ui { thumbnail.applyTweaks(); annotator.applyTweaks(); liveInk.applyTweaks(); warmThumbnails() }
        if new.recentCount != old.recentCount { warmThumbnails() }
        if new.screenshotsFolder != old.screenshotsFolder {
            // A folder macOS doesn't protect needs no asking, so a move to one while setup waits
            // starts the watch at once.
            if !watcherWaitsForSetup {
                startWatching()
            } else if ScreenshotWatcher.protectedArea(of: watchFolder) == nil {
                askForFolder()
            } else {
                Log.write("[watcher] waiting for setup to ask for \(watchFolder.path)")
            }
        }
        if new.recentHotkey != old.recentHotkey { registerHotKey() }
        if new.liveInk != old.liveInk { liveInk.setOn(new.liveInk) }
        if new.liveInk { liveInkOfferOpen = false; if !new.liveInkOffered { settings.update { $0.liveInkOffered = true } } }
        if new.liveInkChord != old.liveInkChord { liveInk.takeChord() }
        if new.hideMenuBarIcon != old.hideMenuBarIcon { updateStatusItem(); showUpdateDot() }
        if new.launchAtLogin != old.launchAtLogin { applyLoginItem() }
    }

    /// Registers or removes the login item as the setting asks. While the menu bar intro plays this
    /// waits for it to go, since macOS announces a new login item in the corner the intro's popover
    /// is in. A quit before then loses nothing: every later launch applies the setting.
    private func applyLoginItem() {
        guard !menuBarIntro.isPlaying else { loginItemAfterIntro = true; return }
        LoginItem.apply(settings.data.launchAtLogin)
    }

    private var loginItemAfterIntro = false

    // MARK: The agent plugin

    /// Launch: the offer if it has never been made, then the marketplace written and every
    /// installed plugin brought up to this app's version (`AgentPlugins.launch`). A plugin goes in
    /// by itself only where the skill from before the plugin was, since that person chose the skill.
    /// Answers whether the offer was made.
    private func startAgentPlugin() -> Bool {
        let offered = settings.data.agentSkillChoice == .unasked && offerAgentPlugin()
        agentPlugins.launch { _ in }
        return offered
    }

    /// The Agents tab's switch, the setup window and `install-skill`. `AgentPlugins` logs each
    /// result, and the Agents tab shows a failure under the agent's name.
    func installAgentPlugin(into roots: [URL], completion: @escaping ([AgentPlugin.Result]) -> Void = { _ in }) {
        agentPlugins.install(into: roots) { [weak self] results in
            for result in results {
                let failed = [.failed, .noTool].contains(result.outcome)
                self?.pluginFailures[result.root] = failed ? "Couldn't install: \(result.detail)" : nil
            }
            completion(results)
        }
    }

    /// A person turning agents on, in setup or the Agents tab: the plugin, and for Claude Code the
    /// permission to open the drawings Vignette sends (`ClaudeReadRule`), once the plugin is in.
    /// `install-skill` installs without it, since a script must not change a person's settings.
    func turnOnAgents(_ roots: [URL], completion: @escaping ([AgentPlugin.Result]) -> Void = { _ in }) {
        installAgentPlugin(into: roots) { results in
            for result in results where ![.failed, .noTool].contains(result.outcome) && AgentPlugin.appClient(of: result.root) == .claude {
                ClaudeReadRule.apply(true, in: result.root)
            }
            completion(results)
        }
    }

    /// Setup has closed by the time its install answers, so a failure opens the Agents tab, which
    /// says why and whose switch tries again.
    private func installAgentPluginFromSetup(_ roots: [URL]) {
        turnOnAgents(roots) { [weak self] results in
            guard results.contains(where: { [.failed, .noTool].contains($0.outcome) }) else { return }
            self?.settingsWindow.show(tab: .agents, activating: false)
        }
    }

    /// The Agents tab's switch, turned off. For Claude Code the permission goes with the plugin, so
    /// its settings are left as they were before Vignette.
    func removeAgentPlugin(from root: URL, completion: @escaping (AgentPlugin.Result) -> Void) {
        agentPlugins.remove(from: root) { result in
            if ![.failed, .noTool].contains(result.outcome), AgentPlugin.appClient(of: root) == .claude {
                ClaudeReadRule.apply(false, in: root)
            }
            completion(result)
        }
    }

    /// The offer, once: the app has never asked and this Mac has an agent directory. The offer is
    /// the Settings window, and the answer is the buttons in it.
    /// Recorded as `off` as it is made, so the question is asked once whatever the user does.
    private func offerAgentPlugin() -> Bool {
        let roots = AgentPlugin.appRoots()
        guard !roots.isEmpty else { return false }
        settings.update { $0.agentSkill = AgentSkill.off.rawValue }
        Log.write("[plugin] offered \(roots.map(\.lastPathComponent).joined(separator: " "))")
        settingsWindow.show(tab: .agents, activating: false)
        return true
    }

    /// The agent folders whose settings have the plugin on, for the state report.
    private func installedPluginRoots() -> [String] {
        AgentPlugin.appStatuses().filter(\.installed).map(\.root.path)
    }

    /// `vignette://install-skill`, for a script: it installs the plugin for every agent on this Mac,
    /// or with `root=` into that one config folder, and answers when the agents' tools have. It
    /// writes no setting; the agents' own settings are what a later launch reads.
    private func installSkill(_ request: CommandRequest) {
        if let root = request.root, !settings.data.debug {
            Commands.error("install-skill", .debugDisabled, "root=\(root.path) needs \"debug\": true in settings.json"); return
        }
        guard AgentPlugin.bundled != nil, AgentPlugin.bundledSkill != nil else {
            Commands.error("install-skill", .missingFile, "the plugin is not in the bundle"); return
        }
        let roots = request.root.map { [$0] } ?? AgentPlugin.appRoots()
        guard !roots.isEmpty else {
            Commands.error("install-skill", .noAgent, "no .claude or .codex in this home folder"); return
        }
        installAgentPlugin(into: roots) { results in
            let detail = results.filter { ![.absent].contains($0.outcome) }
                .map { "\($0.root.path)=\($0.outcome.rawValue)" }.joined(separator: " ")
            if let bad = results.first(where: { [.failed, .noTool].contains($0.outcome) }) {
                Commands.error("install-skill", bad.outcome == .noTool ? .noAgent : .writeFailed,
                               bad.detail.isEmpty ? detail : "\(detail) \(bad.detail)")
                return
            }
            Commands.ok("install-skill", detail)
        }
    }

    private func registerHotKey() {
        hotKey = nil
        modifierTap = nil
        // The press toggles the stack. Holding on lifts a card out of it: the newest, or, when the
        // press closed an open stack, the focused one; the stack comes back first so it can leave from its slot.
        let fire = { [weak self] in
            guard let self else { return }
            Log.write("[hotkey] recent")
            NotificationCenter.default.post(name: .hotKeyFired, object: nil)
            let focused = thumbnail.focusedShot
            pressDismissed = pressRecent(by: .shortcut) == .dismissed
            holdTarget = pressDismissed ? focused : nil
            if !pressDismissed { sessions.refreshKeptLists() }   // a card from the stack may open next
        }
        let hold = { [weak self] in
            guard let self else { return }
            Log.write("[hotkey] hold")
            NotificationCenter.default.post(name: .hotKeyHeld, object: nil)
            if pressDismissed { _ = pressRecent(by: .shortcut) }
            if let shot = holdTarget, shot.kind == .image { annotate([shot]) } else { annotateLast() }
        }
        switch HotKeySpec.parse(settings.data.recentHotkey) {
        case .key(let keyCode, let modifiers):
            let registered = HotKey(keyCode: keyCode, modifiers: modifiers, action: fire, hold: hold)
            guard registered.status == noErr else {
                Log.write("[hotkey] error \(settings.data.recentHotkey) not registered: status \(registered.status)")
                return
            }
            hotKey = registered
        case .doubleTap(let keyCode):
            modifierTap = ModifierTap(keyCode: keyCode, action: fire, hold: hold)
        case nil:
            Log.write("[hotkey] cannot parse \"\(settings.data.recentHotkey)\"; no hotkey registered")
            return
        }
        Log.write("[hotkey] registered \(settings.data.recentHotkey)")
    }

    // MARK: Actions (see Config.actions). Lists arrive in selection order from the stack, else as the URL named them.

    func copyToClipboard(_ shots: [Screenshot]) {
        guard !shots.isEmpty else { Commands.error("copy", .missingFile, "nothing selected"); return }
        Clipboard.copyFiles(shots.map(\.url))
        Commands.ok("copy", shots.map(\.url.lastPathComponent).joined(separator: ", "))
        thumbnail.showCopied(shots)
    }

    func copyPaths(_ shots: [Screenshot]) {
        guard !shots.isEmpty else { Commands.error("paths", .missingFile, "nothing selected"); return }
        Clipboard.copyText(Clipboard.pathsText(shots.map(\.url)))
        Commands.ok("paths", shots.map(\.url.lastPathComponent).joined(separator: ", "))
        thumbnail.showCopied(shots, label: "Copied Path")
    }

    func annotate(_ shots: [Screenshot]) { annotate(shots, from: nil) }

    private func annotate(_ shots: [Screenshot], from origin: NSRect?) {
        guard let shot = shots.first else { Commands.error("annotate", .missingFile, "nothing selected"); return }
        if let recording = shots.first(where: { $0.kind == .recording }) {
            Commands.error("annotate", .unsupportedType, "\(recording.url.lastPathComponent) is a recording"); return
        }
        Commands.ok("annotate", shots.count > 1 ? "\(shot.url.lastPathComponent) 1 of \(shots.count)" : shot.url.lastPathComponent)
        thumbnail.annotate(shots, from: origin)
    }

    /// The newest screenshot in the watch folder goes into the annotator, on screen or not. A newer
    /// recording is passed over: the hold and this menu item both promise drawing.
    @objc private func annotateLast() {
        guard let key = newestShot(where: { $0.kind == .image }) else {
            Commands.error("annotate", .missingFile, "no screenshot in \(watchFolder.path)"); return
        }
        annotate([Screenshot(key: key)])
    }

    // MARK: Drawings

    lazy var drawings = Drawings(store: DrawingStore(directory: Identity.applicationSupportURL.appendingPathComponent("drawings")))

    /// What Vignette puts into the screenshots folder and takes out of it. See FolderWrites.
    lazy var folderWrites: FolderWrites = {
        let writes = FolderWrites()
        writes.callbacks = FolderWrites.Callbacks(
            folder: { [weak self] in self?.watchFolder ?? FileManager.default.temporaryDirectory },
            present: { [weak self] shot, annotate in self?.present(shot, annotate: annotate, from: annotate ? self?.capturedRect(of: shot) : nil) },
            showCard: { [weak self] in self?.thumbnail.show($0) },
            joinMarks: { [weak self] additions, key, done in
                guard let self else { return }
                addMarks(additions, to: key, rule: settings.data.ui.markScaleRule, done: done)
            },
            storedDrawing: { [weak self] in self?.storedDrawing($0) },
            currentDrawing: { [weak self] key in self?.drawings.current(of: key) { self?.storedDrawing(key) } },
            removeCards: { [weak self] in self?.thumbnail.remove($0) },
            removeDrawings: { [weak self] keys, observedAt in self?.drawings.remove(keys, observedAt: observedAt) },
            fileRemoved: { [weak self] in self?.requests.fileRemoved($0) },
            renameCards: { [weak self] renames in
                guard let self else { return }
                self.thumbnail.rename(renames)
                for rename in renames {
                    for (id, shot) in self.sentShots where shot.key == rename.from { self.sentShots[id] = Screenshot(key: rename.to) }
                }
                self.noteCards.renamed(renames)
            },
            renameDrawings: { [weak self] renames in
                guard let self else { return }
                for rename in renames { self.drawings.rename(from: rename.from, to: rename.to, style: self.settings.data.ui.textStyle) }
            },
            renameRequests: { [weak self] in self?.requests.renamed($0) },
            isVisible: { [weak self] in self?.requests.isVisible($0) ?? true },
            sweepDrawings: { [weak self] in self?.drawings.sweep($0) },
            reconcileRequests: { [weak self] in self?.requests.reconcile($0) },
            rescan: { [weak self] in self?.watcher?.rescan(reason: $0) })
        return writes
    }()

    func open(_ shots: [Screenshot]) {
        guard !shots.isEmpty else { Commands.error("open", .missingFile, "nothing selected"); return }
        for shot in shots { NSWorkspace.shared.open(shot.url) }
        Commands.ok("open", shots.map(\.url.lastPathComponent).joined(separator: ", "))
    }

    // MARK: URL commands: vignette://<command>[?file=/path&file=/other]. See Commands.swift.

    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            Log.write("[url] \(url.absoluteString)")
            run(Commands.parse(url))
        }
    }

    private func run(_ request: CommandRequest) {
        let cmd = request.name
        guard Commands.isKnown(cmd) else {
            Commands.error(cmd, .unknownCommand, "\"\(cmd)\"; open -g \(Identity.urlScheme)://help lists the commands"); return
        }
        if Commands.needsDebug(cmd) && !settings.data.debug {
            Commands.error(cmd, .debugDisabled, "set \"debug\": true in settings.json"); return
        }
        switch cmd {
        case "help":
            for line in Commands.helpLines() { Log.write("[help] \(line)") }
            Commands.ok("help", "\(Commands.fixed.count + Config.actions.count) commands; errors end with one of: \(CommandError.allCases.map(\.rawValue).joined(separator: " "))")
        case "last": openLast()
        case "add": folderWrites.add(request)
        case "show": show(request)
        case "recent": pressRecent(by: .url)
        case "state": dumpState(tag: request.tag, section: request.section)
        case "settings": settingsWindow.show(); Commands.ok("settings", "window opened")
        case "install-skill": installSkill(request)
        case "reply":
            guard let file = request.files.first else { Commands.error("reply", .missingFile, "no file given"); return }
            requests.receiveReply(envelope: file)
        case "requests": requests.run(clear: request.clear)
        case "restore-apple-defaults": restoreAppleDefaults()
        case "live-ink-clear":
            guard liveInk.isOn else { Commands.error(cmd, .liveInkOff, "set \"liveInk\" to true in settings.json"); return }
            Commands.ok(cmd, "cleared \(liveInk.clear())")
        case "live-ink-stroke":
            guard liveInk.isOn else { Commands.error(cmd, .liveInkOff, "set \"liveInk\" to true in settings.json"); return }
            guard let points = request.points.flatMap(Commands.points) else {
                Commands.error(cmd, .invalidPoints, "give &points=x,y;x,y in global top-left points"); return
            }
            Commands.ok(cmd, "\(liveInk.take(points).description) marks=\(liveInk.marks.count)")
        case "live-ink-chord-down", "live-ink-chord-up":
            guard liveInk.isOn else { Commands.error(cmd, .liveInkOff, "set \"liveInk\" to true in settings.json"); return }
            liveInk.chordChanged(cmd == "live-ink-chord-down" ? .began : .ended)
            Commands.ok(cmd, "inking=\(liveInk.isInking)")
        case "live-ink-ask":
            guard liveInk.isOn else { Commands.error(cmd, .liveInkOff, "set \"liveInk\" to true in settings.json"); return }
            let words = request.message ?? ""
            guard let id = request.session else {
                switch liveInk.ask(words, to: liveInk.noteAgent) {
                case .success: Commands.ok(cmd, "asking")
                case .failure(let failure): Commands.error(cmd, .liveInkNotAsked, failure.reason)
                }
                return
            }
            // The session a person would pick in the note's target, from the list Send has.
            var answered = false
            // A kept list can predate the session, so only fresh lists can say it is missing.
            sessions.list { [weak self] candidates in
                guard let self, !answered else { return }
                let fresh = candidates.fresh
                if let session = SessionMenu.noteSession(id, among: candidates) {
                    answered = true
                    switch liveInk.ask(words, to: session.destination.client, sendingTo: session) {
                    case .success: Commands.ok(cmd, "sending to \(session.destination.project)")
                    case .failure(let failure): Commands.error(cmd, .liveInkNotAsked, failure.reason)
                    }
                } else if fresh {
                    answered = true
                    Commands.error(cmd, .noAgent, "no session \(id) in the list Send has")
                }
            }
        case "tweaks": debugPanel.toggle(); Commands.ok("tweaks")
        case "intro-lab": introLab.show(); Commands.ok("intro-lab")
        case "setup-lab": setupLab.show(); Commands.ok(cmd)
        case "check-lab": checkLab.show(); Commands.ok("check-lab")
        case "dismiss": thumbnail.dismiss(by: .url); Commands.ok("dismiss")
        case "cancel": Commands.ok("cancel", annotator.cancelForDebug() ? "" : "nothing was open")
        default:
            guard let action = Config.action(id: cmd) else { return }
            var targets: [Screenshot]
            if request.files.isEmpty {
                // The newest file the action can take, so `annotate` passes over a newer recording
                // and `open` over newer screenshots.
                guard let newest = newestShot(where: { action.kinds.contains($0.kind) }) else {
                    Commands.error(cmd, .missingFile, "no file given and none it applies to in \(watchFolder.path)"); return
                }
                targets = [Screenshot(key: newest)]
            } else {
                // Only debug mode lets a file outside the folder past the policy check below.
                targets = request.files.map { Screenshot(key: ScreenshotKey(naming: $0, in: watchFolder)) }
            }
            if !targets.allSatisfy({ action.kinds.contains($0.kind) }),
               let reason = action.unavailableReason(for: targets) {
                Commands.error(cmd, .unsupportedType, reason); return
            }
            if let bad = targets.lazy.compactMap({ self.fileError($0.url) }).first { Commands.error(cmd, bad.code, bad.detail); return }
            guard targets.count >= action.minimumCount else {
                Commands.error(cmd, .notEnoughFiles, "needs \(action.minimumCount), got \(targets.count)"); return
            }
            if cmd == "annotate" {
                // Refused here, before any transition starts, so a dead file never opens an empty editor.
                if let bad = targets.first(where: { !Commands.isReadableImage($0.url) }) { Commands.error(cmd, .unreadableImage, bad.url.path); return }
            } else if let missing = targets.first(where: { !FileManager.default.fileExists(atPath: $0.url.path) }) {
                Commands.error(cmd, .missingFile, missing.url.path); return
            }
            action.run(targets, self)
        }
    }

    private func residentBytes() -> Int {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size / MemoryLayout<natural_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count) }
        }
        return result == KERN_SUCCESS ? Int(info.resident_size) : 0
    }

    /// One `[state] {json}` line, written at once.
    private func dumpState(tag: String?, section: String?) {
        var report = StateReport()
        report.sections = thumbnail.stateJSON
        report.sections["tag"] = tag as Any
        report.sections["app"] = [
            "pid": Int(ProcessInfo.processInfo.processIdentifier), "build": BuildInfo.current.build, "version": BuildInfo.current.version,
            "isActive": NSApp.isActive, "accessibility": ModifierTap.trusted(prompt: false),
            "screenRecording": CGPreflightScreenCaptureAccess(),
            "watchFolder": watchFolder.path, "settingsFile": Settings.fileURL.path, "readOnly": settings.readOnly,
            "bundle": Bundle.main.bundlePath,
            "appleThumbnail": settings.data.appleThumbnail, "recentCount": settings.data.recentCount, "hotkey": settings.data.recentHotkey, "debug": settings.data.debug,
            "launchAtLogin": settings.data.launchAtLogin, "loginItem": LoginItem.status,
            "update": updater?.stateJSON as Any,
            "menuBarIcon": statusItem == nil ? "off" : visibleStatusButton == nil ? "not showing" : "showing",
            "agentSkill": ["setting": settings.data.agentSkill, "installed": installedPluginRoots()] as [String: Any],
        ] as [String: Any]
        report.sections["annotator"] = annotator.stateJSON
        report.sections["editor"] = annotator.editor.core.inspection
        report.sections["drawings"] = drawings.keys.sorted().map(\.path)
        report.sections["requests"] = requests.stateJSON
        var live = liveInk.stateJSON
        live["watching"] = noteCards.watching
        report.sections["liveInk"] = live
        report.sections["memory"] = ["rss": residentBytes(), "thumbnails": Thumbnailer.cacheBytes]
        if let section {
            let always = ["tag", "app"]
            guard let picked = report.sections[section], !always.contains(section) else {
                let choices = report.sections.keys.filter { !always.contains($0) }.sorted()
                Commands.error("state", .unknownSection, "\"\(section)\"; the sections are \(choices.joined(separator: " ")), and every report has app and tag")
                return
            }
            report.sections = ["tag": tag as Any, "app": report.sections["app"] as Any, section: picked]
        }
        Log.write("[state] \(report.rendered())")
    }

    // MARK: Status item

    private func updateStatusItem() {
        if settings.data.hideMenuBarIcon {
            if let item = statusItem { NSStatusBar.system.removeStatusItem(item) }
            statusItem = nil
            return
        }
        guard statusItem == nil else { return }
        // On a crowded menu bar macOS drops a new item into the space under the notch, where it is
        // invisible. Seed a spot near the right edge once; after that macOS remembers where the user drags it.
        let positionKey = "NSStatusItem Preferred Position \(Identity.statusItemAutosaveName)"
        if UserDefaults.standard.object(forKey: positionKey) == nil { UserDefaults.standard.set(80, forKey: positionKey) }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.autosaveName = NSStatusItem.AutosaveName(Identity.statusItemAutosaveName)
        let image = NSImage(named: "MenuBarIcon")
        image?.isTemplate = true
        image?.accessibilityDescription = Identity.name
        item.button?.image = image
        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
        statusItem = item
    }

    /// The status item's button when a person can see it: not turned off, and not hidden by macOS
    /// for want of room (`MenuBarIntro.canSee`).
    private var visibleStatusButton: NSStatusBarButton? {
        statusItem?.button.flatMap { MenuBarIntro.canSee($0) ? $0 : nil }
    }

    /// What setup reads from this Mac and asks of it. `protectedArea` names the folder macOS will ask
    /// about, or is nil when it won't.
    private func setupCallbacks(protectedArea: String?) -> SetupWindowController.Callbacks {
        SetupWindowController.Callbacks(
            conditions: { [unowned self] in setupConditions(protectedArea: protectedArea) },
            agents: { AgentPlugin.appStatuses() },
            responders: .shared,
            // `@Published` sends before the change lands, so the window looks a turn later.
            changes: settings.$appleTarget.dropFirst().map { _ in }
                .merge(with: NotificationCenter.default.publisher(for: AgentTools.found).map { _ in })
                .receive(on: DispatchQueue.main)
                .eraseToAnyPublisher(),
            askFolder: { [weak self] in self?.askForFolder() },
            openFolderSettings: { [weak self] in self?.openFilesAndFolders() },
            askAccessibility: { Accessibility.request() },
            askScreenRecording: { ScreenRecording.request() },
            openScreenRecordingSettings: { ScreenRecording.openSystemSettings() },
            askPickerQuestion: { PickerQuestion.ask() },
            saveToFolder: { Settings.shared.saveCapturesAsFiles() },
            launchAtLogin: { Settings.shared.data.launchAtLogin },
            installAgentPlugin: { [weak self] roots in self?.installAgentPluginFromSetup(roots) },
            introduceMenuBar: { [weak self] window, conditions, usesLiveInk, close, finished in
                self?.introduceMenuBar(from: window, conditions: conditions, usesLiveInk: usesLiveInk, close: close, finished: finished) ?? false
            })
    }

    /// This Mac's conditions, as setup reads them. `protectedArea` names the folder macOS will ask
    /// about, or is nil when it won't.
    private func setupConditions(protectedArea: String?) -> SetupConditions {
        SetupConditions(trusted: ModifierTap.trusted(prompt: false), screenRecording: ScreenRecording.granted,
                        pickerQuestion: PickerQuestion.status, protectedArea: protectedArea, folder: folderAccess, hasScreenshots: hasScreenshots,
                        saveTarget: settings.appleTarget, menuBarIconVisible: visibleStatusButton != nil)
    }

    /// Setup is closing: its window flies into the menu bar icon, and a popover under the icon says
    /// how to use Vignette, or names what `conditions` leave missing for someone who uses live ink or
    /// not, which the menu then lists. False with no icon to point at, and setup closes as any window
    /// does.
    private func introduceMenuBar(from window: NSWindow, conditions: SetupConditions, usesLiveInk: Bool,
                                  close: @escaping () -> Void, finished: @escaping () -> Void) -> Bool {
        guard conditions.menuBarIconVisible, let button = visibleStatusButton else {
            Log.write("[setup] menu bar intro skipped: the icon is \(statusItem == nil ? "off" : "not showing")")
            return false
        }
        let shortcut = HotKeySpec.parse(settings.data.recentHotkey)
        let note: MenuBarIntro.Note = missingNote(missing(in: conditions, usesLiveInk: usesLiveInk))
            ?? shortcut.map { .shortcut($0) } ?? .text("Use the shortcut to see your recent screenshots.")
        Log.write("[setup] menu bar intro")
        menuBarIntro.play(from: window, into: button, note: note, duration: settings.motionUI.introDuration,
                          close: close) { [weak self] in
            finished()
            guard let self, self.loginItemAfterIntro else { return }
            self.loginItemAfterIntro = false
            self.applyLoginItem()
        }
        return true
    }

    /// What stops Vignette working, as menu items that fix it. Apple's thumbnail is off while
    /// Vignette runs, so without these a capture would show nothing and say nothing.
    private func blockers() -> [NSMenuItem] {
        missing().map { blocker in
            switch blocker {
            case .folderAccess:
                return NSMenuItem(title: "Allow Access to Your Screenshots…", action: #selector(openFilesAndFolders), keyEquivalent: "")
            case let .saveTarget(target):
                let item = NSMenuItem(title: "Save Screenshots to a Folder", action: #selector(saveCapturesAsFiles), keyEquivalent: "")
                if #available(macOS 14.4, *) { item.subtitle = "macOS sends them to \(target)." }
                return item
            case let .accessibility(shortcut, liveInk):
                let what = shortcut && liveInk ? "the Shortcut and Live Ink" : shortcut ? "the Shortcut" : "Live Ink"
                return NSMenuItem(title: "Allow Accessibility for \(what)…", action: #selector(requestAccessibility), keyEquivalent: "")
            case .screenRecording:
                return NSMenuItem(title: "Allow Screen Recording for Live Ink…", action: #selector(openScreenRecording), keyEquivalent: "")
            }
        }
    }

    /// What the menu lists first, as the way to fix it, and the intro's popover names.
    private enum Blocker {
        case folderAccess
        /// macOS saves captures somewhere other than a folder, named for a person ("the Clipboard").
        case saveTarget(String)
        /// Accessibility, for the double tap, live ink, or both.
        case accessibility(shortcut: Bool, liveInk: Bool)
        /// Screen Recording, which live ink's asks need to see the window under the ink.
        case screenRecording
    }

    private func missing() -> [Blocker] {
        missing(in: setupConditions(protectedArea: nil), usesLiveInk: settings.data.liveInk)
    }

    /// What is missing under `conditions`, for someone who uses live ink or not.
    private func missing(in conditions: SetupConditions, usesLiveInk liveInk: Bool) -> [Blocker] {
        var missing: [Blocker] = []
        if conditions.folder == .refused { missing.append(.folderAccess) }
        if conditions.saveTarget != "file" { missing.append(.saveTarget(AppleScreencapture.targetName(conditions.saveTarget))) }
        let shortcut = settings.data.usesDoubleTap
        if shortcut || liveInk, !conditions.trusted { missing.append(.accessibility(shortcut: shortcut, liveInk: liveInk)) }
        if liveInk, !conditions.screenRecording { missing.append(.screenRecording) }
        return missing
    }

    /// What the intro's popover says is still missing: one sentence for one thing, else a list
    /// worded as the menu items are.
    private func missingNote(_ missing: [Blocker]) -> MenuBarIntro.Note? {
        guard let only = missing.first else { return nil }
        guard missing.count == 1 else {
            return .list("Click the icon to:", missing.map { blocker in
                switch blocker {
                case .folderAccess: "Allow access to your screenshots"
                case .saveTarget: "Save screenshots to a folder"
                case let .accessibility(shortcut, liveInk):
                    "Allow Accessibility for \(shortcut && liveInk ? "the shortcut and live ink" : shortcut ? "the shortcut" : "live ink")"
                case .screenRecording: "Allow Screen Recording for live ink"
                }
            })
        }
        switch only {
        case .folderAccess: return .text("\(Identity.name) can't open your screenshots folder. Click the icon to allow it.")
        case let .saveTarget(target): return .text("macOS sends your screenshots to \(target). Click the icon to save them to a folder.")
        case let .accessibility(shortcut, liveInk):
            let what = shortcut && liveInk ? "The shortcut and live ink need" : shortcut ? "The shortcut needs" : "Live ink needs"
            return .text("\(what) Accessibility. Click the icon to allow it.")
        case .screenRecording: return .text("Live ink needs Screen Recording. Click the icon to allow it.")
        }
    }

    private func rebuildMenu(_ menu: NSMenu) {
        menu.removeAllItems()
        let shortcut = HotKeySpec.parse(settings.data.recentHotkey)

        MainMenu.addSettings(to: menu, action: #selector(openSettings))
        let liveInkItem = NSMenuItem(title: "Live Ink", action: #selector(toggleLiveInk), keyEquivalent: "")
        liveInkItem.state = settings.data.liveInk ? .on : .off
        liveInkItem.badge = NSMenuItemBadge(string: "Hold \(settings.data.liveInkChordChoice.glyphs)")
        menu.addItem(liveInkItem)
        // The same two switches, under the same heading, as the Settings window's Screenshots tab.
        menu.addItem(.sectionHeader(title: "After a Screenshot"))
        let copyItem = NSMenuItem(title: "Copy to Clipboard", action: #selector(toggleCopyOnCapture), keyEquivalent: "")
        copyItem.state = settings.data.copyOnCapture ? .on : .off
        menu.addItem(copyItem)
        let captureItem = NSMenuItem(title: "Instant Draw", action: #selector(toggleAnnotateOnCapture), keyEquivalent: "")
        captureItem.state = settings.data.annotateOnCapture ? .on : .off
        menu.addItem(captureItem)
        menu.addItem(.separator())

        let blocked = blockers()
        for item in blocked {
            item.image = NSImage(systemSymbolName: "exclamationmark.triangle.fill", accessibilityDescription: "Needs permission")?
                .withSymbolConfiguration(.init(paletteColors: [.white, .systemYellow]))
            menu.addItem(item)
        }
        if !blocked.isEmpty { menu.addItem(.separator()) }

        let waitingUpdate = updater?.waiting
        if let waitingUpdate {
            let updateItem = NSMenuItem(title: "Update Available…", action: #selector(checkForUpdates), keyEquivalent: "")
            updateItem.badge = NSMenuItemBadge(string: waitingUpdate)
            menu.addItem(updateItem)
            menu.addItem(.separator())
        }

        let recentItem = NSMenuItem(title: "Show Recent Screenshots", action: #selector(toggleRecent), keyEquivalent: "")
        // A status item's menu is not the main menu, so this key equivalent is live only while the
        // menu is open; the global press is the Carbon hotkey's.
        if let equivalent = shortcut?.menuKeyEquivalent {
            recentItem.keyEquivalent = equivalent.key
            recentItem.keyEquivalentModifierMask = equivalent.modifiers
        } else if let shortcut {
            recentItem.badge = NSMenuItemBadge(string: shortcut.glyphs)
        }
        menu.addItem(recentItem)
        let drawItem = NSMenuItem(title: "Draw on Newest Screenshot", action: #selector(annotateLast), keyEquivalent: "")
        if let shortcut { drawItem.badge = NSMenuItemBadge(string: shortcut.holdLabel) }
        menu.addItem(drawItem)
        let folderItem = NSMenuItem(title: "Open Screenshots Folder", action: #selector(openScreenshotsFolder), keyEquivalent: "")
        folderItem.toolTip = (settings.data.folderURL.path as NSString).abbreviatingWithTildeInPath
        menu.addItem(folderItem)
        menu.addItem(.separator())

        if settings.data.debug {
            menu.addItem(.sectionHeader(title: "Developer"))
            menu.addItem(withTitle: "Tweak UI…", action: #selector(openTweaks), keyEquivalent: "")
            menu.addItem(withTitle: "Open Log", action: #selector(openLog), keyEquivalent: "")
            menu.addItem(withTitle: "Reveal settings.json", action: #selector(revealSettings), keyEquivalent: "")
            menu.addItem(.separator())
        }

        if waitingUpdate == nil {
            menu.addItem(withTitle: "Check for Updates…", action: #selector(checkForUpdates), keyEquivalent: "")
        }
        if ProblemReport.issuesURL != nil {
            menu.addItem(withTitle: "Report a Problem…", action: #selector(reportProblem), keyEquivalent: "")
        }
        if menu.items.last?.isSeparatorItem == false { menu.addItem(.separator()) }

        menu.addItem(withTitle: "Quit Vignette", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        for item in menu.items where item.action != #selector(NSApplication.terminate(_:)) { item.target = self }
    }

    @objc private func openFilesAndFolders() {
        // macOS doesn't ask twice, so the answer is changed where it keeps it.
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_FilesAndFolders")!)
    }

    @objc private func saveCapturesAsFiles() {
        settings.saveCapturesAsFiles()
    }

    @objc private func requestAccessibility() {
        Accessibility.request()
    }

    @objc private func openScreenRecording() {
        ScreenRecording.openSystemSettings()
    }

    @objc private func checkForUpdates() {
        updater?.checkForUpdates(nil)
    }

    @objc private func reportProblem() {
        ProblemReport.open()
    }

    private func startUpdater() {
        let feed = Launch.isTest ? ProcessInfo.processInfo.environment["VIGNETTE_FEED"].flatMap { $0.isEmpty ? nil : $0 } : nil
        if Launch.isTest, feed == nil {
            Log.write("[update] test launch: no updater; VIGNETTE_FEED names a feed to test one")
            return
        }
        let updater = Updater(feed: feed)
        updater.hasStatusItem = { [weak self] in self?.statusItem != nil }
        updater.onChange = { [weak self] in self?.showUpdateDot() }
        self.updater = updater
    }

    @objc private func openSettings() {
        settingsWindow.show()
    }

    @objc func restoreAppleDefaults() {
        guard let restored = settings.restoreAppleDefaults() else {
            Commands.error("restore-apple-defaults", .noAppleOriginal, "nothing was recorded, so nothing to restore")
            return
        }
        Commands.ok("restore-apple-defaults", restored.joined(separator: " "))
    }

    @objc private func openTweaks() {
        debugPanel.toggle()
    }

    @objc private func openScreenshotsFolder() {
        NSWorkspace.shared.open(settings.data.folderURL)
    }

    @objc private func revealSettings() {
        NSWorkspace.shared.activateFileViewerSelecting([Settings.fileURL])
    }

    @objc private func toggleCopyOnCapture() {
        settings.update { $0.copyOnCapture.toggle() }
        Log.write("[settings] copyOnCapture=\(settings.data.copyOnCapture)")
    }

    @objc private func toggleLiveInk() {
        settings.update { $0.liveInk.toggle() }
        if settings.data.liveInk { ScreenRecording.request() }
        Log.write("[settings] liveInk=\(settings.data.liveInk)")
    }

    @objc private func toggleAnnotateOnCapture() {
        settings.update { $0.annotateOnCapture.toggle() }
        Log.write("[settings] annotateOnCapture=\(settings.data.annotateOnCapture)")
    }

    @objc private func openLast() {
        guard let key = newestShot() else {
            Commands.error("last", .missingFile, "no screenshot in \(watchFolder.path)"); return
        }
        thumbnail.show(Screenshot(key: key))
        Commands.ok("last", key.name)
    }

    // MARK: Screenshot requests: Send, replies, and which files a reply owns. See ScreenshotRequests.

    /// Wires the coordinator and reads what is already on disk. Runs before the watcher starts and
    /// before anything warms the stack: until the reply records are loaded nothing knows which
    /// managed files are unfinished, and an unfinished one must never read as an ordinary capture.
    /// `clearingUnsent` is false when this launch replaces a copy that may still be handing its waiting
    /// sends over as it quits (`ScreenshotRequests.load`).
    private func startRequests(clearingUnsent: Bool) {
        requests.callbacks = ScreenshotRequests.Callbacks(
            installDrawing: { [weak self] shot, marks, agent, answersLiveInk, done in
                guard let self else { return done(Drawings.Failure(code: .writeFailed, description: "the app is gone")) }
                Task {
                    do {
                        let ui = self.settings.data.ui
                        try self.drawings.installReply(marks, from: agent, at: shot.key, style: ui.textStyle, newScreen: Self.newDrawingScreen,
                                                       rule: answersLiveInk ? ui.liveInkMarkScaleRule : ui.markScaleRule)
                        done(nil)
                    } catch let failure as Drawings.Failure {
                        done(failure)
                    } catch {
                        done(Drawings.Failure(code: .writeFailed, description: "\(error)"))
                    }
                }
            },
            cardCanvas: { [weak self] url, agent in
                guard let self, let pixels = PixelSize(imageAt: url) else { return nil }
                let ui = settings.data.ui
                let pointScale = ui.liveInkMarkScaleRule.scale(for: pixels, on: Self.newDrawingScreen).point
                return LiveAnswer.Canvas(pixels: pixels, pointScale: pointScale, style: ui.textStyle, smallestText: ui.smallestNoteText,
                                         agent: agent)
            },
            present: { [weak self] shot in self?.folderWrites.published(shot) },
            presentLive: { [weak self] record, answer, done in
                guard let self else { return done(nil) }
                noteCards.answer(record, answer, done: done)
            },
            watchFolder: { [weak self] in self?.watchFolder ?? FileManager.default.temporaryDirectory },
            delivered: { [weak self] record, outcome in
                guard let self else { return }
                let state: SendNotice.State
                switch outcome {
                case .accepted: state = .sent
                case .queued: state = .queued
                case .uncertain: state = .uncertain
                case .notSubmitted, .destinationChanged: state = .failed
                }
                let noteCard = noteCards.delivered(record.id, failed: state == .failed)
                guard let shot = sentShots.removeValue(forKey: record.id) ?? noteCard else { return }
                thumbnail.delivered(shot, request: record.id, state, reason: outcome.reason)
            },
            replyFailed: { [weak self] record, reason in
                guard let self else { return }
                let shot = Screenshot(key: requests.sourceKey(of: record))
                guard FileManager.default.fileExists(atPath: shot.url.path) else { return }
                thumbnail.replyFailed(shot, request: record.id, client: record.address.client, reason: reason)
            },
            released: { [weak self] record in
                guard let self, let shot = noteCards.released(record.id) ?? sentShots[record.id] else { return }
                thumbnail.released(shot, request: record.id)
            },
            cancelled: { [weak self] record in
                guard let self else { return }
                if let shot = sentShots.removeValue(forKey: record.id) { thumbnail.cancelled(shot, request: record.id) }
                else { _ = noteCards.cancelled(record.id) }
            },
            storedDrawing: { [weak self] in self?.storedDrawing($0) })
        connectSendsToCards()
        requests.load(clearingUnsent: clearingUnsent)
    }

    private func present(_ shot: Screenshot, annotate: Bool, from origin: NSRect?) {
        guard annotate, shot.kind == .image else { return thumbnail.show(shot) }
        self.annotate([shot], from: origin)
    }

    @objc private func toggleRecent() { _ = pressRecent(by: .menu) }

    @discardableResult
    private func pressRecent(by request: StackRequest) -> ThumbnailController.StackToggle {
        let result = thumbnail.toggleRecent(by: request)
        switch result {
        case .shown(let count): Commands.ok("recent", "shown \(count) cards")
        case .dismissed: Commands.ok("recent", "dismissed")
        case .empty: Commands.error("recent", .missingFile, "no screenshots in \(watchFolder.path)")
        }
        return result
    }

    @objc private func openLog() {
        NSWorkspace.shared.open(Log.url)
    }

    /// Setup's Allow…, or the window closing: the watcher's first read raises macOS's prompt.
    private func askForFolder() {
        guard watcherWaitsForSetup else { return }
        watcherWaitsForSetup = false
        startWatching()
    }

    /// Where macOS's permission for the folder stands, as setup shows it.
    private var folderAccess: FolderAccess {
        guard let watcher else { return .ask }
        if watcher.isDenied { return .refused }
        return watcher.isReadable ? .granted : .waiting
    }

    private func startWatching() {
        watcherGeneration += 1
        let generation = watcherGeneration
        Log.write("[watcher] watching \(watchFolder.path)")
        watcher = ScreenshotWatcher(folder: watchFolder, onNew: { [weak self] key in
            guard let self, self.watcherGeneration == generation else { return }
            Log.write("[watcher] new \(key.name)")
            let shot = Screenshot(key: key), url = key.url
            if self.folderWrites.arrived(key) { return }
            // An agent's reply is shown once by its own import, when every byte and its drawing are
            // stored. A watcher report for one — the copy that made it, or a later rescan — is
            // never a capture, so it neither goes to the clipboard nor opens the editor.
            guard self.requests.isCapture(url) else { return }
            self.sessions.refreshKeptLists()   // so Send's list is current if this opens in the editor
            if self.settings.data.copyOnCapture {
                Clipboard.copyFiles([url])
                Log.write("[watcher] copied \(url.lastPathComponent)")
            }
            let origin = self.capturedRect(of: shot), annotate = self.settings.data.annotateOnCapture
            self.logClues(of: shot)
            self.present(shot, annotate: annotate, from: annotate ? origin : nil)
        }, onRemoved: { [weak self] keys, inventory in
            guard let self, self.watcherGeneration == generation else { return }
            self.folderWrites.removed(keys, in: inventory)
        }, onInventory: { [weak self] inventory in
            guard let self, self.watcherGeneration == generation else { return }
            self.folderWrites.listed(inventory)
        }, onRenamed: { [weak self] pairs, inventory in
            guard let self, self.watcherGeneration == generation else { return }
            self.folderWrites.renamed(pairs, in: inventory)
        })
        warmThumbnails()
        if wakeObserver == nil {
            // Both observers are registered with queue: .main, so the notification always arrives there.
            wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
                forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
            ) { [weak self] _ in MainActor.assumeIsolated { self?.watcher?.rescan(reason: "wake") } }
            screenObserver = NotificationCenter.default.addObserver(
                forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
            ) { [weak self] _ in MainActor.assumeIsolated { self?.thumbnail.screensChanged() } }
        }
    }

    /// Decodes thumbnails for the recent stack ahead of time so the hotkey shows it at once.
    private func warmThumbnails() {
        thumbnail.warm(recentShots(limit: settings.data.recentCount).recent.map(Screenshot.init(key:)))
    }
}

extension AppDelegate: NSMenuDelegate, NSMenuItemValidation {
    func menuNeedsUpdate(_ menu: NSMenu) { rebuildMenu(menu) }

    /// Showing and drawing act on a screenshot, and with an empty folder they did nothing and said
    /// so only in the log. Greyed out is what a Mac user already reads as nothing to act on.
    func validateMenuItem(_ item: NSMenuItem) -> Bool {
        switch item.action {
        case #selector(toggleRecent), #selector(annotateLast): return hasScreenshots
        case #selector(checkForUpdates): return updater?.canCheck ?? false
        default: return true
        }
    }
}
