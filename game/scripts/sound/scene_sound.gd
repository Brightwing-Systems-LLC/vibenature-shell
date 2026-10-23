class_name SceneSound
extends Node

## The shell's sound engine (issue 413; proposal
## 2026-10-21-sound-in-packages §6). It exists only while the Sound switch is on (off by default, SPEC §2.1):
## with it off there is no engine, no bus, no stream, and nothing is read or decoded.
##
## Three layers, from the scene package's `soundscape.json` (`SceneSoundscape`):
## - **Beds**: one time-of-day bed (dawn, day, dusk, night by the scene's own sunrise and sunset), crossfaded
##   over `crossfade_s`, its clips rotating one per loop; weather beds over it, each following a continuous
##   value of the scene (`rain`, `wind` with `SceneWind`'s gusts, `wet`, `cloud`) through its curve, and
##   ducking the time bed as they come up.
## - **Calls**: a species' song, while one of it is drawn on screen, at the package's rate and time-of-day
##   weight, from where it is; one voice per species, a few at once.
## - **Events**: typed scene events (`SceneBehaviour.sound_event`) mapped to clips, `kind:species` then
##   `kind`; dropped (never queued) inside `min_gap_s` or past their voices; gain jitter, pitch jitter,
##   gain by true size, pan by x, gain and low-pass by distance, duller under water.
##
## **The visible-cause gate**: an event sounds only if its actor is drawn on screen at that moment (the
## weather's thunder alone excepted), so sound can never become a channel of its own. The engine hears
## only typed scene events; it has no line to the hook or the event server, and the vocabulary has no
## agent kinds.
##
## Everything fades in (the whole engine over `fade_in_sec`, every bed and every one-shot), nothing starts
## suddenly; out over `fade_out_sec` when the scene hides. Levels: the package's per-kind loudness is set
## on the delivered files (§3); trims are capped at -24..+3 dB; the master is `master_db` and ends in a
## hard limiter at `limiter_db`. It never asks the OS to duck other audio and never opens an input.
##
## The output is either the game's audio buses (`SoundBuses`) or the off-screen render (`SoundRender`):
## the same engine decides what plays, when, where and how loud.

## Every play, drop and bed change: {t, what, kind, species, clip, gain_db, pan, lowpass_hz, x, depth_m,
## under, why}. No actor and nothing from outside the scene.
signal played(entry: Dictionary)

## One sound playing.
class Voice:
	extends RefCounted
	var stream: AudioStream
	var clip := ""
	## "beds", "calls" or "events".
	var bus := "events"
	## The bed slot, the event entry's key, or the calling species.
	var key := ""
	## Before the fade and the master, in dB against the file's own level.
	var gain_db := 0.0
	var fade := 0.0
	var fade_to := 1.0
	var fade_per_sec := 1.0
	var stop_at_zero := false
	var pitch := 1.0
	var pan := 0.0
	var lowpass_hz := 20000.0
	var length := 0.0
	var age := 0.0
	var done := false
	## The output's own handle (a player, a playback).
	var out: Variant = null

	## Equal-power fades, so a crossfade between two beds never dips in the middle.
	func amp() -> float:
		return db_to_linear(gain_db) * sin(fade * PI * 0.5)

	func fade_in(sec: float, to: float = 1.0) -> void:
		fade_to = to
		fade_per_sec = 1.0 / maxf(sec, 0.001)
		stop_at_zero = false

	func fade_out(sec: float) -> void:
		fade_to = 0.0
		fade_per_sec = 1.0 / maxf(sec, 0.001)
		stop_at_zero = true

	func step(dt: float) -> void:
		age += dt
		fade = move_toward(fade, fade_to, fade_per_sec * dt)


var scene: LivingScene
var tuning: Dictionary = {}
var scape: SceneSoundscape
## SoundBuses or SoundRender: open(), start(voice) -> bool, stop(voice), update(voices, master_amp),
## position(voice), finished(voice), close().
var output: Object
var t := 0.0
## The whole engine's fade, 0..1.
var level := 0.0
var closing := false
var voices: Array = []
## The newest plays and drops (the debug panel, tests); the render keeps all of them through `played`.
var log: Array = []
var rng := RandomNumberGenerator.new()
var _slot := ""
var _time_voice: Voice
var _weather_voices := {}
var _bed_index := {}
var _last_at := {}
var _last_clip := {}
var _callers: Array = []
var _callers_left := 0.0
var _gust := 0.0


