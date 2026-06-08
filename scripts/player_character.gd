class_name PlayerCharacter
extends Node3D
## Minimal base / interface for a player BODY rig. Concrete rigs (e.g. gangbeast_character.gd) extend
## this and drive their own mesh. WPlayer and VoiceFaceDriver only ever talk to a rig through THESE
## methods, so any model can be dropped in as the body. All methods are safe no-op defaults; a rig
## overrides the ones it supports.

const SELF_LAYER_BIT := 1 << 19   ## first-person self-hide layer — the owner's cam culls it, the mirror keeps it

func _build() -> void: pass
func set_tint(_c: Color) -> void: pass
func set_mouth_open(_v: float) -> void: pass     ## 0..1 voice amplitude -> jaw
func set_blank(_b: bool) -> void: pass           ## downed
func set_scared(_v: float) -> void: pass         ## scream
func set_move(_v: float) -> void: pass           ## 0..1 walking
func set_smoking(_on: bool) -> void: pass        ## body cigarette on/off
func set_reach(_v: float) -> void: pass          ## 0..1 gang-beasts arm reach


## Put every visual under this rig on the self layer, so the owning player's camera hides their own
## body while other cameras (teammates, the lobby MIRROR) still render it.
func set_first_person_layer() -> void:
	_apply_layer(self, SELF_LAYER_BIT)


func _apply_layer(n: Node, bits: int) -> void:
	if n is VisualInstance3D:
		(n as VisualInstance3D).layers = bits
	for c in n.get_children():
		_apply_layer(c, bits)
