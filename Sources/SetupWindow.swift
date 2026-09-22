import AppKit
import Combine
import SwiftUI

extension Notification.Name {
    /// Posted when the recent-stack shortcut fires. The setup window is the only listener: it is
    /// how "try it" learns that the user's own hand worked, rather than that the stack appeared,
    /// which it does not on a Mac with no screenshots yet.
    static let hotKeyFired = Notification.Name("\(Identity.bundleID).hotkey.fired")
}

/// The window a first launch opens: one screen whose job is the shortcut.
///
/// It exists because of what the permission costs. The double tap needs Vignette trusted for
/// Accessibility, and macOS gives an app few chances at that dialog. Raising it during launch,
/// before the user has seen the app, spends the chance on a question nobody asked. Here the dialog
/// is the answer to a choice they just made, and the window then says when the grant landed and
/// invites them to press the keys once.
@MainActor
final class SetupWindowController: NSObject, NSWindowDelegate {
    private let settings = Settings.shared
    private var window: NSWindow?

    /// Whether a first launch should open this. Recorded as done when the window closes rather than
    /// when it opens, so a launch quit part way through asks again.
    var isUnasked: Bool { settings.data.setupChoice == .unasked }

    func show(hasScreenshots: @escaping () -> Bool) {
        if let win = window {
            win.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        // The content decides the height: the recorder, the status line and its button come and go,
        // and a fixed frame clips whichever row is last. `preferredContentSize` has AppKit follow
        // the SwiftUI layout, including the parts that change from the view's own state, which a
        // one-shot measurement at show time cannot see.
        let host = NSHostingController(rootView: SetupView(hasScreenshots: hasScreenshots,
                                                          done: { [weak self] in self?.close() }))
        host.sizingOptions = [.preferredContentSize]
        let win = NSWindow(contentViewController: host)
        win.styleMask = [.titled, .closable]
        win.title = "Welcome to \(Identity.name)"
        win.isReleasedWhenClosed = false
        win.delegate = self
        // Lay the content out before centring. `preferredContentSize` reaches the window a beat
        // after it is made, so centring first centres the placeholder size and leaves the grown
        // window off to one side.
        host.view.layoutSubtreeIfNeeded()
        win.setContentSize(host.view.fittingSize)
        win.center()
        window = win
        Log.write("[setup] shown")
        win.makeKeyAndOrderFront(nil)
        // A window asking for a permission has to be the frontmost thing, or the dialog it raises
        // arrives behind whatever the user was doing.
        NSApp.activate(ignoringOtherApps: true)
    }

    private func close() { window?.performClose(nil) }

    func windowWillClose(_ notification: Notification) {
        settings.update { $0.setup = SetupState.done.rawValue }
        Log.write("[setup] done hotkey=\(settings.data.recentHotkey) trusted=\(ModifierTap.trusted(prompt: false))")
        DispatchQueue.main.async { FocusReturn.shared.restore(reason: "setup closed") }
    }
}

@MainActor
struct SetupView: View {
    static let width: CGFloat = 460

    /// Asked again on every poll rather than read once: a folder filled while the window is open
    /// is the case the window is asking the user to create.
    let hasScreenshots: () -> Bool
    let done: () -> Void

    @ObservedObject private var settings = Settings.shared
    @State private var trusted = ModifierTap.trusted(prompt: false)
    @State private var fired = false
    @State private var hasShots = true
    /// AXIsProcessTrusted does not announce a change, so the only way to know the user came back
    /// from System Settings having flipped the switch is to look.
    private let poll = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Cmd+Shift+3, 4 and 5 still take the screenshot. Vignette handles what comes after.")
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 20).padding(.top, 20).padding(.bottom, 4)
            Form {
                Section {
                    ShortcutSetting()
                    status
                }
                Section {
                    Toggle("Launch at login", isOn: binding(\.launchAtLogin))
                    LabeledContent("Screenshots") {
                        Text(settings.data.screenshotsFolder).lineLimit(1).truncationMode(.middle)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .formStyle(.grouped)
            HStack {
                Spacer()
                Button("Done", action: done).keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 20).padding(.bottom, 20)
        }
        .frame(width: SetupView.width)
        .onAppear { hasShots = hasScreenshots() }
        .onReceive(poll) { _ in
            trusted = ModifierTap.trusted(prompt: false)
            hasShots = hasScreenshots()
        }
        .onReceive(NotificationCenter.default.publisher(for: .hotKeyFired)) { _ in fired = true }
        .onChange(of: settings.data.usesDoubleTap) { fired = false }
    }

    /// One line that changes in place, rather than three that appear and disappear: the user is
    /// watching this spot for the answer.
    @ViewBuilder private var status: some View {
        if !settings.data.usesDoubleTap {
            label("A key combination needs no permission.", symbol: "checkmark.circle.fill", tint: .green)
        } else if trusted, !hasShots {
            // Ahead of `fired`: with nothing in the folder the shortcut opens nothing, so saying
            // it worked would be saying so about an empty corner.
            label("Take a screenshot with Cmd+Shift+4, then tap Right Shift twice.",
                  symbol: "camera", tint: .accentColor)
        } else if fired {
            label("That works. You're set.", symbol: "checkmark.circle.fill", tint: .green)
        } else if trusted {
            label("Try it: tap Right Shift twice.", symbol: "hand.tap", tint: .accentColor)
        } else {
            label("Vignette needs Accessibility permission to see a double tap.",
                  symbol: "exclamationmark.triangle.fill", tint: .orange)
            Button("Allow in System Settings") {
                // Raising the dialog and opening the pane: the dialog is the shortest route when
                // macOS still offers it, and the pane is the only one left once it has stopped.
                _ = ModifierTap.trusted(prompt: true)
                Accessibility.openSystemSettings()
            }
        }
    }

    private func label(_ text: String, symbol: String, tint: Color) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: symbol).foregroundStyle(tint)
            Text(text).fixedSize(horizontal: false, vertical: true)
        }
        .font(.callout)
    }

    private func binding<T>(_ path: WritableKeyPath<SettingsData, T>) -> Binding<T> {
        Binding(get: { settings.data[keyPath: path] }, set: { v in settings.update { $0[keyPath: path] = v } })
    }
}
