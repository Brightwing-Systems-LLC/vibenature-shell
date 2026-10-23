class_name ShelfIslandWindow
extends Window

## One shelf island in its own window, for the shelf demo: sky above, the placeholder island,
## a placeholder bird perched in every band at that band's size, the avatar in the front
## band and a caption below. In a pond, a placeholder fish steps through the voxel grid (back
## to front, side to side, up and down) on a slow timer; a pieced island shows its seams.
## Click the top: the avatar walks the front band to that point across, and the column, rank
## and u under the click are reported.

signal spot_clicked(window: ShelfIslandWindow, where: Dictionary)

var spec: Dictionary
var geo: ShelfGeometry
var scale_px := 1
var sky_px := 0
var pointer: PointerHandler
var _art := Node2D.new()
var _creatures := Node2D.new()
var _avatar: CreatureSprite
var _pos := Vector2.ZERO
var _target := Vector2.ZERO
var _speed := 40.0
var _stroll := Timer.new()
var _strolling := false
var _rng := RandomNumberGenerator.new()
var _fish: Sprite2D
var _fish_path: Array = []
var _fish_step := 0
var _fish_timer := Timer.new()


func setup(island: Dictionary, shelf: Dictionary, scale: int, drag_threshold_px: float, click_epsilon: float, idle_fps_max: float) -> void:
	spec = island
	scale_px = scale
	sky_px = int(shelf["sky_px"])
	geo = ShelfDemo.geometry(spec, shelf)
	var image := ShelfRenderer.render(geo, shelf, spec)
	var caption_px := int(shelf["caption_px"])
	var art_size := Vector2i(image.get_width(), sky_px + image.get_height() + caption_px)
	title = "VibeNature · shelf · %s" % spec["label"]
	WindowChrome.configure(self, art_size * scale_px)
	_art.scale = Vector2(scale_px, scale_px)
	add_child(_art)
	var island_sprite := Sprite2D.new()
	island_sprite.texture = ImageTexture.create_from_image(image)
	island_sprite.centered = false
	island_sprite.position = Vector2(0, sky_px)
	_art.add_child(island_sprite)
	if bool(spec.get("seams", false)):
		for x in geo.seams():
			var seam := ColorRect.new()
			seam.color = Color(Color("fbff86"), 0.7)
			seam.position = Vector2(x, sky_px)
			seam.size = Vector2(1, image.get_height())
			seam.mouse_filter = Control.MOUSE_FILTER_IGNORE
			_art.add_child(seam)
	if not geo.pond.is_empty():
		_fish_path = fish_path(geo)
		_fish = Sprite2D.new()
		_art.add_child(_fish)
		_fish_timer.wait_time = float(shelf["fish_step_sec"])
		_fish_timer.timeout.connect(_step_fish)
		add_child(_fish_timer)
		_step_fish()
	_creatures.y_sort_enabled = true
	_art.add_child(_creatures)
	for band in range(1, geo.bands + 1):
		if not geo.in_top(geo.point_at(band, ShelfDemo.BIRD_U[band - 1])):
			continue
		var bird := Sprite2D.new()
		var size := geo.size_px(band)
		bird.texture = ShelfDemo.bird_texture(size)
		bird.centered = false
		bird.offset = -Vector2(size / 2, size - 1)
		bird.position = _to_art(geo.point_at(band, ShelfDemo.BIRD_U[band - 1])).round()
		_creatures.add_child(bird)
	var avatar_def := Avatar.load_def("a_medium_p1", {"avatar_frame": shelf["avatar_frame"],
			"avatar_figure": shelf["avatar_figure"], "avatar_build_widths": {}}, idle_fps_max)
	_avatar = CreatureSprite.new(avatar_def)
	_avatar.set_layer(Avatar.view_for("idle"))
	_pos = _to_art(geo.point_at(1, 0.5)).round()
	_avatar.position = _pos
	_creatures.add_child(_avatar)
	_speed = float(shelf["walk_speed_px_per_sec"])
	var caption := Label.new()
	caption.text = String(spec["label"])
	caption.add_theme_font_size_override("font_size", 9 * scale_px)
	caption.add_theme_color_override("font_color", Color("ffffff"))
	caption.add_theme_color_override("font_outline_color", Color("2e222f"))
	caption.add_theme_constant_override("outline_size", 3 * scale_px)
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	caption.position = Vector2(0, (sky_px + image.get_height()) * scale_px)
	caption.size = Vector2(art_size.x * scale_px, caption_px * scale_px)
	caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(caption)
	var click := Image.create_empty(art_size.x, art_size.y, false, Image.FORMAT_RGBA8)
	click.blend_rect(image, Rect2i(Vector2i.ZERO, image.get_size()), Vector2i(0, sky_px))
	WindowChrome.set_click_shape(self, click, Vector2i.ZERO, scale_px, click_epsilon)
	pointer = PointerHandler.new(self, drag_threshold_px)
	pointer.clicked.connect(_on_clicked)
	_rng.seed = hash(spec["label"])
	_stroll.one_shot = true
	_stroll.timeout.connect(_stroll_step)
	add_child(_stroll)


