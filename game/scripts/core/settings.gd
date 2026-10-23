class_name Settings
extends RefCounted

## The player's own choices (their day phases, an optional wrap-up time, how big the patches
## are drawn, which patches are out), saved apart from the world. Defaults come from balance.json.

const DEFAULT_PATH := "user://settings.json"

var path := DEFAULT_PATH
var data: Dictionary = {}


static func load_or_default(balance: Balance, file_path: String = DEFAULT_PATH,
		screen_scale: float = DisplayServer.screen_get_max_scale()) -> Settings:
	var settings := Settings.new()
	settings.path = file_path
	settings.data = {
		"day_phases": balance.data["day_phases"].duplicate(true),
		# The optional wrap-up time ("HH:MM"), the one time ever asked for; "" is off, the default (issue 198).
		"wrap_up": "",
		# The optional start-of-day time ("HH:MM", "" off, the default; issue 431): after it the van comes only when
		# you are at this Mac.
		"start_of_day": "",
		# The game day the van last brought you (issue 431), so a relaunch the same day sits you down quietly.
		"van_day": "",
		"art_scale": default_art_scale(balance.data["display"], screen_scale),
		"scale_version": 2,
		"roster": balance.data["player_defaults"]["roster"].duplicate(true),
		"on_top": false,
		"show_over_full_screen": bool(balance.data["display"].get("show_over_full_screen", false)),
		# Now and then a songbird flies out of the scene over the desktop (issue 120); on unless switched off.
		"desktop_flights": bool(balance.data["display"].get("desktop_flights", true)),
		# The living scene's size in percent of full, one of `display.scene_sizes`, shrunk into its corner
		# (issue 169; six steps since issue 222).
		"scene_size": int(balance.data["display"].get("scene_size", 100)),
		# The screen the scene sits on, by its position and size; {} is the main screen (issue 174).
		"scene_screen": {},
		# Which screen corner the scene holds (one of `display.scene_corners`, "bottom_right" the default; issue 424),
		# and how many points a bottom corner is lifted off the bottom of the usable rect (one of
		# `display.scene_lifts_pt`; issue 422; a top corner sits flush under the menu bar).
		"scene_corner": "bottom_right",
		"scene_lift": 0,
		# The picture drawn mirrored, in any corner (issue 424); off by default.
		"scene_mirror": false,
		# The mouse clear's size, points across (one of `scene.mouse_clear.diameters_pt`; issue 438).
		"mouse_clear_size": int(balance.data["scene"]["mouse_clear"]["diameter_pt"]),
		# Off by default (issue 169); the engine is SceneSound (issue 413).
		"sound": bool(balance.data["player_defaults"].get("sound", false)),
		# The VibeNature mark on saved photos, for the photo ticket (issue 169).
		"photo_mark": bool(balance.data["player_defaults"].get("photo_mark", true)),
		# Open at login (issue 199), on by default; the release app adds itself to Login Items (issue 196).
		"open_at_login": bool(balance.data["player_defaults"].get("open_at_login", true)),
		# The Login Items state last seen ("" never), so a change made in System Settings is followed (`LoginItem`).
		"login_item_seen": "",
		"avatar_id": String(balance.data["player_defaults"]["avatar_id"]),
		# The avatar's look and colours (issue 202, `AvatarLook`); an older file gets the nearest look to its avatar_id.
		"avatar": AvatarLook.defaults(balance.data["avatar_looks"]),
		# The van's paint (issue 279, `VanPaint`): ids in the van's meta.json `paint`; "" is the bench's default.
		"van": {"body": "", "accent": ""},
		# The elder who writes to you (issue 213): who (an id in the companion's elder/elders.json), the relationship,
		# and the name they sign with ("" is the default for that elder and relationship). The welcome
		# (issue 199) will set it; Config's Elder tab changes it.
		"elder": (balance.data["player_defaults"]["elder"] as Dictionary).duplicate(true),
		# Missing from a file means it was written before Config existed: that counts as
		# a first run once, so the player meets Config and picks an avatar.
		"first_run_done": false,
		"dismissed": [],
		# The game day the demo's morning card last showed (issue 268), so a relaunch the same day never shows it again.
		"demo_card_day": "",
	}
	if FileAccess.file_exists(file_path):
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(file_path))
		if parsed is Dictionary:
			_migrate(parsed)
			if not (parsed.get("avatar") is Dictionary and parsed["avatar"].has("look")) and parsed.has("avatar_id"):
				parsed["avatar"] = AvatarLook.from_avatar_id(String(parsed["avatar_id"]), balance.data["avatar_looks"])
			for key in parsed:
				if not settings.data.has(key):
					continue
				if settings.data[key] is Dictionary and parsed[key] is Dictionary:
					settings.data[key].merge(parsed[key], true)
				elif not (settings.data[key] is Dictionary):
					settings.data[key] = parsed[key]
	settings.data["avatar"] = AvatarLook.sanitize(settings.data["avatar"], balance.data["avatar_looks"])
	return settings


