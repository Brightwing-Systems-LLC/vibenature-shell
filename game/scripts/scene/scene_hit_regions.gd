class_name SceneHitRegions
extends RefCounted

## The parts of the living scene's window that catch the mouse (issue 169). Everything else is
## click-through. Regions are named rects in window units, so later controls (the monocular on
## right-click) add their own without touching the strip's. With none, the whole window passes
## clicks through.
##
## A window has one passthrough polygon, so several rects are joined into one: each rect is walked
## round and joined to the first by a zero-width corridor, which encloses no area. Regions must not
## overlap (the polygon is tested even-odd, so an overlap would cancel out), except that a region
## wholly inside another adds nothing and is left out: the viewfinder (issue 176) covers the whole
## scene while the strip keeps its own region underneath.

var regions := {}


func set_region(region_name: String, rect: Rect2) -> void:
	regions[region_name] = rect


func clear(region_name: String) -> void:
	regions.erase(region_name)


func is_empty() -> bool:
	return regions.is_empty()


func contains(point: Vector2) -> bool:
	for region_name in regions:
		if (regions[region_name] as Rect2).has_point(point):
			return true
	return false


## The regions as one polygon, in window units (empty when there are none).
func polygon() -> PackedVector2Array:
	var out := PackedVector2Array()
	var names: Array = regions.keys().filter(func(n) -> bool: return not _inside_another(n))
	names.sort()
	var anchor := Vector2.ZERO
	for i in names.size():
		var r: Rect2 = regions[names[i]]
		var corners := [r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]
		if i == 0:
			anchor = r.position
			out.append_array(PackedVector2Array(corners))
			continue
		out.append(anchor)
		out.append_array(PackedVector2Array(corners))
		out.append(r.position)
	return out


func _inside_another(region_name) -> bool:
	var r: Rect2 = regions[region_name]
	for other in regions:
		if other != region_name and (regions[other] as Rect2).encloses(r) and not (r.encloses(regions[other]) and String(other) > String(region_name)):
			return true
	return false


## Puts the regions on `window`: only they take the mouse; with none, nothing does.
func apply(window: Window) -> void:
	if regions.is_empty():
		window.mouse_passthrough_polygon = PackedVector2Array()
		window.mouse_passthrough = true
		return
	window.mouse_passthrough_polygon = polygon()
	window.mouse_passthrough = false
