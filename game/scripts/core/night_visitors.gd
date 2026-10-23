class_name NightVisitors
extends RefCounted

## Rewards for stopping (SPEC §2.5, §4.3): close up before `dusk_close_threshold` and stay
## closed through the night, and night visitors are in the next morning's journal. Coming back
## the same evening, or working through the night, simply brings none; nothing is lost. A week
## away still brings one night's visitors, never a backlog. Independent of agents.


## What closing up now records in the save: the game day and whether it was before the threshold.
static func closing(day_key: String, local_minutes: int, threshold_minutes: int, dawn_minutes: int) -> Dictionary:
	var into := (local_minutes - dawn_minutes + 1440) % 1440
	var limit := (threshold_minutes - dawn_minutes + 1440) % 1440
	return {"day": day_key, "early": into < limit}


## At launch: the visitors that came while the shed was closed, or none. One always comes after
## an early close (a reward for stopping is not a slot machine); a second may.
static func arrivals(close_up: Dictionary, today: String, tuning: Dictionary, rng: RandomNumberGenerator) -> Array[String]:
	var out: Array[String] = []
	if close_up.is_empty() or not bool(close_up.get("early", false)) or String(close_up.get("day", "")) >= today:
		return out
	var weights: Dictionary = tuning["species"].duplicate()
	var first := _pick(weights, rng)
	if first == "":
		return out
	out.append(first)
	weights.erase(first)
	if rng.randf() < float(tuning["second_chance"]):
		var second := _pick(weights, rng)
		if second != "":
			out.append(second)
	return out


static func _pick(weights: Dictionary, rng: RandomNumberGenerator) -> String:
	var total := 0.0
	for id in weights:
		total += float(weights[id])
	if total <= 0.0:
		return ""
	var roll := rng.randf() * total
	for id in weights:
		roll -= float(weights[id])
		if roll < 0.0:
			return String(id)
	return String(weights.keys()[-1])

