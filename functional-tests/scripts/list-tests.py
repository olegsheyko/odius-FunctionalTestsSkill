"""Lists the existing functional / network tests and finds the ones that already cover a request (to avoid duplicates).

  python list-tests.py                                  # every test: class, map, how to run, one-line summary
  python list-tests.py --query "beer fermenter guest serve coin"   # best matches first, with the matching steps
  python list-tests.py --query "..." --top 5 --steps 8

What is searched: the class doc comment (what the test does), its step names (TEXT("...") in AddX calls) and the
names of the files / classes / maps / network test methods. Write the query as English keywords of the mechanic and
its synonyms (the code is in English): e.g. "keg barrel fill tap fermenter".
Exit code: 0; 2 when the module is not found.
"""
import argparse
import glob
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
STOP = set("the a an and or of to in on at by for with from is are be it its this that as into then than when while "
           "player players test tests game".split())


def find_root():
    env = os.environ.get("FT_PROJECT")
    folder = os.path.dirname(os.path.abspath(env)) if env else HERE
    while True:
        if glob.glob(os.path.join(folder, "*.uproject")):
            return folder
        parent = os.path.dirname(folder)
        if parent == folder:
            sys.exit(2)
        folder = parent


def doc_before(text, index):
    """The /** ... */ comment that ends right before index (only whitespace / macros in between)."""
    head = text[:index]
    end = head.rfind("*/")
    if end < 0 or head[end + 2:].strip() and not re.fullmatch(r"\s*(UCLASS\([^)]*\)\s*)?", head[end + 2:]):
        return ""
    start = head.rfind("/**", 0, end)
    if start < 0:
        return ""
    body = head[start + 3:end]
    return " ".join(line.strip().lstrip("*").strip() for line in body.splitlines()).strip()


def step_names(text):
    return re.findall(r"\bAdd[A-Z]\w*\s*\(\s*(?:FString::Printf\(\s*)?TEXT\(\"([^\"]+)\"", text)


def words(text):
    return [w for w in re.findall(r"[a-zа-яё0-9]+", text.lower()) if len(w) > 2 and w not in STOP]


def collect(root):
    module = os.path.join(root, "Source", "MPFunctionalTests")
    if not os.path.isdir(module):
        sys.exit(2)
    maps = {}
    script = os.path.join(root, "Scripts", "CreateFunctionalTestMap.py")
    if os.path.exists(script):
        for m in re.finditer(r"\(\s*['\"](/Game/Tests/\w+)['\"],\s*(?:['\"](/Game/[^'\"]+)['\"],\s*)?['\"]/Script/MPFunctionalTests\.(\w+)['\"]",
                             open(script, encoding="utf-8").read()):
            maps[m.group(3)] = (m.group(1), m.group(2))
    tests = []
    for header in sorted(glob.glob(os.path.join(module, "MPFT_*.h"))):
        name = os.path.splitext(os.path.basename(header))[0]
        h = open(header, encoding="utf-8", errors="replace").read()
        cls = re.search(r"class\s+\w+_API\s+(A\w+)", h)
        doc = doc_before(h, cls.start()) if cls else ""
        cpp_path = header[:-2] + ".cpp"
        cpp = open(cpp_path, encoding="utf-8", errors="replace").read() if os.path.exists(cpp_path) else ""
        map_path, source = maps.get(name, ("?", None))
        tests.append({
            "kind": "functional", "name": name, "file": os.path.relpath(header, root).replace("\\", "/"),
            "map": map_path + (" (copy of %s)" % source if source else ""),
            "run": "Project.Functional Tests.Tests.%s" % map_path.rsplit("/", 1)[-1],
            "doc": doc, "steps": step_names(cpp),
        })
    for path in sorted(glob.glob(os.path.join(module, "*.cpp"))):
        text = open(path, encoding="utf-8", errors="replace").read()
        for m in re.finditer(r"NETWORK_TEST_CLASS\(\s*(\w+)\s*,\s*\"([^\"]+)\"\s*\)", text):
            end = text.find("\n};", m.end())
            body = text[m.end():end if end > 0 else len(text)]
            methods = re.findall(r"TEST_METHOD\(\s*(\w+)\s*\)", body)
            steps = re.findall(r"\.(?:Then|Until)\(\s*TEXT\(\"([^\"]+)\"", body)
            tests.append({
                "kind": "network", "name": m.group(1), "file": os.path.relpath(path, root).replace("\\", "/"),
                "map": "network PIE (listen server + clients)",
                "run": "%s.%s" % (m.group(2), m.group(1)), "doc": doc_before(text, m.start()),
                "steps": methods + steps,
            })
    return tests


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--query", default="")
    p.add_argument("--top", type=int, default=6)
    p.add_argument("--steps", type=int, default=6, help="matching step names to show per test")
    a = p.parse_args()
    root = find_root()
    tests = collect(root)
    if not a.query:
        for t in tests:
            print("%-28s %-10s %s\n    run: %s\n    map: %s\n    %s\n" % (t["name"], t["kind"], t["file"], t["run"], t["map"], t["doc"][:300]))
        print("%d tests" % len(tests))
        return
    query = set(words(a.query))
    scored = []
    for t in tests:
        doc_words = words(t["doc"] + " " + t["name"])
        step_hits = [s for s in t["steps"] if query & set(words(s))]
        hit_words = query & (set(doc_words) | set(w for s in t["steps"] for w in words(s)))
        score = len(hit_words) * 10 + len(step_hits)
        if score:
            scored.append((score, t, sorted(hit_words), step_hits))
    scored.sort(key=lambda x: -x[0])
    if not scored:
        print("No existing test matches: %s" % ", ".join(sorted(query)))
        return
    print("Query words: %s\n" % ", ".join(sorted(query)))
    for score, t, hit_words, step_hits in scored[:a.top]:
        print("%-28s score %-4d %s   (matched: %s)" % (t["name"], score, t["file"], ", ".join(hit_words)))
        print("    run: %s" % t["run"])
        print("    map: %s" % t["map"])
        print("    what it does: %s" % (t["doc"][:400] or "(no doc comment)"))
        for s in step_hits[:a.steps]:
            print("    step: %s" % s)
        print()
    print("A high score means the request may already be covered: show it to the user and ask before writing a new test.")


if __name__ == "__main__":
    main()
