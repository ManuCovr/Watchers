class_name VoiceFaceDriver
extends Node
## Maps a player's VOICE amplitude onto their character's face, so you can tell who
## is talking with zero UI. Attach one per player; point it at the PlayerCharacter
## rig and give it callables for amplitude (0..1) and state.
##
## The networked amplitude (WPlayer.net_mouth) is already smoothed/replicated, so
## this just shapes it: gate out room noise, gain it up to a readable jaw flap,
## smooth attack/release, and push scream/downed expression onto the rig.

@export var gain := 4.5            ## speech peaks are low; multiply up to a real flap
@export var gate := 0.03           ## below this = silence (mouth shut)
@export var scream_at := 0.6       ## amplitude above this widens the eyes
@export var attack := 22.0         ## how fast the mouth opens
@export var release := 12.0        ## how fast it closes (slower = less chattery)

var _rig: PlayerCharacter
var _amp_fn: Callable              ## () -> float, raw amplitude 0..1
var _muted_fn: Callable            ## () -> bool, force-closed when true
var _downed_fn: Callable           ## () -> bool, dead eyes when true

var _open := 0.0
var _scared := 0.0


func configure(rig: PlayerCharacter, amp_fn: Callable, muted_fn: Callable, downed_fn: Callable) -> void:
	_rig = rig
	_amp_fn = amp_fn
	_muted_fn = muted_fn
	_downed_fn = downed_fn


func _process(delta: float) -> void:
	if _rig == null:
		return

	var downed: bool = _downed_fn.call() if _downed_fn.is_valid() else false
	_rig.set_blank(downed)

	var muted: bool = _muted_fn.call() if _muted_fn.is_valid() else false
	var raw: float = _amp_fn.call() if _amp_fn.is_valid() else 0.0

	# Gate + gain -> the jaw target.
	var target := 0.0
	if not muted and not downed and raw > gate:
		target = clampf((raw - gate) * gain, 0.0, 1.0)

	# Asymmetric smoothing: snappy open, lazy close (reads as real speech, not buzz).
	var rate := attack if target > _open else release
	_open = lerpf(_open, target, clampf(delta * rate, 0.0, 1.0))
	_rig.set_mouth_open(_open)

	# Scream -> eyes pop wide. Ease back down when quiet.
	var scream_target := 1.0 if raw > scream_at else 0.0
	_scared = lerpf(_scared, scream_target, clampf(delta * 6.0, 0.0, 1.0))
	_rig.set_scared(_scared)
