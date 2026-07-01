extends SceneTree
## DECORATION STRIP for res://scenes/bunker.tscn — clears the bunker down to a clean shell so the
## user can decorate it themselves. NON-DESTRUCTIVE to structure: it LOADS the scene, removes only the
## DECORATION prop instances, and re-saves. Reversible via git.
##
##   Godot_console.exe --headless --path <proj> --script res://tools/strip_bunker_decor.gd
##
## RULE: a node is removed only if it's an INSTANCED sub-scene (scene_file_path set) whose source is
## NOT a keeper. Everything non-instanced — walls/floors/ceilings (StaticBody box meshes), OmniLights,
## Marker3D spawns, the Nav region, containers — is untouched. Kept instances: ceiling LAMPS, the
## ELEVATOR, TUNNEL pieces, DOORS/frames, structural beams, and all GAMEPLAY scenes (tasks, pickups,
## power-reset, keycard doors, physics items). Anything else instanced (trash, crates, barrels,
## shelves, furniture, posters, graffiti, machinery, generators, pcbs, signs, pipes, vents, …) is
## decoration and gets removed.
##
## The instantiated root is NEVER added to the SceneTree, so @tool scripts don't run/rebuild — the
## tree we re-pack is exactly what was authored, minus the stripped props.

const SRC := "res://scenes/bunker.tscn"
const DRY := false    ## true = report only (no free/save); set false to actually strip + save

## Substrings (lowercased) that mark an instance as KEEP. Match against scene_file_path.
const KEEP := [
	"lamp", "lighting",                 # ceiling lamps / light fixtures
	"elevator",                         # elevator car / doorway / sign
	"tunnel",                           # tunnel pieces + tunnel_fixes
	"door", "frame", "beam", "warehouse",  # structural shells
	"/tasks/", "item_pickup", "power_reset", "keycard", "/items/",  # gameplay scenes
]


func _initialize() -> void:
	var ps := load(SRC) as PackedScene
	if ps == null:
		print("strip_bunker_decor: FAILED to load ", SRC); quit(); return
	var root := ps.instantiate() as Node3D       # NOT added to tree → @tool scripts stay dormant

	var remove: Array = []
	var removed_counts := {}
	var kept_instances := {}
	for c in root.get_children():    # walk CHILDREN — the root itself is the bunker scene, never removed
		_walk(c, remove, kept_instances)

	for n in remove:
		var key := _asset_key((n as Node).scene_file_path)
		removed_counts[key] = int(removed_counts.get(key, 0)) + 1

	var serr := OK
	if not DRY:
		for n in remove:
			if is_instance_valid(n):
				n.free()
		var out := PackedScene.new()
		var err := out.pack(root)
		if err != OK:
			print("strip_bunker_decor: PACK FAILED err=", err); quit(); return
		serr = ResourceSaver.save(out, SRC)

	var total := 0
	for k in removed_counts:
		total += int(removed_counts[k])
	print("=== strip_bunker_decor [%s]: REMOVED %d decoration instances (save err=%d) ===" % [
		"DRY RUN" if DRY else "APPLIED", total, serr])
	var keys := removed_counts.keys()
	keys.sort()
	for k in keys:
		print("  - removed x%d : %s" % [removed_counts[k], k])
	print("--- KEPT instance types (lamps/structure/gameplay) ---")
	var kk := kept_instances.keys()
	kk.sort()
	for k in kk:
		print("  + kept x%d : %s" % [kept_instances[k], k])
	quit()


## Collect every instanced node that isn't a keeper. (We don't recurse INTO a node we're removing — its
## children go with it — but decoration props are leaf instances under Room/Tunnel nodes anyway.)
func _walk(n: Node, remove: Array, kept: Dictionary) -> void:
	var src: String = n.scene_file_path
	if src != "":
		if _is_keeper(src):
			var key := _asset_key(src)
			kept[key] = int(kept.get(key, 0)) + 1
			# keep recursing — a kept shell may parent more instances
		else:
			remove.append(n)
			return            # whole prop (and any children) removed together
	for c in n.get_children():
		_walk(c, remove, kept)


func _is_keeper(src: String) -> bool:
	var s := src.to_lower()
	for k in KEEP:
		if k in s:
			return true
	return false


func _asset_key(path: String) -> String:
	return path.get_file()
