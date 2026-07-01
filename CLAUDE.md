# WATCHERS — Project Guide

> **First-person co-op horror / friendslop.** Figures creep toward you **only while no one is looking at them** — look at one and it freezes; look away and it advances. Cover 360° of dark between you, complete the facility's tasks, and escape. Tagline: **"Don't Blink."**
>
> **Premium, one-time purchase** ($9.99 target). No live-service / battlepass / gacha / ads / pay-to-win. Cosmetics/maps/modifiers only — never power.
>
> **Status:** playable prototype. All boot scenes are headless-clean (0 script errors). Core gaze-freeze loop, bunker level, 12 tasks, outage system, blob player + detached hands, physics items, and an ENet co-op foundation are all in. The work now is consolidation + polish, not new pillars.

This file is the **source of truth for the current state**. It replaces the old stacked "Update N" changelog (which described a house/3-relays/potato-rig era that no longer exists). Git history has the changelog if you need it.

---

## 1. How to run & validate

- **Engine:** Godot **4.6** (Jolt Physics, Forward+, D3D12). Project root: `C:\Users\Manu\Desktop\w`.
- **Play:** open the project, press **F5**. First scene is `res://scenes/main_menu.tscn` → **Play** → lobby → (step into the elevator, press **E**) → `res://scenes/game.tscn` (the bunker).
- **Editor from terminal:**
  ```
  & "C:\Users\Manu\Downloads\Godot_v4.6.1-stable_win64.exe\Godot_v4.6.1-stable_win64.exe" --path "C:\Users\Manu\Desktop\w"
  ```
- **Headless smoke test** (run after ANY code change — clean = no `SCRIPT ERROR`/`Parse Error` lines). On a fresh machine do one `--import` pass first so `class_name`s register:
  ```
  GODOT="C:\Users\Manu\Downloads\Godot_v4.6.1-stable_win64.exe\Godot_v4.6.1-stable_win64_console.exe"
  & $GODOT --headless --path "C:\Users\Manu\Desktop\w" res://scenes/game.tscn --quit-after 150
  ```
  Validate `res://scenes/main_menu.tscn`, `res://scenes/lobby.tscn`, and `res://scenes/game.tscn` after edits. Loading `lobby`/`game` transitively exercises `player.tscn`, the items, the hands, and the watcher.
  - **Expected harmless noise at exit:** under `--headless` the dummy renderer reports `RID allocations … leaked at exit` / `ObjectDB instances leaked` — this is force-quit teardown of code-built materials/textures, NOT a bug. Only `SCRIPT ERROR`/`Parse Error` matter.
  - Audio one-shots are **skipped under headless** on purpose (`AudioGen.is_headless()`); the dummy driver can't play and would leak active playbacks.
- **Visual checks** (mirror, hands, lighting) need a **real F5 run** — headless can't show them. `tools/capture.gd` + `tools/capture.tscn` boot the lobby and save the first-person view (incl. hands) to a PNG: `godot --path . res://tools/capture.tscn`.

---

## 2. Identity & design pillars (locked)

- **Verb: cover your angle.** The horror is the *handoff* — you must look away to move/work, and that's when the figures move. Co-op divides the angles.
- **First-person is mandatory** — the viewport *is* the mechanic.
- **Funny + scary (friendslop).** Goofy blob bodies, detached cartoon hands, physics props you grab/throw/swing, an emote button. Lobby weapons are **knockback-only, never lethal**.
- **Luxury-hotel lobby → descent → industrial bunker.** The lobby is warm/fancy/slightly cursed; the bunker is oppressive PSX/retro horror.

---

## 3. The core rule (the whole game)

