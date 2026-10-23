class_name SceneConfigKit
extends RefCounted

## The field-kit pieces Config is drawn with (Skypatch issue 174),
## the bench's `assets/ui/config_kit` (Skypatch issue 175):
## each piece a sheet of frames (one per state, left to right), nine-sliced where it stretches, @1x on a
## 1× screen and @2x on 2× and up, drawn at one sheet px per device px (never resampled). Also the
## kit's text colours, its font (Fraunces, always through a FontVariation: its default weight is 900)
## and its layout numbers.

const DIR := "res://assets/ui/config_kit"
## The book's italic caption font (Fraunces Italic, SIL OFL 1.1, its licence beside it) is the open shell's, not the
## companion's: a package holds no font (issue 459, 463).
const CAPTION_FONT := "res://assets/fonts/FrauncesItalic.ttf"

## "1x" or "2x".
var density := "1x"
## Sheet px per point.
var d := 1
var meta: Dictionary = {}
var dir := DIR
var _sheets := {}
var _fonts := {}


func _init(ui_scale: float, kit_dir: String = DIR) -> void:
	dir = kit_dir
	density = SceneConfigKit.density_for(ui_scale)
	d = 2 if density == "2x" else 1
	meta = JSON.parse_string(FileAccess.get_file_as_string(dir.path_join("meta.json")))



## The book's kit (Skypatch issue 185), same conventions: the companion's
## `journal/` (`AssetLibrary.companion_file`).
static func book_dir() -> String:
	return AssetLibrary.companion_file("journal")


## @1x on a 1× screen, @2x on 2× and up (as the strip).
static func density_for(ui_scale: float) -> String:
	return "2x" if ui_scale >= 2.0 else "1x"


func pieces() -> Dictionary:
	return meta["pieces"]


func states(piece: String) -> Array:
	return pieces()[piece]["states"]


## The piece's frame for `state` within its sheet (sheet px).
func frame_rect(piece: String, state: String) -> Rect2:
	var spec: Dictionary = pieces()[piece]
	var file: Dictionary = spec["files"][density]
	var index := int(spec["frame_index"].get(state, 0))
	return Rect2(index * float(file["frame_w"]), 0, float(file["frame_w"]), float(file["frame_h"]))


func sheet(piece: String) -> Texture2D:
	if not _sheets.has(piece):
		_sheets[piece] = AssetLibrary.cached_texture(dir.path_join(String(pieces()[piece]["files"][density]["file"])))
	return _sheets[piece]


## A nine-slice stylebox of `piece` in `state`; content margins (device px) are the caller's.
func style(piece: String, state: String = "normal") -> StyleBoxTexture:
	var box := StyleBoxTexture.new()
	box.texture = sheet(piece)
	box.region_rect = frame_rect(piece, state)
	var m := margin(piece)
	box.texture_margin_left = m.x
	box.texture_margin_top = m.y
	box.texture_margin_right = m.z
	box.texture_margin_bottom = m.w
	box.axis_stretch_horizontal = StyleBoxTexture.AXIS_STRETCH_MODE_TILE
	box.axis_stretch_vertical = StyleBoxTexture.AXIS_STRETCH_MODE_TILE
	return box


## One frame of a fixed-size piece (toggle, check, marker).
func texture(piece: String, state: String = "normal") -> Texture2D:
	var atlas := AtlasTexture.new()
	atlas.atlas = sheet(piece)
	atlas.region = frame_rect(piece, state)
	return atlas


## Nine-slice margins in sheet px (left, top, right, bottom).
func margin(piece: String) -> Vector4:
	var m: Dictionary = pieces()[piece]["files"][density].get("nine_slice_px", {})
	return Vector4(float(m.get("left", 0)), float(m.get("top", 0)), float(m.get("right", 0)), float(m.get("bottom", 0)))


## A piece's native size in points.
func size_pt(piece: String) -> Vector2:
	var s: Array = pieces()[piece]["size_pt"]
	return Vector2(float(s[0]), float(s[1]))


func colour(key: String) -> Color:
	return Color(String(meta["text_colours"][key]))


func layout(key: String) -> float:
	return float(meta["layout"][key])


## Fraunces in one of the kit's styles (body, small, label, heading), its axes set.
func font(style_name: String) -> FontVariation:
	if not _fonts.has(style_name):
		var variation := FontVariation.new()
		variation.base_font = load(dir.path_join(String(meta["font"]["file"])))
		var axes: Dictionary = meta["font"]["styles"][style_name]["axes"]
		var opentype := {}
		var ts := TextServerManager.get_primary_interface()
		for axis in axes:
			opentype[ts.name_to_tag(String(axis))] = float(axes[axis])
		variation.variation_opentype = opentype
		_fonts[style_name] = variation
	return _fonts[style_name]


func font_size_pt(style_name: String) -> float:
	return float(meta["font"]["styles"][style_name]["size_pt"])


## The book kit's italic caption font in one of its styles (caption, note), its axes set.
func caption_font(style_name: String) -> FontVariation:
	var key := "caption:" + style_name
	if not _fonts.has(key):
		var spec: Dictionary = meta["font"]["caption"]
		var variation := FontVariation.new()
		variation.base_font = load(CAPTION_FONT)
		var opentype := {}
		var ts := TextServerManager.get_primary_interface()
		var axes: Dictionary = spec["styles"][style_name]["axes"]
		for axis in axes:
			opentype[ts.name_to_tag(String(axis))] = float(axes[axis])
		variation.variation_opentype = opentype
		_fonts[key] = variation
	return _fonts[key]


func caption_size_pt(style_name: String) -> float:
	return float(meta["font"]["caption"]["styles"][style_name]["size_pt"])
