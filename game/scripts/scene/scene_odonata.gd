class_name SceneOdonata
extends Node2D

## Dragonflies and damselflies (ambient, Skypatch issue 116):
## the blue darner, the meadowhawk and the bluet, up to `max_total` at a time, on sunny warm days
## only. They fill the gaps between the bigger moments.
##
## How they move is how odonata move: a straight run at speed that starts and stops short, then a
## dead-still hover (now and then pivoting to face the other way where it hangs), then another
## run; after a few runs a rest on a cattail tip, a reed top or a lily pad, riding the stem as it
## sways, and off again (a meadowhawk sallies out and comes back to the same perch). Each species'
## habits are its `flight` in the behaviour data; the places (`patrol`, `low`, the perch pieces and
## the pads) are the kit's, in the scene package's `behaviour/places/<kit>.json` `odonata`.
##
## Drawn from the bench's sheets (440 px/m) at exactly one art px per sheet px wherever they are,
## and always on whole art px, so they stay crisp and nothing shimmers. Units are scene points.

var beh: SceneBehaviour
var tuning: Dictionary = {}
var flies: Array = []
var _patrols := {}
var _perches := {}
var _rng := RandomNumberGenerator.new()


func setup(owner: SceneBehaviour, odonata_tuning: Dictionary, seed: int) -> void:
	beh = owner
	tuning = odonata_tuning
	name = "Odonata"
	_rng.seed = seed
	var spec: Dictionary = beh.places.get("odonata", {})
	for key in ["patrol", "low"]:
		var poly := PackedVector2Array()
		for p in spec.get(key, []):
			poly.append(beh.uv(p))
		if not poly.is_empty():
			_patrols[key] = poly
	var all_perches: Array = beh.scene.perches()
	var by_piece: Dictionary = spec.get("perch_pieces", {})
	for kind in by_piece:
		var list: Array = []
		for perch in all_perches:
			if (by_piece[kind] as Array).has(String(perch["piece"])):
				list.append({"piece": String(perch["piece"]), "at": perch["at"], "kind": kind})
		_perches[kind] = list
	_perches["pad"] = _pads(String(spec.get("pads", "")))


## Places on a lily pad's top surface, from the piece's own pixels: green, with pad under it.
func _pads(piece_id: String) -> Array:
	var out: Array = []
	var image := beh.scene.piece_image(piece_id)
	if image == null:
		return out
	var origin := Vector2(SceneKit._vec2i(beh.scene.kit.piece(piece_id)["at"]))
	var step := int(tuning.get("pad_step_px", 6))
	for y in range(2, image.get_height() - 3, 2):
		for x in range(0, image.get_width(), step):
			var c := image.get_pixel(x, y)
			if c.a < 0.9 or c.g < c.r or c.g < c.b:
				continue
			# Not the pad's very rim, and with pad below the feet, so it stands on the surface.
			if image.get_pixel(x, y - 2).a < 0.5 or image.get_pixel(x, y + 3).a < 0.5:
				continue
			if image.get_pixel(x - 4 if x >= 4 else x, y).a < 0.5 or image.get_pixel(mini(x + 4, image.get_width() - 1), y).a < 0.5:
				continue
			out.append({"piece": piece_id, "at": (origin + Vector2(x, y)) / beh.scene.density, "kind": "pad", "still": true})
	return out


func count(id: String = "") -> int:
	if id == "":
		return flies.size()
	return flies.filter(func(f: Dictionary) -> bool: return String(f["id"]) == id).size()


## Whether the air suits them now: sun, no rain, not too windy, by day.
func weather_ok() -> bool:
	var env := beh.scene.env
	return env.rain < float(tuning["max_rain"]) and env.sunshine() >= float(tuning["min_sunshine"]) and env.wind.mean < float(tuning["max_wind"])


## Room for one more of `id`: under its own `max_present` and under `max_total` for all of them.
func has_room(id: String) -> bool:
	var sp: SceneSpecies = beh.species.get(id)
	return sp != null and count() < int(tuning["max_total"]) and count(id) < int(sp.data.get("max_present", 1))


