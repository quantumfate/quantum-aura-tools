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

## Commands

- `/qat` — open settings
- `/qat capture on|off` — toggle passive ID capture
- Keybind: **Toggle Tracker Editor** (Controls → Keybindings → Quantum's Aura Tools)

## Roadmap

| Milestone | Scope |
| --- | --- |
| **M0** | Skeleton: manifest, SavedVars + migrations, registered settings, keybinds ✅ |
| **M1** | Event-driven tracker engine (icon/bar/text, screen-anchored) ✅ |
| **M2** | Phases + per-phase display (state-machine trackers) ✅ |
| M3 | ID-based load + runtime conditions |
| M4 | Custom editor window |
| M5 | ID viewers + capture + build-tracker |
| M6 | Bundled raid mechanic library |
| M7 | Polish & release |
| v2 | 3D group-anchored trackers, group sync (LibGroupBroadcast), profiles |

## License & credits

[MIT](LICENSE). Independent rewrite inspired by **HyperTools** by **Hyperioxes**
and **Shadowwolf136** — credit and thanks to them for the original. Raid ability
IDs are verified in-game; community resources such as RaidNotifier are used only
as a reference checklist of what to capture.

This add-on is not created by, affiliated with, or sponsored by ZeniMax Media Inc.
