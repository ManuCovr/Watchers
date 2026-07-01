# Gambling-With-Friends style DETACHED CARTOON hand.
#
# Shape language (replaces the old box-palm + upright-cylinder-fingers test rig):
#   - a SOFT, squashed, slightly-cupped PALM PAD (a flattened low-poly ellipsoid, NOT a cube)
#   - THREE fat, rounded, SHORT teardrop FINGER LOBES: fat rounded tip, slightly tapered base,
#     splayed apart at the tips and tilted forward (the GWF "open starfish mitt" silhouette)
#   - ONE shorter, fatter SIDE THUMB lobe, angled inward toward the fingers
#   - the digits are DETACHED ISLANDS that float just above the palm (small intentional gaps =
#     soft shadow separation, NOT boolean cuts), but spacing + gesture read as ONE hand
#   - low-poly + FLAT shaded -> faceted-but-soft (the WATCHERS PSX look), no remesh, no metaballs
#
# Built UPRIGHT (fingers +Z, back-of-hand toward -Y) so the Blender front render ~ the FP view and the
# controller's existing rest pitch/yaw still apply. Rig (UNCHANGED names — the game finds these):
#   root / palm / finger_a / finger_b / finger_c / finger_thumb
# Each digit island is weighted 100% to its own bone, so curling a bone rotates that whole floating
# lobe about its base -> "detached digit closing toward the palm".
#
# Run: blender --background --python tools/blender/build_hands.py

import bpy, os, math
from mathutils import Euler, Vector

PROJECT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
DESKTOP = os.path.dirname(PROJECT)                       # the user keeps watchers_hand.blend here
OUT_DIR = os.path.join(PROJECT, "assets", "models", "hands")
os.makedirs(OUT_DIR, exist_ok=True)

# ---- shape spec (Blender units; engine model_scale ~0.34) -------------------
# PALM: soft squashed pad — slightly WIDER than tall, THIN front-to-back, gently cupped.
PALM_HALF   = (0.165, 0.058, 0.125)   # half-extents (X width, Y depth/thin, Z height)
PALM_CUP    = 0.05                     # how far the front face dishes inward (concave palm)
PALM_SEG, PALM_RING = 12, 8

# FINGER LOBE: short + stubby, FAT rounded tip, slightly narrower base (teardrop).
F_LEN       = 0.250                    # length base->tip (short + stubby)
F_TIP_R     = 0.092                    # FAT rounded tip radius (GWF chubby digit)
F_BASE_R    = 0.058                    # only slightly tapered base (sinks INTO the palm, hides point)
F_DEPTH     = 0.92                     # front/back squash (slightly flatter than round)
F_SEG, F_RING = 9, 7                   # low-poly faceted lobe (a ring more = rounder fat cap)

# Three fingers: bases SINK into the palm (overlap, no air gap -> reads as one hand), tips fan WIDE in
# the view plane (the GWF "open splat"), only a little forward tilt so all three stay visible.
#   (base_x, base_z, splay_deg [+ = tip outward], tilt_fwd_deg, extra_len)
FINGERS = [
    ("finger_a", -0.100, 0.050, 26.0,  4.0, 0.00),   # outer — splayed wide
    ("finger_b",  0.000, 0.075,  0.0,  3.0, 0.035),  # middle — central, tallest, straight up
    ("finger_c",  0.100, 0.050, 26.0,  4.0, 0.00),   # outer — splayed wide
]
# Thumb: shorter, fatter, side-mounted low, angled up-and-INWARD across the palm + forward.
TH_LEN, TH_TIP_R, TH_BASE_R = 0.170, 0.078, 0.056
TH_BASE     = (0.140, 0.012, -0.010)   # (x, y forward, z) base tucked into the +side of the palm
TH_INWARD   = 46.0                     # yaw toward the fingers
TH_FWD      = 22.0                     # tilt forward
TH_UP       = 18.0                     # raise the tip a little


def clear():
    bpy.ops.wm.read_factory_settings(use_empty=True)


def mk_mat(name, rgb, rough=0.9):
    m = bpy.data.materials.get(name) or bpy.data.materials.new(name)
    m.use_nodes = True
    b = m.node_tree.nodes.get("Principled BSDF")
    if b:
        b.inputs["Base Color"].default_value = (rgb[0], rgb[1], rgb[2], 1.0)
        b.inputs["Roughness"].default_value = rough
    return m


def _smooth(t):
    return t * t * (3.0 - 2.0 * t)


def lobe(name, loc, length, tip_r, base_r, depth, rot_euler):
    """A fat tapered teardrop: rounded fat tip, slightly narrower base. Origin/base at z=0 local,
    so the object rotation (rot_euler) pivots about the BASE -> clean splay + bone alignment."""
    bpy.ops.mesh.primitive_uv_sphere_add(segments=F_SEG, ring_count=F_RING, radius=1.0,
                                         location=(0, 0, 0))
    ob = bpy.context.active_object
    ob.name = name
    me = ob.data
    for v in me.vertices:
        t = (v.co.z * 0.5) + 0.5                 # 0 at bottom (base) .. 1 at top (tip)
        w = base_r + (tip_r - base_r) * _smooth(t)
        v.co.x *= w
        v.co.y *= w * depth
        v.co.z = t * length                      # base sits at z=0, tip at z=length
    ob.rotation_euler = Euler(rot_euler, 'XYZ')
    ob.location = loc
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    return ob