## Starts the engine on `owner`'s scene package with `output`; it hears `owner.behaviour`'s typed events.
func setup(owner: LivingScene, sound_tuning: Dictionary, out: Object, seed: int) -> void:
	scene = owner
	tuning = sound_tuning
	output = out
	name = "Sound"
	rng.seed = seed
	scape = SceneSoundscape.load_for(ScenePackages.scene(scene.kit.id), tuning["voices"])
	output.open(tuning)
	scene.behaviour.sounded.connect(hear)


## Fades everything out over `fade_out_sec`, then lets go of every voice and the output (the switch
## turned off). `now` stops at once.
func close(now: bool = false) -> void:
	closing = true
	if now:
		_release()


func _release() -> void:
	for v in voices:
		output.stop(v)
	voices.clear()
	_time_voice = null
	_weather_voices.clear()
	output.close()
	if scene != null and scene.behaviour.sounded.is_connected(hear):
		scene.behaviour.sounded.disconnect(hear)
	closing = true
	level = 0.0


## Moves the engine on by `dt` (the scene's own step).
func step(dt: float) -> void:
	if output == null:
		return
	t += dt
	var target := 1.0 if scene.visible and not closing and scape.ok() else 0.0
	var sec := float(tuning["fade_in_sec"]) if target > level else float(tuning["fade_out_sec"])
	level = move_toward(level, target, dt / maxf(sec, 0.001))
	if closing and level <= 0.0:
		_release()
		output = null
		return
	if scape.ok():
		_beds(dt)
		_callers_left -= dt
		if _callers_left <= 0.0:
			_callers_left = float(tuning["callers_every_sec"])
			_callers = callers()
		_calls(dt)
	for v in voices:
		var voice: Voice = v
		voice.step(dt)
		if (voice.stop_at_zero and voice.fade <= 0.0) or output.finished(voice):
			voice.done = true
	output.update(voices, level * db_to_linear(float(tuning["master_db"])))
	for v in voices.duplicate():
		if (v as Voice).done:
			output.stop(v)
			voices.erase(v)


# --- Beds -----------------------------------------------------------------------------------------

func _beds(dt: float) -> void:
	var beds: Dictionary = scape.data.get("beds", {})
	var cross := float(beds.get("crossfade_s", 90.0))
	var light := scene.env.light
	var slot := scape.time_slot(scene.minute, float(light.dawn_minutes), float(light.night_minutes))
	var time_beds: Dictionary = beds.get("time", {})
	if slot != _slot:
		var first := _slot == ""
		if _time_voice != null:
			_time_voice.fade_out(cross)
		_slot = slot
		_time_voice = null
		if time_beds.has(slot):
			_time_voice = _start_bed("time:" + slot, time_beds[slot], 0.5 if first else cross)
			_note({"what": "bed", "kind": "time", "species": slot, "clip": _time_voice.clip if _time_voice != null else ""})
	var duck := 0.0
	for w in beds.get("weather", []):
		var id := String(w.get("id", w["follows"]))
		var value := _follow(w, dt)
		var g := SceneSoundscape.curve_at(w["curve"], value)
		var voice: Voice = _weather_voices.get(id)
		if g > float(tuning["silent_db"]):
			if voice == null or voice.stop_at_zero:
				voice = _start_bed("weather:" + id, w, float(tuning["bed_start_sec"]))
				_weather_voices[id] = voice
				if voice != null:
					_note({"what": "bed", "kind": "weather", "species": id, "clip": voice.clip, "gain_db": snappedf(g, 0.1)})
			if voice != null:
				voice.gain_db = g
				duck += float(w.get("ducks_time_db", 0.0)) * clampf(value, 0.0, 1.0)
				_rotate(voice, w)
		elif voice != null and not voice.stop_at_zero:
			voice.fade_out(float(tuning["bed_start_sec"]))
			_weather_voices.erase(id)
	if _time_voice != null and time_beds.has(_slot):
		_time_voice.gain_db = float(time_beds[_slot].get("gain_db", 0.0)) + duck
		_time_voice = _rotate(_time_voice, time_beds[_slot])


