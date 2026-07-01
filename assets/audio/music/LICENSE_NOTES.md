# Music — License Notes

> ⚠️ **SHIPPING BLOCKER UNTIL VERIFIED.** Do not ship a paid/commercial build of
> WATCHERS using any track listed here as "NOT VERIFIED".

## lobby_jazz.mp3  (lobby + main-menu backdrop music)

- **Used by:** `res://scenes/lobby.tscn`, `res://tools/build_lobby.gd`
  (the main menu plays it indirectly by instancing the lobby as a `backdrop_mode` backdrop).
- **Apparent source:** a YouTube "No Copyright" upload, original filename:
  `(No copyright) relaxing music for restaurant, luxury hotel, jazz piano bar (FREE) [xq5TDWwDEHw].mp3`
  (YouTube video id `xq5TDWwDEHw`).
- **License status:** ❌ **NOT VERIFIED for commercial release.**
  "No Copyright Music" / "Free" uploads on YouTube are routinely **not** actually cleared
  for use in a paid product. The label "(No copyright)" / "(FREE)" is **not** proof of a
  commercial license. No written license, receipt, or attribution terms are on file in this repo.
- **Required before shipping (pick one):**
  1. Obtain and store written proof of a commercial license / royalty-free terms for this exact
     track (save the proof next to this file and update the status to ✅ VERIFIED), **or**
  2. Replace it with a track you can prove is cleared (e.g. a purchased asset-store music pack,
     CC0/public-domain, or commissioned original), **or**
  3. Compose/commission an original lobby jazz cue.

## Format / housekeeping TODO

- This track is currently a **72 MB `.mp3`**. Godot prefers **`.ogg` (Vorbis)** for game audio
  (smaller, seamless looping). Convert `lobby_jazz.mp3` → `lobby_jazz.ogg` and update the two
  references above when an encoder (`ffmpeg`/`oggenc`) is available. *(Not converted yet — no
  audio encoder was available in the cleanup environment.)*
- A byte-identical duplicate previously sat in the project **root**; it has been removed.
  Keep music **only** in `res://assets/audio/music/`.

_Last reviewed: 2026-06-15 (automated audit cleanup). Status above is the source of truth —
update it the moment license proof exists._
