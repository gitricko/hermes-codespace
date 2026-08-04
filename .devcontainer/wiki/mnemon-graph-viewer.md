# Mnemon Knowledge-Graph Viewer

> Reference: how the 3D knowledge-graph viewer works and how to regenerate it.
> Procedure: see skill `mnemon-graph-export`. Design detail:
> `.devcontainer/tools/knowledge-graph/DESIGN.md`.

## What it is

A self-contained, dark-themed 3D visualization of the Mnemon knowledge graph
(the memories in `~/.mnemon/data/default/mnemon.db`). One HTML file per
renderer, no server needed to view:

- `mnemon-graph.html` — custom 3D viewer (3d-force-graph v1.80.0 / Three.js),
  nodes sized by effective importance, colored by category, HTML category-pill
  labels overlaid per frame, integer importance slider (1–5), category toggles,
  manual auto-rotate, vis.js 2D fallback at `mnemon-viz.html`.

## Pipeline (data flow)

```
~/.mnemon/data/default/mnemon.db
   │  export_graph.py (read-only SQLite)
   ▼
graph.json  ──►  build.py (inlines template + fg2 bundle + data)
   │                 ▼
   │            mnemon-graph.html   (3D artifact, ~1.4 MB)
   └──►  mnemon viz --format html -o mnemon-viz.html  (vis.js fallback)
```

`index.html` is the editable **template** (markers `__FORCE_GRAPH__`,
`__DATA__`); `build.py` substitutes them deterministically (byte-identical
rebuilds, verified). The fg2 bundle is fetched once into `.cache/` (gitignored;
override with `KG_CACHE`).

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
| Custom 3D + built-in vis.js fallback | User asked for 3D; keeping `mnemon viz` output gives an independently-tested renderer for one command |
| No separate three.js inline | Bundle embeds Three r183 (ESM-only, no UMD); mixing a copy = fatal "Multiple instances of Three.js" crash |
| HTML label overlay, not sprite labels | Sprites would need the THREE copy that crashes; `graph2ScreenCoords()` maps graph→screen per frame, crisp DOM text |
| Manual auto-rotate in rAF loop | The vendored fg2 fork exposes no `.autoRotate()` API (internal OrbitControls only); calling it throws and kills `build()` |
| Integer slider 1–5 | Data importance is integer (2–5); `step="0.1"` showed floats |
| linkVisibility accepts object endpoints | Engine resolves link endpoints to node objects; id-only lookup hid all edges on first filter change (user-reported bug, fixed) |
| Verification = real browser render + pixels | Static greps proved file contents but missed blank-page bugs; PIL pixel measurement is the ground truth |

## Regeneration (quick)

```bash
cd .devcontainer/tools/knowledge-graph
python3 export_graph.py      # fresh graph.json
python3 build.py             # -> mnemon-graph.html
mnemon viz --format html -o mnemon-viz.html
cp mnemon-graph.html /tmp/kg-serve/index.html && python3 -m http.server 8123
```

Full steps + pitfalls: skill `mnemon-graph-export`, or DESIGN.md §6.

## Serving trap

`http.server` rooted at the tools dir serves `index.html` = the TEMPLATE →
blank page (unsubstituted markers). Serve a dir whose root IS the built
artifact.

## Related

- Skill: [mnemon-graph-export](../skills/mnemon-graph-export/SKILL.md)
- Design: `.devcontainer/tools/knowledge-graph/DESIGN.md`
- [persistent-knowledge-proposal.md](persistent-knowledge-proposal.md) — how
  memory/skills/wiki persist across rebuilds
