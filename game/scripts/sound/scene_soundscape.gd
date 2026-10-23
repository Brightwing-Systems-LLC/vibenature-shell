class_name SceneSoundscape
extends RefCounted

## A scene package's sound (proposal 2026-10-21-sound-in-packages §2, §5): its `soundscape.json` (beds by
## time of day and weather, call overrides, event kinds to clips, the distance curve) and each species'
## `creatures/<species>/sounds/calls.json`, checked against the shell's rules before anything plays. A file
## that breaks a rule is refused whole, with one log line, and the scene plays silent; it never crashes.
##
## OGGs are read through the package (a folder or a `.vnpkg`), else where a debug build finds them delivered
## (`AssetLibrary.package_file`, the shared store), and decoded from the buffer with
## `AudioStreamOggVorbis.load_from_buffer`: never a Godot resource, never res:// import. Nothing is decoded
## until a sound is about to play (`stream`), so with sound off nothing is read at all.

const FORMAT := 1
## The `sound_api` this shell plays (package.json); the vocabulary below is its.
const SOUND_API := 1
const FILE := "soundscape.json"
const CALLS := "calls.json"
const LICENCES := "LICENSES.json"
## The shell's event vocabulary at `sound_api` 1 (§2). An official package may add its own in `kinds`.
const VOCABULARY: Array[String] = [
	"fish_jump", "fish_reentry", "fish_rise", "takeoff", "land", "flock_takeoff", "flock_land", "wade_step",
	"strike", "splash_in", "turtle_slide", "alarm", "wingbeats", "thunder_far", "thunder_near",
]
## Kinds with no actor to see: the weather (§6, the visible-cause gate's only exception).
const WEATHER_KINDS: Array[String] = ["thunder_far", "thunder_near"]
## A declared kind may never look like an agent's (§5 rule 7): sound has no channel to the work.
const AGENTISH: Array[String] = ["agent", "session", "tool", "prompt", "notif"]
const TIMES: Array[String] = ["dawn", "day", "dusk", "night"]
const FOLLOWS: Array[String] = ["rain", "wind", "wet", "cloud"]
const ALLOWED_LICENCES: Array[String] = ["cc0", "public-domain", "licensed", "own"]
## §5 rule 8's ranges.
const GAIN_DB := Vector2(-24.0, 3.0)
const MAX_PITCH_JITTER := 0.15
const MAX_GAIN_JITTER_DB := 6.0
const MIN_GAP_S := 0.5
const MIN_CROSSFADE_S := 4.0
const MAX_PER_MIN := 4.0
## §5 rule 4: size and length by what the clip is.
const BED_MAX_BYTES := 6 * 1024 * 1024
const BED_MAX_SEC := 240.0
const SHORT_MAX_BYTES := 512 * 1024
const SHORT_MAX_SEC := 12.0
const THUNDER_MAX_SEC := 20.0

## Every OGG decoded in this run, across all soundscapes (a test asserts sound off decodes none).
static var decoded := 0

var package: ScenePackage
var data: Dictionary = {}
## Why the soundscape was refused ("" when it plays).
var problem := ""
## Clips named but not delivered here (the store not linked): they stay silent; not a refusal.
var missing: PackedStringArray = PackedStringArray()
## Clips turned away when decoded (not Vorbis, wrong rate or channels, too big, no licence record).
var refused_clips := {}
## species -> {"song": {...}, "alarm": {...}}: each set's clips (package paths), per_min, time weights,
## pitch_jitter and gain_db, the scene's overrides applied; muted species are left out.
var calls := {}
var _streams := {}
var _licences := {}
var _caps: Dictionary = {}


## The scene package's soundscape, checked; `caps` is the shell's voices per bus (`sound.voices`).
## Never null: a missing or refused file comes back with `problem` set, and plays nothing.
static func load_for(pkg: ScenePackage, caps: Dictionary) -> SceneSoundscape:
	var s := SceneSoundscape.new()
	s.package = pkg
	s._caps = caps
	if pkg == null:
		s.problem = "no scene package"
		return s
	var api := int(pkg.manifest.get("sound_api", SOUND_API))
	if api != SOUND_API:
		s.problem = "sound_api %d; this shell plays %d" % [api, SOUND_API]
		push_warning("VibeNature: sound: %s refused: %s" % [pkg.id, s.problem])
		return s
	var text := s._text(FILE)
	if text == "":
		s.problem = "no %s" % FILE
		return s
	s.problem = s._parse(text)
	if s.problem == "":
		s.problem = s._load_calls()
	if s.problem != "":
		push_warning("VibeNature: sound: %s %s refused: %s" % [pkg.id, FILE, s.problem])
		s.data = {}
		s.calls = {}
	elif not s.missing.is_empty():
		print("VibeNature: sound: %s: %d clips not delivered here (the store is not linked?), they stay silent" % [pkg.id, s.missing.size()])
	return s


