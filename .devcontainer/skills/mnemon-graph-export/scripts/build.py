#!/usr/bin/env python3
"""build.py — Vendor the ForceGraph3D library into a static viewer HTML.

Produces mnemon-graph.html next to this script: the template (template.html)
plus the 3d-force-graph bundle, fetched once into a local cache dir and
reused. Data is NOT inlined — the viewer fetches graph.json at load time
(portable design), so refreshing the graph never requires a rebuild.

Run once (or when template.html changes); graph refreshes only need
export_graph.py to replace graph.json next to the viewer.
"""
import os
import urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
TEMPLATE = os.path.join(HERE, "template.html")
OUT = os.path.join(HERE, "mnemon-graph.html")

# Where the 3d-force-graph bundle is cached. Defaults to a sibling cache dir so
# a fresh clone can fetch it on first build; override with KG_CACHE env var.
CACHE_DIR = os.environ.get("KG_CACHE", os.path.join(HERE, ".cache"))
FG_URL = "https://unpkg.com/3d-force-graph@1.80.0/dist/3d-force-graph.min.js"
FG_FILE = os.path.join(CACHE_DIR, "fg2.js")
# Pinned SHA-256 of the fg2 bundle (verified against unpkg at vendor time).
FG_SHA256 = "d96e738edcca580edd524730c1c6b05ed2efce028c23ca95db1bf43033a72e42"


def sha256_bytes(b: bytes) -> str:
    import hashlib
    return hashlib.sha256(b).hexdigest()


def fetch(url: str, dest: str) -> None:
    print(f"Downloading {url}")
    with urllib.request.urlopen(url, timeout=60) as r, open(dest, "wb") as f:
        f.write(r.read())


def load_fg() -> str:
    need_fetch = not os.path.exists(FG_FILE)
    if need_fetch:
        os.makedirs(CACHE_DIR, exist_ok=True)
        try:
            fetch(FG_URL, FG_FILE)
        except Exception as e:  # offline or blocked: surface clearly
            raise SystemExit(f"Could not fetch {FG_URL}: {e}\n"
                             f"Place the bundle at {FG_FILE} and re-run.")
    with open(FG_FILE, "rb") as f:
        raw = f.read()
    got = sha256_bytes(raw)
    if got != FG_SHA256:
        raise SystemExit(
            f"Vendored 3d-force-graph bundle fails integrity check.\n"
            f"expected {FG_SHA256}\n     got {got}\n"
            f"File: {FG_FILE}\n"
            f"If you intentionally updated the bundle, update FG_SHA256 "
            f"(verify the new hash against unpkg) and re-run build.py.")
    return raw.decode("utf-8", errors="replace")


def main():
    if not os.path.exists(TEMPLATE):
        raise SystemExit(f"Missing {TEMPLATE}.")

    html = open(TEMPLATE, encoding="utf-8").read()

    # 1) three.js — intentionally NOT inlined: 3d-force-graph v1.80 bundles its
    #    own Three (r183) internally. Inlining a separate copy causes a fatal
    #    'Multiple instances of Three.js' clash, so we rely on the bundled
    #    renderer + graph2ScreenCoords() for the HTML label overlay. (The
    #    <!-- __THREE__ --> marker stays as a harmless HTML comment.)

    # 2) force-graph-3d (vendored once; the viewer is a FIXED asset — data is
    #    fetched at runtime from graph.json, so data changes never need a rebuild)
    if "__FORCE_GRAPH__" in html:
        fg = load_fg()
        html = html.replace(
            "<!-- __FORCE_GRAPH__ -->",
            "<script>/* 3d-force-graph v1.80.0 (MIT) */\n" + fg + "\n</script>")

    # 3) data — deliberately NOT inlined (portable design): the viewer fetches
    #    graph.json at load time. Refresh = replace the JSON, no rebuild.

    with open(OUT, "w", encoding="utf-8") as f:
        f.write(html)
    print(f"Built {OUT} ({os.path.getsize(OUT)/1024:.0f} KB)")


if __name__ == "__main__":
    main()