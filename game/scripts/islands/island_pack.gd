class_name IslandPack
extends RefCounted

## One island as a self-contained pack (contract §5,
## Skypatch issue 32): everything the island is, in
## one folder mounted at res://islands/<id>/. `island.json` says what is in it; the rest is
## its mechanic script (and the scripts that one preloads, by relative path), its numbers
## (`balance.json`), and art the bench delivers under `art/` and `avatar_poses/`.
##
## `read` checks a pack against the format and fills `problem` with why it cannot be used,
## or leaves it "". A pack's scripts never declare `class_name`: an installed pack cannot add
## global classes, and two packs could clash.

const FORMAT := 1
const MANIFEST := "island.json"
const ID_PATTERN := "^[a-z][a-z0-9_]{1,39}$"
const SPOT_KINDS: Array[String] = ["plot", "water", "perch", "stand", "ground", "hive"]
## World signals a pack may listen for: the coarse ones the game already has, nothing more.
const SIGNALS: Array[String] = ["sunlight", "cloud", "bird_roll", "fish_roll", "rain", "new_day", "golden_window"]
const CATALOGUE_KEYS: Array[String] = ["starter", "arrives_after_days", "price", "season"]
## Rank size class to depth layer: large creatures stand in front, small ones at the back.
const LAYER_BY_SIZE := {"large": "front", "medium": "mid", "small": "back"}
## The bench's places on the island art (contract §5, 0.9).
const ART_META := "art/meta.json"

var id := ""
var name := ""
var version := ""
var min_game_version := ""
var author := ""
## res://islands/<id>
var root := ""
## "built-in" or "installed".
var source := "built-in"
var manifest: Dictionary = {}
## Ids this island had before it was a pack; saves under them carry over.
var formerly: Array = []
var catalogue: Dictionary = {}
var geometry: Dictionary = {}
var spots: Dictionary = {}
## [{"id", "action", "color", "icon"}]
var tools: Array = []
var default_tool := ""
var mechanic := ""
var balance: Dictionary = {}
var avatar_poses: Dictionary = {}
var triggers: Dictionary = {}
var settings: Dictionary = {}
var art: Dictionary = {}
## `art/meta.json` as the bench delivered it (size, depth, spots in art pixels), or {}.
var art_meta: Dictionary = {}
## True when the pack has its art and an `art/meta.json` with spots: its places come from the
## picture, and `geometry` and `spots` in `island.json` are ignored (contract §5, 0.9).
var illustrated := false
## Why the pack cannot be used, or "".
var problem := ""


## Reads and checks the pack at `pack_root` against the shelf rules in `shelf`.
static func read(pack_root: String, shelf: Dictionary) -> IslandPack:
	var pack := IslandPack.new()
	pack.root = pack_root.trim_suffix("/")
	pack.problem = pack._read(shelf)
	return pack


func _read(shelf: Dictionary) -> String:
	var path := root.path_join(MANIFEST)
	if not FileAccess.file_exists(path):
		return "no %s" % MANIFEST
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not parsed is Dictionary:
		return "%s does not parse to an object" % MANIFEST
	manifest = parsed
	if int(manifest.get("format", 0)) < 1:
		return "no pack format"
	if int(manifest["format"]) > FORMAT:
		return "pack format %d is newer than this game reads (%d): update the game" % [int(manifest["format"]), FORMAT]
	id = String(manifest.get("id", ""))
	if not RegEx.create_from_string(ID_PATTERN).search(id):
		return "id %s is not snake_case" % id
	if id != root.get_file():
		return "id %s does not match its folder %s" % [id, root.get_file()]
	name = String(manifest.get("name", ""))
	version = String(manifest.get("version", ""))
	min_game_version = String(manifest.get("min_game_version", ""))
	author = String(manifest.get("author", ""))
	if name == "" or author == "":
		return "name and author are required"
	if parse_version(version).is_empty() or parse_version(min_game_version).is_empty():
		return "version and min_game_version must be x.y.z"
	formerly = manifest.get("formerly", [])
	catalogue = manifest.get("catalogue", {})
	for key in catalogue:
		if not CATALOGUE_KEYS.has(String(key)):
			return "unknown catalogue key %s" % key
	art = manifest.get("art", {})
	var why := _read_art_meta()
	if why != "":
		return why
	geometry = manifest.get("geometry", {})
	if not illustrated:
		why = _check_geometry(shelf)
		if why != "":
			return why
	why = _read_tools()
	if why != "":
		return why
	mechanic = String(manifest.get("mechanic", ""))
	if mechanic == "" or not mechanic.ends_with(".gd") or not FileAccess.file_exists(root.path_join(mechanic)):
		return "mechanic %s is missing" % mechanic
	if manifest.has("balance"):
		var numbers = JSON.parse_string(FileAccess.get_file_as_string(root.path_join(String(manifest["balance"]))))
		if not numbers is Dictionary:
			return "balance %s does not parse to an object" % manifest["balance"]
		balance = numbers
	avatar_poses = manifest.get("avatar_poses", {})
	for action in avatar_poses.get("actions", []):
		if not String(action).is_valid_identifier():
			return "avatar pose action %s is not a name" % action
	triggers = manifest.get("triggers", {})
	for kind in triggers.get("listens", []):
		if not SIGNALS.has(String(kind)):
			return "triggers listen for %s, which is not a world signal" % kind
	settings = manifest.get("settings", {})
	return ""


