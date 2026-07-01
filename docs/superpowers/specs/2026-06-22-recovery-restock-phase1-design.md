# WATCHERS — Recovery / Restock Pass, Phase 1 (vertical slice)

Date: 2026-06-22
Status: approved, implementing

## Goal

Move the core objective loop away from random minigame tasks toward a REPO-style
**physical object recovery / restock** loop. Phase 1 proves the spine end-to-end:

```
descend → find physical objects in the bunker → carry them back to the elevator →
drop them in the loading bay → they're restocked → quotas fill → win (elevator goes up)
```

This is one of several phases. Deferred to later phases (their own spec each):
scanner tool, fragile/break system, phone-battery integration, Watcher escalation tied
to progress, personal assignments, meme objectives (cat / vending), full migration cleanup.

## Decisions (from brainstorming)

- **Win source:** recovery REPLACES the task win for this round. Old minigame tasks are
  set inactive (`set_active(false)`) so they stay as set-dressing — no deletion.
- **Progress model:** per-category quotas (e.g. FOOD 0/3, DRINKS 0/2, ELECTRONICS 0/1).
  Win when every category quota is met.
- **Delivery:** drop the object in an Area3D loading bay inside the elevator; once it
  comes to REST (low velocity) for ~0.5s it's accepted (chime + sink-into-crate + count).
  No extra button; can't count a thrown object that's still bouncing.
- **Placement:** code-built by the manager, anchored to existing Task world positions
  (real rooms, reachable, spread across zones). No edit to the 2123-node bunker.tscn —
  fully reversible. (Refinement of the earlier "instance a sub-scene" idea.)

## Components (clear boundaries)

- `RecoverableObject extends PhysicsItem` (`scripts/objectives/recoverable_object.gd`)
  — the ONLY new item type. Inherits grab/carry/throw/hold + netcode unchanged. Adds
  metadata (`object_id`, `display_name`, `category`, `value`, `required`; fragile fields
  reserved/inert) and `mark_delivered()` (freeze, hide, leave physics). Knows nothing
  about quotas or the elevator.
- `ElevatorDeliveryZone extends Area3D` (`scripts/objectives/elevator_delivery_zone.gd`)
  — detects `RecoverableObject`s resting inside it and emits `object_settled`. Authority
  only. Knows nothing about win.
- `RecoveryManager extends Node` (`scripts/objectives/recovery_manager.gd`) — authority-
  owned. Spawns the round's objects at task anchors, builds the delivery zone at the
  elevator, holds the per-category quotas, validates deliveries (`try_deliver`), and
  emits `objective_complete` → `game.gd._win()` (same shape as `_on_task_completed`).
  Replicates quota counts to clients for the HUD only (win stays authority-driven).

## Multiplayer authority

- Objects spawned deterministically on every peer (stable parent + stable names), so
  paths match and `PhysicsItem`'s existing `MultiplayerSynchronizer` (authority=1) syncs
  position; clients stay frozen.
- Only the authority runs delivery validation and mutates quota counts → no double-deliver.
- Acceptance broadcast via `RecoveryManager._net_deliver.rpc(idx, category)` so every peer
  hides the object + ticks its display identically.
- MP not yet play-tested (consistent with the existing "client-side hands" caveat).

## HUD

- New `recovery_fn` callback on `GameHUD`. Small **RESTOCK** panel (gold/ivory, top-left)
  listing category `have/need`, ✓ when met. Bottom-left toast `+FOOD` on accept (reuses
  the existing toast). TAB board shows the restock summary when recovery mode is active.

## game.gd wiring

- New `@export var enable_recovery_mode := true`. When on: `_collect_tasks` skips round
  selection and deactivates all tasks; `_build_recovery()` creates the manager and connects
  `objective_complete → _win`. Win text reworded to a restock theme.

## Testing

- Headless smoke (after one `--import` pass): main_menu, lobby, game — no
  `SCRIPT ERROR`/`Parse Error`.
- Manual F5: object rests on spawn, grab/carry/drop/throw works, drop-in-bay settles →
  chime + sink + quota tick, surplus rejected gracefully, all quotas met → win screen.
- `RecoverableObject` stays a strict `PhysicsItem` subclass — crowbar/fish/bat + hands untouched.