## Whether anything can play.
func ok() -> bool:
	return problem == ""


func _parse(text: String) -> String:
	var parsed = JSON.parse_string(text)
	if not parsed is Dictionary:
		return "it does not parse"
	data = parsed
	if int(data.get("format", 0)) != FORMAT:
		return "format %s; this shell reads %d" % [data.get("format", "none"), FORMAT]
	var times = data.get("times", {})
	if not times is Dictionary:
		return "times is not an object"
	for k in ["dawn", "dusk"]:
		if times.has(k) and not _pair(times[k]):
			return "times.%s is not [from, to] minutes" % k
	var beds = data.get("beds", {})
	if not beds is Dictionary:
		return "beds is not an object"
	if beds.has("crossfade_s") and float(beds["crossfade_s"]) < MIN_CROSSFADE_S:
		return "beds.crossfade_s %s is under %.0f" % [beds["crossfade_s"], MIN_CROSSFADE_S]
	var time_beds = beds.get("time", {})
	if not time_beds is Dictionary:
		return "beds.time is not an object"
	for slot in time_beds:
		if not TIMES.has(String(slot)):
			return "beds.time.%s is not one of %s" % [slot, ", ".join(TIMES)]
		var why := _clip_list(time_beds[slot], "beds.time.%s" % slot, "bed")
		if why != "":
			return why
	var weather_beds = beds.get("weather", [])
	if not weather_beds is Array:
		return "beds.weather is not a list"
	for w in weather_beds:
		if not w is Dictionary:
			return "a weather bed is not an object"
		var id := String(w.get("id", ""))
		if not FOLLOWS.has(String(w.get("follows", ""))):
			return "beds.weather %s follows %s, not one of %s" % [id, w.get("follows", "nothing"), ", ".join(FOLLOWS)]
		if not _curve(w.get("curve", [])):
			return "beds.weather %s has no curve of [value 0..1, dB] points" % id
		for p in w["curve"]:
			if float(p[1]) > GAIN_DB.y:
				return "beds.weather %s's curve goes over %+.0f dB" % [id, GAIN_DB.y]
		if w.has("ducks_time_db") and not _in(float(w["ducks_time_db"]), GAIN_DB):
			return "beds.weather %s ducks_time_db %s is outside %s" % [id, w["ducks_time_db"], GAIN_DB]
		var why := _clip_list(w, "beds.weather %s" % id, "bed")
		if why != "":
			return why
	var events = data.get("events", {})
	if not events is Dictionary:
		return "events is not an object"
	var kinds: Array = data.get("kinds", [])
	if not kinds.is_empty():
		if not PackageGate.code_allowed(ScenePackages.release, package.from_vnpkg, package.trust):
			return "only an official package may declare its own kinds"
		for k in kinds:
			for bad in AGENTISH:
				if String(k).begins_with(bad):
					return "kind %s looks like an agent's" % k
	for key in events:
		var kind := String(key).get_slice(":", 0)
		if not VOCABULARY.has(kind) and not kinds.has(kind):
			return "event %s is not in the shell's vocabulary" % key
		var e = events[key]
		if not e is Dictionary:
			return "event %s is not an object" % key
		var why := _numbers(e, "event %s" % key, str(_caps.get("events", 4)))
		if why != "":
			return why
		if e.has("by_size") and not _pair(e["by_size"]):
			return "event %s by_size is not [small, large]" % key
		if e.has("call"):
			if String(key).get_slice(":", 1) == "":
				return "event %s plays a call but names no species (kind:species)" % key
			continue
		why = _clip_list(e, "event %s" % key, "thunder" if kind.begins_with("thunder") else "short")
		if why != "":
			return why
	var call_overrides = data.get("calls", {})
	if not call_overrides is Dictionary:
		return "calls is not an object"
	for sp in call_overrides:
		var c = call_overrides[sp]
		if not c is Dictionary:
			return "calls.%s is not an object" % sp
		var why := _numbers(c, "calls.%s" % sp, str(_caps.get("calls", 3)))
		if why != "":
			return why
	var dist = data.get("distance", {})
	if not dist is Dictionary or (dist.has("lowpass_hz") and not _curve(dist["lowpass_hz"])):
		return "distance is not {ref_m, rolloff, min_db, lowpass_hz: [[m, Hz]...], pan_width}"
	if float(dist.get("pan_width", 0.6)) > 1.0 or float(dist.get("pan_width", 0.6)) < 0.0:
		return "distance.pan_width is outside 0..1"
	if float(dist.get("min_db", -18.0)) < GAIN_DB.x:
		return "distance.min_db is under %.0f" % GAIN_DB.x
	var under = data.get("underwater", {})
	if not under is Dictionary or (under.has("gain_db") and not _in(float(under["gain_db"]), GAIN_DB)):
		return "underwater is not {gain_db %s, lowpass_hz}" % GAIN_DB
	return ""


