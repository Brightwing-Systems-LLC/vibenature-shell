class_name SceneDesktopFlight
extends Node

## Rare desktop flights (Skypatch issue 120,
## Skypatch issue 134): a songbird on a perch in the scene
## takes off, leaves over the scene's edge and crosses the desktop on a natural line
## (`SceneFlightPath`: one of several shapes, flown as its species flies, in any direction the
## scene's place on the screen leaves open), then comes back and lands with its party, or flies off
## the screen. A second bird may chase it, or a few may swirl together and split to land. With
## nobody on a perch, one may come in from off the screen instead. Rare crossers (a hawk on a
## thermal, a V of geese) cross high and never land, once their sheets exist. When is
## `SceneFlightRule`'s; tuning is the scene package's `behaviour/flights/desktop.json`.
##
## Inside the scene a bird is drawn in the scene (front band); once any of it is past the scene's
## edge it is drawn in the transit window (`TransitWindow`: borderless, transparent, never
## focusable, click-through everywhere), which follows the flight's leader and holds the whole
## party (company stays within it). That window is made once, when flights are on, and stays open
## and empty between flights: a flight only moves it, so a flight never creates, shows, raises or
## orders a window, never takes focus or the mouse, and never activates the app (the native
## extension makes it a non-activating panel besides). It is always above other windows, whether
## or not the scene is on top (`TransitWindow.OVERLAY_TITLE`, issue 235). Nothing here reads anything from outside the
## game: the desktop is only its usable rectangle.

## In the scene package (contract §8): `behaviour/flights/desktop.json`.
const TUNING := "behaviour/flights/desktop.json"

var scene: LivingScene
var data: Dictionary = {}
var rule: SceneFlightRule
var rng := RandomNumberGenerator.new()
var transit: TransitWindow
## The usable desktop in screen units (window coordinates). The snapshot clip sets its own.
var desktop_rect: Callable
## The flight under way, or {}: {kind, shape, t, birds: [{path, look, bird, flock, s, where,
## facing, land}], crosser}. `path`, `look`, `bird`, `flock` and `where` are the leader's (where:
## "desktop" while any of the party is out there).
var active: Dictionary = {}
## Windows this has made (one, ever, while flights are on).
var windows_made := 0
## Asked for by a clip or the debug panel for the next flight: {shape, company}.
var next: Dictionary = {}
var _enabled := true
## `VIBENATURE_FLIGHT_SOON=1` (issue 317): the first flight comes `rule.soon_after_sec` after a
## songbird party settles, for play-testing. -1 off, 0 waiting for a party, else when it is due (`rule.t`).
var soon_at := -1.0
var _soon_refused := ""
## `_transit_pt`, found once: it reads the crossers' sheets, and a flight asks every frame.
var _transit_size := Vector2.ZERO


func setup(owner_scene: LivingScene, seed: int, flight_data: Dictionary = {}) -> void:
	scene = owner_scene
	name = "DesktopFlights"
	data = flight_data if not flight_data.is_empty() else load_data()
	rng.seed = seed
	rule = SceneFlightRule.new(data["rule"], seed + 1)
	rule.say = func(line: String) -> void: print("desktop flight: " + line)
	if OS.get_environment("VIBENATURE_FLIGHT_SOON") == "1":
		soon_at = 0.0
		print("desktop flight: VIBENATURE_FLIGHT_SOON: the first one comes soon after a songbird party settles")


static func load_data() -> Dictionary:
	var pkg := ScenePackages.scene()
	var parsed = pkg.read_json(TUNING) if pkg != null else null
	return parsed if parsed is Dictionary else {}


