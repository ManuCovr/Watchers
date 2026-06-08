class_name AudioGen
extends Object
## Procedural audio. The greybox ships with no .wav/.ogg assets, so we synthesize
## tiny looping AudioStreamWAVs in code. Headless-safe: building a stream and
## calling play() under the dummy audio driver produces no errors.

const RATE := 22050


## True when running under the headless dummy audio driver. We skip play() there:
## it can't output sound, and force-quit (--quit-after) leaks active playbacks.
static func is_headless() -> bool:
	return DisplayServer.get_name() == "headless"


## Pack a mono float buffer (-1..1) into a 16-bit AudioStreamWAV. Loops by default;
## pass loop=false for one-shots (e.g. the emote sting).
static func _to_wav(s: PackedFloat32Array, loop := true) -> AudioStreamWAV:
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.stereo = false
	var b := PackedByteArray()
	b.resize(s.size() * 2)
	for i in s.size():
		b.encode_s16(i * 2, int(clampf(s[i], -1.0, 1.0) * 32767.0))
	w.data = b
	if loop:
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD
		w.loop_begin = 0
		w.loop_end = s.size()
	return w


## A low "lub-dub" heartbeat, one beat per loop (~0.85s).
static func heartbeat() -> AudioStreamWAV:
	var n := int(RATE * 0.85)
	var s := PackedFloat32Array()
	s.resize(n)
	for i in n:
		var t := float(i) / RATE
		var v := _thump(t, 0.0, 60.0) + _thump(t, 0.27, 52.0) * 0.7
		s[i] = v * 0.9
	return _to_wav(s)


static func _thump(t: float, start: float, freq: float) -> float:
	var lt := t - start
	if lt < 0.0:
		return 0.0
	return sin(lt * TAU * freq) * exp(-lt * 14.0)


## Dry rustling/scrape — low-passed noise with an 11Hz flutter (~0.5s loop).
static func skitter() -> AudioStreamWAV:
	var n := int(RATE * 0.5)
	var s := PackedFloat32Array()
	s.resize(n)
	var prev := 0.0
	for i in n:
		var t := float(i) / RATE
		var white := randf() * 2.0 - 1.0
		prev = lerpf(prev, white, 0.35)            # one-pole low-pass
		var flutter := 0.5 + 0.5 * sin(t * TAU * 11.0)
		s[i] = prev * flutter * 0.25
	return _to_wav(s)


## "Vine boom" — punchy bass sting for the emote. One-shot (~0.55s): a fast attack
## and a fundamental that drops from ~85Hz to ~48Hz, with a little 2nd harmonic.
static func vine_boom() -> AudioStreamWAV:
	var n := int(RATE * 0.55)
	var s := PackedFloat32Array()
	s.resize(n)
	var phase := 0.0
	for i in n:
		var t := float(i) / RATE
		var prog := t / 0.55
		var freq := lerpf(85.0, 48.0, prog * prog)     # pitch drop (eased)
		phase += TAU * freq / RATE
		var env := minf(1.0, t / 0.012) * exp(-t * 6.5) # snap attack, long-ish decay
		var body := sin(phase) + 0.3 * sin(phase * 2.0)
		s[i] = clampf(body * env * 0.85, -1.0, 1.0)
	return _to_wav(s, false)


## Short percussive THUD for object impacts (~0.18s): a low body + a noise transient.
static func thud() -> AudioStreamWAV:
	var n := int(RATE * 0.18)
	var s := PackedFloat32Array()
	s.resize(n)
	var phase := 0.0
	for i in n:
		var t := float(i) / RATE
		phase += TAU * lerpf(95.0, 55.0, clampf(t / 0.18, 0.0, 1.0)) / RATE
		var body := sin(phase) * exp(-t * 22.0)
		var click := (randf() * 2.0 - 1.0) * exp(-t * 90.0) * 0.5   # contact transient
		s[i] = clampf((body + click) * 0.8, -1.0, 1.0)
	return _to_wav(s, false)


## Soft footstep (~0.09s): a low-passed noise tap.
static func footstep() -> AudioStreamWAV:
	var n := int(RATE * 0.09)
	var s := PackedFloat32Array()
	s.resize(n)
	var prev := 0.0
	for i in n:
		var t := float(i) / RATE
		var white := randf() * 2.0 - 1.0
		prev = lerpf(prev, white, 0.25)
		s[i] = prev * exp(-t * 38.0) * 0.5
	return _to_wav(s, false)


## Obnoxious airhorn — a harsh dual-tone buzz (~0.7s). Pure lobby chaos.
static func airhorn() -> AudioStreamWAV:
	var n := int(RATE * 0.7)
	var s := PackedFloat32Array()
	s.resize(n)
	for i in n:
		var t := float(i) / RATE
		var env := minf(1.0, t / 0.02) * minf(1.0, (0.7 - t) / 0.1)
		# two close detuned saws = that nasty horn beating
		var a := fmod(t * 220.0, 1.0) * 2.0 - 1.0
		var b := fmod(t * 277.0, 1.0) * 2.0 - 1.0
		s[i] = clampf((a + b) * 0.5 * env, -1.0, 1.0)
	return _to_wav(s, false)
