class_name CreatureDef
extends RefCounted

## A layered creature: one sheet per depth layer, each with its own frame size,
## anchor (the feet) and animations, all from meta.json. A creature belongs to no
## patch; whichever window hosts it draws it.

const LAYER_ORDER: Array[String] = ["back", "mid", "front"]

var id: String
## layer -> {"texture", "frame_size": Vector2i, "anchor": Vector2i, "columns": int,
##           "animations": {name -> {"frames": Array[int], "fps": float, "loop": bool}}}
var layers: Dictionary = {}
var is_placeholder := false
## Where a held rod's tip is drawn (an avatar's meta `rod_tips`): animation -> one
## [x, y] in frame pixels (or null) per frame of that animation, in the side view facing east.
var rod_tips: Dictionary = {}
## The same creature drawn smaller for standing further back (an avatar's `depths`):
## depth (`mid`, `back`) -> a CreatureDef with the same layers and animations. The
## sheets above are the `front` depth.
var depths: Dictionary = {}


static func load_creature(category: String, id: String, placeholder_px: Dictionary, idle_fps_max: float,
		placeholder_color: Color = Color("cf573c"), root: String = AssetLibrary.ROOT) -> CreatureDef:
	var def := CreatureDef.new()
	def.id = id
	var meta := AssetLibrary.load_meta(category, id, root)
	var layer_metas: Dictionary = meta.get("layers", {})
	if layer_metas.is_empty() and meta.has("frame_w"):
		layer_metas = {"front": meta}
	for layer in layer_metas:
		var texture := AssetLibrary.load_texture(category, id, "%s_%s" % [id, layer], root)
		if texture == null and layer_metas.size() == 1:
			texture = AssetLibrary.load_texture(category, id, id, root)
		if texture == null:
			continue
		var lm: Dictionary = layer_metas[layer]
		var frame_size := Vector2i(int(lm["frame_w"]), int(lm["frame_h"]))
		def.layers[layer] = {
			"texture": texture,
			"frame_size": frame_size,
			"anchor": AssetLibrary.vec2i(lm["anchor"]),
			"columns": maxi(1, texture.get_width() / frame_size.x),
			"animations": _animations(lm.get("animations", {}), idle_fps_max),
		}
	if def.layers.is_empty():
		def.is_placeholder = true
		for layer in placeholder_px:
			var px := int(placeholder_px[layer])
			def.layers[layer] = {
				"texture": AssetLibrary.solid_texture(Vector2i(px, px), placeholder_color),
				"frame_size": Vector2i(px, px),
				"anchor": Vector2i(px / 2, px - 1),
				"columns": 1,
				"animations": {
					"idle": {"frames": [0], "fps": 1.0, "loop": true},
					"fly": {"frames": [0], "fps": 1.0, "loop": true},
				},
			}
	return def


## A one-sheet asset (bobber, flower, splash): the contract's plain meta.json, or
## `fallback` (a ready layer dictionary, see `sheet_layer`) if it is missing.
static func load_single(category: String, id: String, idle_fps_max: float, fallback: Dictionary) -> CreatureDef:
	var def := CreatureDef.load_creature(category, id, {}, idle_fps_max)
	if not def.layers.is_empty():
		def.is_placeholder = false
		return def
	# A plain PNG with no frame grid in its meta.json is one frame, anchored at its
	# bottom centre.
	var texture := AssetLibrary.load_texture(category, id, id)
	if texture != null:
		var size := Vector2i(texture.get_width(), texture.get_height())
		def.is_placeholder = false
		def.layers["front"] = {
			"texture": texture,
			"frame_size": size,
			"anchor": Vector2i(size.x / 2, size.y - 1),
			"columns": 1,
			"animations": {"idle": {"frames": [0], "fps": 1.0, "loop": true}},
		}
		return def
	def.is_placeholder = true
	def.layers["front"] = fallback
	return def


## A layer dictionary for a placeholder sheet: `frames` frames side by side, each a
## bar of `color` a little taller than the last.
static func sheet_layer(frame_size: Vector2i, frames: int, color: Color, animations: Dictionary, anchor: Vector2i) -> Dictionary:
	var image := Image.create_empty(frame_size.x * frames, frame_size.y, false, Image.FORMAT_RGBA8)
	for i in frames:
		var height := maxi(2, frame_size.y * (i + 1) / frames)
		image.fill_rect(Rect2i(i * frame_size.x + frame_size.x / 4, frame_size.y - height, frame_size.x / 2, height), color)
	return {
		"texture": ImageTexture.create_from_image(image),
		"frame_size": frame_size,
		"anchor": anchor,
		"columns": frames,
		"animations": animations,
	}


static func _animations(raw: Dictionary, idle_fps_max: float) -> Dictionary:
	var out := {}
	for anim_name in raw:
		var a: Dictionary = raw[anim_name]
		var frames: Array[int] = []
		for f in a["frames"]:
			frames.append(int(f))
		var fps := float(a.get("fps", 1))
		if anim_name == "idle" and fps > idle_fps_max:
			push_warning("idle at %s fps exceeds the battery cap; clamped to %s" % [fps, idle_fps_max])
			fps = idle_fps_max
		out[anim_name] = {"frames": frames, "fps": fps, "loop": bool(a.get("loop", false))}
	return out


func has_layer(layer: String) -> bool:
	return layers.has(layer)


func has_animation(layer: String, anim: String) -> bool:
	return layers.has(layer) and layers[layer]["animations"].has(anim)


## `anim` if this layer has it, else `idle`, else whatever it has.
func animation_or_fallback(layer: String, anim: String) -> String:
	if has_animation(layer, anim):
		return anim
	if has_animation(layer, "idle"):
		return "idle"
	var names: Array = layers[layer]["animations"].keys()
	return String(names[0]) if not names.is_empty() else ""


## The animation used to move through the air in a layer: `fly`, else `hover`, else `idle`.
func flight_animation(layer: String) -> String:
	for anim in ["fly", "hover", "idle"]:
		if has_animation(layer, anim):
			return anim
	return ""


## Layers crossed going from `from_layer` to `to_layer`, both included, skipping any
## layer this creature has no sheet for.
func layer_path(from_layer: String, to_layer: String) -> Array[String]:
	var a := LAYER_ORDER.find(from_layer)
	var b := LAYER_ORDER.find(to_layer)
	var path: Array[String] = []
	if a < 0 or b < 0:
		return path
	var step := 1 if b >= a else -1
	var i := a
	while true:
		if has_layer(LAYER_ORDER[i]):
			path.append(LAYER_ORDER[i])
		if i == b:
			break
		i += step
	return path