## The path tuning for a bird of cast id `who` flying `kind`: the base numbers bent by its style,
## with the shapes that kind of flight may take.
static func path_tuning(flight_data: Dictionary, who: String, kind: String) -> Dictionary:
	var style: Dictionary = flight_data.get("styles", {}).get(who, {})
	var tuning: Dictionary = (flight_data["path"] as Dictionary).merged(style.get("path", {}), true)
	var base: Dictionary = flight_data["path"].get({"out": "out_shapes", "in": "in_shapes"}.get(kind, "shapes"), flight_data["path"]["shapes"])
	var shapes := base.duplicate()
	for s in style.get("shapes", {}):
		if shapes.has(s):
			shapes[s] = float(style["shapes"][s])
	var total := 0.0
	for s in shapes:
		total += float(shapes[s])
	tuning["shapes"] = shapes if total > 0.0 else base
	return tuning


## Company chances for a bird of cast id `who`: {pair, swirl}.
static func company_of(flight_data: Dictionary, who: String) -> Dictionary:
	var base: Dictionary = flight_data.get("company", {})
	return base.merged(flight_data.get("styles", {}).get(who, {}).get("company", {}), true)


func _ready() -> void:
	if _enabled:
		_make_window.call_deferred()


func _exit_tree() -> void:
	if transit != null and is_instance_valid(transit):
		transit.queue_free()
	transit = null


## The player's switch: off stops any flight now (a bird on the desktop goes; one still in the
## scene goes back to its party) and no more come.
func set_enabled(on: bool) -> void:
	_enabled = on
	rule.enabled = on
	if not on:
		abort()
	elif is_inside_tree():
		_make_window()


## The scene changed size (issue 307): any flight stops, and the transit window is made again at
## the scene's new scale.
func rescale() -> void:
	abort()
	if transit != null and is_instance_valid(transit):
		transit.queue_free()
	transit = null
	_drawing = false
	if _enabled and is_inside_tree():
		_make_window()


func is_enabled() -> bool:
	return _enabled


func flying() -> bool:
	return not active.is_empty()


## Claude's edges, from `SceneBehaviour`: a session's prompt (true when its moment is a flight) and
## a session's turn end, whether or not others still work.
func turn_started() -> bool:
	return rule.turn_started()


func turn_ended() -> void:
	rule.turn_ended()


func step(dt: float) -> void:
	var env := scene.env
	var ctx := {"daylight": env.daylight(), "rain": env.rain, "flying": flying()}
	if rule.tick(dt, ctx):
		var crosser := _due_crosser()
		if crosser != "":
			_started(start(crosser))
		else:
			_started(start())
	elif soon_at >= 0.0:
		_soon(ctx)
	if not active.is_empty():
		_step_flight(dt)


func _started(ok: bool) -> void:
	if not ok:
		print("desktop flight: refused: %s" % ("switched off" if not _enabled else "no bird to fly (none settled and none may come in)"))


## `VIBENATURE_FLIGHT_SOON`: once a party has settled, a flight in `soon_after_sec`, still only in
## daylight and dry; then the rule as usual.
func _soon(ctx: Dictionary) -> void:
	if soon_at == 0.0:
		if not _perched_options().is_empty():
			var d: Array = data["rule"]["soon_after_sec"]
			var in_sec := rng.randf_range(float(d[0]), float(d[1]))
			soon_at = rule.t + in_sec
			print("desktop flight: planned: soon flight in %.0f s (a party settled)" % in_sec)
		return
	if rule.t < soon_at:
		return
	var no := rule.refusal(ctx)
	if no == "" and _perched_options().is_empty():
		no = "no bird settled now"
	if no != "":
		if no != _soon_refused:
			print("desktop flight: refused: soon flight, %s (waiting)" % no)
		_soon_refused = no
		return
	if start():
		soon_at = -1.0


