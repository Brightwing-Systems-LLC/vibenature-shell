class_name BirdVisits
extends Node

## Birds belong to no patch. They arrive through the day (§3.3) at any free perch on
## any patch (the Bird Spot is favoured), stay a minute or two, sometimes fly across
## the desktop to another patch, then leave. A bird is photographed once per visit.
## Visits are not saved: a bird that was here when the game closed simply left.

var game: Game
## [{"creature": Creature, "transit": TransitWindow, "species": String,
##   "patch": PatchWindow, "spot": String, "photographed": bool}]
var visitors: Array = []
var _occupied := {}
var _defs := {}
var _timer := Timer.new()


func setup(owner_game: Game) -> void:
	game = owner_game
	_timer.one_shot = true
	_timer.timeout.connect(_on_timer)
	add_child(_timer)
	game.signals.world_signal.connect(_on_world_signal)
	var first: Array = _tuning()["first_visit_delay_sec"]
	_timer.start(game.rng.randf_range(float(first[0]), float(first[1])))


func _tuning() -> Dictionary:
	return game.balance.data["birds"]


## The catalogue birds whose art the bench has delivered (`assets/fauna/<id>/meta.json`). With
## `birds.only_drawn_species`, only these visit, so no placeholder square lands on a perch.
func drawn_species() -> Array:
	var out: Array = []
	for id in game.content.species("birds"):
		if FileAccess.file_exists("res://assets/fauna/%s/meta.json" % id):
			out.append(String(id))
	return out


func _on_timer() -> void:
	if not game.is_night():
		spawn()
	var interval: Array = game.balance.data["bird_spawn_interval_min"]
	_timer.start(game.clock.real_seconds(game.rng.randf_range(float(interval[0]), float(interval[1])) * 60.0))


func _on_world_signal(kind: String, _source: String) -> void:
	if kind == "bird_roll" and not game.is_night() and game.rng.randf() < float(_tuning()["bird_roll_chance"]):
		spawn()


## A visit now, if there is room: a species by rarity, or `forced` (the debug panel).
func spawn(forced: String = "") -> bool:
	if visitors.size() >= int(_tuning()["max_visitors"]) and forced == "":
		return false
	var target := _pick_perch(null)
	if target.is_empty():
		return false
	var species := forced
	if species == "":
		species = game.content.pick("birds", _tuning()["rarity_weights"], game.rng, game.clock.month(), game.rare_multiplier(),
				drawn_species() if bool(_tuning().get("only_drawn_species", false)) else [])
	if species == "":
		return false
	var def := def_for(species)
	var flight: Dictionary = game.balance.data["flight"]
	var transit_layer := String(flight["transit_layer"])
	var patch = target["patch"]
	if not def.has_layer(transit_layer):
		transit_layer = String(def.layers.keys()[0])
	var transit := TransitWindow.new()
	transit.setup(def.layers[transit_layer]["frame_size"], game.scale_px)
	transit.position = patch.position
	add_child(transit)
	WindowChrome.draw_on_demand(transit)
	var creature := Creature.new(def, flight, transit)
	add_child(creature)
	var visitor := {
		"creature": creature, "transit": transit, "species": species,
		"patch": patch, "spot": String(target["spot"]), "photographed": false,
	}
	visitors.append(visitor)
	_visit(visitor)
	return true


func _visit(visitor: Dictionary) -> void:
	var creature: Creature = visitor["creature"]
	var flight: Dictionary = game.balance.data["flight"]
	var patch = visitor["patch"]
	var spot := String(visitor["spot"])
	_claim(patch, spot)
	var arrival_point: Vector2 = creature.top_point(patch, patch.spot_point(spot).x, true)
	await creature.fly_in(patch, spot, arrival_point)
	print("VibeNature: a %s visits %s" % [visitor["species"], _place_name(patch)])
	var stay: Array = game.balance.data["bird_stay_sec"]
	while true:
		await get_tree().create_timer(game.clock.real_seconds(game.rng.randf_range(float(stay[0]), float(stay[1])))).timeout
		if String(flight["crossing"]) != "window" or game.rng.randf() >= float(_tuning()["hop_chance"]):
			break
		var hop := _pick_perch(patch)
		if hop.is_empty():
			break
		var next_patch = hop["patch"]
		var next_spot := String(hop["spot"])
		_claim(next_patch, next_spot)
		var toward := 1.0 if next_patch.position.x > patch.position.x else -1.0
		var exit := creature.top_point(patch, patch.spot_point(spot).x + toward * float(flight["exit_lean_px"]), false)
		var entry := creature.top_point(next_patch, next_patch.spot_point(next_spot).x, false)
		await creature.fly_out(patch, exit)
		_release(patch, spot)
		await creature.cross_by_window(patch, exit, next_patch, entry)
		patch = next_patch
		spot = next_spot
		visitor["patch"] = patch
		visitor["spot"] = spot
		await creature.fly_in(patch, spot, entry)
	await creature.fly_out(patch, creature.top_point(patch, patch.spot_point(spot).x, true))
	_release(patch, spot)
	_remove(visitor)


## The visitor drawn under `art_point` in `patch`, or {}.
func find_at(patch: Window, art_point: Vector2) -> Dictionary:
	for visitor in visitors:
		var creature: Creature = visitor["creature"]
		if creature.host_window() == patch and creature.hit(art_point):
			return visitor
	return {}


## A polaroid of this visit, or {} if it was already taken.
func photograph(visitor: Dictionary) -> Dictionary:
	if visitor.is_empty() or bool(visitor["photographed"]):
		return {}
	visitor["photographed"] = true
	var species := String(visitor["species"])
	var rarity := game.content.rarity_of("birds", species)
	return {
		"kind": "polaroid", "id": species, "rarity": rarity,
		"value": int(game.balance.data["polaroid_payout"].get(rarity, 0)),
	}


## A free perch, weighted by each patch's mechanic: {"patch", "spot"} or {}.
func _pick_perch(exclude: Window) -> Dictionary:
	var options: Array = []
	var total := 0.0
	for patch in game.patches:
		# A dismissed island is hidden; no bird lands where the player cannot see it.
		if patch == exclude or not patch.visible:
			continue
		var weight := patch.mechanic.perch_weight() if patch.mechanic != null else float(_tuning()["patch_weight"]["default"])
		for spot in patch.def.spots_of_kind("perch"):
			if not _occupied.has(_key(patch, spot)):
				options.append({"patch": patch, "spot": spot, "weight": weight})
				total += weight
	if options.is_empty() or total <= 0.0:
		return {}
	var roll := game.rng.randf() * total
	for option in options:
		roll -= float(option["weight"])
		if roll <= 0.0:
			return option
	return options[-1]


func _place_name(patch: Window) -> String:
	return patch.def.id


func _key(patch: Window, spot: String) -> String:
	return "%s/%s" % [_place_name(patch), spot]


func _claim(patch: Window, spot: String) -> void:
	_occupied[_key(patch, spot)] = true


func _release(patch: Window, spot: String) -> void:
	_occupied.erase(_key(patch, spot))


func _remove(visitor: Dictionary) -> void:
	visitors.erase(visitor)
	var creature: Creature = visitor["creature"]
	creature.vanish()
	creature.sprite.queue_free()
	creature.queue_free()
	var transit: TransitWindow = visitor["transit"]
	transit.queue_free()


func def_for(species: String) -> CreatureDef:
	if not _defs.has(species):
		_defs[species] = CreatureDef.load_creature("fauna", species, game.balance.data["placeholders"]["small_creature"],
				game.idle_fps_max, game.content.color_of("birds", species))
	return _defs[species]
