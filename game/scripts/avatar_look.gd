class_name AvatarLook
extends RefCounted

## The player's avatar (Skypatch issue 202): one of the bench's ten
## whole-sprite looks (Skypatch issue 216, the companion's `avatar/looks/`)
## with a skin, a hair colour and a top colour swapped in. Saved in settings as `avatar`:
##
##   {"look": "look01", "skin": "s3_warm", "hair": "dark_brown", "top": "burgundy"}
##
## Every look takes every skin and every top; hair only from its own `hair_allowed`. Looks belong to
## Body 1 or Body 2 (`body_type`), never named by gender.
##
## The swap is colour for colour (the format's compositing rule): each palette entry with a `step` takes
## `ramp[step]` of the chosen colour; every other pixel keeps its colour and no pixel moves (never resampled).
## It is baked on the CPU into a new image, once per look and choice (`sheet`, cached).

const SWAPS: Array[String] = ["skin", "hair", "top"]

static var _catalog: Dictionary = {}
## look id -> {"bytes": PackedByteArray, "size": Vector2i, "groups": {rgb int: PackedInt32Array byte offsets}}
static var _index := {}
static var _sheets := {}
static var _sheet_order: Array[String] = []
static var _days := {}
static var _day_order: Array[String] = []
static var _letter_sheets := {}
static var _letter_order: Array[String] = []
static var _extras := {}
static var _extra_order: Array[String] = []

## The seated activity sheets beside the log sheet (issue 123), each a block in the look's meta.json with the log
## sheet's frame, anchor and scale: the thermos and paperback (issue 122), the looking-down heads (`log_file`, issue
## 313) and the fidgets (issue 321) once the bench delivers them. A look without a block skips its activities.
const EXTRA_BLOCKS: Array[String] = ["thermos", "paperback", "heads", "fidget"]


## The looks' folder: the companion's `avatar/looks` (`AssetLibrary.companion_file`).
static func dir() -> String:
	return AssetLibrary.companion_file("avatar/looks")


## The looks and the palettes: {"palettes": {material: {id: [Color]}}, "order": {material: [id]},
## "names": {material: {id: name}}, "looks": {id: meta}, "ids": [id], "bodies": {1: [id], 2: [id]}}.
static func catalog() -> Dictionary:
	if not _catalog.is_empty():
		return _catalog
	var out := {"palettes": {}, "order": {}, "names": {}, "looks": {}, "ids": [], "bodies": {1: [], 2: []}}
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(dir().path_join("palettes.json")))
	if not (parsed is Dictionary):
		push_warning("VibeNature: no avatar palettes in %s" % dir())
		return out
	for material in SWAPS:
		out["palettes"][material] = {}
		out["order"][material] = []
		out["names"][material] = {}
		for choice in parsed.get(material, []):
			var ramp: Array[Color] = []
			for hex in choice["ramp"]:
				ramp.append(Color(String(hex)))
			out["palettes"][material][String(choice["id"])] = ramp
			out["order"][material].append(String(choice["id"]))
			out["names"][material][String(choice["id"])] = String(choice.get("name", choice["id"]))
	for n in range(1, 100):
		var id := "look%02d" % n
		var path := dir().path_join(id).path_join("meta.json")
		if not FileAccess.file_exists(path):
			break
		var meta = JSON.parse_string(FileAccess.get_file_as_string(path))
		if not (meta is Dictionary):
			continue
		out["looks"][id] = meta
		out["ids"].append(id)
		var body := int(meta.get("body_type", 1))
		if not out["bodies"].has(body):
			out["bodies"][body] = []
		out["bodies"][body].append(id)
	_catalog = out
	return out


static func ids() -> Array:
	return catalog()["ids"]


static func meta(look_id: String) -> Dictionary:
	return catalog()["looks"].get(look_id, {})


static func body(look_id: String) -> int:
	return int(meta(look_id).get("body_type", 1))


## The looks of one body, in order.
static func looks_for_body(body_type: int) -> Array:
	return catalog()["bodies"].get(body_type, [])


## The ids a colour field offers for `look_id`: every skin, every top, the look's own hair colours.
static func options(material: String, look_id: String) -> Array:
	var all: Array = catalog()["order"].get(material, [])
	if material != "hair":
		return all
	var allowed: Array = meta(look_id).get("hair_allowed", [meta(look_id).get("defaults", {}).get("hair", "")])
	return all.filter(func(id) -> bool: return allowed.has(id))


## A ramp, darkest first.
static func ramp(material: String, id: String) -> Array[Color]:
	var out: Array[Color] = []
	out.assign(catalog()["palettes"].get(material, {}).get(id, []))
	return out


