import AppKit
import SwiftUI

/// A floating panel of the settings in `settings.ui`, from `TweakCatalog`: a sidebar of sections, a
/// search across all of them, and the values that differ from their defaults. Every change applies to
/// whatever is on screen at once and lands in settings.json. Previews summon each UI state to tweak
/// against (docs/tweak-panel-redesign-2026-10-12.md).
@MainActor
final class DebugPanelController: NSObject, NSWindowDelegate {
    struct Previews {
        var thumbnail: () -> Void
        var stack: () -> Void
        var annotator: () -> Void
        var intro: () -> Void
        var pointer: () -> Void
        var check: () -> Void
    }

    private var panel: NSPanel?
    private let previews: Previews
    /// Kept with the controller, so the panel opens again where it was left.
    private let place = TweakPlace()

    init(previews: Previews) {
        self.previews = previews
    }

    func toggle() {
        if let p = panel, p.isVisible { p.orderOut(nil); return }
        show()
    }

    func show() {
        let p = panel ?? make()
        p.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func make() -> NSPanel {
        let p = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 720, height: 640),
                        styleMask: [.titled, .closable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
        p.title = "Vignette Tweaks"
        p.isFloatingPanel = true
        p.level = .floating
        p.hidesOnDeactivate = false
        p.isReleasedWhenClosed = false
        p.delegate = self
        p.contentView = NSHostingView(rootView: DebugPanelView(previews: previews, place: place))
        // Left side of the screen so it never sits under the stack or the backdrop.
        if let v = NSScreen.main?.visibleFrame {
            p.setFrameOrigin(NSPoint(x: v.minX + 40, y: v.midY - 320))
        }
        panel = p
        return p
    }

    func windowWillClose(_ notification: Notification) {
        DispatchQueue.main.async { FocusReturn.shared.restore(reason: "tweaks closed") }
    }
}

/// What the panel shows: a section, or the values that differ from their defaults, and the search.
@MainActor
final class TweakPlace: ObservableObject {
    enum Shown: Hashable {
        case changed
        case section(String)
    }

    @Published var shown: Shown? = .section(TweakCatalog.sections[0].name)
    @Published var search = ""
    /// The settings that differed from their defaults when Changed was picked. They stay listed while
    /// it shows, so a row brought back to its default does not vanish under the pointer.
    var listed: Set<String> = []
}

@MainActor
struct DebugPanelView: View {
    let previews: DebugPanelController.Previews
    @ObservedObject var place: TweakPlace
    @ObservedObject private var settings = Settings.shared
    @State private var confirmsReset = false

