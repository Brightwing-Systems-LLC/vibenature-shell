class_name SceneKit
extends RefCounted

## A scene kit (contract §7): its scene package's `kit/kit.json` and its PNGs, or, until
## that lands, the placeholder cut from the pond art (`game/placeholders/scene/<id>/`). Read once,
## checked, and handed to the renderer as plain data. Pure apart from loading images.
##
## Field meanings (as the bench delivered forest_pond, Skypatch issue 99):
## everything is in art px of the kit, origin top-left; `art_scale` is art px per screen point; a
## piece's `at` is its top-left in the scene, its `pivot` and `perches` are in its own px; zone
## points are scene px; bands draw back to front, then by `z`. `zones` may be a list of
## {id, kind, band, polygon|lane} or a map kind -> [{band, polygon|lane}]; both read the same.

const DELIVERY := "res://assets/scene"
const PLACEHOLDER := "res://placeholders/scene"
## The placeholder cut from the old pond art: pixel art with an underwater cut-away, used when a
## scene has no delivery (and by the tests, for the underwater layer).
const PLACEHOLDER_ID := "pond"
const KINDS: Array[String] = ["tree", "crown", "branch", "trunk", "shrub", "reed", "grass", "fern", "flower", "rock",
		"log", "bank", "lily", "far_tree"]
## A far-band tree (Skypatch issue 165) says what it is: the
## type sets its stiffness, reach and leaf shimmer (`scene.sway.far_tree` in balance.json).
const FAR_TREES: Array[String] = ["conifer", "broadleaf"]
const ZONE_KINDS: Array[String] = ["canopy", "ground_far", "ground_mid", "shoreline", "water_surface", "underwater", "sky"]
## Kinds that never bend, whatever their sway says.
const RIGID: Array[String] = ["trunk", "rock", "log", "bank", "lily"]
## Plates sit behind the pieces of their band unless they say otherwise.
const PLATE_Z := -100

var id := ""
var root := ""
var is_placeholder := false
var data: Dictionary = {}
var size := Vector2i.ZERO
var art_scale := 1.0
## "pixel": hard-edged pixel art, sampled nearest and moved by whole art px; anything else is painted.
var style := ""
## [{id, scale}] back to front.
var bands: Array = []
var plates: Array = []
var pieces: Array = []
var water: Dictionary = {}
var zones: Array = []
var seat: Dictionary = {}
## The old composition inside a kit that grew past it (Skypatch issue 136):
## `origin` its top-left and `frame` its size, in kit px. Outside it is margin art that ends like a
## vignette. A kit without them is all frame.
var origin := Vector2i.ZERO
var frame := Vector2i.ZERO
var _problems: Array[String] = []


## The bench's kit `scene_id` if delivered (the scene package's `kit/`, else `delivery`), else the
## placeholder of the same id.
static func load_scene(scene_id: String, delivery: String = DELIVERY, placeholder: String = PLACEHOLDER) -> SceneKit:
	var kit := SceneKit.new()
	var folder := AssetLibrary.kit_dir(scene_id) if delivery == DELIVERY else delivery.path_join(scene_id)
	if FileAccess.file_exists(folder.path_join("kit.json")):
		kit.read(folder)
		return kit
	var own := placeholder.path_join(scene_id)
	kit.read(own if FileAccess.file_exists(own.path_join("kit.json")) else placeholder.path_join(PLACEHOLDER_ID))
	kit.is_placeholder = true
	return kit


func read(folder: String) -> void:
	root = folder
	var path := folder.path_join("kit.json")
	if not FileAccess.file_exists(path):
		_problems.append("no kit.json in %s" % folder)
		return
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not parsed is Dictionary:
		_problems.append("kit.json does not parse")
		return
	data = parsed
	id = String(data.get("id", folder.get_file()))
	size = _vec2i(data.get("size", [0, 0]))
	art_scale = float(data.get("art_scale", 1.0))
	style = String(data.get("style", ""))
	bands = data.get("bands", [])
	plates = data.get("plates", [])
	pieces = data.get("pieces", [])
	water = data.get("water", {})
	zones = SceneKit.zone_list(data.get("zones", []))
	origin = _vec2i(data.get("origin", [0, 0]))
	frame = _vec2i(data.get("frame", [size.x - origin.x, size.y - origin.y]))
	var raw_seat = data.get("seat", {})
	if raw_seat is Array:
		seat = {"at": raw_seat, "band": _front_band(), "z": 0}
	elif raw_seat is Dictionary:
		seat = raw_seat
	if not seat.has("z") and seat.has("at"):
		seat["z"] = _seat_z(Vector2(_vec2i(seat["at"])))
	_check()


