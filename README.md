# Quantum's Aura Tools

A tracker tool for **The Elder Scrolls Online**. Build on-screen displays for
buffs, debuffs, procs, cooldowns and raid mechanics — WeakAuras-style, but with
an **uptime/lifecycle primitive** that lets you express trackers other addons
can't: a set proc with an active window *and* a cooldown lockout, a boss
mechanic with multiple phases, all as a **single tracker**.

> ⚠️ **Early development.** This is a from-scratch rewrite in progress. See
> [DESIGN.md](DESIGN.md) for the full plan and [build order](#roadmap).

## Why a rewrite

Quantum's Aura Tools is an **independent, clean-room rewrite** of
[HyperTools](https://www.esoui.com/downloads/info3057-HyperTools.html) — it
shares no code. It was built by a heavy HyperTools user who, through extensive
use, hit a set of structural flaws that couldn't be patched without re-laying
the foundation. The model was right; the implementation conflated concepts that
should be separate:

- **A tracker held one value and one display.** Anything multi-state — like the
  Huntsman warmask (an active proc window followed by a one-minute lockout) — had
  to be faked as a hand-wired *group* of trackers. In Quantum's Aura Tools a
  tracker is a **phased state machine**: one tracker that changes its appearance
  per phase (Ready → Active → Cooldown).
- **"Cooldown" meant three different things** (an event throttle, the ability's
  real lockout, and an internal load-check timer). Nobody knew which to set. They
  are now three clearly-named, separate concepts.
- **Groups did layout, fake-state, *and* condition-inheritance — and looked like
  trackers**, implying they could track. They can't. Groups are now plain
  **folder containers** for layout and shared conditions, visually distinct from
  trackers.
- **Conditions matched localized name strings** (paste an item link, match its
  set *name*), which felt fragile and broke on non-English clients. Conditions
  now match **stable numeric IDs** with proper in-game pickers.

It also adds what HyperTools lacked: **settings registered in the native Addons
menu**, a **nearby / recently-seen skill-effect ID viewer** that doubles as a
one-click tracker builder, and a growing **built-in library of raid mechanic
IDs**.

## Features (planned)

- Phase-based trackers with per-phase display (icon / bar / text / sound+flash alert)
- Event-driven engine (no per-frame polling) for low overhead in 12-player trials
- ID-based load conditions: class, role, zone, skill slotted, **set equipped**
  (with correct cross-bar "one-bar" set handling)
- In-game ID viewers (nearby effects + recently-seen) with one-click
  **build-tracker**, toggleable to save resources
- Bundled, patch-verified raid mechanic ID library with non-destructive updates
- Native registered settings (LibAddonMenu-2)

## Install (development)

The deployed addon folder must be named **`QuantumAuraTools`** (ESO requires the
folder name to match the manifest). Symlink this repo into your live AddOns
folder:

```
.../Elder Scrolls Online/live/AddOns/QuantumAuraTools  ->  this repo
```

Dependencies (install via [Minion](https://minion.mmoui.com/) or ESOUI):
`LibAddonMenu-2.0`, `LibSets`, `LibMediaProvider`. Optional: `LibDebugLogger`.

Set up editor tooling (clones the decompiled `esoui` source and generates the ESO
API stubs the language server uses) with [just](https://github.com/casey/just):

```
just setup        # one-time: fetch esoui + generate LSP stubs, then restart the LSP
just update-esoui # after a game patch: refresh esoui and regenerate stubs
just fmt          # format all Lua (stylua)
just check        # verify formatting + Lua syntax
```

The `link`, `logs`, and `errors` recipes find your ESO install through environment
variables (so no machine-specific paths live in the repo). Export these in your
shell profile:

```sh
export ESO_USER_DIR="$HOME/…/Elder Scrolls Online"
export ESO_LIVE_ADDONS_DIR="$ESO_USER_DIR/live/AddOns"
export ESO_LIVE_SV_DIR="$ESO_USER_DIR/live/SavedVariables"
export ESO_PTS_ADDONS_DIR="$ESO_USER_DIR/pts/AddOns"
export ESO_PTS_SV_DIR="$ESO_USER_DIR/pts/SavedVariables"
```

Each of those recipes takes an `env` argument selecting `live` (default) or `pts`,
e.g. `just link pts`, `just logs D pts`, `just errors pts`.

## Commands

- `/qat` — open settings
- `/qat capture on|off` — toggle passive ID capture
- Keybind: **Toggle Tracker Editor** (Controls → Keybindings → Quantum's Aura Tools)

## Roadmap

| Milestone | Scope | Status |
| --- | --- | --- |
| **M0** | Skeleton: manifest, SavedVars + versioned migrations, registered settings panel, keybinds | ✅ |
| **M1** | Event-driven tracker engine (filtered effect events + render tick; icon/bar/text, screen-anchored) | ✅ |
| **M2** | Phases + per-phase display (state-machine trackers; the proc-with-lockout primitive) | ✅ |
| **M3** | ID-based load conditions (class/role/zone/skill/set incl. cross-bar logic) + runtime conditions | ✅ |
| **M4** | Custom editor window (see [EDITOR.md](EDITOR.md)) | 🔨 in progress |
| M4.1 | Resizable two-pane frame + tree + inspector shell | ✅ |
| M4.2 | Phases tab: phase editor + flow summary (drawn-arrow graph pending) | ✅ |
| M4.3 | Conditions + Load tabs | ✅ |
| M4.4 | Pickers (ability / set / color / media) | ⬜ |
| M4.5 | Move mode (ghost previews, arming, off-screen clamping) | ⬜ |
| M4.6 | Detach, drag-drop reorder, multi-select, alignment guides | ⬜ |
| **M5** | ID viewers (nearby + recently-seen) + capture + one-click build-tracker | ⬜ |
| **M6** | Bundled raid mechanic ID library + browser + soft back-reference updates | ⬜ |
| **M7** | Polish, screenshots, ESOUI release | ⬜ |
| **v2** | 3D group-anchored trackers · group sync (LibGroupBroadcast) · named profiles · persistent detached-window geometry · group auto-stack layout presets | ⬜ |

See [DESIGN.md](DESIGN.md) for the architecture and [EDITOR.md](EDITOR.md) for the editor design.

## Troubleshooting / logs

QAT logs to LibDebugLogger sub-loggers (`Engine`, `Editor`, `Runtime`,
`Conditions`, `Capture`). Critical init paths are `pcall`-guarded, so a failure is
logged with context (and printed to chat) instead of breaking addon load.

LibDebugLogger writes to `SavedVariables/LibDebugLogger.lua`, which the dev tasks
read directly:

```
just link           # symlink this repo into live AddOns as QuantumAuraTools
just logs           # this addon's log entries (level D; pass V for effect detail)
just errors         # tail ESO's plaintext script-error log
```

Two things to know:

- **Lower the log level.** LibDebugLogger's `minLogLevel` defaults to `Info`, which
  drops QAT's `Debug`/`Verbose` lines. Set it to `Debug` (or `Verbose`) — via the
  DebugLogViewer addon in-game, or by editing `minLogLevel` in
  `SavedVariables/LibDebugLogger.lua` while the game is closed.
- **Reload first.** ESO only flushes SavedVariables to disk on `/reloadui` or
  logout, so reproduce the issue, `/reloadui`, *then* read the log.

## License & credits

[MIT](LICENSE). Independent rewrite inspired by **HyperTools** by **Hyperioxes**
and **Shadowwolf136** — credit and thanks to them for the original. Raid ability
IDs are verified in-game; community resources such as RaidNotifier are used only
as a reference checklist of what to capture.

This add-on is not created by, affiliated with, or sponsored by ZeniMax Media Inc.
