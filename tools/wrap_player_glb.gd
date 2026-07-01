extends SceneTree
## Wrap exported blob GLBs into clean, editor-editable player-model scenes.
##
## For each assets/player_blobs/glb/player_blob_<name>.glb it writes
## actors/player_models/player_blob_<name>.tscn:
##   PlayerBlobModel (PlayerModelView)
##     - ModelRoot           (the .glb, instanced as a LINKED sub-scene — edits to the GLB flow in)
##     - FaceAnchor / LeftHandAnchor / RightHandAnchor / NameplateAnchor  (Marker3D, editable)
##
## The output is a NORMAL scene you can open and tune; re-run only when you add new colours
## (it skips/owerwrites by name). The model stays an INSTANCE of the GLB, so this is not
## "generated junk" — it's the same thing you'd build by hand, just faster.
##
## Run (headless):
##   godot --headless --path . --script res://tools/wrap_player_glb.gd
##   godot --headless --path . --script res://tools/wrap_player_glb.gd -- glb=res://assets/player_blobs/glb/player_blob_violet.glb
const GLB_DIR := "res://assets/player_blobs/glb/"
const OUT_DIR := "res://actors/player_models/"
const SCRIPT_PATH := "res://scripts/player/player_model_view.gd"

# [name, Vector3 position] — same defaults as player_blob_base.tscn. Forward = -Z.
const MARKERS := [
	["FaceAnchor", Vector3(0, 1.25, -0.35)],
	["LeftHandAnchor", Vector3(-0.7, 0.9, -0.1)],
	["RightHandAnchor", Vector3(0.7, 0.9, -0.1)],
	["NameplateAnchor", Vector3(0, 1.85, 0)],
]


func _initialize() -> void:
	var only := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("glb="):
			only = a.substr(4)
	var targets: Array[String] = []
	if only != "":
		targets.append(only)
	else:
		var d := DirAccess.open(GLB_DIR)
		if d == null:
			push_error("Cannot open %s" % GLB_DIR)
			quit(1); return
		for f in d.get_files():
			if f.get_extension().to_lower() == "glb":
				targets.append(GLB_DIR + f)
	if targets.is_empty():
		print("No GLBs found in %s — export your variants there first." % GLB_DIR)
		quit(0); return
	for path in targets:
		_wrap_one(path)
	quit(0)


func _wrap_one(glb_path: String) -> void:
	var glb := load(glb_path) as PackedScene
	if glb == null:
		push_error("Not a scene/GLB: %s" % glb_path)
		return
	var view_script := load(SCRIPT_PATH)

	var root := Node3D.new()
	root.name = "PlayerBlobModel"
	root.set_script(view_script)

	# The GLB as a LINKED instance (its scene_file_path is set by instantiate()).
	var model := glb.instantiate()
	model.name = "ModelRoot"
	root.add_child(model)
	model.owner = root            # instance-root only -> saved as a sub-scene reference, not inlined

	for m in MARKERS:
		var mk := Marker3D.new()
		mk.name = m[0]
		root.add_child(mk)
		mk.owner = root
		mk.position = m[1]

	var packed := PackedScene.new()
	var err := packed.pack(root)
	if err != OK:
		push_error("pack failed for %s (%d)" % [glb_path, err])
		return
	var base := glb_path.get_file().get_basename()    # player_blob_violet
	var out := OUT_DIR + base + ".tscn"
	err = ResourceSaver.save(packed, out)
	if err == OK:
		print("wrote ", out)
	else:
		push_error("save failed: %s (%d)" % [out, err])
