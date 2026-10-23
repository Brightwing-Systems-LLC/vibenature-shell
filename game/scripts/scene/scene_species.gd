class_name SceneSpecies
extends RefCounted

## One animal's habits for the behaviour engine (Skypatch issue 104),
## read from the scene package's `behaviour/<id>.json` (contract §8): when it is about (diurnal, crepuscular,
## nocturnal, as a curve over the player's day), what weather brings it out or keeps it in, where
## it goes, how it moves, what it fears and from how far, and the activities its needs drive. The
## numbers come from the animal, so tuning a deer is editing deer.json. Pure.

## "" is the scene package's `behaviour/` (contract §8); a res:// folder of the same shape for tests.
const DIR := ""
## The species files' folder inside a scene package.
const PACKAGE_DIR := "behaviour"

var id := ""
var data: Dictionary = {}


static func load_all(dir: String = DIR) -> Dictionary:
	if dir == "":
		return load_package(ScenePackages.scene())
	var out := {}
	for file in DirAccess.get_files_at(dir):
		if not file.ends_with(".json"):
			continue
		_add(out, JSON.parse_string(FileAccess.get_file_as_string(dir.path_join(file))), file)
	return out


## Every species and moment in the package `pkg`'s `behaviour/`, by id. A moment whose code body the
## package may not run (a release build reading a development folder, `PackageGate`) is left out with
## every species that plays it, so the director never brings it.
static func load_package(pkg: ScenePackage) -> Dictionary:
	var out := {}
	if pkg == null:
		return out
	for file in pkg.list(PACKAGE_DIR):
		if file.ends_with(".json"):
			_add(out, pkg.read_json(PACKAGE_DIR.path_join(file)), file)
	var unplayable := {}
	for id in out:
		var sp: SceneSpecies = out[id]
		var body := String((sp.data.get("player", {}) as Dictionary).get("body", ""))
		if body != "" and pkg.body(body) == null:
			unplayable[String(sp.data.get("plays", id))] = true
	for id in out.keys():
		var sp: SceneSpecies = out[id]
		if sp.body == "moment" and unplayable.has(String(sp.data.get("plays", id))):
			out.erase(id)
	return out


static func _add(out: Dictionary, parsed, file: String) -> void:
	if parsed is Dictionary:
		var sp := SceneSpecies.new()
		sp.data = parsed
		sp.id = String(parsed.get("id", file.get_basename()))
		out[sp.id] = sp
	else:
		push_warning("VibeNature: behaviour data %s does not parse" % file)


var tier: String:
	get:
		return String(data.get("tier", "visit"))

var body: String:
	get:
		return String(data.get("body", "quadruped"))


## How active the animal is at `minute` (0 .. ~1.6): its day or night level, raised to its
## twilight level in a bell around first light (`dawn` + offset) and last light (`dusk` + offset).
## `day_start_offset_min` / `day_end_offset_min` move where its day begins and ends; `twilight_dawn`
## sets the dawn bell apart from the dusk one (a catfish feeds at dusk far more than at first light).
func activity(minute: float, dawn: float, dusk: float) -> float:
	var a: Dictionary = data.get("activity", {})
	var width := maxf(1.0, float(a.get("twilight_min", 60.0)))
	var sunrise := dawn + float(a.get("dawn_offset_min", 0.0))
	var sunset := dusk + float(a.get("dusk_offset_min", 0.0))
	var m := fposmod(minute, 1440.0)
	# Its day may be shorter than the light's: dragonflies fly only once the morning has warmed.
	var day_from := fposmod(dawn + float(a.get("day_start_offset_min", 0.0)), 1440.0)
	var day_to := fposmod(dusk + float(a.get("day_end_offset_min", 0.0)), 1440.0)
	var up := m >= day_from and m < day_to if day_from < day_to else (m >= day_from or m < day_to)
	var base := float(a.get("day", 0.5)) if up else float(a.get("night", 0.0))
	var twilight := float(a.get("twilight", 0.0))
	var dawn_bell := exp(-0.5 * pow(_circular(m - sunrise) / (width * 0.5), 2.0)) * float(a.get("twilight_dawn", twilight))
	var dusk_bell := exp(-0.5 * pow(_circular(m - sunset) / (width * 0.5), 2.0)) * twilight
	return maxf(base, maxf(dawn_bell, dusk_bell))


static func _circular(d: float) -> float:
	var x := fposmod(d, 1440.0)
	return minf(x, 1440.0 - x)


## How much the weather brings it out (`weather`: rain, wind, fog (or mist), sunshine, each 0..1).
## Each of the species' multipliers applies in proportion; `needs_sun` is a floor of sunshine below
## which it does not come at all (turtles do not bask under cloud).
func weather_factor(w: Dictionary) -> float:
	var m: Dictionary = data.get("weather", {})
	var f := 1.0
	f *= lerpf(1.0, float(m.get("rain", 1.0)), clampf(float(w.get("rain", 0.0)), 0.0, 1.0))
	f *= lerpf(1.0, float(m.get("wind", 1.0)), clampf(float(w.get("wind", 0.0)) / 0.8, 0.0, 1.0))
	f *= lerpf(1.0, float(m.get("fog", 1.0)), clampf(float(w.get("fog", 0.0)), 0.0, 1.0))
	f *= lerpf(1.0, float(m.get("sun", 1.0)), clampf(float(w.get("sunshine", 0.0)), 0.0, 1.0))
	if float(w.get("sunshine", 0.0)) < float(m.get("needs_sun", 0.0)):
		f = 0.0
	return f


