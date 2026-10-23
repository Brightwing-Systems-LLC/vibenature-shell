class_name SceneWelcomeWindow
extends SceneConfigWindow

## The first-run welcome (issue 199; proposals
## `2026-10-18-daily-rhythm.md` "The first run" and `2026-10-18-the-elder.md`). It opens by itself once, when the
## van has driven in and you have stepped out at its door: the one time the app may take focus, because the person
## just launched it. Five steps, in order, each one Config's own controls (so every choice is the same one Config
## changes later): you (the avatar picker; you at the door change as you choose), your elder (one of two, in your
## skin tone; the relationship; the name), your wrap-up time (optional), connect (each agent's status and the
## installer's dry run in plain words before one click connects), open at login (on by default; done by the release
## app, issue 196). Every step can be skipped: what is already set is a sensible default. Done or skipped, you walk
## to the log and sit, and the elder's first letter waits (Game.finish_welcome).

signal finished

const YOU := 0
const ELDER_STEP := 1
const WRAP := 2
const CONNECT := 3
const LOGIN := 4
const STEP_NAMES: Array[String] = ["You", "Your elder", "Wrap-up", "Connect", "Open at login"]

var step_box := VBoxContainer.new()
var steps: Array[Control] = []
var step := 0
var back: Button
var next: Button
var skip: Button
var step_label := Label.new()


func setup(owner_game: Game) -> void:
	_prepare(owner_game, SceneConfigWindow.game_size_pt(owner_game.balance.data["welcome"]))
	title = "VibeNature · welcome"
	var box := _frame()
	box.add_child(_welcome_header())
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tabs.focus_mode = Control.FOCUS_NONE
	box.add_child(tabs)
	_add_tab(STEP_NAMES[YOU], _you_step())
	_add_tab(STEP_NAMES[ELDER_STEP], _elder_step())
	_add_tab(STEP_NAMES[WRAP], _wrap_step())
	_add_tab(STEP_NAMES[CONNECT], _connect_step())
	_add_tab(STEP_NAMES[LOGIN], _login_step())
	# The steps are walked in order with Back and Next; the tabs show where you are.
	tabs.tabs_visible = true
	for i in tabs.get_tab_count():
		tabs.set_tab_disabled(i, false)
	tabs.tab_changed.connect(func(i: int) -> void: _show_step(i))
	box.add_child(_footer())
	window_input.connect(_on_key)


## Shows the welcome on its first step beside the scene and takes focus, this one time.
func open_welcome() -> void:
	_show_step(YOU)
	refresh()
	position = SceneConfigWindow.place_beside(Rect2i(game.scene.position, game.scene.size), size, game.scene_usable(),
			int(_pt("gap_to_scene_pt")))
	show()
	grab_focus()


func refresh() -> void:
	avatar_picker.set_look(game.avatar_look())
	avatar_picker.set_van(game.van_paint())
	_refresh_elder()
	var wrap_at := String(game.settings.data["wrap_up"])
	wrap_up.set_pressed_no_signal(wrap_at != "")
	wrap_up_time.editable = wrap_at != ""
	_show_status(claude_code_status(), claude_status, claude_dot)
	_show_status(codex_status_now(), codex_status, codex_dot)
	open_at_login.set_pressed_no_signal(bool(game.settings.data["open_at_login"]))


## Next: on to the following step, or done after the last.
func go_next() -> void:
	if step >= STEP_NAMES.size() - 1:
		finish()
		return
	_show_step(step + 1)


func go_back() -> void:
	_show_step(maxi(0, step - 1))


## "No thanks" on the wrap-up: it stays off, and on to the next step.
func no_wrap_up() -> void:
	if String(game.settings.data["wrap_up"]) != "":
		game.set_wrap_up("")
	refresh()
	go_next()


## Skip the rest: whatever is set now stays (every step starts on a sensible default), and you walk to the log.
func skip_all() -> void:
	finish()


func finish() -> void:
	if not visible and not game.welcome_pending:
		return
	hide()
	finished.emit()


## Esc is the same as skipping the rest.
func close_config() -> void:
	skip_all()


func _show_step(i: int) -> void:
	step = clampi(i, 0, STEP_NAMES.size() - 1)
	if tabs.current_tab != step:
		tabs.current_tab = step
	if step == ELDER_STEP:
		_refresh_elder()
	back.disabled = step == 0
	back.visible = step > 0
	next.text = "Done" if step == STEP_NAMES.size() - 1 else "Next"
	step_label.text = "%d of %d" % [step + 1, STEP_NAMES.size()]
	WindowChrome.redraw(self)


func _welcome_header() -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", int(6 * _k))
	var lockup := TextureRect.new()
	lockup.name = "Lockup"
	lockup.texture = load(MARK_DIR.path_join(SceneConfigWindow.lockup_file(_k)))
	lockup.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	lockup.stretch_mode = TextureRect.STRETCH_KEEP
	lockup.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(lockup)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)
	skip = _button("Skip the rest", skip_all)
	skip.name = "SkipAll"
	row.add_child(skip)
	return row


func _footer() -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", int(8 * _k))
	_styled(step_label, "small")
	# On the frame, not the page: the tabs' light ink.
	step_label.add_theme_color_override("font_color", kit.colour("on_tab"))
	step_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(step_label)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)
	back = _button("Back", go_back)
	back.name = "Back"
	row.add_child(back)
	next = _button("Next", go_next)
	next.name = "Next"
	row.add_child(next)
	return row


func _intro(heading: String, words: String) -> Control:
	var box := _column()
	box.add_child(_heading(heading))
	box.add_child(_note(words))
	return box


func _you_step() -> Control:
	var box := _column()
	box.name = "StepYou"
	box.add_child(_intro("Welcome to the pond", "This is you. Choose how you look and the colours of your van; both change at the bank as you choose. Everything here can be changed later in Config, and every step can be skipped."))
	box.add_child(_avatar())
	return box


func _elder_step() -> Control:
	var box := _column()
	box.name = "StepElder"
	box.add_child(_intro("Your elder", "Someone who knew this place gave you their old van. Now and then they write, about the photos you send them."))
	box.add_child(_elder())
	return box


func _wrap_step() -> Control:
	var box := _column()
	box.name = "StepWrap"
	box.add_child(_intro("Your wrap-up time", "Optional. Once, at this time, the light turns golden and you pack the thermos. Keep working and nothing more is said."))
	box.add_child(_wrap_up_row())
	var no := _button("No thanks", no_wrap_up)
	no.name = "NoThanks"
	no.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	box.add_child(no)
	return box


func _connect_step() -> Control:
	var box := _column()
	box.name = "StepConnect"
	box.add_child(_intro("Connect your agents", "When an agent starts or stops working, the pond notices: something arrives, or it goes quiet. Only that. Nothing an agent does or reads is ever sent."))
	box.add_child(_card("Claude Code", _status_row(claude_dot, claude_status)))
	box.add_child(_card("Codex", _status_row(codex_dot, codex_status)))
	box.add_child(_connect_controls())
	box.add_child(_note("Not now is fine: Config, Connections has the same button."))
	return box


func _login_step() -> Control:
	var box := _column()
	box.name = "StepLogin"
	box.add_child(_intro("Open at login", "VibeNature can start by itself when you log in, quietly, without taking focus."))
	box.add_child(_open_at_login_row())
	box.add_child(_note("Done takes you to the log."))
	return box


func _set_elder(key: String, value: String) -> void:
	super._set_elder(key, value)
	WindowChrome.redraw(self)
