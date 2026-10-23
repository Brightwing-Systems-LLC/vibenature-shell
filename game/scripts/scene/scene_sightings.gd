class_name SceneSightings
extends RefCounted

## Every species seen in the scene, with when it was first and last seen: the book's field guide
## (Skypatch issue 177). `SceneBehaviour` calls `saw` when
## an animal comes into view (a creature or group, a songbird party by its cast member, a fish swimming
## in the cut-away, a dragonfly); birds only going over are not counted. Kept in the save.
##
## Only what was seen: never a list to complete, never what has not been seen yet.

signal changed

## Poses for the guide's picture, the first a sheet has; else its first animation.
const PICTURE_POSES: Array[String] = ["perch", "idle", "bask", "swim", "hover", "soar", "fly"]

## key -> {first, last (unix seconds), times, name, sheet}
var seen: Dictionary = {}


## `key` (a species id, or a songbird cast member's) was seen at `unix`.
func saw(key: String, display_name: String, sheet: String, unix: float) -> void:
	if key == "":
		return
	if seen.has(key):
		var entry: Dictionary = seen[key]
		entry["last"] = maxf(float(entry["last"]), unix)
		entry["first"] = minf(float(entry["first"]), unix)
		entry["times"] = int(entry.get("times", 1)) + 1
	else:
		seen[key] = {"first": unix, "last": unix, "times": 1, "name": display_name, "sheet": sheet}
	changed.emit()


## Every species seen, most recently seen first: [{key, first, last, times, name, sheet}].
func entries() -> Array:
	var out: Array = []
	for key in seen:
		out.append((seen[key] as Dictionary).merged({"key": key}))
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a["last"]) > float(b["last"]) if a["last"] != b["last"] else String(a["key"]) < String(b["key"]))
	return out


func to_dict() -> Dictionary:
	return {"seen": seen.duplicate(true)}


func from_dict(d: Dictionary) -> void:
	seen = {}
	var saved = d.get("seen", {})
	if not saved is Dictionary:
		return
	for key in saved:
		var e = saved[key]
		if e is Dictionary and e.has("first") and e.has("last"):
			seen[String(key)] = {"first": float(e["first"]), "last": float(e["last"]), "times": int(e.get("times", 1)),
					"name": String(e.get("name", key)), "sheet": String(e.get("sheet", ""))}


## A plain name from the species data or a sheet's meta: no article, nothing in brackets.
static func plain_name(raw: String) -> String:
	var n := raw.strip_edges()
	var bracket := n.find(" (")
	if bracket > 0:
		n = n.substr(0, bracket)
	for article in ["a ", "an ", "the "]:
		if n.to_lower().begins_with(article):
			n = n.substr(article.length())
	return n


## The name and sheet of species `sp` (or its songbird cast `member`).
static func describe(sp: SceneSpecies, member: Dictionary = {}) -> Dictionary:
	if not member.is_empty() and String(member.get("id", "")) != "":
		var id := String(member["id"])
		var meta := SceneSightings.sheet_meta(id)
		return {"key": id, "name": SceneSightings.plain_name(String(meta.get("species", id.replace("_", " ")))), "sheet": id}
	var sheet := ""
	var adults: Array = sp.data.get("sheets", {}).get("adult", [])
	if not adults.is_empty():
		sheet = String(adults[0].get("id", ""))
	return {"key": sp.id, "name": SceneSightings.plain_name(String(sp.data.get("name", sp.id.replace("_", " ")))), "sheet": sheet}


static func sheet_meta(sheet: String) -> Dictionary:
	var path := SceneSheet.dir_of(sheet).path_join("meta.json")
	if sheet == "" or not FileAccess.file_exists(path):
		return {}
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if parsed is Dictionary else {}


## One frame of the sheet in a resting pose (the side view's master), or null without a sheet.
static func picture(sheet: String) -> Texture2D:
	var meta := SceneSightings.sheet_meta(sheet)
	if not meta.has("views"):
		return null
	var views: Dictionary = meta["views"]
	var view := "side" if views.has("side") else String(views.keys()[0])
	var spec: Dictionary = views[view]
	var file := SceneSheet.dir_of(sheet).path_join("%s_%s.png" % [sheet, view])
	var tex := AssetLibrary.cached_texture(file)
	if tex == null:
		return null
	var anims: Dictionary = spec.get("animations", {})
	var frame := 0
	var pose := ""
	for p in PICTURE_POSES:
		if anims.has(p):
			pose = p
			break
	if pose == "" and not anims.is_empty():
		pose = String(anims.keys()[0])
	if pose != "":
		var frames: Array = anims[pose].get("frames", [0])
		frame = int(frames[0]) if not frames.is_empty() else 0
	var fw := float(spec["frame_w"])
	var fh := float(spec["frame_h"])
	var cols := maxi(1, int(round(tex.get_width() / fw)))
	var atlas := AtlasTexture.new()
	atlas.atlas = tex
	atlas.region = Rect2((frame % cols) * fw, (frame / cols) * fh, fw, fh)
	return atlas