static func word(material: String, id: String) -> String:
	return String(catalog()["names"].get(material, {}).get(id, id.capitalize()))


## The look `look_id` as the bench drew it.
static func look_defaults(look_id: String) -> Dictionary:
	var d: Dictionary = meta(look_id).get("defaults", {})
	return {"look": look_id, "skin": String(d.get("skin", "")), "hair": String(d.get("hair", "")), "top": String(d.get("top", ""))}


static func defaults(cfg: Dictionary) -> Dictionary:
	return sanitize({"look": String(cfg.get("default", "look01"))}, cfg)


## `look` whole and valid: an unknown look is the default look; a skin, hair or top it cannot take is
## that look's own (hair outside `hair_allowed` included).
static func sanitize(look: Variant, cfg: Dictionary) -> Dictionary:
	var given: Dictionary = look if look is Dictionary else {}
	var look_id := String(given.get("look", ""))
	if not catalog()["looks"].has(look_id):
		look_id = String(cfg.get("default", "look01"))
		if not catalog()["looks"].has(look_id) and not ids().is_empty():
			look_id = String(ids()[0])
	var out := look_defaults(look_id)
	for material in SWAPS:
		var want := String(given.get(material, ""))
		if options(material, look_id).has(want):
			out[material] = want
	return out


## `look` moved to `look_id`, keeping its skin and top, and its hair when the new look takes it.
static func with_look(look: Dictionary, look_id: String, cfg: Dictionary) -> Dictionary:
	var next := look.duplicate()
	next["look"] = look_id
	return sanitize(next, cfg)


## The nearest look and skin for one of the six old whole avatars (`<build>_<preset>`, e.g. `c_sturdy_p2`).
static func from_avatar_id(avatar_id: String, cfg: Dictionary) -> Dictionary:
	var old: Dictionary = cfg.get("from_old", {})
	if old.has(avatar_id):
		return sanitize(old[avatar_id], cfg)
	return defaults(cfg)


## The old whole avatar the island game still wears for `look` (it has no walking art for the looks).
static func island_avatar_id(look: Dictionary, cfg: Dictionary) -> String:
	return String(cfg.get("island_avatar", {}).get(str(body(String(look["look"]))), "a_medium_p1"))


## A stable text key for caches and comparisons.
static func key(look: Dictionary) -> String:
	return "%s|%s|%s|%s" % [look.get("look", ""), look.get("skin", ""), look.get("hair", ""), look.get("top", "")]


## Source colour (rgb int) -> new colour for `look`: only palette entries with a `step` change.
static func swap_table(look: Dictionary) -> Dictionary:
	var out := {}
	var palettes: Dictionary = catalog()["palettes"]
	for entry in meta(String(look["look"])).get("palette", []):
		if not entry.has("step"):
			continue
		var material := String(entry["material"])
		var ramp_now: Array = palettes.get(material, {}).get(String(look.get(material, "")), [])
		var step := int(entry["step"])
		if step < 0 or step >= ramp_now.size():
			continue
		out[_rgb(Color(String(entry["hex"])))] = ramp_now[step]
	return out


## The look's whole seated sheet, swapped: {"image": Image, "meta": the `log` block, "key"}. Cached.
static func sheet(look: Dictionary) -> Dictionary:
	var k := key(look)
	if _sheets.has(k):
		return _sheets[k]
	var look_id := String(look["look"])
	var log_meta: Dictionary = meta(look_id).get("log", {})
	var src := _source(look_id)
	if src.is_empty() or log_meta.is_empty():
		return {}
	var out := {"image": _recolour(src, swap_table(look)), "meta": log_meta, "key": k}
	_sheets[k] = out
	_sheet_order.append(k)
	while _sheet_order.size() > 6:
		_sheets.erase(_sheet_order.pop_front())
	return out


## The look's standing day actions (issue 197), swapped the
## same way: {"meta": the `day` block, "full": Image, "far": Image, "key"}, or {} for a look without day art yet
## (issue 254). Cached for the last two choices.
static func day_sheets(look: Dictionary) -> Dictionary:
	var k := key(look)
	if _days.has(k):
		return _days[k]
	var look_id := String(look.get("look", ""))
	var day: Dictionary = meta(look_id).get("day", {})
	var far: Dictionary = day.get("depths", {}).get("far", {})
	if day.is_empty() or far.is_empty():
		return {}
	var table := {}
	var swaps := swap_table(look)
	for rgb in swaps:
		var c: Color = swaps[rgb]
		# Little-endian RGBA8 as one int: R | G << 8 | B << 16 | A << 24, opaque only (hard alpha).
		table[_le(rgb)] = _le(_rgb(c))
	var out := {"meta": day, "key": k}
	for pair in [["full", String(day["file"])], ["far", String(far["file"])]]:
		var image := _swap_whole(dir().path_join(look_id).path_join(String(pair[1])), table)
		if image == null:
			return {}
		out[pair[0]] = image
	_days[k] = out
	_day_order.append(k)
	while _day_order.size() > 2:
		_days.erase(_day_order.pop_front())
	return out


