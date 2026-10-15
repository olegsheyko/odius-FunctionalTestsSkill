"""Checks functional-test code for cheats: things a player cannot do, used to get past a problem instead of reporting it.

  python lint-test.py                       # all tests of the module (MPFT_*.cpp, network test files)
  python lint-test.py MPFT_KegFill.cpp ...  # given files (names or paths)
  python lint-test.py --pending             # the module files opened in Perforce (p4 opened)

Errors (exit code 1):
  TELEPORT      moving the player or an object by code (SetActorLocation, TeleportTo, SetActorTransform, ...)
                anywhere in a test file. The player gets somewhere only by walking (AddNavGoTo / AddClimbTo / ...).
  SPAWN-IN-STEP spawning anything inside a step (inside a lambda of AddStep / AddAction / AddWaitUntil / ...):
                items, furniture, ingredients next to the player. The fixture is built ONLY in BuildScenario before the steps.
  SPAWN-ON-MAP  spawning anything in a test on a real map / map copy (it uses BindLevelStation / BindLevelTavern or
                bSpawnFloor = false): such a test uses the level as it is.
  GAME-CALL     calling a game mechanic directly (ServerInteract, ReceiveWort, TryDispenseWort, ...) instead of the
                game's input (keys) - the player cannot do that.
  SCAFFOLD      the "scenario is not written yet" step of new-test.py is still there.
A line can be excused only with a reason the user agreed to:   // lint-ok: <reason>
Exit codes: 0 clean, 1 errors found, 2 setup (files not found).
"""
import argparse
import glob
import os
import re
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))


def find_module():
    env = os.environ.get("FT_PROJECT")
    folder = os.path.dirname(os.path.abspath(env)) if env else HERE
    while True:
        if glob.glob(os.path.join(folder, "*.uproject")):
            return os.path.join(folder, "Source", "MPFunctionalTests")
        parent = os.path.dirname(folder)
        if parent == folder:
            sys.exit("No .uproject found above %s: set FT_PROJECT" % HERE)
        folder = parent


TELEPORT = re.compile(r"\b(SetActorLocation|SetActorLocationAndRotation|SetActorTransform|SetActorRelativeLocation|"
                      r"TeleportTo|K2_TeleportTo|SetWorldLocation|SetWorldLocationAndRotation|SetWorldTransform|"
                      r"SetRelativeLocation|SetPhysicsLinearVelocity|AddImpulse|LaunchCharacter)\s*\(")
SPAWN = re.compile(r"\b(SpawnActor\w*|SpawnFixture\w*|SpawnBlock|SpawnIngredient|BuildCauldronStation|BuildFermenter|"
                   r"SpawnPlayer|SpawnFloor|SpawnDefaultPawnFor|RestartPlayer|DuplicateActor|BeginDeferredActorSpawnFromClass)\s*[<(]")
GAME_CALL = re.compile(r"\b(ServerInteract|ServerPrimary|ServerSecondary|ServerDrop|ServerThrow|ReceiveWort|ReceiveFuel|"
                       r"ReceiveIngredient|TryDispenseWort|TryDispenseBeerForPawn|TryReceiveDispensedItem|InsertItem|"
                       r"ToggleCartHarness|SpawnBeer|SpawnPotion|TryStartBrew|StowHeldItem|SelectSlot)\s*\(")
# The test's own actors (a networked player bot is spawned into its world by the test runner): not game objects.
TEST_ACTOR_SPAWN = re.compile(r"(?<![A-Za-z0-9_])SpawnActor\w*\s*<\s*AMP\w*(Test|Player)\w*\s*>")
STEP_CALL = re.compile(r"\bAdd[A-Z]\w*\s*\(")
LEVEL_TEST = re.compile(r"\bBindLevelStation\s*\(|\bBindLevelTavern\s*\(|bSpawnFloor\s*=\s*false")
SCAFFOLD = "the scenario is not written yet"