## Reads `art/meta.json` when the pack has its island art. With spots it makes the pack
## illustrated; a meta file that is there but wrong refuses the pack.
func _read_art_meta() -> String:
	var art_path := String(art.get("island", ""))
	var meta_path := root.path_join(ART_META)
	if not AssetLibrary.image_exists(root.path_join(art_path)) or not FileAccess.file_exists(meta_path):
		return ""
	var json := JSON.new()
	if json.parse(FileAccess.get_file_as_string(meta_path)) != OK or not json.data is Dictionary:
		return "%s does not parse to an object" % ART_META
	art_meta = json.data
	var raw_spots = art_meta.get("spots", {})
	if not raw_spots is Dictionary:
		return "%s: spots must be an object" % ART_META
	if raw_spots.is_empty():
		return ""
	var size: Array = art_meta.get("size", [])
	var depth: Dictionary = art_meta.get("depth", {})
	if size.size() != 2 or int(size[0]) < 1 or int(size[1]) < 1:
		return "%s needs a size [width, height]" % ART_META
	if not depth.has("back") or not depth.has("front") or float(depth["back"]) >= float(depth["front"]):
		return "%s needs depth {back, front} with back above front" % ART_META
	for spot_name in raw_spots:
		var spot = raw_spots[spot_name]
		if not spot is Dictionary:
			return "%s: spot %s is not an object" % [ART_META, spot_name]
		if not SPOT_KINDS.has(String(spot.get("kind", ""))):
			return "%s: spot %s: unknown kind %s" % [ART_META, spot_name, spot.get("kind", "")]
		var at: Array = spot.get("at", [])
		if at.size() != 2 or float(at[0]) < 0 or float(at[1]) < 0 or float(at[0]) >= float(size[0]) or float(at[1]) >= float(size[1]):
			return "%s: spot %s needs an at [x, y] inside the art" % [ART_META, spot_name]
		if spot.has("layer") and not PatchDef.LAYERS.has(String(spot["layer"])):
			return "%s: spot %s: unknown layer %s" % [ART_META, spot_name, spot["layer"]]
	spots = raw_spots
	illustrated = true
	return ""


func _check_geometry(shelf: Dictionary) -> String:
	for key in ["columns", "ranks", "rows"]:
		if not geometry.has(key):
			return "geometry needs %s" % key
	var why := ShelfGeometry.problem(int(geometry["columns"]), int(geometry["ranks"]), int(geometry["rows"]),
			ShelfDemo.NO_CUTS.merged(geometry.get("cuts", {}), true), geometry.get("pond", {}),
			geometry.get("pieces", [geometry["columns"]]), shelf)
	if why != "":
		return "geometry: " + why
	if not ShelfOutlines.NAMES.has(String(geometry.get("treatment", "A"))):
		return "geometry: unknown treatment %s" % geometry["treatment"]
	spots = manifest.get("spots", {})
	var geo := shelf_geometry(shelf)
	for spot_name in spots:
		var spot: Dictionary = spots[spot_name]
		if not SPOT_KINDS.has(String(spot.get("kind", ""))):
			return "spot %s: unknown kind %s" % [spot_name, spot.get("kind", "")]
		var cell: Array = spot.get("cell", [])
		if cell.size() != 2:
			return "spot %s needs a cell [column, rank]" % spot_name
		var column := int(cell[0])
		var rank := int(cell[1])
		if column < 0 or column >= geo.columns or rank < 1 or rank > geo.bands:
			return "spot %s: cell %s is off the grid" % [spot_name, cell]
		if not geo.in_top(cell_point(geo, column, rank)):
			return "spot %s: cell %s is off the top (a slanted side or a cut)" % [spot_name, cell]
		if spot["kind"] == "water" and not _in_pond(geo, column, rank):
			return "spot %s: water must be on the pond" % spot_name
		if spot.has("layer") and not PatchDef.LAYERS.has(String(spot["layer"])):
			return "spot %s: unknown layer %s" % [spot_name, spot["layer"]]
	return ""


