class_name SceneConfigWindow
extends Window

## The living scene's config (Skypatch issue 169),
## opened by the strip's ⚙. Its own small window beside the scene, one size whatever the scene's
## size. Tabs: General (size, sound, birds outside the window, on top, over full screen, quit),
## Day (the day phases; no workday since issue 198), Connections (status only), Avatar (the picker, issue 202) and Photos.
## The VibeNature lockup (badge and wordmark) sits in the header.
##
## Like the island game's Config, the one kind of window that may take keyboard focus (SPEC §2.1,
## issue 30), and only because the person opened it.

signal closed

const GENERAL := 0
const DAY := 1
const CONNECTIONS := 2
const AVATAR := 3
const PHOTOS := 4
## The elder who writes to you (issue 213): who, the relationship and the name they sign with.
const ELDER := 5
const TAB_NAMES: Array[String] = ["General", "Day", "Connections", "Avatar", "Photos", "Elder"]
## Where Claude Code keeps its hooks; VibeNature's hook command names this.
const HOOK_MARKER := "vibenature-hook"

## The bench's lone tree badge and wordmark (Skypatch issue 170).
const MARK_DIR := "res://assets/ui/vibenature_mark"

var game: Game
var tabs := TabContainer.new()
var tuning: Dictionary = {}
## Path of Claude Code's settings file read for the hook (tests point it elsewhere).
var claude_settings_path := ""
## Path of Codex's hooks file ($CODEX_HOME/hooks.json, default ~/.codex/hooks.json).
var codex_hooks_path := ""
## The scene's sizes in Config, one segment per step (50…100%), in `display.scene_sizes` order.
var size_steps: Array[Button] = []
var sound := CheckButton.new()
var desktop_flights := CheckButton.new()
var mirror := CheckButton.new()
var on_top := CheckButton.new()
var over_full_screen := CheckButton.new()
var photo_mark := CheckButton.new()
## The optional wrap-up time (issue 198): a switch, off by default, and its time.
var wrap_up := CheckButton.new()
## The optional start-of-day time (issue 431): a switch, off by default, and its time.
var start_of_day := CheckButton.new()
var start_of_day_time: LineEdit
## Open at login (issue 199), done by the release app (issue 196, `LoginItem`).
var open_at_login := CheckButton.new()
const OPEN_AT_LOGIN_HELP := "VibeNature starts quietly when you log in. System Settings, General, Login Items has it too."
## The installer's logic (issue 199) and its words, and the two buttons: see the plan, then connect.
var connector: HookConnect
var connect_words := VBoxContainer.new()
var connect_plan: Button
var connect_now: Button
## The chosen elder's portrait in your skin tone (Elder tab and the welcome).
var elder_portrait := TextureRect.new()
var wrap_up_time: LineEdit
var claude_status := Label.new()
var claude_dot := ColorRect.new()
var codex_status := Label.new()
var codex_dot := ColorRect.new()
## "Show the scene on": a box per screen (issue 174).
var screen_picker := SceneScreenPicker.new()
var screen_caption := Label.new()
## Which bottom corner, and the lift off the bottom edge (issue 422): one segment per choice.
var corner_steps: Array[Button] = []
var lift_steps: Array[Button] = []
## The mouse clear's size (issue 438): one segment per size.
var mouse_clear_steps: Array[Button] = []
## The field-kit pieces everything is drawn with (issue 174).
var kit: SceneConfigKit
var _k := 1.0
var _colors := {}
var avatar_picker := SceneAvatarPicker.new()
## The Elder tab's segments (by elder id and by relationship) and the name field.
var elder_buttons := {}
var relation_buttons := {}
var elder_name: LineEdit


func setup(owner_game: Game) -> void:
	_prepare(owner_game, game_size_pt(owner_game.balance.data["scene_config"]))
	var box := _frame()
	box.add_child(_header())
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tabs.focus_mode = Control.FOCUS_NONE
	box.add_child(tabs)
	_add_tab(TAB_NAMES[GENERAL], _general())
	_add_tab(TAB_NAMES[DAY], _day())
	_add_tab(TAB_NAMES[CONNECTIONS], _connections())
	_add_tab(TAB_NAMES[AVATAR], _avatar())
	_add_tab(TAB_NAMES[PHOTOS], _photos())
	_add_tab(TAB_NAMES[ELDER], _elder())
	window_input.connect(_on_key)


static func game_size_pt(block: Dictionary) -> Vector2:
	return Vector2(float(block["size_pt"][0]), float(block["size_pt"][1]))


