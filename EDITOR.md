# Quantum's Aura Tools — Editor (M4) Design

> The custom in-game authoring window. Companion to DESIGN.md; this file owns the
> editor's interaction model. ESO UI is a bespoke toolkit (top-level windows,
> `CT_*` controls, anchor layout, `CT_LINE`, `ZO_*` widgets) — not web/DOM.

## Goals (and the HyperTools flaws they fix)

| HyperTools flaw | Fix |
| --- | --- |
| Window used `SetResizeToFitDescendents` — not user-resizable, just auto-grew | A **user-resizable** window with min size + persisted geometry |
| Scrolling was custom up/down arrow *buttons* | Real scroll (scrollbar + mousewheel) |
| Groups rendered like trackers and defined a confusing draggable *area* | Groups are tree folders with **no spatial box** (DESIGN.md) |
| Move mode let you grab invisible/overlapping trackers by accident | **Arming + no invisible hitboxes + per-tracker isolation** (see Move) |
| One giant imperative build function | Component modules, inspector is **multi-instance** |

## Window & layout

- **One resizable top-level window.** `SetResizeHandleSize` + `SetDimensionConstraints`
  (min size enforced), `SetMovable`, `SetClampedToScreen`. Geometry (x, y, w, h,
  tree-pane width) persisted in `sv.editor`; restored on open, saved on
  `OnMoveStop` / `OnResizeStop`.
- **Two panes** with a **draggable vertical splitter**:
  - **Left — tracker tree** (folders + trackers).
  - **Right — inspector** for the selected node.
- **Real scrolling** via `ZO_ScrollContainer` (mousewheel + scrollbar). Tree list
  height tracks window height; inspector scrolls independently.
  (Implementation note: start with a rebuilt row list inside a scroll container;
  upgrade to virtualized `ZO_ScrollList` only if long lists need it.)

## Tree (left pane)

- Row = expand caret (folders) · kind icon (folder, or the tracker's display
  kind) · name (rename via F2 / double-click) · **enable checkbox** · right-click
  context menu (add child, duplicate, delete, move-to, export).
- **Enable checkbox** = manual on/off, independent of load conditions. A disabled
  node is skipped entirely; a disabled folder disables its subtree.
- Toolbar: **+ Tracker · + Group · Duplicate · Delete · Move mode** · search box.
- **Reorder / reparent**: drag-drop, with **up/down + indent/outdent buttons** as
  an always-works fallback.
- **Multi-select** for bulk enable/disable/delete/move.
- Folders are visually unmistakable from trackers (caret + folder icon, never a
  tracker-looking row).

## Inspector (right pane) — multi-instance

The inspector is a **component bound to a `trackerId`** that renders entirely from
the def and refreshes on `CALLBACK_MANAGER:FireCallbacks("QAT_TrackerChanged", id)`.
Because every view reads/writes the same def and re-renders on that callback, all
views stay consistent for free.

- **Docked instance** — in the right pane, follows tree selection.
- **Detached instances** — a **"pop out"** button spawns a floating, independently
  resizable window with another inspector instance for that tracker. Open several
  to compare/edit side by side; closing one doesn't affect others. Geometry is
  **ephemeral cascade-spawn** (no per-tracker saved position in v1).

**Persistent header** (always visible, never behind a tab): tracker **name**,
**enable** toggle, **Move on screen** button, **pop-out** button.

**Tabs: Phases · Conditions · Load.**

### Phases tab

Master-detail, with a **visual state-machine graph** as the navigator:

- **Graph (top)** — a *derived visualization*, never an editor of record:
  - Nodes = phases (name + color swatch + **initial** badge), auto-laid-out
    left-to-right by order; return transitions drawn as arcs (`CT_LINE` +
    `SetTextureRotation`, arrowhead texture).
  - Arrows generated from the def's triggers / `onExpire`, labeled
    ("gained 999001", "after 60s").
  - **Clicking a node selects that phase** (drives the detail editor). Re-renders
    live on `QAT_TrackerChanged`.
  - **Canvas interaction never writes SavedVars** — editing happens in fields
    below; the graph only reflects. (Drag-to-connect is intentionally *not*
    planned — it was judged fragile.)
- **Phase detail (below)** for the selected node:
  - **Tracked ability** (simple default): pick an ability id (typed, or via
    "Pick from recently-seen" → M5 viewer) with a live icon+name preview. This
    **auto-wires** both "enter when gained" and "duration follows this effect" —
    hiding trigger/duration duplication for the common case.
  - **Advanced** (collapsible): raw enter triggers (gained/faded · unit ·
    **from-phase** guard), duration type (None / Effect-follow / **Fixed** s),
    **On expire → [phase]**.
  - **Look**: display kind (icon/bar/text/alert), name, color, icon, font.
- Phase strip controls: add `+`, reorder, delete, set initial.

### Conditions tab (runtime)

Row list matching the data model `{ stat, op, value, action, color }`:
**when** [stat: remaining / stacks] [op] [value] → **then** [action: hide /
color (glow, alert as the kit grows)]. Rows evaluated in order (later wins).

### Load tab