func _read_tools() -> String:
	tools.clear()
	for entry in manifest.get("tools", []):
		if not entry is Dictionary or not String(entry.get("id", "")).is_valid_identifier():
			return "a tool needs an id"
		var icon := String(entry.get("icon", ""))
		if icon != "" and not AssetLibrary.image_exists(root.path_join(icon)):
			return "tool %s: icon %s is missing" % [entry["id"], icon]
		tools.append({"id": String(entry["id"]), "action": String(entry.get("action", entry["id"])),
				"color": String(entry.get("color", "ffffff")), "icon": icon})
	default_tool = String(manifest.get("default_tool", ""))
	return ""


static func _in_pond(geo: ShelfGeometry, column: int, rank: int) -> bool:
	var p := geo.pond
	return not p.is_empty() and column >= int(p["c0"]) and column < int(p["c1"]) and rank <= int(p["r1"])


## The middle of cell (column, rank) on the top, in island art px.
static func cell_point(geo: ShelfGeometry, column: int, rank: int) -> Vector2:
	return Vector2(geo.left_x() + (column + 0.5) * geo.cube, geo.edge_y(rank - 0.5))


## The island as a shelf spec (ShelfDemo's form), for ShelfGeometry, ShelfRenderer and the
## guide export.
func shelf_spec() -> Dictionary:
	var columns := int(geometry["columns"])
	return {
		"columns": columns, "bands": int(geometry["ranks"]), "rows": int(geometry["rows"]),
		"cuts": ShelfDemo.NO_CUTS.merged(geometry.get("cuts", {}), true), "pond": geometry.get("pond", {}),
		"pieces": geometry.get("pieces", [columns]), "treatment": String(geometry.get("treatment", "A")),
		"front_corners": geometry.get("front_corners", ["square", "square"]), "seed": int(geometry.get("seed", 1)),
		"taper": 0.0, "band_tint": false, "band_lines": false, "grid": false, "seams": false, "label": name,
	}


func shelf_geometry(shelf: Dictionary) -> ShelfGeometry:
	return ShelfDemo.geometry(shelf_spec(), shelf)


## Spot name -> {"layer", "at" (island px), "kind"}, placed on their cells. A spot's layer is
## its own, else the one its rank's creature size stands in.
func spot_points(geo: ShelfGeometry) -> Dictionary:
	var out := {}
	for spot_name in spots:
		var spot: Dictionary = spots[spot_name]
		var rank := int(spot["cell"][1])
		out[String(spot_name)] = {
			"layer": String(spot.get("layer", LAYER_BY_SIZE[geo.size_class(rank)])),
			"at": Vector2i(cell_point(geo, int(spot["cell"][0]), rank).round()),
			"kind": String(spot["kind"]),
		}
	return out


## The island's own art (`art.island`), else the shelf placeholder, and whether it is the
## placeholder.
func island_image(shelf: Dictionary) -> Array:
	var art_path := String(art.get("island", ""))
	var image := AssetLibrary.load_image(root.path_join(art_path)) if art_path != "" else null
	if image != null:
		return [image, false]
	if illustrated:
		# Its art will not decode: a plain block of the art's size keeps the spots on it.
		var blank := Image.create(int(art_meta["size"][0]), int(art_meta["size"][1]), false, Image.FORMAT_RGBA8)
		blank.fill(Color("5d8a52"))
		return [blank, true]
	return [ShelfRenderer.render(shelf_geometry(shelf), shelf, shelf_spec()), true]