## A bed voice near the end of its clip hands over to the slot's next clip (one per loop).
func _rotate(voice: Voice, entry: Dictionary) -> Voice:
	var over := float(tuning["bed_rotate_sec"])
	if voice.stop_at_zero or voice.length <= over * 2.0 or voice.length - output.position(voice) > over:
		return voice
	var next := _start_bed(voice.key, entry, over)
	if next == null:
		return voice
	next.gain_db = voice.gain_db
	voice.fade_out(over)
	for id in _weather_voices:
		if _weather_voices[id] == voice:
			_weather_voices[id] = next
	return next


func _start_bed(key: String, entry: Dictionary, fade_sec: float) -> Voice:
	var clips: Array = entry.get("clips", [])
	if clips.is_empty():
		return null
	var i := int(_bed_index.get(key, rng.randi() % clips.size()))
	for tries in clips.size():
		var rel := String(clips[(i + tries) % clips.size()])
		var s := scape.stream(rel, "bed")
		if s == null:
			continue
		_bed_index[key] = (i + tries + 1) % clips.size()
		var v := Voice.new()
		v.stream = s
		v.clip = rel
		v.bus = "beds"
		v.key = key
		v.gain_db = float(entry.get("gain_db", 0.0))
		v.length = s.get_length()
		v.fade_in(fade_sec)
		if _bus_full("beds") or not output.start(v):
			return null
		voices.append(v)
		return v
	return null


## The scene's value a weather bed follows, 0..1: the wind's mean plus its gusts (with the bed's own
## attack and release, so a gust seen in the reeds is a gust heard), the rain, how wet it is, the cloud.
func _follow(w: Dictionary, dt: float) -> float:
	var env := scene.env
	match String(w["follows"]):
		"rain":
			return env.rain
		"wet":
			return env.wet
		"cloud":
			return env.cloud
		"wind":
			var raw := env.wind.gustiness()
			var g: Dictionary = w.get("gusts", {})
			var sec := float(g.get("attack_s", 0.8)) if raw > _gust else float(g.get("release_s", 3.0))
			_gust = lerpf(_gust, raw, 1.0 - exp(-dt / maxf(sec, 0.01)))
			return clampf(env.wind.mean + float(tuning["gust_share"]) * _gust, 0.0, 1.0)
	return 0.0


# --- Calls ----------------------------------------------------------------------------------------

## Who could call now: every creature and songbird drawn on screen, and whatever a code body says is
## (`PackageBody.callers`): [{species, actor, pos, depth_m, band}].
func callers() -> Array:
	var out: Array = []
	var beh := scene.behaviour
	for c in beh.creatures:
		var creature: SceneCreature = c
		if drawn(creature, creature.pos):
			out.append({"species": creature.sp.id, "actor": creature, "pos": creature.pos, "band": creature.band,
					"depth_m": beh.depth_of(creature.ppm())})
	for f in beh.flocks:
		var flock: SceneFlock = f
		var id := String(flock.member.get("id", flock.sp.id))
		for b in flock.birds:
			var at := flock.screen_of(b["p"])
			if drawn(b["look"], at):
				out.append({"species": id, "actor": b["look"], "pos": at, "band": "mid", "depth_m": float((b["p"] as Vector3).z)})
				break
	for m in beh.big_moments().values():
		if m is PackageBody:
			for c in (m as PackageBody).callers():
				if c is Dictionary and drawn(c.get("actor"), c.get("pos", Vector2.INF)):
					out.append(c)
	return out


