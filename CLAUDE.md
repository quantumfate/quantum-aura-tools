# CLAUDE.md — working notes for Quantum's Aura Tools (QAT)

ESO addon. Phase-based aura / uptime / raid-mechanic tracker. Clean-room rewrite of
HyperTools (no shared code). Namespace `QAT`, SavedVars `QuantumAuraToolsSV`, slash
`/qat`, API `101050`, MIT. Deps: LibAddonMenu-2.0, LibSets, LibMediaProvider,
LibAsync, LibGroupBroadcast (optional LibDebugLogger). Lua 5.1.

Deep docs: `DESIGN.md` (architecture/plan), `EDITOR.md` (editor design),
`AGGREGATOR.md` (M5 effect-aggregator data model + Claude-design brief). Cross-
session facts live in auto-memory (`MEMORY.md` index + files) — read those for the
grilled specs; this file is the always-loaded quick reference.

## Working here

- The user drives design and tests in-game; iterate in tight loops. Give a
  recommendation, not a survey. Relay outcomes plainly.
- Responses are terse ("caveman" — a SessionStart hook, always on). Code, commits
  and security/irreversible warnings are written normally.
- Commit only when asked / when a feature is verified working in-game. On the
  default branch the user commits directly (their flow). Commit trailer:
  `Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>`. Conventional-commit
  style subjects.

## Golden rules

- **Never hardcode ESO install paths.** Use the user's `ESO_*` env vars
  (`ESO_LIVE_ADDONS_DIR`, `ESO_LIVE_SV_DIR`, …).
- **Work on LIVE, not PTS.** The repo is symlinked into the live AddOns folder as
  `QuantumAuraTools`, so edits are live after `/reloadui` — no deploy step.
- **Every changed Lua file:** `luac -p <file>` (syntax) then `stylua <file>` (format;
  tabs, per `stylua.toml`). Do both before handing back.
- **Comments:** industry best practice + LuaCATS annotations. No HyperTools or
  milestone/"M4" references in code comments.
- Don't commit logging/diagnostics — strip them once a bug is found.
- ESOUI hosting: no confirmed site-wide AI ban, but some authors mark repos
  "no AI"; the real review risk is clean-room/attribution, which is handled.

## Dev commands (justfile)

