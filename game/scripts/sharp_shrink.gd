class_name SharpShrink
extends RefCounted

## "Sharp bilinear" for the scene's in-between sizes (Skypatch issue 222):
## the content is drawn nearest at a whole scale (the scene's full size) into its own viewport, and
## that render is shrunk smoothly to the window. Every art pixel keeps an even width; only edges
## soften, by under a device px. Never nearest at an uneven scale.
##
## The render is premultiplied (a transparent viewport blends over transparent black), so it is
## drawn with premultiplied blending and filtered linearly without dark fringes at the scene's
## dissolving edges.

## Where the content is drawn, at the render scale.
var viewport: SubViewport
## The render, shrunk into the window.
var view: Sprite2D
## Window units per render unit (under 1).
var ratio := Vector2.ONE


## Whether a window shown at `shown` units per point needs drawing at `render` and shrinking.
static func needed(shown: float, render: float) -> bool:
	return render > shown + 0.0001


## Puts `content` into a new viewport of `render_size` under `host`, and the shrunk render where
## `content` would have been, filling `shown_size` (window units).
func build(host: Node, content: Node2D, render_size: Vector2i, shown_size: Vector2i) -> void:
	viewport = SubViewport.new()
	viewport.name = "SharpRender"
	viewport.size = render_size
	viewport.transparent_bg = true
	viewport.disable_3d = true
	viewport.gui_disable_input = true
	viewport.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	viewport.snap_2d_transforms_to_pixel = true
	viewport.snap_2d_vertices_to_pixel = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.add_child(content)
	host.add_child(viewport)
	view = Sprite2D.new()
	view.name = "SharpView"
	view.centered = false
	view.texture = viewport.get_texture()
	view.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	var blend := CanvasItemMaterial.new()
	blend.blend_mode = CanvasItemMaterial.BLEND_MODE_PREMULT_ALPHA
	view.material = blend
	ratio = Vector2(shown_size) / Vector2(render_size)
	view.scale = ratio
	host.add_child(view)


## Renders every frame (`on`) or only once more (a transit window going empty).
func set_live(on: bool) -> void:
	if viewport != null:
		viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS if on else SubViewport.UPDATE_ONCE