func _ready() -> void:
	set_process(false)
	if _fish != null:
		_fish_timer.start()
	_avatar.play("idle")


func _to_art(island_point: Vector2) -> Vector2:
	return island_point + Vector2(0, sky_px)


func _on_clicked(button: int, at: Vector2) -> void:
	if button != MOUSE_BUTTON_LEFT:
		return
	var where := geo.locate(at / scale_px - Vector2(0, sky_px))
	if where.is_empty():
		return
	where["size"] = geo.size_class(int(where["band"]))
	spot_clicked.emit(self, where)
	walk_to_u(float(where["u"]))


## The voxels a demo fish visits, in order: from the back rank to the front, and in each rank
## down the rows and across the columns, turning at each end (a serpentine through the box).
static func fish_path(island: ShelfGeometry) -> Array:
	var out: Array = []
	var p := island.pond
	var flip := false
	for rank in range(int(p["r1"]), 0, -1):
		for row in range(1, int(p["w"]) + 1):
			var cols := range(int(p["c0"]), int(p["c1"]))
			if flip:
				cols.reverse()
			for c in cols:
				out.append(Vector3i(c, rank, row))
			flip = not flip
	return out


func _step_fish() -> void:
	var v: Vector3i = _fish_path[_fish_step % _fish_path.size()]
	var next: Vector3i = _fish_path[(_fish_step + 1) % _fish_path.size()]
	_fish_step += 1
	_fish.texture = ShelfDemo.fish_texture(geo.fish_px(v.y))
	_fish.flip_h = next.x < v.x
	_fish.position = _to_art(geo.voxel_point(v.x, v.y, v.z)).round()
	WindowChrome.redraw(self)


## The avatar walks the front band to `u` across. It never leaves the front band, nor steps
## off it where a corner is cut.
func walk_to_u(u: float) -> void:
	u = clampf(u, 0.05, 0.95)
	while not geo.in_top(geo.point_at(1, u)) and absf(u - 0.5) > 0.01:
		u = move_toward(u, 0.5, 0.02)
	_target = _to_art(geo.point_at(1, u)).round()
	if _target == _pos:
		return
	_avatar.set_layer(Avatar.view_for("walk"))
	_avatar.flip_h = _target.x < _pos.x
	_avatar.play("walk")
	if not is_processing():
		set_process(true)
		Pace.start_moving()


## Strolling back and forth on its own (off by default: walking costs battery).
func set_stroll(on: bool) -> void:
	_strolling = on
	if not on:
		_stroll.stop()
	elif not is_processing():
		_stroll_step()


func _stroll_step() -> void:
	walk_to_u(_rng.randf_range(0.1, 0.9))


func _process(delta: float) -> void:
	_pos = _pos.move_toward(_target, _speed * delta)
	_avatar.move_to(_pos.round())
	if _pos == _target:
		set_process(false)
		Pace.stop_moving()
		_avatar.set_layer(Avatar.view_for("idle"))
		_avatar.flip_h = false
		_avatar.play("idle")
		if _strolling:
			_stroll.start(_rng.randf_range(1.0, 3.0))


func _exit_tree() -> void:
	if is_processing():
		Pace.stop_moving()
