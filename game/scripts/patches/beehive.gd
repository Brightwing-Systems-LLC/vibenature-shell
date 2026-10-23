class_name Beehive
extends PatchMechanic

## Beehive: the hive fills with honey over a few hours, faster while flowers bloom
## in the player's beds. When it is full, click it (no tool needed): the waggle dance
## starts, and repeating it sends a jar of honey to the bin. The patch wakes only when
## the honey reaches its next level.

var model := HiveModel.new()
var _hive := Vector2.ZERO
var _hive_layer := "front"
var _sprite: CreatureSprite
var _dance: WaggleDance
var _timer := Timer.new()


func kind() -> String:
	return "beehive"


func _tuning() -> Dictionary:
	return game.balance.data["beehive"]


func _setup_mechanic() -> void:
	var hives := patch.def.spots_of_kind("hive")
	if hives.is_empty():
		_hive = patch.island_to_art((Vector2(patch.def.size) * Vector2(0.5, 0.4)).round())
	else:
		_hive = patch.spot_point(hives[0])
		_hive_layer = patch.spot_layer(hives[0])
	var levels := int(_tuning()["levels"])
	var size := AssetLibrary.vec2i(game.balance.data["placeholders"]["hive"])
	var def := CreatureDef.load_single("fauna", "beehive", game.idle_fps_max, CreatureDef.sheet_layer(
			size, levels, Color("f9c22b"), {"idle": {"frames": [0], "fps": 1.0, "loop": true}},
			Vector2i(size.x / 2, size.y - 1)))
	_sprite = CreatureSprite.new(def)
	_sprite.set_layer("front")
	_sprite.position = _hive
	patch.layer_node(_hive_layer).add_child(_sprite)
	_timer.one_shot = true
	_timer.timeout.connect(_refresh)
	add_child(_timer)
	model.start(game.clock.now())
	_refresh()


func _bloom_bonus() -> float:
	var hive := _tuning()
	return minf(float(hive["bloom_bonus_max"]), game.blooming_flowers() * float(hive["bloom_bonus_per_flower"]))


func _refresh() -> void:
	var hive := _tuning()
	var hours := float(hive["honey_hours"])
	var bonus := _bloom_bonus()
	var levels := int(hive["levels"])
	model.update(game.clock.now(), hours, bonus)
	_sprite.show_frame(model.level(levels))
	_timer.stop()
	var wait := model.seconds_to_next_level(levels, hours, bonus)
	if wait < INF:
		# Wake at the next level, but at least every so often, since blooms change
		# the rate.
		wait = minf(wait, float(hive["check_minutes"]) * 60.0)
		_timer.start(game.clock.real_seconds(wait + 1.0))
	game.request_save()


## The hands on a full hive start the waggle dance.
func use_tool(tool_id: String, art_point: Vector2) -> bool:
	if tool_id != "hands" or _dance != null:
		return false
	return _start_dance(art_point)


func stand_point(_tool_id: String, _art_point: Vector2) -> Vector2:
	return (_hive + Vector2(AssetLibrary.vec2i(game.balance.data["avatar"]["stand_offset_px"]))).round()


func on_click(art_point: Vector2) -> bool:
	if _dance != null:
		_dance.press(art_point)
		return true
	if art_point.distance_to(_hive) > float(_tuning()["click_radius_px"]):
		return false
	return _start_dance(art_point)


func _start_dance(_art_point: Vector2) -> bool:
	model.update(game.clock.now(), float(_tuning()["honey_hours"]), _bloom_bonus())
	if not model.is_full():
		return false
	_dance = WaggleDance.new()
	_dance.finished.connect(_on_dance_finished)
	_dance.start(patch, _hive, _tuning()["dance"], game.rng)
	game.refresh_capture(patch)
	return true


func wants_all_clicks() -> bool:
	return _dance != null


func _on_dance_finished(success: bool) -> void:
	_dance = null
	game.refresh_capture(patch)
	if success and model.collect():
		var item := {"kind": "honey", "id": "honey", "rarity": "common", "value": int(_tuning()["honey_payout"])}
		game.send_to_bin(item, patch.art_to_screen(_hive))
	elif not success:
		print("VibeNature: the bees lost the thread (the honey's still there)")
	_refresh()


func on_time_jump() -> void:
	_refresh()


func debug_actions() -> Array:
	return [{"label": "Fill the hive", "call": _debug_fill}]


func _debug_fill() -> void:
	model.honey = 1.0
	_refresh()


func save_state() -> Dictionary:
	return model.to_dict()


func load_state(state: Dictionary) -> void:
	model.from_dict(state)
	model.start(game.clock.now())
	_refresh()
