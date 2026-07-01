extends SceneTree
## PSX-BACKROOMS GRADING PASS for res://scenes/bunker.tscn — NON-DESTRUCTIVE.
##
## Unlike tools/build_bunker.gd (which regenerates from scratch and DROPS the hand-authored brick
## instances + the TunnelConnectionFixes arched frames), this tool LOADS the existing scene,
## mutates it in place, and re-saves. Every authored node + instanced sub-scene is preserved.
##
##   Godot_console.exe --headless --path <proj> --script res://tools/enhance_bunker.gd
##
## What it does (all idempotent — safe to re-run):
##  1. Environment: warm + darken the ambient/fog for "old bunker lamps barely holding the dark".
##  2. Lights: recolor the cool blue room lamps to warm tungsten; a few rooms go sickly emergency
##     green. Reddish (emergency) lights are left alone.
##  3. Materials: dirty + warm the bare concrete wall/floor/ceiling tints (cool grey -> grimy brown).
##  4. Tunnels: hang a warm lamp every ~10 m with DARK gaps between (the arched-corridor look), all
##     under the Tunnels node so the power outage kills them too.

const SRC := "res://scenes/bunker.tscn"
const LAMP := "res://assets/bunkers/lamp_0.glb"
const CEIL_LAMP := "res://assets/psx/Lighting/ceiling_lamp_1_on.glb"   # matches the rooms' main fixture

# --- grade palette -----------------------------------------------------------
const AMBER := Color(1.0, 0.73, 0.40)         # tungsten bulb
const SICK_GREEN := Color(0.70, 0.84, 0.46)   # failing emergency tube
const TUNNEL_LAMP := Color(1.0, 0.68, 0.34)   # warmer/dirtier than room lamps

const C_WALL := Color(0.33, 0.29, 0.25)       # grimy warm concrete
const C_FLOOR := Color(0.30, 0.285, 0.265)    # worn floor
const C_CEIL := Color(0.13, 0.125, 0.12)      # near-black ceiling (lamps pop off it)
const C_DARKSTEEL := Color(0.12, 0.115, 0.11) # pillars / gantries

var _lamp_ps: PackedScene
var _ceil_lamp_ps: PackedScene
var _stats := {"lights": 0, "mats": 0, "tunnel_lamps": 0, "tunnels": 0, "orphan_lamps": 0}


func _initialize() -> void:
	var ps := load(SRC) as PackedScene
	if ps == null:
		print("enhance_bunker: FAILED to load ", SRC); quit(); return
	var root := ps.instantiate() as Node3D       # detached: @tool task scripts won't rebuild
	_lamp_ps = load(LAMP) as PackedScene
	_ceil_lamp_ps = load(CEIL_LAMP) as PackedScene

	_grade_environment(root)
	var rooms := root.get_node_or_null("Rooms")
	if rooms != null:
		_grade_lights(rooms)
		_fix_orphan_lights(rooms, root)
		_grade_materials(rooms)
	var tunnels := root.get_node_or_null("Tunnels")
	if tunnels != null:
		_grade_materials(tunnels)
		_light_tunnels(tunnels, root)

	var out := PackedScene.new()
	var err := out.pack(root)
	if err != OK:
		print("enhance_bunker: PACK FAILED err=", err); quit(); return
	var serr := ResourceSaver.save(out, SRC)
	print("enhance_bunker: saved err=%d  lights=%d orphan_lamps=%d mats=%d tunnels=%d tunnel_lamps=%d" % [
		serr, _stats.lights, _stats.orphan_lamps, _stats.mats, _stats.tunnels, _stats.tunnel_lamps])
	quit()


# ---- 1. environment ---------------------------------------------------------
func _grade_environment(root: Node3D) -> void:
	var we := root.get_node_or_null("WorldEnvironment") as WorldEnvironment
	if we == null or we.environment == null:
		return
	var env := we.environment
	env.ambient_light_color = Color(0.26, 0.21, 0.16)   # warm brown bounce
	env.ambient_light_energy = 0.16                      # lower => darker corridors, more contrast
	env.fog_enabled = true
	env.fog_light_color = Color(0.06, 0.045, 0.03)       # warm haze, not blue
	env.fog_density = 0.022                               # a touch more distance falloff
	env.glow_enabled = true
	env.glow_intensity = 0.5
	env.glow_bloom = 0.14


# ---- 2. lights --------------------------------------------------------------
func _grade_lights(n: Node) -> void:
	for c in n.get_children():
		if c is OmniLight3D or c is SpotLight3D:
			_warm_light(c as Light3D)
		_grade_lights(c)


func _warm_light(l: Light3D) -> void:
	var col := l.light_color
	# Leave intentional emergency/red washes alone (red-dominant lights).
	if col.r > col.b + 0.05:
		return
	# A fifth of the rooms run a sickly green emergency tube instead of warm tungsten.
	var room := _room_name_of(l)
	var green := absi(room.hash()) % 5 == 0
	l.light_color = SICK_GREEN if green else AMBER       # color-only: idempotent across re-runs
	_stats.lights += 1


func _room_name_of(node: Node) -> String:
	var p := node
	while p != null:
		if String(p.name).begins_with("Room_"):
			return String(p.name)
		p = p.get_parent()
	return String(node.name)


