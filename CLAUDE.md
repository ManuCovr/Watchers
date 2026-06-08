# WATCHERS — Project Guide

> First-person co-op horror prototype. Figures creep toward you **only while you aren't looking at them.**
> Look at one → it freezes. Secure 3 relays to escape while covering 360° of dark with one viewport.
> **Status: Week-1 greybox. Core gaze-freeze loop in, headless-clean, lighting tuned for visibility. Confirmed FUN by the dev.**
> **Update: panic-loop systems added (blink/stamina, procedural audio, danger vignette) + project restructured into separate scenes with a main/pause/options menu flow and a remappable Input Map.**
> **Update 2 (co-op pivot): Resource-driven movement (`MovementTuning`) with sprint burst; bigger HOUSE level with only 1–2 watchers; reusable `Task` architecture (relay / carry-vase / switch-sequence); emote/meme button; a LOBBY warm-up scene; flow is menu → lobby → game. Many feel-values moved from `const` to `@export`/Resource so they're editor-editable.**
> **Update 11 (FROM-SCRATCH BUNKER LEVEL + full asset palette + physical tasks + dev screenshot loop): Extracted the REST of the bought packs (they were the "all the assets" the dev meant): `assets/psx2/` (PSX Mega Pack II, 549 GLBs incl. Modular Structures + Buildings warehouse/garage/shed + Machinery), `assets/bunkers/` (83 — TUNNEL KIT: tunnel_straight/junction_four_way/three_way/ancle, blast_door, computer, pipes), `assets/tech/` (63 control-panel buttons), `assets/nature/` (49 trees/grass/ferns), `assets/van/` (kidnapper's van). ~1279 GLBs total imported. NEW PLAYING AREA built FROM SCRATCH: `scenes/bunker.tscn` (`tools/build_bunker.gd`) — a 3×3 grid of 4-way junction ROOMS linked by straight TUNNELS on a 12m grid (hub 6 + straight 6), perimeter openings capped with walls, dim cold bunker lights per room, dressed with crates/pipes/computer, all REAL authored draggable nodes; collision is BAKED TRIMESH straight from each piece's mesh (exact, no box-alignment guessing) + a safety floor box. Marker names (PlayerSpawn/WatcherSpawn/TaskSlot0-5) preserved so `game.gd` is unchanged except `HOUSE_SCENE` now preloads `bunker.tscn`. DELETED `house.tscn` + the old textured-box house approach (build_house.gd left as dead tool). Looks like a real facility — verified by screenshot. LOBBY enlarged (ROOM 12→18, CEIL→6, more lights) + dressed with the VAN + crates/sofa/table/shelf (was a cramped box). PHYSICAL TASKS (Gang-Beasts feel, using replicated `interact_held`): switches→`SwitchSequenceTask` HOLD-to-yank LEVERS that swing on a pivot + spring back, pull in order; relay→`RelayTask` HOLD-to-CRANK a spinning wheel that bleeds back down when you let go; carry→`CarryTask` HOLD-to-drag with heavy spring SWAY, release=drop. Interaction SFX via `Task.play_sfx`. FOOTSTEPS: `player.gd` distance-cadenced spatial `footstep_wood_a_*` on every copy. MIRROR: SubViewport reflection PROVEN to render (dumped its texture = correct room view); material now double-sided + build-time bound. NOTE: the dev screenshot harness (`tools/shot.gd`, custom SceneTree main loop) does NOT composite SubViewport textures onto materials, so the mirror reads black IN THE HARNESS ONLY — needs a live F5 check. DEV TOOLS added: `tools/shot.gd` (instance a scene, optional `cam=x,y,z look=x,y,z`, save PNG — use to SEE the game), `tools/measure.gd` (print model AABBs for modular grids). EDITOR-AUDIO (dev hears nothing in editor, fine in .exe): confirmed NOT a project bug — no muted bus, no editor_settings audio override, audio driver inits clean on a normal run. It's OS-level: Windows **Volume Mixer** has Godot/the run-child muted, or wrong default output device. All scenes verified headless = 0 errors.**

> **Update 10 (POLISH PASS pt.2 — house actually uses PSX, task clarity, mirror, editor-tunable): HOUSE NOW USES THE ASSETS — `build_house.gd` regenerated `house.tscn` (262 nodes) with REAL PSX furniture baked in as draggable nodes (`_furn` = GLB visual + box collider you collide with; `_deco` = decor-only): sofa/coffee table/tv stand/chairs/shelves/cabinets/beds/wardrobes/bedside tables (PSX) + Fridge/Stove/Bathtub/Toilet (FBX, PSX lacks them) + foyer supply crates as choke-point cover + PSX ceiling-lamp models under each light + cobweb decals in corners. Removed the old eyeballed `game.gd::_build_props`. Re-run the generator to regen (don't hand-edit then regen). TASK CLARITY — every `Task` now spawns a floating BEACON (name Label3D + light-shaft, `task.gd::_build_beacon`, hidden on done) so players see WHERE/WHAT; tasks got real titles (\"Charge the relay\", \"Flip the breakers\", \"Carry the fuse to the box\"); `hud.gd` now draws a readable OBJECTIVE LIST (Cinzel, `N/M` count + per-task `[x]/[%]` + progress bar) instead of anonymous pips. LOBBY MIRROR — full-wall planar-reflection mirror (`lobby.gd::_build_mirror`/`_update_mirror`): a SubViewport (`world_3d` = lobby world) with a camera reflected across the glass each frame, shown on a quad (UV-flipped); the mirror SURFACE is on render-layer 19 (cam excludes → no feedback). SELF-VISIBILITY FIX so you can see your OWN body in the mirror: `player.gd` no longer hides the local rig with `visible=false`; instead `PlayerCharacter.set_first_person_layer()` puts your body on render-layer 20 and your own `cam.cull_mask` excludes it — other cameras (the mirror) still draw it. Lobby also dressed with PSX deco. EDITOR-TUNABLE — converted feel consts to `@export` on `watcher.gd` (MOVE_SPEED/CATCH_DIST/SEP_*/creep_accel/eye colours/skitter), `character_rig.gd` (eye/mouth/blink/sway), `lobby.gd` (ROOM/CEIL/throw/grab/etc). WATCHER feel — eases into motion via `creep_accel` ramp (`_cur_speed`) so it lunges, not teleports. AUDIO-IN-EDITOR: NOT a project bug (no muted bus exists; that's why the .exe is fine) — it's editor-local: Editor Settings▸Audio▸Output Device=Default, OR Windows mic permission blocking `enable_input` init in the editor (test by toggling `audio/driver/enable_input=false`). All scenes + MP host path verified headless = 0 errors.**

> **Update 9 (POLISH PASS pt.1 — real assets imported + expressive characters + UI/atmos): KEY DISCOVERY — the "absurd amount of assets" the dev bought were sitting UNEXTRACTED in `C:\Users\Manu\Downloads` (zips/rars), NOT in the project. Extracted+imported a curated set into `assets/`: **PSX Mega Pack** (489 GLBs — `assets/psx/<Furniture|Modular Structures|Lighting|Items & Weapons|Large/Small Props|Electronics & Misc|Decals>/*.glb`; GLB embeds textures so import is clean), **Modular Retro FPS Kit** (44 GLBs `assets/fpskit/` incl. `button_on/off`, columns, floors, stairs, tunnels — for tactile tasks), **Cinzel** serif fonts (`assets/fonts/*.otf`), curated audio (`assets/audio/{ambience,sfx,ui}/*.ogg` from ROT Horror + Echoes kits). 851 assets imported clean. NEW PLAYER CHARACTER (Content-Warning/REPO vibe): `scripts/character_rig.gd` (class_name `PlayerCharacter`) + `actors/player/character.tscn` — a goofy big-eyed potato guy, flat PSX materials, big UNSHADED eyes (readable in dark) w/ jitter+blink, voice-driven mouth, stubby arms, per-player tint. `systems/voice_face_driver.gd` (class_name `VoiceFaceDriver`) maps `WPlayer.net_mouth` (replicated mic amplitude, 0 while self-muted) → jaw flap w/ attack/release smoothing; scream→eyes widen, downed→dead eyes. `player.gd` now instances the rig as `_body`/`_character` (replaced capsule+sphere); added `net_mouth` to the MultiplayerSynchronizer; remotes waddle from net_pos catch-up. You can tell who's talking with NO UI. FPS UNCAPPED (`project.godot`: `run/max_fps=0`, `window/vsync/vsync_mode=0`; still toggleable in Options). "Weird black lines" fix: `msaa_3d=2` (4×) + `use_nearest_mipmap_filter=true` + anisotropy 0 (PSX crunch + kills tiled-texture moiré at grazing angles; if lines persist they're coplanar z-fighting in the code-built house → fixed by the modular rebuild). UI GLOW-UP: `menu_ui.gd` now uses Cinzel (Decorative-Black title, Bold buttons), framed `card()` panel w/ accent spine, hover/click SFX (`gui_click_*`) on every button; main/pause/options use the card. Ambient horror bed loops under gameplay (`game.gd` `_ambient` = `ambience_nightmares_mx_1`). All scenes (menu/game/lobby) verified headless = 0 errors. STILL TODO (next pass, dev chose FULL MODULAR REBUILD): tear out code-built `house.gd` slabs → reassemble from PSX `Modular Structures` GLBs (walls/doorways/windows/stairs) w/ own collision + re-bake navmesh; dense intentional prop placement (use `assets/psx`); revamp lobby w/ real props; Gang-Beasts-style PHYSICAL tasks (grab/drag/crank/lever using FPS-kit `button`/valves); footstep + interaction SFX; watcher AI/pathing polish.**

