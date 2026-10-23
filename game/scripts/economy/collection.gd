class_name Collection
extends RefCounted

## The patches the player has. The starters from day one; the rest turn up on their
## own as days pass from install (playing is never required, §2.3), or can be bought
## early with patch bucks. Seasonal patches are out during their season unless the
## player turns them off, and keep their state for next year.
##
## Catalogue entries (config/content.json `patches`) may carry: "starter": true,
## "arrives_after_days": N, "price": bucks, "season": {"from": "MM-DD", "to": "MM-DD"}.

var installed_on := ""
## id -> {"since": day_key, "how": "starter" | "arrived" | "bought"}
var owned: Dictionary = {}


## Brings the collection up to `today`. Returns the ids that arrived just now.
func update(catalogue: Dictionary, today: String) -> Array:
	if installed_on == "":
		installed_on = today
	var arrived: Array = []
	var days := GameClock.days_between(installed_on, today)
	for id in catalogue:
		var entry: Dictionary = catalogue[id]
		if owned.has(id) or entry.has("season"):
			continue
		if bool(entry.get("starter", false)):
			owned[id] = {"since": installed_on, "how": "starter"}
		elif entry.has("arrives_after_days") and days >= int(entry["arrives_after_days"]):
			owned[id] = {"since": today, "how": "arrived"}
			arrived.append(String(id))
	return arrived


## Buys a patch early. False if it is already owned, seasonal, not for sale, or the
## player is short of bucks.
func buy(id: String, catalogue: Dictionary, economy: Economy, today: String) -> bool:
	var entry: Dictionary = catalogue.get(id, {})
	if entry.is_empty() or owned.has(id) or entry.has("season") or not entry.has("price"):
		return false
	if not economy.spend(int(entry["price"])):
		return false
	owned[id] = {"since": today, "how": "bought"}
	return true


## Whether a seasonal entry is in season on `today` ("YYYY-MM-DD"); seasons may wrap
## the new year ("12-20" to "01-05").
static func in_season(entry: Dictionary, today: String) -> bool:
	if not entry.has("season"):
		return false
	var month_day := today.substr(5, 5)
	var from := String(entry["season"]["from"])
	var to := String(entry["season"]["to"])
	if from <= to:
		return month_day >= from and month_day <= to
	return month_day >= from or month_day <= to


## The everyday patches the roster chooses from (owned, not seasonal), in catalogue
## order.
func regulars(catalogue: Dictionary) -> Array:
	var ids: Array = []
	for id in catalogue:
		if owned.has(id) and not catalogue[id].has("season"):
			ids.append(String(id))
	return ids


## What is out today: the roster's pick of the regulars, plus anything that arrived
## or was bought today (so the player meets it), plus seasonal patches in season that
## the player has not turned off. Catalogue order.
func out_today(catalogue: Dictionary, roster: Dictionary, today: String) -> Array:
	var picked := Roster.pick(regulars(catalogue), roster, today)
	var seasonal_off: Array = roster.get("seasonal_off", [])
	var out: Array = []
	for id in catalogue:
		var entry: Dictionary = catalogue[id]
		var show := picked.has(id)
		if owned.has(id) and String(owned[id]["since"]) == today and owned[id]["how"] != "starter":
			show = true
		if Collection.in_season(entry, today) and not seasonal_off.has(id):
			show = true
		if show:
			out.append(String(id))
	return out


func to_dict() -> Dictionary:
	return {"installed_on": installed_on, "owned": owned.duplicate(true)}


func from_dict(d: Dictionary) -> void:
	installed_on = String(d.get("installed_on", ""))
	owned = d.get("owned", {}).duplicate(true)