def strip_comments(line, in_block):
    """Removes // and /* */ comments (string contents are kept, good enough for these checks)."""
    out, i = "", 0
    while i < len(line):
        if in_block:
            end = line.find("*/", i)
            if end < 0:
                return out, True
            i, in_block = end + 2, False
            continue
        if line.startswith("//", i):
            break
        if line.startswith("/*", i):
            in_block, i = True, i + 2
            continue
        out += line[i]
        i += 1
    return out, in_block


def lint(path):
    with open(path, encoding="utf-8", errors="replace") as f:
        lines = f.read().split("\n")
    errors = []
    level_test = any(LEVEL_TEST.search(l) for l in lines)
    in_block = False
    depth = 0              # brace depth
    lambda_depths = []     # brace depths at which a step lambda body was opened
    pending_lambda = False
    for number, raw in enumerate(lines, 1):
        ok = "lint-ok:" in raw and raw.split("lint-ok:", 1)[1].strip() != ""
        code, in_block = strip_comments(raw, in_block)
        # A lambda handed to a step helper: "AddX(... [captures](args) ... {" (the brace may be on a later line).
        if STEP_CALL.search(code):
            pending_lambda = True
        in_lambda = bool(lambda_depths)
        if not ok:
            if TELEPORT.search(code):
                errors.append((number, "TELEPORT", raw.strip()))
            if SPAWN.search(code) and not TEST_ACTOR_SPAWN.search(code):
                if level_test:
                    errors.append((number, "SPAWN-ON-MAP", raw.strip()))
                elif in_lambda or (pending_lambda and re.search(r"\]\s*\(", code)):
                    errors.append((number, "SPAWN-IN-STEP", raw.strip()))
            if GAME_CALL.search(code):
                errors.append((number, "GAME-CALL", raw.strip()))
            if SCAFFOLD in raw:
                errors.append((number, "SCAFFOLD", raw.strip()))
        for ch in code:
            if ch == "{":
                depth += 1
                if pending_lambda:
                    lambda_depths.append(depth)
                    pending_lambda = False
            elif ch == "}":
                if lambda_depths and lambda_depths[-1] == depth:
                    lambda_depths.pop()
                depth -= 1
        if ";" in code and not lambda_depths:
            pending_lambda = False
    return errors


def main():
    p = argparse.ArgumentParser()
    p.add_argument("files", nargs="*")
    p.add_argument("--pending", action="store_true", help="lint the module files opened in Perforce")
    a = p.parse_args()
    module = find_module()
    if a.pending:
        try:
            out = subprocess.run(["p4", "-ztag", "-F", "%clientFile%", "opened"], capture_output=True, text=True, cwd=module).stdout
        except OSError:
            sys.exit("p4 not found")
        files = [f for f in out.split() if f.endswith(".cpp") and os.path.normcase(os.path.dirname(f)) == os.path.normcase(module)]
    elif a.files:
        files = [f if os.path.isabs(f) else (f if os.path.exists(f) else os.path.join(module, f)) for f in a.files]
    else:
        files = sorted(glob.glob(os.path.join(module, "MPFT_*.cpp"))) + \
                [os.path.join(module, n) for n in ("MPNetCoopPlayer.cpp", "MPNetTavernCoopTest.cpp") if os.path.exists(os.path.join(module, n))]
    missing = [f for f in files if not os.path.isfile(f)]
    if missing:
        print("not found: " + ", ".join(missing))
        sys.exit(2)
    total = 0
    for path in files:
        errors = lint(path)
        total += len(errors)
        name = os.path.basename(path)
        if not errors:
            print("ok    %s" % name)
        for number, kind, text in errors:
            print("ERROR %s:%d  %-13s %s" % (name, number, kind, text[:160]))
    if total:
        print("\n%d problem(s). These are cheats: a player cannot do them. Do not hide them - fix the test the way a player"
              " would, or STOP and report the obstacle to the user. '// lint-ok: <reason>' only with the user's consent." % total)
        sys.exit(1)
    print("\nclean: %d file(s)" % len(files))


if __name__ == "__main__":
    main()
