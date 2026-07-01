# Blob player models — Blender source pipeline

Keep your `.blend` files here. Godot ignores `.blend` unless the Blender import addon is on, so
these are just your editable masters. Export `.glb` into `../glb/`.

```
source/   player_blob_base.blend   player_blob_violet.blend  ...   <- you edit these
../glb/   player_blob_violet.glb   ...                              <- you export here
../../../actors/player_models/  player_blob_violet.tscn             <- generated wrapper (see below)
```

## 1. Object / mesh organisation (do this once on the base)

```
PlayerBlob_Root        (Empty, at world origin, rotation 0)
├─ Body                (mesh)            material slot: M_Body
├─ FacePlate           (mesh)            material slot: M_FacePlate   <- SEPARATE object
├─ NeckShadow          (mesh, optional)  material slot: M_NeckShadow
├─ LeftHand            (mesh, optional)   <- detached-hand placeholder, can be hidden
└─ RightHand           (mesh, optional)
```

Rules that make the Godot side "just work":
- **FacePlate is its own object with its own material `M_FacePlate`.** This is what lets Godot
  find it by name and print custom faces onto it. (The wrapper script matches the name/material
  containing "face" — so `FacePlate` / `M_FacePlate` are detected automatically.)
- **FacePlate UVs unwrapped flat into 0–1**, filling the square, not rotated/mirrored. Select the
  plate, `U -> Project from View` (front view) or `U -> Unwrap`, then in the UV editor scale it to
  fill the 0–1 box. A circular face image will sit centred and undistorted.
- **Body and FacePlate do NOT share a material.**
- **Forward = -Y in Blender** so it becomes -Z in Godot (a player walks toward -Z). Point the face
  down Blender's -Y. (If it ends up backwards in Godot, rotate the root 180° about Z in Blender and
  re-apply — do NOT fix it with a code hack.)
- **Apply transforms** on every object: `Object -> Apply -> All Transforms` (location, rotation,
  scale). Exported scale/rotation must be baked in.
- **Origin at the character base/centre**: `Object -> Set Origin -> Origin to 3D Cursor` with the
  cursor at world origin, feet/base on the floor (Z=0). The blob should stand ON y=0 in Godot.
- **Scale**: total height ≈ **1.4–1.6 m** (the player capsule in player.gd is 1.7 m tall, eye height
  from MovementTuning). Match roughly so the model fills the capsule without clipping the floor.
- **Names are clean**: `Body`, `FacePlate`, etc. No `.001` duplicates, no spaces.

Do NOT add: an armature/rig, legs, bones, animations, or an outline mesh. The outline is added in
Godot. This model is intentionally simple.

## 2. Materials (Principled BSDF only — exports cleanly to GLB)

| Slot | Look | Notes |
|---|---|---|
| `M_Body` | muted base colour | this is the per-variant paint; the variant owns the colour |
| `M_FacePlate` | plain light off-white | leave it neutral — Godot prints faces onto it |
| `M_NeckShadow` | dark, matte | optional underside ambient-occlusion fake |
| `M_Hands` | later | only when you add real detached hands |

- Use **Principled BSDF**, base colour + roughness only. No procedural node trees, no image nodes
  on the face (Godot supplies the face image). Complex node graphs do not survive GLB export.
- **Do NOT bake an outline** into the model.

## 3. Painting colour variants

1. Open `player_blob_base.blend`, `Save As` `player_blob_<colour>.blend`.
2. Recolour `M_Body` (and only the body) — muted violet / gray / black / orange / yellow.
3. Leave `M_FacePlate` neutral.
4. Export (Part 11).

## 11. GLB export settings (repeatable)

`File -> Export -> glTF 2.0 (.glb)` into `../glb/` named `player_blob_<colour>.glb`:

- **Format:** `glTF Binary (.glb)`  (single file, textures embedded — no purple in Godot)
- **Include:** Selected Objects = OFF (export the whole `PlayerBlob_Root`). Or ON if you select the
  root + children. Custom Properties = ON (harmless, lets you tag things later).
- **Transform:** `+Y Up` = ON (glTF standard; Godot expects it).
- **Geometry:** Apply Modifiers = ON, UVs = ON, Normals = ON, Tangents = ON (needed for the outline
  normals), Materials = `Export`, Images = `Automatic` (embeds them).
- **Compression:** OFF (Draco adds import friction; the blob is tiny anyway).
- **Animation:** OFF / uncheck everything (no rig yet).

Then in Godot, generate the wrapper scene:

```
"C:\Users\Manu\Downloads\Godot_v4.6.1-stable_win64.exe\Godot_v4.6.1-stable_win64_console.exe" \
  --headless --path "C:\Users\Manu\Desktop\w" --import
"C:\Users\Manu\Downloads\Godot_v4.6.1-stable_win64.exe\Godot_v4.6.1-stable_win64_console.exe" \
  --headless --path "C:\Users\Manu\Desktop\w" --script res://tools/wrap_player_glb.gd
```

(or just instance the GLB under `actors/player_models/player_blob_base.tscn` by hand and Save As.)
