# For agents

The agent feature is secondary and experimental. It is a skill that teaches Claude Code or Codex
the `vignette://` contract: push an image with `add`, draw on it with `marks=`, read
`<name>-annotated.png` back. The skill's text is at `skills/vignette/SKILL.md` in the repo, and it
ships in the app bundle. The marks format is in [commands.md](commands.md).

## Installing

Setup's last page offers the skill when this Mac has `~/.claude` or `~/.codex`, with a switch for
each agent, and installs the ones left on when setup closes. A settings file from before that page,
or a setup closed before reaching it, gets the offer once, as the Settings window at the Agents
section. `agentSkill` in settings.json records only that the offer was made. The Agents tab lists
every agent found on this Mac with a switch that adds or removes the skill. Disk is the only record:
a launch updates a copy that holds an older version than the app's, or none (`metadata.version`
in `SKILL.md`), keeps any other, and installs nothing new. `open -g vignette://install-skill`
installs for every agent from a script.

Links are resolved all the way, so the skill is written where it really lives. An agent whose
`skills` is a link into a repository of yours, or whose `vignette` folder is a link to a skill you
keep elsewhere, has that folder updated in place. Two agents reaching one folder share the one copy.
Installing replaces whatever is at the skill's path with the app's copy. Remove takes away the entry
under that agent's `skills` and nothing else, so a link goes and what it pointed at stays.
