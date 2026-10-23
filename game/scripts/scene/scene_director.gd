class_name SceneDirector
extends RefCounted

## Who comes to the pond, and when (Skypatch issue 104).
## It should feel lucky, not staged, so nothing is on a timetable: every species has a chance per
## second (its `rate_per_hour`, times how active it is at this time of day, times what the weather
## does to it), and the director only bends those chances:
##
## - **Rarity:** a species is not seen again within its `min_gap_min` (a bear: two weeks), across
##   restarts (`to_dict`).
## - **Quiet spells:** after an arrival, nothing else arrives for a while, so each one lands.
## - **Memory:** a species seen in the last few arrivals is less likely, the last one much less, and
##   a pair seen in that order before is less likely to repeat.
## - **Escalation:** the longer the scene has gone without someone new (empty, or in part with a
##   quiet visitor), the likelier an everyday visitor becomes (never a rare one).
## - **Room:** at most `max_visitors` visiting species at once.
## - **Claude, the hand-off rhythm** (issue 239):
##   `turn_start` (the hand-off) brings a big moment within seconds: an arrival with a sudden start
##   and a big change of shape (species data `big_moment`: the heron gliding in, the flock bursting
##   in; never a walk-in), at most `big_moments_per_day`, else something small by whoever is there.
##   A big moment leaves a tail (`tail_sec`: small follow-ups by the same animal). While busy the
##   small life is livelier (`busy_lift` by body); `turn_end` gives a calm beat. The turn that
##   brings the van has the van as its moment. Every session's hand-off counts, even while others
##   work (issue 308), within the same gaps and cap.
##
## Ambient life (fish rising, dragonflies) runs on its own chances and does not count as a visit;
## a species may be likelier between visits (`between_visits`) and rarer during one (`during_visits`). Seeded and
## clock-free (time comes in through `tick`), so a seed gives the same day every time. Pure.

var tuning: Dictionary = {}
var species: Dictionary = {}
var rng := RandomNumberGenerator.new()
var t := 0.0
## Seconds the scene has gone without an arrival (counted in part while someone is here).
var quiet_for := 0.0
## Seconds until arrivals are allowed again (a quiet spell or a calm beat).
var hold := 0.0
## The last arrivals, oldest first: [{id, t}].
var recent: Array = []
## Species id -> unix seconds it last arrived (kept across restarts).
var last_seen: Dictionary = {}
var _moment_at := -1.0
var _last_moment := -1.0e9
var _last_big := -1.0e9
## An agent is working (between the busy edges): the small life is livelier.
var busy := false
## Big moments today, for the daily cap only: the game day they count for and how many.
var _big_day := ""
var _big_today := 0
## Tail beats still to come: [{at, species, beat}].
var _tails: Array = []
## Where each kind of place was last used, newest last (issue 272):
## {key: [Vector2 or a name]}, e.g. "heron_land" -> the last few landing spots, "heron_entry" -> the
## last approaches. Kept with the director, so a rebuilt scene (another size) remembers too.
var places_used: Dictionary = {}


func _init(director_tuning: Dictionary, all_species: Dictionary, seed: int) -> void:
	tuning = director_tuning
	species = all_species
	rng.seed = seed
	# Opening the scene should not mean minutes of nothing: it starts as if it had been empty a
	# while, so the first visitor comes soon (but not on cue).
	quiet_for = float(tuning["opening_quiet_sec"])
	hold = rng.randf_range(float(tuning["first_visit_sec"][0]), float(tuning["first_visit_sec"][1])) * 0.35