## What Config and the welcome (issue 199) share: the scale, the hook files, the window's kind, the field kit.
func _prepare(owner_game: Game, size_pt: Vector2) -> void:
	game = owner_game
	tuning = game.balance.data["scene_config"]
	for key in tuning["colors"]:
		_colors[key] = Color(String(tuning["colors"][key]))
	_k = Game.ui_scale(Snapshot.on(), DisplayServer.screen_get_max_scale())
	# The person's own home, except in tests and snapshots (Game.hook_home): never the real ~/.claude there.
	connector = HookConnect.new(game.hook_home(), game.balance.data["welcome"]["python"])
	claude_settings_path = connector.settings_path("claude")
	codex_hooks_path = connector.settings_path("codex")
	title = "VibeNature · settings"
	visible = false
	borderless = true
	unresizable = true
	transparent = false
	transparent_bg = false
	unfocusable = false
	# Opened by the person, so it comes up above every other window (issue 225).
	always_on_top = true
	size = Vector2i((size_pt * _k).round())
	content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	# The kit's pieces are pixel art at one sheet px per device px.
	canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	kit = SceneConfigKit.new(_k)
	# Text colours are the kit's; the status dot's stay in balance.json.
	_colors["text"] = kit.colour("ink")
	_colors["dim_text"] = kit.colour("ink_soft")
	_colors["accent"] = kit.colour("heading")
	theme = _theme()


## The kit's frame over the whole window and the padded column inside it.
func _frame() -> VBoxContainer:
	var background := Panel.new()
	background.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(background)
	var pad := kit.layout("page_inset_pt") * _k
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_FULL_RECT)
	box.offset_left = pad
	box.offset_top = pad * 0.75
	box.offset_right = -pad
	box.offset_bottom = -pad
	box.add_theme_constant_override("separation", int(_pt("gap_pt")))
	add_child(box)
	return box


## Shows the window on `tab`, beside the scene, and takes keyboard focus (the person opened it).
func open(tab: int) -> void:
	tabs.current_tab = tab
	refresh()
	position = place_beside(Rect2i(game.scene.position, game.scene.size), size, game.scene_usable(),
			int(_pt("gap_to_scene_pt")))
	show()
	grab_focus()


func close_config() -> void:
	if not visible:
		return
	hide()
	closed.emit()


## Left of the scene, bottom edges level; right of it when there is no room to the left (the scene in the
## bottom-left corner, issue 422); above it when there is room on neither side; always on the screen.
static func place_beside(scene: Rect2i, own: Vector2i, screen: Rect2i, gap: int) -> Vector2i:
	var at := Vector2i(scene.position.x - own.x - gap, scene.end.y - own.y)
	if at.x < screen.position.x and scene.end.x + gap + own.x <= screen.end.x:
		at = Vector2i(scene.end.x + gap, scene.end.y - own.y)
	elif at.x < screen.position.x and scene.get_center().y < screen.get_center().y:
		# A scene in a top corner (issue 424): below it.
		at = Vector2i(scene.end.x - own.x, scene.end.y + gap)
	elif at.x < screen.position.x:
		at = Vector2i(scene.end.x - own.x, scene.position.y - own.y - gap)
	at.x = clampi(at.x, screen.position.x, maxi(screen.position.x, screen.end.x - own.x))
	at.y = clampi(at.y, screen.position.y, maxi(screen.position.y, screen.end.y - own.y))
	return at


func refresh() -> void:
	var percent := game.scene_percent()
	for b in size_steps:
		b.set_pressed_no_signal(int(b.get_meta("percent")) == percent)
	sound.set_pressed_no_signal(bool(game.settings.data["sound"]))
	desktop_flights.set_pressed_no_signal(bool(game.settings.data["desktop_flights"]))
	on_top.set_pressed_no_signal(bool(game.settings.data["on_top"]))
	over_full_screen.set_pressed_no_signal(bool(game.settings.data["show_over_full_screen"]))
	photo_mark.set_pressed_no_signal(bool(game.settings.data["photo_mark"]))
	open_at_login.set_pressed_no_signal(bool(game.settings.data["open_at_login"]))
	var wrap_at := String(game.settings.data["wrap_up"])
	wrap_up.set_pressed_no_signal(wrap_at != "")
	wrap_up_time.editable = wrap_at != ""
	if wrap_at != "":
		wrap_up_time.text = wrap_at
		wrap_up_time.set_meta("saved", wrap_at)
	var start_at := String(game.settings.data["start_of_day"])
	start_of_day.set_pressed_no_signal(start_at != "")
	start_of_day_time.editable = start_at != ""
	if start_at != "":
		start_of_day_time.text = start_at
		start_of_day_time.set_meta("saved", start_at)
	screen_picker.set_screens(game.screens_source.call(), game.scene_screen())
	for b in corner_steps:
		b.set_pressed_no_signal(String(b.get_meta("corner")) == game.scene_corner())
	mirror.set_pressed_no_signal(game.scene_mirror())
	for b in lift_steps:
		b.set_pressed_no_signal(int(b.get_meta("lift")) == game.scene_lift_pt())
		# A top corner sits flush under the menu bar: the lift is for the bottom edge only.
		b.disabled = game.scene_on_top()
	for b in mouse_clear_steps:
		b.set_pressed_no_signal(int(b.get_meta("size")) == game.mouse_clear_pt())
	_show_status(claude_code_status(), claude_status, claude_dot)
	_show_status(codex_status_now(), codex_status, codex_dot)
	avatar_picker.set_look(game.avatar_look())
	avatar_picker.set_van(game.van_paint())
	_refresh_elder()


