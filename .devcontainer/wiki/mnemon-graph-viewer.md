# Mnemon Knowledge-Graph Viewer

> Reference: how the 3D knowledge-graph viewer works and how to regenerate it.
> Procedure: see skill `mnemon-graph-export`. Design detail:
> `.devcontainer/tools/knowledge-graph/DESIGN.md`.

## What it is

A self-contained, dark-themed 3D visualization of the Mnemon knowledge graph
(the memories in `~/.mnemon/data/default/mnemon.db`). **Portable design: the
viewer is a fixed asset that loads `graph.json` at open time** — refresh the
graph by replacing the data files, never by rebuilding HTML. Works two ways:
**double-click the HTML** (file://, data comes from `graph-data.js`) or **serve
it over http** (data fetched from `graph.json`).

- `mnemon-graph.html` — static 3D viewer (3d-force-graph v1.80.0 / Three.js),
  nodes sized by effective importance, colored by category, HTML category-pill
  labels overlaid per frame, integer importance slider (1–5), category toggles,
  manual auto-rotate. Loads `window.GRAPH_DATA` (from `graph-data.js`) or
  `?data=path.json` / `graph.json` via fetch.
- `graph-data.js` — `window.GRAPH_DATA = {…};`, the file://-safe data sibling.

## Pipeline (data flow)

```
~/.mnemon/data/default/mnemon.db
   │  export_graph.py (read-only SQLite + enrichment)
   ▼
graph.json ────────────►  mnemon-graph.html (STATIC viewer)
graph-data.js ──────────►   file://  (script tag, GRAPH_DATA)
```

Load priority in the viewer: `GRAPH_DATA` (script tag) → `?data=` → `graph.json`.
`template.html` is the editable **template** (marker `__FORCE_GRAPH__`);
`build.py` vendors the fg2 library into `mnemon-graph.html` — run it once (or
when the template changes), **never for data refresh**. `index.html` is a tiny
meta-refresh forwarder to `mnemon-graph.html`, so the server root URL works
without knowing the artifact filename. The fg2 bundle is fetched once into
`.cache/` (gitignored; override with `KG_CACHE`).

## Data model

- Node: id, 42-char label, content, category (decision/context/fact/insight/
  general, unknown → general), importance 1–5, effective importance, tags,
  entities, source, created.
- Edge: source/target ids, type (temporal/semantic/causal/entity), weight.
- Only edges between live (non-deleted) nodes are exported.
- Live DB (2026-08): 69 nodes / 1428 edges; committed graph.json may lag —
  regenerate to refresh.

## Key design decisions (why it looks like this)

| Decision | Rationale |
|---|---|
| **Viewer loads graph.json at runtime (portable)** | Data/viewer decoupling: refresh = replace data files, never rebuild. Same viewer renders any store/snapshot (`?data=`). Dual load path: `graph-data.js` script tag for file:// double-click, fetch for http — both verified |
| Custom 3D viewer (no vis.js fallback) | User asked for 3D; the vis.js fallback (`mnemon viz` output) was dropped as redundant once the 3D viewer was pixel-verified — one renderer, one pipeline |
| No separate three.js inline | Bundle embeds Three r183 (ESM-only, no UMD); mixing a copy = fatal "Multiple instances of Three.js" crash |
| HTML label overlay, not sprite labels | Sprites would need the THREE copy that crashes; `graph2ScreenCoords()` maps graph→screen per frame, crisp DOM text |
| Manual auto-rotate in rAF loop | The vendored fg2 fork exposes no `.autoRotate()` API (internal OrbitControls only); calling it throws and kills `build()` |
| Integer slider 1–5 | Data importance is integer (2–5); `step="0.1"` showed floats |
| linkVisibility accepts object endpoints | Engine resolves link endpoints to node objects; id-only lookup hid all edges on first filter change (user-reported bug, fixed) |
| **Force layout controls exposed in UI** | Dense graphs squish into a ball; sliders for link distance, repulsion strength, min distance + Reheat button let you tune spread live per dataset — no rebuild, no hardcoded values |
| Verification = real browser render + pixels | Static greps proved file contents but missed blank-page bugs; PIL pixel measurement is the ground truth |
| **Auto force-layout on load** | `computeAutoForces()` derives link distance / charge strength / charge min from canvas size + node/edge counts so the graph spreads instead of blob — but see pitfalls 12-13 below: a leading-dot chain after `;` is a JS SyntaxError that kills the whole script, and duplicate function declarations shadow each other |
| **Bubble size** | fg2 radius = `cbrt(nodeVal) * nodeRelSize`; nodeRelSize(3) keeps bubbles small so the graph reads as spread out, not zoomed-in on a giant sphere |
| **Auto-rotate orbits cluster center** | spinCam rotates around `getGraphBbox()` midpoint with `lookAt(tx,ty,tz)`, not the origin — otherwise the framed view drifts during rotation |

## Regeneration (quick)

```bash
cd .devcontainer/tools/knowledge-graph
python3 export_graph.py      # fresh graph.json + graph-data.js (the ONLY refresh step)
python3 -m http.server 8130  # optional: serve; or just double-click mnemon-graph.html
```

`python3 build.py` only when `template.html` (the template) changes.
Full steps + pitfalls: skill `mnemon-graph-export`, or DESIGN.md §6.

## Serving

`index.html` meta-refreshes to `mnemon-graph.html` — so `http://host:8130/`
just works, no need to know the artifact filename. Never serve `template.html`
as the root (unsubstituted markers → blank page). For file:// double-click,
keep `graph-data.js` next to the viewer (browsers block `fetch()` from
file://, so the script tag is the data path there).

## Related

- Skill: [mnemon-graph-export](../skills/mnemon-graph-export/SKILL.md)
- Design: `.devcontainer/tools/knowledge-graph/DESIGN.md`
- [persistent-knowledge-proposal.md](persistent-knowledge-proposal.md) — how
  memory/skills/wiki persist across rebuilds