## Each species' calls.json (bench), with the scene's overrides; species the scene mutes are left out.
func _load_calls() -> String:
	var overrides: Dictionary = data.get("calls", {})
	for sp in _call_species():
		var o: Dictionary = overrides.get(sp, {})
		if bool(o.get("mute", false)):
			continue
		var rel := "creatures/%s/sounds/%s" % [sp, CALLS]
		var parsed = JSON.parse_string(_text(rel))
		if not parsed is Dictionary:
			return "%s does not parse" % rel
		if int(parsed.get("format", 0)) != FORMAT:
			return "%s is not format %d" % [rel, FORMAT]
		var sets := {}
		for set_name in parsed:
			if set_name == "format":
				continue
			var cs = parsed[set_name]
			if not cs is Dictionary:
				return "%s %s is not an object" % [rel, set_name]
			var merged: Dictionary = cs.duplicate()
			if set_name == "song":
				for k in ["per_min", "time", "gain_db", "gain_jitter_db", "pitch_jitter"]:
					if o.has(k):
						merged[k] = o[k]
			var why := _numbers(merged, "%s %s" % [rel, set_name], str(_caps.get("calls", 3)))
			if why != "":
				return why
			var clips: Array = []
			for c in merged.get("clips", []):
				clips.append("creatures/%s/sounds/%s" % [sp, String(c)])
			merged["clips"] = clips
			why = _clip_list(merged, "%s %s" % [rel, set_name], "short")
			if why != "":
				return why
			sets[set_name] = merged
		calls[sp] = sets
	return ""


## The species that have a calls.json: in the package, and (a debug build) in the shared store.
func _call_species() -> PackedStringArray:
	var out := PackedStringArray()
	for f in package.files:
		var parts := f.split("/")
		if parts.size() == 4 and parts[0] == "creatures" and parts[2] == "sounds" and parts[3] == CALLS:
			out.append(parts[1])
	var store := AssetLibrary.store_dir(package.id).path_join("creatures")
	if AssetLibrary.store_dir(package.id) != "" and DirAccess.dir_exists_absolute(store):
		for sp in DirAccess.get_directories_at(store):
			if not out.has(sp) and FileAccess.file_exists(store.path_join(sp).path_join("sounds").path_join(CALLS)):
				out.append(sp)
	out.sort()
	return out