`just fmt` (stylua all) · `just check` (fmt + syntax) · `just link [pts]` (symlink)
· `just logs [D|V] [pts]` (this addon's LibDebugLogger entries) · `just errors [pts]`
(script-error log) · `just setup` / `just update-esoui` (fetch esoui source + LSP
stubs). Reading logs: LibDebugLogger flushes to `SavedVariables/LibDebugLogger.lua`
**only on /reloadui or logout**, and `minLogLevel` defaults to Info (drops Debug) —
so reproduce → `/reloadui` → read. The user often pastes `[tag]`-filtered lines.

## Architecture / file map (load order = manifest)

- **Core/** — `Init` (bootstrap, `/qat`, `QAT.Safe` pcall guard), `Log` (LibDebugLogger
  sub-loggers), `Strings`, `Schema` (**the data model**), `Migrations`, `Util`.
- **Engine/** — `Conditions` (load-condition eval + set/gear helpers), `Tracker`,
  `Runtime` (event-driven; filtered `EVENT_EFFECT_CHANGED`, minimal render tick).
- **Display/** — `Display` (HUD draw kit), `Cues` (sound/flash).
- **Editor/** — `Widgets` (control kit), `Dialogs`, `Window` (two-pane frame +
  splitter), `Tree`, `Inspector`, `AppearanceTab`/`BehaviorTab`/`ConditionsTab`/
  `LoadTab` (per-scope renderers).
- **Examples/SampleTrackers**, **Settings/Settings** (LAM panel), **Bindings**.

## Key concepts

- **Schema (Core/Schema.lua):** every tracker = `phases` + per-phase source-attached
  `transitions` (`{when,to}`, first-match-wins; triggers: effect gained/faded,
  stacks/remaining thresholds, timer-end). `idle` is a real hidden phase
  (`look.display="none"`). `def.initial` = starting phase. Groups are folders
  (`kind="folder"`, `children`), never tracked; their load cascades to members.
  `QAT.CanonicalizeDef(def)` normalizes and **replaces `phase.look` with a new
  table** — see the orphan trap below.
- **Editor IA = scope in the tree** (not tabs): selecting a tracker/its "Load
  conditions" row → aura-wide **Load** scope; a phase row → that phase's
  **Appearance/Behavior/Conditions** tabs. `QAT.editor.selectedId` /
  `selectedScope` ("load"|"phase") / `selectedPhaseId`. `Inspector.refreshBody`
  renders the active renderer from `QAT.editor.tabRenderers[name]`.
- **Control pool** (`Widgets`: NewPool/PoolBegin/PoolGet/PoolEnd) — controls are
  reused across renders (ESO can't destroy controls); pooled controls keep their
  **first-creation parent**. Unused ones are hidden by PoolEnd.
- **Widget kit (Editor/Widgets.lua):** Clickable (CT_CONTROL + bg), Panel, Label,
  TextButton, Checkbox, IconButton, IconWell, Card, Dropdown, EditBox, ColorSwatch,
  Slider, Chip, Badge (colored), CloseButton, Tooltip, ItemTooltip. Shared palette
  `QAT.widgets.palette`.
- **Scroll = ZO_ScrollContainer.** Manual y-offset scrolling can't clip (rows spill
  out of the window). Inspector body and tree both use `CreateControlFromVirtual(…,
  "ZO_ScrollContainer")` → `GetControl(sc,"ScrollChild")` with
  `SetResizeToFitDescendents(true)`. Renderers lay out against a **viewport width**
  passed in (the resize-to-fit child's own width can't be read for layout);
  edge-anchored buttons anchor to their card, not the child.

## Set/load conditions (Engine/Conditions.lua)

Set conditions are **gear placement**, never drawn-bar dependent: `SetSatisfied`
mode `any` (body/jewelry + better weapon bar) / `front` / `back`. `ScanEquippedSets`
reads worn gear → grouped entries (pieces, bar from weapon placement, slots,
category). LibSets helpers: `SetName`, `SetItemLink` (chest→head→any for
icon/tooltip), `SetHasWeapons` (only weapon sets get a bar choice). Everything
matches stable IDs (setId/abilityId/zoneId/classId), never localized names.

## ESO gotchas that bit us (also in [[eso-ui-gotchas]])

- Clickable must be CT_CONTROL, not CT_BACKDROP.
- **Never SetHidden a control inside its own mouse handler** — strands ESO's mouse
  capture and eats the next click everywhere; defer with `zo_callLater(fn, 0)`.
- **Handlers must re-fetch `phase.look` at call time** — capturing `look=phase.look`
  breaks after CanonicalizeDef replaces the table (edits silently discarded).
- CT_BACKDROP edges don't always redraw after a pooled control resizes — re-assert
  `SetEdgeTexture` after `SetDimensions`.

## Status & next

Engine M0–M3 done. **M4 editor done** (scope-in-tree nav, expandable groups, HUD
drag-to-move, ZO_ScrollContainer scroll, set load conditions + live current-loadout
picker).

**M5 Effect Aggregator done.** `Engine/Capture.lua` + `Editor/Aggregator*.lua`:
two fused feeds (combat effect-gained + unit-filtered `EVENT_EFFECT_CHANGED` on
player/reticleover/boss1-6 + seed-sweep), name-keyed dedup (`abilityId + sourceName
+ targetName + zoneId`), relationship buckets (Boss→Self is the money bucket),
filter/list/teaching-inspector window, one-click build-tracker, pin/ignore persisted
(`sv.capture`, schema 6). Background capture default OFF. `/qat aggregator`. Full
spec + as-built notes: `AGGREGATOR.md` and [[m5-aggregator-design]]. Also landed
alongside: load-condition chips, per-phase + global LibMediaProvider fonts, audio-cue
sound picker (see `EDITOR.md` "Authoring UX"). **Capture now persists by default**
(`sv.capture.records`, schema 9; opt-out `account.persistCapture` + "Clear captured
library" in settings); favourites are a subset flag on top.

**Group grid layout done** (schema 8, headline display feature): a group can become a
drawn table (`def.grid`) — rows×cols, headers, styled cells, fill/fake-growth. Editor
`Editor/GridTab.lua` (scope "grid" on a "Grid layout" tree row), chrome `Display/Grid.lua`,
per-tick layout `Engine/GridLayout.lua`. Retired per-layer x/y offsets → 9-point align.
Spec: `DESIGN.md` "Group grid layout" + [[group-grid-layout]].

**Next: M6 raid library** + named-boss load condition (target a boss by name; engine
resolves the live slot; dropdown fed by aggregator-harvested names). Backlog:
searchable set/ability picker, categorize sets via `LibSets.GetSetInfo.setType`,
localization engine + boss/name catalog, polish/ESOUI release (M7).
