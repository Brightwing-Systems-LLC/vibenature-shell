class_name SceneBehaviour
extends Node2D

## The living scene's animals (Skypatch issue 104):
## the director decides who comes; each comes as an agent with needs and habits (`SceneCreature`,
## a flock as `SceneFlock`) that lives in the kit's places; they notice each other, and fear, alarm
## and curiosity pass between them (a deer's approach puts the ground birds up, the squirrel scolds
## the fox, one turtle's plop sends the others in, a bear clears the pond).
##
## Geometry: everything is in scene points, like the rest of the scene. Each band's `px_per_m`
## (interpolated by y where a band gives `y_to`) says how big a metre is there; from it every
## creature has a rough place in the world (`world_of`: metres across, metres away), so distances
## between animals mean something even across bands. Fish rises are ambient and drawn here.
##
## Claude events come in as `turn_started` (any session's hand-off) / `turn_ended` (that session's
## turn ends) / `agents_idle` (nobody works now), and become a moment or a calm beat (issue 308).

signal happened(entry: Dictionary)
## A typed scene event for the sound engine (`sound_event`): {kind, species, actor, pos, band, depth_m,
## under, size, t}. Only the scene's own bodies emit it; nothing from an agent event is in it.
signal sounded(event: Dictionary)

## The kit's places, in the scene package (contract §8): `behaviour/places/<kit>.json`.
const PLACES_DIR := "behaviour/places"

var scene: LivingScene
var tuning: Dictionary = {}
var species: Dictionary = {}
var director: SceneDirector
var creatures: Array = []
var flocks: Array = []
## What happened, newest last: [{t, what, species}] (for clips, tests and the debug panel).
var events: Array = []
var places: Dictionary = {}
var rng := RandomNumberGenerator.new()
var t := 0.0
## Seconds since the epoch, for rarity across restarts; the snapshot path pins it.
var unix_clock: Callable
var on := true
var _perceive_left := 0.0
var _rises: SceneRises
## Dragonflies and damselflies (Skypatch issue 116).
var odonata: SceneOdonata
## The big moments that play themselves (issue 410), each registered by its own data file
## (issue 427): the species file whose `player`
## names a code `body` says how it is made (`tuning`, `seed`, `setup`) and in which `order` it steps; every
## species whose `plays` names it starts it (`player.start`, `player.start_args`). Keyed by `plays`.
var _moments := {}
## Shortcuts the older moments' own tests, probes and clips use (untyped: each is a code body in the scene
## package, contract §8); a new moment needs none (`moment(plays)`).
var bass_leap:
	get: return _moments.get("bass_leap")
var hawk_pass:
	get: return _moments.get("hawk_pass")
var geese:
	get: return _moments.get("goose_landing")
var osprey:
	get: return _moments.get("osprey_dive")
var kingfisher:
	get: return _moments.get("kingfisher_hunt")
var beaver:
	get: return _moments.get("beaver_swim")
var otters:
	get: return _moments.get("otter_play")
var deer_bound:
	get: return _moments.get("deer_bound")
var swallows:
	get: return _moments.get("swallow_skim")
var hatch:
	get: return _moments.get("mayfly_hatch")
var wood_ducks:
	get: return _moments.get("wood_ducks")
var turtles:
	get: return _moments.get("turtle_plop")
var weather_beats:
	get: return _moments.get("gust_sweep")
var shower_beats:
	get: return _moments.get("passing_shower")
var starlings:
	get: return _moments.get("starling_murmuration")
var _water_regions := {}
var _density := 1.0
## The songbird cast (Skypatch issue 134): a clip or the
## debug panel may name the next party's species; a clip may pin the month.
var next_cast := ""
## A clip may name how the next heron comes ("glide" or "walk"); used once.
var next_entrance := ""
## A clip may name the next glide-in's approach (`heron_glide.approaches`, issue 272); used once.
var next_approach := ""
var month_override := 0
## A clip may name the next natural group's kind (issue 320: `herd` in the species data).
var next_herd := ""
## A clip may name the next basker's spot (an index into the places' `bask`, issue 334); used once.
var next_bask := -1
var _trunk_edges := {}
var _stocked := false
var _grips := {}
## Where sightings go (the book's field guide, issue 177); null records nothing.
var sightings: SceneSightings


func setup(owner_scene: LivingScene, behaviour_tuning: Dictionary, seed: int, data_dir: String = SceneSpecies.DIR) -> void:
	scene = owner_scene
	tuning = behaviour_tuning
	name = "Behaviour"
	rng.seed = seed
	_density = scene.density
	species = SceneSpecies.load_all(data_dir)
	director = SceneDirector.new(tuning["director"], species, seed + 1)
	var pkg := ScenePackages.scene(scene.kit.id)
	var parsed = pkg.read_json(PLACES_DIR.path_join(scene.kit.id + ".json")) if pkg != null else null
	if parsed is Dictionary:
		places = parsed
	for region in scene.kit.water.get("regions", []):
		var pts := PackedVector2Array()
		for p in region.get("polygon", []):
			pts.append(Vector2(float(p[0]), float(p[1])) / _density)
		_water_regions[String(region.get("id", ""))] = pts
	_rises = SceneRises.new()
	_rises.setup(self)
	scene.actor_layer("water").add_child(_rises)
	odonata = SceneOdonata.new()
	odonata.setup(self, tuning["odonata"], seed + 3)
	add_child(odonata)
	_moments = make_moments(self, species, tuning, seed)


## Every big moment that plays itself, made from the data (issue 427): one per species whose `player`
## block names its code `body` (contract §8), keyed by its `plays`, set up with the behaviour tuning's `tuning` block
## (default: the `plays`), `seed` plus the behaviour's seed and any `setup` arguments, in `order`.
static func make_moments(beh: SceneBehaviour, all: Dictionary, behaviour_tuning: Dictionary, seed: int) -> Dictionary:
	var out := {}
	var pkg := ScenePackages.scene()
	for id in moment_owners(all):
		var sp: SceneSpecies = all[id]
		var mb: Dictionary = sp.data["player"]
		var plays := String(sp.data.get("plays", id))
		var script: Script = player_script(mb)
		if script == null:
			continue
		var m: Object = script.new()
		if m is PackageBody:
			(m as PackageBody).package = pkg
			(m as PackageBody).sounds_to = beh
		m.callv("setup", [beh, behaviour_tuning.get(String(mb.get("tuning", plays)), {}), seed + int(mb.get("seed", 0))] + Array(mb.get("setup", [])))
		out[plays] = m
	return out


## The script that plays a moment: the scene package's code body its `player.body` names (contract §8,
## through the gate; null when the gate turned it away). Data never names a script by path.
static func player_script(mb: Dictionary) -> Script:
	return ScenePackages.body(String(mb["body"])) if mb.has("body") else null


## The species that own a moment's player (`player.body`), in their `order` (then by id).
static func moment_owners(all: Dictionary) -> Array:
	var ids: Array = []
	for id in all:
		var sp: SceneSpecies = all[id]
		var mb: Dictionary = sp.data.get("player", {})
		if sp.body == "moment" and mb.has("body"):
			ids.append(id)
	ids.sort_custom(func(a: String, b: String) -> bool:
		var oa := int(all[a].data["player"].get("order", 1000))
		var ob := int(all[b].data["player"].get("order", 1000))
		return oa < ob if oa != ob else a < b)
	return ids


## Whether a big moment keeps songbird parties away now (the hawk about, issue 330: `PackageBody.keeps_birds_away`).
func keeps_birds_away() -> bool:
	for m in _moments.values():
		if m != null and m.has_method("keeps_birds_away") and m.keeps_birds_away():
			return true
	return false


## Whether a big moment keeps `species_id` from arriving now (`PackageBody.keeps_away`).
func kept_away(species_id: String) -> bool:
	for m in _moments.values():
		if m != null and m.has_method("keeps_away") and m.keeps_away(species_id):
			return true
	return false


## The moment `plays` names (null if none is registered).
func moment(plays: String) -> Object:
	return _moments.get(plays)


# --- Time ---------------------------------------------------------------------------------------