## Starts a flight now (the rule's call, a clip's event, the debug panel). `kind` "" picks: from a
## perch, out and back when its party will still be there, else out; with nobody perched, in. A
## crosser's id (`crossers` in the tuning) sends that crosser, if its sheet exists.
func start(kind: String = "") -> bool:
	if not _enabled or flying() or (scene.behaviour != null and scene.behaviour.keeps_birds_away()):
		return false
	var wish := next
	next = {}
	if data.get("crossers", {}).has(kind):
		var ok := _start_crosser(kind)
		if ok:
			rule.flew()
		return ok
	if not scene.behaviour.species.has(String(data["species"])):
		return false
	_make_window()
	var found := _perched_bird(String(wish.get("who", "")))
	if kind == "":
		if found.is_empty():
			kind = "in" if bool(data["kinds"].get("arrive_when_empty", true)) else ""
		else:
			var flock: SceneFlock = found["flock"]
			var stays := flock.stay - flock.t > float(data["kinds"]["return_needs_stay_sec"])
			kind = "out_back" if stays and rng.randf() < float(data["kinds"]["return_chance"]) else "out"
	if kind == "":
		return false
	var ok := _start_in(wish) if kind == "in" else (not found.is_empty() and _start_out(kind, found, wish))
	if ok:
		rule.flew()
		scene.behaviour.note("desktop flight: %s %s%s" % [kind, active["shape"], " with %d" % (active["birds"].size() - 1) if active["birds"].size() > 1 else ""],
				String(data["species"]))
	return ok


## Some bird of the flight species settled in the scene (of cast id `who`, if given): {flock, bird}, or {}.
func _perched_bird(who: String = "") -> Dictionary:
	var options := _perched_options(who)
	return options[rng.randi() % options.size()] if not options.is_empty() else {}


func _perched_options(who: String = "") -> Array:
	var options: Array = []
	for f in scene.behaviour.flocks:
		var flock: SceneFlock = f
		if flock.transient or flock.sp.id != String(data["species"]) or flock.state != "settled":
			continue
		if who != "" and String(flock.member.get("id", "")) != who:
			continue
		for b in flock.birds:
			if String(b["mode"]) in SceneFlock.DOWN and (b["perch"] as Dictionary).has("at") and float(b["wait"]) <= 0.0 and not b.has("move"):
				options.append({"flock": flock, "bird": b})
	return options


## How many others go with a bird of `flock` (cast id `who`): 0, 1 (a chase) or 2..4 (a swirl).
func _company(who: String, available: int, wish: Dictionary) -> Array:
	var odds := company_of(data, who)
	var want := String(wish.get("company", ""))
	if want == "":
		var roll := rng.randf()
		want = "pair" if roll < float(odds.get("pair", 0.0)) else ("swirl" if roll < float(odds.get("pair", 0.0)) + float(odds.get("swirl", 0.0)) else "none")
	var cap := int(data.get("company", {}).get("max", 5)) - 1
	if want == "pair" and available >= 1:
		return ["chase", 1]
	if want == "swirl" and available >= 2:
		return ["swirl", rng.randi_range(2, mini(available, cap))]
	if want == "swirl" and available == 1:
		return ["chase", 1]
	return ["none", 0]


func _start_out(kind: String, found: Dictionary, wish: Dictionary) -> bool:
	var flock: SceneFlock = found["flock"]
	var lead: Dictionary = found["bird"]
	var mates: Array = []
	for b in flock.birds:
		if b != lead and String(b["mode"]) in SceneFlock.DOWN and (b["perch"] as Dictionary).has("at") and float(b["wait"]) <= 0.0 and not b.has("move"):
			mates.append(b)
	var company := _company(String(flock.member.get("id", "")), mates.size(), wish)
	# The nearest mates go with it.
	var lead_at: Vector2 = (lead["look"] as Node2D).position
	mates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return (a["look"] as Node2D).position.distance_to(lead_at) < (b["look"] as Node2D).position.distance_to(lead_at))
	var party: Array = [lead] + mates.slice(0, int(company[1]))
	var starts: Array = []
	var lands: Array = []
	var s := 0.0
	var real := 0.0
	for b in party:
		var perch: Dictionary = b["perch"]
		if s == 0.0:
			s = _points_per_m(flock, perch)
			real = flock._ppm(perch)
		starts.append(scene.art_to_screen((b["look"] as Node2D).position))
		if perch.has("piece"):
			scene.perch_impulse(String(perch["piece"]), perch["at"], Vector2(0, float(flock.cfg["takeoff_push"])))
		lands.append(perch)
	for b in party:
		flock.birds.erase(b)
		b["perch"] = {}
		b.erase("move")
	var free := flock._free_perches()
	for i in lands.size():
		if not free.is_empty():
			lands[i] = free.pop_front()
	return _begin(kind, party, flock, s, starts, lands, String(company[0]), wish, real)


