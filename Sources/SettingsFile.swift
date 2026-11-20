import AppKit

extension Settings {
    /// What loading the file produced, before any of it reaches the app.
    struct Bootstrap {
        var data: SettingsData
        var log: [String] = []
        var notice: Notice?
        var readOnly = false
        var readOnlyReason = ""
        var written: Data?
    }

    /// Reads, migrates, validates, and repairs the file at `url`. A missing file is created from
    /// Apple's current values. An invalid file is set aside as `<name>.invalid`, never overwritten,
    /// and replaced by the same first-run defaults. A file from a newer version is used read-only.
    static func bootstrap(at url: URL) -> Bootstrap {
        switch load(url) {
        case .loaded(var loaded):
            var boot = Bootstrap(data: loaded.data, log: loaded.log)
            if loaded.fileVersion > currentVersion {
                boot.readOnly = true
                boot.readOnlyReason = "the file is from a newer version"
                boot.log.append("warning file version \(loaded.fileVersion) is newer than this build's \(currentVersion); not writing to it")
                let validated = loaded.data.validated()
                boot.data = validated.data
                boot.log += validated.corrections.map { "warning clamped \($0)" }
                return boot
            }
            if loaded.data.appleOriginal == nil {
                loaded.data.appleOriginal = AppleOriginal.capture()
                boot.log.append("recorded Apple's screencapture values as appleOriginal at this launch")
            }
            // Fill in any settings the file lacks so each is visible to whoever edits it next. `ui`
            // is the exception: it holds only what differs from the defaults.
            if let full = try? encoder().encode(loaded.data), full != (try? Data(contentsOf: url)) {
                boot.written = write(full, to: url)
            }
            let validated = loaded.data.validated()
            boot.data = validated.data
            boot.log += validated.corrections.map { "warning clamped \($0)" }
            return boot
        case .missing:
            var d = SettingsData.fromSystem()
            d.appleOriginal = AppleOriginal.capture()
            // Installing Vignette is choosing what happens after a capture, so the one Apple
            // behavior it replaces goes off here. Apple's thumbnail withholds the file for about
            // 5.6 seconds (docs/replacing-apple-capture-2026-09-22.md), which makes copy on capture
            // paste what was on the clipboard before. `appleOriginal` above holds the way back.
            d.appleThumbnail = false
            // With Apple's thumbnail off, a restart that does not bring Vignette back leaves every
            // capture silent. The setup window shows this switch, and closing it registers the item.
            d.launchAtLogin = true
            var boot = Bootstrap(data: d)
            do {
                let raw = try encoder().encode(d)
                try writeOrThrow(raw, to: url)
                boot.written = raw
                boot.log.append("created \(url.path)")
            } catch {
                // A `~/.config` that belongs to root is common on developer Macs. Without this, every
                // launch would find no file and start over as a first launch.
                let folder = (url.deletingLastPathComponent().path as NSString).abbreviatingWithTildeInPath
                boot.readOnly = true
                boot.readOnlyReason = "\(folder) cannot be written"
                boot.log.append("error cannot create \(url.path): \(error.localizedDescription); running on defaults without saving")
                boot.notice = Notice(title: "Settings can't be saved",
                                     detail: "Vignette can't write to \(folder). Changes last until it quits.")
            }
            return boot
        case .invalid(let reason):
            let aside = url.appendingPathExtension("invalid")
            try? FileManager.default.removeItem(at: aside)
            let moved = (try? FileManager.default.moveItem(at: url, to: aside)) != nil
            var d = SettingsData.fromSystem()
            d.appleOriginal = AppleOriginal.capture()
            var boot = Bootstrap(data: d)
            boot.log.append("error settings-invalid \(url.path): \(reason)")
            if moved {
                boot.log.append("moved the invalid file to \(aside.path) and replaced it with defaults")
                boot.written = (try? encoder().encode(d)).flatMap { write($0, to: url) }
                boot.notice = Notice(title: "settings.json could not be read",
                                     detail: "Vignette is using the default settings. Your file was kept as settings.json.invalid.")
            } else {
                boot.log.append("could not move the invalid file aside; running on defaults without writing")
                boot.readOnly = true
                boot.readOnlyReason = "the invalid file could not be moved aside"
                boot.notice = Notice(title: "settings.json could not be read",
                                     detail: "Vignette is using the default settings and will not save changes until the file is fixed.")
            }
            return boot
        }
    }

