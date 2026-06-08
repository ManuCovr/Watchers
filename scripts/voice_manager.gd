extends Node
## VOICE MANAGER (autoload `VoiceManager`). The single entry point for voice settings
## and the shared mic capture bus. Per-player `Voice` components read these.
##
## Responsibilities:
##  - own the "Mic" bus + AudioEffectCapture (mic input)
##  - global voice volume, self-mute, per-peer mutes
##  - expose the local mic level (0..1) for the HUD voice meter
## It does NOT do networking or spatial playback — that lives in Voice (per player),
## so the voice layer stays separate from movement/gameplay and survives scene swaps.

signal settings_changed

const BUS_NAME := "Mic"

# DS = downsample factor on send (mix_rate / DS). Fixes the "deep voice" bug by making
# capture and playback rates agree, and cuts bandwidth ~in half.
const DOWNSAMPLE := 2
const GATE := 0.012            ## noise gate: below this we don't transmit

var master_volume := 1.0       ## 0..1, applied to everyone you hear
var self_muted := false        ## stop transmitting your mic
var deafened := false          ## mute everyone you hear
var lobby_mode := false        ## true in the lobby = wider, chattier range

var capture: AudioEffectCapture
var send_rate := 22050.0       ## the rate transmitted frames represent
var mic_level := 0.0           ## 0..1 smoothed local mic level (for the HUD meter)

var _muted_peers := {}         ## peer_id -> true


func _ready() -> void:
	if AudioGen.is_headless():
		return
	send_rate = AudioServer.get_mix_rate() / float(DOWNSAMPLE)
	_ensure_bus()


func _ensure_bus() -> void:
	var idx := AudioServer.get_bus_index(BUS_NAME)
	if idx == -1:
		AudioServer.add_bus()
		idx = AudioServer.bus_count - 1
		AudioServer.set_bus_name(idx, BUS_NAME)
		AudioServer.set_bus_mute(idx, true)        # don't monitor your own mic (no echo)
		capture = AudioEffectCapture.new()
		AudioServer.add_bus_effect(idx, capture)
	else:
		for e in AudioServer.get_bus_effect_count(idx):
			var fx := AudioServer.get_bus_effect(idx, e)
			if fx is AudioEffectCapture:
				capture = fx


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("voice_mute"):
		toggle_self_mute()
	elif event.is_action_pressed("voice_deafen"):
		deafened = not deafened
		settings_changed.emit()


# ---- settings API -----------------------------------------------------------
func set_master_volume(v: float) -> void:
	master_volume = clampf(v, 0.0, 1.5)
	settings_changed.emit()


func toggle_self_mute() -> void:
	self_muted = not self_muted
	settings_changed.emit()


func mute_peer(id: int, muted: bool) -> void:
	if muted:
		_muted_peers[id] = true
	else:
		_muted_peers.erase(id)
	settings_changed.emit()


func is_peer_muted(id: int) -> bool:
	return deafened or _muted_peers.has(id)


## Effective playback volume (dB) for a speaker owned by `peer_id`.
func playback_db(peer_id: int) -> float:
	if is_peer_muted(peer_id):
		return -80.0
	return linear_to_db(maxf(master_volume, 0.0001))
