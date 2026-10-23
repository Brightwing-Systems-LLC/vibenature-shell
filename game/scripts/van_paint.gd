class_name VanPaint
extends RefCounted

## The van's paint (issue 279): a body colour and an accent
## colour, chosen in Config's Avatar tab ("Your van") and the welcome's first step, saved as `settings.van`
## `{body, accent}`. The bench drew the paint only in its source ramps (`paint` in the van's meta.json, issue 278), so
## the swap is colour for colour like `AvatarLook`'s: every pixel of `source[material][i]` becomes the chosen ramp's
## step `i`, in one pass over the whole sheet (every frame, the lit ones too), never resampled. The swap always runs,
## even for the default choice: the sheet's seals and shading are drawn in source colours no choice keeps.

const MATERIALS: Array[String] = ["body", "accent"]

static var _metas := {}
static var _sheets := {}
static var _sheet_order: Array[String] = []


## The van's meta.json at `file`, parsed once ({} without it).
static func meta(file: String) -> Dictionary:
	if _metas.has(file):
		return _metas[file]
	var out := {}
	if file != "" and FileAccess.file_exists(file):
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(file))
		if parsed is Dictionary:
			out = parsed
	_metas[file] = out
	return out


## The choice ids for `material` ("body" or "accent"), in the bench's order.
static func options(van_meta: Dictionary, material: String) -> Array:
	var out: Array = []
	for entry in van_meta.get("paint", {}).get(material, []):
		out.append(String(entry["id"]))
	return out


static func ramp(van_meta: Dictionary, material: String, id: String) -> Array[Color]:
	var out: Array[Color] = []
	for entry in van_meta.get("paint", {}).get(material, []):
		if String(entry["id"]) == id:
			for hex in entry["ramp"]:
				out.append(Color(String(hex)))
	return out


static func word(van_meta: Dictionary, material: String, id: String) -> String:
	for entry in van_meta.get("paint", {}).get(material, []):
		if String(entry["id"]) == id:
			return String(entry.get("name", id))
	return id


## A whole, valid choice: anything unknown or missing takes the bench's default.
static func sanitize(choice: Variant, van_meta: Dictionary) -> Dictionary:
	var paint: Dictionary = van_meta.get("paint", {})
	var defaults: Dictionary = paint.get("default", {})
	var out := {}
	for material in MATERIALS:
		var want := String(choice.get(material, "")) if choice is Dictionary else ""
		out[material] = want if options(van_meta, material).has(want) else String(defaults.get(material, ""))
	return out


static func key(choice: Dictionary) -> String:
	return "%s|%s" % [choice.get("body", ""), choice.get("accent", "")]


## Source colour -> chosen colour, as little-endian opaque RGBA8 ints (the sheet's own bytes).
static func swap_table(van_meta: Dictionary, choice: Dictionary) -> Dictionary:
	var table := {}
	var source: Dictionary = van_meta.get("paint", {}).get("source", {})
	for material in MATERIALS:
		var from: Array = source.get(material, [])
		var to := ramp(van_meta, material, String(choice.get(material, "")))
		for i in mini(from.size(), to.size()):
			table[AvatarLook._le(AvatarLook._rgb(Color(String(from[i]))))] = AvatarLook._le(AvatarLook._rgb(to[i]))
	return table


## The whole van sheet in `choice`'s paint. Cached for the last few choices (the picker flips between them).
static func sheet(art: String, van_meta: Dictionary, choice: Dictionary) -> Image:
	var k := art + "#" + key(choice)
	if _sheets.has(k):
		return _sheets[k]
	if art == "" or not AssetLibrary.image_exists(art):
		return null
	var image := AssetLibrary.load_image(art)
	if image.is_compressed():
		image.decompress()
	image.convert(Image.FORMAT_RGBA8)
	var out := AvatarLook._swap_pixels(image, swap_table(van_meta, choice))
	_sheets[k] = out
	_sheet_order.append(k)
	while _sheet_order.size() > 4:
		_sheets.erase(_sheet_order.pop_front())
	return out


## One frame of the painted van (the picker's preview), `flip` to face left as it parks.
static func frame_image(art: String, van_meta: Dictionary, choice: Dictionary, frame: int, flip: bool = false) -> Image:
	var whole := sheet(art, van_meta, choice)
	if whole == null:
		return null
	var fw := int(van_meta["frame_w"])
	var out := whole.get_region(Rect2i(frame * fw, 0, fw, int(van_meta["frame_h"])))
	if flip:
		out.flip_x()
	return out