## Birds come in from off the screen to land: a party of one (or a few, with company) that the
## scene takes in when it arrives.
func _start_in(wish: Dictionary) -> bool:
	var sp: SceneSpecies = scene.behaviour.species[String(data["species"])]
	if int(scene.behaviour.present().get(sp.id, 0)) >= int(sp.data.get("max_present", 1)) or not scene.behaviour.env_allows_birds():
		return false
	var flock := SceneFlock.new()
	if not flock.setup(scene.behaviour, sp, rng.randi()) or flock.birds.is_empty():
		flock.free_birds()
		return false
	var company := _company(String(flock.member.get("id", "")), flock.birds.size() - 1, wish)
	var n := 1 + int(company[1])
	var free := flock._free_perches()
	if free.is_empty() and flock.habit == "perch":
		flock.free_birds()
		return false
	var party: Array = []
	var lands: Array = []
	var starts: Array = []
	while flock.birds.size() > n:
		(flock.birds.pop_back()["look"] as Node).queue_free()
	for i in n:
		var b: Dictionary = flock.birds.pop_back()
		party.append(b)
		lands.append(free[i % free.size()] if not free.is_empty() else {"at": scene.size_pt * 0.5, "band": "mid"})
		starts.append(Vector2.ZERO)
	flock.state = "settled"
	flock.t = 0.0
	return _begin("in", party, flock, _points_per_m(flock, lands[0]), starts, lands, String(company[0]), wish, flock._ppm(lands[0]))


## `lands`: the perches they mean to come back to (taken by then, they land on others). `s` is the
## points per metre the birds are drawn at, `real` the same at their real distance, without the
## species' `show_scale` (what `SceneSpeedMeter` measures the flight in, issue 334).
func _begin(kind: String, party: Array, flock: SceneFlock, s: float, starts: Array, lands: Array, company: String, wish: Dictionary, real: float) -> bool:
	var scale := scene.scale_px
	var bl := flock.length_m() * s * scale
	var box := _bird_box()
	var who := String(flock.member.get("id", ""))
	var tuning := path_tuning(data, who, kind)
	tuning["speed_scale"] = float(data["path"].get("speed_ref_m", 0.2)) / maxf(flock.length_m(), 0.01)
	var land_at := scene.art_to_screen(lands[0]["at"])
	var scene_rect := Rect2(Vector2(scene.position), Vector2(scene.size))
	# A scene in a top corner (issue 424): planned upside down, so the birds leave over the open desktop below it.
	var axis := _flip_axis()
	if axis != 0.0:
		scene_rect = SceneFlightPath.flip_rect(scene_rect, axis)
		land_at.y = axis - land_at.y
		starts = starts.map(func(v: Vector2) -> Vector2: return Vector2(v.x, axis - v.y))
	var lead := SceneFlightPath.plan(kind, starts[0], land_at, scene_rect, _desktop(), bl, box, tuning, rng.randi(), String(wish.get("shape", "")))
	if lead.points.is_empty():
		return false
	var birds: Array = []
	var paths: Array = []
	var half := _group_half()
	for i in party.size():
		var b: Dictionary = party[i]
		var path := lead
		if i > 0:
			path = SceneFlightPath.follow(lead, starts[i], {"kind": company, "k": i - 1, "n": party.size() - 1}, scene_rect, bl, box, half, tuning, rng.randi())
		b["mode"] = "away"
		paths.append(path)
		birds.append({"path": path, "look": b["look"], "bird": b, "flock": flock, "s": s, "real_s": real, "where": "", "facing": float(b.get("facing", 1.0)) * scene.shown_sign(), "land": lands[i]})
	_unflip(paths, axis)
	# Within the species' real limits at its real distance (issue 334): slowed where it would pass them.
	var lim := SceneSpeedMeter.limits_of(flock.sp)
	SceneFlightPath.fit(paths, real * scale, float(lim["top"]), float(lim["accel"]))
	_activate(kind, lead.shape, birds, "")
	return true


