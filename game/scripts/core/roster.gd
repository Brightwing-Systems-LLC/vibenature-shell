class_name Roster
extends RefCounted

## Which patches are out. The player chooses (settings `roster`):
## - "all": every patch in the catalogue;
## - "chosen": their own list;
## - "daily": `daily_count` of them, picked at dawn and the same all day.
## A patch that is not out keeps its state, so rotating never costs anything.


static func pick(catalogue: Array, roster: Dictionary, day_key: String) -> Array:
	var mode := String(roster.get("mode", "all"))
	var out: Array = []
	if mode == "chosen":
		for id in roster.get("chosen", []):
			if catalogue.has(id) and not out.has(id):
				out.append(String(id))
		if not out.is_empty():
			return out
	if mode == "daily":
		var count := clampi(int(roster.get("daily_count", catalogue.size())), 1, maxi(1, catalogue.size()))
		var pool := catalogue.duplicate()
		pool.sort()
		var rng := RandomNumberGenerator.new()
		rng.seed = hash(day_key + ":roster")
		while out.size() < count and not pool.is_empty():
			out.append(String(pool.pop_at(rng.randi() % pool.size())))
		# Keep catalogue order on screen, whatever the draw order.
		var ordered: Array = []
		for id in catalogue:
			if out.has(id):
				ordered.append(String(id))
		return ordered
	for id in catalogue:
		out.append(String(id))
	return out
