class_name SceneSpeedMeter
extends RefCounted

## How fast every animal in the scene really moves (issue 318):
## sampled once a step, each mover is put in metres (across, up, away from the viewer), so a move
## toward or away counts its distance in depth, not only on screen. Speed is over `WIN` steps
## (a fifth of a second at 30 fps), acceleration the change of that velocity over the next `WIN`;
## a step where something is put somewhere (a beat's `at`) or is out of sight breaks the window.
## `top[species]` keeps the most of each and the path kind that used it ("state/beat").

const WIN := 6

var dt := 1.0 / 30.0
## species id -> {speed, speed_kind, accel, accel_kind, kinds: {kind: [speed, accel]}}
var top := {}
## How many times a creature was handed to another band where it stood (not measured as a move).
var band_changes := 0
## species id -> {jump, kind}: the most a hand-off to another band changed its drawn size (larger
## over smaller, 1.0 none). A hand-off is one step, so its depth may barely change (issue 334: the
## turtle climbing onto the log's far end grew about 7x).
var band_jump := {}
## A species id whose every window is printed (the probe's `trace:<id>`), else "".
var trace := ""
var _hist := {}
var _bands := {}
var _ppms := {}

## Desktop flights are measured under this id, against the flight species' limits.
const FLIGHT := "desktop_flight"
const FLIGHT_MODES := ["flap", "bound", "glide", "takeoff", "hover"]


func sample(beh: SceneBehaviour) -> void:
	var seen := {}
	var w := beh.scene.size_pt.x * 0.5
	for c in beh.creatures:
		var cr: SceneCreature = c
		if cr.state == "gone":
			continue
		var ok := cr.alpha > 0.05 and not (cr.beat.has("at") and cr.beat_t <= dt * 1.5)
		# Handed from one band to another where it stands (onto a rock, into the water) is not a move.
		var key := cr.get_instance_id()
		var p_now := cr.ppm()
		if _bands.get(key, cr.band) != cr.band:
			ok = false
			band_changes += 1
			var was := float(_ppms[key])
			var jump := maxf(p_now, was) / maxf(0.01, minf(p_now, was))
			if jump > float(band_jump.get(cr.sp.id, {}).get("jump", 0.0)):
				band_jump[cr.sp.id] = {"jump": jump, "kind": "%s %s→%s at %s" % [kind_of(cr), _bands[key], cr.band, cr.pos.round()]}
		_bands[key] = cr.band
		_ppms[key] = p_now
		_add(seen, key, cr.sp.id, kind_of(cr), metres(beh, cr), ok)
	for f in beh.flocks:
		var flock: SceneFlock = f
		for b in flock.birds:
			var look: Node2D = b["look"]
			var ok := float(b.get("alpha", 1.0)) > 0.05 and look.visible
			_add(seen, look.get_instance_id(), flock.sp.id, "%s/%s" % [flock.state, b["mode"]], b["p"], ok)
	for f in beh.odonata.flies:
		# Dragonflies are drawn at one size wherever they are, over the near water: measured at its scale.
		var at: Vector2 = f["pos"]
		var p := beh.ppm("near", at.y)
		var m := Vector3((at.x - w) / p, -at.y / p, beh.depth_of(p))
		_add(seen, (f["holder"] as Node).get_instance_id(), String(f["id"]), "%s%s" % [f["mode"], "/leaving" if bool(f["leaving"]) else ""], m, true)
	var flights: SceneDesktopFlight = beh.scene.flights
	if flights.flying() and String(flights.active.get("crosser", "")) == "":
		# Planned in screen units: put in metres at the bird's real distance on the screen's plane
		# (its points per metre without the species' show_scale), so a flight answers to the
		# flight species' own limits (issue 334).
		var shape := "%s/%s" % [flights.active["kind"], flights.active["shape"]]
		for f in flights.active["birds"]:
			if not f.has("at"):
				continue
			var at: Vector2 = f["at"]
			var u := beh.scene.scale_px * maxf(0.01, float(f.get("real_s", f["s"])))
			var mode: String = FLIGHT_MODES[clampi((f["path"] as SceneFlightPath).mode_at(float(flights.active["t"])), 0, 4)]
			_add(seen, -(f["look"] as Node).get_instance_id(), FLIGHT, "%s/%s" % [shape, mode], Vector3(at.x / u, -at.y / u, 0.0), true)
	# Every big moment that plays itself measures its own movers (`speed_samples`, issue 427):
	# [key, species id, kind, metres, shown] each, in the moments' step order.
	for m in beh.big_moments().values():
		if m != null and m.has_method("speed_samples"):
			for row in m.speed_samples(dt):
				_add(seen, int(row[0]), String(row[1]), String(row[2]), row[3], bool(row[4]))
	for k in _hist.keys():
		if not seen.has(k):
			_hist.erase(k)


