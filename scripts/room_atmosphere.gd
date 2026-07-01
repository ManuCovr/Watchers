class_name RoomAtmosphere
extends Node3D
## Non-signage ROOM IDENTITY. Each functional room gets a signature LIGHT COLOUR + a looping diegetic
## HUM, so players learn the facility by feel — "the orange chugging room is the generator", "the cyan
## hissing one is coolant" — instead of reading a label. Data-driven and non-destructive: it derives
## each room's centre from the tasks ALREADY placed there (grouped by Task.zone_display_name), so it
## needs no bunker edits and no hand-placed zone volumes. Built on every peer (pure visual/audio).
##
## The colour lights are parented under house/Rooms so the PowerSystem's outage sweep dims them too
## (the room identity goes dark when the power dies, like everything else).

# zone_display_name -> [Color, energy, omni_range, hum .ogg path]
const PALETTE := {
	"Control Room":       [Color(1.00, 0.78, 0.30), 1.3, 13.0, "res://assets/audio/sfx/retro_computer_fans_mx_1_loop.ogg"],
	"Security":           [Color(0.40, 0.85, 0.45), 1.2, 12.0, "res://assets/audio/sfx/retro_computer_fans_mx_1_loop.ogg"],
	"Surveillance":       [Color(0.40, 0.85, 0.45), 1.2, 12.0, "res://assets/audio/sfx/retro_computer_fans_mx_1_loop.ogg"],
	"Observation":        [Color(0.42, 0.85, 0.52), 1.2, 12.0, "res://assets/audio/sfx/retro_computer_calculating_mx_1_loop.ogg"],
	"Power Plant":        [Color(0.70, 0.80, 1.00), 1.4, 13.0, "res://assets/audio/sfx/old_machine_mx_1_loop.ogg"],
	"Generator":          [Color(1.00, 0.50, 0.16), 1.6, 13.0, "res://assets/audio/sfx/machine_mx_1_loop.ogg"],
	"Coolant":            [Color(0.30, 0.70, 0.95), 1.3, 12.0, "res://assets/audio/sfx/valve_mx_1_loop.ogg"],
	"Pipe Room":          [Color(0.35, 0.70, 0.90), 1.3, 12.0, "res://assets/audio/ambience/ambience_high_pressure_mx_1.ogg"],
	"Comms":              [Color(0.70, 0.45, 0.95), 1.2, 12.0, "res://assets/audio/sfx/radio_static_mx_1_loop.ogg"],
	"Equipment Bay":      [Color(0.55, 0.65, 0.80), 1.2, 12.0, "res://assets/audio/sfx/old_machine_mx_1_loop.ogg"],
	"Armory":             [Color(0.50, 0.60, 0.85), 1.2, 12.0, "res://assets/audio/sfx/sfx_drone_mx_2.ogg"],
	"Deep Storage":       [Color(0.80, 0.60, 0.30), 1.0, 12.0, "res://assets/audio/sfx/sfx_drone_mx_3.ogg"],
	"Containment":        [Color(0.55, 0.30, 0.75), 1.4, 14.0, "res://assets/audio/sfx/sfx_drone_mx_1.ogg"],
	"Electrical":         [Color(0.70, 0.80, 1.00), 1.4, 12.0, "res://assets/audio/sfx/machine_mx_2_loop.ogg"],
	"Deep Tech":          [Color(0.65, 0.75, 1.00), 1.3, 12.0, "res://assets/audio/sfx/old_machine_mx_2_loop.ogg"],
	"Maintenance Corner": [Color(0.90, 0.80, 0.50), 1.1, 11.0, "res://assets/audio/sfx/old_machine_mx_2_loop.ogg"],
}
const FALLBACK := [Color(0.75, 0.78, 0.85), 1.0, 11.0, "res://assets/audio/sfx/sfx_drone_mx_4.ogg"]


## Build from the live task pool. `tasks` = the collected Task array; `house` = the bunker root (its
## Rooms node hosts the lights so the outage can dim them).
func build(tasks: Array, house: Node3D) -> void:
	var light_parent: Node = house.get_node_or_null("Rooms")
	if light_parent == null:
		light_parent = house

	# Group every task's world position by its room label, then take the centroid as the room centre.
	var groups := {}
	for t in tasks:
		var task := t as Task
		if task == null or task.zone_display_name == "":
			continue
		var key := task.zone_display_name
		if not groups.has(key):
			groups[key] = []
		groups[key].append(task.global_position)

	# Also derive zones from the recoverable spawn markers (each tagged with a "zone" meta). This keeps
	# room identity alive now that the minigame tasks are gone — the markers are the new zone anchors.
	for n in get_tree().get_nodes_in_group("recoverable_spawn"):
		var m := n as Node3D
		if m == null or not m.has_meta("zone"):
			continue
		var zkey := String(m.get_meta("zone"))
		if zkey == "":
			continue
		if not groups.has(zkey):
			groups[zkey] = []
		groups[zkey].append(m.global_position)

	for zone in groups.keys():
		var pts: Array = groups[zone]
		var centre := Vector3.ZERO
		for p in pts:
			centre += p
		centre /= float(pts.size())
		var spec: Array = PALETTE.get(zone, FALLBACK)
		_make_zone(zone, centre, spec, light_parent)


func _make_zone(zone: String, centre: Vector3, spec: Array, light_parent: Node) -> void:
	var col: Color = spec[0]
	var energy: float = spec[1]
	var rng: float = spec[2]
	var hum: String = spec[3]

	# Soft colour pool (dim + steep falloff so it tints the room without blowing out the PSX dark).
	var lamp := OmniLight3D.new()
	lamp.name = "ZoneLight_" + zone.replace(" ", "_")
	lamp.light_color = col
	lamp.light_energy = energy
	lamp.omni_range = rng
	lamp.omni_attenuation = 1.8
	lamp.shadow_enabled = false
	light_parent.add_child(lamp)
	lamp.global_position = centre + Vector3(0, 1.8, 0)

	# Looping diegetic hum at the room centre — skipped headless (the dummy driver leaks playbacks).
	if AudioGen.is_headless():
		return
	var stream := load(hum) as AudioStream
	if stream == null:
		return
	if stream is AudioStreamOggVorbis:
		(stream as AudioStreamOggVorbis).loop = true
	var player := AudioStreamPlayer3D.new()
	player.name = "ZoneHum_" + zone.replace(" ", "_")
	player.stream = stream
	player.volume_db = -22.0          # a presence, not a foreground sound
	player.unit_size = 6.0
	player.max_distance = 20.0
	player.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
	add_child(player)
	player.global_position = centre + Vector3(0, 1.2, 0)
	player.play()