func _refresh_elder() -> void:
	if game.letters == null or elder_name == null:
		return
	var choice := game.elder_choice()
	for id in elder_buttons:
		(elder_buttons[id] as Button).set_pressed_no_signal(String(id) == String(choice["who"]))
	for id in relation_buttons:
		(relation_buttons[id] as Button).set_pressed_no_signal(String(id) == String(choice["relation"]))
	elder_name.text = game.letters.name_of(choice)
	elder_name.placeholder_text = game.letters.default_name(choice)
	elder_portrait.texture = game.elder_portrait(String(choice["who"]))
	elder_portrait.visible = elder_portrait.texture != null


func _show_status(status: Dictionary, label: Label, dot: ColorRect) -> void:
	label.text = String(status["text"])
	dot.color = _colors["ok"] if status["state"] == "heard" else (_colors["warn"] if status["state"] == "installed" else _colors["line"])


## Claude Code's connection, as status only: whether the hook is installed, and whether the
## event server has heard anything from it this run. Nothing an event said is ever shown.
func claude_code_status() -> Dictionary:
	return harness_status("claude_code", claude_settings_path, "Hook installed. Nothing heard yet this run.")


## Codex's, the same way. Codex runs a new hook only once it is trusted in its /hooks.
func codex_status_now() -> Dictionary:
	return harness_status("codex", codex_hooks_path, "Hook installed. Trust it once in Codex's /hooks; nothing heard yet this run.")


func harness_status(source: String, path: String, installed_text: String) -> Dictionary:
	var at := 0.0
	if game.bridge != null:
		at = float(game.bridge.last_heard_from.get(source, 0.0))
	if at > 0.0:
		var minutes := maxi(0, int((game.clock.now() - at) / 60.0))
		var when := "just now" if minutes < 1 else ("%d min ago" % minutes if minutes < 60 else "%d h ago" % (minutes / 60))
		return {"state": "heard", "text": "Connected. Last heard from %s." % when}
	if SceneConfigWindow.hook_installed(path):
		return {"state": "installed", "text": installed_text}
	return {"state": "off", "text": "Not connected. Connect… below shows what it would change first."}


## Whether Claude Code's settings carry VibeNature's hook. Reads only for the hook's own name.
static func hook_installed(path: String) -> bool:
	if path == "" or not FileAccess.file_exists(path):
		return false
	return FileAccess.get_file_as_string(path).contains(HOOK_MARKER)


func _header() -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", int(6 * _k))
	var lockup := TextureRect.new()
	lockup.name = "Lockup"
	lockup.texture = load(MARK_DIR.path_join(SceneConfigWindow.lockup_file(_k)))
	lockup.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	# The bench renders it natively at each scale: drawn at its own pixels, never resampled.
	lockup.stretch_mode = TextureRect.STRETCH_KEEP
	lockup.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(lockup)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)
	var close := _button("Close", close_config)
	close.name = "Close"
	row.add_child(close)
	return row


## The lockup (badge and wordmark) for a dark background, rendered for `ui_scale` device px per point:
## 1, 2 or 4 (the scales the bench renders), the largest not above it.
static func lockup_file(ui_scale: float) -> String:
	if ui_scale >= 4.0:
		return "lockup_dark@4x.png"
	if ui_scale >= 2.0:
		return "lockup_dark@2x.png"
	return "lockup_dark.png"


func _add_tab(tab_name: String, content: Control) -> void:
	var scroll := ScrollContainer.new()
	scroll.name = tab_name
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var margin := MarginContainer.new()
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, int(kit.layout("page_padding_pt") * _k))
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.add_child(content)
	scroll.add_child(margin)
	tabs.add_child(scroll)