## Advances `dt` seconds. `ctx`: minute, dawn, dusk (minutes), weather {rain, wind, fog, sunshine},
## unix (seconds), present {species id: count}. Returns what happens now:
## [{species, why: "ambient" | "arrival" | "moment" | "moment_small"}].
func tick(dt: float, ctx: Dictionary) -> Array:
	t += dt
	hold = maxf(0.0, hold - dt)
	var present: Dictionary = ctx.get("present", {})
	var visitors := visitor_count(present)
	# Time since anything new came: all of it when the scene is empty, part of it while someone
	# quiet is here (a basking turtle should not hold the next arrival off for a quarter hour).
	quiet_for += dt if visitors == 0 else dt * float(tuning.get("quiet_while_visited", 0.0))
	var out: Array = []
	for id in species:
		var sp: SceneSpecies = species[id]
		if sp.tier != "ambient" or crowded(id, present):
			continue
		# A rare ambient sighting (the old bass) keeps its gap across restarts like a rare visitor.
		var rare := float(sp.data.get("min_gap_min", 0.0)) > 0.0
		if rare and not allowed(id, ctx):
			continue
		var r := base_rate(id, ctx) * (float(tuning["ambient_under_hold"]) if hold > 0.0 else 1.0) * busy_lift(sp)
		# Some small life fills the gaps between visits (dragonflies) and gives way during them.
		r *= float(sp.data.get("between_visits", 1.0)) if visitors == 0 else float(sp.data.get("during_visits", 1.0))
		if rng.randf() < r * dt:
			out.append({"species": id, "why": "ambient"})
			if rare:
				last_seen[id] = float(ctx.get("unix", 0.0))
	while not _tails.is_empty() and t >= float(_tails[0]["at"]):
		var tail: Dictionary = _tails.pop_front()
		out.append({"species": tail["species"], "why": "tail", "beat": tail["beat"]})
	if _moment_at >= 0.0 and t >= _moment_at:
		_moment_at = -1.0
		out.append(_moment(ctx))
	elif hold <= 0.0 and visitors < int(tuning["max_visitors"]):
		var rates := {}
		var total := 0.0
		for id in species:
			var r := rate(id, ctx)
			if r > 0.0:
				rates[id] = r
				total += r
		if total > 0.0 and rng.randf() < total * dt:
			out.append(_arrive(_pick(rates, total), ctx, "arrival"))
	return out


## Visiting species in the scene now (ambient life does not count).
func visitor_count(present: Dictionary) -> int:
	var n := 0
	for id in present:
		if species.has(id) and (species[id] as SceneSpecies).tier != "ambient" and int(present[id]) > 0:
			n += 1
	return n


## Chance per second from the animal alone: its rate, how active it is now, the weather.
func base_rate(id: String, ctx: Dictionary) -> float:
	var sp: SceneSpecies = species[id]
	var hourly := float(sp.data.get("rate_per_hour", 0.0))
	return hourly / 3600.0 * sp.activity(float(ctx["minute"]), float(ctx["dawn"]), float(ctx["dusk"])) * sp.weather_factor(ctx.get("weather", {}))


## Chance per second of `id` arriving now, with rarity, presence, memory and escalation applied.
func rate(id: String, ctx: Dictionary) -> float:
	var sp: SceneSpecies = species[id]
	if sp.tier == "ambient" or sp.tier == "moment" or not allowed(id, ctx):
		return 0.0
	# Escalation livens up the everyday visitors only: an empty hour must not make a bear likelier.
	var lift := escalation() if sp.tier == "visit" else 1.0
	return base_rate(id, ctx) * lift * repeat_factor(id)


## Not here already, and not seen within its rarity gap.
func allowed(id: String, ctx: Dictionary) -> bool:
	var sp: SceneSpecies = species[id]
	if int(ctx.get("present", {}).get(id, 0)) > 0 or crowded(id, ctx.get("present", {})):
		return false
	# A moment played by animals already here (tier "moment", the bass leap, issue 299) needs one of them.
	var needs: Array = sp.data.get("needs_any", [])
	if not needs.is_empty() and not needs.any(func(n) -> bool: return int(ctx.get("present", {}).get(String(n), 0)) > 0):
		return false
	# A species of some months only (`months`: weight by month, 1-12; the geese, issue 356): never in a month weighted 0.
	if month_weight(sp, ctx) <= 0.0:
		return false
	var gap := float(sp.data.get("min_gap_min", 0.0)) * 60.0
	if last_seen.has(id) and float(ctx.get("unix", 0.0)) - float(last_seen[id]) < gap:
		return false
	return true