## Older settings named the avatar `avatar_preset` (`avatar_base`, or a preset such as
## `p2`). Keep what can be kept as an `avatar_id`; anything else falls back to the default.
static func _migrate(parsed: Dictionary) -> void:
	# The scene was "full" or "half" before its six sizes (issue 222).
	if parsed.get("scene_size") is String:
		parsed["scene_size"] = 50 if String(parsed["scene_size"]) == "half" else 100
	# Sizes before scale_version 2 were ×1, ×2 (the default) and ×3. Today's default is the old ×1
	# (the human, 2026-10-16), so old ×1 and ×2 become 1 and old ×3 becomes 2 ("large").
	if not parsed.has("scale_version") and parsed.has("art_scale"):
		parsed["art_scale"] = 2.0 if int(parsed["art_scale"]) >= 3 else 1.0
		parsed["scale_version"] = 2
	if parsed.has("avatar_id") or not parsed.has("avatar_preset"):
		return
	var old := String(parsed["avatar_preset"])
	var parts := old.split("_")
	if parts.size() >= 3 and parts[-1].begins_with("p"):
		parsed["avatar_id"] = old
	elif old.begins_with("p") and old.substr(1).is_valid_int():
		parsed["avatar_id"] = "a_medium_" + old


func save() -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(data, "  "))


func is_first_run() -> bool:
	return not bool(data["first_run_done"])


func mark_first_run_done() -> void:
	data["first_run_done"] = true
	save()


## Islands the player closed with their ✕; they stay closed until turned back on in
## Config's Islands tab. Their state is kept either way.
func is_dismissed(id: String) -> bool:
	return Array(data["dismissed"]).has(id)


func set_dismissed(id: String, dismissed: bool) -> void:
	var ids: Array = Array(data["dismissed"]).filter(func(other) -> bool: return String(other) != id)
	if dismissed:
		ids.append(id)
	data["dismissed"] = ids
	save()


## The player's art scale, kept to one of `allowed` (½ smaller, 1 default, 2 large).
func art_scale(allowed: Array) -> float:
	var wanted := float(data["art_scale"])
	for value in allowed:
		if is_equal_approx(float(value), wanted):
			return float(value)
	return float(allowed[allowed.size() / 2])


## A new player's size: `art_scale_retina` on a Retina screen (an illustrated island is about
## 500 art px, so ½ is one device pixel per art pixel), `art_scale` elsewhere.
static func default_art_scale(display: Dictionary, screen_scale: float) -> float:
	if screen_scale >= 2.0 and display.has("art_scale_retina"):
		return float(display["art_scale_retina"])
	return float(display["art_scale"])


## Device pixels per art pixel for an art scale, on the screen with the largest scale. Always a
## whole number: ½ on a Retina screen is one device pixel per art pixel; on a 1× screen it is 1.
static func device_scale(art: float, screen_scale: float = DisplayServer.screen_get_max_scale()) -> int:
	return maxi(1, roundi(art * maxi(1, roundi(screen_scale))))


## The living scene's size in percent: the step of `steps` nearest the saved value (an odd value
## in an edited file comes to the nearest step; never above the largest).
func scene_percent(steps: Array) -> int:
	return Settings.nearest_step(steps, float(data["scene_size"]) if data["scene_size"] is float or data["scene_size"] is int else 100.0)


static func nearest_step(steps: Array, wanted: float) -> int:
	var best := int(steps[-1]) if not steps.is_empty() else 100
	for step in steps:
		if absf(float(step) - wanted) < absf(float(best) - wanted):
			best = int(step)
	return best


## The step `delta` steps from `current` (−1 smaller, +1 larger), held at the ends.
static func step_from(steps: Array, current: int, delta: int) -> int:
	var sorted := steps.map(func(v) -> int: return int(v))
	sorted.sort()
	var i := sorted.find(Settings.nearest_step(sorted, float(current)))
	return int(sorted[clampi(i + delta, 0, sorted.size() - 1)])


func day_phases() -> DayPhases:
	return DayPhases.new(data["day_phases"])


## The wrap-up time in minutes of the day, or -1 when it is off (issue 198).
func wrap_up_minutes() -> int:
	return Settings.minutes_or_off(String(data.get("wrap_up", "")))


## The start-of-day time in minutes of the day, or -1 when it is off (issue 431).
func start_of_day_minutes() -> int:
	return Settings.minutes_or_off(String(data.get("start_of_day", "")))


static func minutes_or_off(at: String) -> int:
	if at == "" or not at.contains(":"):
		return -1
	return DayPhases.minutes(at)