## Where a creature is, in metres: across from the picture's middle, up from the pond's surface at its
## distance, and away from the viewer. A fish's depth is its place front to back in the cut-away.
static func metres(beh: SceneBehaviour, c: SceneCreature) -> Vector3:
	var w := beh.scene.size_pt.x * 0.5
	if c.sp.body == "fish":
		var s := c.ppm() * c.depth_size()
		return Vector3((c.pos.x - w) / s, (beh.cut_y() - c.pos.y) / s, c.depth_z * float(c._depth_tuning()["span_m"]))
	var p := c.ppm()
	var z := beh.depth_of(p)
	return Vector3((c.pos.x - w) / p, (beh.ground_y(z) - c.pos.y) / p, z)


## The same for a creature put at `at` drawn at `at_ppm` points per metre (a point along a planned path).
static func metres_at(beh: SceneBehaviour, c: SceneCreature, at: Vector2, at_ppm: float) -> Vector3:
	var w := beh.scene.size_pt.x * 0.5
	if c.sp.body == "fish":
		var s := at_ppm * c.depth_size()
		return Vector3((at.x - w) / s, (beh.cut_y() - at.y) / s, c.depth_z * float(c._depth_tuning()["span_m"]))
	var z := beh.depth_of(at_ppm)
	return Vector3((at.x - w) / at_ppm, (beh.ground_y(z) - at.y) / at_ppm, z)


static func kind_of(c: SceneCreature) -> String:
	var b := c.beat
	var k := String(b.get("a", "idle"))
	if b.has("path"):
		k = "path:" + String(b.get("approach", b.get("a", "")))
	elif b.has("to"):
		k = "to:" + String(b.get("gait", b.get("a", "walk")))
	return "%s/%s" % [c.state, k]


func _add(seen: Dictionary, key: int, id: String, kind: String, p: Vector3, ok: bool) -> void:
	seen[key] = true
	if not _hist.has(key):
		_hist[key] = {"p": [], "ok": [], "v": []}
	var h: Dictionary = _hist[key]
	var ps: Array = h["p"]
	var oks: Array = h["ok"]
	var vs: Array = h["v"]
	ps.append(p)
	oks.append(ok)
	var n := ps.size()
	var v: Variant = null
	if n > WIN and not oks.slice(n - WIN - 1).has(false):
		v = ((ps[n - 1] as Vector3) - (ps[n - 1 - WIN] as Vector3)) / (WIN * dt)
	vs.append(v)
	if ps.size() > WIN * 2 + 1:
		ps.pop_front()
		oks.pop_front()
		vs.pop_front()
	if v == null:
		return
	var speed := (v as Vector3).length()
	var accel := -1.0
	var old: Variant = vs[vs.size() - 1 - WIN] if vs.size() > WIN else null
	if old != null:
		accel = ((v as Vector3) - (old as Vector3)).length() / (WIN * dt)
		if trace != "" and id == trace:
			print("%s %s v %s (%.2f) was %s: %.1f m/s2" % [id, kind, (v as Vector3).snappedf(0.01), speed, (old as Vector3).snappedf(0.01), accel])
	_note(id, kind, speed, accel)


func _note(id: String, kind: String, speed: float, accel: float) -> void:
	if not top.has(id):
		top[id] = {"speed": 0.0, "speed_kind": "", "accel": 0.0, "accel_kind": "", "kinds": {}}
	var t: Dictionary = top[id]
	if speed > float(t["speed"]):
		t["speed"] = speed
		t["speed_kind"] = kind
	if accel > float(t["accel"]):
		t["accel"] = accel
		t["accel_kind"] = kind
	var ks: Dictionary = t["kinds"]
	var row: Array = ks.get(kind, [0.0, 0.0])
	ks[kind] = [maxf(float(row[0]), speed), maxf(float(row[1]), accel)]


## A species' limits from its data (`limits`): {top, accel}; top is the fastest of its gaits.
static func limits_of(sp: SceneSpecies) -> Dictionary:
	var l: Dictionary = sp.data.get("limits", {})
	var top_m := 0.0
	for g in (l.get("gaits", {}) as Dictionary).values():
		top_m = maxf(top_m, float((g as Array)[1]))
	return {"top": top_m, "accel": float(l.get("accel_m_s2", 0.0))}


## The limits `id` answers to: its own, or for desktop flights the flight species'.
static func limits_for(species: Dictionary, id: String) -> Dictionary:
	if id == FLIGHT:
		id = String(SceneDesktopFlight.load_data().get("species", "songbirds_few"))
	return limits_of(species[id]) if species.has(id) else {"top": 0.0, "accel": 0.0}


## Lines of the table: species, top speed (kind), its limit, top acceleration (kind), its limit.
func table(species: Dictionary) -> Array:
	var out: Array = []
	var ids := top.keys()
	ids.sort()
	for id in ids:
		var t: Dictionary = top[id]
		var lim := limits_for(species, id)
		var over := float(t["speed"]) > float(lim["top"]) + 0.001 or float(t["accel"]) > float(lim["accel"]) + 0.001
		out.append("| %s | %.1f | %s | %.1f | %.1f | %s | %.1f |%s" % [id, t["speed"], t["speed_kind"], lim["top"], t["accel"], t["accel_kind"], lim["accel"],
				" **over**" if over else ""])
	return out
