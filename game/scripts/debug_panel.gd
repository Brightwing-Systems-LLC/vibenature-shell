class_name DebugPanel
extends Window

## Option-click home (development runs only): buttons that make things happen
## now, for testing. Each patch out today adds its own (PatchMechanic.debug_actions).
## Plain Godot controls on purpose: this is a tool, not part of the game's look.

var game: Game
var _status := Label.new()
var _status_timer := Timer.new()
var _box := VBoxContainer.new()
var _pointer: PointerHandler


func setup(owner_game: Game) -> void:
	game = owner_game
	title = "VibeNature · debug"
	var k := maxi(1, roundi(DisplayServer.screen_get_max_scale()))
	visible = false
	WindowChrome.configure(self, Vector2i(380, 560) * k)
	transparent = false
	transparent_bg = false
	always_on_top = true
	var theme_ := Theme.new()
	theme_.default_font_size = 13 * k
	theme = theme_
	var background := Panel.new()
	background.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(background)
	var scroll := ScrollContainer.new()
	scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	scroll.offset_left = 10 * k
	scroll.offset_top = 8 * k
	scroll.offset_right = -10 * k
	scroll.offset_bottom = -8 * k
	add_child(scroll)
	_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_box.add_theme_constant_override("separation", 6 * k)
	scroll.add_child(_box)
	_status_timer.timeout.connect(_update_status)
	add_child(_status_timer)
	_pointer = PointerHandler.new(self, float(game.balance.data["input"]["drag_threshold_px"]))
	_build()


func _build() -> void:
	# The status line is kept and re-added; everything else is rebuilt, since the
	# patches out (and so their buttons) can change.
	for child in _box.get_children():
		_box.remove_child(child)
		if child != _status:
			child.queue_free()
	var top := HBoxContainer.new()
	var heading := Label.new()
	heading.text = "Debug"
	heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(heading)
	top.add_child(_button("Close", hide_panel))
	_box.add_child(top)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD
	_box.add_child(_status)

	if game.shelf_demo != null:
		for section in game.shelf_demo.debug_sections():
			_section(section[0], section[1])
	_section("Time", [
		["+1 hour", func() -> void: game.debug_advance(3600.0)],
		["+6 hours", func() -> void: game.debug_advance(6 * 3600.0)],
		["Next dawn (new day)", game.debug_new_day],
	])
	_section("World", [
		["Agent turn ended", game.debug_agent_turn],
		["Cloud", func() -> void: game.signals.send("cloud", "debug")],
		["Rain now", game.debug_rain],
		["Sunlight", func() -> void: game.signals.send("sunlight", "debug")],
		["Golden window on/off", game.debug_toggle_golden],
	])
	var birds: Array = [["Random bird arrives", func() -> void: game.birds.spawn()]]
	var names: Array = game.content.species("birds").keys()
	names.sort()
	for species in names:
		birds.append([String(species).replace("_", " "), func() -> void: game.birds.spawn(String(species))])
	_section("Birds", birds)
	for patch in game.patches:
		if patch.mechanic == null:
			continue
		var actions: Array = []
		for action in patch.mechanic.debug_actions():
			actions.append([action["label"], action["call"]])
		if not actions.is_empty():
			_section(patch.def.id.replace("_", " "), actions)
	if game.scene != null:
		_section("The van", [
			["Van arrives", func() -> void: game.debug_van("arrive")],
			["Van leaves", func() -> void: game.debug_van("leave")],
		])
		_section("Scene", game.scene.debug_actions())
	_section("Economy and collection", [
		["+50 bucks", func() -> void: game.debug_bucks(50)],
		["Next patch arrives", game.debug_next_patch],
	])


func _section(heading: String, actions: Array) -> void:
	var label := Label.new()
	label.text = heading
	label.add_theme_color_override("font_color", Color("f9c22b"))
	_box.add_child(label)
	var flow := HFlowContainer.new()
	for action in actions:
		flow.add_child(_button(String(action[0]), action[1]))
	_box.add_child(flow)


func _button(text: String, call: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.focus_mode = Control.FOCUS_NONE
	button.pressed.connect(func() -> void:
		call.call()
		_update_status()
		WindowChrome.wake(self))
	return button


func open_near(anchor: Window) -> void:
	_build()
	var screen := DisplayServer.screen_get_usable_rect(DisplayServer.window_get_current_screen(anchor.get_window_id()))
	var at := Vector2i(anchor.position.x - size.x - 8, anchor.position.y + anchor.size.y - size.y)
	at.x = clampi(at.x, screen.position.x, maxi(screen.position.x, screen.end.x - size.x))
	at.y = clampi(at.y, screen.position.y, maxi(screen.position.y, screen.end.y - size.y))
	position = at
	show()
	_update_status()
	_status_timer.start(1.0)
	WindowChrome.wake(self)


func hide_panel() -> void:
	_status_timer.stop()
	hide()


func _update_status() -> void:
	var clock := game.clock
	var d := clock.local()
	_status.text = "%04d-%02d-%02d %02d:%02d (%s) · day %s\n%d bucks · bin %d (%d items) · bait %d · %s%s" % [
		int(d["year"]), int(d["month"]), int(d["day"]), int(d["hour"]), int(d["minute"]),
		game.settings.day_phases().phase_at(clock.local_minutes()), game.day_key(),
		game.economy.bucks, game.economy.bin_total(), game.economy.bin.size(), game.economy.bait,
		"golden window" if game.signals.is_golden() else "no golden window",
		" · raining" if game.weather.raining else ""]
	if game.bridge != null:
		_status.text += "\nagents: %s · %d sessions, %d busy · %d events in, %d refused%s" % [
			"127.0.0.1:%d" % game.bridge.server.port() if game.bridge.server.listening() else "not listening",
			game.bridge.sessions.sessions.size(), game.bridge.sessions.busy_count(),
			game.bridge.server.accepted, game.bridge.server.rejected,
			" · long stretch" if game.bridge.long_stretch() else ""]
	if game.shelf_demo != null:
		_status.text += "\n" + game.shelf_demo.describe()
	WindowChrome.redraw(self)
