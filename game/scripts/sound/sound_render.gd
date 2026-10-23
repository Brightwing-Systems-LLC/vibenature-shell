class_name SoundRender
extends RefCounted

## The sound engine's off-screen output (issue 413):
## the same voices the engine would hand the game's buses, mixed here sample by sample into a buffer and
## written as a WAV, so sound is reviewed by listening to a file, never by running a visible game.
##
## The chain mirrors `SoundBuses`: each voice's playback (decoded from the package's OGG, at its pitch), its
## gain ramped across each block, calls and events through a two-pole low-pass at their cutoff and Godot's
## panner law, everything summed, the master level, then a peak limiter at `limiter_db`.

var rate := 44100
var frames := PackedVector2Array()
var _state := {}
var _master := 0.0
var _master_to := 0.0
var _ceiling := 1.0
var _release := 0.0
var _limit := 1.0
var _carry := 0.0


func open(sound_tuning: Dictionary) -> void:
	_ceiling = db_to_linear(float(sound_tuning["limiter_db"]))
	_release = 1.0 - exp(-1.0 / (0.1 * float(rate)))


func start(v: SceneSound.Voice) -> bool:
	var pb := v.stream.instantiate_playback()
	if pb == null:
		return false
	pb.start(0.0)
	v.out = pb
	_state[v] = {"g": 0.0, "z": [0.0, 0.0, 0.0, 0.0]}
	return true


func stop(v: SceneSound.Voice) -> void:
	_state.erase(v)
	v.out = null


func update(_voices: Array, master_amp: float) -> void:
	_master_to = master_amp


func position(v: SceneSound.Voice) -> float:
	var pb := v.out as AudioStreamPlayback
	return pb.get_playback_position() if pb != null else 0.0


func finished(v: SceneSound.Voice) -> bool:
	var pb := v.out as AudioStreamPlayback
	return pb == null or not pb.is_playing()


func close() -> void:
	_state.clear()


## Mixes `sec` seconds of every voice playing now onto the end of `frames`.
func mix(sec: float, voices: Array) -> void:
	_carry += sec * float(rate)
	var n := int(_carry)
	_carry -= float(n)
	if n <= 0:
		return
	var acc := PackedVector2Array()
	acc.resize(n)
	acc.fill(Vector2.ZERO)
	for vv in voices:
		var v: SceneSound.Voice = vv
		if not _state.has(v) or v.out == null:
			continue
		var st: Dictionary = _state[v]
		var buf: PackedVector2Array = (v.out as AudioStreamPlayback).mix_audio(v.pitch, n)
		if buf.size() < n:
			var had := buf.size()
			buf.resize(n)
			for i in range(had, n):
				buf[i] = Vector2.ZERO
		var g := float(st["g"])
		var g1 := v.amp()
		var dg := (g1 - g) / float(n)
		st["g"] = g1
		if v.bus == "beds":
			for i in n:
				acc[i] += buf[i] * g
				g += dg
			continue
		# Mono, panned: Godot's AudioEffectPanner law, through a low-pass at the voice's cutoff.
		var lvol := clampf(1.0 - v.pan, 0.0, 1.0)
		var rvol := clampf(1.0 + v.pan, 0.0, 1.0)
		var to_l := lvol + (1.0 - rvol)
		var to_r := rvol + (1.0 - lvol)
		var c := _lowpass(v.lowpass_hz)
		var z: Array = st["z"]
		var x1 := float(z[0])
		var x2 := float(z[1])
		var y1 := float(z[2])
		var y2 := float(z[3])
		if c.is_empty():
			for i in n:
				var s := buf[i].x * g
				acc[i] += Vector2(s * to_l, s * to_r)
				g += dg
		else:
			var b0: float = c[0]
			var b1: float = c[1]
			var b2: float = c[2]
			var a1: float = c[3]
			var a2: float = c[4]
			for i in n:
				var x := buf[i].x
				var y := b0 * x + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2
				x2 = x1
				x1 = x
				y2 = y1
				y1 = y
				var s := y * g
				acc[i] += Vector2(s * to_l, s * to_r)
				g += dg
		st["z"] = [x1, x2, y1, y2]
	var m := _master
	var dm := (_master_to - _master) / float(n)
	var lim := _limit
	for i in n:
		var s := acc[i] * m
		m += dm
		var peak := maxf(absf(s.x), absf(s.y))
		if peak * lim > _ceiling:
			lim = _ceiling / peak
		else:
			lim += (1.0 - lim) * _release
		acc[i] = s * lim
	_master = _master_to
	_limit = lim
	frames.append_array(acc)


## RBJ low-pass coefficients [b0, b1, b2, a1, a2] at `hz` (Q 0.707), or [] when it would pass everything.
func _lowpass(hz: float) -> Array:
	if hz >= 0.45 * float(rate) or hz >= 18000.0:
		return []
	var w := TAU * hz / float(rate)
	var alpha := sin(w) / (2.0 * 0.7071)
	var cw := cos(w)
	var a0 := 1.0 + alpha
	return [(1.0 - cw) * 0.5 / a0, (1.0 - cw) / a0, (1.0 - cw) * 0.5 / a0, -2.0 * cw / a0, (1.0 - alpha) / a0]


## The mix so far, in seconds.
func seconds() -> float:
	return float(frames.size()) / float(rate)


## Writes the mix as a 32-bit float stereo WAV at its real level (nothing normalised).
func save_wav(path: String) -> Error:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return FileAccess.get_open_error()
	var pcm := PackedFloat32Array()
	pcm.resize(frames.size() * 2)
	for i in frames.size():
		pcm[i * 2] = frames[i].x
		pcm[i * 2 + 1] = frames[i].y
	var data := pcm.to_byte_array()
	f.store_buffer("RIFF".to_ascii_buffer())
	f.store_32(36 + data.size())
	f.store_buffer("WAVEfmt ".to_ascii_buffer())
	f.store_32(16)
	f.store_16(3)
	f.store_16(2)
	f.store_32(rate)
	f.store_32(rate * 8)
	f.store_16(8)
	f.store_16(32)
	f.store_buffer("data".to_ascii_buffer())
	f.store_32(data.size())
	f.store_buffer(data)
	f.close()
	return OK