func _general() -> Control:
	var box := _column()
	box.add_child(_heading("Show the scene on"))
	screen_picker.name = "ScreenPicker"
	screen_picker.setup(kit, _k, float(tuning["picker_height_pt"]), float(tuning["picker_gap_pt"]))
	screen_picker.caption = screen_caption
	screen_picker.picked.connect(game.move_scene_to_screen)
	box.add_child(screen_picker)
	screen_caption.add_theme_color_override("font_color", _colors["accent"])
	box.add_child(screen_caption)
	box.add_child(_place_rows())
	box.add_child(HSeparator.new())
	var sizes := HBoxContainer.new()
	sizes.add_theme_constant_override("separation", int(kit.layout("segment_gap_pt") * _k))
	var group := ButtonGroup.new()
	size_steps.clear()
	for step in game.balance.data["display"]["scene_sizes"]:
		var percent := int(step)
		var b := Button.new()
		b.name = "Size%d" % percent
		b.set_meta("percent", percent)
		b.text = "%d%%" % percent
		b.toggle_mode = true
		b.button_group = group
		b.focus_mode = Control.FOCUS_NONE
		b.theme_type_variation = "Segment"
		b.custom_minimum_size = Vector2(float(tuning["size_step_w_pt"]), kit.size_pt("segment").y) * _k
		b.pressed.connect(func() -> void: game.set_scene_size(percent))
		sizes.add_child(b)
		size_steps.append(b)
	var size_row := VBoxContainer.new()
	size_row.add_theme_constant_override("separation", int(6 * _k))
	size_row.add_child(_row("Scene size", "Smaller sizes shrink the scene into its corner.", Control.new()))
	size_row.add_child(sizes)
	box.add_child(size_row)
	box.add_child(HSeparator.new())
	box.add_child(_switch_row(sound, "Sound", "Off by default. The pond, very quietly.", game.set_sound))
	box.add_child(_switch_row(desktop_flights, "Birds outside the window", "Now and then a bird flies out over the desktop.", game.set_desktop_flights))
	box.add_child(_switch_row(on_top, "Always on top", "Keep the scene above other windows.", game.set_all_on_top))
	box.add_child(_switch_row(over_full_screen, "Show over full screen", "Also show over apps in full screen.", game.set_show_over_full_screen))
	box.add_child(_open_at_login_row())
	box.add_child(HSeparator.new())
	box.add_child(_start_of_day_row())
	box.add_child(_wrap_up_row())
	box.add_child(HSeparator.new())
	var quit := _button("Quit VibeNature", game.quit)
	quit.name = "Quit"
	box.add_child(_row("Close up", "Saves first, then quits.", quit))
	return box


## The corner the scene holds and its lift off the bottom edge (issue 422), each a row of segments.
func _place_rows() -> Control:
	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", int(6 * _k))
	var names := {"top_left": "Top left", "top_right": "Top right", "bottom_left": "Bottom left", "bottom_right": "Bottom right"}
	corner_steps.clear()
	var corners := _segments(rows, "Corner", "The edges against the screen stay straight; the open ones fade into the desktop.")
	var corner_group := ButtonGroup.new()
	for corner in ["top_left", "top_right", "bottom_left", "bottom_right"]:
		if not (game.balance.data["display"]["scene_corners"] as Array).has(corner):
			continue
		var c := String(corner)
		var b := _segment(String(names[c]), corner_group, "Corner_" + c)
		b.set_meta("corner", c)
		b.pressed.connect(func() -> void: game.set_scene_corner(c))
		corners.add_child(b)
		corner_steps.append(b)
	rows.add_child(_switch_row(mirror, "Mirror the scene", "Draws the pond the other way round, in any corner.", game.set_scene_mirror))
	lift_steps.clear()
	var lifts := _segments(rows, "Lift", "Raises the scene off the bottom edge, in points (bottom corners).")
	var lift_group := ButtonGroup.new()
	for step in game.balance.data["display"]["scene_lifts_pt"]:
		var lift := int(step)
		var b := _segment("Flush" if lift == 0 else "%d" % lift, lift_group, "Lift%d" % lift)
		b.set_meta("lift", lift)
		b.pressed.connect(func() -> void: game.set_scene_lift(lift))
		lifts.add_child(b)
		lift_steps.append(b)
	mouse_clear_steps.clear()
	var clears := _segments(rows, "Mouse clear", "A see-through circle round the pointer, shown only while the scene is on top.")
	var clear_group := ButtonGroup.new()
	var clear_names := ["Small", "Medium", "Large", "Extra large"]
	var sizes: Array = game.balance.data["scene"]["mouse_clear"]["diameters_pt"]
	for i in sizes.size():
		var points := int(sizes[i])
		var b := _segment(String(clear_names[i]) if i < clear_names.size() else "%d" % points, clear_group, "MouseClear%d" % points)
		b.set_meta("size", points)
		b.tooltip_text = "%d points across" % points
		b.pressed.connect(func() -> void: game.set_mouse_clear_size(points))
		clears.add_child(b)
		mouse_clear_steps.append(b)
	return rows