## One comes in from outside the scene (above, or a side). False if there is no room or no sheet.
func add(id: String) -> bool:
	if not has_room(id) or _patrols.is_empty():
		return false
	var sp: SceneSpecies = beh.species[id]
	var drawn := sp.pick_sheet(false, _rng)
	var sheet := SceneSheet.load_for(String(drawn.get("id", "")))
	if sheet == null:
		return false
	var holder := Node2D.new()
	holder.name = id
	holder.add_child(sheet)
	beh.scene.actor_layer(String(tuning["layer"])).add_child(holder)
	var flight: Dictionary = sp.data.get("flight", {})
	var poly: PackedVector2Array = _patrols.get(String(flight.get("patrol", "patrol")), _patrols.values()[0])
	var target := _point_in(poly)
	var size := beh.scene.size_pt
	var from := Vector2(target.x + _rng.randf_range(-120.0, 120.0), -float(tuning["enter_margin_pt"]))
	if _rng.randf() < 0.5:
		var left := target.x < size.x * 0.5
		from = Vector2(-float(tuning["enter_margin_pt"]) if left else size.x + float(tuning["enter_margin_pt"]), target.y - _rng.randf_range(20.0, 90.0))
	var f := {
		"id": id, "sp": sp, "flight": flight, "poly": poly, "sheet": sheet, "holder": holder,
		"pos": from, "facing": 1.0 if target.x >= from.x else -1.0, "mode": "dart", "t": 0.0, "dur": 0.0,
		"from": from, "to": target, "perch": {}, "home": {}, "runs_left": _ri(flight, "runs_before_rest", [2, 6]),
		"stay": _rf(sp.data, "stay_sec", [60, 120]), "leaving": false, "pivot_at": -1.0,
	}
	_start_dart(f, target, true)
	flies.append(f)
	_draw_fly(f, 0.0, Color.WHITE)
	beh.note("%s comes" % id, id)
	return true


func step(dt: float, tint: Color) -> void:
	var ok := weather_ok()
	for f in flies.duplicate():
		f["stay"] = float(f["stay"]) - dt
		# Cloud, rain or wind sends them off soon; their time up, they go.
		if not bool(f["leaving"]) and (float(f["stay"]) <= 0.0 or not ok):
			if not ok:
				f["stay"] = minf(float(f["stay"]), _rng.randf_range(0.5, 4.0))
			if float(f["stay"]) <= 0.0:
				_leave(f)
		_advance(f, dt)
		if bool(f["leaving"]) and String(f["mode"]) == "gone":
			(f["holder"] as Node).queue_free()
			flies.erase(f)
			beh.note("%s leaves" % f["id"], String(f["id"]))
			continue
		_draw_fly(f, dt, tint)


func _advance(f: Dictionary, dt: float) -> void:
	f["t"] = float(f["t"]) + dt
	var t := float(f["t"])
	var flight: Dictionary = f["flight"]
	match String(f["mode"]):
		"dart":
			# Coming in to a perch, it homes on the tip as the stem sways.
			if not (f["perch"] as Dictionary).is_empty():
				f["to"] = _perch_at(f["perch"])
			var u := clampf(t / maxf(float(f["dur"]), 0.001), 0.0, 1.0)
			f["pos"] = (f["from"] as Vector2).lerp(f["to"], _dart_ease(u))
			if u >= 1.0:
				if bool(f.get("held", false)) and not (f.get("via", []) as Array).is_empty():
					_start_dart(f, (f["via"] as Array).pop_front())
				elif bool(f["leaving"]):
					f["mode"] = "gone"
				elif not (f["perch"] as Dictionary).is_empty():
					f["mode"] = "perch"
					f["t"] = 0.0
					f["dur"] = _rf(flight, "perch_sec", [5, 15])
				else:
					f["mode"] = "hover"
					f["t"] = 0.0
					f["dur"] = _rf(flight, "hover_sec", [0.4, 1.5])
					f["pivot_at"] = _rng.randf_range(0.3, 0.7) * float(f["dur"]) if _rng.randf() < float(flight.get("pivot_chance", 0.0)) else -1.0
		"hover":
			if float(f["pivot_at"]) >= 0.0 and t >= float(f["pivot_at"]):
				f["pivot_at"] = -1.0
				f["facing"] = -float(f["facing"])
			# Held over the water for a bass's leap (issue 299): it hangs there until let go.
			if t >= float(f["dur"]) and not bool(f.get("held", false)):
				_next(f)
		"perch":
			var perch: Dictionary = f["perch"]
			f["pos"] = _perch_at(perch)
			if t >= float(f["dur"]):
				f["home"] = perch
				f["perch"] = {}
				f["runs_left"] = _ri(flight, "runs_before_rest", [2, 6])
				_next(f)


