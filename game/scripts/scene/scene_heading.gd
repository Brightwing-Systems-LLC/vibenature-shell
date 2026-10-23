class_name SceneHeading
extends RefCounted

## Which way a creature is seen from its heading
## (issue 237 part 1): a bird or fish moving
## mostly across the picture is seen side-on; turning into the scene it is seen three-quarter from
## behind, then from behind; coming out of the depth, three-quarter from the front, then head-on.
##
## The heading is the angle between its way and the picture plane, from its velocity in metres
## (across, away; away positive). The velocity is smoothed, a view changes only one step at a time
## (side, 3q, straight; toward and away only through side), only once the angle is a margin past
## the line between two views, and never sooner than `hold_sec` after the last change, so a view
## never flickers or pops for a frame. Below `min_speed_mps` it keeps the view it has (a fish
## hanging nose-on stays nose-on). Tuning: `behaviour.depth_views` in balance.json.

const ORDER := ["away", "3q_away", "side", "3q_toward", "toward"]

var view := "side"
var tuning: Dictionary = {}
var _v := Vector2.ZERO
var _since := 100.0


func _init(t: Dictionary = {}) -> void:
	tuning = t


func reset(to: String = "side") -> void:
	view = to
	_v = Vector2.ZERO
	_since = 100.0


## Advances `dt` seconds moving `across_mps` (either way) and `away_mps` (into the scene positive).
func update(dt: float, across_mps: float, away_mps: float) -> String:
	_since += dt
	var k := clampf(dt / maxf(float(tuning.get("smooth_sec", 0.35)), 0.001), 0.0, 1.0)
	_v = _v.lerp(Vector2(absf(across_mps), away_mps), k)
	if _v.length() < float(tuning.get("min_speed_mps", 0.02)) or _since < float(tuning.get("hold_sec", 0.4)):
		return view
	var want := view_for(angle_deg(_v.x, _v.y), view, tuning)
	if want != view:
		# One step at a time toward the view wanted.
		var i := ORDER.find(view)
		var j := ORDER.find(want)
		view = ORDER[i + signi(j - i)]
		_since = 0.0
	return view


## Degrees off the picture plane: 0 straight across, 90 straight away, -90 straight at the viewer.
static func angle_deg(across_mps: float, away_mps: float) -> float:
	return rad_to_deg(atan2(away_mps, absf(across_mps)))


## The view for `angle` coming from `now`: it must be `hysteresis_deg` past a line to cross it.
static func view_for(angle: float, now: String, t: Dictionary) -> String:
	var q := float(t.get("three_q_deg", 30.0))
	var s := float(t.get("straight_deg", 62.0))
	var h := float(t.get("hysteresis_deg", 6.0))
	var raw := _band(angle, q, s)
	if raw == now:
		return now
	# Only change when the angle is clearly in the new band, not on its edge.
	var lo := _band(angle - h, q, s)
	var hi := _band(angle + h, q, s)
	return raw if lo == raw and hi == raw else now


static func _band(a: float, q: float, s: float) -> String:
	if a >= s:
		return "away"
	if a >= q:
		return "3q_away"
	if a > -q:
		return "side"
	if a > -s:
		return "3q_toward"
	return "toward"


## Whether `v` is one of the depth views (not side).
static func is_depth(v: String) -> bool:
	return v != "side" and ORDER.has(v)


static func is_straight(v: String) -> bool:
	return v == "toward" or v == "away"