func _segments(rows: VBoxContainer, title_text: String, help: String) -> HBoxContainer:
	rows.add_child(_row(title_text, help, Control.new()))
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", int(kit.layout("segment_gap_pt") * _k))
	rows.add_child(line)
	return line


## Open at login (issue 199): on by default. Only the release app adds itself to Login Items (issue 196); a dev run
## keeps the choice. A change made in System Settings comes back here (`Game.sync_login_item`).
func _open_at_login_row() -> Control:
	open_at_login.name = "OpenAtLogin"
	return _switch_row(open_at_login, "Open at login", OPEN_AT_LOGIN_HELP, game.set_open_at_login)


## The start-of-day time (issue 431): after it, the van brings you when you are at your desk. Off by default: the
## first sign of the day brings it.
func _start_of_day_row() -> Control:
	var initial := String(game.settings.data["start_of_day"])
	if initial == "":
		initial = String(game.balance.data["daily_rhythm"]["start_default"])
	start_of_day_time = _time_edit(initial, func(value: String) -> void:
		if start_of_day.button_pressed:
			game.set_start_of_day(value))
	start_of_day_time.name = "StartOfDayTime"
	start_of_day_time.editable = String(game.settings.data["start_of_day"]) != ""
	start_of_day.name = "StartOfDay"
	var controls := HBoxContainer.new()
	controls.add_theme_constant_override("separation", int(6 * _k))
	controls.add_child(start_of_day_time)
	controls.add_child(start_of_day)
	start_of_day.focus_mode = Control.FOCUS_NONE
	start_of_day.toggled.connect(func(on: bool) -> void:
		start_of_day_time.editable = on
		game.set_start_of_day(String(start_of_day_time.get_meta("saved")) if on else ""))
	return _row("Start of day", "Optional. After this time, the van brings you when you sit down at this Mac.", controls)


## The wrap-up time (issue 198): once, at that time, the scene invites you to stop, without words.
## Off by default; "No thanks" is fine.
func _wrap_up_row() -> Control:
	var initial := String(game.settings.data["wrap_up"])
	if initial == "":
		initial = String(game.balance.data["daily_rhythm"]["wrap_default"])
	wrap_up_time = _time_edit(initial, func(value: String) -> void:
		if wrap_up.button_pressed:
			game.set_wrap_up(value))
	wrap_up_time.name = "WrapUpTime"
	wrap_up_time.editable = String(game.settings.data["wrap_up"]) != ""
	wrap_up.name = "WrapUp"
	var controls := HBoxContainer.new()
	controls.add_theme_constant_override("separation", int(6 * _k))
	controls.add_child(wrap_up_time)
	controls.add_child(wrap_up)
	wrap_up.focus_mode = Control.FOCUS_NONE
	wrap_up.toggled.connect(func(on: bool) -> void:
		wrap_up_time.editable = on
		game.set_wrap_up(String(wrap_up_time.get_meta("saved")) if on else ""))
	return _row("Wrap-up time", "Optional. Once, at this time, the scene invites you to stop. Keep working and nothing more is said.", controls)


func _day() -> Control:
	var box := _column()
	box.add_child(_heading("Day phases"))
	var phases := GridContainer.new()
	phases.columns = 2
	phases.add_theme_constant_override("h_separation", int(12 * _k))
	phases.add_theme_constant_override("v_separation", int(4 * _k))
	var phase_data: Dictionary = game.settings.data["day_phases"]
	for phase in phase_data:
		var name_label := _label(String(phase).replace("_", " ").capitalize())
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		phases.add_child(name_label)
		phases.add_child(_time_edit(String(phase_data[phase]), func(value: String) -> void: _set_phase(String(phase), value)))
	box.add_child(phases)
	box.add_child(HSeparator.new())
	box.add_child(_note("New times count from the next start."))
	return box


func _connections() -> Control:
	var box := _column()
	box.add_child(_card("Claude Code", _status_row(claude_dot, claude_status)))
	box.add_child(_card("Codex", _status_row(codex_dot, codex_status)))
	box.add_child(_connect_controls())
	box.add_child(_note("Only whether events arrive is shown here. Nothing they contain is read, shown or kept."))
	return box


## One-click connect (issue 199), the installer's logic: "Connect…" shows its dry run in plain words; only
## "Connect" then writes. Shared by the Connections tab and the welcome's connect step.
func _connect_controls() -> Control:
	var box := _column()
	connect_words.name = "ConnectWords"
	connect_words.add_theme_constant_override("separation", int(4 * _k))
	box.add_child(connect_words)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", int(8 * _k))
	connect_plan = _button("Connect…", show_connect_plan)
	connect_plan.name = "ConnectPlan"
	row.add_child(connect_plan)
	connect_now = _button("Connect", connect_agents)
	connect_now.name = "ConnectNow"
	connect_now.visible = false
	row.add_child(connect_now)
	box.add_child(row)
	return box


