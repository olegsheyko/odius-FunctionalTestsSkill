# functional-tests: a Claude Code skill for UE functional tests

A skill for [Claude Code](https://claude.com/claude-code) that creates, verifies, fixes and records videos of Unreal Engine 5.7 functional tests in the StealDrive / MonsterPotion project (module `Source/MPFunctionalTests`).

A test is a bot that plays like a real player through the game's own keys: single-player tests on an empty map or on a copy of a real map, local co-op, networked CQTest runs (listen server and clients in PIE), and a shift scenario where players pick jobs from a shared task board.

## Modes
- **Create from a description**: learn the mechanic (GDD, C++, Blueprint dumps), pick the kind of test, write the player's actions, scaffold with `new-test.py`, build, create the map, run a series.
- **Verify**: `run-tests.ps1` picks the right editor, retries a run after a CEF crash and prints a log summary (result, failure reason, last steps of the player that failed, unexpected log errors, shortcuts, shift report).
- **Fix**: find who is at fault (outdated test, game bug, bot, race, log noise, environment), replay with the seed, add diagnostics, fix the cause rather than the symptom.
- **Video**: records the engine viewports (network tests: a 2x2 grid of the players), at least 30 fps, frames are checked before the video is handed over.

## Contents
```
functional-tests/
  SKILL.md                 workflow and rules
  reference/               design guide, triage, network, video
  scripts/                 run-tests, summarize-log, build, new-test, create-maps, dump-assets, video-frames, config
  templates/               .h/.cpp test scaffolds
```

## Installation
Copy the `functional-tests` folder to `<project>/.claude/skills/` (or `~/.claude/skills/`).
Engine, project and ffmpeg paths are set in `functional-tests/scripts/config.ps1`.
The skill relies on the code of the `Source/MPFunctionalTests` module and on the project document `Docs/Technical Design/Functional Tests.md` (a full audit of the tests); without them it is useful only as an example.
