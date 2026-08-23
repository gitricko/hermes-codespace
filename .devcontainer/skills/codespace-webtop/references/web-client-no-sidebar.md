# Web client: no-sidebar diagnosis & correct build

## Symptom
Webtop launches: video renders, mouse/keyboard work, clipboard syncs, WS
handshake returns `MODE websockets`, `curl /` returns HTTP 200 — but the
Selkies **sidebar** (video/audio/screen settings, stats, clipboard, file
transfer, keyboard shortcuts) is missing. The page is just the bare desktop.

## Root cause
The selkies repo ships TWO web addons under `addons/`:
- `selkies-web-core` — the **embeddable streaming Core** only. Its README
  literally states it is "for an external dashboard to interact with the
  client." The built bundle mounts with the sidebar CLOSED
  (`_isSidebarOpen = !1`) and only opens it when a separate dashboard posts a
  `window.postMessage({type:'toggleDashboard'})`. Served alone it is a desktop
  feed with no sidebar chrome.
- `selkies-dashboard` — the **standalone UI** (React app, `react`/`react-dom`).
  Its `prebuild` (`copy-core.js`) copies `../selkies-web-core/dist/selkies-core.js`
  into `src/`; vite then bundles the Core *plus* the full sidebar UI.

Serving `selkies-web-core/dist` as `--web-root` is the wrong client. The
correct `--web-root` is `selkies-dashboard/dist`.

## Confirm which client is being served
```bash
# download the served bundle
curl -s http://127.0.0.1:3000/selkies-core.js > /tmp/core.js 2>/dev/null \
  || curl -s "http://127.0.0.1:3000/$(curl -s http://127.0.0.1:3000/ | grep -oE 'assets/index-[A-Za-z0-9]+\.js' | head -1)" > /tmp/core.js

# bare Core has almost no sidebar refs and starts closed:
grep -oE "_isSidebarOpen=![01]" /tmp/core.js     # bare core: !1 (closed)
grep -oc "sidebar" /tmp/core.js                   # bare core: ~0-4 ; dashboard: ~90
grep -oc "toggle"  /tmp/core.js                   # bare core: ~0  ; dashboard: ~100

# also: index.html. Dashboard's <div id="root"></div> + jsdb/ + assets/ dir;
# bare core's is a single selkies-core.js module with no assets/ folder.
curl -s http://127.0.0.1:3000/ | head
ls ~/.selkies/web_root/
```

## Correct build + serve (do this, not bare core)
```bash
cd ~/.selkies
rm -rf selkies-src && git clone --depth 1 https://github.com/selkies-project/selkies.git selkies-src

for a in selkies-web-core selkies-dashboard; do
  ( cd selkies-src/addons/$a && { npm ci --no-audit --no-fund 2>/dev/null || npm install --no-audit --no-fund; } && npm run build )
done
# web-core FIRST (dashboard prebuild imports its dist); both must be siblings.

# swap web_root to the dashboard dist
rm -rf ~/.selkies/web_root && cp -r ~/.selkies/selkies-src/addons/selkies-dashboard/dist ~/.selkies/web_root

# restart (selkies reads --web-root at startup)
bash ~/.hermes/skills/codespace/codespace-webtop/scripts/selkies-native.sh restart
```
Verify: `curl /` now references `assets/index-*.js`; the served JS contains
~90 `sidebar` refs; open the forwarded port — sidebar chrome present.

## Pitfalls recap
- Build `selkies-web-core` before `selkies-dashboard` (prebuild dependency).
- `npm ci` can fail on a fresh `--depth 1` clone (no lockfile) → use `|| npm install`.
- The control script `cmd_build_web` now does this; older versions built bare
  `selkies-web-core` (no sidebar) — the #1 historical cause of this bug.