func step(dt: float) -> void:
	t += dt
	if on and not _stocked:
		_stocked = true
		stock_fish()
	if on:
		for happening in director.tick(dt, context()):
			_happen(happening)
	_perceive_left -= dt
	var perceive := _perceive_left <= 0.0
	if perceive:
		_perceive_left = float(tuning["perceive_every_sec"])
	var tint := scene.light_tint()
	for c in creatures.duplicate():
		var creature: SceneCreature = c
		if perceive:
			creature.perceive(creatures, flocks)
		creature.step(dt, tint)
		if creature.state == "gone":
			_remove(creature)
	for f in flocks.duplicate():
		var flock: SceneFlock = f
		if perceive:
			flock.perceive(creatures)
		flock.step(dt, tint)
		if flock.done():
			flock.free_birds()
			flocks.erase(flock)
			note("flock gone", flock.sp.id)
	_rises.step(dt)
	odonata.step(dt, tint)
	for m in _moments.values():
		m.step(dt)
	_deliver_alarms()
	if not _lineup.is_empty():
		_step_lineup(dt)


func context() -> Dictionary:
	var env := scene.env
	return {
		"minute": env.minute, "dawn": float(env.light.dawn_minutes), "dusk": float(env.light.night_minutes),
		"weather": weather(), "unix": now_unix(), "present": present(), "day": local_day(), "month": month(),
		"big_playing": big_moment_playing(),
	}


## The big moments that play themselves, keyed by the `plays` of their data (issue 410): one at a time
## across all of them. Each registers itself from its own data file (`make_moments`, issue 427);
## `test_moment_guard` fails for a moment whose data does not.
func big_moments() -> Dictionary:
	return _moments


## Whether any of `big_moments` is playing now.
func big_moment_playing() -> bool:
	for m in big_moments().values():
		if m != null and m.active():
			return true
	return false


## The local date of `now_unix` (the daily cap on big moments counts per day).
func local_day() -> String:
	var bias := int(Time.get_time_zone_from_system().get("bias", 0)) * 60
	return Time.get_date_string_from_unix_time(int(now_unix()) + bias)


func weather() -> Dictionary:
	var env := scene.env
	return {"rain": env.rain, "wind": env.wind.mean, "fog": maxf(env.fog, env.mist), "sunshine": env.sunshine(), "daylight": env.daylight()}


func now_unix() -> float:
	return float(unix_clock.call()) if unix_clock.is_valid() else Time.get_unix_time_from_system()


func present() -> Dictionary:
	var out := {}
	for c in creatures:
		var id: String = (c as SceneCreature).sp.id
		out[id] = int(out.get(id, 0)) + 1
	for f in flocks:
		var id: String = (f as SceneFlock).sp.id
		out[id] = int(out.get(id, 0)) + 1
	for f in odonata.flies:
		out[f["id"]] = int(out.get(f["id"], 0)) + 1
	return out


func note(what: String, who: String = "") -> void:
	var entry := {"t": snappedf(t, 0.1), "what": what, "species": who}
	events.append(entry)
	if events.size() > 400:
		events.pop_front()
	happened.emit(entry)


## A typed scene event (proposal 2026-10-21-sound-in-packages §2, issue 413), beside the text log: `kind`
## from the shell's vocabulary (`SceneSoundscape.VOCABULARY`), the `actor` that makes it (the engine plays
## it only while that is drawn on screen), and in `params` any of `pos` (scene points; default the actor's),
## `species`, `band`, `depth_m` (default from the band's scale at `pos`), `under` (in the cut-away), `size`
## (true length in metres). Sound is the engine's business: this only says what happened, where.
func sound_event(kind: String, actor: Object = null, params: Dictionary = {}) -> void:
	if not sounded.has_connections():
		return
	var live := actor != null and is_instance_valid(actor)
	var pos: Variant = params.get("pos")
	if pos == null and live:
		pos = actor.get("pos") if "pos" in actor else (actor.get("position") if actor is Node2D else null)
	if not pos is Vector2:
		pos = Vector2.INF
	var band := String(params.get("band", actor.get("band") if live and "band" in actor else "water"))
	var sp := String(params.get("species", ""))
	if sp == "" and live and "sp" in actor and actor.get("sp") is SceneSpecies:
		sp = (actor.get("sp") as SceneSpecies).id
	var depth := 0.0
	if params.has("depth_m"):
		depth = float(params["depth_m"])
	elif pos != Vector2.INF:
		depth = depth_of(ppm(band, (pos as Vector2).y))
	sounded.emit({"kind": kind, "species": sp, "actor": actor, "pos": pos, "band": band, "depth_m": depth,
			"under": bool(params.get("under", false)), "size": float(params.get("size", 0.0)), "t": t})


func _happen(h: Dictionary) -> void:
	var id := String(h["species"])
	match String(h["why"]):
		"ambient":
			var sp: SceneSpecies = species[id]
			if sp.body == "songbird" and bool(sp.data.get("lands", false)):
				# A bird or two dropping in between the bigger moments; else they go over.
				if int(present().get(id, 0)) < int(sp.data.get("max_present", 1)) and env_allows_birds() and spawn(id, "ambient"):
					note("%s drop in" % id, id)
				else:
					_pass_over("passing_birds" if species.has("passing_birds") else id)
			elif sp.body == "songbird":
				_pass_over(id)
			elif sp.body == "odonata":
				if odonata.weather_ok():
					spawn(id, "ambient")
			elif sp.body == "fish":
				_fish_ambient(sp)
		"arrival", "moment":
			if spawn(id, String(h["why"])):
				note("%s arrives (%s)" % [id, h["why"]], id)
		"moment_small":
			small_moment()
		"tail":
			_tail(id, int(h.get("beat", 0)))


## The big moment's tail (issue 239): a small follow-up by the same animal where the eye landed
## (the heron settles and preens, the flock flits between perches). Nothing if it has gone.
func _tail(id: String, beat: int) -> void:
	if species.has(id) and (species[id] as SceneSpecies).body == "moment":
		return
	for c in creatures:
		if (c as SceneCreature).sp.id == id and (c as SceneCreature).can_gesture():
			(c as SceneCreature).tail(beat)
			note("tail %d: %s" % [beat, id], id)
			return
	for f in flocks:
		if (f as SceneFlock).sp.id == id and (f as SceneFlock).tail(beat):
			note("tail %d: %s" % [beat, id], id)
			return


## A fish's ambient roll (Skypatch issue 131): it swims into
## the cut-away (its group, if there is room for its kind and for fish at all), or, for the risers, a
## rise somewhere on the surface. A standing heron hushes them.
func _fish_ambient(sp: SceneSpecies) -> void:
	var hush := 1.0
	for other in present():
		hush *= float(sp.data.get("hushed_by", {}).get(other, 1.0))
	var fish := creatures.filter(func(c: SceneCreature) -> bool: return c.sp.body == "fish")
	var mine := fish.filter(func(c: SceneCreature) -> bool: return c.sp == sp).size()
	var room := mine < int(sp.data.get("max_swimming", 0)) and fish.size() < int(tuning["fish"]["max_total"])
	if room and underwater_point() != null and rng.randf() < float(sp.data.get("swim_in_share", 0.5)) * (1.0 if hush >= 1.0 else hush * 2.0):
		if spawn(sp.id, "ambient"):
			note("%s swim in" % sp.id, sp.id)
	elif bool(sp.data.get("rises", false)) and rng.randf() < hush:
		_rises.rise(rng.randf() < float(sp.data.get("jump_chance", 0.1)), sp)


