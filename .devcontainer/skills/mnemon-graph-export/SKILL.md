---
name: mnemon-graph-export
description: "Use when the user asks to export/regenerate/show the Mnemon knowledge graph. Runs export_graph.py -> build.py -> mnemon viz, serves, and commits."
---

# Mnemon Knowledge-Graph Export (3D viewer regeneration)

Regenerate the 3D knowledge-graph viewer from the latest Mnemon data. The tool
lives in `.devcontainer/tools/knowledge-graph/`; the pipeline is
`export_graph.py -> graph.json`, and the STATIC viewer (`mnemon-graph.html`)
fetches `graph.json` at load time — **data refresh never rebuilds the viewer**.
Plus Mnemon's own `viz` command for the vis.js fallback. Design rationale: see
`.devcontainer/tools/knowledge-graph/DESIGN.md`; wiki reference:
`.devcontainer/wiki/mnemon-graph-viewer.md`.

## Trigger

User says anything like: "export mnemon graph", "regenerate/show my knowledge
graph", "update the 3D viewer", "new graph from mnemon".

## Steps (verified end-to-end 2026-08)

```bash
cd .devcontainer/tools/knowledge-graph

# 1) Fresh snapshot from the live DB (read-only SQLite) -> graph.json
python3 export_graph.py
#    -> "Exported N nodes, M edges -> graph.json"

# 2) DONE — the viewer is a fixed asset; it fetches graph.json at load.
#    Serve the directory containing viewer + JSON:
python3 -m http.server 8123 --bind 0.0.0.0   # then http://localhost:8123/mnemon-graph.html

# 3) Regenerate the vis.js fallback (optional but keep in sync)
mnemon viz --format html -o mnemon-viz.html
#    -> "written to mnemon-viz.html"

# 4) Commit the refreshed data (viewer only changes when index.html does)
git add graph.json mnemon-viz.html
git -c commit.gpgsign=false commit -m "chore(knowledge-graph): refresh graph from latest mnemon export"
```

Rebuild the viewer ONLY when the template (`index.html`) changes — re-vendors
the fg2 library into `mnemon-graph.html`; does not touch data:

```bash
python3 build.py   # first run fetches 3d-force-graph into .cache/
```

Non-default DB/store: `python3 export_graph.py <path-to-db> -o out.json`;
`mnemon viz` honors `--store` / `MNEMON_DATA_DIR` env. Point the viewer at any
JSON with `mnemon-graph.html?data=other.json`.

## Verification (MANDATORY — the user's standard)

Static greps / `node --check` are NOT verification. Prove it renders:

1. Load `http://localhost:8123/mnemon-graph.html` in a headless browser.
2. Assert subtitle reads "N memories, M connections" (N = exported node count).
3. Assert category label pills == node count (`.nl` elements in `#labels`).
4. Move the importance slider to 5: node count drops to importance-5 nodes,
   edges stay visible between remaining nodes (the linkVisibility bug).
5. Prove portability: swap `graph.json` for a different export (or use
   `?data=other.json`) and confirm the subtitle changes with NO rebuild.
6. Optionally measure canvas pixels with PIL (expect ~20-40% drawn).

If any check fails, debug the viewer (see pitfalls), never ship unverified.

## Pitfalls (all hit and fixed; do not re-derive)

1. **Serving trap**: `python3 -m http.server` rooted at the tools dir serves
   `index.html` — the TEMPLATE with unsubstituted markers -> blank page. Serve
   a dir containing the BUILT viewer + `graph.json` and open
   `/mnemon-graph.html`. The viewer fetches the JSON at runtime; file://
   double-click blocks the fetch (browser CORS), so always serve over http.
2. **Never inline a separate three.js copy** next to the fg2 bundle: fatal
   "Multiple instances of Three.js" crash, `ForceGraph3D` undefined. The bundle
   embeds its own Three r183 (which ships no UMD build anyway).
3. **No `.autoRotate()`** on the vendored fg2 fork — it throws mid-`build()`
   and silently kills everything after it. Use manual orbit in the rAF loop
   (`spinAngle += 0.0008; camera.position.x = r*sin(a); camera.position.z =
   r*cos(a); camera.lookAt(0,0,0)`), gated by a `spin` flag.
4. **linkVisibility endpoints**: after the engine settles, `l.source`/
   `l.target` are node OBJECTS, not string ids. Predicate must accept both:
   `typeof l.source === 'object' ? l.source : nodes.find(x => x.id ===
   l.source)`. The id-only version hides ALL edges on the first slider move.
5. **`graph2ScreenCoords(x,y,z)` returns `{x,y}` only** (no z field) — any
   depth-culling on `p.z` hides every label. Labels are never culled (known
   limitation).
6. **Slider must be integer**: `min="1" max="5" step="1"` — data importance is
   integer (currently 2-5); `step="0.1"` showed "2.6" style floats.
7. **Repo is PUBLIC** — graph.json embeds memory content. Review the export for
   secrets/PII before committing (content mirrors committed wiki + seed.json,
   but re-scan anyway).
8. Browser caching: after rebuild + copy, hard-reload or cache-bust
   (`?v=N`); the page may otherwise serve a stale artifact.
