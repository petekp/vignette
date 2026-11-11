import Foundation

/// Every setting the tweak panel and the labs show, each defined once: its control, the range its
/// slider covers, and for a number the range outside which a value breaks the app, which
/// `UITweaks.bounds` is made from (docs/tweak-panel-redesign-2026-10-12.md).
struct TweakSpec: @unchecked Sendable, Identifiable {
    enum Control {
        /// A number on a slider over `range`, rounded to `step`. A typed value may go past the slider
        /// but not past `safe`.
        case number(WritableKeyPath<UITweaks, Double>, range: ClosedRange<Double>, step: Double, unit: String, safe: ClosedRange<Double>)
        case integer(WritableKeyPath<UITweaks, Int>, range: ClosedRange<Int>)
        /// `#rrggbb`.
        case colour(WritableKeyPath<UITweaks, String>)
        /// A system design's name or an installed family's.
        case font(WritableKeyPath<UITweaks, String>)
        case choice(WritableKeyPath<UITweaks, String>, [String])
        case toggle(WritableKeyPath<UITweaks, Bool>)
    }

    /// The setting's name in settings.json.
    let key: String
    let label: String
    let control: Control
    /// Whether the setting does anything with the others as they are; a row that does not is hidden.
    let applies: @Sendable (UITweaks) -> Bool

    var id: String { key }

    static func number(_ key: String, _ label: String, _ path: WritableKeyPath<UITweaks, Double>, _ range: ClosedRange<Double>,
                       step: Double = 1, unit: String = "", safe: ClosedRange<Double>,
                       when applies: @escaping @Sendable (UITweaks) -> Bool = { _ in true }) -> TweakSpec {
        TweakSpec(key: key, label: label, control: .number(path, range: range, step: step, unit: unit, safe: safe), applies: applies)
    }

    static func integer(_ key: String, _ label: String, _ path: WritableKeyPath<UITweaks, Int>, _ range: ClosedRange<Int>) -> TweakSpec {
        TweakSpec(key: key, label: label, control: .integer(path, range: range), applies: { _ in true })
    }

    static func colour(_ key: String, _ label: String, _ path: WritableKeyPath<UITweaks, String>) -> TweakSpec {
        TweakSpec(key: key, label: label, control: .colour(path), applies: { _ in true })
    }

    static func font(_ key: String, _ label: String, _ path: WritableKeyPath<UITweaks, String>) -> TweakSpec {
        TweakSpec(key: key, label: label, control: .font(path), applies: { _ in true })
    }

    static func choice(_ key: String, _ label: String, _ path: WritableKeyPath<UITweaks, String>, _ options: [String]) -> TweakSpec {
        TweakSpec(key: key, label: label, control: .choice(path, options), applies: { _ in true })
    }

    static func toggle(_ key: String, _ label: String, _ path: WritableKeyPath<UITweaks, Bool>) -> TweakSpec {
        TweakSpec(key: key, label: label, control: .toggle(path), applies: { _ in true })
    }

    /// Whether `ui` holds this setting's default, counting floating-point noise as equal.
    func isDefault(in ui: UITweaks) -> Bool {
        let defaults = UITweaks()
        switch control {
        case .number(let path, _, _, _, _): return UITweaks.same(ui[keyPath: path], defaults[keyPath: path])
        case .integer(let path, _): return ui[keyPath: path] == defaults[keyPath: path]
        case .colour(let path), .font(let path), .choice(let path, _): return ui[keyPath: path] == defaults[keyPath: path]
        case .toggle(let path): return ui[keyPath: path] == defaults[keyPath: path]
        }
    }

    /// `ui` with this setting put back to its default.
    func reset(_ ui: inout UITweaks) {
        let defaults = UITweaks()
        switch control {
        case .number(let path, _, _, _, _): ui[keyPath: path] = defaults[keyPath: path]
        case .integer(let path, _): ui[keyPath: path] = defaults[keyPath: path]
        case .colour(let path), .font(let path), .choice(let path, _): ui[keyPath: path] = defaults[keyPath: path]
        case .toggle(let path): ui[keyPath: path] = defaults[keyPath: path]
        }
    }
}

/// Rows under one heading, with a caption under them that may follow the settings.
struct TweakGroup: @unchecked Sendable {
    let title: String?
    let tweaks: [TweakSpec]
    let caption: (@Sendable (UITweaks) -> String)?

    init(_ title: String?, _ tweaks: [TweakSpec], caption: (@Sendable (UITweaks) -> String)? = nil) {
        self.title = title; self.tweaks = tweaks; self.caption = caption
    }
}

/// One entry of the panel's sidebar. A section a lab also shows names the lab, and one that changes
/// how live ink looks offers its samples (`InkSamples`).
struct TweakSection: @unchecked Sendable, Identifiable {
    enum Lab { case intro, check, setup }

    let name: String
    let lab: Lab?
    let inkSamples: Bool
    let groups: [TweakGroup]

    var id: String { name }
    var tweaks: [TweakSpec] { groups.flatMap(\.tweaks) }

    init(_ name: String, lab: Lab? = nil, inkSamples: Bool = false, _ groups: [TweakGroup]) {
        self.name = name; self.lab = lab; self.inkSamples = inkSamples; self.groups = groups
    }
}

enum TweakCatalog {
    static func section(_ name: String) -> TweakSection? { sections.first { $0.name == name } }

    static let sections: [TweakSection] = stackSections + annotatorSections + editorSections + liveInkSections + labSections
}
