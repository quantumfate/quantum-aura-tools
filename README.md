# Quantum's Aura Tools

A phase-based aura, uptime and raid-mechanic tracker for **The Elder Scrolls Online**.

Build one tracker that **changes its look as its state changes** — ready → active →
cooldown — instead of stacking several trackers to fake states.

> ⚠️ Alpha (v0.1.0), under active development. Expect rough edges.

## Features

- **Phase-based trackers** — one tracker moves through phases driven by a buff being
  gained or faded, stack/time thresholds, or a timer ending; each phase has its own
  look.
- **Per-phase display** — Bar, Icon, Text, an Audio cue, or hidden — with a
  countdown, stack count, and per-element colours and font sizes.
- Tracks **buffs, debuffs, procs and cooldowns**, including passive/permanent buffs.
- **Groups** (folders) to organise trackers and share load conditions.
- **Load conditions** decide when a tracker is active: class, role, combat state,
  slotted skills, zone, boss, and equipped **sets** — matched by stable IDs, so they
  work in any client language. Set conditions can require a specific bar
  (any / front / back).
- **Current-loadout reader** — see the sets you're wearing and add any as a
  condition in one click; updates live as you swap gear.
- **Visual editor** — a resizable two-pane window; drag a tracker on the HUD to
  position it, drag in the tree to group it.
- Settings registered in the native Addons menu (LibAddonMenu).

## Usage

- Bind **"Toggle Tracker Editor"** under Controls → Keybindings to open the editor.
- `/qat` opens the settings panel.

## Requirements

**LibAddonMenu-2.0**, **LibSets**, **LibMediaProvider** (optional: LibDebugLogger).

## Coming next

**The effect aggregator** — a window into ESO's live data stream that hands you the
tools to process it. It captures the buffs, debuffs and combat events flowing past
you, aggregates them by ability, source and target, and lets you turn any one into a
tracker in a click. It kills the manual ability-ID hunting and the source/target
guesswork — and in doing so teaches you the data model and how ESO actually emits
effects in the first place.

Also planned: a searchable set/ability picker and an in-addon raid-mechanic library.

## Credits & license

An independent, clean-room rewrite of
[HyperTools](https://www.esoui.com/downloads/info3057-HyperTools.html) — thanks to
**Hyperioxes** and **Shadowwolf136** for the original. [MIT](LICENSE) licensed.
Not affiliated with ZeniMax Media Inc.

Contributing / architecture: see [DESIGN.md](DESIGN.md) and [EDITOR.md](EDITOR.md).
