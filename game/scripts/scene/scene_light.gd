class_name SceneLight
extends RefCounted

## The scene's light through the day (SPEC §3.4: a tint over neutral-lit art, shifting smoothly):
## keyframes placed relative to the player's day phases (`[phase, minutes after its start,
## look]`), each look a tint for every layer, a glow behind the trees that dissolves upward into
## the desktop, and how many stars show. Between keyframes everything blends. The sun crosses
## from dawn to night and sets behind the trees; the moon crosses the night. Pure.

var keyframes: Array = []
var looks: Dictionary = {}
var dawn_minutes := 300
var night_minutes := 1200
## The player's day phases.
var day_phases: DayPhases


## `phases` are the player's (Settings.day_phases()); `light` is balance `scene.light`.
func _init(phases: DayPhases, light: Dictionary) -> void:
	looks = light["looks"]
	day_phases = phases
	dawn_minutes = phases.start_of("dawn")
	night_minutes = phases.start_of("night")
	for entry in light["keyframes"]:
		var at := posmod(phases.start_of(String(entry[0])) + int(entry[1]), 1440)
		keyframes.append([at, String(entry[2])])
	keyframes.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])


## The look at `minute` of the day (0..1440, fractions allowed): tint, glow_low, glow_high
## (Colors), glow and stars (0..1), and `name`, the nearest keyframe's look.
func look_at(minute: float) -> Dictionary:
	minute = fposmod(minute, 1440.0)
	var before: Array = keyframes[-1]
	var after: Array = keyframes[0]
	for i in keyframes.size():
		if float(keyframes[i][0]) > minute:
			after = keyframes[i]
			before = keyframes[i - 1] if i > 0 else keyframes[-1]
			break
		before = keyframes[i]
		after = keyframes[(i + 1) % keyframes.size()]
	var span := fposmod(float(after[0]) - float(before[0]), 1440.0)
	var t := 0.0 if span <= 0.0 else fposmod(minute - float(before[0]), 1440.0) / span
	var a: Dictionary = looks[before[1]]
	var b: Dictionary = looks[after[1]]
	return {
		"name": String(before[1]) if t < 0.5 else String(after[1]),
		"tint": Color(String(a["tint"])).lerp(Color(String(b["tint"])), t),
		"glow_low": Color(String(a["glow_low"])).lerp(Color(String(b["glow_low"])), t),
		"glow_high": Color(String(a["glow_high"])).lerp(Color(String(b["glow_high"])), t),
		"glow": lerpf(float(a["glow"]), float(b["glow"]), t),
		"stars": lerpf(float(a["stars"]), float(b["stars"]), t),
	}


## How far the sun is across its day (0 rising at dawn, 1 set at night), or -1 when it is down.
func sun_t(minute: float) -> float:
	var span := float(posmod(night_minutes - dawn_minutes, 1440))
	var into := fposmod(minute - dawn_minutes, 1440.0)
	return into / span if into <= span else -1.0


## How far the moon is across the night (0..1), or -1 by day.
func moon_t(minute: float) -> float:
	var span := float(posmod(dawn_minutes - night_minutes, 1440))
	var into := fposmod(minute - night_minutes, 1440.0)
	return into / span if into <= span else -1.0
