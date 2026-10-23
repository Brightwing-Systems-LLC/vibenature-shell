class_name SceneCreature
extends Node2D

## One animal in the living scene (Skypatch issue 104).
## It comes in its own way (a deer steps out of the treeline and stops to look, a heron comes in low
## and brakes, a turtle's head breaks the surface), then lives by its needs: each activity it picks
## (forage, drink, stalk, bask, climb, groom, rest, watch...) becomes a short run of beats, each beat
## one §7 action for a while, maybe moving somewhere. Its species' numbers decide how long, how far
## and how often, and chance decides the rest, so no two visits play the same.
##
## It keeps an eye on the others (`perceive`): what it fears inside its flight distance sends it off
## (and its alarm goes out to everyone in earshot), what it is wary of it stops to watch, what it
## scolds it scolds. It leaves when its needs are met or its time is up, or when the weather turns.

## Seconds a creature stays uneasy after an alarm: a second alarm inside it puts it to flight.
const UNEASY_SEC := 18.0

var beh: SceneBehaviour
var sp: SceneSpecies
var look := SceneCreatureLook.new()
var habitat := ""
var band := ""
## Feet (or, flying, the body) in scene points.
var pos := Vector2.ZERO
var facing := 1.0
## arriving, living, leaving, fleeing, gone
var state := "arriving"
var beats: Array = []
var beat: Dictionary = {}
var beat_t := 0.0
var needs := {}
var activity := ""
var stay := 60.0
var age := 0.0
var alpha := 1.0
var size_mult := 1.0
var leader: SceneCreature
var young := false
## Why it came ("moment": the hand-off's big moment; the heron then always glides in).
var why := ""
var uneasy := 0.0
var _alpha_target := 1.0
var _rng := RandomNumberGenerator.new()
## Points per metre while flying (on the ground it comes from the band).
var _fly_ppm := -1.0
var _watched := {}
var _spot: Dictionary = {}
var _route: Dictionary = {}
var _aloft := false
var _moved := 0.0
## Its velocity in m/s along the picture's directions (issue 318), so it speeds up, turns and brakes
## within its limits.
var _vel := Vector2.ZERO
## The share of its acceleration the steering plans with: a step's metres per point differ a little
## by direction where the ground runs into the depth, and the rest covers that.
const HEADROOM := 0.9
var _wake_left := 0.0
var _scold_until := 0.0
var _climb := ""
## A departure to plan when the beat in hand ends: "", "calm" or "hurry".
var _leave_next := ""
var _idle_turns := 0
## Fish: the next time it may ease away from something it gives room to.
var _room_until := 0.0
var _last_turn := -100.0
## A follower fish's place in its group (0: the first behind the leader).
var _slot := 0
## Where each follower holds around its leader, in body lengths and heights (back, up/down), so a
## group spreads out instead of stacking up on one spot.
const FISH_SLOTS := [Vector2(1.1, -1.0), Vector2(1.2, 1.1), Vector2(2.2, 0.1), Vector2(2.3, -2.0), Vector2(2.4, 2.1), Vector2(3.3, -0.9)]
## Fish: how far back in the cut-away it is (Skypatch issue 156),
## 0 at the front glass, 1 deep in the murk at the back. Further back is smaller (a crisp set: the
## sheet's `@back`, or the master at 1/2), hazier, dimmer and slower across the screen, and it draws
## behind the near weeds instead of in front of them.
var depth_z := 0.0
var _z_target := 0.0
## A follower's place in depth beside its leader's (a school is not a flat line).
var _z_off := 0.0
var _z_layer := ""
## Nose up (-) or down (+) in radians, for a dive played on the swim frames.
var _pitch := 0.0
## Seconds it has been in the grass behind the shore strip in a row, seen (issue 237: never long).
var hidden_for := 0.0
## What it runs from (points), while fleeing; null otherwise.
var _threat: Variant = null
## It came out of the grass (its followers do too).
var _from_grass := false
## The fade's length for the beat in hand (-1: the tuning's).
var _fade_sec := -1.0
## Which way it is seen from its heading, for a sheet with toward/away rows (issue 237); null otherwise.
var heading: SceneHeading
## The heron's next departure is away over the pond (a clip asked for it).
var _away_next := false
## Its own pace for this visit, a few percent either side of its kind's (issue 272): it walks, swims
## and beats its wings or tail that much faster or slower (gaits still play by the ground covered).
var pace := 1.0
## A natural group's member (issue 320, `SceneHerd`): the sheet chosen for it, its role ("lead", "doe",
## "buck", "trail", "fawn"), how far (metres) it keeps from whom it follows, a fawn's mother, and the
## whole group (itself included). Empty for an animal that comes on its own terms.
var want_sheet := ""
var herd_role := ""
var spacing_m := Vector2.ZERO
var mother: SceneCreature
var herd: Array = []
## A drink beat it held back to keep watch while another drank, and how long it has watched so far.
var _watched_sec := 0.0


func setup(owner: SceneBehaviour, species: SceneSpecies, where: String, lead: SceneCreature, is_young: bool, seed: int) -> bool:
	beh = owner
	sp = species
	habitat = where
	leader = lead
	young = is_young
	_rng.seed = seed
	name = sp.id
	var palette: Dictionary = sp.data.get("colors", {})
	if young:
		var y: Dictionary = sp.data.get("young", {})
		size_mult = float(y.get("scale", 0.6))
		palette = y.get("colors", palette)
	else:
		size_mult = _rng.randf_range(0.92, 1.08)
	var drawn := sp.pick_sheet(young, _rng) if want_sheet == "" else sp.sheet_option(want_sheet, young)
	look.setup(sp, palette, size_mult, seed, String(drawn.get("id", "")), drawn)
	look.density = beh.scene.density
	look.below_alpha = float(beh.tuning.get("below_surface_alpha", 0.0))
	if look.has_sheet():
		# The bench drew each animal at its size: no random resizing of a drawing.
		size_mult = 1.0
		if look.sheet.has_depth_rows():
			var views: Dictionary = beh.tuning.get("depth_views", {})
			heading = SceneHeading.new(views)
			look.sheet.view_fade_sec = float(views.get("view_fade_sec", 0.25))
			# Flying into the scene it steps down through the crisp sizes: each step dissolves.
			look.sheet.crossfade_sec = float(views.get("size_fade_sec", 0.5))
	add_child(look)
	# Its own pace and its own place in its first cycle (issue 272), from a generator of its own so
	# the rest of its visit plays as it would without them.
	var own := RandomNumberGenerator.new()
	own.seed = seed ^ 0x272
	var share := float(sp.data.get("variation", {}).get("pace", beh.tuning.get("variation", {}).get("pace", 0.06)))
	pace = SceneVariety.pace(own, share)
	if look.has_sheet():
		look.sheet.rate = pace
		look.sheet.start_phase = own.randf()
	for need in sp.data.get("needs", {}):
		var r: Array = sp.data["needs"][need]
		needs[need] = _rng.randf_range(float(r[0]), float(r[1]))
	var s := sp.range_of("stay_min", [2, 6])
	stay = _rng.randf_range(s.x, s.y) * 60.0
	if not _plan_arrival():
		return false
	if sp.body == "fish":
		_setup_depth()
	beh.scene.actor_layer(_z_layer if _z_layer != "" else band).add_child(self)
	_place()
	return true


## Side-on in the cut-away, how near the glass a fish is has nothing to do with its height: its
## depth, a group's together but spread a little, arriving out of the murk.
func _setup_depth() -> void:
	var d := _depth_tuning()
	if look.sheet != null:
		look.sheet.crossfade_sec = float(d["crossfade_sec"])
	var r := _depth_range()
	if leader != null:
		var spread := float(d["school_spread"])
		_z_off = _rng.randf_range(0.3, 1.0) * spread * (-1.0 if _rng.randf() < 0.5 else 1.0)
		depth_z = clampf(leader.depth_z + _z_off, 0.0, 1.0)
	else:
		var a: Array = sp.data.get("arrive_z", d["arrive_z"])
		depth_z = _rng.randf_range(float(a[0]), float(a[1]))
		_z_target = r.x if bool(sp.data.get("loom", false)) else _rng.randf_range(r.x, r.y)
	_z_target = depth_z if leader != null else _z_target
	_z_layer = _layer_for(depth_z, "")
	z_index = _z_index()


func _depth_tuning() -> Dictionary:
	return beh.tuning["fish"]["depth"]


## The depths this fish keeps to (front glass 0 .. back 1).
func _depth_range() -> Vector2:
	var r: Array = sp.data.get("depth", [0.0, 1.0])
	return Vector2(float(r[0]), float(r[1]))


## Drawn size as a share of its size at the glass.
func depth_size() -> float:
	if sp.body != "fish":
		return 1.0
	return lerpf(1.0, float(_depth_tuning()["back_size"]), depth_z)


## Which actor layer a fish at `z` draws in (`fish.depth.layers`: behind the near weeds when back,
## in front of them all near the glass), with a little hysteresis so it does not flick between two.
func _layer_for(z: float, now: String) -> String:
	var d := _depth_tuning()
	var h := float(d["layer_hysteresis"])
	var layers: Array = d["layers"]
	for i in layers.size():
		var spec: Dictionary = layers[i]
		if String(spec["layer"]) == now:
			var lo := float(layers[i - 1]["below"]) if i > 0 else -1.0
			if z >= lo - h and z < float(spec["below"]) + h:
				return now
	for spec in layers:
		if z < float(spec["below"]):
			return String(spec["layer"])
	return String(layers[-1]["layer"])


## Nearer the glass draws over further back, whatever the layer.
func _z_index() -> int:
	return int(round((1.0 - depth_z) * 200.0)) + 1


## A new depth to drift toward now and then (the leader's; a follower keeps beside it).
func _maybe_new_depth() -> void:
	if sp.body != "fish" or leader != null:
		return
	if _rng.randf() < float(_depth_tuning()["retarget_chance"]):
		var r := _depth_range()
		_z_target = _rng.randf_range(r.x, r.y)


func _step_depth(dt: float) -> void:
	var d := _depth_tuning()
	if leader != null and is_instance_valid(leader) and leader.state != "gone" and state != "leaving" and state != "fleeing":
		var r := _depth_range()
		_z_target = clampf(leader.depth_z + _z_off, minf(r.x, leader.depth_z), maxf(r.y, leader.depth_z))
	var rate := float(d["z_per_sec"]) * (float(d["leave_rate"]) if state == "leaving" or state == "fleeing" else 1.0)
	if beat.has("z_rate"):
		rate = float(beat["z_rate"])
	elif leader != null and is_instance_valid(leader) and leader.beat.has("z_rate"):
		# Its group goes with it into or out of the depth.
		rate = float(leader.beat["z_rate"]) * 1.1
	if bool(beat.get("dart", false)):
		rate *= 2.0
	depth_z = move_toward(depth_z, _z_target, rate * dt)
	var layer := _layer_for(depth_z, _z_layer)
	if layer != _z_layer:
		_z_layer = layer
		var host := beh.scene.actor_layer(layer)
		if get_parent() != null and get_parent() != host:
			get_parent().remove_child(self)
			host.add_child(self)
	z_index = _z_index()
	# A dive is the swim frames pitched nose-down along the way it goes (the sheets' dive frames
	# leave the body cut at the frame's edge underwater).
	var want := 0.0
	if String(beat.get("a", "")) == "dive" and beat.has("to"):
		var v: Vector2 = (beat["to"] as Vector2) - pos
		if v.length() > 0.5:
			want = clampf(atan2(v.y, absf(v.x)), -float(d["pitch_max"]), float(d["pitch_max"]))
	_pitch = move_toward(_pitch, want, dt * 1.6)


# --- Each frame ---------------------------------------------------------------------------------

func step(dt: float, tint: Color) -> void:
	age += dt
	uneasy = maxf(0.0, uneasy - dt)
	var guard := 0
	while (beat.is_empty() or _beat_done()) and state != "gone" and guard < 4:
		_next_beat()
		guard += 1
	if state == "gone":
		return
	beat_t += dt
	var before := pos
	var ppm_before := ppm()
	var z_before := depth_z
	_move(dt)
	_moved = pos.distance_to(before) / maxf(ppm() * _drawn(), 0.01)
	alpha = move_toward(alpha, _alpha_target, dt / (_fade_sec if _fade_sec > 0.0 else float(beh.tuning["fade_sec"])))
	hidden_for = hidden_for + dt if in_grass() and alpha > 0.05 else 0.0
	if sp.body == "fish":
		_step_depth(dt)
		# The drawn size follows the depth this frame, not the last.
		_place()
	if heading != null:
		_step_heading(dt, before, ppm_before, z_before)
	if sp.body != "fish" and look.has_sheet():
		# The climb row plays at the bark covered (issue 343): its feet still while it clings.
		var per := float(sp.data.get("dash", {}).get("climb_m_per_sec", 0.0))
		look.sheet.rate = clampf(_moved / maxf(dt, 0.0001) / per, 0.0, 3.0) * pace if _climb != "" and per > 0.0 and _drawn_climbing() else pace
	look.advance(dt, _moved)
	_place()
	modulate = Color(tint.r, tint.g, tint.b, alpha)
	if sp.body == "fish" and look.sheet != null:
		var d := _depth_tuning()
		var dim := lerpf(1.0, float(d["dim"]), depth_z)
		modulate = Color(tint.r * dim, tint.g * dim, tint.b * dim, alpha)
		var haze := Color(String(d["haze_color"]))
		look.sheet.haze = float(d["haze"]) * depth_z
		look.sheet.haze_color = Color(haze.r * tint.r, haze.g * tint.g, haze.b * tint.b)
	if band == "water" and _moved > 0.0 and look.under < 0.95 and not (sp.body == "fish" and (beat.has("tilt") or beat.has("leap_phase"))) and not (sp.body == "heron" and _fly_ppm > 0.0):
		_wake_left -= dt
		if _wake_left <= 0.0:
			_wake_left = 0.3
			beh.scene.wake(pos + Vector2(facing * sp.size().x * 0.4 * ppm(), 0), (pos - before) / maxf(dt, 0.001))


