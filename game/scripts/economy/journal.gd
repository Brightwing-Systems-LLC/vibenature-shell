class_name Journal
extends RefCounted

## The life list (every bird photographed, fish caught, flower grown, night visitor), the day
## each species was first and last recorded, and each day's visitors page. Nothing here is
## ever taken away (SPEC §2.2): pruning drops old day pages, never the life list.

const CATEGORIES: Array[String] = ["birds", "fish", "flowers", "night"]

var life: Dictionary = {"birds": {}, "fish": {}, "flowers": {}, "night": {}}
## category -> {species -> day_key}. Saves from before issue 77 have no dates.
var first_seen: Dictionary = {"birds": {}, "fish": {}, "flowers": {}, "night": {}}
var last_seen: Dictionary = {"birds": {}, "fish": {}, "flowers": {}, "night": {}}
## day_key -> {"visitors": [species, …]}
var days: Dictionary = {}


## Returns true the first time this species enters the life list.
func record(category: String, id: String, day_key: String) -> bool:
	var list: Dictionary = life[category]
	var first := not list.has(id)
	list[id] = int(list.get(id, 0)) + 1
	if not first_seen[category].has(id):
		first_seen[category][id] = day_key
	last_seen[category][id] = day_key
	if not days.has(day_key):
		days[day_key] = {"visitors": []}
	var visitors: Array = days[day_key]["visitors"]
	if not visitors.has(id):
		visitors.append(id)
	return first


## The life list of `category` for the journal view, most recently seen first:
## [{"id", "count", "first", "last"}]; a date is "" when an old save did not keep it.
func entries(category: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for id in life[category]:
		out.append({
			"id": String(id), "count": int(life[category][id]),
			"first": String(first_seen[category].get(id, "")), "last": String(last_seen[category].get(id, "")),
		})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if a["last"] != b["last"]:
			return a["last"] > b["last"]
		return a["id"] < b["id"])
	return out


func prune(days_kept: int) -> void:
	var keys := days.keys()
	keys.sort()
	while keys.size() > days_kept:
		days.erase(keys.pop_front())


func to_dict() -> Dictionary:
	return {"life": life.duplicate(true), "first_seen": first_seen.duplicate(true),
			"last_seen": last_seen.duplicate(true), "days": days.duplicate(true)}


func from_dict(d: Dictionary) -> void:
	_load_into(life, d.get("life", {}))
	_load_into(first_seen, d.get("first_seen", {}))
	_load_into(last_seen, d.get("last_seen", {}))
	days = d.get("days", {}).duplicate(true)


static func _load_into(mine: Dictionary, loaded: Dictionary) -> void:
	for category in CATEGORIES:
		if loaded.has(category):
			mine[category] = loaded[category].duplicate(true)
