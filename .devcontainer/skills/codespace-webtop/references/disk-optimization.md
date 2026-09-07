# Disk Space Optimization

## Build-Time vs Runtime Artifacts

The webtop install compiles pixelflux and pcmflux from Rust source (they require PyO3 Rust extensions). After compilation, only the resulting `.so` files in the venv are needed at runtime. The following are **build-time only** and can be safely removed after install:

| Artifact | Size | Why removable |
|----------|------|---------------|
| `~/.rustup` | ~1.5GB | Rust toolchain (compiler, std lib) — only needed to compile extensions |
| `~/.cargo/registry` | ~575MB | Cargo crate cache — only needed during build |
| `~/.selkies/selkies-src/` | ~170MB | Full git clone + node_modules — only `web_root/` dist matters |
| `~/.cache/pip` | ~32MB | pip download cache |

**Total savings: ~2.3GB** (from ~3GB -> ~250MB runtime footprint).

## Cleanup Procedure (in `cmd_install`)

```bash
# Track whether we installed Rust ourselves
local rust_installed_by_us=0
if ! command -v cargo &>/dev/null && [[ ! -d "$HOME/.cargo" && ! -d "$HOME/.rustup" ]]; then
  rust_installed_by_us=1
  # ... install rustup ...
fi

# After pip install + web build:
if [[ "$rust_installed_by_us" -eq 1 ]]; then
  # We installed it -- safe to remove entirely
  rm -rf "$HOME/.rustup" "$HOME/.cargo"
else
  # User had pre-existing toolchain -- only clean build cache
  rm -rf "$HOME/.cargo/registry/cache" "$HOME/.cargo/registry/src" "$HOME/.cargo/git/db"
fi
rm -rf "$HOME/.selkies/selkies-src" "$HOME/.cache/pip"
```

## Reinstalling After Cleanup

If the user runs `install` again:
- Rust toolchain will be re-downloaded if `rust_installed_by_us=1` (we removed it)
- Cargo registry will be repopulated on first build
- `selkies-src` will be re-cloned
- This is correct behavior -- cleanup trades disk for re-download time on reinstall

## Git Commit Pinning (Reproducibility)

The three git dependencies are pinned to specific commits:

| Repo | Pin | How to update |
|------|-----|---------------|
| pixelflux | `bf07c68` | `git ls-remote https://github.com/selkies-project/pixelflux.git HEAD` |
| pcmflux | `d2683ef` | `git ls-remote https://github.com/selkies-project/pcmflux.git HEAD` |
| selkies | `1d9b67b` | `git ls-remote https://github.com/selkies-project/selkies.git HEAD` |

Update pins in `selkies-native.sh` when new features/fixes are needed. Never use mutable `@HEAD` or branch names -- they break reproducibility.
