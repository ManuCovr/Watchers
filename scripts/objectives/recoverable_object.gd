class_name RecoverableObject
extends PhysicsItem
## A physics object the team RECOVERS from the bunker and RESTOCKS into the elevator. Extends
## PhysicsItem, so grab / carry / throw / hold + the existing netcode all work unchanged — this only
## adds objective metadata and a "delivered" terminal state. The `category` (food / drink /
## electronics / …) is what RecoveryManager tallies against the round's restock quotas.
##
## Phase 1 of the recovery pass. The `fragile_*` fields are reserved for the Phase 3 break system and
## are INERT here (nothing reads them yet) — declared now so authored values survive into that phase.

@export_group("Recovery")
@export var object_id: StringName = &""            ## stable id; defaults to the node name
@export var display_name := "Goods"                ## shown in toasts
@export var category: StringName = &"food"         ## food · drink · electronics · …
@export var value := 1                             ## restock weight (informational in Phase 1)
@export var required := false                       ## hint only — the manager owns the live quota
## How awkward it is to sprint with: tiny · small · medium · heavy · awkward · fragile. Drives the
## carry wobble/looseness (physics_item) and the impact-drop bonus.
@export var weight_class: StringName = &"small"

@export_group("Fragile / break")
@export var fragile := false
@export var break_threshold := 6.0                 ## impact speed (m/s) that shatters it when NOT held
@export var broken := false
@export var broken_model := ""                     ## optional GLB swapped in on break (e.g. *_broken.glb)

var delivered := false

## weight_class -> {wobble, loose (lower = laggier hold), drop (extra drop chance)}.
const WEIGHT := {
	&"tiny":    {"wobble": 0.4, "loose": 0.95, "drop": 0.0},
	&"small":   {"wobble": 0.7, "loose": 0.85, "drop": 0.03},
	&"medium":  {"wobble": 1.0, "loose": 0.75, "drop": 0.08},
	&"heavy":   {"wobble": 1.5, "loose": 0.6,  "drop": 0.16},
	&"awkward": {"wobble": 1.9, "loose": 0.6,  "drop": 0.14},
	&"fragile": {"wobble": 1.2, "loose": 0.7,  "drop": 0.10},
}


func _weight() -> Dictionary:
	return WEIGHT.get(weight_class, WEIGHT[&"small"])

## Extra impact-drop chance from this item's heft (read by WPlayer._maybe_drop_from_impact).
func drop_bonus() -> float:
	return float(_weight()["drop"])


func _ready() -> void:
	super._ready()                                  # PhysicsItem: mass, layers, outline, MP sync
	add_to_group("recoverables")
	if object_id == &"":
		object_id = StringName(name)
	# CARGO, not a weapon: it can't swing, it NEVER knocks anyone back, and it floats CENTRED in front
	# of you (between your open hands — see DetachedHandsController) rather than gripped off to one side.
	can_swing = false
	swing_knockback = 0.0
	impact_knockback = 0.0
	max_knockback = 0.0
	hold_position_offset = Vector3(0.0, -0.18, 0.0)   # centred between the hands, not off to the right
	hold_rotation_degrees = Vector3.ZERO
	hold_distance = 0.85


## Fragile cargo SHATTERS on a hard enough impact while NOT held (thrown into a wall/player, or dropped
## hard after a panic). Authority decides; the break is broadcast so every peer sees the same wreck.
func _on_body_entered(body: Node) -> void:
	super._on_body_entered(body)
	if not fragile or broken or held_by != null or delivered:
		return
	if Net.is_active() and not Net.is_authority():
		return
	if linear_velocity.length() >= break_threshold:
		if Net.is_active():
			_net_break.rpc()
		else:
			_net_break()


@rpc("authority", "call_local", "reliable")
func _net_break() -> void:
	if broken:
		return
	broken = true
	value = 0                        # a smashed item is worthless (delivery bay rejects it)
	_swap_to_broken()
	_play(impact_sound, 2.0, 0.7)    # a duller, lower crunch


func _swap_to_broken() -> void:
	if broken_model == "":
		return
	if _model != null and is_instance_valid(_model):
		_model.queue_free()
	var ps := load(broken_model) as PackedScene
	if ps != null:
		var m := ps.instantiate() as Node3D
		m.name = "BrokenMesh"
		m.scale = Vector3.ONE * model_scale
		m.rotation_degrees = model_euler
		add_child(m)
		_model = m


## Terminal state: accepted by the elevator loading bay. Detach from any holder, stop simulating,
## and become non-interactable + invisible so it can't be re-grabbed out of the crate. Runs on EVERY
## peer (driven by RecoveryManager's RPC) so the object vanishes identically for the whole team.
func mark_delivered() -> void:
	if delivered:
		return
	delivered = true
	if held_by != null:
		drop()
	remove_from_group("recoverables")
	remove_from_group("phys_items")                 # PhysicsItem added this — drop it so aim/grab ignore us
	collision_layer = 0
	collision_mask = 0
	freeze = true
	set_deferred("freeze", true)
	visible = false
	set_process(false)
	set_physics_process(false)