## The pond already has its fish when the scene opens (Skypatch issue 131):
## about as many groups of each kind as its arrival rate and stay would keep there at this hour and
## weather, up to `behaviour.fish.stock_max` fish; never a rare one.
func stock_fish() -> void:
	if underwater_point() == null:
		return
	var ctx := context()
	var ids := species.keys().filter(func(id: String) -> bool:
		var sp: SceneSpecies = species[id]
		return sp.body == "fish" and sp.tier == "ambient" and float(sp.data.get("min_gap_min", 0.0)) <= 0.0)
	ids.sort()
	for i in range(ids.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var swap = ids[i]
		ids[i] = ids[j]
		ids[j] = swap
	for id in ids:
		var sp: SceneSpecies = species[id]
		var stay := sp.range_of("stay_min", [2, 6])
		var groups := director.base_rate(id, ctx) * 60.0 * float(sp.data.get("swim_in_share", 0.5)) * (stay.x + stay.y) * 0.5 * float(tuning["fish"]["stock_share"])
		var n := int(groups) + (1 if rng.randf() < fmod(groups, 1.0) else 0)
		for i in mini(n, 2):
			var fish := creatures.filter(func(c: SceneCreature) -> bool: return c.sp.body == "fish").size()
			var mine := creatures.filter(func(c: SceneCreature) -> bool: return c.sp == sp).size()
			if fish >= int(tuning["fish"]["stock_max"]) or mine >= int(sp.data.get("max_swimming", 0)):
				break
			if spawn(id, "ambient"):
				note("%s here already" % id, id)


# --- Arrivals -----------------------------------------------------------------------------------

## Brings `id` into the scene now (its group, its way in). False if it has nowhere to be.
## `habitat` picks where (a clip putting the fox on the far bank); else by the species' weights.
func spawn(id: String, why: String = "debug", habitat: String = "") -> bool:
	if not species.has(id):
		return false
	var sp: SceneSpecies = species[id]
	# No deer walks in while the deer moment plays (issue 372): a moment says what it keeps away.
	if kept_away(id):
		return false
	if sp.body == "moment" and big_moment_playing():
		# One big moment at a time (issue 410): while one plays, the hand-off is something small.
		if why == "moment":
			small_moment()
		return false
	if sp.body == "moment":
		# A moment played by animals already here (the bass leap): nothing new comes in. If it
		# cannot happen after all, something small does instead.
		var m: Object = _moments.get(String(sp.data.get("plays", "")))
		var mb: Dictionary = sp.data.get("player", {})
		if m != null and m.callv(String(mb.get("start", "start")), Array(mb.get("start_args", []))):
			return true
		if why == "moment":
			small_moment()
		return false
	if sp.body == "odonata":
		if not odonata.add(id):
			return false
		_saw(sp)
		return true
	if sp.body == "songbird":
		# No songbirds while the hawk is about (issue 330): they come back only after it has gone.
		if keeps_birds_away():
			return false
		var flock := SceneFlock.new()
		if not flock.setup(self, sp, rng.randi()):
			return false
		if why == "moment":
			flock.land_for_moment()
		flocks.append(flock)
		_saw(sp, flock.member)
		return true
	if sp.body == "fish" and underwater_point() == null:
		_rises.rise(rng.randf() < 0.5, sp)
		return true
	if habitat == "" or not sp.habitat().has(habitat):
		habitat = _pick_weighted(sp.habitat())
	if sp.data.has("herd"):
		return _spawn_herd(sp, why, habitat)
	var group := sp.range_of("group", [1, 1])
	var n := rng.randi_range(int(group.x), int(group.y))
	var leader: SceneCreature = null
	for i in n:
		var c := SceneCreature.new()
		c.why = why
		var young := false
		var young_spec: Dictionary = sp.data.get("young", {})
		if i > 0 and not young_spec.is_empty() and rng.randf() < float(young_spec.get("chance", 0.0)):
			young = true
		if not c.setup(self, sp, habitat, leader, young, rng.randi()):
			c.free()
			return i > 0
		creatures.append(c)
		if leader == null:
			leader = c
			_saw(sp)
	if why == "debug":
		director.recent.append({"id": id, "t": director.t})
		director.quiet_for = 0.0
	return true


## A natural group (issue 320, `SceneHerd`): who comes by season, each with its own sheet and role. A
## group bigger than the mid bank's strip holds comes out on the far meadow instead.
func _spawn_herd(sp: SceneSpecies, why: String, habitat: String) -> bool:
	var herd: Dictionary = sp.data["herd"]
	var mid: Dictionary = herd.get("mid", {})
	var members := SceneHerd.compose(herd, month(), rng)
	if next_herd != "":
		# A clip names the group (`herd`: a kind's id).
		for k in herd.get("kinds", []):
			if String(k["id"]) == next_herd:
				members = SceneHerd.members(herd, k, month(), rng)
		next_herd = ""
	if members.is_empty():
		return false
	if band_of(habitat) == "mid" and sp.habitat().has("ground_far"):
		var adults := members.filter(func(m: Dictionary) -> bool: return not bool(m["young"])).size()
		if adults > int(mid.get("max_adults", 99)) or members.size() > int(mid.get("max_members", 99)):
			habitat = "ground_far"
	var made: Array = []
	for i in members.size():
		var m: Dictionary = members[i]
		var c := SceneCreature.new()
		c.why = why
		c.want_sheet = String(m["sheet"])
		c.herd_role = String(m["role"])
		var spacing: Array = m["spacing"]
		var key := "fawn" if bool(m["young"]) else ("buck_pair" if String(m["role"]) == "buck" else "adult")
		if band_of(habitat) == "mid" and mid.get("spacing_m", {}).has(key) and String(m["role"]) != "trail":
			spacing = mid["spacing_m"][key]
		c.spacing_m = Vector2(float(spacing[0]), float(spacing[1]))
		var lead: SceneCreature = made[0] if not made.is_empty() else null
		if int(m["mother"]) >= 0 and int(m["mother"]) < made.size():
			c.mother = made[int(m["mother"])]
			lead = c.mother
		c.herd = made.duplicate()
		if not c.setup(self, sp, habitat, lead, bool(m["young"]), rng.randi()):
			c.free()
			return i > 0
		creatures.append(c)
		made.append(c)
		if i == 0:
			_saw(sp)
	for c in made:
		(c as SceneCreature).herd = made
	if why == "debug":
		director.recent.append({"id": sp.id, "t": director.t})
		director.quiet_for = 0.0
	return true


## Notes a sighting for the field guide (issue 177).
func _saw(sp: SceneSpecies, member: Dictionary = {}) -> void:
	if sightings == null:
		return
	var d := SceneSightings.describe(sp, member)
	sightings.saw(String(d["key"]), String(d["name"]), String(d["sheet"]), now_unix())


func _remove(c: SceneCreature) -> void:
	creatures.erase(c)
	note("%s leaves" % c.sp.id, c.sp.id)
	c.queue_free()


func _pick_weighted(weights: Dictionary) -> String:
	var total := 0.0
	for k in weights:
		total += float(weights[k])
	var roll := rng.randf() * total
	var last := ""
	for k in weights:
		last = String(k)
		roll -= float(weights[k])
		if roll <= 0.0:
			return last
	return last


# --- Claude -------------------------------------------------------------------------------------

## Some agent started working (the hand-off): a big moment within seconds, then a livelier scene
## until the turn ends. `with_van`: this turn brought the van, and its arrival is the moment. Now
## and then the moment is a bird leaving over the desktop instead (issue 317).
func turn_started(with_van: bool = false) -> void:
	var flight := not with_van and scene.flights != null and scene.flights.turn_started()
	note("turn start (the van arrives)" if with_van else ("turn start (a desktop flight)" if flight else "turn start"))
	director.turn_start(with_van or flight)


## A session's turn ended: a calm beat, unless a moment is coming or a big one's tail is playing.
## Animals pause; the flock settles; nothing new comes for a little while. `others_busy`: another
## session still works (the small life stays lively; a bird may still fly out over the desktop, issue 317).
func turn_ended(others_busy: bool = false) -> void:
	if scene.flights != null:
		scene.flights.turn_ended()
	if director.moment_playing():
		director.busy = others_busy
		note("turn end: no calm, a moment is playing")
		return
	note("turn end: calm")
	director.turn_end(others_busy)
	for c in creatures:
		(c as SceneCreature).pause()
	for f in flocks:
		(f as SceneFlock).settle()


## Nobody works now (the last turn ended, or a silent one timed out): the small life is no longer lifted.
func agents_idle() -> void:
	director.busy = false


## A small moment by whoever is here (a heron's stab, a deer's head coming up, the flock shifting),
## or, with nobody here, a fish clearing the water or a pair of birds going over.
func small_moment() -> void:
	var options := {}
	for c in creatures:
		if (c as SceneCreature).can_gesture():
			options[c] = float((c as SceneCreature).sp.data.get("moment_weight", 0.5))
	for f in flocks:
		if not (f as SceneFlock).transient:
			options[f] = 1.0
	var total := 0.0
	for k in options:
		total += float(options[k])
	if total > 0.3 and rng.randf() < 0.85:
		var roll := rng.randf() * total
		var who = options.keys()[-1]
		for k in options:
			roll -= float(options[k])
			if roll <= 0.0:
				who = k
				break
		who.gesture()
		note("moment: %s" % (who.sp.id if who is SceneCreature else "flock shifts"))
		return
	if rng.randf() < 0.5 and species.has("passing_birds") and env_allows_birds() and _pass_over("passing_birds"):
		note("moment: birds go over", "passing_birds")
		return
	_rises.rise(true)
	note("moment: a fish jumps", "fish")


## A few birds cross the sky without stopping.
func _pass_over(id: String) -> bool:
	var sp: SceneSpecies = species[id]
	var g := sp.range_of("group", [1, 3])
	var flock := SceneFlock.new()
	if not flock.setup(self, sp, rng.randi(), rng.randi_range(int(g.x), int(g.y)), true):
		return false
	flocks.append(flock)
	return true


func env_allows_birds() -> bool:
	return scene.env.rain < 0.4 and scene.env.daylight() > 0.05


# --- Reactions ----------------------------------------------------------------------------------

## `source` sounded an alarm (a snort, a croak, a plop, wings going up, a squirrel's chatter):
## everyone within its reach hears it and looks, or goes if they were already uneasy.
## `level` "flee" is something running (a snort and bounding, a croak, a plop, wings going up);
## "call" is a warning from safety (a squirrel scolding): heard, watched, not run from. Each hearer
## reacts after a short beat of its own (reaction time, and the sound's way there), so a cascade
## ripples instead of everything moving on the same frame.
func alarm(source, at: Vector2, at_ppm: float, radius_m: float, what: String, level: String = "flee") -> void:
	if radius_m <= 0.0:
		return
	note("alarm: %s" % what, String(source.sp.id) if source != null and "sp" in source else "")
	var here := world(at, at_ppm)
	var r: Array = tuning["alarm_react_sec"]
	for who in creatures + flocks:
		if who == source:
			continue
		var d: float = here.distance_to(who.world())
		if d < radius_m:
			_heard.append({"t": t + rng.randf_range(float(r[0]), float(r[1])) + d * 0.01, "who": who, "at": at, "close": d / radius_m, "level": level})


var _heard: Array = []


func _deliver_alarms() -> void:
	for h in _heard.duplicate():
		if float(h["t"]) > t:
			continue
		_heard.erase(h)
		var who = h["who"]
		# A creature may have gone (and been freed) while the sound was on its way.
		if creatures.has(who):
			(who as SceneCreature).hear_alarm(h["at"], float(h["close"]), String(h["level"]))
		elif flocks.has(who):
			(who as SceneFlock).hear_alarm(float(h["close"]), String(h["level"]))


# --- Geometry -----------------------------------------------------------------------------------

## The one size rule for an animal on or against the oak (issues 343, 351): near true size against
## its trunk and bark, never larger than life, which made the oak read small. Art px per metre wanted
## there (`on_oak`); the sheet then takes the set and whole scale nearest it (`SceneSheet.pick_scale`).
func on_oak_ppm_art(band: String = "mid", y: float = 0.0) -> float:
	return ppm(band, y) * _density * float(tuning.get("on_oak", {}).get("show_scale", 1.0))


## The same as a show scale for a creature at `ppm_pt` points per metre (what `look.scale` takes).
func on_oak_show(ppm_pt: float, band: String = "mid", y: float = 0.0) -> float:
	return on_oak_ppm_art(band, y) / maxf(0.0001, ppm_pt * _density)


## Points per metre on `band` at `y` (points).
func ppm(band: String, y: float) -> float:
	for entry in scene.kit.bands:
		if String(entry["id"]) != band:
			continue
		var p := float(entry.get("px_per_m", 100.0))
		if entry.has("y_to") and entry.has("px_per_m_to"):
			var y0 := float(entry["y"])
			var y1 := float(entry["y_to"])
			# Below the far-to-near run (the cut-away under the surface) the scale stays the nearest.
			var u := clampf((y * _density - y0) / maxf(1.0, y1 - y0), 0.0, 1.0)
			p = lerpf(p, float(entry["px_per_m_to"]), u)
		return p / _density
	return 70.0


## Metres away from the viewer at `ppm_pt` points per metre.
func depth_of(ppm_pt: float) -> float:
	return float(tuning["camera_k_art_px_m"]) / _density / maxf(ppm_pt, 0.01)


func ppm_at_depth(z_m: float) -> float:
	return float(tuning["camera_k_art_px_m"]) / _density / maxf(z_m, 0.1)


## The pond's surface row at `z_m` metres away (points): the reference ground for the air.
func ground_y(z_m: float) -> float:
	for entry in scene.kit.bands:
		if entry.has("y_to") and entry.has("px_per_m_to"):
			var p := ppm_at_depth(z_m) * _density
			var p0 := float(entry["px_per_m"])
			var p1 := float(entry["px_per_m_to"])
			return (float(entry["y"]) + (p - p0) / (p1 - p0) * (float(entry["y_to"]) - float(entry["y"]))) / _density
	return scene.size_pt.y * 0.6


## A point and its scale as metres (across, away).
func world(at: Vector2, at_ppm: float) -> Vector2:
	return Vector2((at.x - scene.size_pt.x * 0.5) / at_ppm, depth_of(at_ppm))


func zone(kind: String, band: String = "", with_key: String = "") -> Dictionary:
	for z in scene.zones_of(kind):
		if (band == "" or String(z.get("band", "")) == band) and (with_key == "" or z.has(with_key)):
			return z
	return {}


## The lane a ground habitat walks: [Vector2] in points, left to right.
func lane_of(habitat: String) -> PackedVector2Array:
	var z: Dictionary
	match habitat:
		"ground_far":
			z = zone("ground_far", "", "lane")
		"ground_mid":
			z = zone("ground_mid", "", "lane")
		"shore_far":
			z = zone("shoreline", "far", "lane")
		"shore_mid":
			z = zone("shoreline", "mid", "lane")
	var out := PackedVector2Array()
	for p in z.get("lane", []):
		out.append(Vector2(float(p[0]), float(p[1])))
	return out


func band_of(habitat: String) -> String:
	match habitat:
		"ground_far", "shore_far":
			return "far"
		"ground_mid", "shore_mid":
			return "mid"
	return "water"


static func lane_y(lane: PackedVector2Array, x: float) -> float:
	if lane.is_empty():
		return 0.0
	if x <= lane[0].x:
		return lane[0].y
	for i in range(1, lane.size()):
		if x <= lane[i].x:
			return lerpf(lane[i - 1].y, lane[i].y, (x - lane[i - 1].x) / maxf(0.001, lane[i].x - lane[i - 1].x))
	return lane[-1].y


## A point on `habitat`'s ground `dist_m` (a range) from `from`, a little off the lane's line.
func ground_near(habitat: String, from: Vector2, dist_m: Vector2, toward: float = 0.0) -> Vector2:
	var lane := lane_of(habitat)
	if lane.is_empty():
		return from
	var p := ppm(band_of(habitat), from.y)
	var d := rng.randf_range(dist_m.x, dist_m.y) * p
	var dir := toward if toward != 0.0 else (-1.0 if rng.randf() < 0.5 else 1.0)
	var lo := lane[0].x + 4.0
	var hi := lane[-1].x - 4.0
	var x := from.x + dir * d
	if x < lo or x > hi:
		x = from.x - dir * d
	# Past an end it folds back in rather than stopping on the end itself (issue 272: clamped, every
	# long walk ended on the same pixel).
	x = SceneVariety.fold(x, lo, hi)
	var y := lane_y(lane, x)
	if habitat == "ground_mid":
		y -= rng.randf_range(0.0, 1.0) * float(tuning["mid_depth_pt"])
	elif habitat == "ground_far":
		y += rng.randf_range(-1.0, 1.0) * float(tuning["far_depth_pt"])
	return on_ground(habitat, Vector2(x, y))


## `q` kept on `habitat`'s open ground: on the mid bank, inside the shore strip's walkable `area`
## (issue 233), drawn back toward the lane when it falls behind the strip (into the reeds) or out
## onto the water.
func on_ground(habitat: String, q: Vector2) -> Vector2:
	var area := mid_area() if band_of(habitat) == "mid" else PackedVector2Array()
	if area.is_empty() or Geometry2D.is_point_in_polygon(q, area):
		return q
	var lane := lane_of("ground_mid")
	var x := clampf(q.x, lane[0].x, lane[-1].x)
	var on := Vector2(x, lane_y(lane, x))
	for i in 10:
		var r := on.lerp(q, 1.0 - float(i + 1) / 10.0)
		if Geometry2D.is_point_in_polygon(r, area):
			return r
	return on


## The mid bank's walkable shore strip (points; zone `ground_mid`'s `area`), or empty.
func mid_area() -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in zone("ground_mid", "", "area").get("area", []):
		out.append(Vector2(float(p[0]), float(p[1])) / _density)
	return out


## The strip's back edge at `x` (points): where an animal coming out of the grass first stands on
## the open strip, and where one going into the grass leaves it.
func strip_edge(x: float) -> Vector2:
	var lane := lane_of("ground_mid")
	var at := Vector2(x, lane_y(lane, x))
	var area := mid_area()
	if area.is_empty() or not Geometry2D.is_point_in_polygon(at, area):
		return at
	while Geometry2D.is_point_in_polygon(at - Vector2(0.0, 0.5), area):
		at.y -= 0.5
	return at


## A spot in the grass behind the shore strip near `near_x` (points; the places' `shore_grass`
## line, in the reed stand), or null when the kit has none. An animal there is drawn in actor
## layer `grass.layer`, behind the reeds: partly hidden, and never for long (`grass` in tuning).
func grass_point(near_x: float) -> Variant:
	var line := PackedVector2Array()
	for raw in places.get("shore_grass", {}).get("line", []):
		line.append(uv(raw))
	if line.size() < 2:
		return null
	var x := SceneVariety.fold(near_x + rng.randf_range(-12.0, 12.0), line[0].x, line[-1].x)
	return Vector2(x, lane_y(line, x))


## Which way the open water lies along `band`'s bank, as a facing (-1 left, 1 right, 0 straight in
## front): the places' `water_side` (issue 320).
func water_side(band: String) -> float:
	return float(places.get("water_side", {}).get(band, 0.0))


## The nearest point at the water's edge for a creature on `habitat`.
func shore_near(habitat: String, from: Vector2) -> Vector2:
	var shore := lane_of("shore_mid" if band_of(habitat) == "mid" else "shore_far")
	if shore.is_empty():
		return from
	var x := SceneVariety.fold(from.x + rng.randf_range(-15.0, 15.0), shore[0].x + 6.0, shore[-1].x - 6.0)
	return Vector2(x, lane_y(shore, x))


## Where a ground animal comes in or goes out: into the treeline on the far bank (anywhere along
## it, fading), or off the right edge of the point. {at, fade, grass}. Running from `threat` (points)
## when the right edge lies toward it, a mid-bank animal bounds away from it into the reeds behind
## the strip instead (`grass`: true), as a deer goes for cover, rather than past the threat.
func way_out(habitat: String, from: Vector2, threat: Variant = null) -> Dictionary:
	var lane := lane_of(habitat)
	if band_of(habitat) == "far":
		var x := SceneVariety.fold(from.x + rng.randf_range(-40.0, 40.0), lane[0].x + 4.0, lane[-1].x - 4.0)
		return {"at": Vector2(x, lane_y(lane, x) - float(tuning["treeline_pt"])), "fade": true}
	if threat != null and (threat as Vector2).x > from.x - float(tuning["grass"]["threat_side_pt"]):
		var away: Variant = grass_point(from.x - rng.randf_range(10.0, 40.0))
		if away != null and (away as Vector2).x < (threat as Vector2).x:
			return {"at": away, "fade": true, "grass": true}
	var right := lane_of("ground_mid")
	var y := right[-1].y if not right.is_empty() else from.y
	# Anywhere across the strip's depth, not along one row (issue 272).
	y -= rng.randf_range(0.0, 0.7) * float(tuning["mid_depth_pt"])
	return {"at": Vector2(scene.size_pt.x + float(tuning["offscreen_pt"]), y), "fade": false}


## The surface row (points) over a fish drawn `share` as large as at the glass (its depth in the
## cut-away, issue 237), at `x`: the row where
## the pond's own scale is that share of the nearest water's, so a fish further back breaks the
## surface further out, at the size it is drawn. Where that row is land (the spit, the shore strip),
## the nearest water in front of it. {at, scale}: `scale` the water's size there against the glass.
func surface_at(x: float, share: float) -> Dictionary:
	var cut := cut_y()
	var near := ppm("water", cut)
	var y := minf(ground_y(depth_of(near * clampf(share, 0.05, 1.0))), cut - 2.0)
	while y < cut - 2.0 and not scene.is_water(Vector2(x, y)):
		y += 0.5
	return {"at": Vector2(x, y), "scale": ppm("water", y) / near}


## The director's last few places of `key` (issue 272; empty without a director).
func recent_places(key: String) -> Array:
	return director.recent_places(key) if director != null else []


## Tells the director `at` was just used as a place of `key`.
func remember_place(key: String, at: Variant) -> void:
	if director != null and at != null:
		director.remember_place(key, at)


## Somewhere to wade: {at (points), band}.
func wade_spot() -> Dictionary:
	var spots: Array = places.get("wade", [])
	var weights := {}
	for i in spots.size():
		weights[str(i)] = float(spots[i].get("weight", 1.0))
	if weights.is_empty():
		return {"at": random_water(), "band": "water"}
	var spec: Dictionary = spots[int(_pick_weighted(weights))]
	if spec.has("region") and _water_regions.has(String(spec["region"])):
		return {"at": point_in(_water_regions[String(spec["region"])]), "band": "water"}
	var at := uv(spec["at"])
	var spread: Array = spec.get("spread", [0, 0])
	at += Vector2(rng.randf_range(-1, 1) * float(spread[0]) * scene.frame_pt.size.x, rng.randf_range(-1, 1) * float(spread[1]) * scene.frame_pt.size.y)
	return {"at": at, "band": String(spec.get("band", "water"))}


## A wading step: a point near `from` in shallow water, or `from`.
func wade_near(from: Vector2, dist_m: Vector2) -> Vector2:
	var p := ppm("water", from.y)
	for i in 8:
		var q := from + Vector2(rng.randf_range(-1, 1), rng.randf_range(-0.25, 0.25)).normalized() * rng.randf_range(dist_m.x, dist_m.y) * p
		if scene.is_water(q):
			return q
	return from


## A basking spot: {at, band, water (the nearest water, points)}.
func bask_spot() -> Dictionary:
	var spots: Array = places.get("bask", [])
	var weights := {}
	for i in spots.size():
		weights[str(i)] = float(spots[i].get("weight", 1.0))
	if weights.is_empty():
		return {}
	if next_bask >= 0 and next_bask < spots.size():
		var pinned: Dictionary = spots[next_bask]
		next_bask = -1
		return bask_spot_of(pinned)
	return bask_spot_of(spots[int(_pick_weighted(weights))])


## The basking spot a places entry names: {at, band, water}, or {} when its perch is missing.
func bask_spot_of(spec: Dictionary) -> Dictionary:
	var at := Vector2.ZERO
	var band := String(spec.get("band", "near"))
	if spec.has("piece"):
		var found := false
		var n := 0
		for perch in scene.perches():
			if String(perch["piece"]) == String(spec["piece"]):
				if n == int(spec.get("perch", 0)):
					at = perch["at"]
					band = String(perch.get("band", band))
					found = true
					break
				n += 1
		if not found:
			return {}
	else:
		at = uv(spec["at"])
	return {"at": at, "band": band, "water": water_for(at, band)}


## Where an animal standing at `at` in `band` climbs in and out of the water: the nearest open
## water at the same distance from the viewer, so the hand-off between bands keeps its drawn size
## (issue 334: the log's far end is on the near bank, and the water straight below it on screen is
## the far waterline, ~7x smaller). Within `reach_m` of it, else the nearest water as before.
func water_for(at: Vector2, band: String, reach_m: float = 2.0) -> Vector2:
	if band == "water":
		return water_above(at)
	var row := water_row(ppm(band, at.y))
	if row < 0.0:
		return water_above(at)
	row = minf(row, cut_y() - 2.0)
	var reach := reach_m * ppm(band, at.y)
	for r in range(0, int(reach), 2):
		for d in [Vector2(r, 0), Vector2(-r, 0), Vector2(r, -3), Vector2(-r, -3), Vector2(r, -6), Vector2(-r, -6)]:
			var q: Vector2 = Vector2(at.x, row) + d
			if scene.is_water(q):
				return q
	return water_above(at)


## The surface row (points) where the water is drawn at `ppm_pt` points per metre, or -1.
func water_row(ppm_pt: float) -> float:
	for entry in scene.kit.bands:
		if String(entry["id"]) == "water" and entry.has("y_to") and entry.has("px_per_m_to"):
			var p0 := float(entry["px_per_m"])
			var p1 := float(entry["px_per_m_to"])
			var u := clampf((ppm_pt * _density - p0) / maxf(0.01, p1 - p0), 0.0, 1.0)
			return lerpf(float(entry["y"]), float(entry["y_to"]), u) / _density
	return -1.0


## The nearest open water to `at` (above, below or beside it), for climbing in and out.
func water_above(at: Vector2) -> Vector2:
	for r in range(0, 90, 2):
		for d in [Vector2(0, r), Vector2(0, -r), Vector2(-r, r), Vector2(r, r), Vector2(-r, 0), Vector2(r, 0)]:
			var q: Vector2 = at + d
			if scene.is_water(q):
				return q
	return at + Vector2(0, 10)


## A point in the cut-away under the surface (the places' `swim_region`), or {} when the kit has none.
func underwater_point(near_x: float = -1.0) -> Variant:
	var name := String(places.get("swim_region", ""))
	var poly: PackedVector2Array = _water_regions.get(name, PackedVector2Array())
	if poly.is_empty():
		return null
	for i in 20:
		var q := point_in(poly)
		if near_x >= 0.0:
			q.x = clampf(near_x + rng.randf_range(-60.0, 60.0), q.x - 400.0, q.x + 400.0)
		if Geometry2D.is_point_in_polygon(q, poly) and q.y > cut_y() + 8.0:
			return q
	return null


## Somewhere in the cut-away for a fish that keeps to `zones` ({shallow, mid, bed, weeds: weight},
## the kit's `fish_zones`), within `reach` points of `near_x` when given; any underwater point when
## the kit has no zones.
func fish_point(zones: Dictionary, near_x: float = -1.0, reach: float = 160.0, margin: float = 0.0) -> Variant:
	var spec: Dictionary = places.get("fish_zones", {})
	var poly: PackedVector2Array = _water_regions.get(String(places.get("swim_region", "")), PackedVector2Array())
	if spec.is_empty() or poly.is_empty() or zones.is_empty():
		return underwater_point(near_x)
	for i in 24:
		var rect := _fish_rect(spec, _pick_weighted(zones), near_x)
		if rect.size.x <= 0.0:
			continue
		var q := Vector2(rng.randf_range(rect.position.x, rect.end.x), rng.randf_range(rect.position.y, rect.end.y))
		if near_x >= 0.0:
			q.x = clampf(q.x, near_x - reach, near_x + reach)
		if in_swim(q, margin) and q.y > cut_y() + 8.0:
			return q
	return underwater_point(near_x)


## The rect (points) of one fish zone; for `weeds`, the weed piece nearest `near_x` (or any).
func _fish_rect(spec: Dictionary, zone_id: String, near_x: float) -> Rect2:
	var raw = spec.get(zone_id, null)
	if raw is Array:
		var a := uv([raw[0], raw[1]])
		return Rect2(a, uv([raw[2], raw[3]]) - a)
	if not raw is Dictionary:
		return Rect2()
	var rects: Array = []
	for piece in scene.kit.pieces:
		if not String(piece.get("id", "")).begins_with(String(raw.get("prefix", "weed_"))):
			continue
		var at := Vector2(float(piece["at"][0]), float(piece["at"][1])) / _density
		var size := Vector2(float(piece["size"][0]), float(piece["size"][1])) / _density
		var pad := float(raw.get("pad", 0.0)) * scene.size_pt.x
		rects.append(Rect2(at.x - pad, at.y + size.y * float(raw.get("from", 0.0)), size.x + pad * 2.0, size.y * (float(raw.get("to", 1.0)) - float(raw.get("from", 0.0)))))
	if rects.is_empty():
		return Rect2()
	if near_x >= 0.0 and rng.randf() < 0.75:
		rects.sort_custom(func(p: Rect2, q: Rect2) -> bool: return absf(p.get_center().x - near_x) < absf(q.get_center().x - near_x))
		return rects[rng.randi_range(0, mini(2, rects.size() - 1))]
	return rects[rng.randi() % rects.size()]


## In the cut-away, below the waterline, where a fish may swim (`margin` points clear each side, half
## its length, so a big fish does not poke into the bank).
func in_swim(q: Vector2, margin: float = 0.0) -> bool:
	var poly: PackedVector2Array = _water_regions.get(String(places.get("swim_region", "")), PackedVector2Array())
	if poly.is_empty() or q.y <= cut_y() + 6.0:
		return false
	for dx in [0.0, -margin, margin]:
		if not Geometry2D.is_point_in_polygon(q + Vector2(dx, 0.0), poly):
			return false
	return true


## The waterline seen edge-on (points): above it the surface band, below it the cut-away.
func cut_y() -> float:
	return float(scene.kit.water.get("cut_y", scene.kit.water.get("bottom_y", 0))) / _density


## A random point of open water, weighted by the places' fish regions.
func random_water() -> Vector2:
	var weights: Dictionary = places.get("fish_regions", {})
	var choice := _pick_weighted(weights) if not weights.is_empty() else ""
	var poly: PackedVector2Array = _water_regions.get(choice, PackedVector2Array())
	for i in 20:
		var q := point_in(poly) if not poly.is_empty() else Vector2(rng.randf_range(0, scene.size_pt.x), rng.randf_range(scene.water_rows().x, scene.water_rows().y))
		if scene.is_water(q):
			return q
	return Vector2(scene.size_pt.x * 0.4, scene.water_rows().x + 30.0)


func point_in(poly: PackedVector2Array) -> Vector2:
	var box := Rect2(poly[0], Vector2.ZERO)
	for p in poly:
		box = box.expand(p)
	for i in 30:
		var q := Vector2(rng.randf_range(box.position.x, box.end.x), rng.randf_range(box.position.y, box.end.y))
		if Geometry2D.is_point_in_polygon(q, poly):
			return q
	return box.get_center()


## A place as fractions of the kit's frame (the composition; a kit that grew past it keeps them).
func uv(raw) -> Vector2:
	return scene.frame_pt.position + Vector2(float(raw[0]), float(raw[1])) * scene.frame_pt.size


## The squirrel's way up: the trunk line (bottom to top) and then the long branch's perches.
func climb_route() -> Dictionary:
	var spec: Dictionary = places.get("trunk_climb", {})
	var trunk := PackedVector2Array()
	for p in spec.get("line", []):
		trunk.append(uv(p))
	var branch := PackedVector2Array()
	for perch in scene.perches():
		if String(perch["piece"]) == String(spec.get("branch", "")):
			branch.append(perch["at"])
	return {"trunk": trunk, "branch": branch, "band": String(spec.get("band", "mid"))}


## Perches a flock may use, with the piece they bend: [{at, band, piece}], spread along the
## long branch between the kit's perches as well.
func flock_perches() -> Array:
	var weights: Dictionary = places.get("flock_perches", {})
	var out: Array = []
	for piece in weights:
		var row: Array = []
		for perch in scene.perches():
			if String(perch["piece"]) == String(piece):
				row.append(perch)
		row.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return (a["at"] as Vector2).x < (b["at"] as Vector2).x)
		var spec := scene.kit.piece(String(piece))
		var foot := SceneKit.pivot_of(spec).y / _density if not spec.is_empty() else -1.0
		for i in row.size():
			if foot > 0.0:
				row[i] = row[i].merged({"scale_y": foot}, true)
			var grip := stalk_grip(String(piece))
			if grip.has("none"):
				# A cattail with no head to hold under: no bird stands on its tip.
				continue
			if not grip.is_empty():
				row[i] = row[i].merged(grip, true)
			out.append(_among_leaves(row[i].merged({"weight": float(weights[piece])})))
			if String(piece) == "oak_trunk" and i + 1 < row.size():
				var a: Vector2 = row[i]["at"]
				var b: Vector2 = row[i + 1]["at"]
				out.append(_among_leaves(row[i].merged({"at": a.lerp(b, 0.5) + Vector2(0, 1), "weight": float(weights[piece])}, true)))
	out.append_array(_spread_perches())
	return out