## The dry run, said in plain words; nothing is written.
func show_connect_plan() -> void:
	var report := connector.plan()
	_say(connector.plain(report))
	var changes := false
	for h in report.get("harnesses", []):
		if not ((h["added"] as Array).is_empty() and (h["removed"] as Array).is_empty()):
			changes = true
	connect_now.visible = changes
	connect_plan.text = "Check again"


## Connects for real (after the plan was shown) and shows what was done and each harness's status.
func connect_agents() -> void:
	if connector.last_plan.is_empty():
		show_connect_plan()
		return
	var report := connector.install()
	var lines: Array[String] = []
	if report.has("error"):
		lines.append("Not connected: %s" % String(report["error"]))
	else:
		for h in report.get("harnesses", []):
			lines.append("%s is connected." % String(h["name"]))
		lines.append_array(connector.refusals(report))
		var steps := connector.next_steps(report)
		if not steps.is_empty():
			lines.append("Next:")
			lines.append_array(steps)
	_say(lines)
	connect_now.visible = false
	connect_plan.text = "Connect…"
	_show_status(claude_code_status(), claude_status, claude_dot)
	_show_status(codex_status_now(), codex_status, codex_dot)


func _say(lines: Array[String]) -> void:
	for child in connect_words.get_children():
		connect_words.remove_child(child)
		child.queue_free()
	for line in lines:
		var label := _note(line)
		label.name = "Said_%d" % connect_words.get_child_count()
		connect_words.add_child(label)


func _status_row(dot: ColorRect, label: Label) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", int(8 * _k))
	dot.custom_minimum_size = Vector2(8, 8) * _k
	dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(dot)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)
	return row


## The avatar picker (issue 202): a choice is saved and sat on the log at once.
func _avatar() -> Control:
	avatar_picker.setup(kit, _k, game.balance.data["avatar_looks"], game.avatar_look(), float(tuning["min_small_pt"]))
	avatar_picker.changed.connect(game.set_avatar_look)
	# Your van (issue 279): body and accent paint, saved and painted on the van at once.
	avatar_picker.setup_van(SceneVan.file(game.balance.data["scene"]["day"]["van"], "art"), game.van_meta(), game.van_paint())
	avatar_picker.van_changed.connect(game.set_van_paint)
	return avatar_picker


func _photos() -> Control:
	var box := _column()
	box.add_child(_switch_row(photo_mark, "VibeNature mark", "Put the VibeNature mark on saved photos.", game.set_photo_mark))
	box.add_child(_note("More photo settings: coming soon."))
	return box


## Who writes to you, how you are related, and the name they sign with (the default follows the elder and
## the relationship until you type your own). The welcome (issue 199) will ask the same.
func _elder() -> Control:
	var box := _column()
	if game.letters == null:
		return box
	var family: Dictionary = game.letters.family
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", int(10 * _k))
	elder_portrait.name = "ElderPortrait"
	elder_portrait.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	elder_portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	elder_portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	# One sheet px per point on whole device px, like the journal's.
	var portrait_pt: Array = game.balance.data["scene_book"]["portrait_pt"]
	elder_portrait.custom_minimum_size = Vector2(float(portrait_pt[0]), float(portrait_pt[1])) * maxf(1.0, roundf(_k))
	elder_portrait.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	top.add_child(elder_portrait)
	var who_box := _column()
	who_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	who_box.add_child(_heading("Who writes to you"))
	top.add_child(who_box)
	box.add_child(top)
	var who_row := HBoxContainer.new()
	who_row.add_theme_constant_override("separation", int(kit.layout("segment_gap_pt") * _k))
	var who_group := ButtonGroup.new()
	for id in family.get("order", []):
		var b := _segment(String(family["elders"][id]["label"]), who_group, "Elder_" + String(id))
		b.pressed.connect(func() -> void: _set_elder("who", String(id)))
		elder_buttons[String(id)] = b
		who_row.add_child(b)
	who_box.add_child(who_row)
	who_box.add_child(_note("They are older, and share your skin tone."))
	box.add_child(HSeparator.new())
	box.add_child(_heading("How you are related"))
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", int(kit.layout("segment_gap_pt") * _k))
	grid.add_theme_constant_override("v_separation", int(kit.layout("segment_gap_pt") * _k))
	var rel_group := ButtonGroup.new()
	for id in family.get("relations", []):
		var b := _segment(String(family["relation_labels"][id]), rel_group, "Relation_" + String(id))
		b.pressed.connect(func() -> void: _set_elder("relation", String(id)))
		relation_buttons[String(id)] = b
		grid.add_child(b)
	box.add_child(grid)
	box.add_child(HSeparator.new())
	elder_name = LineEdit.new()
	elder_name.name = "ElderName"
	elder_name.max_length = 24
	elder_name.custom_minimum_size = Vector2(160, kit.size_pt("field").y) * _k
	var commit := func() -> void:
		var text := elder_name.text.strip_edges()
		_set_elder("name", "" if text == game.letters.default_name(game.elder_choice()) else text)
	elder_name.text_submitted.connect(func(_t: String) -> void: commit.call())
	elder_name.focus_exited.connect(commit)
	box.add_child(_row("Their name", "They sign their letters with it. Empty is the usual name.", elder_name))
	box.add_child(_note("Letters come now and then, about photos you send from the journal."))
	_refresh_elder()
	return box