## Its way in metres (across, away) this step, and from it the view it is seen in: toward or away
## (through three-quarter) while it swims or flies mostly into or out of the scene, side-on otherwise
## (issue 237). Only for an action drawn in those views and not pitched (a dive, a leap): else side.
func _step_heading(dt: float, before: Vector2, ppm_before: float, z_before: float) -> void:
	look.sheet.face = facing
	var drawn := look.sheet.depth_row("3q_away").size() + look.sheet.depth_row("3q_toward").size() > 0
	if not drawn or beat.has("tilt") or absf(_pitch) > 0.05 or state == "gone":
		heading.reset()
		look.view_hint = "side"
		return
	if beat.has("at") and beat_t <= dt * 1.5:
		# Put somewhere new this step, not moved there.
		return
	if sp.body == "heron" and beat.has("approach") and String(beat["approach"]) != "far":
		# A glide-in across the picture stays side-on: its drawn size grows toward the landing, which
		# reads as coming nearer and flipped it head-on mid-glide (the human, 2026-10-20). Only the
		# approach out of the distance is seen from the front.
		heading.reset()
		look.view_hint = "side"
		return
	var way := Vector2.ZERO
	if sp.body == "fish":
		way = Vector2((pos.x - before.x) / maxf(ppm() * depth_size(), 0.01), (depth_z - z_before) * float(_depth_tuning()["span_m"]))
	else:
		way = beh.world(pos, ppm()) - beh.world(before, ppm_before)
	look.view_hint = heading.update(dt, way.x / maxf(dt, 0.0001), way.y / maxf(dt, 0.0001))


## How much larger than life it is drawn where it stands, for a heron (whose legs must match the
## ground it covers as drawn: a heron across the pond is shown as big as a near one); 1 for the rest.
func _drawn() -> float:
	if sp.body != "heron" or _fly_ppm > 0.0:
		return 1.0
	var p := ppm()
	return sp.show_scale(band, p * beh.scene.density)


## Stop and go (issue 343, species `dash`): a run or climb to `to` becomes what a gray squirrel does,
## short dashes and bounding hops with freezes between (a look, a sit-up, a tail flick), and on the
## trunk quick bursts with clinging pauses, up head first and down head first. Each leg's speed is
## from the field data and within its gait's limits; its gait plays at the ground it covers. A flight
## from danger, a fade out and a change of band or layer go in one go.
func _split_dash() -> void:
	var dash: Dictionary = sp.data["dash"]
	if not beat.has("to") or beat.has("path") or beat.has("band") or beat.has("then_band") or beat.has("layer") \
			or bool(beat.get("dashed", false)) or float(beat.get("fade", 1.0)) < 0.5 or state == "fleeing":
		return
	var a := String(beat.get("a", ""))
	var climb := String(beat.get("climb", ""))
	if climb == "" and not a in ["run", "walk", "trot"]:
		return
	var to: Vector2 = beat["to"]
	var dist := pos.distance_to(to) / maxf(ppm(), 0.001)
	if dist < 0.05:
		return
	var legs: Array = []
	var left := dist
	while left > 0.0:
		var hop := climb == "" and _rng.randf() < float(dash["hop_chance"])
		var key := ("climb_burst_m" if climb != "" else ("hop_m" if hop else "bound_m"))
		var r := Vector2(float(dash[key][0]), float(dash[key][1]))
		var leg := minf(left, _rng.randf_range(r.x, r.y))
		if left - leg < r.x * 0.5:
			leg = left
		left -= leg
		var b: Dictionary = beat.duplicate()
		b["to"] = to if left <= 0.0 else pos.lerp(to, 1.0 - left / dist)
		b["dashed"] = true
		b["speed"] = _r(dash, ("climb_up_mps" if climb == "up" else "climb_down_mps") if climb != "" else ("hop_mps" if hop else "dash_mps"), [1.0, 1.0])
		if climb == "":
			b["a"] = "run"
			b["gait"] = "run"
		if not legs.is_empty():
			b.erase("fx")
		legs.append(b)
		if left <= 0.0:
			break
		if climb != "":
			if _rng.randf() < float(dash["climb_pause_chance"]):
				legs.append({"a": "climb", "climb": climb, "sec": _r(dash, "climb_pause_sec", [0.3, 1.0]), "dashed": true})
		elif _rng.randf() < float(dash["freeze_chance"]) * (0.5 if hop else 1.0):
			var roll := _rng.randf()
			if roll < float(dash["sit_up_chance"]):
				legs.append({"a": "sit", "sec": _r(dash, "sit_up_sec", [0.6, 1.6])})
			elif roll < float(dash["sit_up_chance"]) + float(dash["flick_chance"]):
				legs.append({"a": "tail_flick", "sec": _r(dash, "flick_sec", [0.5, 0.9])})
			else:
				legs.append({"a": "look", "sec": _r(dash, "freeze_sec", [0.4, 1.6])})
	beat = legs[0]
	for i in range(legs.size() - 1, 0, -1):
		beats.push_front(legs[i])


## Whether its sheet has a climb row of its own (drawn head-up on the trunk), not a run turned upright.
func _drawn_climbing() -> bool:
	return look.has_sheet() and (look.sheet.anims.get("side", {}) as Dictionary).has("climb")


func ppm() -> float:
	if _fly_ppm > 0.0:
		return _fly_ppm
	return beh.ppm(band, pos.y)


func world() -> Vector2:
	return beh.world(pos, ppm())


func is_moving() -> bool:
	return _moved > 0.0005


func _place() -> void:
	position = pos
	if sp.body == "fish" and look.has_sheet() and not beat.has("tilt") and absf(_pitch) < 0.01:
		# A fish's sheet sits on whole art px, so its pixels never straddle two and shimmer.
		position = (pos * beh.scene.density).round() / beh.scene.density
	var p := ppm()
	scale = Vector2(p * facing, p)
	var show := (float(beat["show"]) if beat.has("show") else sp.show_scale(band, p * beh.scene.density)) * depth_size()
	if _aloft or _climb != "":
		show = beh.on_oak_show(p, band, pos.y)
	look.scale = Vector2(show, show)
	look.px = 1.0 / maxf(p * show, 0.01)
	look.at_surface = band == "water" and pos.y < beh.cut_y() - 0.5 and not beat.has("path")
	# A bass leaping out on the pond (issue 340) is cut at the surface row it breaks, like a near one.
	look.waterline_local = (float(beat["cut_at"]) - position.y) / maxf(p * show, 0.0001) if beat.has("cut_at") else INF
	if beat.has("tilt") and beat.has("path"):
		# A leap: the body follows its arc, nose up going out, nose down coming back in.
		var path: Array = beat["path"]
		var u := clampf(float(beat.get("u", 0.0)), 0.0, 1.0)
		var dv := _bezier(path[0], path[1], path[2], path[3], minf(1.0, u + 0.02)) - _bezier(path[0], path[1], path[2], path[3], maxf(0.0, u - 0.02))
		rotation = atan2(dv.y * facing, dv.x * facing) if dv.length() > 0.001 else 0.0
	elif beat.has("bank") and beat.has("line"):
		# A glide tips nose-down as it descends and more through the sweep's turn.
		rotation = SceneHeron.bank_at(beat["line"], float(beat.get("e", 0.0)), float(beat["bank"])) * facing
	elif _climb != "" and _drawn_climbing():
		# The sheet's climb row is drawn head-up on a vertical trunk (issue 343): up as drawn, and
		# down head first, the same drawing turned over.
		rotation = 0.0 if _climb == "up" else PI
	elif _climb == "up":
		rotation = -PI * 0.5 * facing
	elif _climb == "down":
		rotation = PI * 0.5 * facing
	else:
		rotation = _pitch * facing


func _beat_done() -> bool:
	if beat.has("path"):
		return float(beat.get("u", 0.0)) >= 1.0
	if beat.has("to"):
		return pos.distance_to(beat["to"]) < 0.05 or beat_t > float(beat.get("max_sec", 60.0))
	return beat_t >= float(beat.get("sec", 1.0))


func _next_beat() -> void:
	if not beat.is_empty() and beat.has("then_band"):
		_set_band(String(beat["then_band"]))
	if sp.body == "fish" and beat.has("tilt"):
		# Back in from a leap nose-down: the dive carries on from that angle.
		_pitch = clampf(rotation * facing, -float(_depth_tuning()["pitch_max"]), float(_depth_tuning()["pitch_max"]))
	if bool(beat.get("flip", false)):
		# The turn's last frame faces the other way: the sprite flips under it.
		facing = -facing
	if beats.is_empty():
		_plan()
		if beats.is_empty():
			state = "gone"
			return
	beat = beats.pop_front()
	if sp.data.has("dash"):
		_split_dash()
	beat_t = 0.0
	if beat.has("path"):
		_fit_path()
	if beat.has("at") or beat.has("path"):
		_vel = Vector2.ZERO
	if String(beat.get("a", "")) == "drink" and not herd.is_empty():
		var watch := _watch_for()
		if watch > 0.0:
			beats.push_front(beat)
			beat = {"a": "look", "sec": watch, "watch": true}
			_watched_sec += watch
		else:
			_watched_sec = 0.0
	if beat.has("at"):
		pos = beat["at"]
	if beat.has("alpha"):
		alpha = float(beat["alpha"])
		_alpha_target = alpha
	_fade_sec = float(beat.get("fade_sec", -1.0))
	if beat.has("layer"):
		_set_layer(String(beat["layer"]))
	if turns() and heading != null and SceneHeading.is_straight(heading.view):
		# Nose-on or tail-on already: it heads off the new way with no side-on turn (the drawing
		# keeps its mirror until it is seen side-on again).
		var want := _wants_facing(beat)
		if want != 0.0:
			facing = want
	elif turns():
		var want := _wants_facing(beat)
		if want != 0.0 and want != facing:
			beats.push_front(beat)
			var wait := _last_turn + float(beh.tuning["fish"]["turn_gap_sec"]) - beh.t
			if wait > 0.0 and not beat.has("turn_sec"):
				# Just turned: it hangs a moment before turning again, rather than dithering.
				beat = {"a": "swim", "sec": minf(wait, 1.5), "rate": 0.5}
			else:
				_last_turn = beh.t
				beat = {"a": "turn", "sec": float(beat.get("turn_sec", _turn_sec())), "flip": true}
	if sp.body == "fish" and look.sheet != null:
		# The tail beats with the speed: lazy when it hangs in the water, fast in a dart.
		var r := 0.45
		if beat.has("rate"):
			r = float(beat["rate"])
		elif beat.has("speed"):
			r = clampf(float(beat["speed"]) / maxf(0.01, sp.speed("swim")), 0.6, 2.5)
		elif beat.has("to") or beat.has("path") or String(beat.get("a", "")) != "swim":
			r = 1.0
		look.sheet.rate = r * pace
	if beat.has("band"):
		_set_band(String(beat["band"]))
	if beat.has("fade"):
		_alpha_target = float(beat["fade"])
	if beat.has("face"):
		facing = float(beat["face"])
	if beat.has("pitch"):
		# Carries on from a drawn pitch (out of the bass leap's entry, nose-down, issue 299).
		_pitch = float(beat["pitch"])
	if beat.has("face_to"):
		var dx: float = (beat["face_to"] as Vector2).x - pos.x
		# A fish that turns through its sheet has turned already if it needed to; never a flip.
		if absf(dx) > 0.5 and not turns():
			facing = signf(dx)
	if beat.has("gait"):
		look.gait_kind = String(beat["gait"])
	if beat.has("aloft"):
		_aloft = bool(beat["aloft"])
	_climb = String(beat.get("climb", ""))
	if beat.has("fly_ppm"):
		_fly_ppm = float(beat["fly_ppm"])
	elif not beat.has("path"):
		_fly_ppm = -1.0
	var act := String(beat.get("a", "idle"))
	if sp.body == "fish" and act == "dive":
		act = "swim"
	if _climb != "" and _drawn_climbing():
		# On the trunk every beat is the clinging drawing, held still between bursts (a sit or a tail
		# flick there is not drawn yet: requested from the bench, issue 343).
		act = "climb"
	var length := float(beat["anim_sec"]) if beat.has("anim_sec") else (-1.0 if beat.has("to") or beat.has("path") else float(beat.get("sec", 1.0)))
	look.play(act, length, int(beat.get("from", 0)), bool(beat.get("backwards", false)))
	if bool(beat.get("leave", false)):
		_leave_next = "calm"
	if beat.has("wade"):
		look.wade = float(beat["wade"])
	look.set_swallowing(String(beat.get("fx", "")) == "swallow")
	_fx(String(beat.get("fx", "")))


static func _ease(b: Dictionary, u: float) -> float:
	match String(b.get("ease", "")):
		"out":
			return 1.0 - pow(1.0 - u, 2.2)
		"in":
			return pow(u, 1.8)
		"glide":
			# Steady across, easing to about 60% as it brakes in.
			return u + 0.4 * u * u * (1.0 - u)
	return u


## Where a path beat is at eased share `e`, and its scale there: [point, points per metre].
static func _path_point(b: Dictionary, e: float) -> Array:
	if b.has("pts"):
		# Sampled evenly in the world, each point with its own scale (a flight into the scene).
		var pts: PackedVector2Array = b["pts"]
		var scales: PackedFloat32Array = b["ppms"]
		var f := e * float(pts.size() - 1)
		var i := mini(int(f), pts.size() - 2)
		return [pts[i].lerp(pts[i + 1], f - float(i)), lerpf(scales[i], scales[i + 1], f - float(i))]
	var path: Array = b["path"]
	var ppms: Array = b["ppm"]
	var p: Vector2 = SceneHeron.along(b["line"], e) if b.has("line") else _bezier(path[0], path[1], path[2], path[3], e)
	return [p, lerpf(float(ppms[0]), float(ppms[1]), e)]


