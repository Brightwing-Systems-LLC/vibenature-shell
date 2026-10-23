class_name DataHome
extends RefCounted

## Moves the player's data from the Skypatch names to the VibeNature ones on launch
## (Skypatch issue 211). This runs once and never
## overwrites anything.
## - `~/.skypatch` (the hook's salt and bin, and the bench store on a dev machine) moves to
##   `~/.vibenature` in one rename. The old place gets a folder with a note and one link per
##   moved entry, so an old hook entry keeps working until `just hook-install` runs again.
##   game/tools/data_home.py does the same for the tools.
## - Godot's user folder follows `config/name`. Each entry of the old `app_userdata/Skypatch`
##   (settings, save, album, installed islands) moves into `app_userdata/VibeNature` unless the
##   new folder already has an entry by that name. A note is left in the old folder.
## Every path is a parameter, so tests run it on temp folders only.

const NEW_HOME := ".vibenature"
const OLD_HOME := ".skypatch"
const OLD_USER_DIR := "Skypatch"
const NOTE := "MOVED-TO-VIBENATURE.txt"


## Both moves for this player: HOME and Godot's user folder. Returns what happened, for the log.
static func migrate_default() -> PackedStringArray:
	var done := PackedStringArray()
	var home := OS.get_environment("HOME")
	if home != "":
		var moved := migrate_home(home)
		if moved != "":
			done.append(moved)
	var user_dir := OS.get_user_data_dir()
	done.append_array(migrate_user_dir(user_dir.get_base_dir().path_join(OLD_USER_DIR), user_dir))
	return done


## Moves <home>/.skypatch to <home>/.vibenature. Returns "" when there is nothing to do.
static func migrate_home(home: String) -> String:
	var old := home.path_join(OLD_HOME)
	var new := home.path_join(NEW_HOME)
	if DirAccess.dir_exists_absolute(new) or FileAccess.file_exists(new) or _is_link(home, NEW_HOME):
		return ""
	if not DirAccess.dir_exists_absolute(old) or _is_link(home, OLD_HOME):
		return ""
	if DirAccess.rename_absolute(old, new) != OK:
		push_warning("VibeNature: could not move %s to %s" % [old, new])
		return ""
	DirAccess.make_dir_absolute(old)
	var dir := DirAccess.open(old)
	if dir != null:
		for entry in _entries(new):
			dir.create_link(new.path_join(entry), old.path_join(entry))
	_note(old, "VibeNature (formerly Skypatch) keeps its data in %s now.\n" % new
		+ "The links in this folder point there, so old hook entries and bench links keep working.\n"
		+ "Delete this folder once `just hook-install` and `just link` have been run again.\n")
	return "moved %s to %s" % [old, new]


## Moves each entry of the old Godot user folder into the new one, skipping names the new one
## already has. Returns one line per entry moved; nothing when the old folder is absent or
## already moved.
static func migrate_user_dir(old: String, new: String) -> PackedStringArray:
	var moved := PackedStringArray()
	if old == new or not DirAccess.dir_exists_absolute(old) or FileAccess.file_exists(old.path_join(NOTE)):
		return moved
	DirAccess.make_dir_recursive_absolute(new)
	for entry in _entries(old):
		var target := new.path_join(entry)
		if DirAccess.dir_exists_absolute(target) or FileAccess.file_exists(target):
			continue
		if DirAccess.rename_absolute(old.path_join(entry), target) == OK:
			moved.append("moved %s into %s" % [entry, new])
	_note(old, "VibeNature (formerly Skypatch) keeps its settings, save and album in %s now.\n" % new
		+ "Anything left here had a newer copy there already. Delete this folder whenever you like.\n")
	return moved


static func _entries(path: String) -> PackedStringArray:
	var out := PackedStringArray()
	var dir := DirAccess.open(path)
	if dir == null:
		return out
	dir.include_hidden = true
	for name in dir.get_files():
		out.append(name)
	for name in dir.get_directories():
		out.append(name)
	return out


static func _is_link(parent: String, name: String) -> bool:
	var dir := DirAccess.open(parent)
	return dir != null and dir.is_link(name)


static func _note(folder: String, text: String) -> void:
	var file := FileAccess.open(folder.path_join(NOTE), FileAccess.WRITE)
	if file != null:
		file.store_string(text)
		file.close()
