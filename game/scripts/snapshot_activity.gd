class_name SnapshotActivity
extends RefCounted

## The activity path of snapshot mode (`just snap-activity`, issue 68): after the first launch,
## the avatar visits each island and uses each of its tools where it makes sense, through the
## same handlers a click calls, skipping game time with the debug clock where growth or a bite
## would take minutes or hours. Each step is captured like the demo path's. A tool that does
## nothing on screen is still captured, so the images show what a player would see.

var s: Snapshot
var game: Game
var _index := 10


func _init(owner: Snapshot) -> void:
	s = owner
	game = owner.game


func run() -> void:
	await _flower_bed()
	await _fishing_hole()
	await _birds()
	await _journal()
	s.notes["journal"] = game.journal.to_dict()
	s.notes["economy"] = game.economy.to_dict()
	game._on_bench_clicked()
	await s._until(func() -> bool: return game.avatar.is_home() and not game.avatar.busy)
	await _shot("home_after")


func _shot(what: String) -> void:
	await s._settle()
	await s._capture("%02d_%s" % [_index, what])
	_index += 1


func _click(patch: PatchWindow, art_point: Vector2) -> void:
	game._on_patch_clicked(patch, MOUSE_BUTTON_LEFT, art_point)


## Picks `tool_id` from the island's tool row, as a click on its square would.
func _pick(patch: PatchWindow, tool_id: String) -> bool:
	var square := patch.tool_square(tool_id)
	if square.size == Vector2.ZERO:
		s._expect(false, "%s has a %s square in its tool row" % [patch.def.id, tool_id])
		return false
	_click(patch, square.get_center())
	await s._settle()
	s._expect(game.avatar.tool_id == tool_id, "%s is in hand on %s (got %s)" % [tool_id, patch.def.id, game.avatar.tool_id])
	return game.avatar.tool_id == tool_id


## Clicks `art_point` with the tool in hand and waits for the avatar to finish. With `doing`,
## also captures the avatar mid-action, once it has walked to its stand spot.
func _use(patch: PatchWindow, art_point: Vector2, doing: String = "") -> void:
	var tool_id := game.avatar.tool_id
	_click(patch, art_point)
	if doing != "" and patch.mechanic != null:
		var stand := patch.mechanic.stand_point(tool_id, art_point)
		await s._until(func() -> bool: return game.avatar.art_position() == stand or not game.avatar.busy)
		await s.get_tree().create_timer(0.25).timeout
		await s._capture("%02d_%s" % [_index, doing])
		_index += 1
	await s._until(func() -> bool: return not game.avatar.busy)


func _visit(patch: PatchWindow, what: String) -> void:
	await s._visit(patch)
	s._expect(game.avatar.patch == patch, "the avatar is on %s" % patch.def.id)
	await _shot(what)


func _flower_bed() -> void:
	var bed := s._patch_with("flower_bed")
	s._expect(bed != null, "the flower bed is out")
	if bed == null:
		return
	await _visit(bed, "flower_arrive")
	# Plots on every row, each clicked a little off its spot: a click anywhere on the bed uses
	# the nearest plot (issue 75).
	var plots: Array = s.tuning["activity_flower_plots"].filter(func(p: String) -> bool: return bed.def.spots.has(p))
	if plots.is_empty():
		plots = bed.def.spots_of_kind("plot")
	var off := Vector2(AssetLibrary.vec2i(s.tuning["activity_flower_click_offset_px"]))
	var model = bed.mechanic.get("model")
	for action: Dictionary in bed.mechanic.debug_actions():
		if action["label"] == "+3 of each seed":
			(action["call"] as Callable).call()
	if await _pick(bed, "seed_bag"):
		await _shot("flower_seed_bag_in_hand")
		for i in plots.size():
			await _use(bed, bed.spot_point(plots[i]) + off, "flower_sowing" if i == 0 else "")
		s._expect(plots.all(func(p: String) -> bool: return model.plots[p]["state"] == "seeded"),
				"every plot is sown (%s)" % _states(model, plots))
		await _shot("flower_sown")
	if await _pick(bed, "watering_can"):
		for i in plots.size():
			await _use(bed, bed.spot_point(plots[i]) - off, "flower_watering" if i == 0 else "")
		s._expect(plots.all(func(p: String) -> bool: return model.plots[p]["state"] == "growing"),
				"every plot is watered (%s)" % _states(model, plots))
		await _shot("flower_watered")
	var stages := ["sprout", "bud", "bloom"]
	var hours: Array = s.tuning["activity_growth_hours"]
	var passed := 0.0
	for i in stages.size():
		game.debug_advance((float(hours[i]) - passed) * 3600.0)
		passed = float(hours[i])
		await _shot("flower_%s" % stages[i])
	# A weed, then the hands pull it.
	for action: Dictionary in bed.mechanic.debug_actions():
		if action["label"] == "Weed now":
			(action["call"] as Callable).call()
	var weedy := ""
	for p in plots:
		if model.plots[p]["weed"]:
			weedy = p
	s._expect(weedy != "", "a weed came up")
	await _shot("flower_weed")
	if await _pick(bed, "hands"):
		if weedy != "":
			await _use(bed, bed.spot_point(weedy), "flower_hands_weeding")
			s._expect(not model.plots[weedy]["weed"], "the hands pulled the weed")
			await _shot("flower_weed_pulled")
		# The hands on a bloom: what a player would try to pick it.
		var blooming: Array = plots.filter(func(p: String) -> bool: return p != weedy)
		if not blooming.is_empty():
			await _use(bed, bed.spot_point(blooming[0]))
			s.notes["hands_on_bloom"] = model.plots[blooming[0]]["state"]
			await _shot("flower_hands_on_bloom")
	if await _pick(bed, "clippers"):
		for i in plots.size():
			await _use(bed, bed.spot_point(plots[i]), "flower_clipping" if i == 0 else "")
			if i == 0:
				await s.get_tree().create_timer(0.15).timeout
				await _shot("flower_bouquet_flying")
		s._expect(plots.all(func(p: String) -> bool: return model.plots[p]["state"] == "empty"),
				"every bloom was cut (%s)" % _states(model, plots))
		await s.get_tree().create_timer(1.5).timeout
		await _shot("flower_harvested")


