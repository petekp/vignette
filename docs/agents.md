# For agents

The agent feature is secondary and experimental. It is a skill that teaches Claude Code or Codex
the `vignette://` contract: push an image with `add`, draw on it with `marks=`, read
`<name>-annotated.png` back. The skill's text is at `skills/vignette/SKILL.md` in the repo, and it
ships in the app bundle. The marks format is in [commands.md](commands.md).

## Installing

The first launch that finds `~/.claude` or `~/.codex` opens Settings at the Agents section and asks
once; `agentSkill` in settings.json records only that the offer was made. The tab lists every agent
found on this Mac, says whether the skill is there, and gives each one its own Install or Remove
button. Disk is the only record: a later launch rewrites a copy whose files differ from the app's
and installs nothing new. `open -g vignette://install-skill` installs for every agent from a script.

Links are resolved all the way, so the skill is written where it really lives: an agent whose
`skills` is a link into a repository of yours, or whose `vignette` folder is a link to a skill you
keep elsewhere, has that folder updated in place, and two agents reaching one folder share the one
copy. Installing replaces whatever is at the skill's path with the app's copy. Remove takes away
the entry under that agent's `skills` and nothing else, so a link goes and what it pointed at stays.
