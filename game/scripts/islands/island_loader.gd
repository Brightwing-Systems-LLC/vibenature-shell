class_name IslandLoader
extends RefCounted

## Finds, checks and mounts island packs (contract §5):
## - built-in packs: folders under res://islands/, part of the game;
## - installed packs: `<id>.pck` (+ `<id>.pck.sig`) in user://islands/.
##
## An installed pack loads only if its signature checks against a trusted key, or this is a
## development run (`allow_unsigned`); its files all sit under res://islands/<id>/; its id is
## not a built-in one; and the game is new enough for it. Anything else is refused with the
## reason logged, never a crash, and the file is left where it is.

const BUILT_IN := "res://islands"
const INSTALLED := "user://islands"

var shelf: Dictionary
var trusted_keys: Array[CryptoKey] = []
var allow_unsigned := false
var game_version := ""
var installed_dir := INSTALLED
## id -> IslandPack, built-in first.
var packs: Dictionary = {}
## [{"file": String, "why": String}]
var refused: Array = []
## Packs mounted in this process (id -> file). Mounting cannot be undone, and a mounted pack's
## folder shows under res://islands/ like a built-in one, so built-in discovery skips these.
static var mounted: Dictionary = {}


static func create(shelf_config: Dictionary, keys: Array[CryptoKey], unsigned_ok: bool, version: String,
		dir: String = INSTALLED) -> IslandLoader:
	var loader := IslandLoader.new()
	loader.shelf = shelf_config
	loader.trusted_keys = keys
	loader.allow_unsigned = unsigned_ok
	loader.game_version = version
	loader.installed_dir = dir
	return loader


## The loader the game uses: Brightwing's key; unsigned packs only in development runs.
static func for_game(shelf_config: Dictionary, dir: String = INSTALLED) -> IslandLoader:
	return create(shelf_config, IslandSigning.release_keys(), OS.is_debug_build(), IslandPack.game_version(), dir)


func load_all() -> void:
	load_built_in()
	load_installed()


func load_built_in(dir: String = BUILT_IN) -> void:
	var ids := Array(DirAccess.get_directories_at(dir))
	ids.sort()
	for id in ids:
		if mounted.has(id):
			continue
		var pack := IslandPack.read(dir.path_join(id), shelf)
		pack.source = "built-in"
		_register(pack, dir.path_join(id))


func load_installed() -> void:
	if not DirAccess.dir_exists_absolute(installed_dir):
		return
	var files := Array(DirAccess.get_files_at(installed_dir))
	files.sort()
	for file in files:
		if file.ends_with(".pck"):
			mount(installed_dir.path_join(file))


## Checks and mounts one installed pack. Returns the pack, or null (and records why).
func mount(pck_path: String) -> IslandPack:
	var why := check(pck_path)
	if why != "":
		return _refuse(pck_path, why)
	if not ProjectSettings.load_resource_pack(pck_path, false):
		return _refuse(pck_path, "Godot could not mount it")
	var id := pck_path.get_file().get_basename()
	mounted[id] = pck_path
	var pack := IslandPack.read(BUILT_IN.path_join(id), shelf)
	pack.source = "installed"
	return pack if _register(pack, pck_path) else null


## Why `pck_path` must not be mounted, or "". Nothing is mounted here.
func check(pck_path: String) -> String:
	var id := pck_path.get_file().get_basename()
	if not pck_path.ends_with(".pck") or not RegEx.create_from_string(IslandPack.ID_PATTERN).search(id):
		return "an island pack is <id>.pck with a snake_case id"
	if packs.has(id):
		return "an island %s is already loaded (%s)" % [id, packs[id].source]
	var sig_path := pck_path + ".sig"
	if FileAccess.file_exists(sig_path):
		if not IslandSigning.verify_file(pck_path, FileAccess.get_file_as_string(sig_path), trusted_keys):
			return "its signature does not match (altered, or not signed by Brightwing)"
	elif not allow_unsigned:
		return "unsigned; release builds load only packs signed by Brightwing"
	var listing := PckDirectory.list(pck_path)
	if listing.has("error"):
		return String(listing["error"])
	var prefix := "islands/%s/" % id
	var has_manifest := false
	for path: String in listing["paths"]:
		var clean := path.trim_prefix("res://")
		if not clean.begins_with(prefix) or clean.contains(".."):
			return "it holds %s, outside its own folder" % clean
		has_manifest = has_manifest or clean == prefix + IslandPack.MANIFEST
	if not has_manifest:
		return "it has no %s%s" % [prefix, IslandPack.MANIFEST]
	var manifest = JSON.parse_string(PckDirectory.read(pck_path, prefix + IslandPack.MANIFEST).get_string_from_utf8())
	if not manifest is Dictionary or String(manifest.get("id", "")) != id:
		return "its %s is unreadable or names another id" % IslandPack.MANIFEST
	if int(manifest.get("format", 0)) > IslandPack.FORMAT:
		return "pack format %d is newer than this game reads (%d): update the game" % [int(manifest["format"]), IslandPack.FORMAT]
	var needs := String(manifest.get("min_game_version", ""))
	if IslandPack.parse_version(needs).is_empty():
		return "min_game_version must be x.y.z"
	if IslandPack.compare_versions(needs, game_version) > 0:
		return "needs game %s or later; this is %s (it stays installed and loads after an update)" % [needs, game_version]
	return ""


## Copies a pack (and its signature, if any) into the installed folder and mounts it.
## Returns the pack, or null with the reason in `refused`. A pack that fails its checks is
## not copied.
func install(pck_path: String) -> IslandPack:
	var why := check(pck_path)
	if why != "":
		return _refuse(pck_path, why)
	DirAccess.make_dir_recursive_absolute(installed_dir)
	var target := installed_dir.path_join(pck_path.get_file())
	if ProjectSettings.globalize_path(target) != ProjectSettings.globalize_path(pck_path):
		for suffix in ["", ".sig"]:
			if FileAccess.file_exists(pck_path + suffix):
				DirAccess.copy_absolute(ProjectSettings.globalize_path(pck_path + suffix), ProjectSettings.globalize_path(target + suffix))
	return mount(target)


func _register(pack: IslandPack, file: String) -> bool:
	var why := pack.problem
	if why == "":
		why = pack.version_problem(game_version)
	if why == "" and packs.has(pack.id):
		why = "an island %s is already loaded" % pack.id
	if why != "":
		_refuse(file, why)
		return false
	packs[pack.id] = pack
	return true


func _refuse(file: String, why: String) -> IslandPack:
	refused.append({"file": file, "why": why})
	push_warning("VibeNature: island pack %s refused: %s" % [file.get_file(), why])
	return null
