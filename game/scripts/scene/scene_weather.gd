class_name SceneWeather
extends RefCounted

## Weather fronts over the scene: clear → clouds → wind → rain → clearing → clear, each phase a
## few minutes to a few hours (balance `scene.weather`), drawn from a seed. Each phase names
## targets (cloud cover, mean wind, gusts per minute, gust strength, rain); the values ease toward
## them so a front builds and clears rather than switching. Ground stays wet a while after rain.
## Dawn mist and the odd foggy day are the environment's (they depend on the clock). Pure.

var tuning: Dictionary = {}
var phase := "clear"
## Seconds left in this phase.
var left := 0.0
var cloud := 0.0
var rain := 0.0
var wind := 0.2
var gusts_per_min := 1.0
var gust_range := Vector2(0.3, 0.7)
## 0 dry .. 1 soaked: rises with rain, dries slowly after.
var wet := 0.0
## Set by a clip or the debug panel: the phase stays until released.
var held := false
var _rng := RandomNumberGenerator.new()


func _init(weather_tuning: Dictionary, seed: int) -> void:
	tuning = weather_tuning
	_rng.seed = seed
	enter(String(tuning["start"]))
	settle()


func order() -> Array:
	return tuning["order"]


func targets(of_phase: String = "") -> Dictionary:
	return tuning["phases"][of_phase if of_phase != "" else phase]


## Starts `next`, with a duration drawn for it.
func enter(next: String, hold: bool = false) -> void:
	phase = next
	held = hold
	var span: Array = tuning["minutes"][next]
	left = _rng.randf_range(float(span[0]), float(span[1])) * 60.0


## Jumps every value to the phase's targets (a clip that opens in the rain).
func settle() -> void:
	var target := targets()
	cloud = float(target["cloud"])
	rain = float(target["rain"])
	wind = float(target["wind"])
	gusts_per_min = float(target["gusts_per_min"])
	gust_range = Vector2(float(target["gust"][0]), float(target["gust"][1]))
	wet = rain


func step(dt: float) -> void:
	if not held:
		left -= dt
		if left <= 0.0:
			_advance()
	var target := targets()
	var ease := 1.0 - exp(-dt / (float(tuning["ease_min"]) * 60.0))
	# Rain comes on a little after the clouds and stops before they go.
	var rain_ease := 1.0 - exp(-dt / (float(tuning["rain_ease_min"]) * 60.0))
	cloud = lerpf(cloud, float(target["cloud"]), ease)
	# Rain waits for the cloud to close in (Skypatch issue 146): the
	# sky builds and darkens first, then it rains; clearing, the rain stops as the cover breaks.
	var needs: Array = tuning.get("rain_needs_cloud", [0.0, 0.0])
	var ready := 1.0 if float(needs[1]) <= 0.0 else smoothstep(float(needs[0]), float(needs[1]), cloud)
	rain = lerpf(rain, float(target["rain"]) * ready, rain_ease)
	wind = lerpf(wind, float(target["wind"]), ease)
	gusts_per_min = lerpf(gusts_per_min, float(target["gusts_per_min"]), ease)
	gust_range = gust_range.lerp(Vector2(float(target["gust"][0]), float(target["gust"][1])), ease)
	if rain > wet:
		wet = lerpf(wet, rain, 1.0 - exp(-dt / (float(tuning["wetting_min"]) * 60.0)))
	else:
		wet = maxf(rain, wet - dt / (float(tuning["drying_min"]) * 60.0))


func _advance() -> void:
	var phases := order()
	var i := phases.find(phase)
	var next := String(phases[(i + 1) % phases.size()])
	# Most clear spells do not end in a front: stay clear for another spell.
	if phase == "clear" and _rng.randf() > float(tuning["front_chance"]):
		next = "clear"
	enter(next)
