# Renders the built hand (hand_source.blend) to a few preview PNGs so the shape can be EYEBALLED.
# Run: blender --background --python tools/blender/render_hand.py

import bpy, os, math

PROJECT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
OUT_DIR = os.path.join(PROJECT, "assets", "models", "hands")

bpy.ops.wm.open_mainfile(filepath=os.path.join(OUT_DIR, "hand_source.blend"))

scene = bpy.context.scene
scene.render.engine = 'BLENDER_WORKBENCH'
scene.render.resolution_x = 600
scene.render.resolution_y = 600
scene.display.shading.light = 'STUDIO'
scene.display.shading.show_cavity = True

# aim target at the hand centre
tgt = bpy.data.objects.new("tgt", None)
bpy.context.collection.objects.link(tgt)
tgt.location = (0.0, 0.0, 0.25)


def shot(name, loc):
    cam_data = bpy.data.cameras.new("cam")
    cam = bpy.data.objects.new("cam", cam_data)
    bpy.context.collection.objects.link(cam)
    cam.location = loc
    c = cam.constraints.new('TRACK_TO')
    c.target = tgt
    c.track_axis = 'TRACK_NEGATIVE_Z'
    c.up_axis = 'UP_Y'
    scene.camera = cam
    scene.render.filepath = os.path.join(OUT_DIR, "_preview_" + name + ".png")
    bpy.ops.render.render(write_still=True)
    bpy.data.objects.remove(cam)
    print("RENDERED:", name)


shot("front", (0.0, -2.8, 0.25))      # FRONT = the in-game first-person view (back of hand, fingers up)
shot("threeq", (1.8, -2.0, 0.9))      # 3/4
shot("side", (2.8, 0.0, 0.3))         # side (depth)
print("RENDER_DONE")