## A path beat that would need more than the species' top speed anywhere along it (in metres, depth
## included) takes longer instead (issue 318): slowed, never squeezed. A leap keeps its drawn rows.
func _fit_path() -> void:
	var top := sp.top_speed()
	# A leap's rows last exactly their drawn length, except the rise from where the bass is: from deep
	# in the cut-away that was 2.5 m in about a second, 3.2 m/s against its 3.0 (issue 384's sweep).
	if top == INF or (beat.has("leap_phase") and String(beat["leap_phase"]) != "leap_rise"):
		return
	var dur := maxf(0.1, float(beat["dur"]))
	var n := 48
	var peak := 0.0
	var end_v := 0.0
	var last := Vector3.ZERO
	for i in n + 1:
		var u := float(i) / float(n)
		var at := _path_point(beat, _ease(beat, u))
		var m := SceneSpeedMeter.metres_at(beh, self, at[0], at[1])
		if i > 0:
			end_v = m.distance_to(last) / (dur / float(n))
			peak = maxf(peak, end_v)
		last = m
	var f := peak / top if peak > top else 1.0
	# A glide that ends on its feet (the heron's landing, issue 356's scene-suite find): it touches
	# down and stops within `land_brake_sec`, so it comes in no faster than its acceleration can stop
	# in that time; a faster line on some seed is slowed, not let through.
	if String(beat.get("ease", "")) == "glide":
		var brake := float(sp.data.get("glide", {}).get("land_brake_sec", 0.0))
		var cap := sp.accel_limit() * brake
		if brake > 0.0 and cap < INF and end_v > cap:
			f = maxf(f, end_v / cap)
	if f > 1.0:
		beat["dur"] = dur * f
		if beat.has("leap_phase"):
			beat["anim_sec"] = float(beat["anim_sec"]) * f


## Metres per point of a step from where it is toward `dir` (a unit vector), depth included.
func _m_per_pt(dir: Vector2) -> float:
	var here := SceneSpeedMeter.metres(beh, self)
	var keep := pos
	pos = pos + dir
	var there := SceneSpeedMeter.metres(beh, self)
	pos = keep
	return here.distance_to(there)


## Its step toward `d` (points) this frame, wanting `want` points a second, held to its real limits
## (issue 318): never past the gait's top (or, for a beat that sets its own speed, the species' top);
## its velocity (`_vel`, m/s) changes by at most its acceleration, so it speeds up, turns and brakes
## to a stop at `to` as it could. Without limits in its data it steps straight there.
func _limited_step(want: float, d: Vector2, dt: float) -> Vector2:
	var dir := d.normalized()
	var mpp := _m_per_pt(dir)
	var a := sp.accel_limit() * HEADROOM
	if mpp <= 0.000001 or a == INF:
		return dir * minf(d.length(), want * dt)
	var top := sp.top_speed() if beat.has("speed") else sp.gait_limit(String(beat.get("gait", beat.get("a", "walk")))).y
	# Braking is planned at half its acceleration, so a step at a time it still stops on the spot.
	var want_m := minf(minf(want * mpp, top), sqrt(a * d.length() * mpp))
	_vel += (dir * want_m - _vel).limit_length(a * dt)
	var step := _vel / mpp * dt
	if step.length() >= d.length() - 0.001 and step.dot(d) > 0.0:
		_vel = Vector2.ZERO
		return d
	return step


## Not on its way anywhere this beat but still moving (a walk or a run cut short): it brakes to a
## stop within its acceleration instead of stopping dead (issue 318).
func _coast(dt: float) -> void:
	var a := sp.accel_limit() * HEADROOM
	if _vel == Vector2.ZERO or a == INF:
		_vel = Vector2.ZERO
		return
	var mpp := _m_per_pt(_vel.normalized())
	_vel = _vel.move_toward(Vector2.ZERO, a * dt)
	if mpp > 0.000001:
		pos += _vel / mpp * dt


func _move(dt: float) -> void:
	if beat.has("path"):
		var u := minf(1.0, float(beat.get("u", 0.0)) + dt / maxf(0.1, float(beat["dur"])))
		beat["u"] = u
		var e := _ease(beat, u)
		beat["e"] = e
		var at := _path_point(beat, e)
		var p: Vector2 = at[0]
		_fly_ppm = float(at[1])
		if absf(p.x - pos.x) > 0.01 and not beat.has("face"):
			facing = signf(p.x - pos.x)
		pos = p
		if beat.has("fade_at") and u >= float(beat["fade_at"]) and _alpha_target > 0.0:
			# Gone into the far treeline: it fades over the rest of the way.
			_alpha_target = 0.0
			_fade_sec = maxf(0.3, (1.0 - u) * float(beat["dur"]))
		for act in beat.get("acts", []):
			if u >= float(act[0]) and look.action != String(act[1]) and float(act[0]) >= float(beat.get("act_at", -1.0)):
				beat["act_at"] = float(act[0])
				look.play(String(act[1]), float(act[2]) if (act as Array).size() > 2 else -1.0)
		return
	if not beat.has("to"):
		_coast(dt)
		return
	var to: Vector2 = beat["to"]
	var speed := float(beat.get("speed", sp.speed(String(beat.get("gait", "walk"))))) * ppm() * depth_size() * _drawn() * pace
	var d := to - pos
	if d.length() <= 0.001:
		_vel = Vector2.ZERO
		return
	var step := _limited_step(speed, d, dt)
	if beat.has("bend") and _arc(dt, to, step.length() / maxf(dt, 0.0001)):
		return
	pos += step
	if absf(d.x) > 0.02 and not beat.has("face") and _climb == "" and not turns():
		facing = signf(d.x)


## A swim to `to` along a gentle arc (issue 272): the beat's `bend` is how far its middle bows off the
## straight line, as a share of the line's length, across it; steady along the arc at `speed`. Set up
## on the first step from where it is; false (go straight) when the bow would leave the water.
func _arc(dt: float, to: Vector2, speed: float) -> bool:
	if not beat.has("arc_from"):
		var from := pos
		var line := to - from
		var via := from.lerp(to, 0.5) + line.orthogonal() * float(beat["bend"])
		# Only across the picture: a steep line bowed sideways would double back on itself.
		if line.length() < 4.0 or absf(line.x) < 2.0 * absf(line.y) or not beh.in_swim(via, _half()):
			beat.erase("bend")
			return false
		beat["arc_from"] = from
		beat["arc_via"] = via
		beat["arc_len"] = from.distance_to(via) * 0.5 + via.distance_to(to) * 0.5 + from.distance_to(to) * 0.5
		beat["arc_s"] = 0.0
	var s := float(beat["arc_s"]) + speed * dt
	beat["arc_s"] = s
	var u := clampf(s / maxf(float(beat["arc_len"]), 0.01), 0.0, 1.0)
	var a: Vector2 = beat["arc_from"]
	var v: Vector2 = beat["arc_via"]
	var q := a * (1.0 - u) * (1.0 - u) + v * 2.0 * u * (1.0 - u) + to * u * u
	if absf(q.x - pos.x) > 0.02 and not beat.has("face") and not turns():
		facing = signf(q.x - pos.x)
	pos = q
	return true


static func _bezier(a: Vector2, b: Vector2, c: Vector2, d: Vector2, t: float) -> Vector2:
	var u := 1.0 - t
	return a * u * u * u + b * 3.0 * u * u * t + c * 3.0 * u * t * t + d * t * t * t


## Drawn in actor layer `layer` of its band from now (the grass behind the strip, or the band's own).
func _set_layer(layer: String) -> void:
	_z_layer = layer if layer != band else ""
	var host := beh.scene.actor_layer(layer)
	if get_parent() != null and get_parent() != host:
		get_parent().remove_child(self)
		host.add_child(self)


## In the grass behind the shore strip (drawn behind the reeds).
func in_grass() -> bool:
	return _z_layer != "" and _z_layer == String(beh.tuning["grass"]["layer"])


func _set_band(b: String) -> void:
	if b == band or b == "":
		return
	band = b
	var layer := beh.scene.actor_layer(b)
	if get_parent() != null and get_parent() != layer:
		get_parent().remove_child(self)
		layer.add_child(self)


func _fx(what: String) -> void:
	_sound(what)
	match what:
		"":
			pass
		"ring":
			beh.scene.ring(pos, clampf(0.2 + ppm() / 200.0, 0.2, 0.8), 0.7)
		"splash":
			beh.scene.splash(pos, clampf(0.5 + ppm() / 160.0, 0.5, 1.3))
			beh.scene.ring(pos, clampf(0.4 + ppm() / 120.0, 0.4, 1.2), 1.0)
			beh.scene.ring(pos + Vector2(facing * 0.3 * ppm(), 0), clampf(0.3 + ppm() / 150.0, 0.3, 1.0), 0.8)
		"strike":
			# The bill goes in at its tip: a splash and rings on the surface there.
			var tip := _on_surface(_bill("bill_tip_px", Vector2(196, 192)))
			beh.scene.splash(tip, 0.55)
			beh.scene.ring(tip, 0.75, 1.0)
			beh.note("heron strikes", sp.id)
		"lift":
			var tip := _on_surface(_bill("bill_tip_px", Vector2(196, 192)))
			beh.scene.splash(tip, 0.35)
			beh.scene.ring(tip + Vector2(facing * 1.0, 0.0), 0.5, 0.8)
			beh.note("heron catches a %s" % String(beat.get("prey", "fish")), sp.id)
		"miss":
			beh.scene.ring(_on_surface(_bill("bill_tip_px", Vector2(196, 192))), 0.45, 0.7)
			beh.note("heron misses", sp.id)
		"drip":
			var beak: Array = SceneHeron.hunt_data(self).get("beak_px", {}).get(String(beat.get("prey", "fish")), [158, 86])
			beh.scene.ring(_on_surface(_bill("", Vector2(float(beak[0]), float(beak[1])))), 0.2, 0.6)
		"lift_off":
			# The feet leave the water where they stood (the beat has already lifted the waterline).
			var feet := Vector2(pos.x, pos.y - SceneHeron.wade_m(beh) * ppm() * _drawn())
			beh.scene.splash(feet, clampf(0.5 + ppm() / 160.0, 0.5, 1.2))
			beh.scene.ring(feet, clampf(0.4 + ppm() / 120.0, 0.4, 1.1), 0.9)
			beh.note("heron takes off", sp.id)
		"preen", "shake", "freeze":
			beh.note("heron %s" % String(beat.get("a", what)), sp.id)
		"plop":
			beh.scene.splash(pos, 0.6)
			beh.scene.ring(pos, clampf(0.4 + ppm() / 140.0, 0.4, 1.1), 1.0)
			beh.alarm(self, pos, ppm(), float(sp.data.get("alarm", {}).get("radius_m", 0.0)), "%s plops in" % sp.id)
		"alarm":
			beh.alarm(self, pos, ppm(), float(sp.data.get("alarm", {}).get("radius_m", 0.0)), "%s alarm" % sp.id)
		"chatter":
			beh.alarm(self, pos, ppm(), float(sp.data.get("alarm", {}).get("radius_m", 0.0)), "%s scolds" % sp.id, "call")
		"pounce":
			beh.note("%s pounces" % sp.id, sp.id)
		"rise":
			# On the surface over the fish: at the glass for one near it, out on the pond for one
			# further back (issue 237), the ring and the snap as small as the water there.
			var s := surface()
			var k := float(s["scale"])
			beh.scene.ring(s["at"], 0.7, 0.9, k)
			beh.scene.splash((s["at"] as Vector2) + Vector2(facing * 3.0 * k, 0.0), 0.3, k)
			beh.note("a fish rises", sp.id)
		"break":
			var s := surface()
			beh.scene.splash(s["at"], float(sp.data.get("splash", 0.7)), float(s["scale"]))
			beh.scene.ring(s["at"], 0.9, 1.0, float(s["scale"]))
		"leap":
			var s := surface()
			beh.scene.splash(s["at"], float(sp.data.get("splash", 0.7)), float(s["scale"]))
			beh.note("a fish leaps", sp.id)
		"swallow":
			if sp.body == "heron":
				beh.note("heron swallows the %s" % String(beat.get("prey", "fish")), sp.id)
			else:
				beh.note("%s catches a fish" % sp.id, sp.id)
		"rush":
			beh.note("%s rushes the sunfish" % sp.id, sp.id)


## The typed scene event a beat's effect makes, for the sound engine (issue 413; the shell bodies' standard
## kinds, proposal 2026-10-21-sound-in-packages §6): a fish's rise, leap and fall back in at the surface over
## it; the heron's step into the water, landing, strike and take-off; a turtle sliding in; an alarm. Rings
## and the heron's dripping bill make no sound.
func _sound(what: String) -> void:
	var length := sp.size().x
	match what:
		"rise", "leap", "break":
			if sp.body != "fish":
				return
			var at: Vector2 = surface()["at"]
			var kind: String = {"rise": "fish_rise", "leap": "fish_jump", "break": "fish_reentry"}[what]
			beh.sound_event(kind, self, {"pos": at, "band": "water", "size": length * depth_size(),
					"depth_m": beh.depth_of(beh.ppm("water", at.y))})
		"splash":
			beh.sound_event("land", self, {"size": length})
		"step":
			beh.sound_event("wade_step", self, {"pos": _on_surface(pos), "size": length})
		"strike":
			beh.sound_event("strike", self, {"pos": _on_surface(_bill("bill_tip_px", Vector2(196, 192))), "size": length})
		"lift_off":
			beh.sound_event("takeoff", self, {"size": length})
		"plop":
			beh.sound_event("turtle_slide" if sp.body == "turtle" else "splash_in", self, {"size": length})
		"alarm", "chatter":
			beh.sound_event("alarm", self, {"size": length})


## Where it breaks the surface, {at, scale}: the surface row over it for its depth (a fish further
## back, further out on the pond), the water's scale there against the glass's.
func surface() -> Dictionary:
	return beh.surface_at(pos.x, depth_size())