## Metres at which it flees `other` (0: it does not).
func fear_of(other: String) -> float:
	return float(data.get("fears", {}).get(other, 0.0))


## Metres at which it stops to watch `other` (0: it does not).
func watch_of(other: String) -> float:
	return maxf(float(data.get("watches", {}).get(other, 0.0)), fear_of(other) * 1.6)


## Metres at which it scolds `other` from safety (squirrels at foxes).
func scold_of(other: String) -> float:
	return float(data.get("scolds", {}).get(other, 0.0))


func speed(gait: String) -> float:
	var s: Dictionary = data.get("speeds", {})
	return float(s.get(gait, s.get("walk", 1.0)))


## A gait's real [cruise, top] in m/s (issue 318, `limits.gaits`); without one, the fastest gait's.
func gait_limit(gait: String) -> Vector2:
	var gaits: Dictionary = (data.get("limits", {}) as Dictionary).get("gaits", {})
	if gaits.has(gait):
		return Vector2(float(gaits[gait][0]), float(gaits[gait][1]))
	return Vector2(speed(gait), top_speed())


## The fastest it can go at all (m/s); INF for a species without limits.
func top_speed() -> float:
	var gaits: Dictionary = (data.get("limits", {}) as Dictionary).get("gaits", {})
	var top := 0.0
	for g in gaits.values():
		top = maxf(top, float((g as Array)[1]))
	return top if top > 0.0 else INF


## The most it speeds up, brakes or turns (m/s²); INF without limits.
func accel_limit() -> float:
	return float((data.get("limits", {}) as Dictionary).get("accel_m_s2", INF))


## The least time a move of `dist_m` metres can take when its fastest moment is `peak` times its
## mean speed (2 for an ease-out from full speed, 1.5 for a smoothstep from rest).
func min_sec(dist_m: float, peak: float = 1.0, gait: String = "") -> float:
	var top := top_speed() if gait == "" else gait_limit(gait).y
	return dist_m * peak / top if top < INF else 0.0


func size() -> Vector2:
	var s: Dictionary = data.get("size", {})
	return Vector2(float(s.get("length", 1.0)), float(s.get("height", 1.0)))


## How much bigger than life it is drawn on `band` (Skypatch issue 112):
## the scene is a magical forest and a 13 cm bird at true scale is a speck, so small and far animals
## are drawn larger to be read. `show_scale` is a number, or {band: factor, "default": factor}.
## `max_art_px_per_m` caps it (never above life size). `min_art_px_per_m` is a floor instead: never drawn smaller than that (a heron across the pond is
## drawn as big as one nearby, which already reads).
func show_scale(band: String, art_ppm: float = 0.0) -> float:
	var s: Variant = data.get("show_scale", 1.0)
	var f := float((s as Dictionary).get(band, (s as Dictionary).get("default", 1.0))) if s is Dictionary else float(s)
	var floor_ppm := float(data.get("min_art_px_per_m", 0.0))
	if floor_ppm > 0.0 and art_ppm > 0.0:
		f = maxf(f, floor_ppm / art_ppm)
	# And a ceiling: a sparrow rushing past close by stays a sparrow, not the size of a crow.
	var ceiling := float(data.get("max_art_px_per_m", 0.0))
	if ceiling > 0.0 and art_ppm > 0.0:
		f = minf(f, maxf(1.0, ceiling / art_ppm))
	return f


func range_of(key: String, fallback: Array = [1, 1]) -> Vector2:
	var r: Array = data.get(key, fallback)
	return Vector2(float(r[0]), float(r[1]))


## Its habitat kinds and weights ({ground_far: 0.6, ...}).
func habitat() -> Dictionary:
	return data.get("habitat", {})


func activities() -> Array:
	return data.get("activities", [])


## Which of the bench's drawings plays this animal (`sheets` in its data: adult variants by
## chance, and the young): {id, swap, scale}, or {} for the placeholder.
## The sheet option named `id` (its swaps and tweaks), or just the id when the species lists none by it.
func sheet_option(id: String, young: bool) -> Dictionary:
	var all: Dictionary = data.get("sheets", {})
	for o in all.get("young" if young else "adult", []) + all.get("adult" if young else "young", []):
		if String((o as Dictionary).get("id", "")) == id:
			return o
	return {"id": id}


func pick_sheet(young: bool, rng: RandomNumberGenerator) -> Dictionary:
	var all: Dictionary = data.get("sheets", {})
	var options: Array = all.get("young" if young and all.has("young") else "adult", [])
	if options.is_empty():
		return {}
	var roll := rng.randf()
	for o in options:
		roll -= float(o.get("chance", 1.0))
		if roll <= 0.0:
			return o
	return options[-1]