A figure is **frozen** while **any** player has its eye inside a view cone (on the player's *synced aim*) **with clear line-of-sight** (a wall breaks the gaze). See `watcher.gd::_observed_by_any()` — a dot-product cone (~47°) + a wall-only raycast, run for every player. Using the synced aim (not a live `Camera3D` frustum) makes the freeze identical for the host and every client, so there's no proxy-camera desync in co-op.

**Readable tell (the eye is a separate mesh inside the angel's rings):** calm **blue** = frozen/watched, hot flickering **red** = moving, cold white-blue pulse = phone-stunned. One wordless panic signal across a dark room.

**Escalation:** a **phone camera-flash** stuns it solid (hard counter — a limited-use tool, see §6, NOT a throwable); a power **outage** makes it ignore your gaze and keep coming; a long-run **anger** timer (`anger_time`) eventually lets gaze only slow it. (Note: `anger_time` defaults very high — see Known Issues.)

---

## 4. Main scenes & flow

```
main_menu.tscn   Control + ui/main_menu.gd. First scene. Instances lobby.tscn as a live 3D backdrop
                 (backdrop_mode). Play → lobby ; Host Game / Join by IP → ENet session.
lobby.tscn       Node3D + lobby.gd. AUTHORED luxury-hotel warm-up room (191 nodes, hand-edited).
                 Spawns players (blink off), drives the mirror, runs the elevator-start + descent → game.
game.tscn        Node3D "Game" + game.gd (config = default_game.tres, instances bunker.tscn). The gameplay
                 orchestrator: spawns players/watchers, wires tasks, power/outage, HUD, audio, pause.
bunker.tscn      Node3D + (generated by tools/build_bunker.gd). AUTHORED facility (~2123 nodes): rooms +
                 tunnels, baked-trimesh collision, a Nav region, dim cold lights, dressed with PSX props,
                 12 task instances, named markers (PlayerSpawn / WatcherSpawn). Edit in the editor.
entities/player.tscn    CharacterBody3D (WPlayer) + player.gd. Carries a MovementTuning + emote textures.
entities/watcher.tscn   CharacterBody3D (Watcher) + watcher.gd.
tasks/*.tscn            task_relay / task_switches / task_valve / task_capacitors / task_buttons (+ task_carry, spare).
item_pickup.tscn        Look-at "press E to collect" world item (flashlight/phone/keycard/cigs/battery).
keycard_door.tscn, power_reset_button.tscn, mirror.tscn
ui/pause_menu.tscn, ui/options_menu.tscn
items/item_crowbar.tscn, item_fish.tscn, item_baseball_bat.tscn   PhysicsItem toys (the LIVE item system).
```

**Autoloads:** `Net` (`scripts/net.gd`, ENet host/join), `VoiceManager` (`scripts/voice_manager.gd`, mic level + mute/deafen state), `Transition` (`scripts/transition.gd`, fade + threaded scene loads), `PlayerCustomization` (`scripts/player/player_customization.gd`, blob body/face), and `Cursors` (`scripts/cursor_manager.gd`, swaps the OS cursor SHAPES to the Kenney hand set — `hand_point` at rest, `hand_open` on hover, `hand_closed` fist on click, drawing brush/eraser over the customizer canvas; all 32px. The in-game reticle (dot_small, → hand_open over grabbables) is drawn by the HUD since the mouse is captured).

---

## 5. Folder structure

```
actors/
  player/character.tscn        OLD potato rig (character_rig.gd) — DEAD, only a dev screenshot tool uses it.
  player_hands/                detached_hand_left/right.tscn, detached_hands_pair.tscn (the live hands).
  player_models/               player_blob_base/black.tscn (PlayerModelView) — the live player BODY.
assets/        ~1.4GB, ~1283 GLBs: psx/ psx2/ bunkers/ tech/ nature/ van/ models/(angel,hands,furniture)
               audio/{ambience,sfx,ui,music} fonts/ emotes/ player_blobs/. Most psx2 GLBs are unused.
interactions/  grab_point.tscn
items/         PhysicsItem scenes (crowbar/fish/bat).
materials/     player/ (player_outline.gdshader, face_default.tres).
resources/     default_game.tres (GameConfig), movement/default_movement.tres (MovementTuning),
               hand_poses/*.tres (HandPoseResource).
scenes/        main_menu, lobby, game, bunker, entities/, tasks/, ui/, + item/door/button/mirror scenes.
               (house.tscn, main.tscn, test_*.tscn are dead/dev — see §9.)
scripts/       game, player, watcher, lobby, net, voice, voice_manager, power, mirror, item_pickup,
               interactable, keycard_door, red_button, thrown_phone, audio_gen,
               items/physics_item, tasks/*, player/*, resources/*, ui/*, interactions/*.
shaders/       psx_post.gdshader (full-screen PSX dither), watcher.gdshader (body refraction).
systems/       voice_face_driver.gd (mic amplitude → body mouth/face).
tools/         dev-only: build_bunker, build_lobby, shot, capture, measure, dump_glb, wrap_player_glb,
               blender/build_hands.py, etc. (Exclude from shipping builds.)
```

---

## 6. Live gameplay systems

- **Player (`player.gd`, WPlayer).** Resource-driven movement (`MovementTuning`: accel/decel, sprint panic-burst that widens FOV, gravity, crouch, jump), mouse-look (`tuning.mouse_sensitivity * sens_multiplier`, persistent across scenes), head-bob/breath, **blink stamina** (forced eye-shut; drains faster while camping one angle), emote (world billboard others see + POV overlay you see), tools (flashlight torch, **phone camera-flash stun**, comedic cigarette), capacitor carry, knockback + downed/revive. Local owner drives input; remotes interpolate from replicated `net_*`. *(Still a large god-script — a future pass should split items/blink/emote into components.)*
  - **Phone flash (`_try_phone_flash`/`_do_flash_stun`/`_net_flash`).** The cellphone is a **limited-use Watcher stun tool, NOT throwable.** Press V aimed at a figure: owner gates `phone_charges`/cooldown locally + fires the blind-flash FX, then the **authority** validates range (`phone_flash_range`) + aim-cone (`phone_flash_angle`) + line-of-sight and calls `watcher.stun()`. **3 charges**, refilled by a **battery** pickup (which now also tops up the torch). Stun is shortened (`phone_stun_late_mult`) while the power's out. All `@export`-tuned on `player.gd`.
  - **Hand occupancy (torch/item/tool conflict).** One-hand rules so tools don't overlap impossibly: the **torch can't be toggled on while a physics item or two-handed carry occupies your hands**, and grabbing something **snaps the torch off**; the **phone flash is blocked** (`_can_use_tool`) while holding/carrying an item, mid-gesture on a tactile task, or downed (priority: downed > tactile task > held item/carry > tool).
  - **Item targeting = OUTLINE, not glow.** Both `PhysicsItem` and world `ItemPickup`s show a dirty-gold inverted-hull **outline** (`player_outline.gdshader`) while the local player aims at them — `ItemPickup` no longer emits a constant find-glow light. Pickup/grab requires a real **E press**: press EDGES are short-lived timestamps that expire (`PRESS_WINDOW_MS`), so a stale unconsumed tap can't auto-grab the next thing you look at.
- **Player BODY = blob.** `character_scene` defaults to `actors/player_models/player_blob_black.tscn`, a **`PlayerModelView`** (extends the `PlayerCharacter` interface in `scripts/player_character.gd`). No legs; waddle/lean/crouch-squash, face glows while talking (voice "who's talking" tell, no UI). The owner's own body is hidden from their camera via a self render-layer; the mirror still draws it.
- **Detached hands.** `scripts/player/detached_hands_controller.gd` spawns two `DetachedHand`s. The LIVE form (`pose_hands = true`, controller default) is the **low-poly FBX** `assets/models/hands_lowpoly/low_poly_hands.fbx` — 5 swappable POSE meshes per side (open / fist / grab / point / thumbs-up); the controller `set_pose()`s by hand state (idle→open, reach→point, hold→grab, swing→fist, tactile→grab). The FBX imports huge + with its own root transform, so it's instanced under a WRAPPER node that carries `pose_scale`/`pose_euler` (never set rotation on the FBX root directly — it clobbers the import conversion). Older forms remain as fallbacks: a `hand.blend` rounded-cube blob, the procedural spherified cube, and the rigged 3-finger GLBs (`pose_hands=false`). FP rest pose is tuned via the controller's `fp_rest_*` + `fp_*_offset` in `detached_hands_pair.tscn`. Local player sees them as a FP viewmodel; teammates/mirror see them at the body anchors.
- **Watcher (`watcher.gd`).** PS1 "Biblically Accurate Angel" mesh (spinning rings + a separate eye mesh for the tell). Gaze-freeze, NavMesh chase, catch → **downs** the nearest living player (then retreats so a teammate can revive — not instant game-over), phone stun, outage boldness, anger escalation. Server-authoritative, position + tell synced to clients.
- **Tasks (`scripts/tasks/`).** Self-driving `Task` base: finds players via group `"players"`, emits `completed`/`progress_changed`, builds its prop in-editor (`@tool`). Live types (10 placed): **relay** (hold-crank), **switches** (ordered lever pulls), **valve** (rotate), **capacitors** (carry-to-socket), **buttons** (follow-the-light sequence), **keypad** (read a colour code off a readout, reproduce it), **breaker_pattern** (toggle breakers to match a displayed up/down diagram), **dial** (rotate a needle into a drifting target band), **stuck_machine** (meme: slap N times), **pet_cat** (meme: hold to pet the loaf). `task_carry` exists but isn't placed. `game.gd` collects every `Task` in group `"tasks"` and wins when all **active** `counts_toward_win` tasks are done — adding a task needs no `game.gd` change.
  - **Discoverability (no signs).** (1) **Room identity** (`scripts/room_atmosphere.gd`, `RoomAtmosphere`, built by `game.gd::_build_room_atmosphere`): each functional room gets a signature **light colour + looping diegetic hum** (generator=orange/chug, coolant=cyan/hiss, security=green/CRT-fans, electrical=white-blue/buzz, …) so players learn the facility by feel. Data-driven — room centres are derived from the tasks' `zone_display_name` groups, so no bunker edits or hand-placed volumes; the colour lights live under `house/Rooms` so the outage dims them. (2) **Status-lamp beacon** (`Task._update_beacon`): the per-task lamp does a slow "unfinished job" breathe that brightens + pulses faster as a player nears (proximity-driven now; swap for personal-assignment later). Both are pure visual/audio (every peer), not HUD markers. The objectives board (hold TAB) also shows each task's `zone_display_name` room label.
- **Task pool + round selection (`Task` metadata + `game.gd::_select_round_tasks`).** The bunker AUTHORS a large pool (**25 instances** today); each round only a varied SUBSET is **activated**. Each `Task` carries pool metadata (`difficulty` 1-3, `task_category`, `zone_id`, `requires_two_players`/`min_players_required`, `meme_task`/`puzzle_task`, `allow_personal_assignment`). The selector (authority-only, knobs `@export`ed on `game.gd` under "Task pool / round selection") picks `required_solo + per-extra-player` tasks, biased by easy/medium/hard weights, capped per type, spread across the map, gating co-op to ≥2 players and including ≤1 (rare) meme. Selected tasks are `active=true`; the rest `set_active(false)` → drop their beacon + interact targets + stop simulating (set-dressing only). Selection is broadcast to clients for DISPLAY via `_net_apply_selection` (the win tally is already authority-driven via signals, so selection can't cause a wrong win). Personal per-player assignment + round timer/escalation are deferred — the metadata is in place for them. To add pool variety: drop more task instances into `bunker.tscn`'s `Tasks` node.
- **Tactile tasks (`scripts/tasks/tactile_task.gd`, `TactileTask`).** Physical hold-and-gesture interactions (GWF-style): look at the part, HOLD E (the detached hand reaches + grips it), and DRAG the mouse — **down for a lever** (`switches`), **circles for a valve** (`valve`). The local player diverts mouse motion (camera look suppressed) into a replicated monotonic accumulator `WPlayer.tactile_input`; the **authority** task diffs it per frame and advances progress with resistance/decay/strain. Gesture style is on the `Interactable` (`interaction_type` = PRESS/PULL/ROTATE, `hold_prompt`). One active user per task. Subclass overrides `_apply_gesture()` (sign/direction) + `_apply_visual()` (move the part). NOTE: the moving part is positioned on the authority — remote clients don't yet see it animate (a future netcode pass); button/relay poke animations also TODO.
- **Items = PhysicsItem (`scripts/items/physics_item.gd`).** The **one** live item system. A RigidBody that's kinematic-when-held, lerps to a camera-relative hold pose, **E** grab/drop, **hold Q** to charge a throw, **LMB** to swing (windup→active→recovery arc). Hits apply **clamped knockback, never lethal**; a thrown item ignores its own thrower briefly so you can't launch yourself. Per-item feel + optional `HandPoseResource` are exported.
- **Outage / power (`scripts/power.gd`, PowerSystem).** Periodically kills the lights, emboldens the watcher, and arms the glowing red reset button (`power_reset_button.tscn`); players scramble to slam it. All timing/intensity from `GameConfig`.
- **Multiplayer.** `Net` (ENet, default UDP 24545; cross-network needs port-forward or a VPN). `MultiplayerSpawner` spawns a player per peer named by peer id; authority resolves by name. Replicated: transform/aim/emote/voice-mouth/flashlight/smoking/crouch + the `*_held` input flags (the server reads rising edges, so tasks/grabs work identically for host & clients). Watcher/tasks/power/win-lose are server-authoritative. Proximity voice via `scripts/voice.gd`.
- **HUD (`scripts/ui/hud.gd`, GameHUD).** Fully drawn; meters fade in only when relevant (sprint/eyes/flash/voice), bottom-left vitals, bottom-right key prompts, curved throw-charge arc, **hold TAB** objectives board, pickup toasts bottom-left.

---

## 7. Style & UI direction

- **Visual:** PSX/retro — nearest-mip + MSAA 4× + a full-screen dither/colour-reduction pass (`shaders/psx_post.gdshader`, added by `game.gd`/`lobby.gd`). Lobby = warm/fancy/cursed; bunker = cold/industrial/oppressive.
- **UI palette (shared HUD + menus via `MenuUI`):** champagne **gold** on warm charcoal, ivory text. **Red is reserved for danger only.** Prompts are **key-only** (no boxes): interaction prompt bottom-middle, item actions bottom-right with key glyphs, status bottom-left.
- **Fonts — keep it to TWO in menus:** **Daydream** (the "WATCHERS" pixel logo) + **Super Pandora** (everything readable — buttons, taglines, hints). Cinzel is used only for the in-game HUD objectives board. `MenuUI.tagline()` uses Super Pandora so menus stay at two fonts — don't reintroduce a third.
- **Input** is all through the Input Map (`project.godot`) so it stays remappable. Use `Input.is_action_*` / `get_vector(...)`, never raw `KEY_*`.

| Action (Input Map) | Key | Notes |
|---|---|---|
| `move_*` | WASD / arrows | |
| look | Mouse | captured during play |
| `sprint` | Shift | panic burst — faster but widens FOV; stamina-gated |
| `jump` / `crouch` | Space / Ctrl | |
| `interact` | E | look-at + press/hold: tasks, pickups, grab/drop items, revive, elevator start, red button |
| `attack` | LMB | swing a held PhysicsItem |
| `throw` | Q | hold to charge, release to throw a held PhysicsItem |
| `flashlight` | G | toggle the battery-limited torch (the real light — headlamp is OFF by default) |
| `throw_phone` | V | **phone camera-flash** — stuns the watcher (range + aim-cone + line-of-sight). 3 charges, cooldown, refill at a battery. (Action name is legacy; it is NOT a throw anymore.) |
| `smoke` | C | purely comedic cigarette |
| `emote` | hold F | middle-finger billboard + vine boom |
| `objectives` | hold TAB | full objectives board |
| `voice_mute` / `voice_deafen` | M / N | |
| `pause` | Esc | pause menu (in lobby: opens pause; MP pause is local-only) |
| `restart` | R | solo only |

---

## 8. Tuning cheat-sheet (symptom → knob → file)

| Symptom | Knob | Where |
|---|---|---|
| Movement feel (speed/accel/sprint/sens/bob/FOV) | `MovementTuning` | `resources/movement/default_movement.tres` |
| Difficulty: watcher count/speed/catch, task length, outage timing, flashlight/cig feel | `GameConfig` | `resources/default_game.tres` (Inspector) |
| Too dark / bright | `ambient_energy`, `fog_density` (game.gd @export); flashlight `@export`s on `player.gd` | game.gd / player.gd |
| Watcher speed / catch / separation / anger / stun | `MOVE_SPEED`, `CATCH_DIST`, `SEP_*`, `anger_*`, `stun_time` (@export) | `watcher.gd` |
| Danger vignette + heartbeat | `danger_range` (GameConfig), `heart_*` (@export) | `game.gd` |
| Blink / camping | `blink_*`, `stare_drain`/`move_drain` (@export) | `player.gd` |
| Item weight/throw/swing/knockback/hold-pose | per-item `@export`s + `HandPoseResource` | `items/item_*.tscn`, `physics_item.gd` |
| Task specifics (charge rate, sequence length, etc.) | per-task `@export`s | `scripts/tasks/task_*.gd` |
| Hand look / curl / FP rest pose | `@export`s | `detached_hand.gd`, `detached_hands_controller.gd` |

Feel-values are **`@export`/Resource now, not `const`** — tune in the Inspector. A few internal `const`s remain (audio dBs, some watcher constants) — promote to `@export` when you next tune them live.

---

## 9. Do-NOT-use / dead systems (don't revive these)

- **Old melee system** — removed. There is no `held_melee` / `MELEE_MODELS` / `_update_melee` / weapon viewmodel anymore. **Crowbar/fish/bat are `PhysicsItem` only.** Don't reintroduce a second swing path in `player.gd`.
- **`house.tscn` + `house.gd` + `tools/build_house.gd`** — the old mansion, superseded by `bunker.tscn`. Dead.
- **`scenes/main.tscn`** — an orphan stub duplicate of `game.tscn`. Don't use it; `game.tscn` is the real gameplay scene.
- **`character_rig.gd` (potato) + `actors/player/character.tscn`** — the old player rig; the live body is the **blob** (`PlayerModelView`). Only a dev screenshot tool references the potato.
- **`tools/build_gangbeast_character.gd`** — builds scenes that have been deleted. Dead.
- **`scenes/test_*.tscn` + `scripts/test_*.gd`** — dev harnesses; not in the game flow.
- **NEVER regenerate `lobby.tscn` via `tools/build_lobby.gd`** — the lobby is hand-edited; the generator overwrites it. Edit the scene directly. (Same spirit for `bunker.tscn`: prefer editing the scene over re-running `build_bunker.gd`.)
- **Don't re-export the blob player model or the hand GLBs** without asking — they're hand-tuned; prefer code-side fixes.

---

## 10. Known current issues

- **Lobby visual bugs** (need a live F5 pass): bat invisible, elevator blocked, mirror glitch, stretched painting.
- **Music license risk:** `assets/audio/music/lobby_jazz.mp3` is a YouTube "No Copyright" track — **NOT verified for commercial release**. See `assets/audio/music/LICENSE_NOTES.md`. Shipping blocker until verified or replaced. (It's also a 72MB `.mp3` that should become `.ogg`.)
- **Export bloat:** `export_presets.cfg` uses `export_filter="all_resources"` → the whole ~1.4GB asset tree (incl. unused `psx2/`) bundles into the build. Add include/exclude filters before shipping.
- **`player.gd` is large** (god-script) — split items/blink/emote into components in a future pass.
- **`game.tscn` references a stale UID** for `bunker.tscn` (`uid://…`); it falls back to the text path (harmless warning). Re-saving `game.tscn` in the editor clears it.
- **`anger_time`** defaults very high, so the watcher's anger escalation effectively never fires in a normal run — tune it or treat it as latent.
- **Client-side hands** only grip a `PhysicsItem` for the local holder (held_item isn't replicated) — a known gap for a future hands/netcode pass, not a regression.

---

## 11. Conventions & gotchas

- **Scenes are hybrid:** a `.tscn` is usually a root node + script; the script builds children in code. The big authored scenes (`bunker.tscn`, `lobby.tscn`) are the exception — edit them in the editor.
- **Feel-values:** `@export` / Resource (Inspector), not `const`.
- **Input:** Input Map only (see §7).
- **Audio:** a MIX — real `.ogg` assets in `assets/audio/{ambience,sfx,ui,music}` **plus** procedural DSP in `scripts/audio_gen.gd` (heartbeat / skitter / vine-boom). Guard one-shots with `AudioGen.is_headless()` so headless runs don't leak playbacks. (There is currently **no Master/Music/SFX/Voice bus split** — a future audio pass should add one so options sliders can route per-category.)
- **First run on a fresh machine:** do one `--import` pass so `class_name`s (`WPlayer`, `Watcher`, `Task`, `PhysicsItem`, `PlayerCharacter`, `AudioGen`, `MenuUI`, …) register, else you'll see "Could not find type" parse errors.
- Use `absf()`/`absi()`, not `abs()` (Variant return breaks `:=` inference).
- GDScript `static var`s holding a RefCounted **leak at exit** (they outlive SceneTree teardown) — build per-instance or free explicitly.
- Related but separate projects: **SHIFT BREAKERS** (`Documents/shift-breakers`) and **SCRAP** (`Documents/scrap`). The dropped sibling **DEEP POCKETS** lives at `Documents/deep-pockets` and is not pursued. Don't conflate any of these with WATCHERS.

---

## 12. Roadmap (next, in priority order)

1. **Ship-blockers:** verify/replace lobby music license; set export filters (drop unused assets).
2. **Consolidation:** split `player.gd` into components; relocate `test_*`/dev tools out of shipping dirs; delete the dead scenes/scripts in §9 once confirmed.
3. **Polish:** fix the 4 lobby visual bugs; add an audio bus layout; tune `anger_time` (or cut it honestly).
4. **Depth:** key-rebinding UI + options persistence; figure variety (a precise-aim fast one, a slow tanky one); use `tech/` assets for more tactile tasks; place the spare carry task.
5. **Netcode hardening:** reconnect handling, MP restart/return-to-lobby, client-side hand gripping of physics items.
