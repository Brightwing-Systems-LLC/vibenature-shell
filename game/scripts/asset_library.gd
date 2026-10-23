class_name AssetLibrary
extends RefCounted

## Reads deliveries the contract §4 way: game/assets/<category>/<id>/meta.json plus
## PNG sheets. A missing file is "use the placeholder", never an error.

const ROOT := "res://assets"
## The companion package: the avatar's looks and the old avatars, the van, the elders, the journal's art.
const COMPANION := "vibenature_companion"
## Island packs are packages already: `res://islands/<id>/` (contract §5, retired into §8).
const ISLANDS := "res://islands"
static var _found := {}
static var _raw_textures := {}


## The file `rel` of package `package_id` ("creatures/osprey/meta.json", "kit/kit.json", "sounds/rain.ogg",
## the companion's "avatar/…", "van/…", "elder/…", "journal/…", an island's "art/…"): in the package's own
## folder when it is there (a `.vnpkg`'s files written out, `ScenePackages.files_dir`), else in an island pack of that id;
## never an older path (issue 463). The path may not exist
## (missing art is the placeholder, never an error).
static func package_file(package_id: String, rel: String) -> String:
	var key := package_id + ":" + rel
	if _found.has(key):
		return _found[key]
	var out := ScenePackages.files_dir(package_id).path_join(rel)
	var island := ISLANDS.path_join(package_id).path_join(rel)
	if package_id != "" and not _exists(out):
		if _exists(island):
			out = island
		elif _is_sound(rel) and FileAccess.file_exists(store_dir(package_id).path_join(rel)):
			out = store_dir(package_id).path_join(rel)
	_found[key] = out
	return out


## The folder `rel_dir` of package `package_id`, found the same way ("creatures/osprey", "kit").
static func package_dir(package_id: String, rel_dir: String) -> String:
	return package_file(package_id, rel_dir)


## A creature's folder (its sheets and meta.json), in the scene package.
static func creature_dir(sheet_id: String) -> String:
	return package_dir(_scene_id(), "creatures".path_join(sheet_id))


## The scene kit `kit_id`'s folder: the `kit/` of the scene package whose entry it is ("" with no such package).
static func kit_dir(kit_id: String) -> String:
	var pkg := ScenePackages.scene(kit_id)
	return ScenePackages.files_dir(pkg.id).path_join("kit") if pkg != null else ""


## The companion's file `rel` ("avatar/looks", "van/van.png", "elder/june/portrait.png", "journal"), through
## `package_file`.
static func companion_file(rel: String) -> String:
	return package_file(COMPANION, rel)


## The folder holding the companion's `avatar/` (the six old whole avatars as `<root>/avatar/<id>`, the shape
## `load_meta`/`load_texture` read): the companion package.
static func avatar_root() -> String:
	return companion_file("avatar").get_base_dir()


## Where a debug build finds a package's delivered sounds that are not in its folder yet: the shared store
## (`$VIBENATURE_HOME`, else `~/.vibenature`, then `packages/<id>/`; sound proposal 2026-10-21 §1). A release
## build reads sound only from the package itself ("" here).
static func store_dir(package_id: String) -> String:
	if not OS.is_debug_build():
		return ""
	var home := OS.get_environment("VIBENATURE_HOME")
	if home == "":
		home = OS.get_environment("HOME").path_join(DataHome.NEW_HOME) if OS.get_environment("HOME") != "" else ""
	return "" if home == "" else home.path_join("packages").path_join(package_id)


## Whether `rel` is in one of a package's sound folders (`sounds/…`, `creatures/<species>/sounds/…`).
static func _is_sound(rel: String) -> bool:
	var parts := rel.split("/")
	return (parts.size() >= 2 and parts[0] == "sounds") or (parts.size() >= 4 and parts[0] == "creatures" and parts[2] == "sounds")


static func _scene_id() -> String:
	var pkg := ScenePackages.scene()
	return pkg.id if pkg != null else ""


static func _exists(path: String) -> bool:
	return DirAccess.dir_exists_absolute(path) or FileAccess.file_exists(path) or ResourceLoader.exists(path)


