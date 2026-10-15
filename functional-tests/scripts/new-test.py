"""Scaffolds a new functional test: Source/MPFunctionalTests/MPFT_<Name>.h/.cpp from the templates and its map entry
in Scripts/CreateFunctionalTestMap.py. Run with plain Python (not the editor):

  python new-test.py --name KegFill --base brewing --desc "Player fills a keg from the fermenter tap" [--time 180]
  python new-test.py --name TavernNight --base tavern --map-copy /Game/CORE/MAPS/LS_DwarfFort --player-start MP_PlayerStart

--base: functional (AMPFunctionalTest: floor, light, player), brewing (+ cauldron station / fermenter kit),
        tavern (+ guests, order, serving, co-op roles).
--map-copy <source map>: test on a copy of a real map (uses the level's stations; nothing spawned); the test actor
        stands on the PlayerStart labelled --player-start (default MP_PlayerStart).
        Git Bash rewrites /Game/... into C:/Program Files/Git/Game/...: run from PowerShell or with MSYS_NO_PATHCONV=1
        (the script also undoes that rewrite).
--dry-run: print what would be written, write nothing.
All or nothing: every input is validated and every target checked (new files must not exist, the map script must be
writable - in Perforce: p4 edit it first) before anything is written; if a write fails, what was written is removed.
The new files are NOT in Perforce: the script prints the p4 commands to run.
The generated test FAILS (as [setup]) until its scenario is written: an empty scaffold must never pass.
Project: $FT_PROJECT (a .uproject) or the first folder above this script that holds one .uproject.
"""
import argparse
import glob
import os
import re
import sys


def find_project_root():
    env = os.environ.get("FT_PROJECT")
    if env:
        if not os.path.isfile(env):
            sys.exit("FT_PROJECT=%s does not exist" % env)
        return os.path.dirname(os.path.abspath(env))
    folder = os.path.dirname(os.path.abspath(__file__))
    while True:
        found = glob.glob(os.path.join(folder, "*.uproject"))
        if len(found) == 1:
            return folder
        if len(found) > 1:
            sys.exit("Several .uproject files in %s: set FT_PROJECT" % folder)
        parent = os.path.dirname(folder)
        if parent == folder:
            sys.exit("No .uproject found above %s: set FT_PROJECT=<path to .uproject>" % __file__)
        folder = parent


ROOT = find_project_root()
MODULE = os.path.join(ROOT, "Source", "MPFunctionalTests")
MAP_SCRIPT = os.path.join(ROOT, "Scripts", "CreateFunctionalTestMap.py")
TEMPLATES = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "templates")


def cpp_comment(text):
    """Text that is safe inside a /** ... */ comment, one ' * ' line per input line."""
    lines = [line.replace("*/", "* /").rstrip() for line in text.replace("\r", "").split("\n")]
    return "\n * ".join(line for line in lines)

BASES = {
    "functional": ("AMPFunctionalTest", "MPFunctionalTest.h"),
    "brewing": ("AMPBrewingTestBase", "MPBrewingTestBase.h"),
    "tavern": ("AMPTavernTestBase", "MPTavernTestBase.h"),
}


