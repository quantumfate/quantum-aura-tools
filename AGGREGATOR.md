# AGGREGATOR.md — Effect Aggregator design brief

The M5 **Effect Aggregator**: a second top-level window (sibling to the Editor) that
captures the buffs/debuffs/combat events flowing past the player, aggregates them by
ability/source/target, and turns any one into a tracker in a click.

Data model is fully specified and locked (see the Data section below). This document
is the brief handed to Claude design for the visual/interaction layer; the UI itself
is authored there and iterated in-game.

**Reference mockup (local, gitignored):** `handoff/` holds the Claude-design output —
`PROMPT.md`, `Effect Aggregator - Build Spec.md`, the interactive `.dc.html` mockup +
`support.js`, and per-state PNGs. Read `handoff/PROMPT.md` first. That spec's §7 is the
crude first cut of the `sourceRole` resolver; the version below is authoritative.

## Data model (locked)

One row = one aggregated `CapturedEffect` (repeat observations collapse into it).

- **Key / dedup:** `abilityId` + `sourceName` + `targetName` + `zoneId`. Keyed by
  resolved NAMES, never the raw `boss1-6` slot tag — slots are frame-assignment
  order and shuffle between pulls, which would fragment the same effect on the same
  boss into separate rows. `targetName` = `GetUnitName(tag)` at ingest (combat feed
  uses the event's targetName). Raw slot tag + `targetRole` (me/boss) kept for
  display/bucketing. Stable within a locale (EN-now); cross-locale = the future
  name catalog's job.
- **Required (build-tracker consumes):** `abilityId`. `name`/`icon` derive from it
  (`GetAbilityName` / `GetAbilityIcon`) at render.
- **Frozen-at-ingest context:** `sourceRole` (self/boss/group/other), `sourceType`,
  `effectType` (buff/debuff), `timed` (bool — has a duration vs passive/always-on),
  `maxStacks`, `seenCount`, `firstSeen`, `lastSeen`.
- **Relationship** of a row = `sourceRole → targetRole` (target role derives from
  `targetUnitTag`: player=Self, boss=Boss). Boss→Self is the money bucket.

### `sourceRole` resolver (authoritative — supersedes the handoff spec §7)

`sourceRole` is frozen at ingest by a **combined** rule; neither the enum nor the
name alone is sufficient. Resolve in order:

1. `sourceName` matches the live player name → **self**.
2. `sourceName` matches a live `boss1-6` name → **boss** (also splits a specific
   add from the boss).
3. `sourceType == COMBAT_UNIT_TYPE_NONE` while in an active boss fight → **boss**
   — catches ground/environmental boss mechanics that arrive with an *empty*
   `sourceName` (the Xoryn's-Gaze case); name-matching alone would misfile the
   money bucket as "other".
4. `sourceType == COMBAT_UNIT_TYPE_GROUP` (or name matches a group member) → **group**.
5. otherwise → **other**.

The handoff spec's §7 (`COMBAT_UNIT_TYPE_NONE/boss → boss`, `PLAYER → self`) is the
crude first cut; this is the shipping logic.
- Duration seconds are **dropped** — the tracker engine derives duration live from
  the abilityId; only the `timed` bool matters (for build-tracker pre-fill).

**Feeds** (fused into one row): `EVENT_EFFECT_CHANGED` unit-filtered to
player+boss1-6 (no ability filter) + a seed-sweep on start / `EVENT_BOSSES_CHANGED`
(catches passives) gives duration/stacks/effectType; `EVENT_COMBAT_EVENT` gives
`sourceName` + relationship + result. Combat-event = identity spine, scan =
enrichment keyed by `abilityId` + resolved target.

**Lifecycle:** capture is a background toggle, **default OFF**, decoupled from the
window (one-time popup on first enable). Rows accumulate in-memory for the session;
**pin/keep** and build-tracker promote a row to a small persisted SV table; reload
dumps the unpinned catch. Every row is fully self-describing at ingest because the
viewer is detached in time from capture.

**New persisted data:** a small `ignoredAbilityIds` set (the Ignore action). A
session-only `isNew` flag drives the optional "new since last viewed" highlight.

## build-tracker transform

Thin, per-row **editable seed** (not a graph generator). Emits the schema's flat
shorthand `{ abilityIds={id}, name, icon, unit, display, duration }` and lets
`CanonicalizeDef` expand it, then opens the Editor on the new tracker:
- `unit`: target self→`"player"`, boss→`"reticleover"` (default, editable).
- `duration.type`+`showTime`: `timed`→`"effect"`+show; passive→`"none"`+hide.
- `display`: default `"icon"`.

## Deferred

Boss identity + non-EN locales ride on a future localization / name-catalog; **EN
only** for now. Whether the key uses raw `targetUnitTag` vs a role-bucket is still
open, tied to that catalog work.

---

## Prompt for Claude design

```
Design the UI for a new window in Quantum's Aura Tools (QAT), an ESO addon: the
Effect Aggregator. It's a second top-level window, sibling to the existing Editor
window whose design language you already know — MATCH IT exactly: deep-navy flat
palette, no rounded corners, information-dense cards, chips, colored badges,
segmented toggles, small-caps section headers, muted helper text, per-row colored
square swatches, ghost "+" rows for actions. Same title-bar treatment
("Quantum's Aura Tools — Effect Aggregator", close X). Two-pane layout mirroring
the Editor (list | detail).

## What this tool IS (the thesis — let it shape the design)
A window into ESO's live data stream that hands the player the tools to process it.
It captures the buffs, debuffs and combat events flowing past them, aggregates them
by ability/source/target, and turns any one into a tracker in a click. It kills
manual ability-ID hunting and source/target guesswork — and in doing so TEACHES the
player ESO's data model and how the game emits effects. It is a harvest tool AND a
learning tool. The design should feel like an instrument for reading a data stream,
not a settings screen.

## How capture works (affects the UI)
- Capture is a BACKGROUND toggle, default OFF, DECOUPLED from this window — it runs
  whether or not the window is open. The window is a viewer of already-captured data.
- If the window is open while capture runs, it's a LIVE view (rows update in place);
  if opened later, it's a static view of the frozen catch. Same list either way.
- First time capture is enabled, a one-time dismissible popup explains that it runs
  in the background.

## The data (one row = one aggregated "CapturedEffect")
Each row aggregates repeat observations of the same effect. Fields available to show
/ filter / sort:
- abilityId (stable), name, icon (derived from abilityId)
- sourceName + sourceRole (self / boss / group / other, frozen at capture)
- targetUnitTag → target role (me / boss)
- zoneId (which trial/dungeon)
- effectType (buff or debuff)
- timed (true = has a duration, false = passive/always-on)
- maxStacks, seenCount, firstSeen, lastSeen
Relationship of a row = sourceRole → targetRole (e.g. Boss→Self, Self→Boss,
Group→Self). "Boss→Self" is the money bucket — incoming boss mechanics.

## Required surfaces

1. CAPTURE CONTROL BAR (always visible, top): prominent On/Off toggle with a
   recording indicator, a live counter ("capturing in Lucent Citadel · 47 effects"),
   current zone context, and a clear stopped state. Also a freeze/pause-VIEW control
   (holds the list still for reading while capture keeps running).

2. FILTER CONTROLS: the tool lives or dies on filtering — an unfiltered player scan
   dumps dozens of passive noise rows (CP, food, mundus, group buffs) instantly.
   Filter axes: relationship bucket, buff/debuff, timed vs passive, target (me/boss),
   source, zone, session-only vs pinned, has-stacks / min stacks, min seen-count,
   time window, and a text search over id/name. DEFAULT STATE hides Self→Self
   passives and shows Boss→Self + Self→Boss + Group→Self, with one obvious toggle to
   reveal everything. Make the noise dial (timed/passive + relationship) fast to
   reach.

3. GROUPED LIST (left pane): primary grouping by relationship bucket, collapsible
   sections with counts; Self-passives section collapsed by default. Sort within a
   group by seen-count or last-seen (default), also name/id/type. On live refresh:
   update/append in place, preserve scroll + selection, do NOT auto-resort under the
   user. Rows can number in the hundreds during a trial — design for length and
   scannability.

4. ROW ANATOMY: colored swatch/icon, ability name, abilityId (one-click copy),
   buff/debuff badge (color-coded), source→target with a sourceRole badge, a
   timed/passive badge, max stacks, seen-count, last-seen, zone. Optional pinned
   indicator.

5. DETAIL / INSPECTOR PANEL (right pane) — THE TEACHING SURFACE: when a row is
   selected, show the raw ESO data behind it with human labels: sourceType enum,
   effectType constant, ability type, buff slot, castByPlayer, raw targetUnitTag,
   first/last-seen timestamps. This is where "a window into the data stream that
   teaches the data model" literally lives — make it a real, readable panel, not a
   tooltip.

6. PER-ROW ACTIONS: Build Tracker (primary call-to-action — creates a pre-filled
   tracker and hands off to the Editor window), Pin/Keep (promote to a persisted
   library that survives reloads), Copy abilityId, Ignore (permanently suppress a
   known-noise ability from the list).

7. STATES: empty (capture off, nothing captured → explain how to start); capturing
   but nothing yet ("watching…"); pinned/kept rows visually distinct from
   session-only ones; optional subtle "new since last viewed" highlight.

## Notes / constraints
- Not a graph builder: Build Tracker is a thin seed (one effect → one simple
  tracker), then the Editor does the real authoring. Don't over-design that button.
- "Already tracked" indicator is optional and low-priority — it risks being noise
  itself; if included, keep it very subtle / off by default.
- English-only for now.

## Deliverables
An annotated layout for the window (two-pane list | detail), the capture-control
bar, the filter controls, the grouped-list row component (with its badges/chips),
the detail/inspector panel, and the key states (empty, capturing-live, static,
row-selected). Call out component reuse from the existing Editor design.
```