func _segment(text: String, group: ButtonGroup, node_name: String) -> Button:
	var b := Button.new()
	b.name = node_name
	b.text = text
	b.toggle_mode = true
	b.button_group = group
	b.focus_mode = Control.FOCUS_NONE
	b.theme_type_variation = "Segment"
	b.custom_minimum_size.y = kit.size_pt("segment").y * _k
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return b


func _set_elder(key: String, value: String) -> void:
	var choice := game.elder_choice().duplicate()
	choice[key] = value
	game.set_elder(choice)
	_refresh_elder()


func _set_phase(phase: String, value: String) -> void:
	game.settings.data["day_phases"][phase] = value
	game.settings.save()


## An HH:MM field, saved on Return or on leaving it; anything invalid goes back.
func _time_edit(value: String, on_change: Callable) -> LineEdit:
	var edit := LineEdit.new()
	edit.text = value
	edit.max_length = 5
	edit.alignment = HORIZONTAL_ALIGNMENT_CENTER
	edit.custom_minimum_size = Vector2(64, kit.size_pt("field").y) * _k
	edit.set_meta("saved", value)
	var commit := func() -> void:
		var text := edit.text.strip_edges()
		if ConfigWindow.valid_time(text) and text != String(edit.get_meta("saved")):
			edit.set_meta("saved", text)
			on_change.call(text)
		edit.text = String(edit.get_meta("saved"))
	edit.text_submitted.connect(func(_text: String) -> void: commit.call())
	edit.focus_exited.connect(commit)
	return edit


func _column() -> VBoxContainer:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", int(_pt("gap_pt")))
	return box


## A setting: its name and a line saying what it does on the left, its control on the right.
func _row(title_text: String, help: String, control: Control) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", int(10 * _k))
	var words := VBoxContainer.new()
	words.add_theme_constant_override("separation", int(1 * _k))
	words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var name_label := _label(title_text)
	_styled(name_label, "label")
	words.add_child(name_label)
	words.add_child(_note(help))
	row.add_child(words)
	control.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(control)
	return row


func _switch_row(switch: CheckButton, title_text: String, help: String, on_toggle: Callable) -> Control:
	switch.focus_mode = Control.FOCUS_NONE
	switch.toggled.connect(func(on: bool) -> void: on_toggle.call(on))
	return _row(title_text, help, switch)


## A heading, its content, and the divider under it.
func _card(title_text: String, content: Control) -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", int(6 * _k))
	box.add_child(_heading(title_text))
	box.add_child(content)
	box.add_child(HSeparator.new())
	return box


func _heading(text: String) -> Label:
	var label := _label(text)
	label.add_theme_color_override("font_color", _colors["accent"])
	_styled(label, "heading")
	return label


## Fraunces in one of the kit's styles. Small text is never under `min_small_pt` (12 pt is tight on a 1x screen).
func _styled(label: Label, style_name: String) -> void:
	var size_pt := kit.font_size_pt(style_name)
	if style_name == "small":
		size_pt = maxf(size_pt, float(tuning["min_small_pt"]))
	label.add_theme_font_override("font", kit.font(style_name))
	label.add_theme_font_size_override("font_size", int(round(size_pt * _k)))


func _label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	return label


func _note(text: String) -> Label:
	var label := _label(text)
	label.add_theme_color_override("font_color", _colors["dim_text"])
	_styled(label, "small")
	label.autowrap_mode = TextServer.AUTOWRAP_WORD
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return label


