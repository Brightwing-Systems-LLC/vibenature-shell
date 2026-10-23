class_name Balance
extends RefCounted

const DEFAULT_PATH := "res://config/balance.json"

var data: Dictionary


static func load_from(path: String) -> Balance:
	var text := FileAccess.get_file_as_string(path)
	var parsed = JSON.parse_string(text)
	assert(parsed is Dictionary, "balance.json did not parse to an object: %s" % path)
	var balance := Balance.new()
	balance.data = parsed
	return balance


## The game's numbers with each package's tuning put in place (contract §8: the pond's director, sky,
## light, weather and moments live in its package, `ScenePackages.apply_tuning`).
static func load_default() -> Balance:
	var balance := load_from(DEFAULT_PATH)
	ScenePackages.apply_tuning(balance.data)
	return balance


func daily_stipend() -> int:
	return int(data["daily_stipend"])