func _states(model, plots: Array) -> String:
	return ", ".join(plots.map(func(p: String) -> String: return "%s:%s" % [p, model.plots[p]["state"]]))


func _fishing_hole() -> void:
	var pond := s._patch_with("fishing_hole")
	s._expect(pond != null, "the fishing hole is out")
	if pond == null:
		return
	await _visit(pond, "fishing_arrive")
	var water: Vector2 = pond.mechanic.get("_water")
	var model = pond.mechanic.get("model")
	s.notes["fishing_tools"] = game.content.patch_tools(pond.def.id) if pond.tool_square("bait_jar").size == Vector2.ZERO else []
	s.notes["bait_jar_in_tool_row"] = pond.tool_square("bait_jar").size != Vector2.ZERO
	game.avatar.tool_id = "rod"
	pond.select_tool("rod")
	_click(pond, water)
	await s.get_tree().create_timer(0.2).timeout
	await _shot("fishing_casting")
	await s._until(func() -> bool: return not game.avatar.busy)
	s._expect(model.is_baited(), "the cast baits the hook")
	await s.get_tree().create_timer(1.0).timeout
	await _shot("fishing_waiting")
	for action: Dictionary in pond.mechanic.debug_actions():
		if action["label"] == "Bite now":
			(action["call"] as Callable).call()
	s._expect(model.state == "biting", "a fish bites (state %s)" % model.state)
	await s.get_tree().create_timer(0.1).timeout
	await _shot("fishing_bite_splash")
	await s.get_tree().create_timer(1.0).timeout
	await _shot("fishing_bite_dip")
	_click(pond, water)
	await s.get_tree().create_timer(0.1).timeout
	var reel = pond.mechanic.get("_reel")
	s._expect(reel != null, "clicking the bobber starts the reel mini-game")
	await _shot("fishing_reel")
	var hits := 0
	while reel != null and is_instance_valid(reel) and pond.mechanic.get("_reel") != null and hits < 4:
		var in_zone := await s._until(func() -> bool:
			var m := float(reel.get("_marker"))
			var z := float(reel.get("_zone_start"))
			return pond.mechanic.get("_reel") == null or (m > z + 1.0 and m < z + float(reel.get("_zone_px")) - 1.0))
		if not in_zone or pond.mechanic.get("_reel") == null:
			break
		_click(pond, water)
		hits += 1
		if hits == 1 and pond.mechanic.get("_reel") != null:
			await _shot("fishing_reel_hit")
		await s.get_tree().create_timer(0.2).timeout
	s._expect(pond.mechanic.get("_reel") == null and int(game.journal.life["fish"].size()) > 0,
			"the reel lands a fish (%s)" % game.journal.life["fish"])
	await s.get_tree().create_timer(0.15).timeout
	await _shot("fishing_landed")
	await s.get_tree().create_timer(1.5).timeout
	await _shot("fishing_after")
	var bites_before: int = model.bites_left
	if await _pick(pond, "bait_jar"):
		await _use(pond, water)
		await s.get_tree().create_timer(0.3).timeout
		s._expect(model.bites_left > bites_before, "the bait jar adds bites to the hook (%d -> %d)" % [bites_before, model.bites_left])
		s._expect(model.next_bite_at <= game.clock.now() + 20.0, "scattered bait brings a fish soon")
		await _shot("fishing_bait_scattered")
	s.notes["bait_left"] = game.economy.bait


