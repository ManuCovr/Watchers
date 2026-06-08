class_name Voice
extends Node3D
## Per-player proximity voice. The LOCAL player captures the mic (via VoiceManager's
## "Mic" bus), downsamples, and RPCs frames; EVERY player has a spatial
## AudioStreamPlayer3D so you hear teammates by DISTANCE + DIRECTION.
##
## Modes: normal proximity, lobby (wider range), megaphone (loud + overdriven).
## Mute/volume come from VoiceManager. Headless-safe (capture/playback skipped).

const NORMAL_DISTANCE := 22.0
const LOBBY_DISTANCE := 34.0       ## the lobby is more relaxed/social
const MEGA_DISTANCE := 70.0
const NORMAL_UNIT := 5.0
const MEGA_UNIT := 12.0

var _is_local := false
var _peer_id := 1
var _spk: AudioStreamPlayer3D
var _playback: AudioStreamGeneratorPlayback
var _mic: AudioStreamPlayer


func setup(is_local: bool) -> void:
	_is_local = is_local


func _ready() -> void:
	if AudioGen.is_headless() or not Net.is_active():
		return
	var p := get_parent()
	_peer_id = p.get_multiplayer_authority() if p != null else 1

	# Spatial speaker at head height = proximity falloff + directionality.
	_spk = AudioStreamPlayer3D.new()
	var gen := AudioStreamGenerator.new()
	gen.mix_rate = VoiceManager.send_rate          # MATCHES the send rate (fixes deep voice)
	gen.buffer_length = 0.3
	_spk.stream = gen
	_spk.unit_size = NORMAL_UNIT
	_spk.max_distance = LOBBY_DISTANCE if VoiceManager.lobby_mode else NORMAL_DISTANCE
	_spk.position = Vector3(0, 1.6, 0)
	_spk.attenuation_filter_cutoff_hz = 5000.0     # distance muffling (cheap "occlusion" feel)
	add_child(_spk)
	_spk.play()
	_playback = _spk.get_stream_playback()

	# Capture (local only): mic -> Mic bus -> VoiceManager.capture.
	if _is_local:
		_mic = AudioStreamPlayer.new()
		_mic.stream = AudioStreamMicrophone.new()
		_mic.bus = VoiceManager.BUS_NAME
		add_child(_mic)
		_mic.play()


func _process(_delta: float) -> void:
	if _spk == null:
		return
	var mega := _megaphone()
	# Apply listener settings (volume / mute) + megaphone boost to what WE hear of them.
	_spk.volume_db = VoiceManager.playback_db(_peer_id) + (6.0 if mega else 0.0)
	if mega:
		_spk.max_distance = MEGA_DISTANCE
		_spk.unit_size = MEGA_UNIT
	else:
		_spk.max_distance = LOBBY_DISTANCE if VoiceManager.lobby_mode else NORMAL_DISTANCE
		_spk.unit_size = NORMAL_UNIT

	if not _is_local:
		return
	_capture_and_send(mega)


func _megaphone() -> bool:
	var p := get_parent() as WPlayer
	return p != null and p.megaphone


func _capture_and_send(mega: bool) -> void:
	var cap := VoiceManager.capture
	if cap == null:
		return
	var avail := cap.get_frames_available()
	if avail < VoiceManager.DOWNSAMPLE * 128:
		return
	var buf := cap.get_buffer(avail)               # full-rate stereo
	var ds := VoiceManager.DOWNSAMPLE
	var n := int(buf.size() / ds)
	var mono := PackedFloat32Array()
	mono.resize(n)
	var peak := 0.0
	for i in n:
		var s := 0.0
		for k in ds:
			s += buf[i * ds + k].x
		s /= float(ds)
		if mega:
			s = clampf(s * 3.0, -1.0, 1.0)         # overdrive = megaphone crunch
		mono[i] = s
		peak = maxf(peak, absf(s))
	VoiceManager.mic_level = lerpf(VoiceManager.mic_level, peak, 0.5)   # for the HUD meter

	if VoiceManager.self_muted or peak <= VoiceManager.GATE:
		return
	_recv_voice.rpc(mono)


@rpc("any_peer", "unreliable")
func _recv_voice(frames: PackedFloat32Array) -> void:
	if _playback == null:
		return
	var stereo := PackedVector2Array()
	stereo.resize(frames.size())
	for i in frames.size():
		stereo[i] = Vector2(frames[i], frames[i])
	if _playback.get_frames_available() >= stereo.size():
		_playback.push_buffer(stereo)
