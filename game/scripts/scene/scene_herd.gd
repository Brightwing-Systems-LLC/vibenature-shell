class_name SceneHerd
extends RefCounted

## Who comes together, for an animal that comes in natural groups (issue 320):
## white-tailed deer at a pond. Most often a lone doe or a doe with her fawns of the year; sometimes
## two related does with theirs; never more than two does together outside winter; a buck alone (in
## the rut sometimes trailing a doe group at a distance; in late summer now and then two bucks
## together), never inside a doe's group. Pure: everything comes from the species' `herd` data and
## the caller's generator.


## The season `month` (1..12) falls in, by the herd's `seasons` ({name: [months]}).
static func season(herd: Dictionary, month: int) -> String:
	var seasons: Dictionary = herd.get("seasons", {})
	for s in seasons:
		if month in (seasons[s] as Array).map(func(m) -> int: return int(m)):
			return String(s)
	return ""


## One group for `month`: members in arrival order, the first the leader. Each is {sheet, young,
## role ("lead", "doe", "buck", "trail", "fawn"), mother (index of its doe, -1), spacing ([lo, hi]
## metres from whom it keeps by: its mother for a fawn, else the leader), kind (the group's id)}.
## `max_adults`/`max_members` (0: no limit) leave out kinds that need more room than the place has.
static func compose(herd: Dictionary, month: int, rng: RandomNumberGenerator, max_adults: int = 0, max_members: int = 0) -> Array:
	var kind := pick_kind(herd, month, rng, max_adults, max_members)
	if kind.is_empty():
		return []
	return members(herd, kind, month, rng, max_members)


## A kind of group for `month`, by its season's weights; {} when none fits.
static func pick_kind(herd: Dictionary, month: int, rng: RandomNumberGenerator, max_adults: int = 0, max_members: int = 0) -> Dictionary:
	var s := season(herd, month)
	var options: Array = []
	var total := 0.0
	for k in herd.get("kinds", []):
		var kind: Dictionary = k
		var w := float(kind.get("weights", {}).get(s, 0.0))
		if w <= 0.0:
			continue
		if max_adults > 0 and adults_min(kind) > max_adults:
			continue
		if max_members > 0 and adults_min(kind) + int(_range(kind, "fawns").x) > max_members:
			continue
		options.append(kind)
		total += w
	if options.is_empty():
		return {}
	var roll := rng.randf() * total
	for kind in options:
		roll -= float(kind["weights"][s])
		if roll <= 0.0:
			return kind
	return options[-1]


## The fewest adults a kind brings (does, bucks; a trailing buck comes on his own way).
static func adults_min(kind: Dictionary) -> int:
	return int(_range(kind, "does").x) + int(_range(kind, "bucks").x)


static func members(herd: Dictionary, kind: Dictionary, month: int, rng: RandomNumberGenerator, max_members: int = 0) -> Array:
	var spacing: Dictionary = herd.get("spacing_m", {})
	var sheets: Dictionary = herd.get("sheets", {})
	var out: Array = []
	var does := _roll(kind, "does", rng)
	var bucks := _roll(kind, "bucks", rng)
	var cap := int(herd.get("group_max", 6))
	if max_members > 0:
		cap = mini(cap, max_members)
	var fawns_left := int(herd.get("fawns_max", 3))
	for i in does:
		out.append({"sheet": String(sheets.get("doe", "")), "young": false, "role": "lead" if out.is_empty() else "doe", "mother": -1,
				"spacing": spacing.get("adult", [3, 10]), "kind": String(kind.get("id", ""))})
	for i in bucks:
		out.append({"sheet": String(sheets.get("buck", "")), "young": false, "role": "lead" if out.is_empty() else "buck", "mother": -1,
				"spacing": spacing.get("buck_pair", spacing.get("adult", [3, 10])), "kind": String(kind.get("id", ""))})
	var fawn_sheet := fawn_sheet_for(herd, month)
	if not fawn_season(herd, month):
		# Last year's fawns are yearlings by spring, on their own; this year's are not born yet.
		fawns_left = 0
	for i in does:
		for f in _roll(kind, "fawns", rng):
			if fawns_left <= 0 or out.size() >= cap:
				break
			fawns_left -= 1
			out.append({"sheet": fawn_sheet, "young": true, "role": "fawn", "mother": i, "spacing": spacing.get("fawn", [1, 4]),
					"kind": String(kind.get("id", ""))})
	if bool(kind.get("trailing_buck", false)) and out.size() < cap:
		out.append({"sheet": String(sheets.get("buck", "")), "young": false, "role": "trail", "mother": -1,
				"spacing": spacing.get("trail", [15, 35]), "kind": String(kind.get("id", ""))})
	return out


## The fawn sheet for `month`: the first of `sheets.fawn` ([{id, months}]) whose months hold it and
## that the bench has drawn (`exists`, a Callable; by default `SceneSheet.exists`), else the first drawn.
static func fawn_sheet_for(herd: Dictionary, month: int, exists: Callable = Callable()) -> String:
	var options: Array = herd.get("sheets", {}).get("fawn", [])
	var drawn := func(id: String) -> bool: return exists.call(id) if exists.is_valid() else SceneSheet.exists(id)
	for o in options:
		var months: Array = (o as Dictionary).get("months", [])
		if (months.is_empty() or month in months.map(func(m) -> int: return int(m))) and drawn.call(String(o["id"])):
			return String(o["id"])
	for o in options:
		if drawn.call(String(o["id"])):
			return String(o["id"])
	return ""


## Whether a doe has fawns at heel in `month`: any month a fawn sheet is listed for.
static func fawn_season(herd: Dictionary, month: int) -> bool:
	for o in herd.get("sheets", {}).get("fawn", []):
		if month in (o as Dictionary).get("months", []).map(func(m) -> int: return int(m)):
			return true
	return false


static func _range(kind: Dictionary, key: String) -> Vector2:
	var v: Variant = kind.get(key, 0)
	if v is Array:
		return Vector2(float(v[0]), float(v[1]))
	return Vector2(float(v), float(v))


static func _roll(kind: Dictionary, key: String, rng: RandomNumberGenerator) -> int:
	var r := _range(kind, key)
	return rng.randi_range(int(r.x), int(r.y))
