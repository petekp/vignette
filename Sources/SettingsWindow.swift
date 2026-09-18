import AppKit
import SwiftUI

/// A thin editor over settings.json. Every control writes straight to the file.
@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    private let focus = SettingsFocus()

    /// `section` is a section id to bring into view, for a window opened to ask something.
    func show(scrollTo section: String? = nil) {
        let win = window ?? makeWindow()
        win.center()
        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        focus.section = section
    }

    private func makeWindow() -> NSWindow {
        let win = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 460, height: 600), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        win.title = "Shotnote Settings"
        let hosting = NSHostingView(rootView: SettingsView(focus: focus))
        win.contentView = hosting
        // The form is taller than a laptop screen, and the window has no resize control, so the
        // last sections would hang off the bottom where nothing can reach them. Capped, the form
        // scrolls inside the window instead.
        let room = (NSScreen.main?.visibleFrame.height ?? .greatestFiniteMagnitude) - SettingsView.screenRoom
        let fitting = hosting.fittingSize
        win.setContentSize(NSSize(width: fitting.width, height: min(fitting.height, room)))
        win.isReleasedWhenClosed = false
        win.delegate = self
        window = win
        return win
    }

    func windowWillClose(_ notification: Notification) {
        DispatchQueue.main.async { FocusReturn.shared.restore(reason: "settings closed") }
    }
}

/// Which section the window was opened to show. The offer sets it; the view clears it once it has
/// scrolled, so reopening the window by hand starts at the top again.
@MainActor
final class SettingsFocus: ObservableObject {
    @Published var section: String?
}

@MainActor
struct SettingsView: View {
    /// Title bar plus a margin: how much of the screen's visible height the form may not use.
    static let screenRoom: CGFloat = 60
    /// What `show(scrollTo:)` names to open the window on the skill toggle.
    static let agentsSection = "agents"


    @ObservedObject var focus: SettingsFocus
    @ObservedObject private var settings = Settings.shared
    @State private var hotkeyText = Settings.shared.data.recentHotkey

    private func binding<T>(_ path: WritableKeyPath<SettingsData, T>) -> Binding<T> {
        Binding(get: { settings.data[keyPath: path] }, set: { v in settings.update { $0[keyPath: path] = v } })
    }

    /// The skill toggle. Off is an answer, so the setting never goes back to `unasked` from here.
    private var agentSkill: Binding<Bool> {
        Binding(get: { settings.data.agentSkillChoice == .on },
                set: { on in settings.update { $0.agentSkill = (on ? AgentSkill.on : AgentSkill.off).rawValue } })
    }

    var body: some View {
        ScrollViewReader { proxy in
            form
                .onAppear { scroll(proxy) }
                .onChange(of: focus.section) { _, _ in scroll(proxy) }
        }
    }

    /// Brings the section the window was opened for into view. Not animated: it is where the
    /// window starts, not a movement.
    private func scroll(_ proxy: ScrollViewProxy) {
        guard let section = focus.section else { return }
        proxy.scrollTo(section, anchor: .top)
        focus.section = nil
    }

    private var form: some View {
        Form {
            Section("Screenshots") {
                LabeledContent("Folder") {
                    HStack {
                        Text(settings.data.screenshotsFolder).lineLimit(1).truncationMode(.middle)
                        Button("Choose…", action: chooseFolder)
                    }
                }
                Toggle("Tell macOS to save screenshots here", isOn: binding(\.syncAppleSaveLocation))
                Toggle("Show Apple's floating thumbnail", isOn: binding(\.appleThumbnail))
                Text("Off means the file lands immediately and Shotnote's thumbnail is the only one.")
                    .font(.caption).foregroundStyle(.secondary)
                Toggle("Window capture shadow", isOn: binding(\.windowShadow))
                Picker("Format", selection: binding(\.format)) {
                    Text("PNG").tag("png")
                    Text("JPG").tag("jpg")
                }
            }
            Section("Recent stack") {
                Stepper("Keep \(settings.data.recentCount) recent screenshots in the stack", value: binding(\.recentCount), in: 1...100)
                LabeledContent("Thumbnail stays for") {
                    HStack {
                        Slider(value: binding(\.ui.thumbnailSeconds), in: 2...15, step: 1)
                        Text("\(Int(settings.data.ui.thumbnailSeconds))s").monospacedDigit().frame(width: 30)
                    }
                }
                LabeledContent("Hotkey") {
                    TextField("", text: $hotkeyText, prompt: Text("cmd+shift+6"))
                        .labelsHidden()
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 160)
                        .onSubmit(commitHotkey)
                        .foregroundStyle(HotKeySpec.parse(hotkeyText) == nil ? .red : .primary)
                }
                Text("Modifiers cmd, shift, opt, ctrl and a key, joined with +, or double-rshift for a double tap of right Shift (asks for Accessibility permission). Press Return to apply. Hold the key, or the second tap, to draw on the newest screenshot.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("New captures") {
                Toggle("Copy to the clipboard", isOn: binding(\.copyOnCapture))
                Text("Every new screenshot is on the clipboard as soon as it lands: the image, plus its file for apps that take one.")
                    .font(.caption).foregroundStyle(.secondary)
                Toggle("Draw on new captures", isOn: binding(\.annotateOnCapture))
                Text("Every new screenshot opens in the annotator right away, instead of showing a thumbnail.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Drawing") {
                Toggle("Quick draw", isOn: binding(\.quickAnnotate))
                Text("Done copies the image you drew on and closes everything, instead of returning to the stack.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Agents") {
                Toggle("Install the Shotnote skill", isOn: agentSkill)
                    .id(SettingsView.agentsSection)
                Text("Copies a skill into ~/.claude/skills and ~/.codex/skills, so Claude Code and Codex know how to show you an image and read back what you drew on it. Off removes the copies Shotnote made; a skill you put there yourself is left alone.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Startup") {
                Toggle("Launch at login", isOn: binding(\.launchAtLogin))
                Text("Adds Shotnote to System Settings > General > Login Items.").font(.caption).foregroundStyle(.secondary)
            }
            Section("Advanced") {
                Toggle("Hide menu bar icon", isOn: binding(\.hideMenuBarIcon))
                Text("Reopen settings with: open shotnote://settings").font(.caption).foregroundStyle(.secondary)
                HStack {
                    Button("Reveal settings.json") { NSWorkspace.shared.activateFileViewerSelecting([Settings.fileURL]) }
                    Button("Open Log") { NSWorkspace.shared.open(Log.url) }
                    Button("Debug Panel…") { NSWorkspace.shared.open(URL(string: "shotnote://tweaks")!) }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 460)
        .onChange(of: settings.data.recentHotkey) { _, new in hotkeyText = new }
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

    private func commitHotkey() {
        guard HotKeySpec.parse(hotkeyText) != nil else { return }
        settings.update { $0.recentHotkey = hotkeyText }
    }
}
