class_name SceneEnvironment
extends RefCounted

## One environment state for the whole living scene (contract §7: the game owns sky, light,
## weather, wind and water motion). Everything that moves reads it: plants bend to `wind_at`,
## water ruffles under `gust_at` and rings in `rain`, the light follows the real time of day
## dimmed by `cloud`, mist rises at dawn on calm mornings, and some days are foggy. The behaviour
## engine to come reads the same values (a deer will not graze in a downpour; birds shelter).
##
## It never reads the clock itself: the scene hands it the minute of the day and the seconds
## that passed, so the snapshot path drives it exactly. Pure.

var tuning: Dictionary = {}
var wind: SceneWind
var weather: SceneWeather
var light: SceneLight
var t := 0.0
## Minute of the local day, fractions allowed.
var minute := 600.0
var look: Dictionary = {}
var sun_t := -1.0
var moon_t := -1.0
var mist := 0.0
var fog := 0.0
## Where the cloud pattern has drifted to (scene px): shadows and sky share it.
var cloud_offset := Vector2.ZERO
## The high layer's drift (slower: it is further away) and the seconds of cloud time the shapes evolve
## with (Skypatch issue 146).
var high_offset := Vector2.ZERO
var cloud_time := 0.0
## Clouds drift and change this many times faster than the clock (a clip that judges them at 10×).
var cloud_speed := 1.0
## Set to hold a value regardless of the clock (clips, debug): {"mist": 0.8, "fog": 0.0}.
var overrides: Dictionary = {}
## Weather runs this many times faster than the clock (a clip that shows a whole front).
var weather_speed := 1.0
## Which day it is (days since the epoch, local): the foggy-day roll is per day.
var day_number := 0
var _seed := 0
var _fog_days := {}


func _init(scene_tuning: Dictionary, phases: DayPhases, scene_width: float, seed: int) -> void:
	tuning = scene_tuning
	_seed = seed
	wind = SceneWind.new(tuning["wind"], scene_width, seed * 7 + 1)
	weather = SceneWeather.new(tuning["weather"], seed * 13 + 5)
	light = SceneLight.new(phases, tuning["light"])
	_feed_wind()
	wind.settle()
	_update_light()


## Advances `dt` seconds with the day at `minute_of_day`.
func step(dt: float, minute_of_day: float) -> void:
	t += dt
	minute = fposmod(minute_of_day, 1440.0)
	weather.step(dt * weather_speed)
	_feed_wind()
	wind.step(dt)
	var clouds: Dictionary = tuning["clouds"]
	var cdt := dt * cloud_speed
	var drift: float = float(clouds["drift_px_per_sec"]) * (0.35 + wind.mean)
	cloud_offset += Vector2(wind.direction * drift * cdt, drift * 0.08 * cdt)
	high_offset += Vector2(wind.direction * drift * float(clouds.get("high_drift", 0.3)) * cdt, 0.0)
	cloud_time += cdt
	_update_light()


## Starts a weather phase at once, held until `release_weather` (a clip or the debug panel).
func force_weather(phase: String, hold: bool = true) -> void:
	weather.enter(phase, hold)
	weather.settle()
	_feed_wind()
	wind.settle()
	_update_light()


## The wind takes the weather's values at once (after a clip changes them).
func force_wind_now() -> void:
	_feed_wind()
	wind.settle()


func release_weather() -> void:
	weather.held = false


func _feed_wind() -> void:
	wind.set_weather(weather.wind, weather.gusts_per_min, weather.gust_range)


func wind_at(x: float) -> float:
	return wind.at(x)


func gust_at(x: float) -> float:
	return wind.gust_at(x)


var cloud: float:
	get:
		return weather.cloud

## Where the cloud is heading: > 0 a front building, < 0 clearing (the phase's target less the cover now).
var cloud_front: float:
	get:
		return float(weather.targets()["cloud"]) - weather.cloud

var rain: float:
	get:
		return weather.rain

var wet: float:
	get:
		return weather.wet


## 0 at night .. 1 in full day: how much the sun can light (shadows, glints, caustics).
func daylight() -> float:
	if sun_t < 0.0:
		return 0.0
	return clampf(sin(PI * sun_t) * 2.2, 0.0, 1.0)


## The sun's strength through the clouds right now (0..1).
func sunshine() -> float:
	return daylight() * (1.0 - 0.85 * cloud)


func _update_light() -> void:
	look = light.look_at(minute)
	sun_t = light.sun_t(minute)
	moon_t = light.moon_t(minute)
	mist = float(overrides.get("mist", _dawn_mist()))
	fog = float(overrides.get("fog", _fog()))


## Mist over the water: from just before dawn to an hour or so into the morning, thicker on calm,
## damp mornings, burnt off by wind.
func _dawn_mist() -> float:
	var m: Dictionary = tuning["mist"]
	var dawn := float(light.dawn_minutes)
	var start := dawn + float(m["from_dawn_min"])
	var peak := dawn + float(m["peak_after_dawn_min"])
	var end := dawn + float(m["until_after_dawn_min"])
	var rise := clampf((minute - start) / maxf(1.0, peak - start), 0.0, 1.0)
	var fall := clampf((end - minute) / maxf(1.0, end - peak), 0.0, 1.0)
	var curve := smoothstep(0.0, 1.0, minf(rise, fall))
	var damp := float(m["base"]) + float(m["wet_boost"]) * weather.wet
	var calm := 1.0 - clampf(wind.mean / float(m["wind_burns_off"]), 0.0, 1.0)
	return clampf(curve * damp * (0.35 + 0.65 * calm), 0.0, 1.0)


## A foggy day now and then (rolled once per day from the seed): thick at first light, thinning
## by late morning; a little back in the evening.
func _fog() -> float:
	var f: Dictionary = tuning["fog"]
	var day := day_number
	if not _fog_days.has(day):
		var rng := RandomNumberGenerator.new()
		rng.seed = _seed * 31 + day
		_fog_days[day] = rng.randf() < float(f["chance_per_day"])
	if not _fog_days[day]:
		return 0.0
	var dawn := float(light.dawn_minutes)
	var morning := 1.0 - smoothstep(dawn + float(f["clear_from_dawn_min"]), dawn + float(f["clear_by_dawn_min"]), minute)
	if minute < dawn - 60.0:
		morning = 0.0
	var evening := smoothstep(float(light.night_minutes) - 60.0, float(light.night_minutes) + 30.0, minute) * 0.5
	return clampf(maxf(morning, evening) * float(f["strength"]), 0.0, 1.0)


## A plain snapshot for the debug panel, logs and the behaviour engine.
func summary() -> Dictionary:
	return {
		"minute": minute, "phase": weather.phase, "cloud": weather.cloud, "rain": weather.rain, "wet": weather.wet,
		"wind": wind.mean, "gusts": wind.gusts.size(), "mist": mist, "fog": fog, "light": look.get("name", ""),
		"daylight": daylight(),
	}