## "No rogue lights on the ceiling": every fill-light the generator added (Light2/Light3/MezzLight/
## BaseLight) has NO visible fixture. Give each orphan a real ceiling lamp so light always has a
## source. All lights + lamps in a room are DIRECT children of the Room_ group, so a same-parent
## local-distance check is exact. Idempotent: the lamp we add itself counts as "a lamp nearby".
func _fix_orphan_lights(rooms: Node, root: Node3D) -> void:
	for room in rooms.get_children():
		var lights: Array = []
		var lamp_pos: Array = []
		for c in room.get_children():
			if c is OmniLight3D or c is SpotLight3D:
				lights.append(c)
			elif c is Node3D and String(c.name).to_lower().find("lamp") != -1:
				lamp_pos.append((c as Node3D).position)
		for l in lights:
			var lp := (l as Node3D).position
			var col := (l as Light3D).light_color
			# Leave only TRUE emergency-RED washes sourceless (red-dominant AND low green). Warm amber
			# (high green) and sickly green both get a real fixture.
			if col.r > col.b + 0.05 and col.g < 0.5:
				continue
			if String(l.name).to_lower().find("elev") != -1:
				continue                                  # elevator interior glow, not a ceiling
			var has_fixture := false
			for fp in lamp_pos:
				if Vector2(lp.x - fp.x, lp.z - fp.z).length() < 2.5:
					has_fixture = true
					break
			if has_fixture:
				continue
			if _ceil_lamp_ps == null:
				continue
			var lamp := _ceil_lamp_ps.instantiate() as Node3D
			lamp.name = "OrphanLamp_%s" % l.name
			lamp.position = Vector3(lp.x, lp.y + 0.45, lp.z)   # up to the ceiling above the light
			room.add_child(lamp)
			lamp.owner = root
			lamp_pos.append(lamp.position)                # so a second orphan nearby reuses it
			_stats.orphan_lamps += 1


# ---- 3. materials -----------------------------------------------------------
func _grade_materials(n: Node) -> void:
	for c in n.get_children():
		if c is MeshInstance3D:
			var mi := c as MeshInstance3D
			var m := mi.material_override
			if m is StandardMaterial3D:
				_dirty_material(c as MeshInstance3D, m as StandardMaterial3D)
		_grade_materials(c)


func _dirty_material(mi: MeshInstance3D, m: StandardMaterial3D) -> void:
	var who := String(mi.get_parent().name) if mi.get_parent() != null else String(mi.name)
	var tint := Color.BLACK
	var hit := true
	if who.begins_with("Wall"):
		tint = C_WALL
	elif who.begins_with("BaseWall"):
		tint = Color(0.30, 0.27, 0.235)
	elif who.begins_with("Floor") or who.begins_with("BaseFloor") or who.find("Ramp") != -1:
		tint = C_FLOOR
	elif who.begins_with("Mezz"):
		tint = Color(0.29, 0.275, 0.255)
	elif who.begins_with("Ceil"):
		tint = C_CEIL
	elif who.begins_with("Pillar") or who.begins_with("Gantry"):
		tint = C_DARKSTEEL
	else:
		hit = false                                      # props / elevator / plinth: leave as-is
	if not hit:
		return
	m.albedo_color = tint
	m.roughness = 1.0
	m.metallic = 0.0
	_stats.mats += 1


# ---- 4. tunnel lamps (the arched-corridor look) -----------------------------
func _light_tunnels(tunnels: Node, root: Node3D) -> void:
	for tun in tunnels.get_children():
		if not (tun is Node3D):
			continue
		if tun.get_node_or_null("TunLamps") != null:     # idempotent: already lit
			continue
		_stats.tunnels += 1
		var span := _tunnel_span(tun as Node3D)          # [length, axis_is_z]
		var length: float = span[0]
		var along_z: bool = span[1]
		if length <= 0.0:
			continue
		var holder := Node3D.new()
		holder.name = "TunLamps"
		tun.add_child(holder)
		holder.owner = root
		var count := maxi(int(round(length / 10.0)), 1)
		for i in count:
			var frac := (float(i) + 0.5) / float(count)
			var off := lerpf(-length * 0.5, length * 0.5, frac)
			var p := Vector3(0, 2.35, off) if along_z else Vector3(off, 2.35, 0)
			if _lamp_ps != null:
				var lamp := _lamp_ps.instantiate() as Node3D
				lamp.name = "TunLampModel%d" % i
				lamp.position = p
				holder.add_child(lamp)
				lamp.owner = root
			var ol := OmniLight3D.new()
			ol.name = "TunLamp%d" % i
			ol.position = p - Vector3(0, 0.25, 0)
			ol.light_color = TUNNEL_LAMP
			ol.light_energy = 1.5
			ol.omni_range = 6.5
			ol.omni_attenuation = 1.6
			holder.add_child(ol)
			ol.owner = root
			_stats.tunnel_lamps += 1


## Reads the tunnel's floor collider ("F") box to recover [length, axis_is_z] without guessing.
func _tunnel_span(tun: Node3D) -> Array:
	var f := tun.get_node_or_null("F")
	if f != null:
		for c in f.get_children():
			if c is CollisionShape3D and (c as CollisionShape3D).shape is BoxShape3D:
				var s := ((c as CollisionShape3D).shape as BoxShape3D).size
				if s.z >= s.x:
					return [maxf(s.z - 0.6, 0.0), true]
				return [maxf(s.x - 0.6, 0.0), false]
	# Fallback: infer from the tube children spread.
	var lo := 1e9
	var hi := -1e9
	var axis_z := true
	for c in tun.get_children():
		if String(c.name).begins_with("Tube") and c is Node3D:
			var pos := (c as Node3D).position
			axis_z = absf(pos.z) >= absf(pos.x)
			var v: float = pos.z if axis_z else pos.x
			lo = minf(lo, v); hi = maxf(hi, v)
	if hi < lo:
		return [0.0, true]
	return [hi - lo + 6.0, axis_z]
