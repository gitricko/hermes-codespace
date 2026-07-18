# Upstream bug report: `omniroute@3.8.48` npm tarball ships an incomplete `dist/node_modules/` (hollow bundled deps) → MCP server crashes on startup

## Summary

The published `omniroute` npm package (observed on **3.8.48**) contains an
**incomplete `dist/node_modules/` directory**. Several bundled dependency
folders ship with **only a `package.json` stub and no JavaScript/native code**.

Because the runtime imports its bundled deps from `dist/node_modules/`, the MCP
server (`dist/open-sse/mcp-server/server.js`) throws on startup:

```
Error: Cannot find package '/usr/local/lib/omniroute/lib/node_modules/omniroute/dist/node_modules/undici/index.js'
  imported from /usr/local/lib/omniroute/lib/node_modules/omniroute/dist/open-sse/mcp-server/server.js
```

Any MCP client (in our case Hermes Agent) then fails to connect
(`✗ Failed to connect: Connection closed`) and the server is left disabled.

## Environment

| | |
|---|---|
| omniroute | **3.8.48** (from `npm install omniroute@3.8.48 -g`) |
| Node.js | v24.14.0 |
| OS | Ubuntu 24.04 (noble), amd64 |
| Install cmd | `sudo npm install omniroute@3.8.48 -g --prefix /usr/local/lib/omniroute` |

## Reproduction

1. `npm install omniroute@3.8.48 -g --prefix /usr/local/lib/omniroute`
2. Start the MCP server:
   `node <prefix>/lib/node_modules/omniroute/dist/open-sse/mcp-server/server.js --mcp`
3. Observe the crash: `Error: Cannot find package '.../dist/node_modules/undici/index.js'`

Or inspect the tarball directly — the following dirs under
`dist/node_modules/` contain only `package.json`:

```
undici, ioredis, @atjsh/llmlingua-2, sql.js, sqlite-vec-linux-x64,
lru-cache, mdn-data, @csstools/css-syntax-patches-for-csstree
```

## Root cause analysis

- The runtime resolves bundled dependencies from
  `omniroute/dist/node_modules/`, **not** from the top-level
  `omniroute/node_modules/`.
- In the published tarball, many `dist/node_modules/<pkg>/` dirs are "hollow":
  they contain a `package.json` but the actual entry files (`index.js`,
  `lib/**`, `*.node`, `*.so`) are missing.
- npm's own dependency resolution correctly populated the **sibling**
  `omniroute/node_modules/` with the full packages, which is what allowed a
  local workaround (copy sibling → dist). This strongly indicates the
  `dist/node_modules/` was assembled/pruned by a build or bundling step that
  dropped file contents (e.g. an `.npmignore`/`files` glob, a `prune`, or a
  bundler that emitted stub `package.json`s without copying package payloads).

### Two categories of hollow package observed

1. **Hollow but a full copy exists in the sibling `node_modules/`** — these are
   the ones that actually break the runtime and are trivially repairable:
   - `undici` (crashes MCP server — the fatal one)
   - `ioredis`
   - `@atjsh/llmlingua-2`
   - `sql.js`
   - `sqlite-vec-linux-x64` (native `vec0.so` missing)

2. **Hollow and no sibling copy, but not imported from `dist/`** — currently
   harmless, but still indicate the packaging step is broken:
   - `lru-cache`, `mdn-data`, `@csstools/css-syntax-patches-for-csstree`

## Impact

- MCP server is completely non-functional out of the box on a clean install.
- Downstream tools that auto-configure omniroute as an MCP server (e.g. Hermes
  Agent) silently persist it as **disabled** after the failed connection.

## Suggested fix (upstream)

Ensure the packaging/bundling step that produces `dist/node_modules/` copies the
**complete** package contents, not just `package.json`. Concretely:

- If a bundler/prune step generates `dist/node_modules/`, verify its file globs
  include package payloads (`index.js`, `lib/**`, `dist/**`, `*.node`, `*.so`,
  etc.), not only manifests.
- Add a publish-time smoke test: after `npm pack`, extract the tarball and run
  `node dist/open-sse/mcp-server/server.js --mcp` (or import the top-level
  entrypoint) in a clean container; fail the release if it throws
  `Cannot find package`.
- Alternatively, drop the private `dist/node_modules/` entirely and resolve
  bundled deps from the standard `node_modules/` that npm already populates
  correctly.

## Workaround (consumer side)

Until fixed upstream, copy each hollow package from the sibling `node_modules/`
over its stub in `dist/node_modules/` after install (auto-detecting the broken
set so it survives version bumps). Reference implementation (bash), run **after**
`npm install` and **before** any `npm cache clean`:

```bash
repair_omniroute_dist_deps() {
  local omni_root="/usr/local/lib/omniroute/lib/node_modules/omniroute"
  local dist_nm="$omni_root/dist/node_modules"
  local parent_nm="$omni_root/node_modules"
  [ -d "$dist_nm" ] || return 0
  # for every dist/node_modules/<pkg> (incl. @scope/name) that has no
  # *.js/*.mjs/*.cjs/*.node/*.so, replace it with the sibling node_modules copy
  # (see .devcontainer/post-create-cmd.sh for the full implementation)
}
```

After repair: `hermes mcp test omniroute` → `✓ Connected`, 99 tools discovered.