## How likely `sp` is in the context's month (`months` in its data: {"1": weight, ...}; 1 without).
static func month_weight(sp: SceneSpecies, ctx: Dictionary) -> float:
	var months: Dictionary = sp.data.get("months", {})
	if months.is_empty() or not ctx.has("month"):
		return 1.0
	return float(months.get(str(int(ctx["month"])), 0.0))


## One bird moment at a time (Skypatch issue 147): `id`
## waits while any species in its `apart_from` is here.
func crowded(id: String, present: Dictionary) -> bool:
	for other in (species[id] as SceneSpecies).data.get("apart_from", []):
		if int(present.get(String(other), 0)) > 0:
			return true
	return false


## 1 until the scene has been empty `escalate_after_sec`, then rising to `escalate_max`.
func escalation() -> float:
	var u := clampf((quiet_for - float(tuning["escalate_after_sec"])) / maxf(1.0, float(tuning["escalate_ramp_sec"])), 0.0, 1.0)
	return 1.0 + (float(tuning["escalate_max"]) - 1.0) * u


## Less of what was just seen: each recent arrival of `id`, the last one more so, and a pair
## (the last arrival, then `id`) that has happened in that order before.
func repeat_factor(id: String) -> float:
	var f := 1.0
	for r in recent:
		if String(r["id"]) == id:
			f *= float(tuning["repeat_penalty"])
	if not recent.is_empty():
		var last := String(recent[-1]["id"])
		if last == id:
			f *= float(tuning["last_penalty"])
		for i in recent.size() - 1:
			if String(recent[i]["id"]) == last and String(recent[i + 1]["id"]) == id:
				f *= float(tuning["pair_penalty"])
	return f


## Livelier small life while an agent works: `busy_lift` by body (songbird, fish, odonata).
func busy_lift(sp: SceneSpecies) -> float:
	return float(tuning.get("busy_lift", {}).get(sp.body, 1.0)) if busy else 1.0


## A turn started (the hand-off): a moment within a few seconds, unless one is already coming or
## just came. `with_van`: this turn brought the van (the day's first sign), and its arrival is the
## moment, so nothing else is added on top of it.
func turn_start(with_van: bool = false) -> void:
	busy = true
	if with_van:
		_moment_at = -1.0
		_last_moment = t
		return
	if _moment_at >= 0.0 or t - _last_moment < float(tuning["moment_min_gap_sec"]):
		return
	var d: Array = tuning["moment_delay_sec"]
	_moment_at = t + rng.randf_range(float(d[0]), float(d[1]))


## A turn ended: a calm beat, no arrivals for a little while. `others_busy`: another session still
## works, so the small life stays lively.
func turn_end(others_busy: bool = false) -> void:
	busy = others_busy
	var c: Array = tuning["calm_sec"]
	hold = maxf(hold, rng.randf_range(float(c[0]), float(c[1])))


func moment_pending() -> bool:
	return _moment_at >= 0.0


## A moment is coming or a big one's tail is still playing: a turn ending now brings no calm.
func moment_playing() -> bool:
	return _moment_at >= 0.0 or not _tails.is_empty()