## A rare crosser (its sheet must exist): a hawk circling on a thermal, a V of geese.
func _start_crosser(id: String) -> bool:
	var spec: Dictionary = data["crossers"][id]
	if not SceneSheet.exists(String(spec["sheet"])):
		return false
	_make_window()
	var scale := scene.scale_px
	var bl := float(spec["bl_pt"]) * scale
	var tuning: Dictionary = (data["path"] as Dictionary).merged(spec.get("path", {}), true)
	var scene_rect := Rect2(Vector2(scene.position), Vector2(scene.size))
	var axis := _flip_axis()
	if axis != 0.0:
		scene_rect = SceneFlightPath.flip_rect(scene_rect, axis)
	var box := _bird_box()
	var lead := SceneFlightPath.plan_crosser(String(spec["shape"]), scene_rect, _desktop(), bl, box, tuning, rng.randi())
	var count: Array = spec.get("count", [1, 1])
	var n := rng.randi_range(int(count[0]), int(count[1]))
	var half := (_transit_pt() - _bird_pt()) * 0.5 * scene.scale_px
	var sp := SceneSpecies.new()
	sp.id = id
	sp.data = {"body": "songbird", "size": {"length": float(spec.get("length", 0.5)), "height": float(spec.get("length", 0.5)) * 0.4}}
	var s := float(spec["bl_pt"]) / float(spec.get("length", 0.5))
	var birds: Array = []
	for i in n:
		var path := lead if i == 0 else SceneFlightPath.follow(lead, Vector2.ZERO, {"kind": "v", "k": i - 1, "n": n - 1}, scene_rect, bl, box, half, tuning, rng.randi())
		var look := SceneCreatureLook.new()
		look.setup(sp, {}, 1.0, rng.randi(), String(spec["sheet"]))
		look.density = scene.density
		# Each goose on its own wingbeat, not the V in unison.
		var phase := rng.randf() * 1.2
		birds.append({"path": path, "look": look, "bird": {}, "flock": null, "s": s, "where": "", "facing": 1.0, "land": {},
				"phase": phase, "honk": float(spec.get("honk", 0.0)), "banks": bool(spec.get("banks", false)), "honk_left": 0.0})
	var paths: Array = []
	for f in birds:
		paths.append(f["path"])
	_unflip(paths, axis)
	_activate("cross", String(spec["shape"]), birds, id)
	scene.behaviour.note("desktop flight: %s crosses" % id, id)
	return true


func _activate(kind: String, shape: String, birds: Array, crosser: String) -> void:
	active = {"kind": kind, "shape": shape, "t": 0.0, "birds": birds, "crosser": crosser, "where": ""}
	_mirror_lead()
	_place(0.0)


## The leader's fields at the top of `active` (for the probe, the clip and the tests).
func _mirror_lead() -> void:
	var lead: Dictionary = active["birds"][0]
	for key in ["path", "look", "bird", "flock", "land", "facing"]:
		active[key] = lead[key]


func _step_flight(dt: float) -> void:
	var path: SceneFlightPath = active["path"]
	active["t"] = float(active["t"]) + dt
	if float(active["t"]) >= path.duration():
		_finish()
		return
	_place(dt)


