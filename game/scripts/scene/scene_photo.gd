class_name ScenePhoto
extends RefCounted

## Taking a photo of the scene (Skypatch issue 176): the
## scene's own render (never the screen, so nothing from the desktop or another app can be in it),
## grabbed with the control strip and the viewfinder hidden, cropped to exactly the framed rect at
## the scene's resolution (window units: two px per point on a Retina screen at full size).
##
## The VibeNature stamp is **baked in at capture** when `photo_mark` is on: the stored PNG is the
## photo as it was taken, so the book, an enlarged view and an export all show the same picture,
## and turning the setting off later never changes a photo already taken. It is a small corner
## mark: the largest of the bench's native renders (stamp @4x, @2x, @1x) no wider than
## `stamp_max_share` of the photo, never resampled; a photo too small for the @1x stamp gets the
## badge alone (no wordmark, 32 or 16 px), and one too small for that gets no mark (`mark_file`).
##
## The metadata is only the date and time, a weather word and the species with a good share of
## their drawn body inside the frame at the click (`species_in`), by construction (`PhotoAlbum.add`
## keeps nothing else).

const MARK_DIR := "res://assets/ui/vibenature_mark"
## Largest first: the stamp's native renders, then the badge alone (green ring, for the photo's
## mostly dark corners).
const MARK_FILES: Array[String] = ["stamp@4x.png", "stamp@2x.png", "stamp.png", "badge_32_dark.png", "badge_16_dark.png"]


## The scene's render without the strip or the viewfinder, at `scene.photo_scale()` units per point:
## the window's own, or at the in-between sizes (issue 222) the full-size render before it is shrunk,
## so a photo is as sharp at 70% as at 100% (null without a renderer). `render` stands in for reading the window's texture (tests: headless has none).
static func grab(scene: LivingScene, render: Callable = Callable()) -> Image:
	if not render.is_valid() and DisplayServer.get_name() == "headless":
		return null
	var hidden: Array[CanvasItem] = []
	for item: CanvasItem in [scene.controls, scene.viewfinder, scene.demo_card]:
		if item != null and item.visible:
			item.visible = false
			hidden.append(item)
	var image: Image
	if render.is_valid():
		image = render.call(scene)
	else:
		WindowChrome.redraw(scene)
		RenderingServer.force_draw(false)
		image = scene.photo_texture().get_image()
	for item in hidden:
		item.visible = true
	scene.resume_drawing()
	if image == null or image.is_empty():
		return null
	image.convert(Image.FORMAT_RGBA8)
	return image


## `rect_pt` (points) out of `full` (window units at `px_per_pt`), clipped to the image.
static func crop(full: Image, rect_pt: Rect2, px_per_pt: float) -> Image:
	var r := Rect2i((rect_pt.position * px_per_pt).round(), (rect_pt.size * px_per_pt).round())
	r = r.intersection(Rect2i(Vector2i.ZERO, full.get_size()))
	if r.size.x <= 0 or r.size.y <= 0:
		return null
	return full.get_region(r)

## The mark for a photo `photo_w` px wide: the largest native render no wider than `max_share` of
## the photo, from the stamp (@4x, @2x, @1x) down to the badge alone (32, 16 px, no wordmark) for a
## photo too small for even the @1x stamp; "" (no mark) when not even the small badge fits.
static func mark_file(photo_w: int, max_share: float) -> String:
	var meta := ScenePhoto._mark_meta()
	var room := float(photo_w) * max_share
	for file in MARK_FILES:
		var size: Array = meta.get("sizes", {}).get(file, [])
		if not size.is_empty() and float(size[0]) <= room:
			return file
	return ""


static func mark_image(file: String) -> Image:
	if file == "":
		return null
	var texture := load(MARK_DIR.path_join(file)) as Texture2D
	if texture == null:
		return null
	var image := texture.get_image()
	image.convert(Image.FORMAT_RGBA8)
	return image


static func _mark_meta() -> Dictionary:
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(MARK_DIR.path_join("meta.json")))
	return parsed if parsed is Dictionary else {}