> **Update 8 (STAIRS FIXED + voice + physics lobby): STAIRS finally work — diagnosed via an automated headless test (`scenes/test_stairs.tscn`): it was NOT collision (steps were layer 2, player mask 2) — the stacked-box step colliders + fragile test_move step-assist jammed the player. FIX: visible stepped MESH (no collision) + a smooth RAMP COLLIDER underneath; plain `move_and_slide` climbs it (verified player Y 0→3.5). Step-assist removed. Floor handling now editor-tunable (`MovementTuning`: floor_snap_length/floor_max_angle_deg/floor_stop_on_slope; walk 4.0, accel 28). PROXIMITY VOICE CHAT (`scripts/voice.gd`, per-player): local mic → `AudioEffectCapture` on a "Mic" bus → RPC frames → spatial `AudioStreamGenerator` `AudioStreamPlayer3D` (distance = proximity). `audio/driver/enable_input=true`. NETWORKED PHYSICS LOBBY (`lobby.gd` rewritten): Host/Join now go menu→LOBBY→(START)→game; players spawn together; throwable RigidBody balls + a BAT (server-simulated, synced; clients frozen+kinematic). E=grab/drop, Left-click(`attack`)=throw/swing; bat swing DOWNS players in front (auto-recover 4s in lobby). All verified host+client headless = 0 errors (mic/physics interactions need live test).**
> **Update 7 (real assets): WATCHER is now the PS1 **Biblically Accurate Angel** (`assets/models/angel/...obj`) rendered as a dark silhouette (eye-tell intact). PSX **furniture** (9 FBX: Couch/TV/Fridge/Stove/Dresser/SingleBed/Toilet/Bathtub/FloorLamp under `assets/models/furniture/`) placed in the house via `game.gd::_build_props()` (decor, no collision, eyeballed transforms — tweak in editor). PSX **car** in lobby. Extracted with WinRAR's UnRAR; the angel `.mtl` had the author's absolute texture paths (stripped `map_Kd` so import is clean). Medieval kit still `.blend` (skipped). All assets imported clean; solo + 2-peer headless verified 0 errors.**
> **Update 6 (co-op playable): players now have VISIBLE bodies (capsule on `BODY_LAYER`, hidden from own cam) so friends see each other + each other's emotes. NETWORKED TASK INTERACTION — clients can do carry/switch tasks too (player `consume_interact()` press intent via `_interact_rpc` to server; tasks loop group "players"). DOWNED + REVIVE — a watcher catch now DOWNS the nearest living player (tips over + "REVIVE (hold E)" Label3D + red overlay) instead of instant game-over; a teammate holds E nearby for `REVIVE_TIME` (3s) to revive (server reads replicated `interact_held`); lose only when ALL players are downed. Solo unchanged (down = instant lose). Verified host+client 2-peer headless = 0 errors.**
> **Update 5 (multiplayer + fixes): HOSTING WORKS — `Net` autoload (ENet, `scripts/net.gd`); main menu has Play(Solo)/Host Co-op/Join by IP. Verified host+client connect + replicate (players sync position/aim/emote via `MultiplayerSynchronizer`; watcher server-authoritative + synced; server owns tasks/win-lose). For cross-network: host port-forwards UDP 24545 (or everyone uses a ZeroTier VPN). Launch flags `-- --host` / `-- --join` for testing. Stairs FIXED (solid steps + player step-assist `_move_with_stairs`). Watcher pathfinding REVERTED to direct movement (it moves again). Slightly darker. Bigger house (80×60, 9 rooms, 6 tasks). PSX car asset (`assets/models/car/Car8.obj`) placed in lobby. KNOWN v1 GAPS: client task-interaction not networked yet (host does interact-tasks; relays work for all via synced gaze); no downed/revive; no voice chat; lobby not yet networked. `.rar` packs (angel/furniture) need extraction (no unrar here); medieval kit is `.blend` (needs Blender).**
> **Update 4 (editor-editable + AI/lighting): the house is now an AUTHORED scene — `scenes/house.tscn` is real, draggable nodes (walls/floors/lights/furniture/`Marker3D` spawns/`NavigationRegion3D`), generated once by `tools/build_house.gd` (a one-time builder; don't re-run it after you hand-edit). `game.gd` loads it, bakes the navmesh, and spawns player/tasks/watcher at the named markers. Stairs fixed (flush no-lip ramp through a gap in both floor slabs). ONE watcher now, and it PATHFINDS via NavMesh (no wall-phasing). Brighter lighting + bright lamps over each task room. Emote split: YOU see `povmiddlefinger.png` (screen overlay), everyone else sees the world billboard (render-layer trick). NEXT (not yet built): ENet host/join netcode → physics lobby (throw/bat/grab) → downed+revive → proximity voice chat.**
> **Update 3 (proper house): two-floor mansion (`house.gd`/`house.tscn`) — ground rooms + central hall + ramp staircase through a hole in the mid-slab + second-floor bedrooms + flat roof + furniture + easter eggs (shrine/duck/sign). Player now has GRAVITY (stairs/ledges work); the second floor is a refuge (watchers are height-gated — no catch/scare from another level). Emote is now a WORLD-SPACE billboard (`Sprite3D`, everyone sees it, hold-to-show, no fade) using `assets/emotes/middlefinger.png`. Mouse sensitivity fixed (persistent `sens_multiplier`, no longer reset on spawn). Lobby expanded: kickable physics balls, strobing disco floor, a BONK dummy, slots, signage.**

> Sibling concept **DEEP POCKETS** was prototyped and **dropped** — it had no true objective (just "don't lose your loot"), which felt hollow. WATCHERS won because the relays give a real win condition. Project still exists at `C:\Users\Manu\Documents\deep-pockets` but is not being pursued.

---

## 1. How to run
- Open in **Godot 4.6**, press **F5**. Main scene is now `res://scenes/main_menu.tscn` — the menu loads first; click **Play** to enter `res://scenes/game.tscn`.
- Terminal (editor):
  ```
  & "C:\Users\Manu\Downloads\Godot_v4.6.1-stable_win64.exe\Godot_v4.6.1-stable_win64.exe" --path "C:\Users\Manu\Documents\watchers"
  ```
- Headless smoke test (after one `--import` pass that registers `class_name`s). The default boot is the menu, so point the test at the **gameplay** scene to exercise player/watchers/relays/audio:
  ```
  & "C:\Users\Manu\Downloads\Godot_v4.6.1-stable_win64.exe\Godot_v4.6.1-stable_win64_console.exe" --headless --path "C:\Users\Manu\Documents\watchers" res://scenes/game.tscn --quit-after 200
  ```
  Clean = engine banner only. `SCRIPT ERROR` lines = something to fix. **Run this after any code change before assuming it works.**
  - Note: audio is procedural (built in code, no assets) and is **skipped under `--headless`** on purpose — the dummy audio driver can't output sound and force-quit would otherwise leak active playbacks. See `AudioGen.is_headless()`.

Engine: **Godot 4.6, Jolt Physics, Forward+, D3D12.**

---

## 2. Controls
All bindings live in the **Input Map** (`project.godot`) and are remappable later.
| | |
|---|---|
| Move | **WASD** / arrows (`move_forward/back/left/right`) |
| Look | **Mouse** (captured during play) |
| Sprint (panic burst) | **Shift** (`sprint`) — faster but **widens FOV** (you cover worse), stamina-gated |
| Interact | **E** (`interact`) — LOOK AT an object (button/lever/valve/capacitor/keycard reader/red button/item) and press/hold E. Also revive, START in lobby |
| Flashlight | **G** (`flashlight`) — toggle the battery-limited torch (essential in the dark / during outages) |
| Throw phone | **V** (`throw_phone`) — one-time cellphone stun: hurl it at the watcher (the late-game counter once it's angry) |
| Smoke | **C** (`smoke`) — light a cigarette: **purely comedic**, available any time (cig in view + drifting smoke, no gameplay effect) |
| Emote (meme) | **HOLD F** (`emote`) — shows a middle finger **in the world in front of you** (everyone sees it) + vine boom. Visible while held. |
| Charge a relay | just **look at it** while standing within range (gaze IS the action) |
| Pause / resume | **Esc** (`pause`) — opens the pause menu, frees the mouse (in lobby: back to main menu) |
| Restart | **R** (`restart`) |

No weapons. **Your gaze is the only tool.** Look at a figure to freeze it; look away and it advances.
A soft **headlamp** is mounted on the camera, so you can always see roughly where you're looking — the periphery stays dark on purpose.
You also **can't keep your eyes open forever**: a stamina meter drains toward a forced **blink** (brief eyes-shut), and it drains *faster while you stand still and camp one angle* — so the game keeps pushing you to reposition and hand off your coverage.

---

## 3. The core rule (the whole game)
A figure is **frozen** when its eye is **inside the camera frustum AND has clear line-of-sight** (a wall breaks the gaze). See `watcher.gd::_is_observed()` — uses `Camera3D.is_position_in_frustum()` + a wall-only raycast. Gives the fair, legible rule: **"if I can see it, it's frozen."**

**Readable tell:** frozen eye = calm **blue**, moving eye = hot flickering **red**. In the gloom that's an instant wordless panic signal.

---

## 4. Architecture (code-built greybox, split into scenes, editor-tunable)
**Hybrid scenes:** each entity/task/menu is its own instantiable `.tscn` (trivial: root node + script; the script builds its greybox children in code). **Feel-values are now `@export`/Resource, not `const`** — editable in the Inspector without digging through scripts (per the editor-friendly direction). `player.tscn` carries a `MovementTuning` resource + the emote texture; `game.tscn`'s root exposes room/threat/lighting/heartbeat `@export` groups.
```
scenes/
  main_menu.tscn          Control + main_menu.gd. FIRST scene loaded (Play→lobby / Options / Quit).
  lobby.tscn              Node3D + lobby.gd. Bright warm-up room (no blink/headlamp); START pad, slots,
						  BONK dummy, disco floor, kickable physics balls, signage.
  game.tscn               Node3D "Game" + game.gd. The gameplay scene; instantiates the House.
  house.tscn              Node3D (House) + house.gd. The 2-floor mansion (geometry + room lights + anchors).
  entities/
	player.tscn           CharacterBody3D (WPlayer) + player.gd  [tuning + emote_texture(png) assigned].
	watcher.tscn          CharacterBody3D (Watcher) + watcher.gd.
  tasks/
	task_relay.tscn       Node3D (RelayTask)  — gaze-charge.
	task_carry.tscn       Node3D (CarryTask)  — carry vase to a drop zone.
	task_switches.tscn    Node3D (SwitchSequenceTask) — press numbered switches in order.
  ui/
	pause_menu.tscn / options_menu.tscn   CanvasLayer + scripts.
scripts/
  game.gd       ORCHESTRATOR. Instantiates the House; spawns player (at `house.player_start`) + watchers +
				task scenes (at `house.task_anchors`); HUD task-checklist, danger vignette, heartbeat, pause,
				win(=all tasks)/lose. @export: Threat (watcher_count/spawn_ring/danger_range), Lighting/Heartbeat.
  house.gd      (House) Builds the mansion: slabs (ground/mid-with-stair-hole/roof), perimeter + interior
				walls w/ doorways, ramp staircase, second-floor rooms, lights, furniture, easter eggs.
				Exposes `task_anchors` + `player_start`. Dims (`half_x/half_z/floor_h`) are @export.
  lobby.gd      Bright pre-game scene + toys (balls/disco/bonk/slots). Spawns player with blink off; START → game.
  player.gd     WPlayer. Resource-driven movement (accel/decel + sprint burst + GRAVITY for stairs), mouse-look
				(`tuning.mouse_sensitivity * sens_multiplier`), head-bob/breath, headlamp, BLINK overlay,
				EMOTE (world-space `Sprite3D` billboard, hold-to-show). Exposes `cam`. Joins group "players".
  watcher.gd    The creeping figure. Observation check, creep-when-unseen, catch, eye tell, skitter audio.
  tasks/task.gd (Task) BASE CLASS. Self-driving: finds players via group "players", emits `completed`/
				`progress_changed`. Subclass overrides `_build()` + `_task_process()`. Greybox mesh helpers.
  tasks/task_relay.gd, task_carry.gd, task_switches.gd   concrete tasks.
  resources/movement_tuning.gd  (MovementTuning : Resource) all movement feel as @export. .tres in /resources/movement.
  audio_gen.gd  (AudioGen) Static DSP — heartbeat / skitter / vine_boom AudioStreamWAVs built in code.
  ui/menu_ui.gd + ui/{main_menu,pause_menu,options_menu}.gd
assets/emotes/middle_finger.svg   placeholder emote art (SVG → texture).
resources/movement/default_movement.tres   the default MovementTuning profile.
```
**Flow:** main menu → **Play → lobby** → (stand on START, press E) → **game**. In-game **Esc** flips `get_tree().paused` + pause menu (`process_mode = ALWAYS`); lobby **Esc** → main menu. Options overlay is reachable from main + pause menus; emits `closed` (no global manager).

**Task contract (the reusable spine):** a `Task` is a self-contained scene. It finds players via the `"players"` group, updates itself each frame, and emits `completed(task)`. `game.gd` just instantiates task scenes at room positions, connects `completed`, and wins when all `counts_toward_win` tasks are done. Adding a new task = new script extending `Task` + a trivial `.tscn`; no changes to `game.gd` required beyond placing it. This is why co-op is additive — tasks don't care *who* acts.

---

## 5. Tuning cheat-sheet (symptom → knob → file)
| Symptom | Knob | File |
|---|---|---|
| **Movement feel (speed/accel/sprint/sens/bob/FOV)** | `MovementTuning` resource | `resources/movement/default_movement.tres` (Inspector) |
| **Too dark / can't see** | ↑ `ambient_energy`/`lamp_energy`, ↓ `fog_density` (game.tscn @export); headlamp `@export`s on player | both |
| Too bright / not scary | reverse the above | both |
| House too big/small | `room_half_extent`, `door_gap` (game.tscn @export) | `game.gd` |
| Figures too fast/slow | `MOVE_SPEED` | `watcher.gd` |
| Caught too easily | `CATCH_DIST` | `watcher.gd` |
| Too easy/hard overall | `watcher_count` (keep 1–2!), `spawn_ring` (game.tscn @export) | `game.gd` |
| Relay charge time | `charge_rate`, `charge_range` (@export) | `task_relay.gd` |
| Carry zone placement | `zone_offset`, `zone_radius` (@export, set per-instance in game.gd) | `task_carry.gd` |
| Switch puzzle length | `switch_count` (@export, set per-instance) | `task_switches.gd` |
| Vignette + heartbeat range | `danger_range` (@export) | `game.gd` |
| Heartbeat loudness/tempo | `heart_min/max_db`, `heart_min/max_pitch` (@export) | `game.gd` |
| Skitter loudness/falloff | `SKITTER_DB`, `SKITTER_MAX_DIST` | `watcher.gd` |
| Blink / camping / emote | `blink_*`, `stare_drain`/`move_drain`, `emote_show_time` (@export) | `player.gd` |
| Figures clump up | `SEP_DIST`, `SEP_FORCE` | `watcher.gd` |

> Most feel-values are now **`@export` (Inspector) or in the `MovementTuning` resource** — open `game.tscn` / `player.tscn` / `default_movement.tres` and tune there. A few internal `const`s remain in `watcher.gd` (`MOVE_SPEED`, `CATCH_DIST`, `SEP_*`) and audio — promote them to `@export` when you next need to tune them live.

---

## 6. Locked design (from the concept session)
- **Verb: cover your angle.** The horror is the *handoff* — you must look away to move/charge, and that's when the others move.
- FP is mandatory: the viewport **is** the mechanic. (Dev prefers FP for immersion.)
- Premium **$9.99**, no live-service / battlepass / FOMO / gacha / ads / subscription / pay-to-win. Local-first; netcode is a later phase. Cosmetics/maps/modifiers only — never power.

---

## 7. Roadmap / next steps
**Phase 1 — feel (current, local)** ✅ verb proven & fun
- [x] **Audio** — skitter (`watcher.gd`), heartbeat (`game.gd`), vine-boom emote (`AudioGen`). Procedural.
- [x] **Blink/stamina**, **danger vignette** (see Update 1).
- [x] **Movement rework** — Resource-driven (`MovementTuning`): accel/decel + sprint panic-burst that widens FOV.
- [x] **Bigger house + 1–2 watchers** — fairness via scale, forces "come watch this while I work".
- [x] **Task system** — reusable `Task` base + relay/carry/switches. Win = all tasks done.
- [x] **Emote/meme** — F → middle finger + vine boom. **Lobby** warm-up scene with START + gamble toy.
- [ ] Tune the **panic curve**: movement tuning / `watcher_count` / task counts against real play.
- [ ] Figure variety (a fast one you must center precisely; a slow tanky one).
- [ ] Settings depth: a proper **key-rebinding UI** on top of the Input Map; persist options to a config file.
- [ ] More tasks (see the big list at the bottom of this file / the brief) + a data-driven level layout.

**Phase 2 — co-op (the real fantasy)**
- [ ] Split-screen or P2P so players literally **divide the angles**. Observation + danger are already per-entity, so this is additive, not a rewrite.

**Phase 3 — content (only after feel + co-op)**
- [ ] More relay layouts / rooms; per-run modifiers; objective variants (carry an item between relays, etc.).

---

## 8. Conventions
- Feel values are `const` at the top of each script. Edit there.
- **Scenes are hybrid:** `.tscn` = root node + script only; the script builds its own children in code. Add new entities the same way (trivial `.tscn`, code-built body) so tuning stays in `const` blocks.
- **Input goes through the Input Map** (`move_*`, `pause`, `restart`, `interact`) so it stays remappable — use `Input.is_action_pressed(...)` / `get_vector(...)`, not raw `KEY_*`.
- **Audio is procedural** (`AudioGen` builds `AudioStreamWAV`s in code; no assets). Skip `play()` under headless via `AudioGen.is_headless()` — active playbacks leak on force-quit otherwise.
- The first run on a fresh machine needs `--import` once so `WPlayer`/`Watcher`/`Relay`/`AudioGen`/menu `class_name`s register, else you'll see "Could not find type" parse errors.
- Watch out for `abs()` (returns Variant, breaks `:=` inference) — use `absf()`/`absi()`.
- GDScript `static var`s that hold a RefCounted (e.g. a cached stream) **leak at exit** — they outlive SceneTree teardown. Build per-instance or free explicitly.
- Related projects: **SHIFT BREAKERS** (`Documents/shift-breakers`, throw/catch relay) and **SCRAP** (`Documents/scrap`, junk-climbing). Don't conflate.
