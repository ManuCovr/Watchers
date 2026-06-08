class_name PowerSystem
extends Node
## The facility power state + OUTAGE event. Periodically the lights die: the bunker goes near-black,
## the watcher gets bolder, and the emergency red button (PowerResetButton, `button_etx_red_1`) in
## the electrical room starts pulsing. Players must scramble through the dark and slam it to restore
## power before the watcher reaches them. A failsafe restores it after outage_max_duration.
##
## All timing/intensity comes from GameConfig, so it's tuned entirely in the editor.

signal outage_started
signal power_restored

var config: GameConfig
var house: Node3D
var env: Environment
var watchers: Array = []

var powered := true
var _reset_btn: PowerResetButton
var _lights: Array = []           # [{ "l": Light3D, "e": base_energy }]
var _base_ambient := 0.3
var _next_outage := 1e9
var _outage_t := 0.0
var _started := false


func setup(cfg: GameConfig, house_node: Node3D, environment: Environment, watcher_arr: Array) -> void:
	config = cfg
	house = house_node
	env = environment
	watchers = watcher_arr
	if env != null:
		_base_ambient = env.ambient_light_energy
	_gather_lights()
	_reset_btn = _find_reset()
	if _reset_btn != null:
		_reset_btn.set_armed(false)
	if config != null and config.outage_enabled:
		_next_outage = config.outage_first_delay
	_started = true


func _gather_lights() -> void:
	for cont in ["Rooms", "Tunnels"]:
		var n := house.get_node_or_null(cont)
		if n != null:
			_collect_lights(n)


func _collect_lights(n: Node) -> void:
	for c in n.get_children():
		if c is OmniLight3D or c is SpotLight3D:
			_lights.append({ "l": c, "e": (c as Light3D).light_energy })
		_collect_lights(c)


func _find_reset() -> PowerResetButton:
	for n in get_tree().get_nodes_in_group("power_reset"):
		if n is PowerResetButton:
			return n
	return null


func _process(delta: float) -> void:
	if not _started or config == null or not config.outage_enabled:
		return
	if not Net.is_authority():
		return
	if powered:
		_next_outage -= delta
		if _next_outage <= 0.0:
			_trigger(true)
	else:
		_outage_t += delta
		# Look at the glowing red button + press E to restore.
		if _reset_btn != null:
			for n in get_tree().get_nodes_in_group("players"):
				var p := n as WPlayer
				if p != null and not p._downed and p.aimed == _reset_btn and p.consume_interact():
					_reset_btn.punch()
					_trigger(false)
					return
		if _outage_t >= config.outage_max_duration:
			_trigger(false)


## Server decides; broadcast so every peer's lights/ambient match (call_local handles solo too).
func _trigger(on: bool) -> void:
	if Net.is_active():
		_apply.rpc(on)
	else:
		_apply(on)


@rpc("authority", "call_local", "reliable")
func _apply(on: bool) -> void:
	powered = not on
	for d in _lights:
		var l := d["l"] as Light3D
		if l != null and is_instance_valid(l):
			l.light_energy = (d["e"] as float) * (0.0 if on else 1.0)
	if env != null:
		env.ambient_light_energy = config.outage_ambient_energy if on else _base_ambient
	var mult := config.outage_watcher_speed_mult if on else 1.0
	for w in watchers:
		if w != null and is_instance_valid(w):
			(w as Watcher).set_outage(mult)
	if _reset_btn != null:
		_reset_btn.set_armed(on)
	if Net.is_authority():
		if on:
			_outage_t = 0.0
		else:
			_next_outage = config.outage_interval + randf_range(
				-config.outage_interval_jitter, config.outage_interval_jitter)
	if on:
		outage_started.emit()
	else:
		power_restored.emit()
