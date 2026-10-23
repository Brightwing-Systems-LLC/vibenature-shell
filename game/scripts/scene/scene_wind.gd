class_name SceneWind
extends RefCounted

## The wind field over the scene: a slowly wandering mean, gusts that travel across the scene
## from the upwind edge as soft bumps (so the reeds by the log bow first and the far crowns a
## moment later), and a little turbulence so no two plants agree exactly. Values are in wind
## units: 0 still air, ~0.2 a breeze, 1 a strong gust. Positive blows toward +x.
## Deterministic for a seed and a sequence of steps. Pure.

var tuning: Dictionary = {}
var width := 1152.0
## +1 blows left to right, -1 right to left.
var direction := 1.0
## What the weather asks for; the field follows it.
var target_mean := 0.2
var target_gusts_per_min := 1.0
var gust_range := Vector2(0.3, 0.7)
var mean := 0.2
var t := 0.0
## Active gusts: {x, strength, sigma, speed, age, life}.
var gusts: Array = []
var _rng := RandomNumberGenerator.new()
var _next_gust := 0.0


func _init(wind_tuning: Dictionary, scene_width: float, seed: int) -> void:
	tuning = wind_tuning
	width = scene_width
	_rng.seed = seed
	_next_gust = _rng.randf_range(0.5, 3.0)


## The weather's wish: mean wind, gusts per minute, and the range of gust strengths.
func set_weather(wind_mean: float, gusts_per_min: float, gust_strength: Vector2) -> void:
	target_mean = wind_mean
	target_gusts_per_min = gusts_per_min
	gust_range = gust_strength


## Jumps straight to the weather's wish (a clip that starts mid-storm).
func settle() -> void:
	mean = target_mean


func step(dt: float) -> void:
	t += dt
	var follow := 1.0 - exp(-dt / float(tuning["mean_follow_sec"]))
	mean = lerpf(mean, target_mean, follow)
	_next_gust -= dt
	if _next_gust <= 0.0:
		spawn_gust()
		var rate := maxf(0.05, target_gusts_per_min) / 60.0
		# Poisson arrivals, but never two right on top of each other.
		_next_gust = maxf(float(tuning["gust_min_gap_sec"]), -log(1.0 - _rng.randf()) / rate)
	for gust in gusts:
		gust["age"] += dt
		gust["x"] += direction * float(gust["speed"]) * dt
	gusts = gusts.filter(func(g: Dictionary) -> bool: return float(g["age"]) < float(g["life"]))


## A gust now, from just beyond the upwind edge (or `strength` if given; a width `sigma_px` and a speed
## `speed_px` if given: the weather beats' sweeping gust, issue 380).
func spawn_gust(strength: float = -1.0, sigma_px: float = -1.0, speed_px: float = -1.0) -> void:
	var sigma := _rng.randf_range(float(tuning["gust_width_px"][0]), float(tuning["gust_width_px"][1]))
	var speed := _rng.randf_range(float(tuning["gust_speed_px_per_sec"][0]), float(tuning["gust_speed_px_per_sec"][1]))
	if sigma_px > 0.0:
		sigma = sigma_px
	if speed_px > 0.0:
		speed = speed_px
	var start := -2.0 * sigma if direction > 0.0 else width + 2.0 * sigma
	var a := strength if strength >= 0.0 else _rng.randf_range(gust_range.x, gust_range.y)
	gusts.append({"x": start, "strength": a, "sigma": sigma, "speed": speed, "age": 0.0,
			"life": (width + 4.0 * sigma) / speed, "phase": _rng.randf() * TAU})


## Signed wind at scene column `x`.
func at(x: float) -> float:
	return direction * (mean * _wander(x) + gust_at(x) + turbulence(x))


## Only the gusts' part at `x` (unsigned): what ruffles water and flips leaves.
func gust_at(x: float) -> float:
	var sum := 0.0
	for g in gusts:
		var d := (x - float(g["x"])) / float(g["sigma"])
		if absf(d) > 3.0:
			continue
		var life := float(g["life"])
		var age := float(g["age"])
		# Builds and fades over its crossing, and pulses a little inside (gusts come in breaths).
		var envelope := sin(PI * clampf(age / life, 0.0, 1.0))
		var breath := 0.8 + 0.2 * sin(age * 2.3 + float(g["phase"]))
		sum += float(g["strength"]) * envelope * breath * exp(-d * d)
	return sum


## The slow wander of the mean across space and time: never quite uniform.
func _wander(x: float) -> float:
	return 1.0 + 0.22 * sin(t * 0.21 + x * 0.004) + 0.12 * sin(t * 0.53 - x * 0.011 + 1.7)


## Eddies: broadband, never periodic. Slow swells that neighbours share, and quick buffets that
## each reed feels on its own; all grow with the wind, more than in proportion (a breeze is
## smooth, a gale is ragged).
func turbulence(x: float) -> float:
	var speed := mean + 0.8 * gust_at(x)
	var amount := float(tuning["turbulence"]) * speed * (0.6 + speed)
	var slow := _noise(t * 0.7 - x * 0.006, 1.0) * 0.45
	var mid := _noise(t * 2.1 + x * 0.021, 2.0) * 0.4
	var fast := _noise(t * 4.3 - x * 0.08, 3.0) * 0.35 * clampf(speed * 1.5, 0.0, 1.0)
	return amount * (slow + mid + fast)


## Smooth value noise in one dimension, -1..1; `lane` gives independent streams.
static func _noise(u: float, lane: float) -> float:
	var i := floorf(u)
	var f := u - i
	f = f * f * (3.0 - 2.0 * f)
	return lerpf(_hash(i, lane), _hash(i + 1.0, lane), f)


static func _hash(i: float, lane: float) -> float:
	var h := sin(i * 127.1 + lane * 311.7) * 43758.5453
	return (h - floorf(h)) * 2.0 - 1.0


## The strongest gust anywhere right now (0 when calm): what the water and sound key off.
func gustiness() -> float:
	var best := 0.0
	var x := 0.0
	while x <= width:
		best = maxf(best, gust_at(x))
		x += 32.0
	return best