## Checks an entry's numbers against §5 rule 8; `voices_cap` is its bus's.
func _numbers(e: Dictionary, what: String, voices_cap: String) -> String:
	if e.has("gain_db") and not _in(float(e["gain_db"]), GAIN_DB):
		return "%s gain_db %s is outside %+.0f..%+.0f" % [what, e["gain_db"], GAIN_DB.x, GAIN_DB.y]
	if float(e.get("pitch_jitter", 0.0)) > MAX_PITCH_JITTER or float(e.get("pitch_jitter", 0.0)) < 0.0:
		return "%s pitch_jitter %s is over %.2f" % [what, e["pitch_jitter"], MAX_PITCH_JITTER]
	if float(e.get("gain_jitter_db", 0.0)) > MAX_GAIN_JITTER_DB or float(e.get("gain_jitter_db", 0.0)) < 0.0:
		return "%s gain_jitter_db %s is outside 0..%.0f" % [what, e["gain_jitter_db"], MAX_GAIN_JITTER_DB]
	if e.has("min_gap_s") and float(e["min_gap_s"]) < MIN_GAP_S:
		return "%s min_gap_s %s is under %.1f" % [what, e["min_gap_s"], MIN_GAP_S]
	if e.has("voices") and (int(e["voices"]) < 1 or int(e["voices"]) > int(voices_cap)):
		return "%s voices %s is outside 1..%s" % [what, e["voices"], voices_cap]
	if e.has("per_min") and (float(e["per_min"]) < 0.0 or float(e["per_min"]) > MAX_PER_MIN):
		return "%s per_min %s is outside 0..%.0f" % [what, e["per_min"], MAX_PER_MIN]
	if e.has("time"):
		if not e["time"] is Dictionary:
			return "%s time is not {dawn, day, dusk, night}" % what
		for k in e["time"]:
			if not TIMES.has(String(k)) or float(e["time"][k]) < 0.0 or float(e["time"][k]) > MAX_PER_MIN:
				return "%s time.%s is not a weight 0..%.0f for a time of day" % [what, k, MAX_PER_MIN]
	return ""


## Checks that `e.clips` is a non-empty list of OGGs in a sound folder; notes the ones not delivered here.
func _clip_list(e, what: String, _kind: String) -> String:
	if not e is Dictionary:
		return "%s is not an object" % what
	var clips = e.get("clips", [])
	if not clips is Array or clips.is_empty():
		return "%s has no clips" % what
	for c in clips:
		var rel := String(c)
		if rel.get_extension().to_lower() != "ogg" or ScenePackage.path_problem(rel, false) != "":
			return "%s names %s, not an OGG in the package" % [what, rel]
		if not AssetLibrary._is_sound(rel):
			return "%s names %s, outside sounds/ and creatures/<species>/sounds/" % [what, rel]
		if not _has(rel) and not missing.has(rel):
			missing.append(rel)
	return ""


## The event entry for a typed event: `kind:species` first, then `kind`; {} when nothing sounds.
func event_entry(kind: String, species: String) -> Dictionary:
	var events: Dictionary = data.get("events", {})
	if species != "" and events.has(kind + ":" + species):
		return events[kind + ":" + species]
	return events.get(kind, {})


## The key an event entry is found under (its gap and voices count per key).
func event_key(kind: String, species: String) -> String:
	var events: Dictionary = data.get("events", {})
	return kind + ":" + species if species != "" and events.has(kind + ":" + species) else kind


## The time bed's slot at `minute`: dawn and dusk are windows of `times` around sunrise and sunset.
func time_slot(minute: float, sunrise: float, sunset: float) -> String:
	var times: Dictionary = data.get("times", {})
	var dawn: Array = times.get("dawn", [-40, 70])
	var dusk: Array = times.get("dusk", [-50, 40])
	var d0 := sunrise + float(dawn[0])
	var d1 := sunrise + float(dawn[1])
	var k0 := sunset + float(dusk[0])
	var k1 := sunset + float(dusk[1])
	var m := fposmod(minute, 1440.0)
	if m >= d0 and m < d1:
		return "dawn"
	if m >= d1 and m < k0:
		return "day"
	if m >= k0 and m < k1:
		return "dusk"
	return "night"


## The decoded clip `rel` (a path in the package), or null when it is not delivered or is refused. Decoded
## once, from the bytes, never as a resource.
func stream(rel: String, kind: String = "short") -> AudioStream:
	if _streams.has(rel):
		return _streams[rel]
	var out: AudioStream = null
	var bytes := _bytes(rel)
	if bytes.is_empty():
		_streams[rel] = null
		return null
	var why := clip_problem(rel, bytes, kind)
	if why == "":
		why = _licence_problem(rel)
	if why != "":
		refused_clips[rel] = why
		push_warning("VibeNature: sound: %s refused: %s" % [rel, why])
	else:
		var s := AudioStreamOggVorbis.load_from_buffer(bytes)
		decoded += 1
		if s == null:
			refused_clips[rel] = "does not decode"
		elif s.get_length() > _max_sec(kind):
			refused_clips[rel] = "%.1f s is over %.0f s" % [s.get_length(), _max_sec(kind)]
		else:
			# A bed loops (the bench makes its seam click-free), so one still fading out never stops dead.
			s.loop = kind == "bed"
			out = s
	_streams[rel] = out
	return out


