class_name CalmLabBeacon
extends RefCounted

## Tells the a local calm study whether the scene is on screen: `~/.calmlab/scene.json` is
## rewritten as {"running": true, "updated_at": <epoch>, "source": "vibe-nature"} at least every
## `every_sec` while the scene is visible, and with "running": false when it is hidden or the game
## quits. Nothing else goes in it (no work content, no events). Never used in snapshot mode.

const SOURCE := "vibe-nature"

var path := ""
var every_sec := 15.0
var _last_write := -INF
var _last_running := false
var _stopped := false


func _init(file_path: String, interval_sec: float) -> void:
	path = file_path
	every_sec = interval_sec


## The default file: ~/.calmlab/scene.json.
static func default_path() -> String:
	var home := OS.get_environment("HOME")
	return home.path_join(".calmlab").path_join("scene.json") if home != "" else ""


static func payload(running: bool, unix: float) -> Dictionary:
	return {"running": running, "updated_at": int(unix), "source": SOURCE}


## Called every scene step: writes when visibility changed, or when the last write is old.
func tick(t: float, running: bool, force: bool = false) -> void:
	if _stopped or path == "":
		return
	if force or running != _last_running or t - _last_write >= every_sec:
		_write(running)
		_last_write = t
		_last_running = running


func stop() -> void:
	if _stopped or path == "":
		return
	_write(false)
	_stopped = true


func _write(running: bool) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var tmp := path + ".tmp"
	var file := FileAccess.open(tmp, FileAccess.WRITE)
	if file == null:
		return
	file.store_string(JSON.stringify(CalmLabBeacon.payload(running, Time.get_unix_time_from_system())))
	file.close()
	DirAccess.rename_absolute(tmp, path)
