class_name PatchDef
extends RefCounted

## A patch island as delivered: base + front overlay, its size taken from the base
## image, and its named spots in island pixel coordinates.

const LAYERS: Array[String] = ["back", "mid", "front"]

var id: String
var base: Texture2D
var front: Texture2D
var size: Vector2i
## name -> {"layer": String, "at": Vector2i, "kind": String}
var spots: Dictionary = {}
var is_placeholder := false


static func load_patch(id: String, placeholder_size: Vector2i) -> PatchDef:
	var def := PatchDef.new()
	def.id = id
	def.base = AssetLibrary.load_texture("patches", id, id + "_base")
	def.front = AssetLibrary.load_texture("patches", id, id + "_front")
	var meta := AssetLibrary.load_meta("patches", id)
	if def.base == null:
		def.is_placeholder = true
		def.base = AssetLibrary.blob_texture(placeholder_size, Color("5d8a52"))
	def.size = Vector2i(def.base.get_width(), def.base.get_height())
	for spot_name in meta.get("spots", {}):
		var spot: Dictionary = meta["spots"][spot_name]
		def.spots[spot_name] = {
			"layer": String(spot["layer"]),
			"at": AssetLibrary.vec2i(spot["at"]),
			"kind": String(spot["kind"]),
		}
	if def.spots.is_empty():
		def.spots = _placeholder_spots(def.size)
	return def


## An island pack's island: one image (its art, or the shelf placeholder) and its spots.
static func from_image(id: String, image: Image, island_spots: Dictionary, placeholder: bool) -> PatchDef:
	var def := PatchDef.new()
	def.id = id
	def.base = ImageTexture.create_from_image(image)
	def.size = image.get_size()
	def.spots = island_spots
	def.is_placeholder = placeholder
	return def


static func _placeholder_spots(island: Vector2i) -> Dictionary:
	var spots := {}
	for i in LAYERS.size():
		var layer := LAYERS[i]
		spots["placeholder_perch_" + layer] = {
			"layer": layer,
			"at": Vector2i(island.x * (i + 1) / 4, island.y * (i + 1) / 5),
			"kind": "perch",
		}
	return spots


func spots_of_kind(kind: String) -> Array[String]:
	var names: Array[String] = []
	for spot_name in spots:
		if spots[spot_name]["kind"] == kind:
			names.append(spot_name)
	names.sort()
	return names


## The opaque pixels of base and front together, for click-through.
func opaque_image() -> Image:
	var image := base.get_image()
	if image.is_compressed():
		image.decompress()
	image.convert(Image.FORMAT_RGBA8)
	if front != null:
		var overlay := front.get_image()
		if overlay.is_compressed():
			overlay.decompress()
		overlay.convert(Image.FORMAT_RGBA8)
		image.blend_rect(overlay, Rect2i(Vector2i.ZERO, overlay.get_size()), Vector2i.ZERO)
	return image
