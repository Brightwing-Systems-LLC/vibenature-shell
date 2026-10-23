class_name PhotoAlbum
extends RefCounted

## The person's photos of the scene (Skypatch issue 177):
## a folder (`user://album`) with one PNG per photo and a small JSON beside it. Photos live here
## only; export is how a copy leaves the app (nothing goes to ~/Pictures on its own).
##
## The JSON holds only what the scene showed: the local date and time, a word for the weather and
## the species in view (ids). Privacy is a construction rule: `add` keeps those keys and drops
## everything else, so nothing from an agent or the person's work can reach the album.
##
## The photo ticket (Skypatch issue 176) calls
## `album.add(image, {"unix": clock.now(), "weather": PhotoAlbum.weather_word(beh.weather(), balance["scene_book"]["weather_words"]),
## "species": beh.present().keys()})`.

signal changed

const DEFAULT_DIR := "user://album"
const ENV := "VIBENATURE_ALBUM"
const WEATHER_WORDS: Array[String] = ["clear", "sunny", "cloudy", "overcast", "rain", "fog", "mist", "wind", "night", "dawn", "dusk"]

var dir := DEFAULT_DIR


func _init(album_dir: String = DEFAULT_DIR) -> void:
	dir = album_dir


## The player's album: its env override, else user://album; a snapshot run keeps its own.
static func default_dir() -> String:
	if Snapshot.on():
		return Snapshot.user_dir().path_join("album")
	var value := OS.get_environment(ENV)
	return value if value != "" else DEFAULT_DIR


## Saves `image` with its metadata; returns the photo's id ("" if it could not be written).
## `meta`: `unix` (when it was taken; else now), `weather` (one of WEATHER_WORDS), `species`
## (species ids in view). Optional `date` ("YYYY-MM-DD") and `time` ("HH:MM") are the local ones;
## without them they come from `unix` and the system's time zone. Any other key is dropped.
func add(image: Image, meta: Dictionary) -> String:
	if image == null or image.is_empty():
		return ""
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	var unix := float(meta.get("unix", Time.get_unix_time_from_system()))
	var local := PhotoAlbum.local_of(unix)
	var clean := {
		"unix": unix,
		"date": String(meta.get("date", "%04d-%02d-%02d" % [local["year"], local["month"], local["day"]])),
		"time": String(meta.get("time", "%02d:%02d" % [local["hour"], local["minute"]])),
		"weather": PhotoAlbum.clean_weather(meta.get("weather", "")),
		"species": PhotoAlbum.clean_species(meta.get("species", [])),
	}
	var stem := "%s-%s" % [clean["date"].replace("-", ""), clean["time"].replace(":", "")]
	var id := stem
	var n := 2
	while FileAccess.file_exists(_file(id, "png")):
		id = "%s-%d" % [stem, n]
		n += 1
	if image.save_png(_file(id, "png")) != OK:
		return ""
	var file := FileAccess.open(_file(id, "json"), FileAccess.WRITE)
	if file == null:
		DirAccess.remove_absolute(_file(id, "png"))
		return ""
	file.store_string(JSON.stringify(clean, "  "))
	file.close()
	changed.emit()
	return id


## Every photo, newest first: {id, png (absolute path), unix, date, time, weather, species}.
func photos() -> Array:
	var out: Array = []
	var d := DirAccess.open(ProjectSettings.globalize_path(dir))
	if d == null:
		return out
	for name in d.get_files():
		if not name.ends_with(".png"):
			continue
		var id := name.get_basename()
		var meta := {}
		if FileAccess.file_exists(_file(id, "json")):
			var parsed = JSON.parse_string(FileAccess.get_file_as_string(_file(id, "json")))
			if parsed is Dictionary:
				meta = parsed
		out.append({"id": id, "png": _file(id, "png"), "unix": float(meta.get("unix", 0.0)),
				"date": String(meta.get("date", "")), "time": String(meta.get("time", "")),
				"weather": PhotoAlbum.clean_weather(meta.get("weather", "")),
				"species": PhotoAlbum.clean_species(meta.get("species", []))})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return a["unix"] > b["unix"] if a["unix"] != b["unix"] else String(a["id"]) > String(b["id"]))
	return out


func image(id: String) -> Image:
	if not FileAccess.file_exists(_file(id, "png")):
		return null
	return Image.load_from_file(_file(id, "png"))


## The photo's PNG as an absolute path (for reveal in Finder).
func path_of(id: String) -> String:
	return _file(id, "png")


## Deletes the photo and its metadata.
func remove(id: String) -> bool:
	if not FileAccess.file_exists(_file(id, "png")):
		return false
	DirAccess.remove_absolute(_file(id, "png"))
	DirAccess.remove_absolute(_file(id, "json"))
	changed.emit()
	return true


## Copies the photo's PNG to `to` (a path the person chose); ".png" is added if missing.
func export_to(id: String, to: String) -> bool:
	if not FileAccess.file_exists(_file(id, "png")) or to == "":
		return false
	if to.get_extension().to_lower() != "png":
		to += ".png"
	return DirAccess.copy_absolute(_file(id, "png"), to) == OK


## A name for an exported copy: "VibeNature 2026-10-18 14.05.png".
static func export_name(photo: Dictionary) -> String:
	return "VibeNature %s %s.png" % [photo.get("date", ""), String(photo.get("time", "")).replace(":", ".")]


## A word for the scene's weather (`SceneBehaviour.weather()`), for a photo's metadata; the
## thresholds are `scene_book.weather_words` in balance.json.
static func weather_word(w: Dictionary, at: Dictionary) -> String:
	if float(w.get("daylight", 1.0)) < float(at["night_below_daylight"]):
		return "night"
	if float(w.get("rain", 0.0)) > float(at["rain_above"]):
		return "rain"
	if float(w.get("fog", 0.0)) > float(at["fog_above"]):
		return "fog"
	if float(w.get("wind", 0.0)) > float(at["wind_above"]):
		return "wind"
	var sun := float(w.get("sunshine", 1.0))
	if sun > float(at["sunny_above"]):
		return "sunny"
	return "cloudy" if sun > float(at["cloudy_above"]) else "overcast"


static func clean_weather(value) -> String:
	var word := String(value) if value is String else ""
	return word if WEATHER_WORDS.has(word) else ""


## Species ids only: short lowercase words, never free text.
static func clean_species(value) -> Array:
	var out: Array = []
	if not value is Array:
		return out
	for s in value:
		var id := String(s) if s is String else ""
		if id.length() <= 40 and id == id.to_lower() and id.is_valid_ascii_identifier() and not out.has(id):
			out.append(id)
	return out


static func local_of(unix: float) -> Dictionary:
	var bias := int(Time.get_time_zone_from_system().get("bias", 0))
	return Time.get_datetime_dict_from_unix_time(int(unix) + bias * 60)


func _file(id: String, ext: String) -> String:
	return ProjectSettings.globalize_path(dir.path_join("%s.%s" % [id, ext]))
