# Quantum's Aura Tools — Design

> Status: design locked, pre-implementation. This document is the shared
> understanding that drives the rewrite. Code follows it; when they disagree,
> fix one of them deliberately.

## What this is

**Quantum's Aura Tools (QAT)** is a from-scratch (clean-room) rewrite of the
Elder Scrolls Online addon **HyperTools**. It lets a player build on-screen
trackers for buffs, debuffs, procs, cooldowns and raid mechanics — a
WeakAuras-style tool, but with an uptime/lifecycle-centric primitive that makes
otherwise-impossible trackers (set procs with lockouts, multi-phase mechanics)
expressible as a *single* tracker.

- Target: ESO **patch 50**, API **101050**.
- Namespace `QAT`, SavedVariables `QuantumAuraToolsSV`, slash `/qat`.
- License: **MIT**. Independent rewrite — shares no code with HyperTools.
- Credits: Hyperioxes & Shadowwolf136 (original HyperTools authors).

## Why a rewrite (not a fork)

Built by a heavy HyperTools user who hit its technical walls. The model was
right; the implementation had structural flaws that couldn't be patched without
re-laying the foundation. The recurring theme: **HyperTools conflated concepts
that should be separate.** QAT de-conflates them.

| HyperTools problem | Consequence | QAT fix |
| --- | --- | --- |
| A tracker holds **one scalar value + one display** | Multi-state auras (e.g. a set proc with an active window *and* a cooldown lockout) had to be faked as a hand-wired **group** of trackers | A tracker is a **phased state machine** (§ Tracker) |
| **"cooldown"** meant three unrelated things (event throttle, the ability's real lockout, an internal load-check debounce) | Nobody knew which field to set; setup was guesswork | Three distinctly-named concepts: `throttle`, `lockout`, internal debounce |
| **Groups** did layout *and* fake-state *and* condition-inheritance, and **rendered like a tracker** | The UI implied a group could track; it can't | Groups are **folder containers** (§ Group): layout + inherited load-conditions, never trackable, visually distinct |
| Load conditions matched **localized name strings** (e.g. paste an item link, match its set *name*) | Fragile; broke on non-English clients | Match **stable numeric IDs** (setId / abilityId / zoneId / classId) with real pickers (§ Conditions) |

## Core model

### Tracker

A tracker owns **one or more phases**. Default is a single implicit phase, so
"just show this buff's uptime on me" stays trivial — no state-machine thinking.

Each **phase** = `{ enter-trigger, duration source, display }`. Phases transition
on game events. The canonical example, the Huntsman warmask set, becomes **one**
tracker with three phases instead of a group of wired-together trackers:

- **Ready** → bright icon + glow ("proc available, press me")
- **Active** → green countdown bar (uptime ticking down)
- **Cooldown** → desaturated icon + cooldown swipe + grey lockout timer

**Per-phase display** is the headline visual win: one tracker visibly changes
appearance per state. HyperTools needed multiple grouped trackers and still
couldn't cleanly swap appearance.

### Group

A purely **logical container**, rendered in the editor as a folder/header — never
as a tracker row, and with **no spatial representation** (no area/box, the
HyperTools confusion). A group:

- carries load conditions that **cascade to its children** (set once for a whole
  bar-pack)
- offers **bulk move**: dragging a group's transient move handle translates every
  descendant by the same `(dx, dy)`. The group stores no position; each tracker
  keeps its own absolute position. (See the editor's move model in EDITOR.md.)
- has **no display, no phases, no track affordance, no auto-layout** (stacking /
  bar-pack auto-arrange is a v2 maybe; v1 positions every tracker explicitly)

### Update model (engine)

Event-driven, not polling:

- **State transitions** = `EVENT_EFFECT_CHANGED` registered **per tracked
  abilityId** via `AddFilterForEvent(..., REGISTER_FILTER_ABILITY_ID, id)`. You
  receive gained/faded callbacks only for IDs you track → transitions fire on
  real game events, near-zero idle cost. Incoming casts use filtered
  `EVENT_COMBAT_EVENT`.
- **Render tick** ~10–20 Hz animates only *currently-active* trackers' countdown
  visuals. It never *detects* state. Hidden/idle trackers cost nothing.
- **Sampled triggers** (resource %, distance-to-unit, own ability slot cooldown,
  generic timers) — the few things that can't be ability-ID events — are
  evaluated by the render tick on active trackers only. Bounded, not a separate
  polling system.
- **Load-condition checks** are event-driven (skill / equipment / zone / boss
  changed), keeping HyperTools' one good performance pattern; the polling goes.

So a phase's enter-trigger *is* an event subscription. The phased model and the
performance model are the same thing.

## Conditions

All conditions match **stable IDs, never localized name strings.**

| Condition | API |
| --- | --- |
| Set equipped | iterate `BAG_WORN` slots → `GetItemLinkSetInfo(GetItemLink(BAG_WORN, slot), false)` → `setId`, count pieces |
| Skill slotted | `GetSlotBoundId(slot, hotbar)` → abilityId |
| Zone | `GetZoneId(GetUnitZoneIndex("player"))` |
| Class | `GetUnitClassId("player")` |
| Role | `GetGroupMemberSelectedRole` |
| In combat | `IsUnitInCombat("player")` |

UI replaces HyperTools' paste-link flow with a **searchable set picker**
(backed by LibSets) plus a **"use the set I'm currently wearing"** button.

### Cross-bar set logic (important)

Weapon set pieces only count for the currently-drawn bar (the "one-bar a set"
tech). Using the live `numEquipped` for the load check would make the tracker
flicker out on every weapon swap. So the **load** check uses the **cross-bar
theoretical maximum**:

```
theoreticalMax(setId) = bodyJewelryCount               -- 7 bar-independent slots
                      + max(frontWeaponCount, backWeaponCount)
```

If `theoreticalMax >= requiredPieces`, the set *can* be active in this build →
keep the tracker loaded. No swap-flicker.

The set condition exposes an **"Active on" mode** toggle:

- **Any bar (theoretical)** — default; shows whenever the set can be active.
- **Current bar only (live)** — uses live `numEquipped`; hides when you're on the
  bar where the bonus isn't reached.

This separates *whether the tracker exists* (build-level, cross-bar) from
*whether it's active this instant* (bar-level) — the same de-conflation theme.

## ID tools (discovery → authoring)

Two viewers inside the editor window, sharing one record type with build-tracker.

### `CapturedEffect`

```lua
{ abilityId, name,        -- GetAbilityName
  icon,                   -- GetAbilityIcon
  effectType,             -- BUFF | DEBUFF (GetUnitBuffInfo buffType)
  sourceType, targetType, -- player | group | boss | other
  sourceName, targetName, -- actual unit strings, e.g. "Xalvakka" -> "Quantum"
  observedDuration,       -- expireTime - startTime, live patch-50 truth
  stacks, firstSeen, lastSeen, count }
```

Two capture feeds, because one isn't enough:

- **Effect scan** — `GetNumBuffs` / `GetUnitBuffInfo` across `player`, `boss1-6`,
  `group1-N`, `reticleover` → active buffs/debuffs with real durations.
- **Combat-event stream** — `EVENT_COMBAT_EVENT` → *incoming* casts/telegraphs
  that aren't buffs yet. Buff-scanning can't see these.

### Organization

Primary grouping = **relationship** (sourceType → targetType), because that's the
exact axis that powers build-tracker's pre-fill — one axis serves view and
authoring:

| Bucket | Tracker kind | build-tracker pre-fills |
| --- | --- | --- |
| Boss → Self | incoming / debuff on you | target=Self, type=debuff, dur=observed |
| You → Boss | your debuff uptime on boss | target=Boss, onlyYourCast=true |
| any → Self (buff) | set/proc uptime (Huntsman) | target=Self, type=buff |
| any → Group | group-buff uptime | target=Group |

The live viewer is **context-free** — it knows source/target *types*, never which
raid. Optional secondary **name-context filter** (pick a `sourceName` = the boss,
and/or `targetName` = a player) turns it into the **per-boss authoring
workbench**: filter to the boss → every mechanic it does is listed → build a
tracker down each row. That is the curated-library harvesting workflow.

### Background capture toggle

- **Window-open scanning** (live viewer) registers on show, unregisters on hide —
  already free when closed.
- **Always-on background capture** (records the recently-seen timeline even with
  no window open) is the only persistent cost / crash surface. It is governed by
  a toggle: LAM checkbox + `/qat capture on|off`. **Default OFF.**
- Because capture is fully independent of the tracker runtime, disabling it is
  also a clean A/B lever to isolate instability.
- On first editor open, a **one-time, must-dismiss popup** (`ZO_Dialog`, "Got it")
  announces the feature so it can't be missed; a `capturePopupSeen` flag persists
  it.

### build-tracker

Transforms a `CapturedEffect` (or a library entry) into a single-phase tracker,
pre-filling `ids`, `icon`, `text`, `target` + `onlyYourCast` (from the bucket),
and seeding duration from `observedDuration`. The user lands in the editor with
everything but styling already done.

## Raid library

- Bundled raid data ships as a **read-only Lua data file in the addon**, versioned
  with releases. Per-mechanic *rich records*, not a flat `{id=name}` dump:

  ```lua
  { raid="Rockgrove", boss="Xalvakka", mechanic="Flame Geyser",
    ids={...}, source="boss", suggestedTarget="self",
    type="debuff", note="incoming AoE" }
  ```

- User-captured/curated entries live in a **separate user-library in
  SavedVars**. Bundled and user libraries never mix.
- **build-tracker from the library = copy + soft back-reference.** The tracker
  stores a `libraryRef` (raid/boss/mechanic key) alongside the copied IDs. It
  runs standalone (the copy executes), but the ref lets QAT detect "this library
  entry's IDs changed since you built this" and offer a **non-destructive**
  "update IDs from library" — refreshing only IDs, leaving the user's
  colors/font/layout/phases untouched. Deleting the library entry leaves the
  tracker working; it just loses update offers.
- **Sourcing:** ability IDs are facts (game data); another addon's *curation* is
  its work. RaidNotifier is used as a **reference checklist** of what to capture
  (with attribution), then actual IDs are **harvested and verified in-game on
  patch 50** using QAT's own viewers — IDs drift between patches. Reference,
  don't copy.
- **Scope:** schema covers all 14 trials; seed **current endgame first**
  (Ossein Cage, Lucent Citadel, Sanity's Edge — what people actually farm IDs
  for), backfill the catalog incrementally.

## Persistence

- **Account-wide** SavedVars. The load-condition system already delivers
  per-character relevance (a DK tracker won't load on a Sorc) — no per-character
  storage needed. Define once, loads where relevant.
- **Versioned schema migrations:** SavedVars stores `schemaVersion`; on load, run
  ordered N→N+1 migration steps. Replaces HyperTools' single ad-hoc nil-filling
  function.

## UI architecture (two surfaces)

- **LibAddonMenu-2 panel**, registered in the native **Settings → Addons** menu —
  this is what "properly registered settings" means (HyperTools never appeared in
  the addon menu at all). Global/account options: enable, background-capture
  toggle, default media, debug, reset.
- **Custom in-game editor window** for authoring: tracker tree (folders visually
  distinct from trackers), phase editor, per-phase display/style pickers,
  condition pickers, the ID viewers, the library browser, live drag-positioning.
  LAM fundamentally can't do drag-positioning or contextual phase editing, so this
  stays custom — rebuilt intuitively. ID tools live *inside* this window so
  discovery → authoring is one continuous flow.

## Display kit

Per-phase, so a single tracker changes look per state:

- **Icon** — cooldown swipe + desaturate for lockout phases, stack count, timer
  overlay
- **Progress bar** — horizontal / vertical
- **Text-only**
- **Alert** — audio cue + optional screen flash, for incoming-boss-mechanic
  trackers ("X is being cast now")

Media (fonts / textures / sounds) via **LibMediaProvider**, interoperating with
other addons' media registries.

## Dependencies

Declared as standalone `DependsOn` — **not embedded** (embedding causes the
stale-embedded-lib-shadows-newer-standalone bug).

- `LibAddonMenu-2.0` — registered settings panel
- `LibSets` — set picker / set conditions
- `LibMediaProvider` — fonts / textures / sounds
- `LibDebugLogger` — optional, structured logging
- Native ZOS keybinds (no keybind lib)

## Out of scope for v1 (v2 roadmap)

- **3D group-anchored trackers** — projecting a tracker onto a group member's
  on-screen world position (HyperTools `Matrix.lua`, ~1250 lines of camera math).
  Group-member buffs are still trackable in v1 via normal screen-anchored
  trackers; only the float-follows-them visual is deferred.
- **Group sync** — sharing/syncing trackers across the group, ported to the
  official `LibGroupBroadcast` API.
- **Named profiles** (raiding vs soloing) — account-wide + load-filter covers v1.
- **Back-catalog trials** and a **user-extendable/shareable library**.

## Build order (dependency-first)

Engine before editor — don't build UI on an unproven primitive; dogfood via
hand-written Lua first. Viewers before library — the viewers *are* the harvest
tool.

- **M0 Skeleton** — manifest, namespace, MIT LICENSE, SavedVars + migration
  framework, registered LAM panel (ships "properly registered settings" day one),
  slash + keybinds. *(this commit)*
- **M1 Engine, single-phase** — tracker tree + folder-groups, event-driven
  updates, Icon/Bar/Text, screen-anchored. Test via hand-authored Lua.
- **M2 Phases + per-phase display** — state machine, swipe/desaturate, Alert.
  Hand-author the Huntsman aura → proves the thesis.
- **M3 Conditions** — ID-based load (incl. cross-bar set logic), group
  inheritance, runtime conditions.
- **M4 Editor window** — the intuitive authoring UI.
- **M5 ID viewers + capture** — viewers, recently-seen, build-tracker pre-fill.
- **M6 Raid library** — data + browser + soft back-reference; seed current trials
  harvested via M5.
- **M7 Polish / release** — README narrative + credits, screenshots leading with
  the per-phase Huntsman aura, ESOUI listing.