## The rest of the scene's perches (Skypatch issue 147), so
## landings are not all on the oak and the reeds: `flock_spread` in the places file. `perches` are
## twigs on a piece (the birch's, settled onto its drawn pixels; `watch` turns the bird toward the
## sitter now and then), `pads` places on the lily pads, `far` spots in the far treeline.
func _spread_perches() -> Array:
	var spec: Dictionary = places.get("flock_spread", {})
	var out: Array = []
	for raw in spec.get("perches", []):
		var piece := String(raw["piece"])
		var pspec := scene.kit.piece(piece)
		var at := _settle_on(String(raw.get("image", piece)), uv(raw["at"]))
		if pspec.is_empty() or at == Vector2.INF:
			continue
		var foot := SceneKit.pivot_of(pspec).y / _density
		out.append({"piece": piece, "at": at, "band": String(pspec.get("band", "near")), "weight": float(raw.get("weight", 1.0)),
				"scale_y": maxf(foot, at.y), "watch": float(raw.get("watch", 0.0)), "area": String(raw.get("area", piece))})
	var pads: Dictionary = spec.get("pads", {})
	if not pads.is_empty():
		for at in pad_spots(String(pads["piece"]), float(pads.get("every_pt", 14.0))):
			out.append({"piece": String(pads["piece"]), "at": at, "band": String(pads.get("band", "water")), "weight": float(pads.get("weight", 0.3)),
					"area": "pads"})
	var far: Dictionary = spec.get("far", {})
	for raw in far.get("at", []):
		out.append({"piece": "far_trees", "at": uv(raw), "band": String(far.get("band", "far")), "weight": float(far.get("weight", 0.3)), "area": "far"})
	return out


