# Upstream bug report for OmniRoute repo

> **File via:** https://github.com/diegosouzapw/OmniRoute/issues/new/choose → Bug Report
> They use a YAML form template with structured fields. This document is organized
> per-field for easy copy-paste into the GitHub form.

---

## Before you file

- Searched open issues (173) and closed issues (2,368) — **not reported yet**.
- Keywords checked: `dist/node_modules`, `undici`, `hollow`, `MCP server`, 
  `bundled deps missing` — no matches.

---

## Field-by-field values for the Bug Report form

### OmniRoute Version
```
3.8.48
```

### Installation Method
```
npm (global)
```

### Operating System
```
Linux
```

### OS Version
```
Ubuntu 24.04 (noble), amd64
```

### Node.js Version
```
v24.14.0
```

### Provider(s) Involved
```
N/A — this is a packaging/build issue, not a provider issue
```

### Model(s) Involved
```
N/A
```

### Client Tool
```
Any MCP client that connects to OmniRoute's built-in MCP server.
Observed with: Hermes Agent (via stdio MCP transport), though any MCP client
connecting to `omniroute --mcp` will hit the same crash.
```

### Description
```
The published omniroute npm package ships an incomplete `dist/node_modules/`
directory. Several bundled dependency packages contain ONLY a `package.json`
stub with zero JavaScript, native (.node), or shared-object (.so) files.

When OmniRoute's MCP server (`dist/open-sse/mcp-server/server.js`) starts, it
imports from `dist/node_modules/` and crashes immediately:

```
Error: Cannot find package '.../dist/node_modules/undici/index.js'
  imported from .../dist/open-sse/mcp-server/server.js
```

Any MCP client connecting to `omniroute --mcp` gets `Connection closed` and
the server is unusable out of the box.

**Hollow packages (dist/node_modules/<pkg/> with only package.json, no code):**
Groups by repairability:

1. **Hollow + full sibling exists in `node_modules/` — break the MCP server:**
   - `undici` — fatal crash on MCP server startup
   - `ioredis`
   - `@atjsh/llmlingua-2`
   - `sql.js`
   - `sqlite-vec-linux-x64` (missing native `vec0.so`)

2. **Hollow + no sibling copy — not directly imported from dist (currently harmless):**
   - `lru-cache`, `mdn-data`, `@csstools/css-syntax-patches-for-csstree`
```

### Steps to Reproduce
```
1. npm install omniroute@3.8.48 -g --prefix /usr/local/lib/omniroute
2. Run the MCP server:
     node /usr/local/lib/omniroute/lib/node_modules/omniroute/dist/open-sse/mcp-server/server.js --mcp
3. Observe crash:
     Error: Cannot find package '.../dist/node_modules/undici/index.js'
   imported from .../dist/open-sse/mcp-server/server.js

Alternative MCP-client-level reproduction:
1. Install omniroute via npm and configure it as an MCP server in any MCP client
2. Attempt to connect — client reports "Connection closed"
3. Check stderr — same `Cannot find package undici` error
```

### Expected Behavior
```
Starting `omniroute --mcp` should print:
  [MCP] OmniRoute MCP Server starting (stdio transport)...
  [MCP] OmniRoute MCP Server connected and ready.

All dependencies in `dist/node_modules/` should be complete — the bundled
dependency tree that the published code actually imports from must ship with
all executable files, not just manifest stubs.
```

### Actual Behavior
```
The MCP server crashes on startup because `dist/node_modules/undici/index.js`
does not exist — only the package.json was shipped in the npm tarball.

Hermes Agent (and likely other MCP clients) auto-saves the server as disabled
after the failed connection, requiring manual repair.
```

### Test Impact
```
Needs a new integration test
```

### Error Logs / Output
```
===== starting MCP server 'omniroute' =====
📋 Loaded env from /home/codespace/.omniroute/.env
📋 Loaded env from /usr/local/lib/omniroute/lib/node_modules/omniroute/.env

Error: Cannot find package '/usr/local/lib/omniroute/lib/node_modules/omniroute/dist/node_modules/undici/index.js'
  imported from /usr/local/lib/omniroute/lib/node_modules/omniroute/dist/open-sse/mcp-server/server.js

(Among the hollow packages: undici version 8.7.0 only has a package.json stub
 — 0 JS files shipped in the tarball's dist/node_modules/undici/)

After manual repair (copy sibling node_modules/undici → dist/node_modules/undici):
  [MCP] OmniRoute MCP Server starting (stdio transport)...
  [MCP] OmniRoute MCP Server connected and ready.
  ✓ Tools discovered: 99
```

### Screenshots
```
N/A — the error is textual and fully captured in the logs above.
```

### Additional Context
```
Root cause analysis:

The runtime differentiates between two `node_modules` trees:
- `omniroute/node_modules/<pkg>` — populated correctly by npm's standard
  dependency resolution.
- `omniroute/dist/node_modules/<pkg>` — a bundled dependency tree that the
  published code imports from. This is assembled by a build/bundling step.

In the 3.8.48 tarball, the bundling step emitted `package.json` stubs for many
packages without copying their actual payload files (`index.js`, `lib/**`,
`*.node`, `*.so`). npm's own resolution in the sibling `node_modules/` is
correct and complete — the defect is limited to the build step that produces
`dist/node_modules/`.

The fact that `lru-cache`, `mdn-data`, and `@csstools/css-syntax-patches-for-csstree`
are hollow AND have no sibling suggests they're genuinely unused dead weights,
but the rest (undici, ioredis, etc.) ARE used at runtime.
```

### Validation Plan
```
1. `npm pack` → extract tarball → verify every directory under
   dist/node_modules/ contains at least one *.js or *.mjs file (or a .node/.so
   for native packages).
2. `node dist/open-sse/mcp-server/server.js --mcp` must print "connected and
   ready" without throwing.
3. Register with an MCP client → `hermes mcp test omniroute` reports
   "✓ Connected" and tool discovery succeeds.
```

---

## Workaround (for anyone hitting this before the fix)

```bash
# After `npm install omniroute`, run this to repair hollow dist deps:
DIST="/usr/local/lib/omniroute/lib/node_modules/omniroute/dist/node_modules"
PARENT="/usr/local/lib/omniroute/lib/node_modules/omniroute/node_modules"
for dst in "$DIST"/*/ "$DIST"/@*/*/; do
  [ -d "$dst" ] || continue
  # Skip scope dirs themselves
  case "$(basename "$dst")" in @*) [ -f "$dst/package.json" ] || continue ;; esac
  code=$(find "$dst" \( -name '*.js' -o -name '*.mjs' -o -name '*.cjs' -o -name '*.node' -o -name '*.so' \) -type f | head -1)
  [ -n "$code" ] && continue
  rel="${dst#"$DIST"/}"
  src="$PARENT/$rel"
  [ -d "$src" ] || continue
  src_code=$(find "$src" \( -name '*.js' -o -name '*.mjs' -o -name '*.cjs' -o -name '*.node' -o -name '*.so' \) -type f | head -1)
  [ -n "$src_code" ] || continue
  sudo rm -rf "$dst"
  sudo cp -r "$src" "$dst"
  echo "Repaired: $rel"
done
```