## Puts the mark in the photo's bottom-right corner, `margin_pt` in, pixel for pixel. Returns its
## rect in the photo (empty when the photo is too small for any mark).
static func stamp(photo: Image, px_per_pt: float, margin_pt: float, max_share: float) -> Rect2i:
	var mark := ScenePhoto.mark_image(ScenePhoto.mark_file(photo.get_width(), max_share))
	if mark == null:
		return Rect2i()
	var margin := int(roundf(margin_pt * px_per_pt))
	var at := photo.get_size() - mark.get_size() - Vector2i(margin, margin)
	if at.x < 0 or at.y < 0:
		return Rect2i()
	photo.blend_rect(mark, Rect2i(Vector2i.ZERO, mark.get_size()), at)
	return Rect2i(at, mark.get_size())


## The species with at least `share` of their drawn body inside `rect_pt` (points) now: visitors,
## songbird parties (by cast member, as the field guide names them), fish in the cut-away and
## odonata. The body is the sheet's drawn frame rect; an animal without a sheet counts by its point.
static func species_in(beh: SceneBehaviour, rect_pt: Rect2, share: float) -> Array:
	var out: Array = []
	var world := beh.scene.world if beh.scene != null else null
	# The frame is drawn on the window; bodies are measured in the world (mirrored, or a margin cut; issues 422, 424).
	if beh.scene != null:
		rect_pt = beh.scene.unshown_rect(rect_pt)
	for c in beh.creatures:
		var creature: SceneCreature = c
		if creature.state != "gone" and creature.alpha > 0.3 and ScenePhoto._framed(world, creature.look.sheet, creature.pos, rect_pt, share):
			_add(out, creature.sp.id)
	for f in beh.flocks:
		var flock: SceneFlock = f
		var id := String(flock.member.get("id", "")) if not flock.member.is_empty() else flock.sp.id
		for b in flock.birds:
			var look: SceneCreatureLook = b["look"]
			if is_instance_valid(look) and float(b.get("alpha", 1.0)) > 0.3 and ScenePhoto._framed(world, look.sheet, look.position, rect_pt, share):
				_add(out, id if id != "" else flock.sp.id)
				break
	if beh.odonata != null:
		for f in beh.odonata.flies:
			if ScenePhoto._framed(world, f.get("sheet"), f["pos"], rect_pt, share):
				_add(out, String(f["id"]))
	return out


## The drawn body's rect in points (world space), or an empty rect without a drawn sheet.
static func body_rect(world: Node2D, sheet: Sprite2D) -> Rect2:
	if world == null or sheet == null or not is_instance_valid(sheet) or sheet.texture == null or not sheet.is_visible_in_tree():
		return Rect2()
	var to_world := world.get_global_transform().affine_inverse() * sheet.get_global_transform()
	return to_world * sheet.get_rect()


static func _framed(world: Node2D, sheet, at: Vector2, rect_pt: Rect2, share: float) -> bool:
	var body := ScenePhoto.body_rect(world, sheet as Sprite2D)
	if not body.has_area():
		return rect_pt.has_point(at)
	var inside := body.intersection(rect_pt)
	return inside.has_area() and inside.get_area() >= share * body.get_area()


static func _add(out: Array, id: String) -> void:
	if not out.has(id):
		out.append(id)


## The photo from the scene's render `full` (`grab`): cropped to the frame, marked. Null if nothing
## could be rendered. `photo_tuning` is `scene.photo` (stamp margin and share).
static func take(scene: LivingScene, rect_pt: Rect2, mark: bool, photo_tuning: Dictionary, full: Image) -> Image:
	if full == null:
		return null
	var photo := ScenePhoto.crop(full, rect_pt, scene.photo_scale())
	if photo == null:
		return null
	if mark:
		ScenePhoto.stamp(photo, scene.photo_scale(), float(photo_tuning["stamp_margin_pt"]), float(photo_tuning["stamp_max_share"]))
	return photo