    enum Load {
        case missing
        case invalid(String)
        case loaded(Loaded)
    }

    struct Loaded {
        var data: SettingsData
        var fileVersion: Int
        var log: [String] = []
    }

    /// Reads the file over the defaults, so missing keys (including whole sections) keep their
    /// defaults. Distinguishes a missing file from one that does not parse.
    static func load(_ url: URL) -> Load {
        guard let raw = try? Data(contentsOf: url) else { return .missing }
        return parse(raw)
    }

    /// Reads the file's bytes over the defaults, as `load` does once it has them. Never answers `.missing`.
    nonisolated static func parse(_ raw: Data) -> Load {
        do {
            guard let fromFile = try JSONSerialization.jsonObject(with: raw) as? [String: Any] else {
                return .invalid("top level is not an object")
            }
            if let version = fromFile["version"], !(version is NSNumber) { return .invalid("version is not a number") }
            let migrated = migrate(fromFile)
            let defaults = try JSONSerialization.jsonObject(with: JSONEncoder().encode(SettingsData())) as! [String: Any]
            let merged = try JSONSerialization.data(withJSONObject: deepMerge(defaults, migrated.json))
            var loaded = Loaded(data: try JSONDecoder().decode(SettingsData.self, from: merged), fileVersion: migrated.from)
            if migrated.from < currentVersion { loaded.log.append("migrated from version \(migrated.from) to \(currentVersion)") }
            return .loaded(loaded)
        } catch {
            return .invalid(String(describing: error).replacingOccurrences(of: "\n", with: " "))
        }
    }

    /// Brings a file's raw JSON up to `currentVersion`. Files with no `version` are version 0.
    /// A file from a newer version is returned unchanged. A bump that changes a key rewrites it
    /// here, between the guard and the stamp, one step per version. Version 1 introduced the
    /// version field. Version 2 writes only the `ui` values that differ from the defaults.
    nonisolated static func migrate(_ raw: [String: Any]) -> (json: [String: Any], from: Int) {
        var json = raw
        // A file that already has live ink's switch in it is past the offer: the switch was set by the
        // person or by setup. Written before `liveInkOffered` existed, so the key is absent.
        if json["liveInk"] != nil, json["liveInkOffered"] == nil { json["liveInkOffered"] = true }
        let from = (json["version"] as? NSNumber)?.intValue ?? 0
        guard from < currentVersion else { return (json, from) }
        // 0.1.0 and 0.1.1 wrote every `ui` value, so a value there is a choice only where it
        // differs from their default. Kept, their old defaults would read as choices from now on.
        if from < 2, var ui = json["ui"] as? [String: Any] {
            for (key, old) in Self.uiDefaultsBeforeVersion2 where (ui[key] as? NSObject)?.isEqual(old) == true {
                ui[key] = nil
            }
            json["ui"] = ui
        }
        json["version"] = currentVersion
        return (json, from)
    }