## Where the sheet's pixel `px` (or the hunt data's `key`) is drawn, in points (facing applied).
func _bill(key: String, px: Vector2) -> Vector2:
	if key != "":
		var raw: Array = SceneHeron.hunt_data(self).get(key, [px.x, px.y])
		px = Vector2(float(raw[0]), float(raw[1]))
	var off := SceneHeron._px_m(self, px) * ppm() * _drawn()
	if look.sheet != null and look.sheet.art_per_master_px > 0.0:
		off = look.sheet.art_offset(px) / beh.scene.density
	return pos + Vector2(off.x * facing, off.y)


## `at` brought to the water's surface at this bird's depth (its waterline, where the legs go in).
func _on_surface(at: Vector2) -> Vector2:
	return Vector2(at.x, pos.y - look.wade * ppm() * _drawn())


# --- Planning -----------------------------------------------------------------------------------

func _plan() -> void:
	if _leave_next != "":
		var hurry := _leave_next == "hurry"
		_leave_next = ""
		_leave(hurry)
		return
	if state == "leaving" or state == "fleeing":
		return
	if state == "arriving":
		state = "living"
	if leader != null and is_instance_valid(leader) and leader.state != "gone":
		if leader.state == "leaving" or leader.state == "fleeing":
			_leave(leader.state == "fleeing")
			return
		_follow()
		return
	if _should_leave():
		_leave(false)
		return
	var a := _choose()
	if a.is_empty():
		_leave(false)
		return
	activity = String(a["do"])
	beh.note("%s: %s" % [sp.id, activity], sp.id)
	var need := String(a.get("need", ""))
	# Nothing left it needs here: after a few idle turns it moves on.
	_idle_turns = _idle_turns + 1 if need == "" or float(needs.get(need, 0.0)) < 0.2 else 0
	if need != "" and needs.has(need):
		needs[need] = maxf(0.0, float(needs[need]) - _rng.randf_range(0.3, 0.6))
	call("_do_" + activity, a)
	if beats.is_empty() and sp.body == "fish":
		# Nowhere to go this time: it hangs a moment rather than vanishing.
		push_warning("VibeNature: %s found nowhere to %s" % [sp.id, activity])
		beats.append({"a": "swim", "sec": _rng.randf_range(1.0, 2.5), "rate": 0.5})


func _should_leave() -> bool:
	if age > stay or _idle_turns >= int(sp.data.get("restless_after", 3)):
		return true
	var w := beh.weather()
	var m: Dictionary = sp.data.get("weather", {})
	if float(w["rain"]) > 0.5 and float(m.get("rain", 1.0)) < 0.5 and _rng.randf() < 0.6:
		return true
	if float(w["sunshine"]) < float(m.get("needs_sun", 0.0)) * 0.8:
		return true
	if not needs.is_empty() and age > stay * 0.5:
		var any := false
		for n in needs:
			if float(needs[n]) > 0.15:
				any = true
		return not any
	return false


func _choose() -> Dictionary:
	var scores := {}
	var total := 0.0
	var options := sp.activities()
	for i in options.size():
		var a: Dictionary = options[i]
		var need := String(a.get("need", ""))
		var s := float(a.get("weight", 1.0)) * (float(needs.get(need, 0.0)) if need != "" else 0.35)
		if String(a["do"]) == activity:
			s *= 0.35
		if String(a["do"]) == "rest" and stay - age < 90.0:
			s *= 0.05
		if String(a["do"]) == "climb" and _aloft:
			s = 0.0
		if not has_method("_do_" + String(a["do"])):
			s = 0.0
		s *= _rng.randf_range(0.6, 1.4)
		if s > 0.0:
			scores[i] = s
			total += s
	if total <= 0.0:
		return {}
	var roll := _rng.randf() * total
	for i in scores:
		roll -= float(scores[i])
		if roll <= 0.0:
			return options[i]
	return options[scores.keys()[-1]]


func _r(a: Dictionary, key: String, fallback: Array) -> float:
	var r: Array = a.get(key, fallback)
	return _rng.randf_range(float(r[0]), float(r[1]))


func _ri(a: Dictionary, key: String, fallback: Array) -> int:
	var r: Array = a.get(key, fallback)
	return _rng.randi_range(int(r[0]), int(r[1]))


func _vr(a: Dictionary, key: String, fallback: Array) -> Vector2:
	var r: Array = a.get(key, fallback)
	return Vector2(float(r[0]), float(r[1]))


func _on_ground() -> bool:
	return habitat in ["ground_far", "ground_mid", "shore_far", "shore_mid"]


func _forage_habitat() -> String:
	if habitat == "shore_far":
		return "ground_far"
	if habitat == "shore_mid":
		return "ground_mid"
	return habitat


# --- Arrival and departure ----------------------------------------------------------------------

func _plan_arrival() -> bool:
	match sp.body:
		"heron":
			band = "water"
			beats.append_array(SceneHeron.walk_in(self) if SceneHeron.entrance(self, why) == "walk" else SceneHeron.glide_in(self))
			return true
		"turtle":
			return _arrive_basker()
		"snake":
			return _arrive_swimmer()
		"fish":
			return _arrive_fish()
	if sp.id == "gray_squirrel" and _rng.randf() < 0.45:
		return _arrive_down_trunk()
	return _arrive_walking()


func _arrive_walking() -> bool:
	var g := _forage_habitat()
	var lane := beh.lane_of(g)
	if lane.is_empty():
		return false
	band = beh.band_of(habitat)
	if leader != null and spacing_m != Vector2.ZERO and not leader._from_grass:
		return _arrive_in_herd(g)
	if leader != null:
		var behind := -leader.facing * _rng.randf_range(1.5, 4.0) * beh.ppm(band, leader.pos.y)
		pos = leader.pos + Vector2(behind, _rng.randf_range(-2.0, 2.0))
		alpha = 0.0 if band == "far" else 1.0
		var target: Vector2 = leader.beats[0]["to"] if not leader.beats.is_empty() and leader.beats[0].has("to") else leader.pos
		if not leader.beat.is_empty() and leader.beat.has("to"):
			target = leader.beat["to"]
		if leader._from_grass and _out_of_grass(leader.pos.x + behind, leader._grass_left() + _rng.randf_range(0.8, 1.8)):
			return true
		beats.append({"a": "walk", "to": beh.on_ground(g, target + Vector2(behind * 0.6, _rng.randf_range(-1.5, 1.5))), "gait": "walk", "fade": 1.0, "max_sec": 25.0})
		beats.append({"a": "look", "sec": _rng.randf_range(0.6, 2.0)})
		return true
	var grass: Dictionary = beh.tuning["grass"]
	if band == "mid" and _rng.randf() < float(grass["come_out_chance"]):
		var at_x: Vector2 = SceneVariety.apart(func() -> Variant: return Vector2(_rng.randf_range(lane[0].x, lane[-1].x), 0.0),
				beh.recent_places(sp.id + "_grass"), _apart_pt())
		beh.remember_place(sp.id + "_grass", at_x)
		var line_x := at_x.x
		if _out_of_grass(line_x, _r(grass, "hidden_sec", [1.0, 3.5])):
			return true
	var start_x := _rng.randf_range(lane[0].x + 10.0, lane[-1].x - 10.0)
	var way := beh.way_out(g, Vector2(start_x, SceneBehaviour.lane_y(lane, start_x)))
	pos = way["at"]
	alpha = 0.0 if bool(way["fade"]) else 1.0
	var gait := "run" if sp.id == "gray_squirrel" else "walk"
	if bool(way["fade"]):
		var into := beh.ground_near(g, Vector2(pos.x, SceneBehaviour.lane_y(lane, pos.x)), Vector2(0.5, 3.0))
		beats.append({"a": gait, "to": into, "gait": gait, "fade": 1.0})
	else:
		# Where it first stops: never where the last few of its kind did (issue 272).
		var into: Vector2 = SceneVariety.apart(func() -> Variant: return beh.ground_near(g, Vector2(lane[-1].x, lane[-1].y), Vector2(4.0, 14.0), -1.0),
				beh.recent_places(sp.id + "_arrive"), _apart_pt())
		beh.remember_place(sp.id + "_arrive", into)
		beats.append({"a": gait, "to": into, "gait": gait, "fade": 1.0, "max_sec": 40.0})
	# Out of cover, a prey animal stops and looks before it commits.
	beats.append({"a": "look", "sec": _rng.randf_range(1.5, 5.0)})
	if _rng.randf() < 0.5:
		beats.append({"a": "ear_flick" if sp.id == "deer" else "tail_flick", "sec": 0.6})
	return true


## A member of a natural group (issue 320) comes the leader's way but to its own place: `spacing_m`
## from whom it keeps by (a fawn its mother, a doe or a second buck the leader, a trailing buck the
## doe from well back), never on top of another, not in a line (its own depth on the ground), and a
## little after the one before it, never in step.
func _arrive_in_herd(g: String) -> bool:
	var h: Dictionary = sp.data.get("herd", {})
	var anchor := leader.first_stop()
	var p := beh.ppm(band, anchor.y)
	var to := herd_spot(anchor, -leader.facing)
	_first_stop = to
	var shift := to.x - anchor.x
	if beh.band_of(habitat) == "mid" and leader.pos.x > beh.scene.size_pt.x:
		# In off the right edge after the leader, at its own depth on the strip.
		pos = leader.pos + Vector2(_rng.randf_range(0.6, 1.8) * p, to.y - anchor.y)
	else:
		pos = Vector2(SceneVariety.fold(leader.pos.x + shift, 0.0, beh.scene.size_pt.x), leader.pos.y)
	alpha = leader.alpha
	var key := "fawn" if young else "adult"
	var wait: Vector2 = Vector2(h.get("stagger_sec", {}).get(key, [0.5, 3.0])[0], h.get("stagger_sec", {}).get(key, [0.5, 3.0])[1])
	if herd_role == "trail":
		var t: Array = h.get("trail_delay_sec", [10, 30])
		wait = Vector2(float(t[0]), float(t[1]))
	facing = leader.facing
	beats.append({"a": "idle", "sec": _rng.randf_range(wait.x, wait.y), "alpha": alpha})
	beats.append({"a": "walk", "to": to, "gait": "walk", "fade": 1.0, "max_sec": 40.0})
	beats.append({"a": "look", "sec": _rng.randf_range(1.0, 4.0)})
	if _rng.randf() < 0.5:
		beats.append({"a": "ear_flick", "sec": 0.6})
	return true


## Where it first stops (points): its arrival's last place to walk to.
var _first_stop: Variant = null


func first_stop() -> Vector2:
	if _first_stop != null:
		return _first_stop
	for i in range(beats.size() - 1, -1, -1):
		if beats[i].has("to"):
			return beats[i]["to"]
	return pos


## A place `spacing_m` from `center` (points) on its ground, on side `side` more often than not, kept
## clear of the rest of its group (where they stand and where they are going): an adult at least the
## near end of its spacing from other adults, anyone at least a body's length across from anyone.
## The best of a few tries.
func herd_spot(center: Vector2, side: float) -> Vector2:
	var g := _forage_habitat()
	var lane := beh.lane_of(g)
	var p := beh.ppm(band, center.y)
	var best := center
	var best_score := -INF
	for i in 10:
		var s := side if _rng.randf() < 0.7 else -side
		if s == 0.0:
			s = -1.0 if _rng.randf() < 0.5 else 1.0
		var x := center.x + s * _rng.randf_range(spacing_m.x, spacing_m.y) * p
		if not lane.is_empty():
			x = SceneVariety.fold(x, lane[0].x + 6.0, lane[-1].x - 6.0)
		var q := beh.ground_near(g, Vector2(x, center.y), Vector2.ZERO)
		var score := minf(_herd_clearance(q), 3.0)
		var off := absf(q.x - center.x) / p
		if off < spacing_m.x * 0.8 or off > spacing_m.y * 1.2:
			score -= 2.0
		if score > best_score:
			best_score = score
			best = q
		if score >= 3.0:
			break
	return best


## How clear `q` is of the rest of its group, in metres beyond the gap it needs (negative: too close).
func _herd_clearance(q: Vector2) -> float:
	var p := beh.ppm(band, q.y)
	var worst := INF
	for o in herd:
		var c: SceneCreature = o
		if c == self or not is_instance_valid(c) or c.state == "gone" or c.band != band:
			continue
		var need := 1.3 if young or c.young else spacing_m.x
		if c.herd_role == "trail" or herd_role == "trail":
			need = 1.5
		for at in [c.pos, c.heading_to(), c.water_spot()]:
			worst = minf(worst, absf((at as Vector2).x - q.x) / p - need)
	return worst


## Where it drinks: the last place it walks to before its next draught (it may stop on the way), else
## where it is going.
func water_spot() -> Vector2:
	var at := heading_to()
	for b in [beat] + beats:
		if String((b as Dictionary).get("a", "")) == "drink":
			return at
		if (b as Dictionary).has("to"):
			at = b["to"]
	return heading_to()


## Where it is going (its beat's place), else where it is.
func heading_to() -> Vector2:
	if beat.has("to"):
		return beat["to"]
	if _first_stop != null and state == "arriving":
		return _first_stop
	return pos


## How far (points) an arrival's first stop keeps from the last few of its kind (issue 272):
## the species' `variation.apart_pt`, else `behaviour.variation.apart_pt`.
func _apart_pt() -> float:
	return float(sp.data.get("variation", {}).get("apart_pt", beh.tuning.get("variation", {}).get("apart_pt", 24.0)))


