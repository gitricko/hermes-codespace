# Selkies Package Discrepancy: PyPI vs GitHub Actions

## Problem

The PyPI package `selkies==1.6.1` is **NOT** the pixelflux-based selkies described in the spec. It is the **legacy `selkies_gstreamer`** package — an older GStreamer/WebRTC project with:

- No pixelflux (Rust capture engine)
- No bundled React web client
- No `--mode=websockets` flag
- Console script is `selkies-gstreamer`, not `selkies`

## Correct Package

The pixelflux-based `selkies` (v0.0.0.dev0) with:
- Real Selkies web client (React dashboard)
- pixelflux (Rust X11 capture → H.264/JPEG)
- `--mode=websockets` flag
- WebSocket endpoint at `/api/websockets`
- Console script `selkies`

...is distributed as a **GitHub Actions artifact** (`selkies-wheel`) from the `selkies-project/selkies` repository.

## How to Download

1. Go to <https://github.com/selkies-project/selkies/actions>
2. Find the latest successful workflow run
3. Download the `selkies-wheel` artifact (a zip file)
4. Extract the `.whl` file inside

The wheel filename is `selkies-0.0.0.dev0-py3-none-any.whl`.

## Verification

To distinguish the two packages:

```bash
# WRONG (PyPI legacy):
pip install selkies  # gets selkies==1.6.1 (GStreamer)
selkies-gstreamer    # console script exists
# Missing: --mode=websockets, selkies_web/, pixelflux

# CORRECT (GitHub Actions):
pip install selkies-0.0.0.dev0-py3-none-any.whl
selkies --help       # should show --mode=websockets
# Has: selkies_web/ React client, pixelflux, pcmflux
```

## Dependency: pixelflux + libva

The pixelflux Rust extension requires system libraries:
```bash
sudo apt-get install -y libva2 libva-drm2 libva-x11-2
```

Without these, `import pixelflux` fails with a missing shared library error.