func _button(text: String, call: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size.y = kit.size_pt("button").y * _k
	button.pressed.connect(call)
	return button


func _on_key(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key != null and key.pressed and key.keycode == KEY_ESCAPE:
		close_config()


func _pt(key: String) -> float:
	return float(tuning[key]) * _k


## Everything from the field kit: the frame round the window, the page under the tabs, the tabs,
## buttons, Full/Half segments (theme type `Segment`), toggles, day boxes, time fields, dividers.
func _theme() -> Theme:
	return SceneConfigWindow.field_theme(kit, _k)


## Shared with the book (issue 177).
static func field_theme(kit: SceneConfigKit, _k: float) -> Theme:
	var t := Theme.new()
	t.default_font = kit.font("body")
	t.default_font_size = int(round(kit.font_size_pt("body") * _k))
	t.set_stylebox("panel", "Panel", kit.style("frame"))
	t.set_stylebox("panel", "TabContainer", SceneConfigWindow.pad_pt(_k, kit.style("page"), 0, 0))
	var tab_pad := kit.layout("tab_pad_pt")
	for pair in [["tab_selected", "selected"], ["tab_unselected", "normal"], ["tab_hovered", "hover"]]:
		var tab := SceneConfigWindow.pad_pt(_k, kit.style("tab", pair[1]), tab_pad, 3)
		# The tabs stand on the page: the selected one's paper covers the page's top border.
		tab.expand_margin_bottom = kit.layout("tab_overlap_pt") * _k
		t.set_stylebox(pair[0], "TabContainer", tab)
	for state in ["font_selected_color", "font_unselected_color", "font_hovered_color"]:
		t.set_color(state, "TabContainer", kit.colour("on_tab"))
	t.set_font("font", "TabContainer", kit.font("label"))
	t.set_constant("tab_separation", "TabContainer", int(kit.layout("tab_gap_pt") * _k))
	for kind in ["Label", "LineEdit", "CheckBox"]:
		t.set_color("font_color", kind, kit.colour("ink"))
	for state in ["font_hover_color", "font_pressed_color", "font_hover_pressed_color", "font_focus_color"]:
		t.set_color(state, "CheckBox", kit.colour("ink"))
	t.set_font("font", "Button", kit.font("label"))
	t.set_color("font_color", "Button", kit.colour("on_button"))
	t.set_color("font_hover_color", "Button", kit.colour("on_button"))
	t.set_color("font_focus_color", "Button", kit.colour("on_button"))
	t.set_color("font_pressed_color", "Button", kit.colour("on_button_pressed"))
	t.set_color("font_hover_pressed_color", "Button", kit.colour("on_button_pressed"))
	for state in ["normal", "hover", "pressed"]:
		t.set_stylebox(state, "Button", SceneConfigWindow.pad_pt(_k, kit.style("button", state), 12, 2))
	t.set_stylebox("hover_pressed", "Button", SceneConfigWindow.pad_pt(_k, kit.style("button", "pressed"), 12, 2))
	t.set_type_variation("Segment", "Button")
	for pair in [["normal", "normal"], ["hover", "hover"], ["pressed", "selected"], ["hover_pressed", "selected"]]:
		t.set_stylebox(pair[0], "Segment", SceneConfigWindow.pad_pt(_k, kit.style("segment", pair[1]), 12, 2))
	for state in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color", "font_focus_color"]:
		t.set_color(state, "Segment", kit.colour("on_segment"))
	t.set_icon("checked", "CheckBox", kit.texture("check", "on"))
	t.set_icon("unchecked", "CheckBox", kit.texture("check", "off"))
	t.set_constant("h_separation", "CheckBox", int(4 * _k))
	t.set_icon("checked", "CheckButton", kit.texture("toggle", "on"))
	t.set_icon("checked_mirrored", "CheckButton", kit.texture("toggle", "on"))
	t.set_icon("unchecked", "CheckButton", kit.texture("toggle", "off"))
	t.set_icon("unchecked_mirrored", "CheckButton", kit.texture("toggle", "off"))
	for kind in ["CheckBox", "CheckButton"]:
		for state in ["normal", "hover", "pressed", "hover_pressed"]:
			t.set_stylebox(state, kind, StyleBoxEmpty.new())
	t.set_stylebox("normal", "LineEdit", SceneConfigWindow.pad_pt(_k, kit.style("field"), 6, 2))
	t.set_stylebox("focus", "LineEdit", StyleBoxEmpty.new())
	var divider := kit.style("divider")
	# Its nine-slice has no top or bottom margin; the content margins give it its native height.
	var divider_h := kit.size_pt("divider").y * _k
	divider.content_margin_top = floorf(divider_h / 2.0)
	divider.content_margin_bottom = divider_h - floorf(divider_h / 2.0)
	t.set_stylebox("separator", "HSeparator", divider)
	t.set_constant("separation", "HSeparator", int(divider_h))
	t.set_stylebox("panel", "ScrollContainer", StyleBoxEmpty.new())
	return t


## Content margins in points (the kit's pieces carry only their nine-slice margins).
static func pad_pt(_k: float, box: StyleBoxTexture, x_pt: float, y_pt: float) -> StyleBoxTexture:
	box.content_margin_left = x_pt * _k
	box.content_margin_right = x_pt * _k
	box.content_margin_top = y_pt * _k
	box.content_margin_bottom = y_pt * _k
	return box