## Out of the grass behind the shore strip near `x`: it fades in among the reeds, stands there
## `hold` seconds (partly hidden, looking out), and steps out onto the open strip. False when the
## places have no grass.
func _out_of_grass(x: float, hold: float) -> bool:
	var grass: Dictionary = beh.tuning["grass"]
	var found: Variant = beh.grass_point(x)
	if found == null:
		return false
	var at: Vector2 = found
	var fade := float(grass["fade_sec"])
	hold = clampf(hold, 0.3, float(grass["max_hidden_sec"]) - fade - 1.5)
	var p := beh.ppm(band, at.y)
	var edge := beh.strip_edge(at.x)
	pos = at + Vector2(_rng.randf_range(-0.2, 0.2) * p, -0.06 * p)
	alpha = 0.0
	_from_grass = true
	_z_layer = String(grass["layer"])
	facing = -1.0 if _rng.randf() < 0.5 else 1.0
	beats.append({"a": "walk", "to": at, "gait": "walk", "speed": float(grass["into_m_per_sec"]), "fade": 1.0, "fade_sec": fade, "max_sec": fade})
	beats.append({"a": "look", "sec": hold, "fade": 1.0})
	if sp.id == "deer" and _rng.randf() < 0.5:
		beats.append({"a": "ear_flick", "sec": 0.5})
	beats.append({"a": "walk", "to": edge, "gait": "walk", "max_sec": 1.5})
	var into := beh.ground_near(_forage_habitat(), edge, Vector2(0.4, 1.5))
	beats.append({"a": "walk", "to": into, "gait": "walk", "layer": band})
	beats.append({"a": "look", "sec": _rng.randf_range(1.0, 3.0)})
	return true


## How long it has left in the grass while it comes out of it (0 once out).
func _grass_left() -> float:
	if not in_grass():
		return 0.0
	var left := 0.0
	for b in [beat] + beats:
		if (b as Dictionary).has("layer"):
			break
		left += float((b as Dictionary).get("sec", (b as Dictionary).get("max_sec", 0.0)))
	return maxf(0.0, left - beat_t)


func _arrive_down_trunk() -> bool:
	_route = beh.climb_route()
	var trunk: PackedVector2Array = _route.get("trunk", PackedVector2Array())
	if trunk.size() < 2:
		return _arrive_walking()
	band = String(_route["band"])
	pos = trunk[-1] + Vector2(0, -12)
	alpha = 0.0
	_aloft = true
	facing = -1.0
	for i in range(trunk.size() - 1, -1, -1):
		beats.append({"a": "climb", "to": trunk[i], "speed": sp.speed("climb"), "climb": "down", "fade": 1.0})
	beats.append({"a": "sit", "sec": _rng.randf_range(0.8, 2.5), "aloft": false})
	beats.append({"a": "tail_flick", "sec": 0.8})
	return true


func _wade_depth(at: Vector2) -> float:
	return 0.13 if beh.scene.is_water(at) else 0.0


func _arrive_basker() -> bool:
	if leader != null and not leader._spot.is_empty():
		_spot = leader._spot.duplicate()
		var p := beh.ppm(String(_spot["band"]), (_spot["at"] as Vector2).y)
		_spot["at"] = (_spot["at"] as Vector2) + Vector2(_rng.randf_range(0.18, 0.35) * (-1.0 if _rng.randf() < 0.5 else 1.0) * p, _rng.randf_range(-0.03, 0.03) * p)
	else:
		_spot = beh.bask_spot()
	if _spot.is_empty():
		return false
	band = "water"
	var water: Vector2 = _spot["water"]
	var p := beh.ppm("water", water.y)
	pos = water + Vector2(_rng.randf_range(1.0, 3.5) * (-1.0 if _rng.randf() < 0.5 else 1.0) * p, _rng.randf_range(-0.3, 0.1) * p)
	if not beh.scene.is_water(pos):
		pos = water
	alpha = 0.0
	look.under = 1.0
	var deep: Variant = beh.underwater_point(water.x)
	# Up out of the cut-away only to water near its front: a spot out on the far pond is tens of
	# metres back, which it cannot swim in a few seconds (issue 318); there it surfaces where it is.
	var back_m := beh.depth_of(beh.ppm("water", water.y)) - beh.depth_of(beh.ppm("water", beh.cut_y()))
	if back_m > float(sp.data.get("rise_reach_m", 6.0)):
		deep = null
	if deep != null:
		# Up out of the murk of the cut-away, through the surface, then across to the rock.
		pos = deep
		var below := Vector2(water.x + _rng.randf_range(-20.0, 20.0), beh.cut_y() + 6.0)
		beats.append({"a": "swim", "to": below, "speed": sp.speed("swim"), "fade": 1.0})
		beats.append({"a": "surface", "to": water, "speed": sp.speed("swim") * 0.6, "fx": "break"})
	else:
		beats.append({"a": "surface", "sec": _rng.randf_range(1.5, 3.0) + (4.0 if leader != null else 0.0), "fade": 1.0, "fx": "ring"})
		beats.append({"a": "swim", "to": water, "speed": sp.speed("swim")})
	beats.append({"a": "look", "sec": _rng.randf_range(1.0, 3.0)})
	beats.append({"a": "walk", "to": _spot["at"], "speed": sp.speed("walk"), "band": String(_spot["band"]), "gait": "walk"})
	return true


## Fish come up out of the murk of the cut-away in the part of it their kind keeps to (a catfish
## on the bed, crappie mid-water, sunfish near the glass and the weeds), a group around its leader.
func _arrive_fish() -> bool:
	var start: Variant = null
	if leader != null:
		var f := sp.range_of("follow_pt", [8, 24])
		_slot = beh.creatures.filter(func(c: SceneCreature) -> bool: return c.leader == leader).size()
		start = _slot_point(leader.facing)
		if not beh.in_swim(start, _half()):
			start = beh.fish_point(zones(), leader.pos.x, f.y * 2.0, _half())
	else:
		start = beh.fish_point(zones(), -1.0, 160.0, _half())
	if start == null:
		return false
	band = "water"
	pos = start
	alpha = 0.0
	facing = leader.facing if leader != null else (-1.0 if _rng.randf() < 0.5 else 1.0)
	var bottom := bottom_fish()
	beats.append({"a": "bottom" if bottom else "swim", "to": _level(pos, pos + Vector2(facing * _rng.randf_range(10.0, 30.0), _rng.randf_range(-6.0, 6.0))),
			"speed": sp.speed("bottom" if bottom else "swim"), "fade": 1.0})
	return true


## Half its drawn length (points): how far it must keep from the bank.
func _half() -> float:
	if look.sheet != null:
		return float(look.sheet.sets["side"]["master"]["frame"].x) * 0.45 / beh.scene.density
	return sp.size().x * 0.5 * 90.0


func zones() -> Dictionary:
	return sp.data.get("zones", {})


## A catfish: it keeps to the bed and plays its `bottom` cruise there.
func bottom_fish() -> bool:
	return zones().has("bed") and look.sheet != null and look.sheet.anims.get("side", {}).has("bottom")


## Turns through the bench's `turn` sheet (right, nose-on, left; flipped after) instead of flipping.
func turns() -> bool:
	return sp.body == "fish" and look.sheet != null and look.sheet.anims.get("side", {}).has("turn")


func _turn_sec() -> float:
	var anim: Dictionary = look.sheet.anims["side"]["turn"]
	return float((anim.get("frames", []) as Array).size()) / maxf(1.0, float(anim.get("fps", 12)))


## Which way `b` needs the fish to face first (0: either).
func _wants_facing(b: Dictionary) -> float:
	if b.has("path"):
		return 0.0
	if b.has("face"):
		return float(b["face"])
	var dx := 0.0
	if b.has("face_to"):
		dx = (b["face_to"] as Vector2).x - pos.x
	elif b.has("to"):
		dx = (b["to"] as Vector2).x - pos.x
	if absf(dx) <= float(beh.tuning["fish"]["turn_min_pt"]):
		return 0.0
	return signf(dx)


## This follower's place by its leader (points), a little different each time.
func _slot_point(lead_facing: float) -> Vector2:
	var body := Vector2(sp.size().x, sp.size().y) * 0.5 * ppm() * sp.show_scale(band, ppm() * beh.scene.density)
	if look.sheet != null:
		var frame: Vector2 = look.sheet.sets["side"]["master"]["frame"]
		body = frame * 0.8 / beh.scene.density
	var s: Vector2 = FISH_SLOTS[_slot % FISH_SLOTS.size()] * float(sp.data.get("spread", 1.2)) * leader.depth_size()
	var jitter := Vector2(_rng.randf_range(-0.25, 0.25), _rng.randf_range(-0.2, 0.2))
	return leader.pos + Vector2(-lead_facing * (s.x + jitter.x) * body.x, (s.y + jitter.y) * body.y)


## Fish swim level, not up and down hills: `to` brought within a slope of `from` (and kept in the water).
func _level(from: Vector2, to: Vector2) -> Vector2:
	var dx := absf(to.x - from.x)
	var q := Vector2(to.x, from.y + clampf(to.y - from.y, -dx * 0.4 - 4.0, dx * 0.4 + 4.0))
	if beh.in_swim(q, _half()):
		return q
	# Short of the bank: as far along the way as stays in the water.
	for i in range(8, -1, -1):
		var r := from.lerp(to, float(i) / 8.0)
		if beh.in_swim(r, _half()):
			return r
	return from


func _do_cruise(_a: Dictionary) -> void:
	if heading != null and leader == null and _rng.randf() < float(beh.tuning["fish"].get("depth_run", {}).get("chance", 0.0)) and _depth_run():
		return
	_maybe_new_depth()
	var c := sp.range_of("cruise_pt", [20, 160])
	# Mostly on the way it is going; now and then it turns back.
	var ahead := facing if _rng.randf() < 0.7 else -facing
	var to: Variant = beh.fish_point(zones(), pos.x + ahead * _rng.randf_range(c.x, c.y), c.y * 0.5, _half())
	if to == null:
		return
	# A gentle arc of its own, never the ruler line between two points (issue 272).
	var bend: float = beh.tuning["fish"].get("bend", 0.0)
	beats.append({"a": "swim", "to": _level(pos, to), "speed": sp.speed("swim") * _rng.randf_range(0.6, 1.2), "bend": _rng.randf_range(-bend, bend)})
	if _rng.randf() < 0.4:
		beats.append({"a": "swim", "sec": _rng.randf_range(1.0, 4.0)})


## Swims into the depth of the cut-away or out of it toward the glass, mostly straight, drifting a
## little across (issue 237): seen from behind going in, from the front coming out. Only for a fish
## drawn in those views. False when it is already about as far in or out as it goes.
func _depth_run() -> bool:
	var spec: Dictionary = beh.tuning["fish"]["depth_run"]
	var r := _depth_range()
	var z_to := r.y if depth_z - r.x < r.y - depth_z else r.x
	var dz := z_to - depth_z
	if absf(dz) < float(spec["min_dz"]):
		return false
	var v := sp.speed("swim") * _rng.randf_range(float(spec["speed"][0]), float(spec["speed"][1]))
	var across := deg_to_rad(_rng.randf_range(float(spec["across_deg"][0]), float(spec["across_deg"][1])))
	var sec := absf(dz) * float(_depth_tuning()["span_m"]) / maxf(v * cos(across), 0.01)
	var dir := facing if _rng.randf() < 0.7 else -facing
	# Points across at its size midway in.
	var size_mid := lerpf(depth_size(), lerpf(1.0, float(_depth_tuning()["back_size"]), z_to), 0.5)
	var to := _level(pos, pos + Vector2(dir * v * sin(across) * sec * ppm() * size_mid, _rng.randf_range(-4.0, 4.0)))
	_z_target = z_to
	var run := {"a": "swim", "z_rate": absf(dz) / sec, "rate": clampf(v / maxf(sp.speed("swim"), 0.01), 0.6, 1.4), "sec": sec}
	if pos.distance_to(to) > 1.0:
		# Across at the pace that takes it there as it gets to its depth.
		run["to"] = to
		run["speed"] = pos.distance_to(to) / (sec * ppm() * size_mid)
		run["max_sec"] = sec * 1.2
	beats.append(run)
	if _rng.randf() < 0.5:
		beats.append({"a": "swim", "sec": _rng.randf_range(1.0, 3.0), "rate": 0.5})
	return true


## A depth run now (a clip's `act`), or a cruise when it is as far in or out as it goes.
func _do_depth_run(a: Dictionary) -> void:
	if heading == null or not _depth_run():
		_do_cruise(a)


## The heron leaves now, away over the pond into the scene (a clip's `act`).
func _do_fly_away(_a: Dictionary) -> void:
	_away_next = true
	_leave(false)


## Hangs in the water by the weeds, fins going, drifting a little.
func _do_hang(_a: Dictionary) -> void:
	_maybe_new_depth()
	var p := ppm()
	var long := sp.size().x > 0.45
	for i in _rng.randi_range(1, 3):
		var drift := _level(pos, pos + Vector2(facing * _rng.randf_range(0.01, 0.06) * p, _rng.randf_range(-0.03, 0.03) * p))
		beats.append({"a": "swim", "to": drift, "speed": sp.speed("swim") * 0.12, "rate": 0.45,
				"max_sec": _rng.randf_range(4.0, 12.0) if long else _rng.randf_range(1.5, 5.0)})


## A catfish working along the bed: slow bouts with its barbels out, stops, and on.
func _do_bottom(_a: Dictionary) -> void:
	_maybe_new_depth()
	var c := sp.range_of("cruise_pt", [40, 160])
	for i in _rng.randi_range(2, 4):
		var ahead := facing if _rng.randf() < 0.75 else -facing
		var to: Variant = beh.fish_point({"bed": 1.0}, pos.x + ahead * _rng.randf_range(c.x, c.y) * 0.5, c.y * 0.4, _half())
		if to == null:
			return
		beats.append({"a": "bottom", "to": to, "speed": sp.speed("bottom") * _rng.randf_range(0.7, 1.2), "rate": 1.0, "max_sec": 40.0})
		if _rng.randf() < 0.6:
			beats.append({"a": "bottom", "sec": _rng.randf_range(2.0, 6.0), "rate": 0.5})


