import Foundation

/// The settings file's sync: what the file and the app last agreed on, and what to do when either
/// changes. `Settings` reads the file, runs the watchers and the timers, and runs what this returns.
struct SettingsSync {
    /// Coalesces a slider drag into one write.
    static let writeDelay: TimeInterval = 0.3
    /// One reload after an editor's burst of file events.
    static let reloadDelay: TimeInterval = 0.15

    enum Event: Equatable {
        /// `update`, `restoreAppleDefaults` or `followAppleLocation` changed `data`, after its apply.
        case appChanged
        /// The file's watcher or its folder's fired.
        case fileChanged
        /// `file` is the bytes read when the timer fired, nil when the read failed.
        case reloadDue(file: Data?, app: SettingsData)
        case writeDue(file: Data?, app: SettingsData)
        /// Quitting. Answered with `.readFileAndFlush` when the app changed since the last flush.
        case quit
        /// The answer to `.readFileAndFlush`.
        case flush(file: Data?, app: SettingsData)
        /// The answer to `.writeAppData`: the app's data after the effects before it.
        case appData(SettingsData)
    }

    enum Effect: Equatable {
        /// One log line, without the `[settings]` tag.
        case log(String)
        /// `Settings.apply(_:source:)`, which pushes Apple's keys.
        case apply(SettingsData, source: String)
        /// Write the file, then watch the new file.
        case write(Data)
        /// Answer with `.appData`. Always the last effect. An `onChange` handler may call `update`
        /// during the `.apply` before it, so the write takes the app's data as it is afterwards.
        case writeAppData
        /// Read the file and answer with `.flush`.
        case readFileAndFlush
        /// Replaces any scheduled write.
        case scheduleWrite(after: TimeInterval)
        case cancelWrite
        /// Replaces any scheduled reload.
        case scheduleReload(after: TimeInterval)
    }

    /// True when the file was written by a newer Vignette, whose keys a write would drop, or when it
    /// cannot be written at all. Nothing is written then, and `readOnlyReason` says why. Never cleared.
    private(set) var readOnly: Bool
    private var readOnlyReason: String
    /// The file as this app last wrote or read it: the state the file and the app last agreed on.
    private var syncedBytes: Data?
    private var syncedData: SettingsData
    /// An app change since the last flush. Only a flush clears it, so a flush at quit writes even
    /// after the timer's write ran.
    private var changedSinceFlush = false

    init(bytes: Data?, data: SettingsData, readOnly: Bool, readOnlyReason: String) {
        syncedBytes = bytes
        syncedData = data
        self.readOnly = readOnly
        self.readOnlyReason = readOnlyReason
    }

    mutating func reduce(_ event: Event) -> [Effect] {
        switch event {
        case .appChanged:
            changedSinceFlush = true
            return [.scheduleWrite(after: Self.writeDelay)]
        case .fileChanged:
            return [.scheduleReload(after: Self.reloadDelay)]
        case .reloadDue(let file, let app):
            return takeIn(file, app: app)
        case .writeDue(let file, let app):
            // The file may have been edited since the app last read it, with the watcher's reload
            // still to come, so that edit is taken in first and the write keeps it.
            return takeIn(file, app: app) + [.writeAppData]
        case .quit:
            // A quit with nothing to write does not read the file.
            guard changedSinceFlush else { return [] }
            changedSinceFlush = false
            return [.cancelWrite, .readFileAndFlush]
        case .flush(let file, let app):
            return takeIn(file, app: app) + [.writeAppData]
        case .appData(let d):
            return write(d)
        }
    }

    private mutating func write(_ d: SettingsData) -> [Effect] {
        if readOnly { return [.log("warning not written: \(readOnlyReason)")] }
        guard let raw = try? Settings.encoder().encode(d) else { return [] }
        var effects: [Effect] = []
        // Tweak-panel changes are not logged as they happen (a drag is many of them); the write is.
        let changed = Self.uiChanges(from: syncedData.ui, to: d.ui)
        if !changed.isEmpty { effects.append(.log("wrote \(changed.joined(separator: " "))")) }
        syncedBytes = raw
        syncedData = d
        effects.append(.write(raw))
        return effects
    }

    /// `ui.key=value` for every UI number that differs, in key order.
    private static func uiChanges(from old: UITweaks, to new: UITweaks) -> [String] {
        func dict(_ u: UITweaks) -> [String: Any] {
            (try? JSONSerialization.jsonObject(with: JSONEncoder().encode(u))) as? [String: Any] ?? [:]
        }
        let a = dict(old), b = dict(new)
        return b.keys.sorted().compactMap { key in
            let value = b[key].map { "\($0)" } ?? "null"
            let before = a[key].map { "\($0)" } ?? "null"
            return value == before ? nil : "ui.\(key)=\(value)"
        }
    }

    private mutating func takeIn(_ raw: Data?, app: SettingsData) -> [Effect] {
        guard let raw, raw != syncedBytes else { return [] }
        switch Settings.parse(raw) {
        case .missing:
            return []
        case .invalid(let reason):
            return [.log("error settings-invalid file changed but does not parse; keeping current settings: \(reason)")]
        case .loaded(var loaded):
            var effects: [Effect] = loaded.log.map { .log($0) }
            if loaded.fileVersion > Settings.currentVersion, !readOnly {
                readOnly = true
                readOnlyReason = "the file is from a newer version"
                effects.append(.log("warning file version \(loaded.fileVersion) is newer than this build's \(Settings.currentVersion); not writing to it"))
            }
            // The app owns this record; a pasted or older file must not erase it.
            if loaded.data.appleOriginal == nil { loaded.data.appleOriginal = app.appleOriginal }
            let validated = loaded.data.validated()
            effects += validated.corrections.map { .log("warning clamped \($0)") }
            // A change made in the app since the last write is not in the file yet. Merging from
            // what the two last agreed on keeps it beside the file's edit.
            var next = validated.data
            if syncedData != app, let merged = Settings.merged(base: syncedData, app: app, file: validated.data) {
                next = merged.data
                effects += merged.conflicts.map { .log("kept the file's \($0) over this app's change") }
            }
            effects.append(.apply(next, source: "file"))
            syncedBytes = raw
            syncedData = validated.data   // the next tweak-panel write logs only what it changed
            // Stamp a pre-version file once so the migration does not repeat on every reload.
            if loaded.fileVersion < Settings.currentVersion { effects += write(loaded.data) }
            return effects
        }
    }
}