## The z just in front of the log the seat is on (or 0).
func _seat_z(at: Vector2) -> float:
	for p in pieces:
		if String(p.get("kind", "")) != "log":
			continue
		var rect := Rect2(Vector2(_vec2i(p["at"])), Vector2(_vec2i(p.get("size", [0, 0]))))
		if rect.has_point(at) or rect.size == Vector2.ZERO:
			return float(p.get("z", 0)) + 0.5
	return 0.0


## Zones as a list of {id, kind, band, polygon|lane}, from either shape.
static func zone_list(raw) -> Array:
	if raw is Array:
		return raw
	var out: Array = []
	if raw is Dictionary:
		for kind in raw:
			var entries = raw[kind]
			if entries is Dictionary:
				entries = [entries]
			var n := 0
			for entry in entries:
				var zone: Dictionary = entry.duplicate()
				zone["kind"] = String(kind)
				zone["id"] = String(zone.get("id", "%s_%d" % [kind, n]))
				out.append(zone)
				n += 1
	return out


## The old composition in kit px (the whole kit when it never grew).
func frame_rect() -> Rect2:
	return Rect2(Vector2(origin), Vector2(frame))


## Whether the kit has margin art around its frame.
func has_margin() -> bool:
	return frame_rect() != Rect2(Vector2.ZERO, Vector2(size))


## The piece an edge piece continues across the old border (`follows`), or "".
static func parent_of(spec: Dictionary) -> String:
	return String(spec.get("follows", ""))


## A single leaf or tiny cluster the game may let fall now and then (`drop`).
static func drops(spec: Dictionary) -> bool:
	return bool(spec.get("drop", false))


func problems() -> Array[String]:
	return _problems


func band_ids() -> Array[String]:
	var out: Array[String] = []
	for band in bands:
		out.append(String(band["id"]))
	return out


func band_index(band: String) -> int:
	return band_ids().find(band)


func band_scale(band: String) -> float:
	for entry in bands:
		if String(entry["id"]) == band:
			return float(entry.get("scale", 1.0))
	return 1.0


func _front_band() -> String:
	return String(bands[-1]["id"]) if not bands.is_empty() else ""


## Everything drawable, back to front: [{"what": "plate"|"piece", "spec": Dictionary, "band": i, "z": z}].
func draw_order() -> Array:
	var out: Array = []
	var n := 0
	for plate in plates:
		out.append({"what": "plate", "spec": plate, "band": band_index(String(plate.get("band", ""))), "z": float(plate.get("z", PLATE_Z)), "n": n})
		n += 1
	for piece in pieces:
		out.append({"what": "piece", "spec": piece, "band": band_index(String(piece.get("band", ""))), "z": float(piece.get("z", 0)), "n": n})
		n += 1
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if a["band"] != b["band"]:
			return a["band"] < b["band"]
		if a["z"] != b["z"]:
			return a["z"] < b["z"]
		return a["n"] < b["n"])
	return out


func image(file: String) -> Image:
	return AssetLibrary.load_image(root.path_join(file))


func piece(piece_id: String) -> Dictionary:
	for p in pieces:
		if String(p["id"]) == piece_id:
			return p
	return {}


## Every far-band tree piece (`kind: far_tree`).
func far_trees() -> Array:
	return pieces.filter(func(p: Dictionary) -> bool: return String(p.get("kind", "")) == "far_tree")


## Where a piece is rooted, in scene px.
static func pivot_of(spec: Dictionary) -> Vector2:
	return Vector2(_vec2i(spec["at"]) + _vec2i(spec.get("pivot", [0, 0])))


static func bends(spec: Dictionary) -> bool:
	return not RIGID.has(String(spec.get("kind", ""))) and float(spec.get("sway", {}).get("weight", 0.0)) > 0.0


## Every perch of every piece, in scene px: [{"piece": id, "at": Vector2, "band": String}].
func perches() -> Array:
	var out: Array = []
	for p in pieces:
		var origin := Vector2(_vec2i(p["at"]))
		for at in p.get("perches", []):
			out.append({"piece": String(p["id"]), "at": origin + Vector2(_vec2i(at)), "band": String(p.get("band", ""))})
	return out


func is_pixel() -> bool:
	return style == "pixel"