## After a hover or a rest: rest if the runs are spent (and it likes to), else another run.
func _next(f: Dictionary) -> void:
	var flight: Dictionary = f["flight"]
	f["runs_left"] = int(f["runs_left"]) - 1
	if int(f["runs_left"]) <= 0 and _rng.randf() < float(flight.get("rest_chance", 0.5)):
		var perch := _pick_perch(f)
		if not perch.is_empty():
			f["perch"] = perch
			_start_dart(f, _perch_at(perch))
			return
	if int(f["runs_left"]) <= 0:
		f["runs_left"] = _ri(flight, "runs_before_rest", [2, 6])
	_start_dart(f, _run_target(f))


## A perch of a kind it likes that nobody else is on: back to the last one for a sally, else the
## nearest few of a kind picked by its weights.
func _pick_perch(f: Dictionary) -> Dictionary:
	var flight: Dictionary = f["flight"]
	var home: Dictionary = f["home"]
	if not home.is_empty() and _rng.randf() < float(flight.get("sally_chance", 0.0)) and not _taken(home, f):
		return home
	var weights: Dictionary = flight.get("perches", {})
	var total := 0.0
	for kind in weights:
		if not (_perches.get(kind, []) as Array).is_empty():
			total += float(weights[kind])
	if total <= 0.0:
		return {}
	var roll := _rng.randf() * total
	var kind := ""
	for k in weights:
		if (_perches.get(k, []) as Array).is_empty():
			continue
		kind = String(k)
		roll -= float(weights[k])
		if roll <= 0.0:
			break
	var options: Array = (_perches[kind] as Array).filter(func(p: Dictionary) -> bool: return not _taken(p, f))
	if options.is_empty():
		return {}
	var here: Vector2 = f["pos"]
	options.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return here.distance_squared_to(a["at"]) < here.distance_squared_to(b["at"]))
	return options[_rng.randi_range(0, mini(3, options.size() - 1))]


func _taken(perch: Dictionary, by: Dictionary) -> bool:
	for other in flies:
		var p: Dictionary = other["perch"]
		if other != by and not p.is_empty() and (p["at"] as Vector2).distance_to(perch["at"]) < float(tuning["perch_apart_pt"]):
			return true
	return false


## Where a perch is now: its tip carried by the stem's sway (a pad does not sway).
func _perch_at(perch: Dictionary) -> Vector2:
	var at: Vector2 = perch["at"]
	if bool(perch.get("still", false)):
		return at
	return at + beh.scene.perch_offset(String(perch["piece"]), at)


## The end of the next run: a straight line from here, mostly across rather than up or down,
## inside its patrol.
func _run_target(f: Dictionary) -> Vector2:
	var flight: Dictionary = f["flight"]
	var poly: PackedVector2Array = f["poly"]
	var here: Vector2 = f["pos"]
	for i in 16:
		var a := _rng.randf_range(-0.6, 0.6) + (PI if _rng.randf() < 0.5 else 0.0)
		var d := _rf(flight, "run_pt", [20, 80])
		var q := here + Vector2(cos(a), sin(a) * 0.7) * d
		if Geometry2D.is_point_in_polygon(q, poly):
			return q
	return _point_in(poly)


func _start_dart(f: Dictionary, to: Vector2, entering: bool = false) -> void:
	var flight: Dictionary = f["flight"]
	var from: Vector2 = f["pos"]
	f["mode"] = "dart"
	f["t"] = 0.0
	f["from"] = from
	f["to"] = to
	var speed := _rf(flight, "speed_pt", [150, 250]) * (float(tuning["enter_speed"]) if entering else 1.0)
	f["dur"] = maxf(from.distance_to(to) / maxf(speed, 1.0), float(tuning["min_dart_sec"]))
	if absf(to.x - from.x) > float(tuning["turn_min_pt"]):
		f["facing"] = signf(to.x - from.x)


## Off it goes: a long run up and out of the scene.
func _leave(f: Dictionary) -> void:
	f["leaving"] = true
	f["perch"] = {}
	var here: Vector2 = f["pos"]
	var size := beh.scene.size_pt
	var m := float(tuning["enter_margin_pt"])
	var out := Vector2(here.x + _rng.randf_range(-200.0, 200.0), -m)
	if _rng.randf() < 0.5:
		out = Vector2(-m if here.x < size.x * 0.5 else size.x + m, here.y - _rng.randf_range(30.0, 120.0))
	_start_dart(f, out, true)


