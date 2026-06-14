# macvscr

A macOS menu-bar tool that creates **controllable virtual displays** — arbitrary resolution, HiDPI (Retina `@2x`), aspect ratio, and iMac presets. It unblocks HiDPI screen-sharing on headless Macs (e.g. a Mac mini with no monitor attached), where the session is otherwise locked to 1920×1080 non-HiDPI.

[简体中文](README.zh-CN.md) · npm: **[macvscr](https://www.npmjs.com/package/macvscr)** · command: `macvscr`

## Install

```bash
npx -y macvscr@latest setup     # zero-install: stable binary + shell alias + login LaunchAgent
# or
npm install -g macvscr && macvscr setup
```

Requires macOS 13+ on Apple Silicon (arm64).

## Three ways to run (progressive)

| Mode | Command | Behavior | Stop |
|---|---|---|---|
| ① Foreground | `macvscr` *(default)* or `macvscr run` | occupies the terminal, prints guidance; **Ctrl+C** to quit | Ctrl+C |
| ② Background | `macvscr run -d` | detached; the terminal returns immediately | `macvscr stop` |
| ③ Login service | `macvscr setup` | LaunchAgent — runs at login, restarts on crash | `macvscr stop` / `macvscr uninstall` |

```bash
macvscr                                  # foreground, default 3440×1440 @2x
macvscr --width 2560 --ratio 16:9 --hidpi
macvscr run -d --width 2560 --ratio 16:9
macvscr setup --width 2560 --ratio 16:9
macvscr status | stop | start | restart | uninstall
```

## Resolution model

Everything you type and see is in **logical pixels**; HiDPI (`@2x`) doubles the physical surface.

- `2560×1440 @2x` → logical workspace 2560×1440, physical 5120×2880 (the Retina way macOS describes a 5K iMac)
- `1920×1080` (HiDPI off) → logical = physical = 1920×1080

The tray header shows both, so logical and physical are never confused.

## Menu bar

Click the display icon: **Presets ▸** (iMac sizes folded in with tails), **Width ▸ / Height ▸ / Aspect ▸** (each with a `Custom…` input dialog), **HiDPI / Retina @2x**, **Quit**. Width, height, and ratio are linked (width is the master axis). Switching rebuilds the display live — no restart.

## Headless / Screen Sharing

1. On the headless Mac, run `macvscr setup` and pick a preset from the menu bar.
2. From another Mac, connect via Screen Sharing → **View** menu → select the dummy.
3. The remote session renders at the chosen geometry with Retina.

## How it works

- **Swift** (SPM, AppKit). Virtual displays use the private `CGVirtualDisplay*` ObjC classes, which live in the **public CoreGraphics binary** — no `dlopen`, **SIP stays on**. The ObjC declarations sit in a small `VSCBridge` target exposing a plain-C API to Swift.
- Pure CLI; no `.app`. A menu-bar tray app can only start at **login** (LaunchAgent), not boot (LaunchDaemon has no GUI session).
- Bundled arm64 binary is rebuilt by CI and published to npm via **trusted publishing** (provenance).

## Build

```bash
swift build -c release --arch arm64   # → .build/release/macvscr
.build/release/macvscr --help
```

## Publish (CI)

Tagging `v*` triggers `.github/workflows/release.yml` (macos-14 runner → build arm64 → `npm publish --provenance`). Manual:

```bash
swift build -c release --arch arm64
cp .build/release/macvscr npm/binaries/macvscr-darwin-arm64
cd npm && npm publish
```

## Layout

```
Sources/
  VSCBridge/         ObjC++ shim: declares CGVirtualDisplay*, exposes vsc_create/destroy/display_id
  macvscr/           Swift: TrayController, VirtualDisplay, Presets, Geometry, CLI, main
.github/workflows/   ci.yml (build check), release.yml (tag → npm trusted publish)
npm/                 publishable npm package (package.json, bin/macvscr.js, binaries/, README, LICENSE)
```

## Verify

```bash
system_profiler SPDisplaysDataType | grep -i virtual
```

MIT licensed.