## `at` (points) settled straight down onto the first drawn pixel of `piece_id` (within the kit's
## perch reach); INF if there is none.
func _settle_on(piece_id: String, at: Vector2) -> Vector2:
	var image := scene.piece_image(piece_id)
	var pspec := scene.kit.piece(piece_id)
	if image == null or pspec.is_empty():
		return Vector2.INF
	var local := Vector2i((at * _density).round()) - SceneKit._vec2i(pspec["at"])
	var reach := int(float(scene.tuning["visitors"]["perch_settle_pt"]) * _density)
	for dy in reach:
		var q := local + Vector2i(0, dy)
		if q.x < 0 or q.y < 0 or q.x >= image.get_width() or q.y >= image.get_height():
			continue
		if image.get_pixelv(q).a > 0.5:
			return (Vector2(q) + Vector2(SceneKit._vec2i(pspec["at"]))) / _density
	return Vector2.INF


## Places on the lily pads' top surface (points), one per `every_pt` across, from the piece's pixels.
func pad_spots(piece_id: String, every_pt: float) -> Array:
	var image := scene.piece_image(piece_id)
	var pspec := scene.kit.piece(piece_id)
	var out: Array = []
	if image == null or pspec.is_empty():
		return out
	var origin := Vector2(SceneKit._vec2i(pspec["at"]))
	var step := maxi(2, int(every_pt * _density))
	for x in range(4, image.get_width() - 4, step):
		for y in range(1, image.get_height() - 4):
			var c := image.get_pixel(x, y)
			if c.a < 0.9:
				continue
			# The first drawn pixel down this column: the top of a pad when it is green with pad
			# under the feet and to both sides (not a flower or a stem).
			if c.g >= c.r and c.g >= c.b and image.get_pixel(x, y + 3).a > 0.5 and image.get_pixel(x - 4, y + 1).a > 0.5 \
					and image.get_pixel(x + 4, y + 1).a > 0.5:
				out.append((origin + Vector2(x, y)) / _density)
			break
	return out


