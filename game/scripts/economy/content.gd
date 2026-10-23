class_name Content
extends RefCounted

## What the game knows about (config/content.json): the patch catalogue (each
## patch's mechanic and the tools it brings), the tools, and birds, fish and flowers
## by rarity. Island packs (contract §5) add their own catalogue entries and tools
## (`add_pack`); a new island is a pack, not an entry here.

const DEFAULT_PATH := "res://config/content.json"
const RARITIES: Array[String] = ["common", "uncommon", "rare"]

var data: Dictionary


static func load_default() -> Content:
	return load_from(DEFAULT_PATH)


static func load_from(path: String) -> Content:
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	assert(parsed is Dictionary, "content.json did not parse to an object: %s" % path)
	var content := Content.new()
	content.data = parsed
	return content


## Adds an island pack's catalogue entry and its tools' colours.
func add_pack(pack: IslandPack) -> void:
	if not data.has("patches"):
		data["patches"] = {}
	data["patches"][pack.id] = pack.catalogue_entry()
	if not data.has("tools"):
		data["tools"] = {}
	for t in pack.tools:
		if not data["tools"].has(t["id"]):
			data["tools"][t["id"]] = {"color": t["color"], "icon": pack.root.path_join(t["icon"]) if t["icon"] != "" else ""}


## The display name of a catalogue island.
func patch_name(patch_id: String) -> String:
	var entry: Dictionary = data.get("patches", {}).get(patch_id, {})
	return String(entry.get("name", patch_id.trim_suffix("_base").replace("_", " ").capitalize()))


func species(category: String) -> Dictionary:
	return data.get(category, {})


func rarity_of(category: String, id: String) -> String:
	return String(species(category).get(id, {}).get("rarity", "common"))


func color_of(category: String, id: String) -> Color:
	return Color(String(species(category).get(id, {}).get("color", "ffffff")))


## A species' name for the journal: its `name`, else the id in words ("Northern Cardinal").
func species_name(category: String, id: String) -> String:
	return String(species(category).get(id, {}).get("name", id.replace("_", " ").capitalize()))


func asset_of(category: String, id: String) -> String:
	return String(species(category).get(id, {}).get("asset", id))


func patch_ids() -> Array:
	return data.get("patches", {}).keys()


func catalogue() -> Dictionary:
	return data.get("patches", {})


func mechanic_for(patch_id: String) -> String:
	return String(data.get("patches", {}).get(patch_id, {}).get("mechanic", ""))


## The rack for these patches: the shared tools, then each patch's own, in catalogue
## order, each once.
func tools_for(patch_ids_out: Array) -> Array:
	var tools: Array = []
	for tool_id in data.get("shared_tools", []):
		if not tools.has(tool_id):
			tools.append(String(tool_id))
	for patch_id in patch_ids():
		if not patch_ids_out.has(patch_id):
			continue
		for tool_id in data["patches"][patch_id].get("tools", []):
			if not tools.has(tool_id):
				tools.append(String(tool_id))
	return tools


## An island's tool squares: its own tools, then the shared ones (the camera works on any
## island a bird lands on).
func patch_tools(patch_id: String) -> Array:
	var tools: Array = []
	for tool_id in data.get("patches", {}).get(patch_id, {}).get("tools", []):
		tools.append(String(tool_id))
	for tool_id in data.get("shared_tools", []):
		if not tools.has(tool_id):
			tools.append(String(tool_id))
	return tools


func default_tool(patch_id: String) -> String:
	var tools := patch_tools(patch_id)
	var wanted := String(data.get("patches", {}).get(patch_id, {}).get("default_tool", ""))
	if tools.has(wanted):
		return wanted
	return String(tools[0]) if not tools.is_empty() else ""


## A tool's icon inside its island pack, or "" (then the game's own delivery, or a square).
func tool_icon_path(tool_id: String) -> String:
	return String(data.get("tools", {}).get(tool_id, {}).get("icon", ""))


func tool_color(tool_id: String) -> Color:
	return Color(String(data.get("tools", {}).get(tool_id, {}).get("color", "ffffff")))


## Picks a rarity by weight (rare weighted up during a golden window), then a species
## of that rarity in season. Returns "" if nothing is eligible.
func pick(category: String, weights: Dictionary, rng: RandomNumberGenerator, month: int, rare_multiplier: float = 1.0,
		only: Array = []) -> String:
	var pools := {}
	for id in species(category):
		if not only.is_empty() and not only.has(id):
			continue
		var entry: Dictionary = species(category)[id]
		if entry.has("months") and not _contains_int(entry["months"], month):
			continue
		var rarity := String(entry.get("rarity", "common"))
		if not pools.has(rarity):
			pools[rarity] = []
		pools[rarity].append(id)
	var total := 0.0
	var options: Array = []
	for rarity in RARITIES:
		if not pools.has(rarity):
			continue
		var weight := float(weights.get(rarity, 0.0))
		if rarity == "rare":
			weight *= rare_multiplier
		if weight > 0.0:
			options.append([rarity, weight])
			total += weight
	if options.is_empty():
		return ""
	var roll := rng.randf() * total
	var chosen: String = options[-1][0]
	for option in options:
		roll -= float(option[1])
		if roll <= 0.0:
			chosen = option[0]
			break
	var pool: Array = pools[chosen]
	pool.sort()
	return String(pool[rng.randi() % pool.size()])


## JSON numbers arrive as floats.
static func _contains_int(values: Array, wanted: int) -> bool:
	for value in values:
		if int(value) == wanted:
			return true
	return false