func _calls(dt: float) -> void:
	for c in _callers:
		var sp := String(c["species"])
		var sets: Dictionary = scape.calls.get(sp, {})
		if not sets.has("song") or _voiced(sp):
			continue
		var song: Dictionary = sets["song"]
		var weight := float((song.get("time", {}) as Dictionary).get(_slot, 1.0))
		var per_sec := float(song.get("per_min", 0.5)) * weight / 60.0
		if rng.randf() < per_sec * dt and drawn(c.get("actor"), c.get("pos", Vector2.INF)):
			_play_call(sp, song, c, "call")


func _voiced(key: String) -> bool:
	for v in voices:
		if (v as Voice).key == key and not (v as Voice).stop_at_zero:
			return true
	return false


func _play_call(sp: String, call_set: Dictionary, at: Dictionary, what: String) -> void:
	if _bus_full("calls"):
		_note({"what": "drop", "kind": what, "species": sp, "why": "calls full"})
		return
	var v := _voice(call_set, "calls", sp, "short")
	if v == null:
		return
	var trim := float(call_set.get("gain_db", 0.0)) - rng.randf() * float(call_set.get("gain_jitter_db", 0.0))
	_place(v, at, clampf(trim, SceneSoundscape.GAIN_DB.x, SceneSoundscape.GAIN_DB.y))
	_start(v, what, sp, at)


# --- Events ---------------------------------------------------------------------------------------

## A typed scene event (`SceneBehaviour.sound_event`): through the gate, the gap and the voices, to a clip.
func hear(ev: Dictionary) -> void:
	if output == null or closing or not scape.ok():
		return
	var kind := String(ev.get("kind", ""))
	var sp := String(ev.get("species", ""))
	if not SceneSoundscape.VOCABULARY.has(kind) and not (scape.data.get("kinds", []) as Array).has(kind):
		_note({"what": "drop", "kind": kind, "species": sp, "why": "not a sound kind"})
		return
	var entry := scape.event_entry(kind, sp)
	if entry.is_empty():
		return
	if not SceneSoundscape.WEATHER_KINDS.has(kind) and not drawn(ev.get("actor"), ev.get("pos", Vector2.INF)):
		_note({"what": "drop", "kind": kind, "species": sp, "why": "not on screen"})
		return
	var key := scape.event_key(kind, sp)
	if t - float(_last_at.get(key, -1e9)) < float(entry.get("min_gap_s", 0.5)):
		_note({"what": "drop", "kind": kind, "species": sp, "why": "inside its gap"})
		return
	var playing := 0
	for v in voices:
		if (v as Voice).key == key:
			playing += 1
	if playing >= int(entry.get("voices", 1)):
		_note({"what": "drop", "kind": kind, "species": sp, "why": "its voices are busy"})
		return
	if entry.has("call"):
		var sets: Dictionary = scape.calls.get(sp, {})
		if sets.has(String(entry["call"])):
			_last_at[key] = t
			_play_call(sp, sets[String(entry["call"])], ev, kind)
		return
	if _bus_full("events"):
		_note({"what": "drop", "kind": kind, "species": sp, "why": "events full"})
		return
	var v := _voice(entry, "events", key, "thunder" if kind.begins_with("thunder") else "short")
	if v == null:
		return
	var trim := float(entry.get("gain_db", 0.0)) - rng.randf() * float(entry.get("gain_jitter_db", 0.0))
	if entry.has("by_size"):
		var sizes: Array = tuning["size_m"]
		var size := float(ev.get("size", 0.0))
		var u := 0.5 if size <= 0.0 else clampf(inverse_lerp(float(sizes[0]), float(sizes[1]), size), 0.0, 1.0)
		trim += linear_to_db(lerpf(float(entry["by_size"][0]), float(entry["by_size"][1]), u))
	_place(v, ev, clampf(trim, SceneSoundscape.GAIN_DB.x, SceneSoundscape.GAIN_DB.y))
	_last_at[key] = t
	_start(v, kind, sp, ev)


