import XCTest

/// The keys the random sequences edit. The app edits the first three and the file all but the
/// folder, each with a fresh number: odd from the app, even from the file, all inside their bounds
/// and none a default of 0.1.1, which a migration would drop.
enum SyncKey: String, CaseIterable {
    case recentCount, cardMaxWidth = "ui.cardMaxWidth", screenshotsFolder, motion = "ui.motion"

    func set(_ n: Int, in d: inout SettingsData) {
        switch self {
        case .recentCount: d.recentCount = n
        case .cardMaxWidth: d.ui.cardMaxWidth = Double(300 + n)
        case .screenshotsFolder: d.screenshotsFolder = "~/s\(n)"
        case .motion: d.ui.motion = Double(n) / 1000
        }
    }

    func value(of n: Int) -> String {
        var d = SettingsData()
        set(n, in: &d)
        return value(in: d)
    }

    func value(in d: SettingsData) -> String {
        switch self {
        case .recentCount: "\(d.recentCount)"
        case .cardMaxWidth: "\(d.ui.cardMaxWidth)"
        case .screenshotsFolder: d.screenshotsFolder
        case .motion: "\(d.ui.motion)"
        }
    }

    static func values(in d: SettingsData) -> [SyncKey: String] {
        Dictionary(uniqueKeysWithValues: allCases.map { ($0, $0.value(in: d)) })
    }

    static func describe(_ d: SettingsData) -> String {
        allCases.map { "\($0.rawValue)=\($0.value(in: d))" }.joined(separator: " ")
    }

    /// An effect short enough for a trace.
    static func brief(_ effect: SettingsSync.Effect) -> String {
        switch effect {
        case .apply(let d, let source): return "apply(\(source): \(describe(d)))"
        case .write(let raw):
            guard case .loaded(let loaded) = Settings.parse(raw) else { return "write(invalid)" }
            return "write(\(describe(loaded.data)))"
        default: return "\(effect)"
        }
    }
}

/// Plays `Settings` in memory: the file is `disk` and the timers are two flags. Events pass through
/// an `EventHold` as in `Settings.send`, so an answer, or an edit made inside an `.apply`, is
/// reduced after every effect of the event that led to it.
struct SyncRig {
    static let original = AppleOriginal(location: "~/Desktop", showThumbnail: true, disableShadow: false, type: "png")

    private let hold = EventHold<SettingsSync.Event>()
    var sync: SettingsSync
    var app: SettingsData
    var disk: Data?
    /// The last bytes on disk that parsed, which a hand edit starts from when the file is broken or gone.
    var lastValid: Data
    var writes: [Data] = []
    var log: [String] = []
    var writeTimer = false
    var reloadTimer = false
    var writesFail = 0
    /// An app edit made inside the next `.apply`, as an `onChange` handler that calls `update` makes it.
    var onApply: ((inout SettingsData) -> Void)?

    init(readOnly: Bool = false, reason: String = "") {
        var base = SettingsData()
        base.appleOriginal = Self.original
        let raw = try! Settings.encoder().encode(base)
        app = base
        disk = raw
        lastValid = raw
        sync = SettingsSync(bytes: raw, data: base, readOnly: readOnly, readOnlyReason: reason)
    }

    @discardableResult
    mutating func send(_ event: SettingsSync.Event) -> [SettingsSync.Effect] {
        var all: [SettingsSync.Effect] = []
        let hold = self.hold
        hold.send(event) { event in
            let effects = sync.reduce(event)
            all += effects
            for effect in effects { run(effect) }
        }
        return all
    }

    private mutating func run(_ effect: SettingsSync.Effect) {
        switch effect {
        case .log(let line): log.append(line)
        case .apply(let d, _):
            app = d
            if let edit = onApply {
                onApply = nil
                appEdits(edit)
            }
        case .write(let raw):
            if writesFail > 0 {
                writesFail -= 1
                send(.wrote(raw, failure: "settings.json: the disk is full"))
                return
            }
            disk = raw
            lastValid = raw
            writes.append(raw)
            reloadTimer = true   // the watcher sees the app's own write
            send(.wrote(raw, failure: nil))
        case .writeAppData: send(.appData(app))
        case .readFileAndFlush: send(.flush(file: disk, app: app))
        case .scheduleWrite: writeTimer = true
        case .cancelWrite: writeTimer = false
        case .scheduleReload: reloadTimer = true
        }
    }

    @discardableResult
    mutating func appEdits(_ change: (inout SettingsData) -> Void) -> [SettingsSync.Effect] {
        change(&app)
        return send(.appChanged)
    }

    /// A hand edit, made over the file as it is, or over its last good bytes when it is broken or gone.
    @discardableResult
    mutating func fileEdits(_ change: (inout SettingsData) -> Void) -> [SettingsSync.Effect] {
        var d = parsed(disk) ?? parsed(lastValid)!
        change(&d)
        let raw = try! Settings.encoder().encode(d)
        disk = raw
        lastValid = raw
        return send(.fileChanged)
    }

    /// A hand edit to the file's JSON itself, for a key `SettingsData` would not write as given.
    @discardableResult
    mutating func putJSON(_ change: (inout [String: Any]) -> Void) -> [SettingsSync.Effect] {
        var json = try! JSONSerialization.jsonObject(with: parsed(disk) != nil ? disk! : lastValid) as! [String: Any]
        change(&json)
        let raw = try! JSONSerialization.data(withJSONObject: json, options: [.sortedKeys])
        disk = raw
        lastValid = raw
        return send(.fileChanged)
    }

    @discardableResult
    mutating func put(_ json: String) -> [SettingsSync.Effect] {
        disk = Data(json.utf8)
        if parsed(disk) != nil { lastValid = disk! }
        return send(.fileChanged)
    }

    @discardableResult
    mutating func writeFires() -> [SettingsSync.Effect] {
        writeTimer = false
        return send(.writeDue(file: disk, app: app))
    }

    @discardableResult
    mutating func reloadFires() -> [SettingsSync.Effect] {
        reloadTimer = false
        return send(.reloadDue(file: disk, app: app))
    }

    @discardableResult
    mutating func quit() -> [SettingsSync.Effect] {
        send(.quit)
    }

    /// The bytes as the app reads them; `SettingsData()` for bytes that do not parse.
    func decoded(_ raw: Data?) -> SettingsData {
        guard let d = parsed(raw) else {
            XCTFail("the bytes do not parse")
            return SettingsData()
        }
        return d
    }

    func parsed(_ raw: Data?) -> SettingsData? {
        guard let raw, case .loaded(let loaded) = Settings.parse(raw) else { return nil }
        return loaded.data
    }
}

extension Array where Element == SettingsSync.Effect {
    var hasWrite: Bool { contains { if case .write = $0 { true } else { false } } }
    var logLines: [String] { compactMap { effect -> String? in if case .log(let line) = effect { return line }; return nil } }
}

extension SyncRig {
    /// Plays one of `SettingsSyncTests.syncOrders`.
    mutating func play(_ order: String, app: (inout SettingsData) -> Void, file: (inout SettingsData) -> Void) {
        for step in order {
            switch step {
            case "C": appEdits(app)
            case "E": fileEdits(file)
            case "R": reloadFires()
            default: writeFires()
            }
        }
    }
}
