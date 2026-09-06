#!/usr/bin/env python3
"""
export_graph.py — Export Mnemon knowledge graph to graph.json for the 3D viewer.

Reads the sqlite DB directly (schema-verified) and emits {nodes, edges, meta}.
Usage: python3 export_graph.py [path-to-mnemon.db] [-o out.json]
"""
import json
import os
import re
import sqlite3
import sys
from datetime import datetime, timezone

CATEGORY = ["decision", "context", "fact", "insight", "general"]
SHORT_LEN = 42


def short_label(content: str) -> str:
    s = " ".join(content.split())
    # Strip common wiki prefixes for cleaner labels
    for p in ("Wiki: ", "CI Debugging "):
        if s.startswith(p):
            s = s[len(p):]
            break
    return (s[:SHORT_LEN] + "…") if len(s) > SHORT_LEN else s


def main():
    args = sys.argv[1:]
    db = os.path.expanduser("~/.mnemon/data/default/mnemon.db")
    out = os.path.join(os.path.dirname(os.path.abspath(__file__)), "graph.json")
    i = 0
    while i < len(args):
        if args[i] == "-o" and i + 1 < len(args):
            out = args[i + 1]
            i += 2
        elif not args[i].startswith("-"):
            db = os.path.expanduser(args[i])
            i += 1
        else:
            i += 1

    con = sqlite3.connect(f"file:{db}?mode=ro", uri=True)
    con.row_factory = sqlite3.Row

    rows = con.execute("""
        SELECT id, content, category, importance, effective_importance,
               tags, entities, source, created_at, access_count
        FROM insights WHERE deleted_at IS NULL
    """).fetchall()

    nodes = {}
    for r in rows:
        cat = r["category"] if r["category"] in CATEGORY else "general"
        try:
            tags = json.loads(r["tags"])
        except (TypeError, ValueError):
            tags = []
        try:
            entities = json.loads(r["entities"])
        except (TypeError, ValueError):
            entities = []
        nodes[r["id"]] = {
            "id": r["id"],
            "label": short_label(r["content"]),
            "content": r["content"],
            "category": cat,
            "importance": r["importance"],
            "eff": round(r["effective_importance"], 3),
            "tags": tags[:8],
            "entities": entities[:8],
            "source": r["source"],
            "created": r["created_at"],
        }

    edges = []
    for e in con.execute("""
        SELECT source_id, target_id, edge_type, weight FROM edges
    """).fetchall():
        # only edges between live nodes
        if e["source_id"] in nodes and e["target_id"] in nodes:
            edges.append({
                "source": e["source_id"],
                "target": e["target_id"],
                "type": e["edge_type"],
                "weight": round(e["weight"], 3),
            })

    counts = {}
    for r in rows:
        counts[r["category"] if r["category"] in CATEGORY else "general"] = \
            counts.get(r["category"] if r["category"] in CATEGORY else "general", 0) + 1

    data = {
        "meta": {
            "node_count": len(nodes),
            "edge_count": len(edges),
            "by_category": counts,
            "exported_at": datetime.now(timezone.utc).isoformat(),
            "db": os.path.basename(db),
        },
        "nodes": list(nodes.values()),
        "edges": edges,
    }
    with open(out, "w") as f:
        json.dump(data, f, indent=1)
    # file://-safe sibling: a <script src="graph-data.js"> tag is allowed from
    # file:// where fetch() is blocked. Viewer prefers GRAPH_DATA when present.
    out_js = os.path.splitext(out)[0] + "-data.js"
    with open(out_js, "w") as f:
        # JSON must not contain `</script` or the browser ends our <script> tag
        # early (broken viewer / potential injection). Escape the sequence in
        # all case-insensitive forms before embedding into executable JS.
        safe_json = re.sub(r"</script", "<\\/script", json.dumps(data), flags=re.IGNORECASE)
        f.write("window.GRAPH_DATA = " + safe_json + ";\n")
    print(f"Exported {len(nodes)} nodes, {len(edges)} edges -> {out} (+{os.path.basename(out_js)})")


if __name__ == "__main__":
    main()