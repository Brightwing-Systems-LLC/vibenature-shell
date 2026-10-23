class_name Economy
extends RefCounted

## Patch bucks, the bin and the player's small inventory. Today's deposits become
## spendable at the next dawn (§3.5), and the stipend arrives then too. A missed day
## still pays its stipend (up to a cap), so being away never costs anything.

var bucks := 0
var bin: Array = []
var day_key := ""
var seeds: Dictionary = {}
var bait := 0


static func starting(start: Dictionary) -> Economy:
	var economy := Economy.new()
	economy.bucks = int(start.get("bucks", 0))
	economy.seeds = start.get("seeds", {}).duplicate(true)
	economy.bait = int(start.get("bait", 0))
	return economy


## An item is {"kind": "polaroid" | "fish" | "bouquet", "id": String, "rarity": String,
## "value": int}.
func deposit(item: Dictionary) -> void:
	bin.append(item.duplicate(true))


func bin_total() -> int:
	var total := 0
	for item in bin:
		total += int(item.get("value", 0))
	return total


## At the first check of a new game day: the bin converts and the stipend arrives.
## Returns the bucks added. The very first day only records the date.
func roll_over(new_day_key: String, stipend: int, catchup_days_max: int) -> int:
	if new_day_key == day_key:
		return 0
	if day_key == "":
		day_key = new_day_key
		return 0
	var days := clampi(GameClock.days_between(day_key, new_day_key), 1, maxi(1, catchup_days_max))
	var added := bin_total() + stipend * days
	bucks += added
	bin.clear()
	day_key = new_day_key
	return added


## Spends bucks if there are enough. Prices are small on purpose (§3.5).
func spend(amount: int) -> bool:
	if amount < 0 or bucks < amount:
		return false
	bucks -= amount
	return true


func take_seed() -> String:
	var names := seeds.keys()
	names.sort()
	for species in names:
		if int(seeds[species]) > 0:
			seeds[species] = int(seeds[species]) - 1
			return String(species)
	return ""


func take_bait() -> bool:
	if bait <= 0:
		return false
	bait -= 1
	return true


func to_dict() -> Dictionary:
	return {"bucks": bucks, "bin": bin.duplicate(true), "day_key": day_key, "seeds": seeds.duplicate(true), "bait": bait}


func from_dict(d: Dictionary) -> void:
	bucks = int(d.get("bucks", bucks))
	bin = d.get("bin", []).duplicate(true)
	day_key = String(d.get("day_key", ""))
	seeds = d.get("seeds", seeds).duplicate(true)
	bait = int(d.get("bait", bait))