    var body: some View {
        let ui = settings.data.ui
        NavigationSplitView {
            List(selection: $place.shown) {
                Label("Changed", systemImage: "circle.fill")
                    .badge(TweakCatalog.sections.reduce(0) { $0 + changed(in: $1, ui) })
                    .tag(TweakPlace.Shown.changed)
                Section {
                    ForEach(TweakCatalog.sections) { section in
                        Text(section.name)
                            .badge(changed(in: section, ui))
                            .tag(TweakPlace.Shown.section(section.name))
                    }
                }
            }
            .searchable(text: $place.search, placement: .sidebar, prompt: "Search tweaks")
            .onChange(of: place.shown) { _, shown in
                place.listed = shown == .changed ? Set(TweakCatalog.sections.flatMap(\.tweaks).filter { !$0.isDefault(in: ui) }.map(\.key)) : []
            }
            .navigationSplitViewColumnWidth(min: 170, ideal: 190, max: 260)
            .safeAreaInset(edge: .bottom) {
                HStack {
                    Button("Reveal File") { NSWorkspace.shared.activateFileViewerSelecting([Settings.fileURL]) }
                        .help("Show settings.json in the Finder")
                    Spacer()
                    Button("Reset All…") { confirmsReset = true }
                }
                .controlSize(.small)
                .padding(10)
            }
        } detail: {
            VStack(spacing: 0) {
                // Which file the values write to: a test launch points at another file, and a change
                // made there never reaches the real one.
                if Settings.isOverridden {
                    Text("Test settings file: \(Settings.fileURL.path). Changes here do not reach your settings.json.")
                        .font(.caption).foregroundStyle(.black)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .background(Color.yellow)
                }
                detail(ui)
            }
            .navigationTitle(title)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button("Thumbnail", action: previews.thumbnail)
                        Button("Stack", action: previews.stack)
                        Button("Annotator", action: previews.annotator)
                        Divider()
                        Button("Menu Bar Intro Lab", action: previews.intro)
                        Button("Pointer Lab", action: previews.pointer)
                        Button("Check Lab", action: previews.check)
                    } label: {
                        Label("Preview", systemImage: "eye")
                    }
                    .help("Show a part of Vignette to tweak against")
                }
            }
            .confirmationDialog("Reset every tweak to its default?", isPresented: $confirmsReset) {
                Button("Reset Every Tweak", role: .destructive) { settings.update { $0.ui = UITweaks() } }
            }
        }
        .frame(minWidth: 620, minHeight: 420)
    }

    private var title: String {
        if !place.search.isEmpty { return "Search" }
        switch place.shown {
        case .changed: return "Changed"
        case .section(let name): return name
        case nil: return "Tweaks"
        }
    }

    @ViewBuilder private func detail(_ ui: UITweaks) -> some View {
        let query = place.search.trimmingCharacters(in: .whitespaces)
        if !query.isEmpty {
            let found = TweakCatalog.sections.compactMap { section -> (TweakSection, [TweakSpec])? in
                let hits = section.tweaks.filter { matches($0, in: section, query) && $0.applies(ui) }
                return hits.isEmpty ? nil : (section, hits)
            }
            listing(found, ui, empty: "No tweak matches “\(query)”.")
        } else if place.shown == .changed {
            let changed = TweakCatalog.sections.compactMap { section -> (TweakSection, [TweakSpec])? in
                let differ = section.tweaks.filter { !$0.isDefault(in: ui) || place.listed.contains($0.key) }
                return differ.isEmpty ? nil : (section, differ)
            }
            listing(changed, ui, empty: "Every tweak is at its default.")
        } else if case .section(let name) = place.shown, let section = TweakCatalog.section(name) {
            Form {
                // Always there, so the rows below keep their places, and a slider its drag, when a value
                // comes back to its default.
                Section {
                    HStack {
                        if let lab = section.lab {
                            Button("Open \(labName(lab))") { open(lab) }
                        }
                        Spacer()
                        Button("Reset \(section.name)") {
                            settings.update { data in section.tweaks.forEach { $0.reset(&data.ui) } }
                        }
                        .disabled(changed(in: section, ui) == 0)
                    }
                }
                TweakGroups(section: section, ui: ui)
            }
            .formStyle(.grouped)
        } else {
            Text("Pick a section.").foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    /// Rows from several sections, each under its section's name.
    @ViewBuilder private func listing(_ found: [(TweakSection, [TweakSpec])], _ ui: UITweaks, empty: String) -> some View {
        if found.isEmpty {
            Text(empty).foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            Form {
                ForEach(found, id: \.0.id) { section, tweaks in
                    Section(section.name) {
                        ForEach(tweaks) { TweakRow(spec: $0, ui: ui).equatable() }
                    }
                }
            }
            .formStyle(.grouped)
        }
    }

    private func matches(_ spec: TweakSpec, in section: TweakSection, _ query: String) -> Bool {
        [spec.label, spec.key, section.name].contains { $0.localizedCaseInsensitiveContains(query) }
    }

    private func changed(in section: TweakSection, _ ui: UITweaks) -> Int {
        section.tweaks.filter { !$0.isDefault(in: ui) }.count
    }

    private func labName(_ lab: TweakSection.Lab) -> String {
        switch lab {
        case .intro: "Menu Bar Intro Lab"
        case .pointer: "Pointer Lab"
        case .check: "Check Lab"
        }
    }

    private func open(_ lab: TweakSection.Lab) {
        switch lab {
        case .intro: previews.intro()
        case .pointer: previews.pointer()
        case .check: previews.check()
        }
    }
}

/// A section's groups as form sections, each with its caption under it. The labs show their sections
/// with it too.
@MainActor
struct TweakGroups: View {
    let section: TweakSection
    let ui: UITweaks

    var body: some View {
        ForEach(section.groups.indices, id: \.self) { index in
            let group = section.groups[index]
            Section {
                ForEach(group.tweaks.filter { $0.applies(ui) }) { TweakRow(spec: $0, ui: ui).equatable() }
            } header: {
                if let title = group.title { Text(title) }
            } footer: {
                if let caption = group.caption {
                    Text(caption(ui)).font(.caption).foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading).frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }
}

/// One setting: its label, its control, its value, which takes a typed number, and a dot when it
/// differs from its default, which puts the default back. Equal while its own value is, so a change
/// to another setting does not draw it again.
@MainActor
struct TweakRow: View, Equatable {
    let spec: TweakSpec
    let ui: UITweaks

    nonisolated static func == (a: TweakRow, b: TweakRow) -> Bool {
        a.spec.key == b.spec.key && a.spec.value(in: a.ui) == b.spec.value(in: b.ui)
    }

    var body: some View {
        HStack(spacing: 8) {
            Text(spec.label)
                .lineLimit(1)
                .frame(width: 150, alignment: .leading)
                .help(spec.key)
            control
            resetDot
        }
    }

    @ViewBuilder private var control: some View {
        switch spec.control {
        case .number(let path, let range, let step, let unit, let safe):
            NumberControl(value: ui[keyPath: path], range: range, step: step, unit: unit, safe: safe) { write(path, $0) }
        case .integer(let path, let range):
            NumberControl(value: Double(ui[keyPath: path]), range: Double(range.lowerBound)...Double(range.upperBound), step: 1, unit: "",
                          safe: Double(range.lowerBound)...Double(range.upperBound)) { v in write(path, Int(v.rounded())) }
        case .colour(let path):
            let hex = ui[keyPath: path]
            ColorPicker("", selection: Binding(get: { (SRGB(hex: hex) ?? SRGB(hex: UITweaks()[keyPath: path])!).cgColor },
                                               set: { color in if let picked = SRGB(color)?.hex { write(path, picked) } }),
                        supportsOpacity: false)
                .labelsHidden()
            Spacer()
            Text(hex).monospacedDigit().font(.caption).foregroundStyle(.secondary)
        case .font(let path):
            FontField(value: ui[keyPath: path]) { write(path, $0) }
        case .choice(let path, let options):
            Picker("", selection: Binding(get: { ui[keyPath: path] }, set: { write(path, $0) })) {
                ForEach(options, id: \.self) { Text($0).tag($0) }
            }
            .labelsHidden()
        case .style(let path, let names, _):
            Picker("", selection: Binding(get: { Int(ui[keyPath: path].rounded()) }, set: { write(path, Double($0)) })) {
                ForEach(names.indices, id: \.self) { Text(names[$0]).tag($0) }
            }
            .labelsHidden()
        }
    }

    @ViewBuilder private var resetDot: some View {
        if spec.isDefault(in: ui) {
            Color.clear.frame(width: 14, height: 14)
        } else {
            Button {
                Settings.shared.update { spec.reset(&$0.ui) }
            } label: {
                Circle().fill(Color.accentColor).frame(width: 7, height: 7).frame(width: 14, height: 14).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Changed. Click to reset to \(spec.defaultText).")
        }
    }

    private func write<T>(_ path: WritableKeyPath<UITweaks, T>, _ value: T) {
        Settings.shared.update { $0.ui[keyPath: path] = value }
    }
}

/// A slider with no tick marks and the value beside it, which takes a typed number. The slider covers
/// `range` and rounds to `step`; a typed value may go past the slider, but not past `safe`.
private struct NumberControl: View {
    let value: Double
    let range: ClosedRange<Double>
    let step: Double
    let unit: String
    let safe: ClosedRange<Double>
    let set: (Double) -> Void
    @State private var typed: String?
    @FocusState private var typing: Bool

    var body: some View {
        Slider(value: Binding(get: { min(max(value, range.lowerBound), range.upperBound) },
                              set: { set(((($0 - range.lowerBound) / step).rounded() * step + range.lowerBound)) }),
               in: range)
        TextField("", text: Binding(get: { typed ?? TweakSpec.format(value, step: step) }, set: { typed = $0 }))
            .multilineTextAlignment(.trailing)
            .monospacedDigit()
            .font(.callout)
            .textFieldStyle(.plain)
            .frame(width: 56)
            .focused($typing)
            .onSubmit(commit)
            .onChange(of: typing) { _, now in if !now { commit() } }
        Text(unit).font(.caption).foregroundStyle(.secondary).frame(width: 30, alignment: .leading)
    }

    private func commit() {
        defer { typed = nil }
        guard let typed, let number = Double(typed.trimmingCharacters(in: .whitespaces)), number.isFinite else { return }
        set(min(max(number, safe.lowerBound), safe.upperBound))
    }
}

/// A font's name. One that is not installed is not saved.
private struct FontField: View {
    let value: String
    let set: (String) -> Void
    @State private var typed: String?

    var body: some View {
        TextField("", text: Binding(get: { typed ?? value }, set: { typed = $0 }))
            .onSubmit {
                if let typed, TextStyle.isInstalled(typed) { set(typed) }
                typed = nil
            }
    }
}

extension TweakSpec {
    /// The setting's value in `ui`, to compare.
    func value(in ui: UITweaks) -> AnyHashable {
        switch control {
        case .number(let path, _, _, _, _), .style(let path, _, _): ui[keyPath: path]
        case .integer(let path, _): ui[keyPath: path]
        case .colour(let path), .font(let path), .choice(let path, _): ui[keyPath: path]
        }
    }

    /// The default, as the row shows a value.
    var defaultText: String {
        let defaults = UITweaks()
        switch control {
        case .number(let path, _, let step, let unit, _): return Self.format(defaults[keyPath: path], step: step) + (unit.isEmpty ? "" : " \(unit)")
        case .style(let path, let names, _): return names[min(max(Int(defaults[keyPath: path].rounded()), 0), names.count - 1)]
        case .integer(let path, _): return "\(defaults[keyPath: path])"
        case .colour(let path), .font(let path), .choice(let path, _): return defaults[keyPath: path]
        }
    }

    /// `value` with as many decimals as `step` has.
    static func format(_ value: Double, step: Double) -> String {
        let decimals = step >= 1 ? 0 : step >= 0.1 ? 1 : step >= 0.01 ? 2 : 3
        return String(format: "%.\(decimals)f", value)
    }
}