## The look reading the elder's letter on the log (issue 269,
## played by issue 270), swapped the same way: {"meta": the `letter` block, "image": Image, "key"}, or {} for a look
## without that art (it then never reads on the log). The sheet shares the log sheet's frame, anchor and scale.
## Cached for the last two choices.
static func letter_sheet(look: Dictionary) -> Dictionary:
	var k := key(look)
	if _letter_sheets.has(k):
		return _letter_sheets[k]
	var look_id := String(look.get("look", ""))
	var letter: Dictionary = meta(look_id).get("letter", {})
	if letter.is_empty() or not letter.get("animations", {}).has("log_letter_read"):
		return {}
	var table := {}
	var swaps := swap_table(look)
	for rgb in swaps:
		table[_le(rgb)] = _le(_rgb(swaps[rgb]))
	var image := _swap_whole(dir().path_join(look_id).path_join(String(letter["file"])), table)
	if image == null:
		return {}
	var out := {"meta": letter, "image": image, "key": k}
	_letter_sheets[k] = out
	_letter_order.append(k)
	while _letter_order.size() > 2:
		_letter_sheets.erase(_letter_order.pop_front())
	return out


## One seated activity sheet of the look (`EXTRA_BLOCKS`), swapped like the log sheet: {"meta": the block,
## "image": Image, "key"}, or {} for a look without that art. The heads block's whole-frame sheet is its `log_file`.
## The thermos block's ground prop comes as "prop" (Image) with "prop_meta". Cached for the last eight.
static func extra_sheet(look: Dictionary, block: String) -> Dictionary:
	var k := key(look) + "|" + block
	if _extras.has(k):
		return _extras[k]
	var look_id := String(look.get("look", ""))
	var m: Dictionary = meta(look_id).get(block, {})
	var file := String(m.get("log_file" if block == "heads" else "file", ""))
	if m.is_empty() or file == "" or m.get("animations", {}).is_empty():
		return {}
	var table := {}
	var swaps := swap_table(look)
	for rgb in swaps:
		table[_le(rgb)] = _le(_rgb(swaps[rgb]))
	var image := _swap_whole(dir().path_join(look_id).path_join(file), table)
	if image == null:
		return {}
	var out := {"meta": m, "image": image, "key": k}
	var prop: Dictionary = m.get("prop", {})
	if not prop.is_empty():
		var prop_image := _swap_whole(dir().path_join(look_id).path_join(String(prop.get("file", ""))), table)
		if prop_image != null:
			out["prop"] = prop_image
			out["prop_meta"] = prop
	_extras[k] = out
	_extra_order.append(k)
	while _extra_order.size() > 8:
		_extras.erase(_extra_order.pop_front())
	return out


## Every seated activity sheet the look has: {block: extra_sheet}.
static func extra_sheets(look: Dictionary) -> Dictionary:
	var out := {}
	for block in EXTRA_BLOCKS:
		var sheet := extra_sheet(look, block)
		if not sheet.is_empty():
			out[block] = sheet
	return out


static func _le(rgb: int) -> int:
	var v := ((rgb >> 16) & 0xff) | (((rgb >> 8) & 0xff) << 8) | ((rgb & 0xff) << 16) | (0xff << 24)
	return v - 0x100000000 if v >= 0x80000000 else v


static func _swap_whole(file: String, table: Dictionary) -> Image:
	if not AssetLibrary.image_exists(file):
		push_warning("VibeNature: no look sheet %s" % file)
		return null
	var image := AssetLibrary.load_image(file)
	if image.is_compressed():
		image.decompress()
	image.convert(Image.FORMAT_RGBA8)
	return _swap_pixels(image, table)