## Draws each bird where its path has it at the flight's time: in the scene while all of it is
## inside, else in the transit window (placed on the leader, so it holds the whole party).
func _place(dt: float) -> void:
	var t := float(active["t"])
	var scale := scene.scale_px
	var scene_rect := Rect2(Vector2(scene.position), Vector2(scene.size))
	var lead_path: SceneFlightPath = active["path"]
	var lead_at := lead_path.at(t)
	var any_out := false
	var box := _bird_box()
	# The window sits on the leader; a bird is drawn there when any of it is past the scene's edge
	# and all of it is in the window, else in the scene (a companion still on a perch at the top
	# of the oak, its box over the edge, waits there).
	var window := Rect2(lead_at - _window_anchor() * scale, _transit_pt() * scale)
	for f in active["birds"]:
		var at := (f["path"] as SceneFlightPath).at(t)
		var cover := Rect2(at + box.position, box.size)
		var where := "desktop" if not scene_rect.encloses(cover) and (f == active["birds"][0] or window.grow(scale).encloses(cover)) else "scene"
		f["at"] = at
		f["where_now"] = where
		any_out = any_out or where == "desktop"
	if any_out:
		transit.place(lead_at, Vector2i(_window_anchor().round()))
	var tint := scene.light_tint()
	for f in active["birds"]:
		var where := String(f["where_now"])
		if where != String(f["where"]):
			_rehost(f, where)
		var look: SceneCreatureLook = f["look"]
		var at: Vector2 = f["at"]
		if where == "scene":
			look.position = scene.unshown((at - Vector2(scene.position)) / scale)
		else:
			look.position = (at - Vector2(transit.position)) / transit.scale_px
		var path: SceneFlightPath = f["path"]
		var v := path.velocity_at(t)
		if absf(v.x) > absf(v.y) * 0.25 and absf(v.x) > 1.0:
			f["facing"] = signf(v.x)
		var s := float(f["s"])
		# The facing is the screen's; drawn in a mirrored scene (issue 422) it is the other way in the world.
		look.scale = Vector2(s * float(f["facing"]) * (scene.shown_sign() if where == "scene" else 1.0), s)
		look.px = 1.0 / maxf(s, 0.01)
		look.view_hint = "side"
		var mode := path.mode_at(t)
		match mode:
			SceneFlightPath.TAKEOFF:
				look.play("takeoff")
				look.wings = 1.0
			SceneFlightPath.FLAP:
				look.play(_beat(f, dt))
				look.wings = 1.0
			SceneFlightPath.HOVER:
				look.play("hover")
				look.wings = 1.0
			_:
				# A hawk on a thermal banks round its circle and soars out of it.
				look.play("bank" if bool(f.get("banks", false)) and _turning(path, t) > 0.22 else "glide")
				look.wings = 0.35
		var lag := float(f.get("phase", 0.0))
		if lag > 0.0:
			f["phase"] = 0.0
		look.advance(dt + lag, v.length() * dt / maxf(s * scale, 0.01))
		var c := tint.lerp(Color.WHITE, float(data["desktop_tint"])) if where == "desktop" else tint
		look.modulate = Color(c.r, c.g, c.b, 1.0)
	active["where"] = "desktop" if any_out else "scene"
	_transit_drawing(any_out)


## The wingbeat to play: `fly`, or now and then `honk` for a goose (its frames beat with fly's).
func _beat(f: Dictionary, dt: float) -> String:
	var chance := float(f.get("honk", 0.0))
	if chance <= 0.0:
		return "fly"
	f["honk_left"] = float(f["honk_left"]) - dt
	if float(f["honk_left"]) <= 0.0:
		f["honking"] = rng.randf() < chance
		f["honk_left"] = rng.randf_range(0.7, 2.2)
	return "honk" if bool(f.get("honking", false)) else "fly"


## How fast the line turns at `t` (radians a second).
func _turning(path: SceneFlightPath, t: float) -> float:
	var a := path.velocity_at(maxf(0.0, t - 0.25))
	var b := path.velocity_at(t + 0.25)
	if a.length() < 1.0 or b.length() < 1.0:
		return 0.0
	return absf(wrapf(b.angle() - a.angle(), -PI, PI)) / 0.5


