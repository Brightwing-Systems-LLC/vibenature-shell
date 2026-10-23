class_name SelfTest
extends Node

## VIBENATURE_SELF_TEST=1: plays the avatar loop through the game's own code paths (no
## mouse events anywhere on the desktop), then closes up.

var game: Game


func run(owner_game: Game) -> void:
	game = owner_game
	await _wait(1.5)
	var was_on_top := game.get_window().always_on_top
	game.set_all_on_top(true)
	var bed := _patch_with("flower_bed")
	if bed == null:
		_say("no flower bed out today; skipping the flower loop")
	else:
		var bed_rules: Object = bed.mechanic
		var plot: Vector2 = bed_rules.get("_points").values()[0]
		_say("click the flower bed: the avatar poofs there")
		game._on_patch_clicked(bed, MOUSE_BUTTON_LEFT, plot)
		await _wait(1.5)
		_say("avatar on %s holding %s" % [game.avatar.patch.def.id if game.avatar.patch else "home", game.avatar.tool_id])
		for tool_id in ["seed_bag", "watering_can"]:
			_say("tool square: %s, then the plot" % tool_id)
			game._select_tool(bed, tool_id)
			game._on_patch_clicked(bed, MOUSE_BUTTON_LEFT, plot)
			await _wait(3.0)
		_say("plots: %s" % JSON.stringify(bed_rules.get("model").plots))
	var pond := _patch_with("fishing_hole")
	if pond != null:
		var pond_rules: Object = pond.mechanic
		_say("click the fishing hole: poof over, cast with the rod")
		game._on_patch_clicked(pond, MOUSE_BUTTON_LEFT, pond.arrival_point())
		await _wait(1.5)
		game._on_patch_clicked(pond, MOUSE_BUTTON_LEFT, pond_rules.get("_water"))
		await _wait(3.0)
		_say("fishing state: %s" % pond_rules.get("model").state)
	_say("bench: home")
	game._on_bench_clicked()
	await _wait(1.5)
	_say("avatar home: %s" % game.avatar.is_home())
	_say("debug panel and Config")
	game._open_debug_panel()
	await _wait(1.0)
	game.debug_panel.hide_panel()
	game._on_sign_clicked()
	await _wait(1.0)
	game.config.close_config()
	game.set_all_on_top(was_on_top)
	_say("passed; closing up")
	game.quit()


func _patch_with(kind: String) -> PatchWindow:
	for patch in game.patches:
		if patch.mechanic != null and patch.mechanic.kind() == kind:
			return patch
	return null


func _wait(seconds: float) -> Signal:
	return get_tree().create_timer(seconds).timeout


func _say(text: String) -> void:
	print("VibeNature self-test: " + text)