func _max_sec(kind: String) -> float:
	match kind:
		"bed":
			return BED_MAX_SEC
		"thunder":
			return THUNDER_MAX_SEC
	return SHORT_MAX_SEC


## Why the bytes of `rel` may not play (§5 rules 2-4), or "": an Ogg container whose first packet is a
## Vorbis identification header, mono or stereo (mono for calls and events, which are panned), 44.1 or
## 48 kHz, within its kind's size.
static func clip_problem(rel: String, bytes: PackedByteArray, kind: String) -> String:
	if bytes.size() < 58 or bytes.slice(0, 4).get_string_from_ascii() != "OggS":
		return "not an Ogg file"
	var segments := bytes[26]
	var at := 27 + segments
	if bytes.size() < at + 30 or bytes[at] != 1 or bytes.slice(at + 1, at + 7).get_string_from_ascii() != "vorbis":
		return "not Vorbis inside the Ogg (Opus and FLAC are refused)"
	var channels := bytes[at + 11]
	var rate := bytes.decode_u32(at + 12)
	if channels < 1 or channels > 2:
		return "%d channels (mono or stereo only)" % channels
	if kind != "bed" and channels != 1:
		return "a call or event must be mono (it is panned)"
	if rate != 44100 and rate != 48000:
		return "%d Hz (44.1 or 48 kHz only)" % rate
	var cap := BED_MAX_BYTES if kind == "bed" else SHORT_MAX_BYTES
	if bytes.size() > cap:
		return "%d KB is over %d KB" % [bytes.size() / 1024, cap / 1024]
	return ""


## Why `rel` has no allowed licence record in its folder's LICENSES.json (§4, §5 rule 5), or "".
func _licence_problem(rel: String) -> String:
	var folder := rel.get_base_dir()
	if not _licences.has(folder):
		var text := _text(folder.path_join(LICENCES))
		var parsed = JSON.parse_string(text) if text != "" else null
		_licences[folder] = parsed.get("files", {}) if parsed is Dictionary else {}
	var rec = (_licences[folder] as Dictionary).get(rel.get_file())
	if not rec is Dictionary:
		return "no licence record in %s" % folder.path_join(LICENCES)
	if not ALLOWED_LICENCES.has(String(rec.get("licence", ""))):
		return "licence %s is not one of %s" % [rec.get("licence", "none"), ", ".join(ALLOWED_LICENCES)]
	for src in rec.get("sources", []):
		if not src is Dictionary or not ALLOWED_LICENCES.has(String(src.get("licence", ""))):
			return "a source's licence is not one of %s" % ", ".join(ALLOWED_LICENCES)
	return ""


func _has(rel: String) -> bool:
	return package.has_file(rel) or FileAccess.file_exists(AssetLibrary.package_file(package.id, rel))


func _bytes(rel: String) -> PackedByteArray:
	if package.has_file(rel):
		return package.read_bytes(rel)
	var path := AssetLibrary.package_file(package.id, rel)
	return FileAccess.get_file_as_bytes(path) if FileAccess.file_exists(path) else PackedByteArray()


func _text(rel: String) -> String:
	if package.has_file(rel):
		return package.read_text(rel)
	var path := AssetLibrary.package_file(package.id, rel)
	return FileAccess.get_file_as_string(path) if FileAccess.file_exists(path) else ""


static func _pair(v) -> bool:
	return v is Array and v.size() == 2 and (v[0] is float or v[0] is int) and (v[1] is float or v[1] is int)


static func _curve(v) -> bool:
	if not v is Array or v.is_empty():
		return false
	for p in v:
		if not _pair(p):
			return false
	return true


static func _in(x: float, r: Vector2) -> bool:
	return x >= r.x and x <= r.y


## The value of a curve of [x, y] points at `x` (flat beyond its ends).
static func curve_at(curve: Array, x: float) -> float:
	if curve.is_empty():
		return 0.0
	if x <= float(curve[0][0]):
		return float(curve[0][1])
	for i in range(1, curve.size()):
		var a: Array = curve[i - 1]
		var b: Array = curve[i]
		if x <= float(b[0]):
			var span := float(b[0]) - float(a[0])
			return lerpf(float(a[1]), float(b[1]), (x - float(a[0])) / span if span > 0.0 else 1.0)
	return float(curve[-1][1])
