@tool
class_name Interactable
extends StaticBody3D
## A "look at it + press/hold E" target. Lives on a dedicated INTERACT physics layer so the
## player's aim-ray finds it, and walls (layer 2) naturally OCCLUDE it (closest hit wins).
##
## Logic is supplied by the owner through Callables, so a task or item can spawn many of these
## inline without a subclass per piece. Two interaction styles are supported:
##   - PRESS  : the owning task calls player.consume_interact() when player.aimed == this piece
##   - HOLD   : the owning task checks player.interact_held && player.aimed == this piece
## (this node just makes the piece TARGETABLE + gives readable hover feedback; the task decides
##  what holding/pressing it does.)

const INTERACT_BIT := 1 << 7      ## physics layer 8 — player aim-ray mask is (WALL | INTERACT)

@export var prompt := "Use"       ## shown on the HUD while you're aiming at it
@export var enabled := true
var on_use := Callable()          ## optional: func(p: WPlayer) — fired on a PRESS while aimed
var on_hover := Callable()        ## optional: func(on: bool)   — owner-specific highlight

var _hover_light: OmniLight3D
var _hovered := false


func _ready() -> void:
	collision_layer = INTERACT_BIT
	collision_mask = 0
	input_ray_pickable = false


## Give the piece a clickable volume. Call once from the owner after positioning the node.
func add_box(size: Vector3, offset := Vector3.ZERO) -> void:
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	cs.shape = bs
	cs.position = offset
	add_child(cs)
	# A faint hover glow built once and parked off — reads in the dark without touching the
	# piece's shared GLB material (which other instances share). Skip in the editor preview.
	if not Engine.is_editor_hint():
		_hover_light = OmniLight3D.new()
		_hover_light.light_color = Color(0.85, 0.92, 1.0)
		_hover_light.light_energy = 0.0
		_hover_light.omni_range = maxf(size.length(), 0.4) * 2.2
		_hover_light.omni_attenuation = 2.0
		_hover_light.position = offset + Vector3(0, 0, 0)
		add_child(_hover_light)


func look_hover(on: bool) -> void:
	if on == _hovered:
		return
	_hovered = on
	if _hover_light != null:
		_hover_light.light_energy = 1.1 if on else 0.0
	if on_hover.is_valid():
		on_hover.call(on)


## Called by the player on the AUTHORITY when interact is pressed while aiming here.
func look_use(p: WPlayer) -> void:
	if enabled and on_use.is_valid():
		on_use.call(p)