## Where a bird holds a cattail (Skypatch issue 147): on the
## stalk just below the brown head, found on the piece's own pixels: {at (points), grip: true}, or {}
## for a piece that is not a cattail (`flock_grip.pieces` prefixes in the places file).
func stalk_grip(piece_id: String) -> Dictionary:
	var spec: Dictionary = places.get("flock_grip", {})
	var wanted := false
	for prefix in spec.get("pieces", []):
		wanted = wanted or piece_id.begins_with(String(prefix))
	if not wanted:
		return {}
	if _grips.has(piece_id):
		return _grips[piece_id]
	var image := scene.piece_image(piece_id)
	var pspec := scene.kit.piece(piece_id)
	var found := {}
	if image != null and not pspec.is_empty():
		var head_px := int(spec.get("head_px", 9))
		var stem_px := int(spec.get("stem_px", 8))
		var in_head := false
		# Measured around the spike at the very top, so a leaf beside the stalk is left out.
		var top_x := -1.0
		for y in mini(image.get_height(), int(spec.get("search_px", 160))):
			var xs: Array = []
			for x in image.get_width():
				if image.get_pixel(x, y).a > 0.5 and (top_x < 0.0 or absf(float(x) - top_x) <= 7.0):
					xs.append(x)
			if xs.is_empty():
				continue
			if top_x < 0.0:
				top_x = (float(xs[0]) + float(xs[-1])) * 0.5
			if xs.size() >= head_px:
				in_head = true
			elif in_head and xs.size() <= stem_px:
				# The stalk's own pixels near the head's middle (a leaf beside it is left out).
				var row := y + int(spec.get("below_px", 3))
				var stem: Array = []
				for x in image.get_width():
					if absf(float(x) - top_x) <= 4.0 and image.get_pixel(x, row).a > 0.5:
						stem.append(x)
				if not stem.is_empty():
					var cx := (float(stem[0]) + float(stem[-1]) + 1.0) * 0.5
					found = {"at": (Vector2(SceneKit._vec2i(pspec["at"])) + Vector2(cx, float(row))) / _density, "grip": true}
				break
	if found.is_empty():
		found = {"none": true}
	_grips[piece_id] = found
	return found


