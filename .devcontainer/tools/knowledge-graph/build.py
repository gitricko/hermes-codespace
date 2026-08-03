#!/usr/bin/env python3
"""build.py — Inline ForceGraph3D (3D) + graph.json into a single self-contained HTML.

Produces mnemon-graph.html next to this script. The 3d-force-graph bundle is
fetched once into a local cache dir and reused; graph.json is read from the same
dir as this script (produced by export_graph.py).
"""
import json
import os
import sys
import urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
TEMPLATE = os.path.join(HERE, "index.html")
OUT = os.path.join(HERE, "mnemon-graph.html")
DATA = os.path.join(HERE, "graph.json")

# Where the 3d-force-graph bundle is cached. Defaults to a sibling cache dir so
# a fresh clone can fetch it on first build; override with KG_CACHE env var.
CACHE_DIR = os.environ.get("KG_CACHE", os.path.join(HERE, ".cache"))
FG_URL = "https://unpkg.com/3d-force-graph@1.80.0/dist/3d-force-graph.min.js"
FG_FILE = os.path.join(CACHE_DIR, "fg2.js")


def fetch(url: str, dest: str) -> None:
    print(f"Downloading {url}")
    with urllib.request.urlopen(url, timeout=60) as r, open(dest, "wb") as f:
        f.write(r.read())


def load_fg() -> str:
    if not os.path.exists(FG_FILE):
        os.makedirs(CACHE_DIR, exist_ok=True)
        try:
            fetch(FG_URL, FG_FILE)
        except Exception as e:  # offline or blocked: surface clearly
            raise SystemExit(f"Could not fetch {FG_URL}: {e}\n"
                             f"Place the bundle at {FG_FILE} and re-run.")
    return open(FG_FILE, encoding="utf-8", errors="replace").read()


def main():
    if not os.path.exists(DATA):
        raise SystemExit(f"Missing {DATA} — run export_graph.py first.")
    if not os.path.exists(TEMPLATE):
        raise SystemExit(f"Missing {TEMPLATE}.")

    html = open(TEMPLATE, encoding="utf-8").read()

    # 1) three.js — intentionally NOT inlined: 3d-force-graph v1.80 bundles its
    #    own Three (r183) internally. Inlining a separate copy causes a fatal
    #    'Multiple instances of Three.js' clash, so we rely on the bundled
    #    renderer + graph2ScreenCoords() for the HTML label overlay. (The
    #    <!-- __THREE__ --> marker stays as a harmless HTML comment.)

    # 2) force-graph-3d
    if "__FORCE_GRAPH__" in html:
        fg = load_fg()
        html = html.replace(
            "<!-- __FORCE_GRAPH__ -->",
            "<script>/* 3d-force-graph v1.80.0 (MIT) */\n" + fg + "\n</script>")

    # 3) data
    if "__DATA__" in html:
        data = open(DATA, encoding="utf-8").read()
        html = html.replace("/* __DATA__ */", "DATA = " + data + ";\n")

    with open(OUT, "w", encoding="utf-8") as f:
        f.write(html)
    print(f"Built {OUT} ({os.path.getsize(OUT)/1024:.0f} KB)")


if __name__ == "__main__":
    main()