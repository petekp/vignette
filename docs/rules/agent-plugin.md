# The agent plugin

- The agent plugin (`agent-plugin/`) and the skill it carries (`skills/vignette/SKILL.md`) ship in
  the bundle as folder resources (project.yml), and `AgentPlugin.swift` installs them.
  `AgentPlugin.stage` writes a marketplace into Application Support: the template, the skill copied
  into `plugins/vignette/skills/vignette`, `scripts/inbox-root` naming this app's inboxes, and both
  marketplace lists named for the URL scheme, so a fork installs `vignette@<its scheme>`. It is
  assembled beside the old copy and swapped in whole. Each agent installs from it with its own
  command line tool (`PluginHost`): `claude plugin marketplace add`, then `claude plugin install
  … --scope user`; `codex plugin marketplace add`, then `codex plugin add`. Claude Code reads a
  folder marketplace in place. Codex copies the plugin into its cache, so its update is `codex
  plugin add` again. A root is `~/.claude` or `~/.codex`, or where `CLAUDE_CONFIG_DIR` and
  `CODEX_HOME` point, and only one that exists. A launch with `VIGNETTE_SETTINGS` never gets the
  person's own two, whatever the environment names (`AgentPlugin.guarded`, found from the user
  database, which `CFFIXED_USER_HOME` does not move). Vignette never reads or removes the person's
  `~/.agents` either, and `install(into:)` and `remove(from:)` refuse the person's own folders, which
  `install-skill?root=` can name. A folder inside one, one reached through a link, or one spelled in
  another case counts as theirs (`AgentPlugin.isPersons`). A test launch on the person's own home
  folder, one without `CFFIXED_USER_HOME`, runs no agent tool (`AgentPlugin.isPersonsHome`): a tool
  run there gets the person's `HOME`, and codex reads `$HOME/.agents/skills` whatever `CODEX_HOME`
  says. Its launch writes the marketplace and logs `[plugin] test launch: <home> is the person's own
  home folder, so no install or update runs; …`, and `install(into:)` and `remove(from:)` answer
  `failed`. Send lists and reads no Claude Code session in a test launch whose Claude Code folder is
  the person's: `StartableSessions` and `ClaudeCodeConnection.transcripts` read
  `AgentPlugin.claudeRoot`, which is nil there. `AgentPlugins` takes the home folder, the
  environment and the person's home as parameters, and gives each tool that home as `HOME`. Its
  `init()` and the `AgentPlugin.app…` entry points (`AgentPluginFolders.swift`) read the app's own.
  `scripts/check-agent-folders.py`, which `scripts/build.sh --test` runs, fails a default of the
  process's home or environment in `Sources/AgentPlugin*.swift`, and `AgentPlugins()` in a test.
  `root(of:)` keeps its default until `CodexConnection.isLoaded` passes an environment. The live
  check is `install-skill?root=<dir>` (debug only, a folder named `.claude` or `.codex`). A test copy
  launched with `CFFIXED_USER_HOME` installs into its scratch home, as the end-to-end copies do.
  The Codex app's own codex needs nothing from `HOME`. A vite-plus shim does: it finds its package
  through `HOME`, so a test that runs one links
  the scratch home's `.vite-plus` to the real one, and unlinks it before anything lists Codex
  threads. Whether the plugin is on is read from
  the agent's own settings (`enabledPlugins` in Claude Code's settings.json, `[plugins."<id>"]` in
  Codex's config.toml), so a window asks without running a tool. Installs run one at a time on
  `AgentPlugins`' queue and answer on the main thread, and each result logs one `[plugin]` line.
  A launch writes the marketplace and updates an installed plugin whose listed version differs from
  the bundle's, or whose marketplace copy changed. It installs the plugin only where the skill from
  before the plugin is (`<root>/skills/vignette`, and `~/.agents/skills/vignette` for Codex), since
  that person chose the skill. Codex reads `~/.agents/skills` whatever `CODEX_HOME` says (codex
  0.164.0, 2026-11-11), so that skill goes with the Codex folder the app's environment names, the one
  `roots` lists: an install into another Codex folder leaves it for the Codex that uses that one.
  An app opened from Finder has no shell `CODEX_HOME`, so there it is `~/.codex`. Once
  the plugin is in, a folder there is removed; a link is the person's own and stays,
  with a `[plugin] kept` line. It does this once per agent folder: whenever
  the plugin is in beside that skill, from a launch or a switch, the folder is recorded in
  `agent-plugin-migrated.json` in Application Support (`LegacySkillMigrations`), and a launch never
  installs for the skill in a recorded folder. So a linked skill gets the plugin once, and the
  switch's off holds after that. The record lives there rather than in settings.json because it is
  about this Mac's agent folders, and a settings.json synced by dotfiles reaches other Macs. A build
  from before the record ignores the file and installs again at each launch, as it always did. A
  test launch records only the scratch folders it iterates, since `roots` leaves out the person's
  own. A launch never removes the plugin, and never installs it anywhere else. Raise the version in both of the plugin's manifests with every change
  to the plugin or the skill, and the skill's own `metadata.version` with every change to the skill.
  `agentSkill` in settings.json records only that the offer was made. Setup's last page makes it
  and records `off`. A file that finished setup before that page existed, or a setup closed before
  it, still reads `unasked`, and with an agent directory present the next launch makes the offer
  once as the Settings window at the Agents section. That window
  comes up with `orderFront` and does not activate the app: the user did not ask for it. The Agents
  tab's switches, setup's last page and `install-skill` are the only things that install the plugin
  somewhere new, and the switch is the only thing that removes it. A switch says Installing… or
  Removing… until the tool answers, and a failure is said under the agent's name. A launch's
  update of an installed plugin says a failure only in the log.
  The tools are found by `AgentTools`: the installers' folders, the version managers' (nvm, fnm,
  Volta, Bun, pnpm, asdf, mise), then the login shell's `PATH`, asked once at launch off the main
  thread (`[tools] login shell found …`). A lookup on the main thread answers at once with what is
  known, and setup and the Agents tab refresh on `AgentTools.found`. Without the agent's tool the
  switch is off and says which command is missing. After a Claude Code install, the Agents tab and
  setup's last page say sessions already open need `/reload-plugins`. An older file holding `on` is read
  as `off` (`validated()`). The app carries the plugin because someone who downloads Vignette needs
  their agent to learn the `vignette://` contract and, for Claude Code, to receive what Send sends.
  The app is the one thing they are sure to have and the one thing that knows which commands its
  version supports. `docs/claude-code-without-herdr-2026-09-27.md` has the design and its tests.