## Moves a bird's drawing between the scene's front band and the transit window.
func _rehost(f: Dictionary, where: String) -> void:
	var look: SceneCreatureLook = f["look"]
	if look.get_parent() != null:
		look.get_parent().remove_child(look)
	if where == "scene":
		scene.actor_layer(scene.kit.band_ids()[-1]).add_child(look)
	else:
		transit.host().add_child(look)
	f["where"] = where


var _drawing := false


## The transit window draws every frame only while a bird is in it; emptied, it draws once more
## (clear) and goes back to drawing on demand.
func _transit_drawing(on: bool) -> void:
	if transit == null or on == _drawing:
		return
	_drawing = on
	transit.set_live(on)


func _finish() -> void:
	var flight := active
	active = {}
	var t := (flight["path"] as SceneFlightPath).duration()
	for f in flight["birds"]:
		var path: SceneFlightPath = f["path"]
		if path.ends == "home" and path.complete and f["flock"] != null:
			_hand_back(f, path.at(t), path.velocity_at(t))
		else:
			_vanish(f)
	_transit_drawing(false)
	if flight["crosser"] != "":
		scene.behaviour.note("desktop flight: %s gone" % flight["crosser"], String(flight["crosser"]))


## Back in the scene: the bird joins its party again and comes down where its kind settles.
func _hand_back(f: Dictionary, at: Vector2, v: Vector2) -> void:
	var flock: SceneFlock = f["flock"]
	var b: Dictionary = f["bird"]
	var look: SceneCreatureLook = f["look"]
	var flip := scene.shown_sign()
	b["facing"] = float(f["facing"]) * flip
	flock.rejoin(b, scene.unshown((at - Vector2(scene.position)) / scene.scale_px), Vector2(v.x * flip, v.y) / scene.scale_px, float(f["s"]), f["land"])
	look.scale = Vector2(float(f["s"]) * float(b["facing"]), float(f["s"]))
	scene.behaviour.note("desktop flight: back in the scene", flock.sp.id)


## Off the screen (or cut short): the bird is gone.
func _vanish(f: Dictionary) -> void:
	var look: SceneCreatureLook = f["look"]
	if is_instance_valid(look):
		if look.get_parent() != null:
			look.get_parent().remove_child(look)
		look.queue_free()
	scene.behaviour.note("desktop flight: gone", String(data["species"]))


## Stops a flight now: a bird on the desktop goes, one still in the scene rejoins its party.
func abort() -> void:
	if active.is_empty():
		return
	var flight := active
	active = {}
	var t := float(flight["t"])
	for f in flight["birds"]:
		var path: SceneFlightPath = f["path"]
		if String(f["where"]) == "scene" and f["flock"] != null:
			_hand_back(f, path.at(t), path.velocity_at(t))
		else:
			_vanish(f)
	_transit_drawing(false)


## A crosser due now instead of a songbird, by its chance, if its sheet exists and it is its
## season and hour; else "".
func _due_crosser() -> String:
	for id in data.get("crossers", {}):
		if String(id) == "about":
			continue
		var spec: Dictionary = data["crossers"][id]
		var months: Array = spec.get("months", [])
		if not months.is_empty() and not scene.behaviour.month() in months.map(func(x) -> int: return int(x)):
			continue
		var minutes: Array = spec.get("minutes", [])
		if not minutes.is_empty() and (scene.env.minute < float(minutes[0]) or scene.env.minute > float(minutes[1])):
			continue
		if not SceneSheet.exists(String(spec["sheet"])):
			continue
		if rng.randf() < float(spec.get("chance", 0.0)):
			return String(id)
	return ""


