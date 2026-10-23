class_name SceneScreens
extends RefCounted

## The connected screens, for putting the living scene on one of them
## (Skypatch issue 174). Pure: a screen is a Dictionary
## {rect: Rect2i, usable: Rect2i, primary: bool, scale: float}; tests pass fakes.
##
## A saved screen is its key, {pos, size} of its whole rect, steadier than its index (which macOS
## reorders when screens come and go). A key that matches no screen exactly falls back to the one
## screen of the same size, else to the main screen.


## The real screens, from the display server.
static func from_display() -> Array:
	var screens: Array = []
	var primary := DisplayServer.get_primary_screen()
	for i in DisplayServer.get_screen_count():
		screens.append({
			"rect": Rect2i(DisplayServer.screen_get_position(i), DisplayServer.screen_get_size(i)),
			"usable": DisplayServer.screen_get_usable_rect(i),
			"primary": i == primary,
			"scale": DisplayServer.screen_get_scale(i),
		})
	return screens


static func key(screen: Dictionary) -> Dictionary:
	var r: Rect2i = screen["rect"]
	return {"pos": [r.position.x, r.position.y], "size": [r.size.x, r.size.y]}


static func primary(screens: Array) -> int:
	for i in screens.size():
		if bool(screens[i].get("primary", false)):
			return i
	return 0


## The screen a saved key names, or -1 if it is gone.
static func find(screens: Array, saved: Dictionary) -> int:
	if not saved.has("pos") or not saved.has("size"):
		return -1
	var same_size: Array[int] = []
	for i in screens.size():
		var k := key(screens[i])
		if _same(k["size"], saved["size"]):
			if _same(k["pos"], saved["pos"]):
				return i
			same_size.append(i)
	return same_size[0] if same_size.size() == 1 else -1


## The screen for a saved key: that screen if it is still here, else the main screen.
static func resolve(screens: Array, saved: Dictionary) -> int:
	var found := find(screens, saved)
	return found if found >= 0 else primary(screens)


## Flush to a corner of a usable rect (the Dock and menu bar left alone): the bottom-right, or the left
## (`left`, issue 422), or the top (`top`, issue 424: flush under the menu bar, never lifted). A bottom corner
## is `lift` units up from the rect's bottom (a lift never takes it above the rect's top).
static func corner(usable: Rect2i, own: Vector2i, left: bool = false, lift: int = 0, top: bool = false) -> Vector2i:
	var x := usable.position.x if left else usable.end.x - own.x
	if top:
		return Vector2i(x, usable.position.y)
	var y := usable.end.y - own.y
	return Vector2i(x, maxi(mini(y, usable.position.y), y - maxi(lift, 0)))


## The four corners (issue 424); anything else saved reads as the bottom-right, the default.
const CORNERS := ["bottom_right", "bottom_left", "top_left", "top_right"]


static func corner_name(raw: Variant) -> String:
	return String(raw) if CORNERS.has(String(raw)) else "bottom_right"


## Whether a corner setting is a left one.
static func is_left(corner_name_raw: Variant) -> bool:
	return corner_name(corner_name_raw).ends_with("left")


## Whether a corner setting is a top one.
static func is_top(corner_name_raw: Variant) -> bool:
	return corner_name(corner_name_raw).begins_with("top")


## What changes when screens come and go (for noticing a plug or unplug).
static func signature(screens: Array) -> String:
	var parts: PackedStringArray = []
	for screen in screens:
		parts.append("%s|%s|%s" % [screen["rect"], screen["usable"], screen.get("primary", false)])
	return ";".join(parts)


## Each screen's box in a picker of `area`, laid out as the screens are arranged (positions and
## relative sizes), scaled down to fit and centred, each inset by `gap` / 2 so neighbours do not touch.
static func layout(screens: Array, area: Vector2, gap: float = 0.0) -> Array[Rect2]:
	var boxes: Array[Rect2] = []
	if screens.is_empty() or area.x <= 0.0 or area.y <= 0.0:
		return boxes
	var bounds := Rect2(Rect2i(screens[0]["rect"]))
	for screen in screens:
		bounds = bounds.merge(Rect2(Rect2i(screen["rect"])))
	if bounds.size.x <= 0.0 or bounds.size.y <= 0.0:
		return boxes
	var k := minf(area.x / bounds.size.x, area.y / bounds.size.y)
	var offset := (area - bounds.size * k) / 2.0
	for screen in screens:
		var r := Rect2(Rect2i(screen["rect"]))
		var box := Rect2(offset + (r.position - bounds.position) * k, r.size * k)
		boxes.append(box.grow(-gap / 2.0))
	return boxes


static func _same(a: Variant, b: Variant) -> bool:
	return a is Array and b is Array and a.size() == 2 and b.size() == 2 \
			and int(a[0]) == int(b[0]) and int(a[1]) == int(b[1])