## A voice for one of `entry`'s clips, never the one it played last; null when none can play.
func _voice(entry: Dictionary, bus: String, key: String, kind: String) -> Voice:
	var clips: Array = entry.get("clips", [])
	if clips.is_empty():
		return null
	var last := String(_last_clip.get(key, ""))
	var order: Array = clips.duplicate()
	order.shuffle()
	if order.size() > 1 and String(order[0]) == last:
		order.push_back(order.pop_front())
	for c in order:
		var s := scape.stream(String(c), kind)
		if s == null:
			continue
		_last_clip[key] = String(c)
		var v := Voice.new()
		v.stream = s
		v.clip = String(c)
		v.bus = bus
		v.key = key
		v.length = s.get_length()
		var jitter := float(entry.get("pitch_jitter", 0.0))
		v.pitch = 1.0 + rng.randf_range(-jitter, jitter)
		v.fade_in(float(tuning["event_attack_sec"]))
		return v
	return null


## Where it is: gain by distance (`rolloff` × 6 dB per doubling past `ref_m`, floored at `min_db`), the
## distance's low-pass, pan by x (never past `pan_width`), and under water duller and quieter.
func _place(v: Voice, at: Dictionary, trim_db: float) -> void:
	var dist: Dictionary = scape.data.get("distance", {})
	var m := maxf(0.1, float(at.get("depth_m", 0.0)))
	var ref := float(dist.get("ref_m", 6.0))
	var fall := 0.0
	if m > ref:
		fall = maxf(float(dist.get("min_db", -18.0)), -float(dist.get("rolloff", 0.7)) * 6.0 * log(m / ref) / log(2.0))
	v.gain_db = trim_db + fall
	v.lowpass_hz = SceneSoundscape.curve_at(dist.get("lowpass_hz", [[0, 20000]]), m)
	var x := (at.get("pos", Vector2.ZERO) as Vector2).x
	v.pan = clampf((x / maxf(1.0, scene.size_pt.x)) * 2.0 - 1.0, -1.0, 1.0) * float(dist.get("pan_width", 0.6))
	if scene.mirrored:
		v.pan = -v.pan
	if bool(at.get("under", false)):
		var under: Dictionary = scape.data.get("underwater", {})
		v.gain_db += float(under.get("gain_db", -10.0))
		v.lowpass_hz = minf(v.lowpass_hz, float(under.get("lowpass_hz", 900.0)))


func _start(v: Voice, kind: String, sp: String, at: Dictionary) -> void:
	if not output.start(v):
		_note({"what": "drop", "kind": kind, "species": sp, "why": "no output voice"})
		return
	voices.append(v)
	var pos: Vector2 = at.get("pos", Vector2.ZERO)
	_note({"what": "call" if v.bus == "calls" else "event", "kind": kind, "species": sp, "clip": v.clip.get_file(),
			"gain_db": snappedf(v.gain_db, 0.1), "pitch": snappedf(v.pitch, 0.01), "pan": snappedf(v.pan, 0.01),
			"lowpass_hz": roundf(v.lowpass_hz), "x": roundf(pos.x), "depth_m": snappedf(float(at.get("depth_m", 0.0)), 0.1),
			"under": bool(at.get("under", false))})


func _bus_full(bus: String) -> bool:
	var n := 0
	for v in voices:
		if (v as Voice).bus == bus:
			n += 1
	return n >= int(tuning["voices"][bus])


## Whether `actor` is drawn on screen now at `pos` (scene points): in the tree, visible, not faded out,
## inside the scene, and the scene itself showing.
func drawn(actor: Variant, pos: Variant) -> bool:
	if actor == null or not is_instance_valid(actor) or not pos is Vector2 or not scene.visible:
		return false
	if actor is CanvasItem:
		var ci := actor as CanvasItem
		if not ci.is_inside_tree() or not ci.is_visible_in_tree() or ci.modulate.a < 0.05 or ci.self_modulate.a < 0.05:
			return false
	if "alpha" in actor and float(actor.get("alpha")) < 0.05:
		return false
	var margin := float(tuning["edge_margin_pt"])
	return Rect2(Vector2.ZERO, scene.size_pt).grow(margin).has_point(pos)


func _note(entry: Dictionary) -> void:
	entry["t"] = snappedf(t, 0.01)
	log.append(entry)
	if log.size() > 400:
		log.pop_front()
	played.emit(entry)
