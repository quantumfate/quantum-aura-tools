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
- **Effect Aggregator** — a live window into the buffs, debuffs and combat events
  flowing past you (see below).
- **Visual editor** — a resizable two-pane window; drag a tracker on the HUD to
  position it, drag in the tree to group it. Per-phase display fonts and a global UI
  font come from your installed LibMediaProvider fonts.
- Settings registered in the native Addons menu (LibAddonMenu).

## The Effect Aggregator

A window into ESO's live data stream that hands you the tools to process it. Turn on
capture, fight (a boss, a trial dummy, anything), and it records every buff and
debuff it sees — **aggregated** by ability, deduped, and grouped by relationship:
what the boss put on **you** (the mechanics you care about), what **you** put on the
target, your own passives, and more. Each row shows the ability, its id, buff/debuff
and timed/passive tags, stacks, and how often it's been seen.

It kills the manual ability-ID hunting and the source/target guesswork — and while
you use it, its inspector shows the **raw data ESO actually returns** for each
effect, so you learn the data model as you go. One click on **Build Tracker** turns
any effect into a pre-filled tracker and drops you into the editor to refine it.

- Open it with `/qat aggregator` (or `/qat agg`).
- Capture runs in the background and is **off by default** — toggle it on while
  you're hunting, then off again.
- **Pin** effects to keep them across reloads; **Ignore** known noise to hide it.
- **Freeze view** holds the list still for reading while capture keeps running.
- English client only for now.

## Usage

- Bind **"Toggle Tracker Editor"** under Controls → Keybindings to open the editor.
- `/qat` opens the settings panel.

## Requirements

**LibAddonMenu-2.0**, **LibSets**, **LibMediaProvider** (optional: LibDebugLogger).

## Coming next

A searchable set/ability picker, targeting a boss by name (the engine resolves the
live boss slot for you), and an in-addon raid-mechanic library.

## Credits & license

An independent, clean-room rewrite of
[HyperTools](https://www.esoui.com/downloads/info3057-HyperTools.html) — thanks to
**Hyperioxes** and **Shadowwolf136** for the original. [MIT](LICENSE) licensed.
Not affiliated with ZeniMax Media Inc.

Contributing / architecture: see [DESIGN.md](DESIGN.md) and [EDITOR.md](EDITOR.md).
