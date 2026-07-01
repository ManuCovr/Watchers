@tool
class_name PetCatTask
extends Task
## MEME / EASY — there is a cat in the bunker. Of course there is. Look at the loaf and HOLD E to
## pet it; it wiggles and loafs harder while you do, a purr-meter fills, and once it's sufficiently
## appreciated the objective ticks. Rare, quick, wholesome — the friendslop breather between scares.
## (Uses the real cat_loaf model; no new pet system, just a hold-to-fill on a cute prop.)

@export var pet_time := 2.0
@export var model := "res://assets/models/cat/cat_loaf.glb"
@export var model_scale := 1.0

var _cat: Node3D
var _spot: Interactable
var _rest := Vector3.ZERO
var _pet := 0.0
var _wiggle := 0.0


func _build() -> void:
	if is_default_title():
		task_title = "Pet the bunker cat"
	task_category = &"meme"
	meme_task = true
	difficulty = 1
	estimated_duration = 3.0
	beacon_color = Color(1.0, 0.6, 0.75)   # soft pink so it reads as the odd-one-out

	# A little crate for the loaf to sit on.
	var crate := make_model("res://assets/psx/Furniture/shelf_mp_3.glb",
		Vector3(0.7, 0.5, 0.5), Color(0.2, 0.18, 0.16), 0.6)
	crate.position = Vector3(0, 0, 0)
	add_child(crate)

	_cat = make_model(model, Vector3(0.4, 0.3, 0.5), Color(0.5, 0.45, 0.4), model_scale)
	_cat.position = Vector3(0, 0.55, 0)
	add_child(_cat)
	_rest = _cat.position

	_spot = make_interactable(Vector3(0.6, 0.5, 0.7), "Pet the cat", Vector3(0, 0.55, 0))
	_spot.grab_point = _cat
	add_child(_spot)


func _task_process(delta: float) -> void:
	var petting := false
	for nd in get_tree().get_nodes_in_group("players"):
		var p := nd as WPlayer
		if p == null or p._downed:
			continue
		if p.aimed == _spot and p.interact_held:
			petting = true
			break

	if petting:
		_pet = minf(pet_time, _pet + delta)
		_wiggle += delta * 9.0
	else:
		_pet = maxf(0.0, _pet - delta * 0.6)   # it gets bored, slowly
		_wiggle += delta * 1.5

	# Happy loaf wiggle while appreciated.
	if _cat != null:
		var amt := 0.5 + 0.5 * (_pet / maxf(0.01, pet_time))
		_cat.position = _rest + Vector3(0, sin(_wiggle) * 0.03 * amt, 0)
		_cat.rotation.z = sin(_wiggle * 0.7) * 0.06 * amt

	report_progress(_pet / maxf(0.01, pet_time))
	if _pet >= pet_time:
		play_sfx("res://assets/audio/sfx/button_4.ogg", -10.0, 1.4)
		mark_done()


func _on_done() -> void:
	if _cat != null:
		_cat.rotation.z = 0.0


func get_progress() -> float:
	return _pet / maxf(0.01, pet_time)