def fixture_code(base, copy):
    lines = []
    if copy:
        lines.append("\t// --- The level is a copy of a real map: use what stands on it, spawn nothing. ---")
        if base in ("brewing", "tavern"):
            lines.append("\tif (!BindLevelStation()) return;   // the level's cauldron, bellows, fuel rack, fermenter; AddGoTo walks its navmesh")
        if base == "tavern":
            lines.append("\tif (!BindLevelTavern()) return;    // the level's tavern manager (kiosk) and brew director (coins)")
        if base in ("brewing", "tavern"):
            lines.append("\tAddWaitStationSettled();")
        else:
            lines.append("\tAddWaitUntilSettled(TEXT(\"Everything lands\"));")
    else:
        lines += [
            "\t// --- Fixture: spawned here, destroyed with the test (SpawnFixtureOfClass / SpawnBlock / AddFixture). ---",
            "\tconst FVector Origin = GetActorLocation();",
            "\t// UClass* Class = SomethingClass.LoadSynchronous();",
            "\t// Something = SpawnFixtureOfClass(Class, Origin + FVector(700.f, 0.f, 0.f), FRotator::ZeroRotator);",
            "\t// if (!CheckSetup(Something != nullptr, TEXT(\"BP_Something not found\"))) return;",
            "\t// AddObserverFocus(Something);",
        ]
        if base in ("brewing", "tavern"):
            lines += [
                "\t// Brewing station kit (AMPBrewingTestBase): cauldron with platform + ramp, bellows, fuel rack; optional fermenter.",
                "\t// if (!BuildCauldronStation(Origin + FVector(1000.f, 0.f, 0.f), Origin + FVector(350.f, -400.f, 0.f))) return;",
                "\t// if (!BuildFermenter()) return;",
                "\t// AddWaitStationSettled();",
            ]
        lines.append("\tAddWaitUntilSettled(TEXT(\"Everything lands\"));")
    return "\n".join(lines) + "\n"


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--name", required=True, help="CamelCase, without the MPFT_ prefix")
    p.add_argument("--base", choices=list(BASES.keys()), default="functional")
    p.add_argument("--desc", default="TODO: what the player does and what is checked.")
    p.add_argument("--time", type=int, default=180, help="TimeLimit, seconds")
    p.add_argument("--map-copy", default="", help="<source map>, e.g. /Game/CORE/MAPS/LS_DwarfFort")
    p.add_argument("--player-start", default="MP_PlayerStart", help="label of the PlayerStart the test actor stands on")
    p.add_argument("--dry-run", action="store_true")
    a = p.parse_args()

    if not re.match(r"^[A-Z][A-Za-z0-9]+$", a.name):
        sys.exit("--name must be CamelCase letters/digits, e.g. KegFill")
    file_name = "MPFT_" + a.name
    base_class, base_header = BASES[a.base]
    map_name = "FTEST_" + a.name
    copy = a.map_copy.strip().replace("\\", "/")
    # Undo Git Bash's path conversion (/Game/X -> C:/Program Files/Git/Game/X).
    mangled = re.match(r"^[A-Za-z]:/.*?/Git(/Game/.*)$", copy)
    if mangled:
        copy = mangled.group(1)
    if copy and not re.match(r"^/Game/[A-Za-z0-9_/]+$", copy):
        sys.exit("--map-copy must be a package path like /Game/CORE/MAPS/LS_DwarfFort (got %s)" % copy)
    if not re.match(r"^[A-Za-z0-9_ .-]+$", a.player_start):
        sys.exit("--player-start must be an actor label (letters, digits, _ . - space), got %r" % a.player_start)
    if not 10 <= a.time <= 3600:
        sys.exit("--time must be 10..3600 seconds")
    for folder, what in ((MODULE, "test module"), (TEMPLATES, "templates")):
        if not os.path.isdir(folder):
            sys.exit("%s folder not found: %s" % (what, folder))
    if not os.path.isfile(MAP_SCRIPT):
        sys.exit("Map script not found: %s" % MAP_SCRIPT)
    ctor = ""
    if copy:
        ctor = ("\t// A copy of a real map: it has its own floor and light; the observer camera is not needed.\n"
                "\tbSpawnFloor = false;\n\tbSpawnLighting = false;\n\tbObserverView = false;\n")
    values = {
        "{{FileName}}": file_name, "{{BaseClass}}": base_class, "{{BaseHeader}}": base_header,
        "{{Description}}": cpp_comment(a.desc), "{{MapName}}": map_name, "{{ShortName}}": a.name,
        "{{TimeLimit}}": str(a.time), "{{CtorExtra}}": ctor, "{{FixtureCode}}": fixture_code(a.base, copy),
        "{{FixtureNote}}": "nothing: it uses the stations, navmesh and guests of the map copy" if copy
                           else "floor, sky and light, the player and the actors under test",
    }

    outputs = []
    for ext in ("h", "cpp"):
        target = os.path.join(MODULE, "%s.%s" % (file_name, ext))
        if os.path.exists(target):
            sys.exit("%s already exists - not overwriting" % target)
        with open(os.path.join(TEMPLATES, "FunctionalTest.%s.template" % ext), encoding="utf-8") as f:
            text = f.read()
        for k, v in values.items():
            text = text.replace(k, v)
        outputs.append((target, text))

    # The script path of a C++ class has no A prefix: /Script/MPFunctionalTests.MPFT_<Name>
    class_path = "/Script/MPFunctionalTests." + file_name
    label = "FT_" + a.name
    with open(MAP_SCRIPT, encoding="utf-8") as f:
        script = f.read()
    if ("/Game/Tests/%s\"" % map_name) in script:
        row, where = None, "already there"
    elif copy:
        # repr() quotes and escapes every value as a Python string literal.
        row = "    (%s, %s, %s, %s, %s),\n" % tuple(repr(v) for v in ("/Game/Tests/" + map_name, copy, class_path, label, a.player_start))
        where = "MAP_COPY_TESTS"
    else:
        row = "    (%s, %s, %s, None),\n" % tuple(repr(v) for v in ("/Game/Tests/" + map_name, class_path, label))
        where = "TESTS"
    new_script = script
    if row:
        new_script, n = re.subn(r"(?m)^%s = \[\n" % where, lambda m: m.group(0) + row, script, count=1)
        if n != 1:
            sys.exit("Could not find '%s = [' in %s" % (where, MAP_SCRIPT))
        if not os.access(MAP_SCRIPT, os.W_OK):
            sys.exit("%s is read-only (Perforce): run  p4 edit \"%s\"  first. Nothing was written." % (MAP_SCRIPT, MAP_SCRIPT))

    if a.dry_run:
        for target, text in outputs:
            print("===== would write %s\n%s" % (target, text))
        print("===== map entry (%s): %s" % (where, row.strip() if row else "-"))
        return

    # All or nothing: write everything to temporary files, then move them in place; undo on any failure.
    staged = [(target, text, "\r\n") for target, text in outputs]
    if row:
        staged.append((MAP_SCRIPT, new_script, ""))
    temps, done = [], []
    try:
        for target, text, newline in staged:
            temp = target + ".new-test.tmp"
            with open(temp, "w", encoding="utf-8", newline=newline) as f:
                f.write(text)
            temps.append((temp, target))
        for temp, target in temps:
            os.replace(temp, target)
            done.append(target)
    except OSError as error:
        for temp, _ in temps:
            if os.path.exists(temp):
                os.remove(temp)
        for target in done:
            if target != MAP_SCRIPT:
                os.remove(target)
        if MAP_SCRIPT in done:
            with open(MAP_SCRIPT, "w", encoding="utf-8", newline="") as f:
                f.write(script)
        sys.exit("Write failed (%s); nothing was left behind." % error)

    for target in done:
        print("written: " + target)
    rel = lambda path: os.path.relpath(path, ROOT).replace("\\", "/")
    print("\nnext:\n  1. write the scenario in %s (until then the test fails as [setup])" % rel(outputs[1][0]))
    print("  2. build: scripts/build.ps1;  create the map: scripts/create-maps.ps1")
    print("  3. Perforce (nothing does it for you):")
    print("     p4 add \"%s\" \"%s\" \"Content/Tests/%s.umap\"" % (rel(outputs[0][0]), rel(outputs[1][0]), map_name))
    print("     p4 opened \"%s\"   (must show edit; if not: p4 edit it)" % rel(MAP_SCRIPT))


if __name__ == "__main__":
    main()
