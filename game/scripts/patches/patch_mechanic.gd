class_name PatchMechanic
extends Node

## A patch's rules. A mechanic is a child of its PatchWindow and draws into it; the
## Game routes tool uses and bare clicks here. Subclasses override what they need.
##
## An island pack's `mechanic` script extends this (contract §5). What a pack's code may use
## is this class, the `patch` and `game` handles it is given, and the game's own classes
## (CreatureDef, CreatureSprite, AssetLibrary, …). It gets world signals by kind only, never
## their source or anything an agent said. By convention it never touches files, the network
## or the OS: GDScript cannot enforce that, so the signature on a pack is the boundary.

var patch: PatchWindow
var game: Game
## The island's own numbers: its pack's balance.json ({} for an island that is not a pack).
var tuning: Dictionary = {}


func setup(target: PatchWindow, owner_game: Game) -> void:
	patch = target
	game = owner_game
	_setup_mechanic()


func _setup_mechanic() -> void:
	pass


func kind() -> String:
	return ""


## The player clicked with a tool. Returns true if the tool did something here.
func use_tool(_tool_id: String, _art_point: Vector2) -> bool:
	return false


## The tool in hand on this island changed ("" when the avatar leaves).
func on_tool_selected(_tool_id: String) -> void:
	pass


## A click with no tool (or a tool that did nothing). Returns true if handled.
func on_click(_art_point: Vector2) -> bool:
	return false


func on_world_signal(_kind: String) -> void:
	pass


func on_rain() -> void:
	pass


func on_new_day() -> void:
	pass


## While true, the whole window takes clicks (a mini-game in progress).
func wants_all_clicks() -> bool:
	return false


## Flowers in bloom here now (the beehive works faster with more of them).
func count_blooming(_now: float) -> int:
	return 0


## How strongly visiting birds favour this patch's perches.
func perch_weight() -> float:
	return float(game.balance.data["birds"]["patch_weight"]["default"])


## Where the avatar stands to use `tool_id` at `art_point` (window art pixels). By default
## just beside the target, in the front band.
func stand_point(_tool_id: String, art_point: Vector2) -> Vector2:
	return (art_point + Vector2(AssetLibrary.vec2i(game.balance.data["avatar"]["stand_offset_px"]))).round()


## True if this island poses the avatar itself for `tool_id` (`Avatar.show_doing`), in place
## of the usual action then idle.
func animates_avatar(_tool_id: String) -> bool:
	return false


## True if the avatar, done with `tool_id` at `art_point`, stands facing into the island
## (its back view) rather than out at the player.
func faces_into_island(_tool_id: String, _art_point: Vector2) -> bool:
	return false


## The avatar came to this island / left it.
func on_avatar_arrived() -> void:
	pass


func on_avatar_left() -> void:
	pass


## The game clock jumped (the debug panel): redraw and reschedule for the new time.
func on_time_jump() -> void:
	pass


## Buttons for the debug panel: [{"label": String, "call": Callable}, …].
func debug_actions() -> Array:
	return []


func save_state() -> Dictionary:
	return {}


func load_state(_state: Dictionary) -> void:
	pass


## The key of `points` (name -> art point) nearest `art_point`, within `radius`, or "".
func nearest(points: Dictionary, art_point: Vector2, radius: float) -> String:
	var best := ""
	var best_distance := radius
	for spot_name in points:
		var distance := art_point.distance_to(points[spot_name])
		if distance <= best_distance:
			best = spot_name
			best_distance = distance
	return best
