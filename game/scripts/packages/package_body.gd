class_name PackageBody
extends RefCounted

## A code body (contract §8, proposal 2026-10-20-open-shell-and-scene-packages §3a): a bespoke moment
## that ships inside Brightwing's own package, `bodies/<name>@<major>.gd`, compiled from its published
## source through `PackageGate`. Every code body extends this class; it is the only way a body reaches the
## scene, and its surface is versioned as `body_api` (`API`). `game/docs/package-format.md` lists it.
##
## **What the shell calls** (a moment's player, made by `SceneBehaviour.make_moments` from its data's
## `player` block):
## - `setup(beh: SceneBehaviour, tuning: Dictionary, seed: int, ...)`: once; `tuning` is its block of the
##   behaviour tuning, `seed` its own dice, then any `player.setup` arguments.
## - `step(dt)`, every scene step; `active() -> bool`, while it plays (one big moment at a time);
##   `start(...) -> bool` (or `player.start`, with `player.start_args`), when the director hands off;
##   a `phase` (String), its own `rng`, and `next` (a Dictionary a clip pins the next one with).
## - For the speed sweep, as its data's `speed_sweep` says: `speed_samples(dt)`, `sweep_next(n)`,
##   `put_away()`, `sweep_busy()`.
## - The hooks below, when it holds other life back.
##
## **What a body may use:** this class; the `SceneBehaviour` handed to `setup` and the scene behind it
## (`beh.scene`, a `LivingScene`) through their public members; and the shell's scene classes (sheets,
## looks, flocks, the plan in metres, the speed meter, the director's hand-off). Never a file, the OS or
## the network (`PackageGate.scan` refuses those).

## The `body_api` major this class is.
const API := 1

## The package the body came from (set before `setup`); its data through `data`.
var package: ScenePackage
## Where `sound_event` goes (set by the shell before `setup`).
var sounds_to: SceneBehaviour


## Another code body of the scene package by name ("osprey_dive@1"), for its statics; null if absent.
static func body_script(body_name: String) -> Script:
	return ScenePackages.body(body_name)


## A JSON file of the body's own package (`rel` inside it), or null.
func data(rel: String) -> Variant:
	return package.read_json(rel) if package != null else null


## A creature sheet's meta.json (`creatures/<sheet>/meta.json`, found by `AssetLibrary.creature_dir`), or {}.
func sheet_meta(sheet_id: String) -> Dictionary:
	return SceneSheet.meta_of(sheet_id)


## A creature sheet's image `file` (in `creatures/<sheet>/`) as a texture, or null.
func sheet_texture(sheet_id: String, file: String) -> Texture2D:
	return AssetLibrary.cached_texture(SceneSheet.dir_of(sheet_id).path_join(file))


## Says that something sounding happened (proposal 2026-10-21-sound-in-packages §6): `kind` from the
## shell's vocabulary or the package's own `kinds`, the `actor` drawn on screen that makes it, and
## `params` (`pos`, `species`, `band`, `depth_m`, `under`, `size`; `SceneBehaviour.sound_event`). The only
## way a body makes sound: the package's `soundscape.json` maps the kind to clips, and the shell's engine
## decides whether, how loud and where. A body never names a file, a gain, a player or a bus.
func sound_event(kind: String, actor: Object = null, params: Dictionary = {}) -> void:
	if sounds_to != null:
		sounds_to.sound_event(kind, actor, params)


## The callers it has on screen now, for their songs: [{species, actor, pos, band, depth_m}] (the geese on
## the water, the hawk on the oak). The shell asks; the calls themselves are the package's data.
func callers() -> Array:
	return []


## True while it keeps songbird parties away (none spawns, no desktop flight starts).
func keeps_birds_away() -> bool:
	return false


## True while no `species_id` may arrive (the deer moment keeps the deer visit out).
func keeps_away(_species_id: String) -> bool:
	return false
