# Quantum's Aura Tools

A phase-based aura, uptime and raid-mechanic tracker for **The Elder Scrolls Online**.

One tracker changes its look as its state changes — ready → active → cooldown —
instead of stacking several to fake states.

> ⚠️ Beta (v0.2.0-beta3). The saved-data format may still change between builds.

## Features

- **Phase-based trackers.** A tracker is a small state machine. Phases advance on a
  buff gained/faded, a stack or time-left threshold, or a timer ending.
- **Per-phase display.** Several draw kinds — countdown, stacks, per-element colours
  and per-phase fonts across all of them:
  - **Bar** with an optional square icon (it never hides behind the icon),
    configurable height (thin / half / full) and vertical anchor.
  - **Icon**, **Text**, an audio/flash cue, or hidden.
  - **Border** — a frame whose perimeter drains as the timer runs out; transparent
    background so it can overlay another phase.
  - **Gradient sweep** — a translucent fill that reveals the icon as time runs down,
    in the direction you pick.
  - A **low-time** recolour + pulse for bars and borders.
- **Parallel layers.** Stack several state machines in one tracker so it can show,
  say, a duration icon *and* a cooldown frame at once. Each layer is its own node in
  the tree with a settings card (stack order, 9-point alignment, visibility); drag a
  phase between layers.
- **Switch trackers.** Pick several mutually-exclusive effects (e.g. the four
  vampire stages); build one aura that shows whichever is active. Stage order is
  editable, or opt out and wire the transitions yourself.
- **"How this phase works" card.** Plain-language summary of what a phase tracks and
  where it goes next — no ability IDs to read.
- **Load conditions.** Gate a tracker by class, role, combat state, slotted skills,
  zone, boss, **curse** (vampirism / werewolf), or equipped **sets** (any / front /
  back bar). All matched by stable ID, so they work in any client language.
- **Current-loadout reader.** See the sets you wear, the abilities on your bars, and
  the grimoires you can scribe; add any as a condition in one click. Updates live as
  you swap gear or skills.
- **Scribing-aware.** Add a scribed grimoire's cast id from the live bar/grimoire
  lists; the aggregator's **Focus Scribing** surfaces scribed effects (see below).
- **Groups.** Folders that organise trackers and share load conditions.
- **Grid layout.** Turn any group into a drawn **table** — arrange its members into
  rows × columns with optional row/column headers, styled cells (colours, borders,
  gaps, striped rows) and an optional "fill empty cells" mode that packs live effects
  toward one side so a row grows like a buff bar. Off by default; a group stays a
  plain folder until you switch it on.
- **Tracks** buffs, debuffs, procs, cooldowns, and passive/permanent buffs.

## Effect Aggregator

A live window over ESO's buff/debuff/combat stream — no more manual ability-ID
hunting.

- Records every effect it sees, deduped and grouped by relationship: what the boss
  put on **you**, what **you** put on the target, your passives, and more.
- The inspector shows the **raw data ESO returns** for each effect, so you learn the
  model as you go.
- **Build Tracker** turns one effect (or several, as a switch tracker) into a
  pre-filled tracker in the editor.
- **Persists by default.** Everything captured is kept across reloads and sessions as
  a standing library, so the viewer is already populated next time. Turn it off in
  settings to keep captures for the session only, or clear the library outright.
- **Favourite** effects to float them to the top (kept even with persistence off);
  **Ignore** noise to hide it (the ignored list un-ignores in one click).
- **Focus Scribing** floats effects from your scribable grimoires up within each
  favourite band, and tags each with the grimoire it comes from.
- **Freeze view** holds the list still while capture keeps running.
- Background capture (recording with no viewer open) is **off by default**; the viewer
  captures whenever it's open. English client only for now.

## Commands & keybinds

- `/qat` — settings
- `/qat capture on` / `off` — passive ID capture
- `/qat aggregator` (`agg`) — open the aggregator
- `/qat restore examples` — re-add deleted example trackers

Bind **Toggle Tracker Editor** and **Toggle Effect Aggregator** under
Controls → Keybindings.

## Requirements

**LibAddonMenu-2.0**, **LibSets**, **LibMediaProvider** (optional: LibDebugLogger).
API 101050.

## Planned

- **Overhead icons — self.** Render your own tracked auras above your character in
  the world, not just on the HUD.
- **Overhead uptimes — group.** Aura uptimes above your groupmates' heads. ESO won't
  let a client read other players' buffs, so this needs everyone running the add-on
  and sharing their own state over **LibGroupBroadcast**.
- **Shared trackers.** Raid leads broadcast a tracker to the group so everyone runs
  the same setup (also via LibGroupBroadcast).
- **Named-boss targeting.** Scope a tracker to a specific boss (e.g. only Z'Maja);
  the engine resolves the live boss slot, backed by a boss/zone name catalogue.
- **Searchable set / ability picker** and an in-addon **raid-mechanic library**.

> Overhead-group and shared trackers only benefit groupmates who also run the
> add-on — non-users show nothing.

## Credits & license

Independent, clean-room rewrite of
[HyperTools](https://www.esoui.com/downloads/info3057-HyperTools.html) — thanks to
**Hyperioxes** and **Shadowwolf136** for the original. [MIT](LICENSE) licensed.
Not affiliated with ZeniMax Media Inc.