func patch_def(shelf: Dictionary) -> PatchDef:
	var drawn := island_image(shelf)
	var places := art_spot_points() if illustrated else spot_points(shelf_geometry(shelf))
	return PatchDef.from_image(id, drawn[0], places, drawn[1])


## Spot name -> {"layer", "at" (island px), "kind"} from `art/meta.json`: each at its `at`,
## in its own layer, else the layer its y falls in (`layer_at`).
func art_spot_points() -> Dictionary:
	var out := {}
	for spot_name in spots:
		var spot: Dictionary = spots[spot_name]
		var at := Vector2i(roundi(float(spot["at"][0])), roundi(float(spot["at"][1])))
		out[String(spot_name)] = {
			"layer": String(spot.get("layer", layer_at(at.y))),
			"at": at,
			"kind": String(spot["kind"]),
		}
	return out


## The depth layer at art y on an illustrated island: thirds of the walkable top between
## `depth.back` and `depth.front` (back, mid, front); above the top is back, below it front.
func layer_at(y: float) -> String:
	var back := float(art_meta["depth"]["back"])
	var front := float(art_meta["depth"]["front"])
	var third := (front - back) / 3.0
	if y < back + third:
		return "back"
	if y < back + 2.0 * third:
		return "mid"
	return "front"


## The highest art y (the furthest back) still in `layer` by `layer_at`; for `back`, -INF.
func layer_top(layer: String) -> float:
	var back := float(art_meta["depth"]["back"])
	var third := (float(art_meta["depth"]["front"]) - back) / 3.0
	match layer:
		"front":
			return back + 2.0 * third
		"mid":
			return back + third
	return -INF


## A fresh instance of the island's mechanic, or null (logged) if its script will not load.
func make_mechanic() -> PatchMechanic:
	var script := load(root.path_join(mechanic)) as GDScript
	if script == null or not script.can_instantiate():
		push_warning("VibeNature: island %s: its mechanic %s does not load" % [id, mechanic])
		return null
	var made = script.new()
	if not made is PatchMechanic:
		push_warning("VibeNature: island %s: its mechanic does not extend PatchMechanic" % id)
		if made is Node:
			made.free()
		return null
	var out: PatchMechanic = made
	out.tuning = balance.duplicate(true)
	return out


func tool_ids() -> Array:
	return tools.map(func(t: Dictionary) -> String: return String(t["id"]))


## What the avatar does with `tool_id` here (its animation), or "" if the pack has no such tool.
func tool_action(tool_id: String) -> String:
	for t in tools:
		if t["id"] == tool_id:
			return String(t["action"])
	return ""


## The pack's pose folder for `avatar_id` doing `action`, or "" if it brings none (then the
## avatar's own animations play, as for any island).
func pose_dir(avatar_id: String, action: String) -> String:
	if not Array(avatar_poses.get("actions", [])).has(action):
		return ""
	var dir := root.path_join("avatar_poses").path_join(avatar_id)
	return dir if FileAccess.file_exists(dir.path_join("meta.json")) else ""


## What the content catalogue knows about the island.
func catalogue_entry() -> Dictionary:
	var entry := catalogue.duplicate(true)
	entry["mechanic"] = id
	entry["pack"] = id
	entry["name"] = name
	entry["tools"] = tool_ids()
	entry["default_tool"] = default_tool
	return entry


## Why this game (version `game_version`) cannot run the pack, or "".
func version_problem(game_version: String) -> String:
	if compare_versions(min_game_version, game_version) > 0:
		return "needs game %s or later; this is %s (it stays installed and loads after an update)" % [min_game_version, game_version]
	return ""


## [major, minor, patch], or [] if `text` is not x.y.z.
static func parse_version(text: String) -> Array:
	var parts := text.split(".")
	if parts.size() != 3:
		return []
	var out: Array = []
	for part in parts:
		if not part.is_valid_int() or int(part) < 0:
			return []
		out.append(int(part))
	return out


## -1, 0 or 1 as `a` is older than, the same as, or newer than `b`.
static func compare_versions(a: String, b: String) -> int:
	var x := parse_version(a)
	var y := parse_version(b)
	for i in 3:
		if int(x[i]) != int(y[i]):
			return -1 if int(x[i]) < int(y[i]) else 1
	return 0


## The game's own version (project.godot, application/config/version).
static func game_version() -> String:
	return String(ProjectSettings.get_setting("application/config/version", "0.0.0"))