func _birds() -> void:
	var spot := s._patch_with("bird_spot")
	s._expect(spot != null, "the bird spot is out")
	if spot == null:
		return
	await _visit(spot, "birds_arrive")
	var tries := int(s.tuning["activity_bird_tries"])
	for i in tries:
		if _visitor_on(spot).is_empty() and not game.birds.spawn() and not game.birds.visitors.is_empty():
			# Birds already visiting the other islands fill max_visitors: one more, as a known species.
			game.birds.spawn(String(game.birds.visitors[0]["species"]))
	await s._until(func() -> bool: return _perched_on(spot) != null)
	await _shot("birds_perched")
	var visitor := _visitor_on(spot)
	s._expect(not visitor.is_empty(), "a bird perches on the bird spot")
	if visitor.is_empty():
		return
	s._expect(game.avatar.tool_id == "camera", "the bird spot hands the avatar the camera (got %s)" % game.avatar.tool_id)
	var creature: Creature = visitor["creature"]
	var sheet: Dictionary = creature.def.layers[creature.sprite.layer]
	var aim := creature.art_position() - Vector2(sheet["anchor"]) + Vector2(sheet["frame_size"]) / 2.0
	var species := String(visitor["species"])
	var photos := _photo_count()
	_click(spot, aim)
	# The photo pose and the flash last under a second: captured as they happen, no settle.
	await s._until(func() -> bool: return game.avatar.sprite.has_node("HeldCamera") or not game.avatar.busy)
	await s.get_tree().create_timer(0.1).timeout
	await s._capture("%02d_%s" % [_index, "birds_photo_taking"])
	_index += 1
	s._expect(game.avatar.sprite.has_node("HeldCamera"), "the avatar holds the camera up to take the photo")
	await s._until(func() -> bool: return _photo_count() > photos or not game.avatar.busy)
	await s._capture("%02d_%s" % [_index, "birds_photo_flash"])
	_index += 1
	var lit: Color = (spot.get("_art") as Node2D).modulate
	s._expect(lit.r > 1.0, "the camera flashes the island (brightness %.2f)" % lit.r)
	s._expect(_polaroid_shows(species), "the polaroid shows the %s that was photographed" % species)
	await s._until(func() -> bool: return not game.avatar.busy)
	await s.get_tree().create_timer(0.1).timeout
	await _shot("birds_polaroid_flying")
	s._expect(_photo_count() > photos, "the photo goes in the journal (%s)" % game.journal.life["birds"])
	s._expect(game.journal.last_seen["birds"].get(species, "") == game.day_key(), "the journal keeps the day of the photo")
	await s.get_tree().create_timer(1.5).timeout
	await _shot("birds_after_photo")
	# The camera is shared: on another island with a bird on it, if one landed there.
	for patch in game.patches:
		if patch == spot:
			continue
		var other := _visitor_on(patch)
		if other.is_empty() or not _perched(other):
			continue
		await s._visit(patch)
		if await _pick(patch, "camera"):
			var c: Creature = other["creature"]
			var sh: Dictionary = c.def.layers[c.sprite.layer]
			_click(patch, c.art_position() - Vector2(sh["anchor"]) + Vector2(sh["frame_size"]) / 2.0)
			await s._until(func() -> bool: return not game.avatar.busy)
			await _shot("birds_camera_on_%s" % patch.def.id)
		break


## Config's Journal tab after the day's activity: a row for every bird photographed and fish caught.
func _journal() -> void:
	game.open_config(ConfigWindow.JOURNAL)
	await _shot("journal")
	s._expect(game.config.visible and game.config.tabs.current_tab == ConfigWindow.JOURNAL, "Config opens on the Journal tab")
	for category in ["birds", "fish", "night"]:
		for id in game.journal.life[category]:
			s._expect(game.config.find_child("%s_%s" % [category, id], true, false) != null,
					"the journal lists the %s %s" % [category, id])
	game.config.close_config()
	await s._settle()


func _photo_count() -> int:
	var total := 0
	for id in game.journal.life["birds"]:
		total += int(game.journal.life["birds"][id])
	return total


## The polaroid's photo is this species' own perched frame: its picture's pixels sit in the
## polaroid at the photo's corner.
func _polaroid_shows(species: String) -> bool:
	var polaroid: Image = game.item_texture({"kind": "polaroid", "id": species}).get_image()
	var picture := Polaroid.bird_picture(game.birds.def_for(species))
	var tuning: Dictionary = game.balance.data["polaroid"]
	var corner := Vector2i.ONE * (1 + int(tuning["border_px"]) + int(tuning["margin_px"]))
	var opaque := 0
	for y in picture.get_height():
		for x in picture.get_width():
			var c := picture.get_pixel(x, y)
			if c.a < 1.0:
				continue
			opaque += 1
			if not polaroid.get_pixel(corner.x + x, corner.y + y).is_equal_approx(c):
				return false
	return opaque > 0


func _visitor_on(patch: PatchWindow) -> Dictionary:
	for visitor in game.birds.visitors:
		if visitor["patch"] == patch and not bool(visitor["photographed"]):
			return visitor
	return {}


func _perched(visitor: Dictionary) -> bool:
	var creature: Creature = visitor["creature"]
	var patch: PatchWindow = visitor["patch"]
	return creature.host_window() == patch and creature.art_position() == patch.spot_point(String(visitor["spot"])) \
			and creature.sprite.anim == "idle"


func _perched_on(patch: PatchWindow) -> Variant:
	var visitor := _visitor_on(patch)
	return visitor if not visitor.is_empty() and _perched(visitor) else null
