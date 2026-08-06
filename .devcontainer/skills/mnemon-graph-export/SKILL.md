---
name: mnemon-graph-export
description: "Use when exporting/regenerating the Mnemon knowledge graph."
---

# Mnemon Knowledge-Graph Export (3D viewer regeneration)

Regenerate the 3D knowledge-graph viewer from the latest Mnemon data. The tool
lives in `.devcontainer/tools/knowledge-graph/`; the pipeline is
`export_graph.py -> graph.json (+graph-data.js)`, and the STATIC viewer
(`mnemon-graph.html`) loads the data on open — **data refresh never rebuilds
the viewer**. It works both by double-clicking the HTML (file://, via
`graph-data.js`) and over http (fetch). Plus Mnemon's own `viz` command for
the vis.js fallback. Design rationale: see
`.devcontainer/tools/knowledge-graph/DESIGN.md`; wiki reference:
`.devcontainer/wiki/mnemon-graph-viewer.md`.

## Trigger

User says anything like: "export mnemon graph", "regenerate/show my knowledge
graph", "update the 3D viewer", "new graph from mnemon".

## Steps (verified end-to-end 2026-08)

```bash
cd .devcontainer/tools/knowledge-graph

# 1) Fresh snapshot from the live DB (read-only SQLite) -> graph.json
#    (+ graph-data.js, the file://-safe sibling — keep both in sync)
python3 export_graph.py
#    -> "Exported N nodes, M edges -> graph.json (+graph-data.js)"

# 2) DONE — the viewer is a fixed asset; it loads the data on open.
#    Double-click mnemon-graph.html (file://, uses graph-data.js) or serve:
python3 -m http.server 8123 --bind 0.0.0.0   # then http://localhost:8123/ (index.html forwards)

# 3) Regenerate the vis.js fallback (optional but keep in sync)
mnemon viz --format html -o mnemon-viz.html
#    -> "written to mnemon-viz.html"

# 4) Commit the refreshed data (viewer only changes when template.html does)
git add graph.json graph-data.js mnemon-viz.html
git -c commit.gpgsign=false commit -m "chore(knowledge-graph): refresh graph from latest mnemon export"
```

Rebuild the viewer ONLY when the template (`template.html`) changes — re-vendors
the fg2 library into `mnemon-graph.html`; does not touch data:

```bash
python3 build.py   # first run fetches 3d-force-graph into .cache/
```

Non-default DB/store: `python3 export_graph.py <path-to-db> -o out.json`;
`mnemon viz` honors `--store` / `MNEMON_DATA_DIR` env. Point the viewer at any
JSON with `mnemon-graph.html?data=other.json`.

## Verification (MANDATORY — the user's standard)

Static greps / `node --check` are NOT verification. Prove it renders:

1. **file:// mode** (the user-reported failure): copy `mnemon-graph.html` +
   `graph-data.js` to a fresh dir, open the HTML via `file://` in a headless
   browser — subtitle must read "N memories, M connections" with NO server.
2. **http mode**: serve a dir with viewer + `graph.json` (no `graph-data.js`),
   open `/mnemon-graph.html` — same subtitle (fetch path).
3. Assert category label pills == node count (`.nl` elements in `#labels`).
4. Move the importance slider to 5: node count drops to importance-5 nodes,
   edges stay visible between remaining nodes (the linkVisibility bug).
5. Prove portability: swap the data (or use `?data=other.json`) and confirm
   the subtitle changes with NO rebuild.

If any check fails, debug the viewer (see pitfalls), never ship unverified.

## Pitfalls (all hit and fixed; do not re-derive)

