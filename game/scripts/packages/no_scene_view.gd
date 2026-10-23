class_name NoSceneView
extends Control

## What the shell shows when it has no scene package to play (issue 487): a plain card in the screen's
## bottom-right corner that says so, where a scene goes, and a Quit button. Nothing else starts: no event
## server, no save, no hooks. The open shell built from source has no scene of its own (the scenes are
## separate, data-only packages), so this is its first screen until one is added; it must never crash.
##
## Drawn in the root window with Godot's default theme and font, so it needs no art. It never takes focus,
## raises itself or activates the app (the root window is `no_focus`, SPEC §2.1).

const TITLE := "No scene installed"
const BODY := "This VibeNature shell has no scene package to play. Scenes are separate, data-only packages: put one in game/packages/<id>/ (a folder with its package.json) and start the shell again."
## The window's size in points; multiplied by the screen's scale for macOS window units.
const SIZE_PT := Vector2i(360, 132)
const MARGIN_PT := 16
const PAPER := Color(0.96, 0.95, 0.91)
const INK := Color(0.16, 0.18, 0.16)

signal quit_requested

var title_label: Label
var body_label: Label
var quit_button: Button


## The line every run prints in this state (a check reads it): the packages it looked at and any refused.
static func status_line() -> String:
	var refused: Array = []
	for r in ScenePackages.refused:
		refused.append("%s (%s)" % [String(r["path"]).get_file(), r["why"]])
	return "VibeNature: no scene installed; %s" % (
			"refused: " + "; ".join(refused) if not refused.is_empty() else "no scene package found")


## Sets up `window` (the root) as the card and builds the view; the caller adds it to the tree.
func show_in(window: Window) -> void:
	var scale := maxf(1.0, DisplayServer.screen_get_max_scale())
	window.content_scale_factor = scale
	window.transparent = false
	window.mouse_passthrough = false
	window.size = Vector2i(Vector2(SIZE_PT) * scale)
	var usable := DisplayServer.screen_get_usable_rect(DisplayServer.window_get_current_screen())
	var margin := int(MARGIN_PT * scale)
	window.position = usable.end - window.size - Vector2i(margin, margin)
	_build()


func _build() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var paper := Panel.new()
	var style := StyleBoxFlat.new()
	style.bg_color = PAPER
	paper.add_theme_stylebox_override("panel", style)
	paper.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(paper)
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_FULL_RECT)
	box.offset_left = 14
	box.offset_top = 10
	box.offset_right = -14
	box.offset_bottom = -10
	box.add_theme_constant_override("separation", 6)
	add_child(box)
	title_label = Label.new()
	title_label.text = TITLE
	title_label.add_theme_font_size_override("font_size", 17)
	title_label.add_theme_color_override("font_color", INK)
	box.add_child(title_label)
	body_label = Label.new()
	body_label.text = BODY
	body_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body_label.add_theme_font_size_override("font_size", 12)
	body_label.add_theme_color_override("font_color", INK)
	body_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(body_label)
	quit_button = Button.new()
	quit_button.text = "Quit"
	quit_button.focus_mode = Control.FOCUS_NONE
	quit_button.size_flags_horizontal = Control.SIZE_SHRINK_END
	quit_button.pressed.connect(func() -> void: quit_requested.emit())
	box.add_child(quit_button)