## The elder's portrait (issue 241) in `skin`, the player's
## skin tone (the human, issue 199): the bench drew its skin in the looks' default ramp and marked each colour's
## `step` in the meta.json beside it, so the same colour-for-colour swap as the looks applies. Null without the file.
static func portrait_image(file: String, skin: String) -> Image:
	if file == "" or not AssetLibrary.image_exists(file):
		return null
	var image := AssetLibrary.load_image(file)
	if image.is_compressed():
		image.decompress()
	image.convert(Image.FORMAT_RGBA8)
	var meta_file := file.get_base_dir().path_join("meta.json")
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(meta_file)) if FileAccess.file_exists(meta_file) else null
	var ramp_now := ramp("skin", skin)
	if not (parsed is Dictionary) or ramp_now.is_empty():
		return image
	var table := {}
	for entry in parsed.get("palette", []):
		if String(entry.get("material", "")) != "skin" or not entry.has("step"):
			continue
		var step := int(entry["step"])
		if step >= 0 and step < ramp_now.size():
			table[_le(_rgb(Color(String(entry["hex"]))))] = _le(_rgb(ramp_now[step]))
	return _swap_pixels(image, table)


static func _swap_pixels(image: Image, table: Dictionary) -> Image:
	if table.is_empty():
		return image
	var pixels := image.get_data().to_int32_array()
	for i in pixels.size():
		var v := pixels[i]
		if table.has(v):
			pixels[i] = table[v]
	return Image.create_from_data(image.get_width(), image.get_height(), false, Image.FORMAT_RGBA8, pixels.to_byte_array())


## One frame of the look, swapped (the picker's pictures): only that frame is recoloured.
static func frame_image(look: Dictionary, frame: int = 0) -> Image:
	var src := _source(String(look["look"]), frame)
	if src.is_empty():
		return null
	return _recolour(src, swap_table(look))


## Every colour `look`'s sheet may hold after the swap: the fixed palette entries and the chosen ramps.
static func allowed_colours(look: Dictionary) -> Dictionary:
	var out := {}
	var table := swap_table(look)
	for entry in meta(String(look["look"])).get("palette", []):
		var src := _rgb(Color(String(entry["hex"])))
		if entry.has("step"):
			if table.has(src):
				out[_rgb(table[src])] = true
		else:
			out[src] = true
	return out


static func _rgb(c: Color) -> int:
	return (c.r8 << 16) | (c.g8 << 8) | c.b8


## The look's PNG as bytes, with every opaque pixel's byte offset grouped by its colour (one pass, once).
## With `frame` >= 0, only that frame of the sheet.
static func _source(look_id: String, frame: int = -1) -> Dictionary:
	var cache_key := "%s#%d" % [look_id, frame]
	if _index.has(cache_key):
		return _index[cache_key]
	var log_meta: Dictionary = meta(look_id).get("log", {})
	var file := dir().path_join(look_id).path_join(String(log_meta.get("file", look_id + "_log.png")))
	if not AssetLibrary.image_exists(file):
		push_warning("VibeNature: no look sheet %s" % file)
		return {}
	var image := AssetLibrary.load_image(file)
	if image.is_compressed():
		image.decompress()
	image.convert(Image.FORMAT_RGBA8)
	if frame >= 0:
		var w := int(log_meta["frame_w"])
		image = image.get_region(Rect2i(frame * w, 0, w, int(log_meta["frame_h"])))
	var bytes := image.get_data()
	var swappable := {}
	for entry in meta(look_id).get("palette", []):
		if entry.has("step"):
			swappable[_rgb(Color(String(entry["hex"])))] = true
	var groups := {}
	var n := bytes.size()
	var i := 0
	while i < n:
		if bytes[i + 3] != 0:
			var rgb := (bytes[i] << 16) | (bytes[i + 1] << 8) | bytes[i + 2]
			if swappable.has(rgb):
				if not groups.has(rgb):
					groups[rgb] = []
				(groups[rgb] as Array).append(i)
		i += 4
	# Packed arrays are values, so offsets are gathered in Arrays (references) and packed once.
	for rgb in groups:
		groups[rgb] = PackedInt32Array(groups[rgb])
	var out := {"bytes": bytes, "size": image.get_size(), "groups": groups}
	_index[cache_key] = out
	return out


static func _recolour(src: Dictionary, table: Dictionary) -> Image:
	var bytes: PackedByteArray = (src["bytes"] as PackedByteArray).duplicate()
	var groups: Dictionary = src["groups"]
	for rgb in groups:
		if not table.has(rgb):
			continue
		var c: Color = table[rgb]
		var r := c.r8
		var g := c.g8
		var b := c.b8
		for at in groups[rgb]:
			bytes[at] = r
			bytes[at + 1] = g
			bytes[at + 2] = b
	var size: Vector2i = src["size"]
	return Image.create_from_data(size.x, size.y, false, Image.FORMAT_RGBA8, bytes)