1. **file:// fetch blocked** (user-reported "Cannot load graph.json"): browsers
   block `fetch()` from `file://`. The viewer loads data via a
   `<script src="graph-data.js">` tag (allowed from file://), falling back to
   fetch. ALWAYS regenerate `graph-data.js` together with `graph.json`
   (`export_graph.py` writes both).
2. **Serving**: `index.html` is a meta-refresh forwarder to
   `mnemon-graph.html`, so `http://host:8123/` just works — no need to know
   the artifact filename. Never serve the TEMPLATE (`template.html`) as the
   root: it still has unsubstituted markers and renders blank.
3. **Never inline a separate three.js copy** next to the fg2 bundle: fatal
   "Multiple instances of Three.js" crash, `ForceGraph3D` undefined. The bundle
   embeds its own Three r183 (which ships no UMD build anyway).
4. **No `.autoRotate()`** on the vendored fg2 fork — it throws mid-`build()`
   and silently kills everything after it. Use manual orbit in the rAF loop
   (`spinAngle += 0.0008; camera.position.x = r*sin(a); camera.position.z =
   r*cos(a); camera.lookAt(0,0,0)`), gated by a `spin` flag.
5. **linkVisibility endpoints**: after the engine settles, `l.source`/
   `l.target` are node OBJECTS, not string ids. Predicate must accept both:
   `typeof l.source === 'object' ? l.source : nodes.find(x => x.id ===
   l.source)`. The id-only version hides ALL edges on the first slider move.
6. **`graph2ScreenCoords(x,y,z)` returns `{x,y}` only** (no z field) — any
   depth-culling on `p.z` hides every label. Labels are never culled (known
   limitation).
7. **Slider must be integer**: `min="1" max="5" step="1"` — data importance is
   integer (currently 2-5); `step="0.1"` showed "2.6" style floats.
8. **Repo is PUBLIC** — graph.json embeds memory content. Review the export for
   secrets/PII before committing (content mirrors committed wiki + seed.json,
   but re-scan anyway).
9. **Generated data files should be gitignored**: `graph.json` and `graph-data.js`
   are refreshed by `export_graph.py` on every regeneration. Add them to
   `.gitignore` to avoid commit noise and conflicts — users run the export once
   after clone to get a local graph.
10. **Dense graphs squish together**: with many edges (e.g. 25 nodes / 372 edges),
    the default d3 force parameters pull everything into a tight ball. The fix
    is exposing force controls in the UI: link distance, charge strength,
    charge distanceMin, plus a "Reheat simulation" button calling
    `d3ReheatSimulation()`. This lets you tune spread per dataset without
    rebuilds. See `references/force-controls.md` for the implementation.
11. Browser caching: after rebuild + copy, hard-reload or cache-bust
    (`?v=N`); the page may otherwise serve a stale artifact.
12. **Leading-dot chain after `;` = silent total failure**: applying forces
    with `...cameraPosition(...);\n.d3Force('link').distance(x)` is a JS
    SyntaxError (`.d3Force` has no receiver) — the ENTIRE app `<script>`
    dies: no auto-layout, no labels, no visible error. User just sees
    "no change". Force application MUST be separate statements:
    `Graph.d3Force('link').distance(x);`. Always `node --check` the
    extracted app script after editing the template.
13. **Duplicate function declarations shadow each other**: two
    `computeAutoForces()` definitions (one added in a new section, one left
    in the old build section) — JS hoisting makes the LAST one win. After
    editing, `grep -c "function computeAutoForces"` must be 1.
14. **Bubble size**: fg2 sphere radius = `Math.cbrt(nodeVal) * nodeRelSize`
    (verified in bundle). nodeRelSize 12 with val up to 19 → radius ~21
    units = giant bubbles that read as "zoom too big". Use nodeRelSize(3)
    and keep effToVal small (3..19): radius ~8 units max.
15. **Auto-rotate orbit center**: spinCam must orbit the graph CLUSTER
    center (`Graph.getGraphBbox()` midpoint), NOT the origin — otherwise
    auto-rotate swings the framed view off-center and the graph appears to
    drift/cluster. Camera must lookAt(tx,ty,tz).