One scroll, labeled sections — empty section = no constraint:

- **Class** · **Role** · **In-combat** (ignore / in / out) · **Never / Always**
- **Zones** — list + **"add current zone"** (`GetZoneId`)
- **Skills slotted** — ability-id picker list
- **Sets** — picker rows: set (LibSets search + **"use set I'm wearing"**),
  piece count, **any-bar / current-bar** mode (cross-bar logic, DESIGN.md)
- **Bosses** — list + **"add current boss"**

Editing a **folder** node's Load tab edits its cascading load (note: "applies to
all children").

## Pickers

- **Ability id** — field accepting id(s) with live `GetAbilityIcon`/`GetAbilityName`
  preview, plus **"Pick from recently-seen"** opening the M5 viewer to click an
  effect in. The discovery→authoring bridge.
- **Set** — LibSets searchable dropdown + **"use set I'm wearing"** (reads worn
  `setId`s) + piece count + any/current-bar toggle.
- **Color** — ESO's native `ZO_ColorPickerManager`.
- **Media** — font / sound / status-bar texture dropdowns from **LibMediaProvider**,
  with preview (sample text, play sound).

## Move mode (positioning trackers on screen)

Trackers anchor to `GuiRoot`; most are hidden (idle phase) when out of combat.

- **Three granularities**:
  - **Global move mode** — all trackers ghost-preview + (armed) draggable.
  - **Per-tracker move** (tree / header) — isolates one tracker; **all others get
    mouse disabled** so they can't be touched. The path for overlapping
    conditional trackers.
  - **Per-group move** — translates every descendant by one `(dx, dy)`.
- **Ghosts** render the tracker's **real phase look** (dimmed + labeled) at true
  footprint, so you place the real size, not a placeholder.
- **Never move an invisible tracker** (the HyperTools bug):
  1. A ghost's hitbox == its visible footprint; non-ghosted trackers have
     `SetMouseEnabled(false)` → **zero invisible hitboxes**.
  2. **Arming**: a click only selects/arms (highlight + raise + name); only the
     **armed** ghost responds to drag.
  3. Per-tracker move disables every other ghost's mouse.
  - Plus a per-tracker **position lock** flag and **revert position** (cheap undo).
- **Off-screen guards** (nothing ever renders off-screen):
  1. Direct drags: `SetClampedToScreen(true)` on every tracker.
  2. Group bulk moves (programmatic): compute children bbox via `GetScreenRect`,
     **clamp the delta** so the bbox can't cross `GuiRoot` edges.
  3. On init + `EVENT_SCREEN_RESIZED`: re-clamp all stored positions into the
     current screen.
  4. Numeric x/y entry clamped on commit.
- **Precision**: numeric x/y + anchor-point dropdown, arrow-key nudge, optional
  **grid snap** (off by default), **alignment guides** (edges snap-line to other
  trackers).

## Groups (spatial behavior)

Groups have **no area and no stored position** (DESIGN.md). Default layout is
**free** — each tracker keeps its own absolute position; the group only provides
condition inheritance + bulk move (a transient handle derived from the children's
bbox, shown only in move mode). An **optional per-group "stack" layout** (auto-
arrange children vertically/horizontally from a group origin) is available for
bar-packs; off by default.

## Build order within M4

1. Window frame (resizable, two-pane, splitter, tab bar, persisted geometry,
   Toggle) + tree (rows from defs, select, enable, add/delete) + inspector shell.
2. Phases tab: detail editor (simple + advanced) → graph visualization.
3. Conditions + Load tabs.
4. Pickers (ability/set/color/media).
5. Move mode (ghosts, arming, clamping, per-tracker/group).
6. Detach (pop-out), drag-drop, multi-select, alignment guides.

## Authoring UX (added post-M4, alongside the aggregator)

- **Load conditions as removable chips** (`Editor/LoadTab.lua`): Zones, Bosses and
  Skill-ids render as wrapping `×`-to-remove chips instead of a comma string that
  overflowed the buttons. Zones/Bosses keep **+ current** / **clear**; Skill-ids has
  an inline **add-id** box (type an id, Enter → chip; dedupes). Zones key on stable
  `zoneId`; bosses on localized name (EN-now; a name catalog stabilizes this later).
  "+ current" dedupes.
- **Per-phase font family** (Appearance → **Font** card): a family dropdown from
  LibMediaProvider stored on `phase.look.font`; `Display` resolves it via
  `QAT.util.FontFace` and applies it to that phase's readouts (name/timer/stacks).
- **Audio-cue sound dropdown**: an Audio phase picks its cue from a curated,
  self-validating list of `SOUNDS.*` keys (invalid keys dropped, custom preserved),
  previews on pick.
- **Global UI font** (settings panel, `requiresReload`): `sv.account.uiFont`; the
  widget kit rewrites every kit label/editbox face via `QAT.widgets.ApplyUIFace`, so
  both custom windows adopt it. HUD trackers keep their own per-phase fonts.
- **Checkbox widget**: fills solid blue when checked (legible state), 20px, visible
  border — applies everywhere the kit's `Checkbox` is used.
