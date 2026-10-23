class_name WindowChrome
extends RefCounted

## What every VibeNature window shares: transparent, borderless, never focusable,
## behind other windows unless the player opts in, and click-through outside its
## opaque pixels. Dragging is PointerHandler's.


static func configure(window: Window, size_px: Vector2i) -> void:
	window.borderless = true
	window.transparent = true
	window.transparent_bg = true
	window.unfocusable = true
	window.always_on_top = false
	window.unresizable = true
	# Clear old limits first: the root window is reconfigured after a scale change.
	window.min_size = Vector2i.ZERO
	window.max_size = Vector2i.ZERO
	window.size = size_px
	window.min_size = size_px
	window.max_size = size_px
	window.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	window.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	window.snap_2d_transforms_to_pixel = true
	window.snap_2d_vertices_to_pixel = true


## Windows draw only when asked to: Godot otherwise re-renders every window when
## anything in any of them changes.
static func draw_on_demand(window: Window) -> void:
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	if not is_instance_valid(window):
		return
	RenderingServer.viewport_set_update_mode(window.get_viewport_rid(), RenderingServer.VIEWPORT_UPDATE_DISABLED)


static func redraw(viewport: Viewport) -> void:
	if viewport != null:
		RenderingServer.viewport_set_update_mode(viewport.get_viewport_rid(), RenderingServer.VIEWPORT_UPDATE_ONCE)


## For a window that was hidden or changes for a while: draw every frame for a
## moment, then go back to drawing on demand.
static func wake(window: Window) -> void:
	RenderingServer.viewport_set_update_mode(window.get_viewport_rid(), RenderingServer.VIEWPORT_UPDATE_ALWAYS)
	WindowChrome.draw_on_demand(window)


static func toggle_on_top(window: Window) -> void:
	window.always_on_top = not window.always_on_top
	print("VibeNature: %s on top = %s" % [window.title, window.always_on_top])


## Clicks pass through every pixel outside the largest opaque region of `image`,
## drawn with its top-left at `origin_art` and scaled by `scale_px`.
static func set_click_shape(window: Window, image: Image, origin_art: Vector2i, scale_px: int, epsilon: float) -> PackedVector2Array:
	var shape := click_shape(image, origin_art, scale_px, epsilon)
	window.mouse_passthrough_polygon = shape
	return shape


static func click_shape(image: Image, origin_art: Vector2i, scale_px: int, epsilon: float) -> PackedVector2Array:
	var bitmap := BitMap.new()
	bitmap.create_from_image_alpha(image, 0.5)
	var polygons := bitmap.opaque_to_polygons(Rect2i(Vector2i.ZERO, image.get_size()), epsilon)
	var best := PackedVector2Array()
	var best_area := 0.0
	for polygon in polygons:
		var area := absf(_area(polygon))
		if area > best_area:
			best_area = area
			best = polygon
	var shape := PackedVector2Array()
	for point in best:
		shape.append((point + Vector2(origin_art)) * scale_px)
	return shape


static func _area(polygon: PackedVector2Array) -> float:
	var sum := 0.0
	for i in polygon.size():
		var a := polygon[i]
		var b := polygon[(i + 1) % polygon.size()]
		sum += a.x * b.y - b.x * a.y
	return sum / 2.0