    /// Every `ui` default of 0.1.0 and 0.1.1, which are the same, taken from v0.1.1's source. All of
    /// them, not only those that differ from today's, so a default changed later cannot turn one
    /// into a choice.
    nonisolated static let uiDefaultsBeforeVersion2: [String: any Sendable] = [
        "slideInCurve": "spring",
        "cardMaxWidth": 208, "cardMaxHeight": 86, "cardMinSide": 114, "cardSpacing": 10, "panelInset": 19,
        "screenMargin": 17, "stackMinScale": 0.5, "stackGap": 24, "cardCornerRadius": 12,
        "cardBorderWidth": 2, "cardBorderOpacity": 0.35, "cardShadowRadius": 4, "cardShadowOpacity": 0.5,
        "cardShadowY": 6, "hoverScale": 1.06, "pressScale": 0.96, "hoverDim": 0.35, "buttonSize": 27,
        "buttonIconSize": 11, "buttonSpacing": 4, "selectionCircleSize": 19, "selectionBarHeight": 44,
        "selectionStripGap": 16, "autoScrollZone": 44, "autoScrollSpeed": 600, "thumbnailSeconds": 5,
        "toastSeconds": 1.7, "slideInDuration": 0.75, "slideOutDuration": 0.3, "staggerDelay": 0.05,
        "staggerTotalMax": 0.3, "relayoutDuration": 0.2, "insertDuration": 0.5, "expandDuration": 0.25,
        "hoverRevealDuration": 0.15, "flightArc": 0.08, "flightArcMax": 64, "flightDepth": 0.05, "motion": 1,
        "backdropWidth": 290, "backdropTint": 0, "backdropTintStart": 0, "backdropBlurRadius": 13,
        "backdropBands": 3, "backdropRampPower": 2, "backdropFadeIn": 0.35, "backdropFadeOut": 0.35,
        "backdropSlideIn": 0.5, "backdropSlideOut": 0.3, "dimOpacity": 0.5, "dimBlurRadius": 12,
        "dimFade": 0.4, "annotationMinWidth": 770, "annotationMinHeight": 320, "annotationCornerRadius": 10,
        "annotationToolbarGap": 12, "annotationScreenInset": 65, "zoomEdgeBandPoints": 120,
        "zoomEdgePull": 0.5, "dragDistance": 4, "hitMargin": 4, "cornerHitSize": 13.5, "edgeHitSize": 9,
        "smallSide": 16, "handleSize": 8, "dotRadius": 4, "dotHitRadius": 12, "smallestRectangle": 4,
        "shortestArrow": 8, "textDragDelay": 0.15, "textDragDistance": 24, "newTextSize": 24,
        "selectionOutlineWidth": 3.5, "textWeight": 500, "textLineHeight": 1.35, "arrowheadLength": 4.5,
        "arrowheadWidth": 4, "stitchLongSide": 4096,
    ]

    nonisolated static func encoder() -> JSONEncoder {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        enc.userInfo[UITweaks.differencesOnly] = true
        return enc
    }

    /// `raw` when it was written, nil when it was not.
    static func write(_ raw: Data, to url: URL) -> Data? {
        failure(writing: raw, to: url) == nil ? raw : nil
    }

    /// Why writing `raw` failed, or nil when it was written.
    nonisolated static func failure(writing raw: Data, to url: URL) -> String? {
        do { try writeOrThrow(raw, to: url) } catch { return "\(url.lastPathComponent): \(error.localizedDescription)" }
        return nil
    }

    private nonisolated static func writeOrThrow(_ raw: Data, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try raw.write(to: url, options: .atomic)
    }

    private nonisolated static func deepMerge(_ base: [String: Any], _ over: [String: Any]) -> [String: Any] {
        var out = base
        for (k, v) in over {
            if let b = base[k] as? [String: Any], let o = v as? [String: Any] { out[k] = deepMerge(b, o) } else { out[k] = v }
        }
        return out
    }

    /// Three-way merge from `base`, what the file and the app last agreed on: a key the app changed
    /// takes the app's value, and every other key the file's. Where both changed a key, the file's
    /// value stands, and the key is listed in `conflicts`. nil when one of them does not encode.
    nonisolated static func merged(base: SettingsData, app: SettingsData, file: SettingsData) -> (data: SettingsData, conflicts: [String])? {
        func object(_ d: SettingsData) -> [String: Any]? {
            (try? JSONEncoder().encode(d)).flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
        }
        // JSONSerialization's values are all NSObjects, which compare with `isEqual`.
        func same(_ a: Any?, _ b: Any?) -> Bool { (a as? NSObject) == (b as? NSObject) }
        func merge(_ base: [String: Any], _ app: [String: Any], _ file: [String: Any], path: String,
                   conflicts: inout [String]) -> [String: Any] {
            var out = file
            for key in Set(app.keys).union(base.keys) where !same(app[key], base[key]) {
                if let b = base[key] as? [String: Any], let a = app[key] as? [String: Any], let f = file[key] as? [String: Any] {
                    out[key] = merge(b, a, f, path: "\(path)\(key).", conflicts: &conflicts)
                } else if same(file[key], base[key]) {
                    out[key] = app[key]
                } else if !same(file[key], app[key]) {
                    conflicts.append(path + key)
                }
            }
            return out
        }
        guard let b = object(base), let a = object(app), let f = object(file) else { return nil }
        var conflicts: [String] = []
        let out = merge(b, a, f, path: "", conflicts: &conflicts)
        guard let raw = try? JSONSerialization.data(withJSONObject: out),
              let data = try? JSONDecoder().decode(SettingsData.self, from: raw) else { return nil }
        return (data, conflicts.sorted())
    }
}
