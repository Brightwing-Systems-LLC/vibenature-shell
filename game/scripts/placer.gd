class_name Placer
extends RefCounted

## Random homes for windows across every screen, so the day's patches turn up in
## different places: not overlapping each other or anything already placed, kept
## inside each screen's usable area. Callers pass each island's grown footprint, so islands
## stay apart at any size (issue 66). Also: which saved places to keep, and the smallest
## nudge that clears an overlap. Pure, for tests.


## Positions (top-left) for windows of `sizes`, or Vector2i(-1, -1) for any that did
## not fit after `attempts` tries (the caller lays those out its own way).
static func place(sizes: Array, screens: Array, taken: Array, margin: int, rng: RandomNumberGenerator, attempts: int = 200) -> Array:
	var placed: Array = []
	var occupied: Array = taken.duplicate()
	var total_area := 0.0
	for screen: Rect2i in screens:
		total_area += float(screen.get_area())
	for size: Vector2i in sizes:
		var spot := Vector2i(-1, -1)
		# No screens (a headless run): nothing fits; the caller lines everything up.
		for attempt in attempts if not screens.is_empty() else 0:
			var screen := _pick_screen(screens, total_area, rng)
			var room := screen.size - size - Vector2i(2 * margin, 2 * margin)
			if room.x < 0 or room.y < 0:
				continue
			var at := screen.position + Vector2i(margin, margin) + Vector2i(rng.randi_range(0, room.x), rng.randi_range(0, room.y))
			var rect := Rect2i(at, size)
			var clear := true
			for other: Rect2i in occupied:
				if other.grow(margin).intersects(rect):
					clear = false
					break
			if clear:
				spot = at
				occupied.append(rect)
				break
		placed.append(spot)
	return placed


## Bigger screens get more patches.
static func _pick_screen(screens: Array, total_area: float, rng: RandomNumberGenerator) -> Rect2i:
	var roll := rng.randf() * total_area
	for screen: Rect2i in screens:
		roll -= float(screen.get_area())
		if roll <= 0.0:
			return screen
	return screens[-1]


## The rect a window of `rect` takes once grown by `factor` about its bottom centre (as
## `PatchWindow.rescale` grows the island the avatar is on).
static func grown(rect: Rect2i, factor: float) -> Rect2i:
	var size := Vector2i((Vector2(rect.size) * factor).round())
	var bottom_centre := Vector2(rect.position) + Vector2(rect.size.x / 2.0, rect.size.y)
	return Rect2i(Vector2i((bottom_centre - Vector2(size.x / 2.0, size.y)).round()), size)


## Home's default top-left: the bottom-left corner of `usable`, `margin` in from each edge
## (issue 89; the bottom-right is the living scene's, contract §7).
## With the scene in the bottom-left (`right`, issue 422) home takes the bottom-right instead.
static func home_corner(usable: Rect2i, size: Vector2i, margin: int, right: bool = false) -> Vector2i:
	if right:
		return usable.end - Vector2i(margin, margin) - size
	return Vector2i(usable.position.x + margin, usable.end.y - margin - size.y)


## What the living scene keeps in the bottom-right corner of `usable` (the bottom-left with `left`,
## issue 422): `size`, `margin` in from each edge, clipped to `usable`. Islands are placed clear of it.
static func scene_corner(usable: Rect2i, size: Vector2i, margin: int, left: bool = false) -> Rect2i:
	if left:
		return Rect2i(Vector2i(usable.position.x + margin, usable.end.y - margin - size.y), size).intersection(usable)
	return Rect2i(usable.end - Vector2i(margin, margin) - size, size).intersection(usable)


## Where a window of `size` sits so that it grows into `footprint` (same bottom centre).
static func inside(footprint: Rect2i, size: Vector2i) -> Vector2i:
	var bottom_centre := Vector2(footprint.position) + Vector2(footprint.size.x / 2.0, footprint.size.y)
	return Vector2i((bottom_centre - Vector2(size.x / 2.0, size.y)).round())


## Whether a window saved at `rect` (`grown` at its largest) goes back there: where the player
## dragged it, if its centre is still on a screen, whatever it overlaps; where the game put it,
## only if `grown` still `fits`. Otherwise it is placed afresh.
static func keep_saved(rect: Rect2i, grown_rect: Rect2i, by_player: bool, screens: Array, taken: Array, margin: int) -> bool:
	if by_player:
		for screen: Rect2i in screens:
			if screen.has_point(rect.get_center()):
				return true
		return false
	return fits(grown_rect, screens, taken, margin)


## True when `rect` lies wholly on one of `screens` and `margin` clear of every rect in `taken`.
static func fits(rect: Rect2i, screens: Array, taken: Array, margin: int) -> bool:
	var on_screen := false
	for screen: Rect2i in screens:
		if screen.encloses(rect):
			on_screen = true
			break
	if not on_screen:
		return false
	for other: Rect2i in taken:
		if other.grow(margin).intersects(rect):
			return false
	return true


## The nearest top-left for `rect` (by distance moved) that `fits`: beside one of `taken`
## on any side, or pushed back onto a screen; Vector2i(-1, -1) if none does.
static func nudge(rect: Rect2i, screens: Array, taken: Array, margin: int) -> Vector2i:
	var xs: Array[int] = [rect.position.x]
	var ys: Array[int] = [rect.position.y]
	for other: Rect2i in taken:
		xs.append(other.position.x - margin - rect.size.x)
		xs.append(other.end.x + margin)
		ys.append(other.position.y - margin - rect.size.y)
		ys.append(other.end.y + margin)
	for screen: Rect2i in screens:
		xs.append(screen.position.x)
		xs.append(screen.end.x - rect.size.x)
		ys.append(screen.position.y)
		ys.append(screen.end.y - rect.size.y)
	var best := Vector2i(-1, -1)
	var best_distance := INF
	for x in xs:
		for y in ys:
			var at := Vector2i(x, y)
			var distance := Vector2(at - rect.position).length()
			if distance < best_distance and fits(Rect2i(at, rect.size), screens, taken, margin):
				best = at
				best_distance = distance
	return best
