import Combine
import Foundation

/// The lab's conditions, over this Mac's own.
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

        init(_ status: AgentPluginStatus?) {
            guard let status else { self = .absent; return }
            self = status.installed ? .installed : status.hasTool ? .notInstalled : .noTool
        }
    }

    /// What the lab sets. Each is nil while it is this Mac's own.
    struct Overrides: Equatable {
        /// A home no agent has, so nothing a run does can reach the person's own folders.
        static let home = URL(fileURLWithPath: "/setup-lab")
        /// What a simulated protected folder is called: the Desktop, where macOS saves screenshots
        /// until someone picks another folder.
        static let protectedArea = ScreenshotWatcher.protectedArea(of: home.appendingPathComponent("Desktop"), home: home)

        var trusted: Bool?
        var screenRecording: Bool?
        var pickerQuestion: PickerQuestion.Status?
        var folder: Folder?
        var hasScreenshots: Bool?
        var saveTarget: String?
        var menuBarIcon: Bool?
        var claude: AgentState?
        var codex: AgentState?

        func conditions(over mac: SetupConditions) -> SetupConditions {
            var conditions = mac
            if let trusted { conditions.trusted = trusted }
            if let screenRecording { conditions.screenRecording = screenRecording }
            if let pickerQuestion { conditions.pickerQuestion = pickerQuestion }
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
                guard let state = client == .claude ? claude : codex else { return mac.first { $0.client == client } }
                guard state != .absent else { return nil }
                // With no environment, since CLAUDE_CONFIG_DIR or CODEX_HOME would name a real folder.
                let root = AgentPlugin.root(of: client, home: Self.home, environment: [:])
                return AgentPluginStatus(root: root, client: client, installed: state == .installed, hasTool: state != .noTool)
            }
        }

        /// The simulated conditions, for the log.
        var summary: String {
            var parts: [String] = []
            if let trusted { parts.append("accessibility=\(trusted)") }
            if let screenRecording { parts.append("screenRecording=\(screenRecording)") }
            if let pickerQuestion { parts.append("pickerQuestion=\(pickerQuestion)") }
            if let folder { parts.append("folder=\(folder.name)") }
            if let hasScreenshots { parts.append("screenshots=\(hasScreenshots)") }
            if let saveTarget { parts.append("saveTo=\(saveTarget)") }
            if let menuBarIcon { parts.append("icon=\(menuBarIcon)") }
            if let claude { parts.append("claude=\(claude)") }
            if let codex { parts.append("codex=\(codex)") }
            return parts.isEmpty ? "conditions=real" : parts.joined(separator: " ")
        }
    }

    @Published var overrides = Overrides() { didSet { keepStart() } }
    /// How macOS's folder prompt is answered, when the folder is simulated.
    @Published var folderAnswer = Answer.allow
    @Published var scope = SetupModel.Scope.whole { didSet { keepStart() } }
    @Published var start = SetupModel.Page.welcome
    @Published var running = false
    /// This Mac's own, for the pickers' Real and under the overrides.
    @Published var real = SetupWindowController.Callbacks().conditions()
    @Published var realAgents: [AgentPluginStatus] = [] { didSet { keepStart() } }

    /// What a run reads.
    var conditions: SetupConditions { overrides.conditions(over: real) }
    var agents: [AgentPluginStatus] { overrides.agents(over: realAgents) }

    /// Sends when what a run reads changes. `@Published` sends before the change lands, so this sends
    /// a turn later, once for every change made in that turn.
    var changes: AnyPublisher<Void, Never> {
        Publishers.Merge3($overrides.dropFirst().map { _ in }, $real.dropFirst().map { _ in }, $realAgents.dropFirst().map { _ in })
            .debounce(for: .zero, scheduler: DispatchQueue.main)
            .eraseToAnyPublisher()
    }

    /// The pages a run can start on: those the run will hold.
    var startPages: [SetupModel.Page] {
        SetupModel.pages(scope: scope, usesLiveInk: true, hasAgents: !agents.isEmpty)
    }

    private func keepStart() {
        if !startPages.contains(start) { start = startPages[0] }
    }

    /// Back to this Mac's own, as the lab closes.
    func forget() {
        overrides = Overrides()
        folderAnswer = .allow
    }
}
