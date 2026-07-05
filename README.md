# Quantum's Aura Tools

A phase-based aura, uptime and raid-mechanic tracker for **The Elder Scrolls Online**.

One tracker changes its look as its state changes — ready → active → cooldown —
instead of stacking several to fake states.

> ⚠️ Beta (v0.2.0-beta1). The saved-data format may still change between builds.

## Features

- **Phase-based trackers.** A tracker is a small state machine. Phases advance on a
  buff gained/faded, a stack or time-left threshold, or a timer ending.
- **Per-phase display.** Bar, Icon, Text, an audio/flash cue, or hidden. Countdown,
  stacks, per-element colours, and per-phase fonts.
- **Switch trackers.** Pick several mutually-exclusive effects (e.g. the four
  vampire stages); build one aura that shows whichever is active. Stage order is
  editable, or opt out and wire the transitions yourself.
- **"How this phase works" card.** Plain-language summary of what a phase tracks and
  where it goes next — no ability IDs to read.
- **Load conditions.** Gate a tracker by class, role, combat state, slotted skills,
  zone, boss, **curse** (vampirism / werewolf), or equipped **sets** (any / front /
  back bar). All matched by stable ID, so they work in any client language.
- **Current-loadout reader.** See the sets you wear; add any as a condition in one
  click. Updates live as you swap gear.
- **Groups.** Folders that organise trackers and share load conditions.
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
- **Favourite** effects to keep them across reloads and float them to the top;
  **Ignore** noise to hide it.
- **Freeze view** holds the list still while capture keeps running.
- Capture is background and **off by default**. English client only for now.

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