## A perch the oak's crowns partly cover is drawn among the leaves (behind the crowns, peeking
## through); one in the open, or buried, stays in front.
func _among_leaves(perch: Dictionary) -> Dictionary:
	var spec: Dictionary = places.get("leaf_cover", {})
	if spec.is_empty() or String(perch.get("band", "")) != "mid":
		return perch
	var cover := leaf_cover(perch["at"])
	var among: Array = spec.get("among", [0.15, 0.8])
	if cover >= float(among[0]) and cover <= float(among[1]):
		perch["layer"] = "mid_leaves"
	elif cover > float(among[1]):
		# Deep in the crown, a bird could only be drawn on top of the leaves: seldom chosen.
		perch["weight"] = float(perch.get("weight", 1.0)) * float(spec.get("buried_weight", 0.35))
	perch["leaf_cover"] = cover
	return perch


## The share (0..1) of a small bird's box standing at `at` (points) that the crowns cover.
func leaf_cover(at: Vector2) -> float:
	var spec: Dictionary = places.get("leaf_cover", {})
	var box: Array = spec.get("box_pt", [10, 9])
	var w := float(box[0]) * _density
	var h := float(box[1]) * _density
	var foot := at * _density
	var n := 0
	var hit := 0
	for iy in 6:
		for ix in 6:
			var q := foot + Vector2((float(ix) / 5.0 - 0.5) * w, -float(iy) / 5.0 * h - 1.0)
			n += 1
			for piece in spec.get("pieces", []):
				var image := scene.piece_image(String(piece))
				var pspec := scene.kit.piece(String(piece))
				if image == null or pspec.is_empty():
					continue
				var local := Vector2i(q) - SceneKit._vec2i(pspec["at"])
				if local.x >= 0 and local.y >= 0 and local.x < image.get_width() and local.y < image.get_height() and image.get_pixelv(local).a > 0.5:
					hit += 1
					break
	return float(hit) / float(maxi(n, 1))