## `root` is the deliveries folder; tests point it at a fixture folder of the same shape.
static func asset_dir(category: String, id: String, root: String = ROOT) -> String:
	return "%s/%s/%s" % [root, category, id]


static func load_meta(category: String, id: String, root: String = ROOT) -> Dictionary:
	return load_json(asset_dir(category, id, root) + "/meta.json")


## A meta.json (or any JSON object file) at `path`, or {} when it is missing or unreadable.
static func load_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	if parsed is Dictionary:
		return parsed
	push_warning("Unreadable meta.json, using placeholder: %s" % path)
	return {}


static func load_texture(category: String, id: String, file_name: String, root: String = ROOT) -> Texture2D:
	return image_texture("%s/%s.png" % [asset_dir(category, id, root), file_name])


## Whether the image at `path` is there: imported (the only form an export keeps of a project PNG,
## issue 395) or a raw file (an installed island
## pack's art, or a delivery not imported yet).
static func image_exists(path: String) -> bool:
	return path != "" and (ResourceLoader.exists(path) or FileAccess.file_exists(path))


## Like `image_texture`, but a raw file is decoded once and kept (a package's sheets in a release app are raw
## files written out of its `.vnpkg`, issue 452, and every animal of a species shares its sheet).
static func cached_texture(path: String) -> Texture2D:
	if path.begins_with("res://") and ResourceLoader.exists(path):
		return load(path) as Texture2D
	if not _raw_textures.has(path):
		var image := _raw_image(path)
		_raw_textures[path] = ImageTexture.create_from_image(image) if image != null else null
	return _raw_textures[path]


## Forgets where package files were found and the decoded sheets (the packages were opened again).
static func forget() -> void:
	_found.clear()
	_raw_textures.clear()


## The image at `path` as a texture, or null: its imported texture, else the raw file decoded.
static func image_texture(path: String) -> Texture2D:
	if path == "":
		return null
	if ResourceLoader.exists(path):
		var texture := load(path) as Texture2D
		if texture != null:
			return texture
	var image := _raw_image(path)
	return ImageTexture.create_from_image(image) if image != null else null


## The image at `path`, or null: its imported texture's pixels, else the raw file decoded.
static func load_image(path: String) -> Image:
	if path == "":
		return null
	if ResourceLoader.exists(path):
		var texture := load(path) as Texture2D
		if texture != null:
			return texture.get_image()
	return _raw_image(path)


## Decodes the file itself through FileAccess (which reads res:// inside a pck too), never by OS path.
static func _raw_image(path: String) -> Image:
	if not FileAccess.file_exists(path):
		return null
	var bytes := FileAccess.get_file_as_bytes(path)
	var image := Image.new()
	var err := ERR_FILE_UNRECOGNIZED
	match path.get_extension().to_lower():
		"png":
			err = image.load_png_from_buffer(bytes)
		"jpg", "jpeg":
			err = image.load_jpg_from_buffer(bytes)
		"webp":
			err = image.load_webp_from_buffer(bytes)
	return image if err == OK else null


## A tool's icon by tool id (`rod` is `items/tool_rod`), or a coloured placeholder square
## when the delivery is missing.
static func tool_icon(tool_id: String, placeholder_size: Vector2i, placeholder_color: Color) -> Texture2D:
	var texture := load_texture("items", "tool_" + tool_id, "tool_" + tool_id)
	if texture == null:
		texture = solid_texture(placeholder_size, placeholder_color)
	return texture


static func vec2i(value) -> Vector2i:
	return Vector2i(int(value[0]), int(value[1]))


static func solid_texture(size: Vector2i, color: Color) -> ImageTexture:
	var image := Image.create_empty(size.x, size.y, false, Image.FORMAT_RGBA8)
	image.fill(color)
	return ImageTexture.create_from_image(image)


static func blob_texture(size: Vector2i, color: Color) -> ImageTexture:
	var image := Image.create_empty(size.x, size.y, false, Image.FORMAT_RGBA8)
	var center := Vector2(size) / 2.0
	for y in size.y:
		for x in size.x:
			var d := (Vector2(x, y) + Vector2(0.5, 0.5) - center) / center
			if d.length_squared() <= 1.0:
				image.set_pixel(x, y, color)
	return ImageTexture.create_from_image(image)
