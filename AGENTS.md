# AGENTS.md

Guidance for AI coding agents in this repository. User-facing docs stay in [`README.md`](README.md).

## What this is

Omarchy shell plugin (`yuler.omaports`) that lists listening TCP ports on the bar and in a centered overlay. Quickshell QML + a Qt-free `Model.js` that Node can unit-test.

Do not edit `/usr/share/omarchy/`. Read it for APIs (`qs.Commons`, `qs.Ui`: `BarWidget`, `KeyboardPanel`, `PanelKeyCatcher`, `PanelHero`, `ConfirmDialog`, `Hint`-style chrome). Customize only this checkout.

## Layout

| File | Role |
| --- | --- |
| `manifest.json` | Plugin id, kinds (`bar-widget`, `overlay`), settings schema |
| `BarWidget.qml` | Bar mark + IPC (`open` / `close` / `toggle` / `refresh`) |
| `Panel.qml` | Bar popout (`KeyboardPanel`) wrapping the shared view |
| `Overlay.qml` | Fullscreen overlay + centered card wrapping the same view |
| `PortManagerView.qml` | Search, list, shortcuts, footer tips, confirm-to-kill |
| `PortCollector.qml` | Runs `ss` / docker, feeds the view |
| `Model.js` | Parsing, filtering, kill-safety, URLs — **no Qt** |
| `test/model-test.js` | Node asserts against `Model.js` |
| `Makefile` | `link`, `validate`, `enable`, `restart` |

State: `~/.local/state/omarchy/omaports/` (`names.json`, `settings.json`).

## Commands

```sh
make link enable   # symlink this repo into ~/.config/omarchy/plugins/yuler.omaports
make test          # node test/model-test.js
make validate      # tests + omarchy plugin validate (run on the real checkout, not the symlink path)
make restart       # omarchy restart shell (QML/JS usually hot-reload; use if the shell is stuck)
```

Open the bar panel: `omarchy-shell yuler.omaports open`  
Open the overlay: `omarchy-shell shell toggle yuler.omaports`

`omarchy plugin validate` rejects a plugin *path* that is itself a symlink. Always validate `$(REPO)`, not the plugins-dir symlink.

## Architecture

- **One UI**: `PortManagerView` is shared. Bar vs overlay only differ in chrome (anchor popout vs scrim + card) and width/height.
- **Logic in `Model.js`**: `ss` parse, ignore lists, filter, `canKillRow` / `canSignalProcess`, open/copy URLs. Add tests in `test/model-test.js` when you change it.
- **Kill is gated**: confirm dialog first, with Cancel selected. Only the current user's processes (uid + start time via `/proc`). Docker is off by default, is locked to a configured local Unix socket, and rechecks that socket before `stop`. Lowercase `k` moves up; **`K`** (and `x`) kills.
- **Two focus panes**: search and list. **Tab** toggles; do not treat Shift+Tab as a separate direction. List actions (`y`/`c`, `x`/`K`, `r`, `j`/`k`) apply only when the list is focused.

## UI conventions

- Colors, radii, type, and spacing come from `Style` / `Color` / `Border`. Do not hard-code theme palettes.
- Footer tips (`hintItems`): slash inside one keycap (`↑/↓/j/k`, `y/c`, `x/K`). **r** refresh is last. Use a `Row`, not a wrapping `Flow`.
- **Bar popout width** must fit that full tip row on one line (`preferredHintWidth` + panel padding/borders). Do not shrink it back to a fixed `420` if tips overflow.
- **Centered overlay width** stays independent (`Style.space(760)` unless the user asks to change it).
- Bar icon is the plugin `PortIcon` (RJ45 with slash), not the network ethernet glyph.

## Working in this repo

- Prefer editing existing files over adding new top-level docs or abstractions.
- After QML/JS edits, a linked checkout reloads in the running shell; confirm with the bar panel and overlay if the change is user-visible.
- Keep `Model.js` CommonJS-importable (`module.exports` at the bottom, no Qt types).
