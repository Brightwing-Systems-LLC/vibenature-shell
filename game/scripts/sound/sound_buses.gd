class_name SoundBuses
extends Node

## The sound engine's output in the game (proposal 2026-10-21-sound-in-packages §6): Godot audio buses made
## when the Sound switch turns on and removed when it turns off, so with sound off there is no bus, no
## player and no stream.
##
##   Master <- "VN Sound" (the master level, then a hard limiter at `limiter_db`)
##              <- "VN Beds"   (stereo beds, players straight on it)
##              <- "VN Calls"  <- "VN Calls 1".."VN Calls n"   (one per voice: a panner and a low-pass)
##              <- "VN Events" <- "VN Events 1".."VN Events n"
##
## A voice bus is a voice: the engine's cap per bus (`sound.voices`) is how many there are. The shell never
## creates an input bus and never asks the OS to duck other audio.

const MASTER := "VN Sound"
const KINDS := {"beds": "VN Beds", "calls": "VN Calls", "events": "VN Events"}

var _free := {"calls": [], "events": []}
var _opened := false


func open(sound_tuning: Dictionary) -> void:
	name = "SoundBuses"
	_add_bus(MASTER, "Master")
	var limiter := AudioEffectHardLimiter.new()
	limiter.ceiling_db = float(sound_tuning["limiter_db"])
	AudioServer.add_bus_effect(AudioServer.get_bus_index(MASTER), limiter)
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index(MASTER), -80.0)
	for kind in KINDS:
		_add_bus(KINDS[kind], MASTER)
	for kind in ["calls", "events"]:
		for i in int(sound_tuning["voices"][kind]):
			var bus := "%s %d" % [KINDS[kind], i + 1]
			_add_bus(bus, KINDS[kind])
			var idx := AudioServer.get_bus_index(bus)
			AudioServer.add_bus_effect(idx, AudioEffectPanner.new())
			AudioServer.add_bus_effect(idx, AudioEffectLowPassFilter.new())
			_free[kind].append(bus)
	_opened = true


## Every bus this made (tests: none while sound is off).
static func buses() -> PackedStringArray:
	var out := PackedStringArray()
	for i in AudioServer.bus_count:
		if AudioServer.get_bus_name(i).begins_with("VN "):
			out.append(AudioServer.get_bus_name(i))
	return out


func _add_bus(bus: String, send: String) -> void:
	AudioServer.add_bus()
	var idx := AudioServer.bus_count - 1
	AudioServer.set_bus_name(idx, bus)
	AudioServer.set_bus_send(idx, send)


func start(v: SceneSound.Voice) -> bool:
	var bus := String(KINDS["beds"])
	if v.bus != "beds":
		var free: Array = _free[v.bus]
		if free.is_empty():
			return false
		bus = free.pop_front()
		var idx := AudioServer.get_bus_index(bus)
		(AudioServer.get_bus_effect(idx, 0) as AudioEffectPanner).pan = v.pan
		(AudioServer.get_bus_effect(idx, 1) as AudioEffectLowPassFilter).cutoff_hz = v.lowpass_hz
	var p := AudioStreamPlayer.new()
	p.stream = v.stream
	p.bus = bus
	p.pitch_scale = v.pitch
	p.volume_db = linear_to_db(maxf(v.amp(), 0.00001))
	add_child(p)
	p.play()
	v.out = p
	return true


func stop(v: SceneSound.Voice) -> void:
	var p := v.out as AudioStreamPlayer
	if p == null or not is_instance_valid(p):
		return
	if v.bus != "beds":
		_free[v.bus].append(p.bus)
	p.stop()
	p.queue_free()
	v.out = null


func update(voices: Array, master_amp: float) -> void:
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index(MASTER), linear_to_db(maxf(master_amp, 0.00001)))
	for v in voices:
		var p := (v as SceneSound.Voice).out as AudioStreamPlayer
		if p != null and is_instance_valid(p):
			p.volume_db = linear_to_db(maxf((v as SceneSound.Voice).amp(), 0.00001))


func position(v: SceneSound.Voice) -> float:
	var p := v.out as AudioStreamPlayer
	return p.get_playback_position() if p != null and is_instance_valid(p) else 0.0


func finished(v: SceneSound.Voice) -> bool:
	var p := v.out as AudioStreamPlayer
	return p == null or not is_instance_valid(p) or not p.playing


## Leaving with the scene (the game quits, the scene is rebuilt) takes the buses with it.
func _exit_tree() -> void:
	close()


## Every player and every bus this made, gone.
func close() -> void:
	for c in get_children():
		(c as AudioStreamPlayer).stop()
		c.queue_free()
	if _opened:
		for i in range(AudioServer.bus_count - 1, -1, -1):
			if AudioServer.get_bus_name(i).begins_with("VN "):
				AudioServer.remove_bus(i)
	_opened = false
	_free = {"calls": [], "events": []}