## A bass goes for the sunfish: a beat lined up on them, then a short fast rush that scatters them.
func _do_rush(_a: Dictionary) -> void:
	var spec: Dictionary = sp.data.get("rush", {})
	var prey: SceneCreature = null
	var best := float(spec.get("within_m", 1.5))
	for o in beh.creatures:
		var other: SceneCreature = o
		if other.state == "gone" or other.alpha < 0.5 or not (spec.get("prey", []) as Array).has(other.sp.id):
			continue
		var d := _dist_m(other)
		if d < best:
			best = d
			prey = other
	if prey == null:
		_do_cruise({})
		return
	_z_target = prey.depth_z
	var p := ppm()
	beats.append({"a": "swim", "sec": _rng.randf_range(0.6, 1.4), "face_to": prey.pos, "rate": 0.5})
	var dir := signf(prey.pos.x - pos.x) if absf(prey.pos.x - pos.x) > 0.5 else facing
	var to := _level(pos, prey.pos + Vector2(dir * 0.2 * p, 0.0))
	beats.append({"a": "swim", "to": to, "speed": sp.speed("dart"), "rate": 2.5, "max_sec": 3.0, "fx": "rush"})
	beats.append({"a": "swim", "to": _level(to, to + Vector2(dir * 0.25 * p, 0.0)), "speed": sp.speed("swim"), "rate": 0.8})


## Up to just under the surface, a snap at something on it (a ring above), and back down; now and
## then it comes up fast and clears the water in an arc, back in with a splash.
func _do_rise(a: Dictionary) -> void:
	var under := Vector2(pos.x + facing * _rng.randf_range(5.0, 25.0), beh.cut_y() + 6.0)
	beats.append({"a": "swim", "to": under, "speed": sp.speed("swim") * 1.3})
	var leap := _rng.randf() < float(sp.data.get("leap_chance", 0.0))
	if bool(a.get("leap", leap)):
		var p := ppm()
		var k := depth_size()
		var h: Array = sp.data.get("leap_m", [0.25, 0.5])
		var up := _rng.randf_range(float(h[0]), float(h[1])) * p * k
		var across := facing * up * _rng.randf_range(1.1, 1.6)
		var row: Vector2 = beh.surface_at(under.x, k)["at"]
		var out := Vector2(under.x, beh.cut_y() + 2.0)
		var after := {"a": "dive", "to": out + Vector2(across + facing * 6.0, 14.0), "speed": sp.speed("swim") * 2.0, "fx": "break"}
		var far := row.y < beh.cut_y() - 4.0
		if far:
			# Further back, it leaves the cut-away for the surface over it (issue 237): it fades
			# going up into the light under the surface, clears the water out on the pond at its own
			# row, as large as it is drawn, and is back under the surface, fading in as it goes down.
			out = row
			beats.append({"a": "swim", "sec": 0.5, "rate": 0.7, "fade": 0.0, "fade_sec": float(_depth_tuning()["leap_fade_sec"])})
			var under_again := Vector2(under.x + across, beh.cut_y() + 4.0)
			after["at"] = under_again
			after["alpha"] = 0.0
			after["fade"] = 1.0
			after["to"] = _level(under_again, under_again + Vector2(facing * 6.0, 14.0))
		var back := out + Vector2(across, 0.0)
		var leap_beat := {"a": "surface", "path": [out, out + Vector2(across * 0.2, -up * 1.35), back + Vector2(-across * 0.2, -up * 1.35), back],
				"dur": sqrt(up / (p * k)) * 0.9, "ppm": [p, p], "tilt": true, "fx": "leap"}
		if far:
			leap_beat["alpha"] = 1.0
		beats.append(leap_beat)
		beats.append(after)
	else:
		beats.append({"a": "surface", "sec": 1.2, "fx": "rise"})
	var down: Variant = beh.fish_point(zones(), under.x, 60.0, _half())
	if down != null:
		beats.append({"a": "dive", "to": down, "speed": sp.speed("swim") * 1.5})


func _arrive_swimmer() -> bool:
	var path := beh.snake_path()
	band = "water"
	pos = path[0]
	alpha = 0.0
	_route = {"path": path}
	var mid: Vector2 = (path[0] as Vector2).lerp(path[1], _rng.randf_range(0.35, 0.6))
	beats.append({"a": "swim", "to": mid, "speed": sp.speed("swim"), "fade": 1.0})
	if _rng.randf() < 0.6:
		beats.append({"a": "look", "sec": _rng.randf_range(1.5, 4.0)})
	beats.append({"a": "swim", "to": path[1], "speed": sp.speed("swim")})
	return true


func _leave(hurry: bool) -> void:
	beats.clear()
	state = "fleeing" if hurry else "leaving"
	match sp.body:
		"heron":
			# Heavy and low: mostly away across the pond (the long, open way), climbing slowly.
			var up := Vector2(-80.0 if pos.x > beh.scene.size_pt.x * 0.5 else beh.scene.size_pt.x + 80.0, _rng.randf_range(30.0, 110.0))
			if _rng.randf() < 0.2:
				up.x = beh.scene.size_pt.x + 80.0 - up.x
			var p := ppm()
			var dir := signf(up.x - pos.x)
			if (_away_next or _rng.randf() < float(sp.data.get("fly_away", {}).get("chance", 0.0))) and band == "water":
				# Or away over the open pond into the scene (issue 237), seen going from behind.
				dir = -1.0 if pos.x > beh.scene.size_pt.x * 0.5 else 1.0
				var lift := SceneHeron.takeoff(self, dir, hurry)
				beats.append_array(lift)
				beats.append(SceneHeron.fly_away(self, (lift[-1]["path"] as Array)[-1], dir, hurry))
				return
			var off := SceneHeron.takeoff(self, dir, hurry)
			beats.append_array(off)
			var from: Vector2 = (off[-1]["path"] as Array)[-1]
			beats.append({"a": "fly", "path": [from, from + Vector2(dir * 60.0, -12.0), up.lerp(from, 0.35) + Vector2(0, -10), up],
					"dur": clampf(from.distance_to(up) / (p * sp.speed("fly") * (1.3 if hurry else 1.0)), 5.0, 10.0), "ppm": [p, p * 0.6], "ease": "", "wade": 0.0})
		"turtle":
			if band != "water":
				beats.append({"a": "walk", "to": _spot.get("water", pos), "speed": sp.speed("walk") * (4.0 if hurry else 1.0), "then_band": "water"})
			beats.append({"a": "dive", "sec": 0.8 if hurry else 1.6, "fade": 0.0, "fx": "plop" if hurry else "ring"})
		"snake":
			beats.append({"a": "dive", "sec": 1.6, "fade": 0.0, "fx": "ring"})
		"fish":
			# Back into the murk as it fades.
			_z_target = 1.0
			var deep: Variant = beh.fish_point(zones(), pos.x + facing * 80.0, 60.0, _half())
			var bottom := bottom_fish()
			beats.append({"a": "bottom" if bottom else "swim", "to": _level(pos, deep) if deep != null else pos,
					"speed": sp.speed("bottom" if bottom else "swim") * (3.0 if hurry else 1.0), "fade": 0.0})
		_:
			if _aloft and not _route.is_empty():
				var trunk: PackedVector2Array = _route["trunk"]
				beats.append({"a": "climb", "to": trunk[-1] + Vector2(-4, -26), "speed": sp.speed("climb") * (1.6 if hurry else 1.0), "climb": "up", "fade": 0.0})
				return
			var g := _forage_habitat()
			var way := beh.way_out(g, pos, _threat if hurry else null)
			var gait := "run" if hurry or sp.id == "gray_squirrel" else ("trot" if _rng.randf() < 0.25 else "walk")
			if hurry:
				beats.append({"a": "startle", "sec": _rng.randf_range(0.25, 0.9), "fx": "alarm"})
			if band == "mid" and not bool(way.get("grass", false)):
				var lead_in := leader != null and is_instance_valid(leader) and leader._into_grass()
				if lead_in or in_grass() or (not hurry and leader == null and _rng.randf() < float(beh.tuning["grass"]["go_in_chance"])):
					var spot: Variant = beh.grass_point(leader.pos.x if lead_in else pos.x)
					if spot != null:
						way = {"at": spot, "fade": true, "grass": true}
			if bool(way.get("grass", false)):
				_into_grass_beats(way["at"], gait, hurry)
				return
			var to: Vector2 = way["at"]
			if leader != null and is_instance_valid(leader) and not leader.beats.is_empty():
				for b in leader.beats:
					if b.has("to"):
						to = (b["to"] as Vector2) + Vector2(_rng.randf_range(-8.0, 8.0), _rng.randf_range(-2.0, 2.0))
			beats.append({"a": gait, "to": to, "gait": gait, "fade": 0.0 if bool(way["fade"]) else 1.0, "max_sec": 60.0})
			beats.append({"a": "idle", "sec": 0.2, "fade": 0.0})


## Off the strip into the grass at `spot` and on into the reed stand, fading as it goes: from the
## strip's back edge it is drawn behind the reeds.
func _into_grass_beats(spot: Vector2, gait: String, hurry: bool) -> void:
	var grass: Dictionary = beh.tuning["grass"]
	var p := beh.ppm(band, spot.y)
	if not in_grass():
		beats.append({"a": gait, "to": beh.strip_edge(spot.x), "gait": gait, "max_sec": 30.0})
	var fade := float(grass["flee_fade_sec" if hurry else "fade_sec"])
	var dir := signf(spot.x - pos.x) if absf(spot.x - pos.x) > 1.0 else facing
	var deep := spot + Vector2(dir * 0.6 * p, -0.06 * p)
	var slow := "walk" if not hurry else gait
	beats.append({"a": gait, "to": spot, "gait": gait, "layer": String(grass["layer"]), "max_sec": 3.0})
	beats.append({"a": slow, "to": deep, "gait": slow, "speed": float(grass["into_m_per_sec"]) * (3.0 if hurry else 1.0),
			"fade": 0.0, "fade_sec": fade, "max_sec": fade})
	beats.append({"a": "idle", "sec": 0.1, "fade": 0.0, "alpha": 0.0})


## Its way out is into the grass (its followers go after it).
func _into_grass() -> bool:
	if state != "leaving" and state != "fleeing":
		return false
	for b in [beat] + beats:
		if String((b as Dictionary).get("layer", "")) == String(beh.tuning["grass"]["layer"]):
			return true
	return in_grass()


## A fish darting off from a bigger fish: a quick turn if it must, a burst away, and on with its
## life a beat later (it does not leave the pond over it).
func scatter(from: Vector2, why: String) -> void:
	if state != "living" or bool(beat.get("dart", false)) or beats.any(func(b: Dictionary) -> bool: return bool(b.get("dart", false))):
		return
	beh.note("%s scatters (%s)" % [sp.id, why], sp.id)
	var p := ppm()
	var dir := signf(pos.x - from.x) if absf(pos.x - from.x) > 0.5 else -facing
	var r: Array = beh.tuning["fish"]["dart_m"]
	var d := _rng.randf_range(float(r[0]), float(r[1])) * p
	var to := pos + Vector2(dir * d, _rng.randf_range(-0.35, 0.35) * d)
	if not beh.in_swim(to, _half()):
		var q: Variant = beh.fish_point(zones(), pos.x + dir * d, d * 0.5, _half())
		to = q if q != null else pos
	uneasy = UNEASY_SEC
	_interrupt([{"a": "swim", "to": to, "speed": sp.speed("dart"), "rate": 2.5, "dart": true, "max_sec": 2.0, "turn_sec": float(beh.tuning["fish"]["dart_turn_sec"])},
			{"a": "swim", "sec": _rng.randf_range(0.6, 1.8), "rate": 0.8}], true)


## Away from `from`, now.
func flee(from: Vector2, why: String) -> void:
	if state == "fleeing" or state == "gone":
		return
	beh.note("%s flees (%s)" % [sp.id, why], sp.id)
	_threat = from
	if beat.has("path") or _climb != "" or beat.has("band"):
		# Finish the flight or the climb in hand, then go.
		state = "fleeing"
		beats.clear()
		_leave_next = "hurry"
		return
	_leave(true)
	beat = {}


# --- Activities ---------------------------------------------------------------------------------

func _do_forage(a: Dictionary) -> void:
	var g := _forage_habitat()
	var gait := String(a.get("gait", "walk"))
	# Grazing along the shore it faces the water more often than not (issue 320): its steps lean that way.
	var side := beh.water_side(band) if sp.data.has("herd") else 0.0
	var lean := float(sp.data.get("herd", {}).get("water_face_chance", 0.5))
	for i in _ri(a, "bouts", [2, 5]):
		if _rng.randf() < 0.75:
			var toward := (side if _rng.randf() < lean else -side) if side != 0.0 else 0.0
			var step := beh.ground_near(g, pos if beats.is_empty() else _last_to(), _vr(a, "step_m", [0.5, 2.0]), toward)
			var tries := 0
			while not herd.is_empty() and _herd_clearance(step) < 0.0 and tries < 5:
				# Never onto another of its group: another step, or it grazes where it stands.
				tries += 1
				step = beh.ground_near(g, pos if beats.is_empty() else _last_to(), _vr(a, "step_m", [0.5, 2.0]) * (1.0 + tries * 0.4), -toward if tries % 2 == 1 else toward)
			if herd.is_empty() or _herd_clearance(step) >= 0.0:
				beats.append({"a": gait, "to": step, "gait": gait})
		beats.append({"a": String(a.get("action", "graze")), "sec": _r(a, "bout_sec", [3, 8])})
		if _rng.randf() < float(a.get("scan_chance", 0.4)):
			beats.append({"a": "look", "sec": _r(a, "scan_sec", [1, 3])})
		if _rng.randf() < float(a.get("flick_chance", 0.3)):
			beats.append({"a": "ear_flick" if _rng.randf() < 0.55 else "tail_flick", "sec": 0.7})
		if _rng.randf() < 0.1:
			beats.append({"a": "idle", "sec": 0.5, "face": -facing})


func _last_to() -> Vector2:
	for i in range(beats.size() - 1, -1, -1):
		if beats[i].has("to"):
			return beats[i]["to"]
	return pos