## The waterline seen edge-on (kit px): below it the scene is the pond in cross-section, so nothing
## falls or stands there in the open air. `water.cut_y`, else the top of the underwater region,
## else the nearest water.
func cut_y() -> float:
	if water.has("cut_y"):
		return float(water["cut_y"])
	var under := underwater_rect()
	if under.size.y > 0.0:
		return under.position.y
	return float(water.get("bottom_y", water.get("surface_y", size.y)))


## The bounding box of an underwater region (rect or polygon), in kit px; empty if none.
func underwater_rect() -> Rect2:
	for region in water.get("regions", []):
		if String(region.get("kind", "")) != "underwater":
			continue
		if region.has("rect"):
			var r: Array = region["rect"]
			return Rect2(float(r[0]), float(r[1]), float(r[2]), float(r[3])).abs()
		if region.has("polygon"):
			var points := _points(region["polygon"])
			var box := Rect2(points[0], Vector2.ZERO)
			for p in points:
				box = box.expand(p)
			return box
	return Rect2()


func zones_of(kind: String) -> Array:
	return zones.filter(func(z: Dictionary) -> bool: return String(z.get("kind", "")) == kind)


## Whether `point` is inside zone `zone` (a polygon), or within `slack` px of it (a lane).
static func in_zone(zone: Dictionary, point: Vector2, slack: float = 4.0) -> bool:
	if zone.has("polygon"):
		return Geometry2D.is_point_in_polygon(point, _points(zone["polygon"]))
	if zone.has("lane"):
		var lane := _points(zone["lane"])
		for i in lane.size() - 1:
			if Geometry2D.get_closest_point_to_segment(point, lane[i], lane[i + 1]).distance_to(point) <= slack:
				return true
	return false


static func _points(raw: Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in raw:
		out.append(Vector2(float(p[0]), float(p[1])))
	return out


static func _vec2i(raw) -> Vector2i:
	if raw is Array and raw.size() >= 2:
		return Vector2i(int(raw[0]), int(raw[1]))
	return Vector2i.ZERO


func _check() -> void:
	if size.x <= 0 or size.y <= 0:
		_problems.append("size is missing")
	if art_scale <= 0.0:
		_problems.append("art_scale must be above 0")
	if bands.is_empty():
		_problems.append("no bands")
	var names := band_ids()
	for plate in plates:
		if not names.has(String(plate.get("band", ""))):
			_problems.append("plate %s: unknown band %s" % [plate.get("id"), plate.get("band")])
		if not AssetLibrary.image_exists(root.path_join(String(plate.get("file", "")))):
			_problems.append("plate %s: no file %s" % [plate.get("id"), plate.get("file")])
	var seen := {}
	for p in pieces:
		var pid := String(p.get("id", ""))
		if seen.has(pid):
			_problems.append("piece %s appears twice" % pid)
		seen[pid] = true
		for key in ["file", "kind", "at", "band", "pivot"]:
			if not p.has(key):
				_problems.append("piece %s: no %s" % [pid, key])
		if not KINDS.has(String(p.get("kind", ""))):
			_problems.append("piece %s: unknown kind %s" % [pid, p.get("kind")])
		if not names.has(String(p.get("band", ""))):
			_problems.append("piece %s: unknown band %s" % [pid, p.get("band")])
		if not AssetLibrary.image_exists(root.path_join(String(p.get("file", "")))):
			_problems.append("piece %s: no file %s" % [pid, p.get("file")])
		if String(p.get("kind", "")) == "far_tree" and not FAR_TREES.has(String(p.get("tree", ""))):
			_problems.append("piece %s: a far_tree needs tree conifer or broadleaf, not %s" % [pid, p.get("tree")])
	for p in pieces:
		var parent := SceneKit.parent_of(p)
		if parent != "" and (not seen.has(parent) or parent == String(p.get("id", ""))):
			_problems.append("piece %s: follows %s, which is not another piece" % [p.get("id"), parent])
	if not Rect2(Vector2.ZERO, Vector2(size)).encloses(frame_rect()) or frame.x <= 0 or frame.y <= 0:
		_problems.append("the frame %s at %s is not inside the kit" % [frame, origin])
	for zone in zones:
		if not ZONE_KINDS.has(String(zone.get("kind", ""))):
			_problems.append("zone %s: unknown kind %s" % [zone.get("id"), zone.get("kind")])
		if not zone.has("polygon") and not zone.has("lane"):
			_problems.append("zone %s: neither polygon nor lane" % zone.get("id"))
	if not water.has("surface_y"):
		_problems.append("water has no surface_y")
	if seat.is_empty() or not seat.has("at"):
		_problems.append("no seat")