## Points per metre the bird is drawn at, as its party draws it on `perch`.
func _points_per_m(flock: SceneFlock, perch: Dictionary) -> float:
	var s := flock._ppm(perch)
	return s * flock.sp.show_scale(String(perch.get("band", "mid")), s * scene.density)


## What one bird covers around its feet (screen units).
func _bird_box() -> Rect2:
	var scale := scene.scale_px
	return Rect2(-_anchor_pt() * scale, _bird_pt() * scale)


## How far a companion may be from the leader (screen units) and still be in the window.
func _group_half() -> Vector2:
	return (_window_pt() - _bird_pt()) * 0.5 * scene.scale_px


## The leader's feet in the window: its bird box centred in the window.
func _window_anchor() -> Vector2:
	return _anchor_pt() + (_transit_pt() - _bird_pt()) * 0.5


## The transit window's size: big enough for a party, and for a V of geese once their art is in.
func _transit_pt() -> Vector2:
	if _transit_size != Vector2.ZERO:
		return _transit_size
	var size := _window_pt()
	for id in data.get("crossers", {}):
		if String(id) != "about" and data.has("crosser_window_pt") and SceneSheet.exists(String(data["crossers"][id]["sheet"])):
			size = size.max(Vector2(float(data["crosser_window_pt"][0]), float(data["crosser_window_pt"][1])))
	_transit_size = size
	return size


func _window_pt() -> Vector2:
	return Vector2(float(data["window_pt"][0]), float(data["window_pt"][1]))


func _bird_pt() -> Vector2:
	var b: Array = data.get("bird_pt", data["window_pt"])
	return Vector2(float(b[0]), float(b[1]))


func _anchor_pt() -> Vector2:
	return Vector2(float(data["anchor_pt"][0]), float(data["anchor_pt"][1]))


## The desktop's top plus bottom while the scene holds a top corner (issue 424), else 0: flights are planned
## about that axis upside down, as if from a bottom corner, then turned the right way up (`_unflip`).
func _flip_axis() -> float:
	if not scene.on_top():
		return 0.0
	var d := _desktop()
	return d.position.y + d.end.y


func _unflip(paths: Array, axis: float) -> void:
	if axis == 0.0:
		return
	var done := {}
	for path: SceneFlightPath in paths:
		if not done.has(path.get_instance_id()):
			done[path.get_instance_id()] = true
			path.flip_y(axis)


func _desktop() -> Rect2:
	var r: Rect2
	if desktop_rect.is_valid():
		r = desktop_rect.call()
	else:
		var screen := DisplayServer.window_get_current_screen(scene.get_window_id()) if scene.is_inside_tree() else DisplayServer.SCREEN_OF_MAIN_WINDOW
		r = Rect2(DisplayServer.screen_get_usable_rect(screen))
	if r.size.x <= 0 or r.size.y <= 0:
		return Rect2(Vector2(scene.position) - Vector2(scene.size) * 0.4, Vector2(scene.size) * 1.4)
	return r


## The transit window, made once and left open and empty: click-through, never focusable.
func _make_window() -> void:
	if transit != null or not is_inside_tree():
		return
	transit = TransitWindow.new()
	transit.setup(Vector2i(_transit_pt().round()), scene.scale_px, scene.render_scale)
	transit.position = scene.position
	get_tree().root.add_child(transit)
	windows_made += 1
	WindowChrome.draw_on_demand(transit)


func debug_actions() -> Array:
	var out: Array = []
	for shape in SceneFlightPath.SHAPES:
		out.append(["Desktop flight: out and back, " + shape, func() -> void:
			next = {"shape": shape}
			start("out_back")])
	out.append(["Desktop flight: a pair chasing", func() -> void:
		next = {"company": "pair"}
		start("out_back")])
	out.append(["Desktop flight: a few swirling", func() -> void:
		next = {"company": "swirl"}
		start("out_back")])
	for id in data.get("crossers", {}):
		if String(id) != "about":
			out.append(["Desktop crosser: " + String(id), func() -> void: start(String(id))])
	return out