func _do_drink(a: Dictionary) -> void:
	var g := _forage_habitat()
	var edge := beh.shore_near(g, pos)
	if sp.data.has("herd"):
		# Down to the water cautiously, facing it, clear of the rest of its group (issue 320).
		for i in 6:
			if _herd_clearance(edge) > 0.0:
				break
			edge = beh.shore_near(g, pos)
		_to_water(edge, true)
	else:
		beats.append({"a": "walk", "to": edge, "gait": "walk"})
		beats.append({"a": "look", "sec": _rng.randf_range(0.8, 2.5)})
	var left := _r(a, "sec", [5, 12])
	while left > 0.0:
		var chunk := minf(left, _r(a, "lift_every_sec", [3, 7]))
		beats.append({"a": "drink", "sec": chunk})
		left -= chunk
		if left > 0.0:
			beats.append({"a": "look", "sec": _rng.randf_range(0.7, 2.0)})
			if _rng.randf() < 0.3:
				beats.append({"a": "ear_flick", "sec": 0.5})
	beats.append({"a": "walk", "to": beh.ground_near(g, edge, Vector2(1.0, 3.0)), "gait": "walk"})


func _do_dabble(a: Dictionary) -> void:
	var edge := beh.shore_near(_forage_habitat(), pos)
	beats.append({"a": "walk", "to": edge, "gait": "walk"})
	for i in _ri(a, "bouts", [3, 6]):
		beats.append({"a": "drink", "sec": _r(a, "bout_sec", [3, 8])})
		if _rng.randf() < 0.3:
			beats.append({"a": "sit", "sec": _rng.randf_range(1.5, 4.0)})
		var lane := beh.lane_of("shore_mid" if band == "mid" else "shore_far")
		if not lane.is_empty():
			var x := clampf(_last_to().x + _rng.randf_range(-1.0, 1.0) * _r(a, "step_m", [0.5, 2.0]) * ppm(), lane[0].x + 4.0, lane[-1].x - 4.0)
			beats.append({"a": "walk", "to": Vector2(x, SceneBehaviour.lane_y(lane, x)), "gait": "walk"})


func _do_wander(a: Dictionary) -> void:
	var gait := String(a.get("gait", "walk"))
	var to := beh.ground_near(_forage_habitat(), pos, _vr(a, "dist_m", [3, 10]))
	if gait == "run":
		# Dashes: a run, a stop, another run.
		var mid := pos.lerp(to, _rng.randf_range(0.35, 0.65))
		beats.append({"a": "run", "to": mid, "gait": "run"})
		beats.append({"a": "sit" if _rng.randf() < 0.5 else "look", "sec": _rng.randf_range(0.4, 1.6)})
		beats.append({"a": "tail_flick", "sec": 0.6})
	beats.append({"a": gait, "to": to, "gait": gait})
	if _rng.randf() < 0.5:
		beats.append({"a": "look", "sec": _rng.randf_range(1.0, 3.0)})


func _do_watch(a: Dictionary) -> void:
	var act := String(a.get("action", "idle" if sp.body == "heron" else "look"))
	var total := _r(a, "sec", [3, 8])
	var parts := _rng.randi_range(1, 3)
	for i in parts:
		beats.append({"a": act, "sec": total / float(parts), "face": facing if i == 0 or _rng.randf() < 0.5 else -facing})
		if sp.id == "deer" and _rng.randf() < 0.4:
			beats.append({"a": "ear_flick", "sec": 0.5})


func _do_groom(a: Dictionary) -> void:
	if sp.body == "heron":
		beats.append_array(SceneHeron.preen(self, 1))
		if _rng.randf() < 0.4:
			beats.append({"a": "shake", "sec": SceneHeron.anim_sec(self, "shake", 1.1)})
		return
	var total := _r(a, "sec", [2, 6])
	beats.append({"a": "groom", "sec": total * 0.6})
	if _rng.randf() < 0.5:
		beats.append({"a": "look", "sec": _rng.randf_range(0.6, 1.6)})
	beats.append({"a": "groom", "sec": total * 0.4})


func _do_rest(a: Dictionary) -> void:
	var act := String(a.get("action", "lie"))
	var total := _r(a, "sec", [15, 50])
	beats.append({"a": "look", "sec": _rng.randf_range(1.0, 2.5)})
	beats.append({"a": act, "sec": total * 0.55})
	beats.append({"a": act, "sec": 0.1})
	beats.append({"a": "ear_flick", "sec": 0.5})
	beats.append({"a": act, "sec": total * 0.45})
	beats.append({"a": "look", "sec": _rng.randf_range(1.0, 2.0)})


## A heron fishing (issue 238): `SceneHeron.hunt` from the species' `hunt` numbers.
func _do_stalk(_a: Dictionary) -> void:
	beats.append_array(SceneHeron.hunt(self))
	if beats.is_empty():
		beats.append({"a": "idle", "sec": _rng.randf_range(2.0, 4.0)})


## A fox mousing: trot, stop dead, head cocked at the grass, then the high pounce.
func _do_mouse(a: Dictionary) -> void:
	var g := _forage_habitat()
	for i in _ri(a, "bouts", [1, 3]):
		var to := beh.ground_near(g, _last_to(), Vector2(2.0, 8.0))
		beats.append({"a": "trot", "to": to, "gait": "trot"})
		beats.append({"a": "look", "sec": _r(a, "freeze_sec", [1.5, 5])})
		if _rng.randf() < 0.75:
			var dir := facing
			var p := beh.ppm(band, to.y)
			var land := beh.on_ground(g, to + Vector2(dir * 0.8 * p, 0))
			if absf(land.x - to.x) < 0.4 * p:
				# No room that way on the strip: it pounces the other way.
				land = beh.on_ground(g, to - Vector2(dir * 0.8 * p, 0))
			beats.append({"a": "strike", "to": land, "speed": 1.15, "fx": "pounce", "max_sec": 0.9})
			beats.append({"a": "graze", "sec": _rng.randf_range(1.0, 2.5)})
			if _rng.randf() < float(a.get("catch_chance", 0.3)):
				beats.append({"a": "sit", "sec": _rng.randf_range(2.0, 5.0)})


func _do_bask(a: Dictionary) -> void:
	var total := _r(a, "sec", [60, 200])
	while total > 0.0:
		var chunk := minf(total, _rng.randf_range(15.0, 50.0))
		beats.append({"a": "bask", "sec": chunk})
		total -= chunk
		if total > 0.0:
			beats.append({"a": "look", "sec": _rng.randf_range(1.0, 3.0)})


func _do_swim(_a: Dictionary) -> void:
	var path: Array = _route.get("path", [])
	if not path.is_empty() and pos.distance_to(path[1]) > 4.0:
		beats.append({"a": "swim", "to": path[1], "speed": sp.speed("swim")})
	else:
		stay = 0.0
		beats.append({"a": "look", "sec": _rng.randf_range(0.5, 1.5)})


## A squirrel up the oak: a dash to the trunk, up in hitches, out along the long branch to sit and
## groom, and back down.
func _do_climb(_a: Dictionary) -> void:
	_route = beh.climb_route()
	var trunk: PackedVector2Array = _route.get("trunk", PackedVector2Array())
	var branch: PackedVector2Array = _route.get("branch", PackedVector2Array())
	if trunk.size() < 2:
		beats.append({"a": "look", "sec": 1.0})
		return
	beats.append({"a": "run", "to": trunk[0], "gait": "run"})
	beats.append({"a": "look", "sec": _rng.randf_range(0.3, 1.0)})
	for i in range(1, trunk.size()):
		var mid := trunk[i - 1].lerp(trunk[i], 0.5)
		beats.append({"a": "climb", "to": mid, "speed": sp.speed("climb"), "climb": "up", "aloft": true})
		if _rng.randf() < 0.4:
			beats.append({"a": "climb", "sec": _rng.randf_range(0.3, 1.0), "climb": "up"})
		beats.append({"a": "climb", "to": trunk[i], "speed": sp.speed("climb"), "climb": "up"})
	var out := trunk[-1]
	if not branch.is_empty():
		var ordered := Array(branch)
		ordered.sort_custom(func(p: Vector2, q: Vector2) -> bool: return p.x > q.x)
		var k := _rng.randi_range(0, mini(ordered.size() - 1, 4))
		for i in k + 1:
			beats.append({"a": "run", "to": ordered[i], "gait": "run"})
			if _rng.randf() < 0.35:
				beats.append({"a": "sit", "sec": _rng.randf_range(0.4, 1.4)})
		out = ordered[k]
	beats.append({"a": "sit", "sec": _rng.randf_range(3.0, 9.0)})
	beats.append({"a": "tail_flick", "sec": 0.8})
	if _rng.randf() < 0.6:
		beats.append({"a": "groom", "sec": _rng.randf_range(2.0, 5.0)})
	beats.append({"a": "look", "sec": _rng.randf_range(1.0, 3.0)})
	if not branch.is_empty():
		beats.append({"a": "run", "to": trunk[-1], "gait": "run"})
	for i in range(trunk.size() - 2, -1, -1):
		beats.append({"a": "climb", "to": trunk[i], "speed": sp.speed("climb") * 1.2, "climb": "down"})
	beats.append({"a": "sit", "sec": _rng.randf_range(0.5, 1.5), "aloft": false})


## A follower (a fawn, a second raccoon, a turtle that came along) keeps near its leader.
func _follow() -> void:
	var p := ppm()
	var d := pos.distance_to(leader.pos) / p
	if sp.body == "fish":
		# A loose group (a school, closer) keeps around its leader; one just behind it hangs on a
		# beat rather than turning round for a few points.
		var f := sp.range_of("follow_pt", [8, 24])
		var near := _slot_point(leader.facing)
		if not beh.in_swim(near, _half()):
			near = pos
		var dx := near.x - pos.x
		var close := pos.distance_to(leader.pos) < f.y * 1.5
		if pos.distance_to(near) < f.x or (close and signf(dx) != facing and absf(dx) < f.y):
			beats.append({"a": "swim", "sec": _rng.randf_range(0.6, 2.0), "rate": 0.5})
		else:
			var speed := sp.speed("swim") * clampf(pos.distance_to(near) / (f.y * 2.0), 0.8, 2.2)
			beats.append({"a": "swim", "to": near, "speed": speed, "max_sec": 10.0})
		return
	if sp.body == "turtle":
		if band == "water" and not _spot.is_empty():
			beats.append({"a": "walk", "to": _spot["at"], "speed": sp.speed("walk"), "band": String(_spot["band"]), "gait": "walk"})
		else:
			beats.append({"a": "bask", "sec": _rng.randf_range(10.0, 40.0)})
			beats.append({"a": "look", "sec": _rng.randf_range(1.0, 2.5)})
		return
	if spacing_m != Vector2.ZERO:
		_follow_herd()
		return
	if d > 6.0 or (leader.is_moving() and d > 3.5):
		var off := Vector2(-leader.facing * _rng.randf_range(2.0, 4.5) * p, _rng.randf_range(-7.0, 5.0))
		var gait := "trot" if d > 9.0 else "walk"
		var to := leader.pos + off
		if _on_ground():
			to = beh.on_ground(habitat, to)
		beats.append({"a": gait, "to": to, "gait": gait, "max_sec": 12.0})
	else:
		var act := "graze" if leader.look.action in ["graze", "drink"] or _rng.randf() < 0.6 else "look"
		if leader.look.action == "drink":
			act = "drink" if _rng.randf() < 0.5 else "graze"
		beats.append({"a": act, "sec": _rng.randf_range(1.5, 5.0)})
		if _rng.randf() < 0.3:
			beats.append({"a": "ear_flick" if _rng.randf() < 0.5 else "tail_flick", "sec": 0.6})


## A member of a natural group (issue 320) keeps `spacing_m` from whom it follows: it moves up when
## left behind (a fawn trots), steps off when crowded, comes down to drink beside its leader, and
## otherwise lives its own beats (grazing, a look round, ears and tail), not the leader's.
func _follow_herd() -> void:
	var p := ppm()
	var to_at := leader.heading_to()
	var d := absf(pos.x - to_at.x) / p
	if leader.activity == "drink" and leader.state == "living" and herd_role != "trail" and activity != "drink":
		activity = "drink"
		_drink_beside(leader)
		return
	if activity == "drink":
		activity = ""
	var behind := d > spacing_m.y * 1.15 or (leader.is_moving() and d > spacing_m.y * 0.9)
	var crowded := _herd_clearance(pos) < -0.2
	if behind or crowded:
		var side := signf(pos.x - to_at.x)
		var to := herd_spot(to_at, side if side != 0.0 else -leader.facing)
		var gait := "trot" if d > spacing_m.y * 2.0 or (young and d > spacing_m.y * 1.4) else "walk"
		beats.append({"a": gait, "to": to, "gait": gait, "max_sec": 20.0})
		if _rng.randf() < 0.5:
			beats.append({"a": "look", "sec": _rng.randf_range(0.6, 2.0)})
		return
	var h: Dictionary = sp.data.get("herd", {})
	var roll := _rng.randf()
	if herd_role == "trail" and roll < 0.45:
		# The buck behind the does watches them.
		var face := signf(leader.pos.x - pos.x)
		beats.append({"a": "look", "sec": _rng.randf_range(2.0, 5.0), "face": face if face != 0.0 else facing})
	elif roll < 0.7:
		if _rng.randf() < 0.4:
			var side := beh.water_side(band)
			var toward := (side if _rng.randf() < float(h.get("water_face_chance", 0.5)) else -side) if side != 0.0 else 0.0
			var step := beh.ground_near(_forage_habitat(), pos, Vector2(0.3, 1.2), toward)
			if _herd_clearance(step) > 0.0:
				beats.append({"a": "walk", "to": step, "gait": "walk"})
		beats.append({"a": "graze", "sec": _rng.randf_range(2.5, 8.0)})
	else:
		beats.append({"a": "look", "sec": _rng.randf_range(1.0, 3.5)})
	if _rng.randf() < 0.3:
		beats.append({"a": "ear_flick" if _rng.randf() < 0.5 else "tail_flick", "sec": 0.6})