## The month (1..12) for the cast: a clip's pinned month, else the scene's clock.
func month() -> int:
	return month_override if month_override > 0 else SceneSongbirdCast.month_of(now_unix())


## What the cast needs to pick a party now.
func cast_ctx() -> Dictionary:
	var env := scene.env
	return {"month": month(), "minute": env.minute, "dawn": float(env.light.dawn_minutes), "dusk": float(env.light.night_minutes),
			"habits": {"ground": not flock_ground().is_empty(), "trunk": not trunk_spot(0.5).is_empty(), "flowers": not flower_spots().is_empty()}}


## Flower heads a hummingbird visits: [{at (points), band}].
func flower_spots() -> Array:
	var spec: Dictionary = places.get("flowers", {})
	var out: Array = []
	for p in spec.get("at", []):
		out.append({"at": uv(p), "band": String(spec.get("band", "near"))})
	return out


## A place on the oak trunk's left face at `u` (0 low .. 1 high) of the woodpecker's rows:
## {at (points), band, piece}, found on the trunk's own pixels; {} without one.
func trunk_spot(u: float) -> Dictionary:
	var spec: Dictionary = places.get("woodpecker_trunk", {})
	if spec.is_empty():
		return {}
	var rows: Array = spec["v"]
	var v := lerpf(float(rows[1]), float(rows[0]), clampf(u, 0.0, 1.0))
	var key := snappedf(v, 0.002)
	if _trunk_edges.has(key):
		return _trunk_edges[key]
	var piece := String(spec.get("piece", "oak_trunk"))
	var image := scene.piece_image(piece)
	var pspec := scene.kit.piece(piece)
	var found := {}
	if image != null and not pspec.is_empty():
		var origin := SceneKit._vec2i(pspec["at"])
		var art := uv([float(spec.get("line_u", 0.93)), v]) * _density
		var y := int(art.y) - origin.y
		var x := int(art.x) - origin.x
		if y >= 0 and y < image.get_height() and x >= 2 and x < image.get_width() and image.get_pixel(x, y).a > 0.5:
			while x > 2 and (image.get_pixel(x - 1, y).a > 0.5 or image.get_pixel(x - 2, y).a > 0.5):
				x -= 1
			found = {"at": Vector2(float(x + origin.x), float(y + origin.y)) / _density, "band": String(spec.get("band", "mid")), "piece": piece}
	_trunk_edges[key] = found
	return found


func flock_ground() -> Dictionary:
	var spec: Dictionary = places.get("flock_ground", {})
	if spec.is_empty():
		return {}
	return {"from": uv(spec["from"]), "to": uv(spec["to"]), "band": String(spec.get("band", "mid")), "weight": float(spec.get("weight", 1.0)), "area": "ground"}


## Every stretch of grass a party may drop to (Skypatch issue 147):
## `flock_ground` (under the oak) and `flock_spread.grounds` (the left bank, the far meadow), each
## {from, to, band, weight, area}.
func flock_grounds() -> Array:
	var out: Array = []
	var main := flock_ground()
	if not main.is_empty():
		out.append(main)
	for raw in places.get("flock_spread", {}).get("grounds", []):
		out.append({"from": uv(raw["from"]), "to": uv(raw["to"]), "band": String(raw.get("band", "mid")), "weight": float(raw.get("weight", 1.0)),
				"area": String(raw.get("area", "ground"))})
	return out


func snake_path() -> Array:
	var paths: Array = places.get("snake_paths", [])
	if paths.is_empty():
		return [random_water(), random_water()]
	var p: Dictionary = paths[rng.randi() % paths.size()]
	var a := uv(p["from"])
	var b := uv(p["to"])
	if rng.randf() < 0.5:
		return [b, a]
	return [a, b]


## What the avatar's eyes follow: the newest thing moving, or anything here.
## The animal nearest `at` (points) within `reach_pt`: a songbird down on the grass, on a perch or landing,
## or any creature in sight; null when nothing is that close. The sitter watches this before anything farther
## away (the human, 2026-10-20: a bird landing at his feet or on the log in front of him).
func focus_near(at: Vector2, reach_pt: float) -> Variant:
	var best: Variant = null
	var best_d := reach_pt
	for f in flocks:
		var flock: SceneFlock = f
		for b in flock.birds:
			if String(b["mode"]) in ["perched", "ground", "to_perch"]:
				var p := flock.screen_of(b["p"])
				var d := p.distance_to(at)
				if d < best_d:
					best_d = d
					best = p
	for c in creatures:
		var creature: SceneCreature = c
		if creature.alpha > 0.5:
			var d := creature.position.distance_to(at)
			if d < best_d:
				best_d = d
				best = creature.position
	return best


func focus() -> Variant:
	for f in flocks:
		var c: Variant = (f as SceneFlock).centre_on_screen()
		if c != null:
			return c
	var best: Variant = null
	for c in creatures:
		var creature: SceneCreature = c
		if creature.alpha > 0.5:
			if creature.is_moving():
				return creature.position
			best = creature.position
	return best


## Every body plan doing each of its actions in a grid on the near bank, for judging the
## placeholders (and later the bench's sheets) side by side: the `lineup` clip.
func lineup() -> void:
	var rows := {
		"deer": ["idle", "walk", "trot", "run", "graze", "drink", "look", "startle", "lie", "groom"],
		"red_fox": ["walk", "trot", "sit", "look", "groom", "strike", "graze", "lie"],
		"black_bear": ["walk", "graze", "drink", "sit", "look"],
		"raccoon": ["walk", "drink", "sit", "groom"],
		"gray_squirrel": ["run", "sit", "peck", "climb", "tail_flick"],
		"great_blue_heron": ["idle", "walk", "look", "strike", "groom", "fly", "glide", "land"],
		"painted_turtle": ["bask", "walk", "swim", "look"],
		"songbird_flock": ["perch", "peck", "fly", "glide", "hop", "look"],
		"water_snake": ["swim", "look"],
	}
	var backdrop := ColorRect.new()
	backdrop.size = scene.size_pt
	backdrop.color = Color("9aa48f")
	backdrop.z_index = 50
	scene.actor_layer(scene.kit.band_ids()[-1]).add_child(backdrop)
	var y := 4.0
	for id in rows:
		var sp: SceneSpecies = species[id]
		var palette: Dictionary = sp.data.get("colors", sp.data.get("palettes", [{}])[0])
		var actions: Array = rows[id]
		var s := 46.0 / maxf(sp.size().y, sp.size().x * 0.55)
		for i in actions.size():
			var look := SceneCreatureLook.new()
			var drawn := sp.pick_sheet(false, rng)
			look.setup(sp, palette, 1.0, i, String(drawn.get("id", "")), drawn)
			look.density = scene.density
			look.play(String(actions[i]))
			look.gait_kind = "run" if actions[i] == "run" else ("trot" if actions[i] == "trot" else "walk")
			look.position = Vector2(60.0 + float(i) * 108.0, y + 46.0)
			look.scale = Vector2(s, s)
			look.px = 1.0 / s
			look.set_meta("moving", String(actions[i]) in ["walk", "trot", "run", "climb", "swim"])
			look.z_index = 51
			scene.actor_layer(scene.kit.band_ids()[-1]).add_child(look)
			_lineup.append(look)
		y += 52.0


var _lineup: Array = []


func _step_lineup(dt: float) -> void:
	for look in _lineup:
		var l: SceneCreatureLook = look
		l.advance(dt, dt * 1.2 if bool(l.get_meta("moving")) else 0.0)


func debug_actions() -> Array:
	var out: Array = []
	for id in species:
		out.append(["Comes now: " + String(id), func() -> void: spawn(String(id))])
	for sid in species:
		for m in (species[sid] as SceneSpecies).data.get("cast", []):
			var who := String(m["id"])
			out.append(["Songbird now: %s (%s)" % [who, sid], func() -> void:
				next_cast = who
				spawn(String(sid))])
	out.append(["Claude turn starts", turn_started])
	out.append(["Claude turn ends", turn_ended])
	return out
