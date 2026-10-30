#!/usr/bin/env python3
"""Query builds.json.

  manifest.py ids [--buildable]      one entry id per line
  manifest.py get <id> <key.path>    a value; lists one item per line, objects as JSON
  manifest.py top <key.path>         a value outside the entries
  manifest.py tag <id>               the release tag
  manifest.py match <cx_version>     the entry id for a CrossOver version (exit 1 if none)
  manifest.py matrix                 GitHub Actions matrix JSON of the buildable entries
"""
import json
import os
import sys

MANIFEST = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "builds.json")


def load():
    with open(os.environ.get("VARBOR_MANIFEST", MANIFEST)) as f:
        return json.load(f)


def entry(m, ident):
    for b in m["builds"]:
        if b["id"] == ident:
            return b
    sys.exit(f"manifest: no entry {ident}")


def lookup(obj, path):
    for k in path.split("."):
        if not isinstance(obj, dict) or k not in obj:
            return None
        obj = obj[k]
    return obj


def show(v):
    if v is None:
        return
    if isinstance(v, list):
        for x in v:
            print(x if not isinstance(x, (dict, list)) else json.dumps(x))
    elif isinstance(v, dict):
        print(json.dumps(v))
    elif isinstance(v, bool):
        print("true" if v else "false")
    else:
        print(v)


def tag(m, b):
    return m["release_tag"].replace("{crossover.version}", b["crossover"]["version"])


def main(argv):
    if not argv:
        sys.exit(__doc__)
    m = load()
    cmd = argv[0]
    if cmd == "ids":
        for b in m["builds"]:
            if "--buildable" not in argv or b.get("build"):
                print(b["id"])
    elif cmd == "get" and len(argv) == 3:
        show(lookup(entry(m, argv[1]), argv[2]))
    elif cmd == "top" and len(argv) == 2:
        show(lookup(m, argv[1]))
    elif cmd == "tag" and len(argv) == 2:
        print(tag(m, entry(m, argv[1])))
    elif cmd == "match" and len(argv) == 2:
        for b in m["builds"]:
            if b["crossover"]["version"] == argv[1]:
                print(b["id"])
                return
        sys.exit(1)
    elif cmd == "matrix":
        inc = [{"id": b["id"], "tag": tag(m, b)} for b in m["builds"] if b.get("build")]
        print(json.dumps({"include": inc}))
    else:
        sys.exit(__doc__)


if __name__ == "__main__":
    main(sys.argv[1:])
