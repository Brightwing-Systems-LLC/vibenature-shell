class_name TransitWindow
extends Window

## A small transparent window that carries a creature across the desktop between
## patches. Fully click-through and never focusable; it stays open and empty
## between crossings so showing a bird never creates or orders a window.

## The native extension knows this window by this exact title and keeps it above every normal
## window and the on-top ones, under the menu bar (macos_windows.m `kOverlayTitle`; test.sh checks
## the two agree). Never rename the window
## (issue 235).
const OVERLAY_TITLE := "VibeNature · overlay"

## Window units per frame unit. A scene at half size on a 1× screen is ½ (issue 179), so this is
## not always whole; the window's size and position stay whole units either way.
var scale_px: float
## Units per frame unit the art is drawn at: `scale_px`, or at the scene's in-between sizes the
## full size's, shrunk smoothly to `scale_px` like the scene (`SharpShrink`, issue 222).
var render_scale: float
var shrink: SharpShrink
var _art := Node2D.new()


func setup(frame_size: Vector2i, scale: float, draw_scale: float = 0.0) -> void:
	scale_px = scale
	render_scale = maxf(draw_scale, scale)
	title = OVERLAY_TITLE
	WindowChrome.configure(self, Vector2i((Vector2(frame_size) * scale_px).ceil()))
	# Always on top, so Godot asks for a level and the extension lifts it to the overlay's.
	always_on_top = true
	mouse_passthrough = true
	_art.scale = Vector2(render_scale, render_scale)
	if SharpShrink.needed(scale_px, render_scale):
		shrink = SharpShrink.new()
		shrink.build(self, _art, Vector2i((Vector2(size) * render_scale / scale_px).round()), size)
		shrink.set_live(false)
	else:
		add_child(_art)


## Draws every frame while a bird is in it, else once more (empty) and then on demand.
func set_live(on: bool) -> void:
	if shrink != null:
		shrink.set_live(on)
	if on:
		RenderingServer.viewport_set_update_mode(get_viewport_rid(), RenderingServer.VIEWPORT_UPDATE_ALWAYS)
	else:
		WindowChrome.redraw(self)


func host() -> Node2D:
	return _art


## Puts the creature's anchor (inside the frame) at `screen_point`.
func place(screen_point: Vector2, anchor: Vector2i) -> void:
	var top_left := screen_point - Vector2(anchor) * scale_px
	var step := 1.0 if shrink != null else maxf(1.0, scale_px)
	position = Vector2i(top_left.snapped(Vector2(step, step)))
