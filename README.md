# functional-tests: a Claude Code skill for Unreal Engine functional tests

This skill teaches [Claude Code](https://claude.com/claude-code) to **write, run, debug and record videos of functional tests** for the StealDrive / MonsterPotion project (Unreal Engine 5.7).

A functional test here is a bot that plays the game like a person: it walks, aims, presses the game's own keys (E, LMB, G, Space) and waits for the game to react. It checks the result by reading the game state (cauldron, fermenter, coins, guest state). The tests are C++ classes in the project module `Source/MPFunctionalTests`; this repository holds only the skill (instructions + helper scripts) that Claude uses to work with them.

- [What you get](#what-you-get)
- [Requirements](#requirements)
- [Installation](#installation)
- [How to use it (prompts)](#how-to-use-it-prompts)
- [Using the scripts without Claude](#using-the-scripts-without-claude)
- [What a test looks like](#what-a-test-looks-like)
- [Rules the skill enforces](#rules-the-skill-enforces)
- [Troubleshooting](#troubleshooting)

## What you get

**The implementation (C++) lives in the project, not in this repository.** In the StealDrive depot:

| Where | What |
|---|---|
| `Source/MPFunctionalTests/MPFunctionalTest.h/.cpp` | Base class `AMPFunctionalTest`: step queue, player lanes, navigation, approach with a random distance inside the game's reach, aiming, key presses, dropping into openings, run reports, failure kinds |
| `Source/MPFunctionalTests/MPBrewingTestBase.*` | Brewing station kit: cauldron, bellows, fuel rack, fermenter (spawned or taken from the level) and their player steps |
| `Source/MPFunctionalTests/MPTavernTestBase.*` | Guest flow (order, dialogue, serving, coin, review) and co-op roles |
| `Source/MPFunctionalTests/MPFT_*.h/.cpp` | The tests themselves: `FT_CartTow`, `FT_FermenterBrew`, `FT_CauldronBrew`, `FT_GuestOrder`, `FT_TavernCoop`, ... (one actor per map `Content/Tests/FTEST_*`) |
| `Source/MPFunctionalTests/MPNetTavernCoopTest.cpp`, `MPNetCoopPlayer.*`, `MPMapNetworkComponent.h`, `MPShiftBoard.*` | Networked tests (CQTest: listen server + clients in PIE), co-op roles, the shift with a shared task board |
| `Source/MPFunctionalTests/MPGridRecorder.h` | Video recording from the engine viewports (2x2 grid for network tests) |
| `Scripts/CreateFunctionalTestMap.py` | Creates the `FTEST_*` maps |
| `Docs/Technical Design/Functional Tests.md` | Full documentation: architecture, rules, API, known game issues, checklist (local to the project) |

**This repository** (copy it into the project):

```
functional-tests/
  SKILL.md                   what Claude does in each mode, and the rules
  reference/design-guide.md  from a description to a test scenario
  reference/triage.md        why a test is red and how to fix it
  reference/network.md       networked tests, co-op roles, shift tasks
  reference/video.md         recording and checking videos
  scripts/                   PowerShell / Python helpers: run, summarize, build, scaffold, lint (cheat check),
                             list existing tests, pending precheck, video check (also usable by hand, see below)
  templates/                 .h/.cpp scaffold for a new test
```

## Requirements

- Windows, the StealDrive project with the `MPFunctionalTests` module, Unreal Engine 5.7 registered on the machine.
- Claude Code (CLI, desktop or IDE extension).
- PowerShell 5+ and Python 3 (for `new-test.py`).
- Perforce command line (`p4`) if you want Claude to open / add files for you.
- ffmpeg, only for video (`ffmpeg` on the PATH or `FFMPEG=<path to ffmpeg.exe>`).

## Installation

1. Copy the `functional-tests` folder to `<project>/.claude/skills/` (for example `A:\StealDrive\.claude\skills\functional-tests`).
2. Restart Claude Code in the project folder. The skill appears as `functional-tests` in the list of skills.
3. Nothing else to configure in the usual case. The scripts find everything themselves:
   - the project: the nearest `.uproject` above the skill folder (or set `FT_PROJECT=<path to .uproject>`);
   - the engine: the project's `EngineAssociation` in the registry (or set `UE_ENGINE_DIR=<engine root>`);
   - ffmpeg: the PATH (or `FFMPEG=<path>`).

   If something is missing, the script stops with a clear message (exit code 2) instead of using a wrong path.

## How to use it (prompts)

Just describe what you need in plain words. Claude loads the skill when the request is about functional tests; you can also force it with "use the functional-tests skill". Each request below is a complete prompt.

### 1. Create a test from a description
```
Write a functional test: the player takes a beer from the fermenter tap, carries it to the guest at the kiosk
and serves it; check that the guest pays and the reputation goes up.
```
```
Make a network test with 2 clients where one client pumps the bellows and the other stirs; check the wort is
ready on every machine.
```
What Claude does first: it looks for an existing test that already covers the request (`list-tests.py`). If one does, it does **not** write code; it tells you which test it is and asks:

> This looks covered by `FT_GuestOrder` (`Source/MPFunctionalTests/MPFT_GuestOrder.h`, map `FTEST_GuestOrder`): a guest comes, the player takes the order, brews it, serves it and picks up the coin. What should I do: 1) check and show the existing test (run it, show the result / a video), or 2) write a separate test from scratch?

Otherwise it reads the GDD and the C++ of the mechanic (and Blueprint dumps when needed), picks the kind of test (empty map, copy of a real map, local co-op, network), writes the steps as player actions, scaffolds the files with `new-test.py`, fills `BuildScenario()`, builds, creates the map, runs a series until it is green, and reports the files, the results and any game bugs it found. It asks you only if the game has several valid ways to do the action and the GDD does not say which one.

Tips for a good prompt: say **what the player does** and **what must be true at the end**. Mention the map if it matters ("on a copy of LS_DwarfFort"), the number of players, and whether the network matters.

### 2. Run / check tests
```
Run all functional tests and tell me which are red.
Run FTEST_GuestOrder 4 times and tell me if it is stable.
Run the network shift test.
```
You get: green / red per run with the reason, the last steps of the player that failed, unexpected log errors, and for the shift the number of guests served and how busy every player was.

### 3. Fix a red test
```
FT_CartTow is red: [timeout] Step 'The cart comes to rest behind the player'. Find out why and fix it.
```
(or paste the log). Claude decides who is at fault (outdated test, game bug, bot, race between players, log noise, environment), reproduces with the seed, adds diagnostics if the cause is unclear, and fixes the cause. It does **not** change game code or weaken checks to make a test green; a game bug is reported to you with file, line and seed.

### 4. Record a video
```
Record a video of the network shift test.
Record FT_CauldronBrew.
```
You get an MP4 (at least 30 fps) in `Saved/Videos`: a functional test shows the player view and the side observer; a network test shows all players in a 2x2 grid with labels. Claude retries until a green run and checks the frames before giving you the file.

### 5. Before a submit
```
Check that my pending changelist builds on top of the latest depot and list what must be submitted together.
```

## Using the scripts without Claude

All scripts are in `functional-tests/scripts` and work by hand. Run them from PowerShell:

```powershell
$S = ".claude\skills\functional-tests\scripts"

# Build the editor target (close the editor first: it locks the DLLs)
powershell -ExecutionPolicy Bypass -File $S\build.ps1

# Run tests (headless for functional tests; network tests use the full editor automatically)
powershell -ExecutionPolicy Bypass -File $S\run-tests.ps1 -Tests "Project.Functional Tests"
powershell -ExecutionPolicy Bypass -File $S\run-tests.ps1 -Tests "Project.Functional Tests.Tests.FTEST_CartTow" -Count 4
powershell -ExecutionPolicy Bypass -File $S\run-tests.ps1 -Tests "Project.Network.TavernShift"
powershell -ExecutionPolicy Bypass -File $S\run-tests.ps1 -Tests "Project.Functional Tests.Tests.FTEST_CartTow" -Seed 1414637697

# Record a video (keeps retrying until a green run, max 3)
$env:FFMPEG = "E:\ffmpeg\ffmpeg.exe"
powershell -ExecutionPolicy Bypass -File $S\run-tests.ps1 -Tests "Project.Network.TavernShift" -Video -UntilGreen 3
powershell -ExecutionPolicy Bypass -File $S\video-frames.ps1 -Video <file.mp4>      # duration, fps check, sample frames

# Summarize any test log
powershell -ExecutionPolicy Bypass -File $S\summarize-log.ps1 -Log <path to .log>

# Scaffold a new test (+ its map entry), then create the map
python $S\new-test.py --name KegFill --base brewing --desc "Player fills a keg from the fermenter tap"
python $S\new-test.py --name NightShift --base tavern --map-copy /Game/CORE/MAPS/LS_DwarfFort
powershell -ExecutionPolicy Bypass -File $S\create-maps.ps1

# Dump Blueprints / StateTrees / levels as text (variable and component names for test steps)
powershell -ExecutionPolicy Bypass -File $S\dump-assets.ps1 -Paths /Game/CORE/AI/BP_GuestBase

# Is this already covered? List every test, or find the ones matching a request
python $S\list-tests.py
python $S\list-tests.py --query "guest order serve beer coin"

# Check test code for cheats (teleports, spawning to get around problems, direct game calls, an unwritten scaffold)
python $S\lint-test.py                      # all tests
python $S\lint-test.py MPFT_KegFill.cpp     # one test

# Before a submit: build the latest depot, then the latest depot + your pending, in a separate folder
powershell -ExecutionPolicy Bypass -File $S\precheck-pending.ps1
```

| Script | Exit codes |
|---|---|
| `run-tests.ps1` | 0 every run green (or a green run found with `-UntilGreen`), 3 red, 2 setup problem |
| `build.ps1` | 0 built, 1 compile / link error, 2 setup problem or editor running |
| `create-maps.ps1`, `dump-assets.ps1` | 0 done, 1 failed or timed out, 2 setup problem |
| `video-frames.ps1` | 0 fine, 3 below 30 fps, 2 setup problem |
| `lint-test.py` | 0 clean, 1 cheats found (file:line and kind), 2 files not found |
| `list-tests.py` | 0 always (prints the list or the matches) |
| `precheck-pending.ps1` | 0 head and head + pending build, 1 the depot head itself is broken, 3 your pending breaks the build, 2 setup problem |

A run is **green** only if the editor exited by itself with code 0 and without a crash, every test the filter found completed and passed, and (with `-Video`) the MP4 was written and passed the check. `-UntilGreen` is for getting one recording; stability is shown by a series (`-Count N`). The log of a run that crashed at start (CEF assert) is kept as `*_cefcrash.log`. Every editor run has a time limit (`-TimeoutMinutes`, default 45).

**Perforce is not automatic.** The scripts never open or add files. `new-test.py` refuses to write when the map script is read-only and prints the `p4 edit` / `p4 add` commands to run.

## What a test looks like

A scaffold from `new-test.py` fails as `[setup]` until its scenario is written. A filled-in test reads like the player's actions:

```cpp
void AMPFT_CartTow::BuildScenario()
{
    Cart = Cast<ANetworkIngredientCart>(SpawnFixtureOfClass(CartClass.LoadSynchronous(), GetActorLocation() + FVector(CartDistance, 0, 0), FRotator::ZeroRotator));
    if (!CheckSetup(Cart != nullptr, TEXT("BP cart not found"))) return;
    AddWaitUntilSettled(TEXT("Everything lands"));
    AddApproach(TEXT("Walk up to the cart"), [this]() { return Cart.Get(); });          // random distance within the game's reach
    AddClickOn(TEXT("Harness the cart (E)"), EKeys::E, [this]() { return Cart.Get(); },   // aims, presses, retries like a player
        [this]() { return Cart->GetTowingPawn() == TestPawn; });
    AddWalkTo(TEXT("Tow it"), [this]() { return CartStart + FVector(-500, 0, 0); });
    AddAction(TEXT("It moved"), [this]() { Check(FVector::Dist2D(Cart->GetActorLocation(), CartStart) >= MinTowedDistance, TEXT("Cart did not move")); });
}
```

Failures say who is at fault: `[game]` (a check of the game state failed), `[timeout]` (the game did not get to the expected state in time), `[setup]` (the test is out of date: an asset, component or Blueprint variable is gone). Every run writes a report with its seed to `Saved/Automation/MPFunctionalTests/History.csv`.

## Rules the skill enforces

1. The player acts only through the game's input; anything done differently is listed in the run report as a shortcut.
2. Distances and amounts come from the game (for example the reach `MaxGrabDistance`), not from the test.
3. Wait for a state, never for a fixed time.
4. Game code and assets are not changed without your consent; found bugs are reported with file, line and seed.
5. Checks are never weakened to get a green result.
6. "Done" means a green series, and the other tests still pass when shared code changed.
7. Every ignored log error has a comment saying what it is and when to remove it.
8. Videos are at least 30 fps.
9. Perforce is explicit (`p4 edit` / `p4 add`), there is never a `p4 submit`, and a pending changelist is checked to build on top of the latest depot before it is handed over.
10. **No cheating when the bot gets stuck.** The test never moves the player or objects by code (teleport), never spawns things to get around a problem (ingredients next to the player, a table, a navmesh) and spawns nothing at all on a real map; it never calls game mechanics directly. If the same obstacle is not solved by two honest attempts, it stops and asks you: an unreachable room or item is a finding about the game or the map. `lint-test.py` checks the code for exactly these cheats; a test is not done until it is clean.
11. Before writing a new test, it checks whether an existing test already covers the request and asks you what to do.

## Troubleshooting

| Symptom | What to do |
|---|---|
| `SETUP: ... not found` | Set `FT_PROJECT`, `UE_ENGINE_DIR` or `FFMPEG` as the message says |
| `build.ps1` exit 2 "editor is running" | Close the editor of this project (it locks the module DLLs) |
| Compile errors like `'AddWaitStationSettled': identifier not found` after a sync | Your workspace mixes old and new files of `Source/MPFunctionalTests` (files left open or writable are skipped by `p4 sync`): check `p4 opened`, then `p4 sync -f //.../Source/MPFunctionalTests/...` |
| `the filter found no tests` | Wrong `-Tests` filter, or the map / class does not exist yet (build, then `create-maps.ps1`) |
| The bot cannot get into a room / reach an item, `NAVMESH NEEDS TO BE REBUILT` on screen | A finding about the map, not a reason to teleport or spawn: the skill stops and reports it; fix the level (navmesh, doors, stairs) or decide with the team |
| `CEF assert ... BUseSupportedRHIRenderer` | Environmental; the script retries once. Rendered and network runs must use the full editor (the script does) |
| Video `FAIL ... fps` or the "distinct frames" warning | The machine was too loaded while recording; close other heavy programs and record again |