## Down to the water beside `other` (its spacing from it along the edge), then drinks in short
## draughts with its head coming up between.
func _drink_beside(other: SceneCreature) -> void:
	var shore := beh.lane_of("shore_mid" if band == "mid" else "shore_far")
	var at := other.water_spot()
	if shore.is_empty():
		beats.append({"a": "look", "sec": _rng.randf_range(1.0, 2.5)})
		return
	var p := ppm()
	var best := at
	var best_score := -INF
	for i in 8:
		var s := signf(pos.x - at.x)
		if s == 0.0 or _rng.randf() < 0.25:
			s = -1.0 if _rng.randf() < 0.5 else 1.0
		var lo := spacing_m.x if young else minf(spacing_m.x, 3.0)
		var x := SceneVariety.fold(at.x + s * _rng.randf_range(lo, lo * 1.6) * p, shore[0].x + 6.0, shore[-1].x - 6.0)
		var q := Vector2(x, SceneBehaviour.lane_y(shore, x))
		var score := minf(_herd_clearance(q), 2.0)
		if score > best_score:
			best_score = score
			best = q
	_to_water(best, false)
	for i in _rng.randi_range(1, 3):
		beats.append({"a": "drink", "sec": _rng.randf_range(2.5, 6.0)})
		beats.append({"a": "look", "sec": _rng.randf_range(0.8, 2.2)})
	beats.append({"a": "walk", "to": beh.ground_near(_forage_habitat(), best, Vector2(0.8, 2.5)), "gait": "walk"})


## Walks to `edge` at the water so that it arrives facing the water (the places' `water_side`), with
## a cautious stop on the way when `wary` (the head up, the ears going), and a look before it drinks.
func _to_water(edge: Vector2, wary: bool) -> void:
	var h: Dictionary = sp.data.get("herd", {})
	var side := beh.water_side(band)
	var p := ppm()
	var from := _last_to() if not beats.is_empty() else pos
	if side != 0.0 and signf(edge.x - from.x) != side:
		# Come round so the last steps are toward the water, rather than flipping on the spot.
		var lane := beh.lane_of(_forage_habitat())
		var pre_x := edge.x - side * _rng.randf_range(0.8, 1.6) * p
		if not lane.is_empty() and pre_x > lane[0].x and pre_x < lane[-1].x:
			beats.append({"a": "walk", "to": beh.on_ground(_forage_habitat(), Vector2(pre_x, lerpf(from.y, edge.y, 0.4))), "gait": "walk"})
			from = beats[-1]["to"]
	var a: Dictionary = h.get("approach", {})
	if wary and _rng.randf() < float(a.get("pause_chance", 0.0)):
		var mid := from.lerp(edge, _rng.randf_range(0.4, 0.7))
		beats.append({"a": "walk", "to": mid, "gait": "walk"})
		beats.append({"a": "look", "sec": _r(a, "look_sec", [1.0, 3.0])})
		beats.append({"a": "ear_flick", "sec": 0.6})
	beats.append({"a": "walk", "to": edge, "gait": "walk"})
	var face := side if side != 0.0 and signf(edge.x - from.x) != side else 0.0
	var look := {"a": "look", "sec": _rng.randf_range(0.8, 2.5)}
	if face != 0.0:
		look["face"] = face
	beats.append(look)


## Keeping watch (issue 320): about to drink while every other of its group near the water has its
## head down, it holds its head up instead until one of them lifts (a little after), within
## `herd.watch.max_sec`. Returns the seconds to watch, or 0 to drink now.
func _watch_for() -> float:
	var w: Dictionary = sp.data.get("herd", {}).get("watch", {})
	if herd.size() < 2 or w.is_empty() or _watched_sec >= float(w.get("max_sec", 12.0)):
		return 0.0
	var p := ppm()
	var near := 0
	var soonest := INF
	for o in herd:
		var c: SceneCreature = o
		if c == self or not is_instance_valid(c) or c.state != "living" or c.band != band or c.alpha < 0.5:
			continue
		if absf(c.pos.x - pos.x) / p > 15.0:
			continue
		near += 1
		if String(c.beat.get("a", "")) != "drink":
			return 0.0
		soonest = minf(soonest, maxf(0.0, float(c.beat.get("sec", 1.0)) - c.beat_t))
	if near == 0 or _rng.randf() >= float(w.get("chance", 1.0)):
		return 0.0
	var extra: Array = w.get("extra_sec", [0.4, 1.5])
	return minf(soonest + _rng.randf_range(float(extra[0]), float(extra[1])), float(w.get("max_sec", 12.0)) - _watched_sec + 0.5)


# --- Senses -------------------------------------------------------------------------------------

## Looks at the others: flees what it fears inside its flight distance, scolds what it scolds,
## stops to watch what it is wary of.
func perceive(others: Array, _flocks: Array) -> void:
	if state == "gone" or state == "fleeing" or alpha < 0.2:
		return
	var here := world()
	var skittish := 1.0 + beh.scene.env.wind.mean * 0.6
	for o in others:
		var other: SceneCreature = o
		if other == self or other.sp == sp or other.alpha < 0.3 or other.state == "gone":
			continue
		# Two in the cut-away (a bass, a turtle or a snake swimming by a sunfish) are side-on to each
		# other: straight across the water, and a fright there is a dart, not leaving the pond.
		var under := sp.body == "fish" and (other.sp.body == "fish" or other.pos.y > beh.cut_y() + 4.0)
		var d := _dist_m(other) if under else here.distance_to(other.world())
		var f := sp.fear_of(other.sp.id) * skittish
		if f > 0.0 and d < f and under:
			scatter(other.pos, "%s at %.2f m" % [other.sp.id, d])
			continue
		var room := float(sp.data.get("room", {}).get(other.sp.id, 0.0))
		if room > 0.0 and d < room and beh.t > _room_until and state == "living":
			_give_room(other)
			continue
		if f > 0.0 and d < f:
			# A squirrel escapes up the tree and scolds from there rather than running off.
			if sp.scold_of(other.sp.id) > 0.0 and state == "living":
				if beh.t > _scold_until:
					_scold(other)
				continue
			flee(other.pos, "%s at %.0f m" % [other.sp.id, d])
			return
		var s := sp.scold_of(other.sp.id)
		if s > 0.0 and d < s and beh.t > _scold_until and state == "living":
			_scold(other)
			continue
		var w := sp.watch_of(other.sp.id)
		if w > 0.0 and d < w and float(_watched.get(other.get_instance_id(), -1.0)) < beh.t and state == "living":
			_watched[other.get_instance_id()] = beh.t + _rng.randf_range(20.0, 45.0)
			_interrupt([{"a": "look", "sec": _rng.randf_range(2.0, 5.0), "face_to": other.pos}])
			beh.note("%s watches %s" % [sp.id, other.sp.id], sp.id)


## Metres to `other`: in the cut-away, straight across the water (both are side-on there).
func _dist_m(other: SceneCreature) -> float:
	# In metres as drawn: fish are shown larger than life, so a bass's reach is measured at its drawn size.
	var across := pos.distance_to(other.pos) / maxf(0.01, ppm() * sp.show_scale(band, ppm() * beh.scene.density))
	if sp.body == "fish" and other.sp.body == "fish":
		# Two fish far apart front to back are not near, however they overlap on the screen.
		var gap := (depth_z - other.depth_z) * float(_depth_tuning()["span_m"])
		return sqrt(across * across + gap * gap)
	return across


## Eases off out of a big fish's way, unhurried: the old bass, a catfish coming along the bed.
func _give_room(other: SceneCreature) -> void:
	_room_until = beh.t + float(beh.tuning["fish"]["room_every_sec"])
	var p := ppm()
	var dir := signf(pos.x - other.pos.x) if absf(pos.x - other.pos.x) > 0.5 else -other.facing
	var away := pos + Vector2(dir * _rng.randf_range(0.4, 0.8) * p, signf(pos.y - other.pos.y) * _rng.randf_range(0.05, 0.2) * p)
	if not beh.in_swim(away, _half()):
		var q: Variant = beh.fish_point(zones(), pos.x + dir * 0.6 * p, 0.4 * p, _half())
		if q == null:
			return
		away = q
	beh.note("%s gives %s room" % [sp.id, other.sp.id], sp.id)
	_interrupt([{"a": "swim", "to": away, "speed": sp.speed("swim") * 1.3, "max_sec": 6.0}], true)


func _scold(other: SceneCreature) -> void:
	_scold_until = beh.t + _rng.randf_range(18.0, 30.0)
	beh.note("%s scolds %s" % [sp.id, other.sp.id], sp.id)
	var list: Array = []
	var on := ""
	var trunk := PackedVector2Array()
	if not _aloft:
		# Up the trunk first, to a safe height, and scold from there.
		trunk = beh.climb_route().get("trunk", PackedVector2Array())
		if trunk.size() >= 2:
			list.append({"a": "run", "to": trunk[0], "gait": "run"})
			list.append({"a": "climb", "to": trunk[0].lerp(trunk[1], 0.6), "speed": sp.speed("climb") * 1.4, "climb": "up", "aloft": true})
			on = "up"
	for i in _rng.randi_range(3, 6):
		var flick := {"a": "tail_flick", "sec": _rng.randf_range(0.6, 1.0), "fx": "chatter" if i == 0 else "", "climb": on}
		if on == "":
			flick["face_to"] = other.pos
		list.append(flick)
		list.append({"a": "look", "sec": _rng.randf_range(0.4, 1.2), "climb": on})
	if on == "up":
		list.append({"a": "climb", "to": trunk[0], "speed": sp.speed("climb"), "climb": "down"})
		list.append({"a": "sit", "sec": 0.8, "aloft": false})
	_interrupt(list, true)


## An alarm went off `closeness` (0 at the source .. 1 at the edge of earshot) away.
func hear_alarm(at: Vector2, closeness: float, level: String = "flee") -> void:
	if state == "gone" or state == "fleeing":
		return
	if String(beat.get("hawk", "")) == "freeze":
		# Frozen neck-up under the hawk (issue 311): the scatter's wings change nothing.
		return
	if sp.body == "turtle" and level == "flee":
		flee(at, "a plop")
		return
	var heed := float(sp.data.get("heeds", 0.5))
	if heed <= 0.0:
		return
	# Uneasy for a while already (not this very moment) and now something is running: go.
	var settled_in := UNEASY_SEC - uneasy
	if level == "flee" and uneasy > 0.0 and settled_in > 1.5 and _rng.randf() < heed * (1.0 - closeness) * 0.7:
		flee(at, "second alarm")
		return
	if uneasy <= 0.0 or level == "flee":
		uneasy = UNEASY_SEC
	if _rng.randf() < heed:
		var list: Array = [{"a": "look", "sec": _rng.randf_range(1.5, 4.0), "face_to": at}]
		if sp.id == "deer":
			list.append({"a": "ear_flick", "sec": 0.5})
			list.append({"a": "tail_flick", "sec": 0.8})
		_interrupt(list)


## The beats `list` come now; the current one ends unless it is a flight or a climb (those finish).
func _interrupt(list: Array, replace: bool = false) -> void:
	if state == "gone" or state == "fleeing":
		return
	if beat.has("prey"):
		# Prey in the bill: it is swallowed first, then whatever came up.
		var at := 0
		while at < beats.size() and (beats[at] as Dictionary).has("prey"):
			at += 1
		if replace:
			beats = beats.slice(0, at)
		for i in range(list.size() - 1, -1, -1):
			beats.insert(at, list[i])
		return
	if replace:
		beats.clear()
	for i in range(list.size() - 1, -1, -1):
		beats.push_front(list[i])
	if not beat.has("path") and _climb == "" and not (beat.has("band")) and not bool(beat.get("flip", false)):
		beat = {}


## Turn end: a still moment.
func pause() -> void:
	if state != "living":
		return
	_interrupt([{"a": "idle" if sp.body in ["heron", "turtle"] else "look", "sec": _rng.randf_range(2.0, 4.5)}])


func can_gesture() -> bool:
	return state == "living" and alpha > 0.8 and not beat.has("path") and _climb == ""


## A beat of a big moment's tail (issue 239), soon after it came in: a heron that has just landed
## shakes down and preens, then stands tall and looks about before it starts to hunt; anyone else
## does its telling small act.
func tail(beat: int) -> void:
	match sp.body:
		"heron":
			# Down from the glide: a feather shake, a preen, then it stands tall and looks about.
			match beat:
				0:
					_interrupt([{"a": "shake", "sec": SceneHeron.anim_sec(self, "shake", 1.1)}, {"a": "idle", "sec": 1.0}])
				1:
					_interrupt(SceneHeron.preen(self, 1))
				_:
					_interrupt([{"a": "look", "sec": _rng.randf_range(1.8, 3.0)}, {"a": "idle", "sec": 0.8}])
		_:
			gesture()


## Turn start, with this creature as the moment: its most telling small act.
func gesture() -> void:
	match sp.id:
		"great_blue_heron":
			if SceneHeron.bill_in_water(self, pos, facing):
				_interrupt(SceneHeron.strike_beats(self, true))
			else:
				_interrupt([{"a": "look", "sec": 2.0}, {"a": "idle", "sec": 1.0}])
		"deer":
			_interrupt([{"a": "look", "sec": 2.5}, {"a": "ear_flick", "sec": 0.5}, {"a": "tail_flick", "sec": 0.8}, {"a": "look", "sec": 1.5}])
		"red_fox":
			var p := ppm()
			_interrupt([{"a": "look", "sec": 1.6}, {"a": "strike", "to": pos + Vector2(facing * 0.8 * p, 0), "speed": 1.15, "fx": "pounce", "max_sec": 0.9},
					{"a": "graze", "sec": 1.5}])
		"gray_squirrel":
			_interrupt([{"a": "tail_flick", "sec": 0.8}, {"a": "sit", "sec": 1.2}, {"a": "tail_flick", "sec": 0.8}])
		_:
			_interrupt([{"a": "look", "sec": 2.5}])