## An arrival when a big moment is allowed and someone plausible can come (awake now, weather
## fine, not too rare); otherwise a small moment by whoever is here.
func _moment(ctx: Dictionary) -> Dictionary:
	_last_moment = t
	var present: Dictionary = ctx.get("present", {})
	var day := _day_of(ctx)
	if day != _big_day:
		_big_day = day
		_big_today = 0
	# One big moment at a time (issue 410): while one plays, the hand-off is small and spends nothing.
	var room := _big_today < int(tuning["big_moments_per_day"]) and not bool(ctx.get("big_playing", false))
	if room and t - _last_big >= float(tuning["big_moment_gap_sec"]) and visitor_count(present) < int(tuning["max_visitors"]):
		var rates := {}
		var total := 0.0
		for id in species:
			var sp: SceneSpecies = species[id]
			if sp.tier == "ambient" or not bool(sp.data.get("big_moment", false)) or not allowed(id, ctx):
				continue
			var plausible := sp.activity(float(ctx["minute"]), float(ctx["dawn"]), float(ctx["dusk"])) * sp.weather_factor(ctx.get("weather", {}))
			if plausible < float(tuning["moment_floor"]):
				continue
			# Only arrivals that read at once qualify (a flock bursting in, a heron gliding in);
			# among them, `moment_weight` leans the pick.
			var r := plausible * float(sp.data.get("rate_per_hour", 0.0)) * float(sp.data.get("moment_weight", 0.5)) * repeat_factor(id) * month_weight(sp, ctx)
			if r > 0.0:
				rates[id] = r
				total += r
		if total > 0.0:
			_last_big = t
			_big_today += 1
			var id := _pick(rates, total)
			_tail_after(id)
			return _arrive(id, ctx, "moment")
	return {"species": "", "why": "moment_small"}


## The tail: small follow-ups by the big moment's animal, where the eye landed.
func _tail_after(id: String) -> void:
	_tails.clear()
	var beat := 0
	for w in tuning["tail_sec"]:
		_tails.append({"at": t + rng.randf_range(float(w[0]), float(w[1])), "species": id, "beat": beat})
		beat += 1
	_tails.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["at"]) < float(b["at"]))


## The game day `ctx` is in (`day`, a local date the scene passes), else the UTC day of its unix.
static func _day_of(ctx: Dictionary) -> String:
	var day := String(ctx.get("day", ""))
	return day if day != "" else str(int(floorf(float(ctx.get("unix", 0.0)) / 86400.0)))


## Big moments left today (the cap; nothing else is counted).
func big_left(ctx: Dictionary) -> int:
	if _day_of(ctx) != _big_day:
		return int(tuning["big_moments_per_day"])
	return maxi(0, int(tuning["big_moments_per_day"]) - _big_today)


func _arrive(id: String, ctx: Dictionary, why: String) -> Dictionary:
	recent.append({"id": id, "t": t})
	while recent.size() > int(tuning["memory"]):
		recent.pop_front()
	last_seen[id] = float(ctx.get("unix", 0.0))
	var q: Array = tuning["quiet_after_arrival_sec"]
	hold = maxf(hold, rng.randf_range(float(q[0]), float(q[1])))
	quiet_for = 0.0
	return {"species": id, "why": why}


func _pick(rates: Dictionary, total: float) -> String:
	var roll := rng.randf() * total
	var last := ""
	for id in rates:
		last = String(id)
		roll -= float(rates[id])
		if roll <= 0.0:
			return last
	return last


## The last few places of `key` (oldest first).
func recent_places(key: String) -> Array:
	return places_used.get(key, [])


## Remembers `at` (a point or a name) as the newest place of `key`, keeping `director.place_memory`.
func remember_place(key: String, at: Variant) -> void:
	var list: Array = places_used.get(key, [])
	list.append(at)
	while list.size() > int(tuning.get("place_memory", 4)):
		list.pop_front()
	places_used[key] = list


func to_dict() -> Dictionary:
	return {"last_seen": last_seen.duplicate(), "big": {"day": _big_day, "n": _big_today}}


func from_dict(d: Dictionary) -> void:
	last_seen = d.get("last_seen", {}).duplicate()
	var big: Dictionary = d.get("big", {})
	_big_day = String(big.get("day", ""))
	_big_today = int(big.get("n", 0))
