class_name Polaroid
extends RefCounted

## The polaroid of one bird (issue 77): the delivered polaroid's frame colours around the
## photographed species' own perched frame, at one art pixel per pixel. The delivered
## `items/polaroid` has a cardinal painted in, so it is read only for its colours.

## Where the delivered 16×16 frame keeps its outline, its white card and the photo's backdrop.
const OUTLINE_AT := Vector2i(2, 1)
const CARD_AT := Vector2i(4, 12)
const BACKDROP_AT := Vector2i(4, 2)


## `frame`: the delivered polaroid (null: plain card colours from `tuning`). `bird`: the
## species' CreatureDef; its smallest layer's first idle frame is the picture.
## `tuning`: balance `polaroid` (margin, border and bottom strip in art pixels, fallback colours).
static func compose(frame: Texture2D, bird: CreatureDef, tuning: Dictionary) -> ImageTexture:
	var outline := Color(String(tuning["outline"]))
	var card := Color(String(tuning["card"]))
	var backdrop := Color(String(tuning["backdrop"]))
	var frame_image := frame.get_image() if frame != null else null
	if frame_image != null and not frame_image.is_empty():
		frame_image.decompress()
		if _inside(frame_image, OUTLINE_AT) and _inside(frame_image, CARD_AT) and _inside(frame_image, BACKDROP_AT):
			outline = frame_image.get_pixelv(OUTLINE_AT)
			card = frame_image.get_pixelv(CARD_AT)
			backdrop = frame_image.get_pixelv(BACKDROP_AT)
	var picture := bird_picture(bird)
	var margin := int(tuning["margin_px"])
	var border := int(tuning["border_px"])
	var bottom := int(tuning["bottom_px"])
	var photo := picture.get_size() + Vector2i(margin, margin) * 2
	var size := photo + Vector2i(2 + border * 2, 2 + border + bottom)
	var image := Image.create_empty(size.x, size.y, false, Image.FORMAT_RGBA8)
	image.fill(outline)
	image.fill_rect(Rect2i(Vector2i.ONE, size - Vector2i(2, 2)), card)
	var photo_at := Vector2i(1 + border, 1 + border)
	image.fill_rect(Rect2i(photo_at, photo), backdrop)
	image.blend_rect(picture, Rect2i(Vector2i.ZERO, picture.get_size()), photo_at + Vector2i(margin, margin))
	return ImageTexture.create_from_image(image)


## The bird as it perches, cropped to its pixels: the first idle frame of its smallest layer.
static func bird_picture(bird: CreatureDef) -> Image:
	var layer := _smallest_layer(bird)
	var sheet: Dictionary = bird.layers[layer]
	var frame_size: Vector2i = sheet["frame_size"]
	var anim := bird.animation_or_fallback(layer, "idle")
	var index := int(sheet["animations"][anim]["frames"][0]) if anim != "" else 0
	var columns := int(sheet["columns"])
	var at := Vector2i(index % columns, index / columns) * frame_size
	var source: Image = (sheet["texture"] as Texture2D).get_image()
	if source == null or source.is_empty():
		var blank := Image.create_empty(frame_size.x, frame_size.y, false, Image.FORMAT_RGBA8)
		return blank
	source.decompress()
	source.convert(Image.FORMAT_RGBA8)
	var picture := source.get_region(Rect2i(at, frame_size))
	var used := picture.get_used_rect()
	return picture.get_region(used) if used.has_area() else picture


static func _smallest_layer(bird: CreatureDef) -> String:
	var best := ""
	for layer in bird.layers:
		var area: int = (bird.layers[layer]["frame_size"] as Vector2i).x * (bird.layers[layer]["frame_size"] as Vector2i).y
		if best == "" or area < (bird.layers[best]["frame_size"] as Vector2i).x * (bird.layers[best]["frame_size"] as Vector2i).y:
			best = layer
	return best


static func _inside(image: Image, at: Vector2i) -> bool:
	return at.x < image.get_width() and at.y < image.get_height()
