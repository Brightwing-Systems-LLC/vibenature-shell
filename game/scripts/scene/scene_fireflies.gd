class_name SceneFireflies
extends Node2D

## Fireflies over the bank from dusk into the night, on dry evenings: slow wandering lights that
## glow for a second and go dark for a few. Their own light, so the night's tint never dims them.

var tuning: Dictionary = {}
var flies: Array = []
var _amount := 0.0
var _rng := RandomNumberGenerator.new()


func setup(fly_tuning: Dictionary, seed: int) -> void:
	tuning = fly_tuning
	name = "Fireflies"
	_rng.seed = seed
	var area: Array = tuning["area"]
	for i in int(tuning["count"]):
		flies.append({"home": Vector2(_rng.randf_range(float(area[0]), float(area[2])), _rng.randf_range(float(area[1]), float(area[3]))),
				"phase": _rng.randf() * 100.0, "rate": _rng.randf_range(0.7, 1.3), "share": _rng.randf(),
				"blink": _rng.randf_range(2.5, 5.5), "offset": _rng.randf() * 10.0, "at": Vector2.ZERO, "glow": 0.0})


func step(t: float, env: SceneEnvironment) -> void:
	var dusk := 1.0 - env.daylight()
	var names: Array = tuning["looks"]
	var wanted := 1.0 if names.has(String(env.look.get("name", ""))) else 0.0
	_amount = minf(dusk, wanted) * (1.0 - env.rain) * (1.0 - clampf(env.wind.mean / 0.6, 0.0, 1.0) * 0.6)
	var wander := float(tuning["wander_px"])
	for f in flies:
		var p := float(f["phase"]) + t * 0.23 * float(f["rate"])
		var home: Vector2 = f["home"]
		f["at"] = home + Vector2(sin(p) * wander + sin(p * 2.3 + 1.0) * wander * 0.4, sin(p * 0.7 + 2.0) * wander * 0.35 + cos(p * 1.9) * 2.0)
		var cycle := fposmod(t + float(f["offset"]), float(f["blink"])) / float(f["blink"])
		f["glow"] = clampf(sin(PI * clampf(cycle / 0.3, 0.0, 1.0)), 0.0, 1.0) if cycle < 0.3 else 0.0
	queue_redraw()


func _draw() -> void:
	if _amount <= 0.02:
		return
	var color := Color(String(tuning["color"]))
	for f in flies:
		if float(f["share"]) > _amount or float(f["glow"]) <= 0.01:
			continue
		var at: Vector2 = (f["at"] as Vector2).round()
		var g := float(f["glow"])
		draw_rect(Rect2(at - Vector2(1, 0), Vector2(3, 1)), Color(color, 0.35 * g))
		draw_rect(Rect2(at - Vector2(0, 1), Vector2(1, 3)), Color(color, 0.35 * g))
		draw_rect(Rect2(at, Vector2.ONE), Color(color.lightened(0.5), g))
