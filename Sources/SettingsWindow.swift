import AppKit
import SwiftUI

/// A thin editor over settings.json. Every control writes straight to the file.
final class SettingsWindowController: NSObject, NSWindowDelegate {
    private var window: NSWindow?

    func show() {
        let win = window ?? makeWindow()
        win.center()
        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func makeWindow() -> NSWindow {
        let win = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 460, height: 600), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        win.title = "Shotnote Settings"
        let hosting = NSHostingView(rootView: SettingsView())
        win.contentView = hosting
        win.setContentSize(hosting.fittingSize)
        win.isReleasedWhenClosed = false
        win.delegate = self
        window = win
        return win
    }

    func windowWillClose(_ notification: Notification) {
        DispatchQueue.main.async { FocusReturn.shared.restore(reason: "settings closed") }
    }
}

struct SettingsView: View {
    @ObservedObject private var settings = Settings.shared
    @State private var hotkeyText = Settings.shared.data.recentHotkey

    private func binding<T>(_ path: WritableKeyPath<SettingsData, T>) -> Binding<T> {
        Binding(get: { settings.data[keyPath: path] }, set: { v in settings.update { $0[keyPath: path] = v } })
    }

    var body: some View {
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
                Stepper("Show \(settings.data.recentCount) recent screenshots", value: binding(\.recentCount), in: 1...20)
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
                        .foregroundStyle(HotKey.parse(hotkeyText) == nil ? .red : .primary)
                }
                Text("Modifiers cmd, shift, opt, ctrl and a key, joined with +. Press Return to apply.")
                    .font(.caption).foregroundStyle(.secondary)
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
        guard HotKey.parse(hotkeyText) != nil else { return }
        settings.update { $0.recentHotkey = hotkeyText }
    }
}