# --- A bass's leap (issue 299) ---------------

## A dragonfly for the bass to go for: one already flying (`id`'s kind first), else one comes in.
## Empty when none can (no room, no sheet, the air not right).
func summon(id: String) -> Dictionary:
	var mine := flies.filter(func(f: Dictionary) -> bool: return not bool(f["leaving"]))
	mine.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return String(a["id"]) == id and String(b["id"]) != id)
	if not mine.is_empty():
		return mine[0]
	if not weather_ok() or not add(id):
		return {}
	return flies[-1]


## Flies it low over the water to `at` and keeps it hovering there (dead still, as they do) until
## `jink` or `take`. Its time is held too, so it does not leave mid-moment.
## `via`: points it runs through first (issue 340: down to the water off to one side, then a skim in
## low along it to the station), one run each.
func hold(f: Dictionary, at: Vector2, via: Array = []) -> void:
	f["held"] = true
	f["perch"] = {}
	f["leaving"] = false
	f["stay"] = maxf(float(f["stay"]), 30.0)
	f["via"] = via.duplicate()
	(f["via"] as Array).append(at)
	_start_dart(f, (f["via"] as Array).pop_front())


func at_station(f: Dictionary) -> bool:
	return bool(f.get("held", false)) and String(f["mode"]) == "hover"


## Missed: it jinks away, a fast short run up and off to one side, then flies on as before.
func jink(f: Dictionary, away: float, run_pt: Vector2, speed: float) -> void:
	f["held"] = false
	var here: Vector2 = f["pos"]
	_start_dart(f, here + Vector2(away * run_pt.x, -run_pt.y))
	f["dur"] = maxf(here.distance_to(f["to"]) / maxf(speed, 1.0), float(tuning["min_dart_sec"]))


## Let go without a leap (the moment gave up): it flies on.
func release(f: Dictionary) -> void:
	if flies.has(f):
		f["held"] = false
		if String(f["mode"]) == "hover":
			f["dur"] = 0.0


## Caught: the bass's own frames draw it in the mouth from here on, so ours goes.
func take(f: Dictionary) -> void:
	if not flies.has(f):
		return
	(f["holder"] as Node).queue_free()
	flies.erase(f)
	beh.note("a bass takes the %s" % f["id"], String(f["id"]))


## A quick start and a short stop, the middle at full speed: how a dragonfly's runs look.
static func _dart_ease(u: float) -> float:
	var r := 0.18
	var v := 1.0 / (1.0 - r)
	if u < r:
		return v * u * u / (2.0 * r)
	if u > 1.0 - r:
		var w := 1.0 - u
		return 1.0 - v * w * w / (2.0 * r)
	return v * (u - r * 0.5)


func _draw_fly(f: Dictionary, dt: float, tint: Color) -> void:
	var holder: Node2D = f["holder"]
	var sheet: SceneSheet = f["sheet"]
	var density := beh.scene.density
	# One sheet px to one art px: the holder is in metres at the sheet's own px per metre.
	var k := sheet.master_ppm / density
	holder.scale = Vector2(k * float(f["facing"]), k)
	holder.position = ((f["pos"] as Vector2) * density).round() / density
	var mode := String(f["mode"])
	sheet.set_action("fly" if mode in ["dart", "gone"] else ("hover" if mode == "hover" else "perch"))
	sheet.update(dt, 0.0, sheet.master_ppm)
	holder.modulate = Color(tint.r, tint.g, tint.b, 1.0)


func _point_in(poly: PackedVector2Array) -> Vector2:
	var box := Rect2(poly[0], Vector2.ZERO)
	for p in poly:
		box = box.expand(p)
	for i in 30:
		var q := Vector2(_rng.randf_range(box.position.x, box.end.x), _rng.randf_range(box.position.y, box.end.y))
		if Geometry2D.is_point_in_polygon(q, poly):
			return q
	return box.get_center()


func _rf(d: Dictionary, key: String, fallback: Array) -> float:
	var r: Array = d.get(key, fallback)
	return _rng.randf_range(float(r[0]), float(r[1]))


func _ri(d: Dictionary, key: String, fallback: Array) -> int:
	var r: Array = d.get(key, fallback)
	return _rng.randi_range(int(r[0]), int(r[1]))