def palm_pad(name, half, cup):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=PALM_SEG, ring_count=PALM_RING, radius=1.0,
                                         location=(0, 0, 0))
    ob = bpy.context.active_object
    ob.name = name
    me = ob.data
    for v in me.vertices:
        v.co.x *= half[0]
        v.co.y *= half[1]
        v.co.z *= half[2]
        # dish the FRONT face (-Y) inward a touch so the palm is gently cupped, not a bulge
        if v.co.y < 0.0:
            n = min(1.0, ((v.co.x / half[0]) ** 2 + (v.co.z / half[2]) ** 2))
            v.co.y += cup * (1.0 - n)
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    return ob


def assign_group(ob, group_name):
    vg = ob.vertex_groups.new(name=group_name)
    vg.add(list(range(len(ob.data.vertices))), 1.0, 'REPLACE')


def finger_rot(splay_deg, tilt_fwd_deg, placed_x):
    # +tilt about X leans the +Z tip forward (toward -Y / the camera). Splay about Y fans each tip AWAY
    # from centre, based on the finger's OWN side (sign of its placed x) so both outers open outward.
    s = 0.0 if abs(placed_x) < 1e-5 else (1.0 if placed_x > 0 else -1.0)
    return (math.radians(tilt_fwd_deg), math.radians(s * splay_deg), 0.0)


def dir_from_euler(rot_euler):
    return Euler(rot_euler, 'XYZ').to_matrix() @ Vector((0, 0, 1))


def build_hand(side):
    clear()
    mat_skin = mk_mat("HandMat", (0.85, 0.72, 0.5))

    palm = palm_pad("palm", PALM_HALF, PALM_CUP)
    assign_group(palm, "palm")
    parts = [palm]

    # bases sink INTO the palm (overlap) so the hand reads as one unit; the detached look comes from
    # the grooves BETWEEN the separate islands, not an air gap under them.
    GAP = 0.0

    digit_info = {}   # bone_name -> (base_pos, dir, length)
    for nm, bx, bz, splay, tilt, extra in FINGERS:
        placed_x = side * bx
        rot = finger_rot(splay, tilt, placed_x)
        base = (placed_x, -0.01, bz + GAP)
        ob = lobe(nm, base, F_LEN + extra, F_TIP_R, F_BASE_R, F_DEPTH, rot)
        assign_group(ob, nm)
        parts.append(ob)
        digit_info[nm] = (Vector(base), dir_from_euler(rot), F_LEN + extra)

    # thumb
    th_rot = (math.radians(TH_FWD), math.radians(-side * TH_INWARD), math.radians(side * TH_UP))
    th_base = (side * TH_BASE[0], TH_BASE[1] - 0.01, TH_BASE[2])
    th = lobe("finger_thumb", th_base, TH_LEN, TH_TIP_R, TH_BASE_R, F_DEPTH, th_rot)
    assign_group(th, "finger_thumb")
    parts.append(th)
    digit_info["finger_thumb"] = (Vector(th_base), dir_from_euler(th_rot), TH_LEN)

    # JOIN into one skinned mesh (islands stay separate -> detached look; groups survive the join)
    bpy.ops.object.select_all(action='DESELECT')
    for p in parts:
        p.select_set(True)
    bpy.context.view_layer.objects.active = palm
    bpy.ops.object.join()
    hand = bpy.context.active_object
    hand.name = "hand_mesh"
    bpy.ops.object.shade_flat()                  # FLAT = faceted-but-soft (the WATCHERS PSX look)
    hand.data.materials.clear(); hand.data.materials.append(mat_skin)

    # --- Armature (same bone names the game looks up) ---
    arm_data = bpy.data.armatures.new("HandArmature")
    arm = bpy.data.objects.new("HandArmature", arm_data)
    bpy.context.collection.objects.link(arm)
    bpy.context.view_layer.objects.active = arm
    bpy.ops.object.mode_set(mode='EDIT')
    eb = arm_data.edit_bones
    root = eb.new("root"); root.head = (0, 0, -0.30); root.tail = (0, 0, -0.12)
    palm_b = eb.new("palm"); palm_b.head = (0, 0, -0.12); palm_b.tail = (0, 0, PALM_HALF[2]); palm_b.parent = root
    for nm, _bx, _bz, _s, _t, _e in FINGERS:
        base, d, ln = digit_info[nm]
        b = eb.new(nm); b.head = base; b.tail = base + d * ln; b.parent = palm_b
    base, d, ln = digit_info["finger_thumb"]
    bt = eb.new("finger_thumb"); bt.head = base; bt.tail = base + d * ln; bt.parent = palm_b
    bpy.ops.object.mode_set(mode='OBJECT')

    # Parent using the EXISTING vertex groups (rigid per-digit) — NOT auto weights, so a digit is
    # never partly driven by a neighbour bone.
    bpy.ops.object.select_all(action='DESELECT')
    hand.select_set(True); arm.select_set(True)
    bpy.context.view_layer.objects.active = arm
    bpy.ops.object.parent_set(type='ARMATURE_NAME')
    return arm


def export(side, filename, save_blend=False):
    build_hand(side)
    if save_blend:
        bpy.ops.wm.save_as_mainfile(filepath=os.path.join(OUT_DIR, "hand_source.blend"), check_existing=False)
        desk = os.path.join(DESKTOP, "watchers_hand.blend")
        try:
            bpy.ops.wm.save_as_mainfile(filepath=desk, check_existing=False)
            print("SAVED_BLEND:", desk)
        except Exception as e:
            print("WARN could not save desktop blend:", e)
    path = os.path.join(OUT_DIR, filename)
    bpy.ops.export_scene.gltf(filepath=path, export_format='GLB', use_selection=False,
                              export_apply=True, export_yup=True)
    print("EXPORTED:", path)


export(1.0, "hand_right.glb", save_blend=True)
export(-1.0, "hand_left.glb")
print("HANDS_BUILD_DONE")
