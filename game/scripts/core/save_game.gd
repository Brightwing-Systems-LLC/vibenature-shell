class_name SaveGame
extends RefCounted

## The world on disk: the economy, journal, weather, each patch's state and where
## the windows are. Never anything from an agent event (contract §2 rule 4).
## Written to a temporary file and renamed, so a crash mid-write keeps the old save.

const DEFAULT_PATH := "user://save.json"
const VERSION := 1

var path := DEFAULT_PATH


func _init(file_path: String = DEFAULT_PATH) -> void:
	path = file_path


func read() -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	if parsed is Dictionary and int(parsed.get("version", 0)) <= VERSION:
		return parsed
	push_warning("Save unreadable or from a newer version, starting fresh: %s" % path)
	return {}


func write(data: Dictionary) -> bool:
	var out := data.duplicate(true)
	out["version"] = VERSION
	var temp := path + ".tmp"
	var file := FileAccess.open(temp, FileAccess.WRITE)
	if file == null:
		push_warning("Could not write the save: %s" % temp)
		return false
	file.store_string(JSON.stringify(out, "  "))
	file.close()
	return DirAccess.rename_absolute(ProjectSettings.globalize_path(temp), ProjectSettings.globalize_path(path)) == OK
