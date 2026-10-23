class_name ElderLetters
extends RefCounted

## The elder's letters (issue 213; rules in
## a private design note and `-2.md`). Pure: the clock, the game day and
## the dice come in from outside, so tests drive it with a fake clock.
##
## You send a photo from the journal (`send`); overnight (`overnight`, once a game day, while you are
## not at the log) a reply may be written for one photo sent before today, picked from the pool by the
## photo's metadata only (species, weather, season, place, time of day; nothing else exists to read),
## or now and then an unprompted note (a place tip, a seasonal note). At most one letter waits; letters
## never pile up, and nothing ever says how long you were gone. Read letters are kept like photos.
##
## Privacy: what is kept is the photo's own metadata (as the album keeps it), the letter ids and the
## filled letters. No string from an agent ever reaches this.

signal changed

## In the companion package (contract §8).
const LETTERS_PATH := "elder/letters.json"
const ELDERS_PATH := "elder/elders.json"
const DAY_SEC := 86400.0

var tuning: Dictionary = {}
var phases: DayPhases
## The companion package's elder/letters.json and elder/elders.json.
var book: Dictionary = {}
var family: Dictionary = {}
## Sent photos by album id: {unix, day, date, time, weather, species, place, first_of, replied}.
var sent: Dictionary = {}
## Every letter that came, oldest first: {id, kind, photo, photo_date, photo_time, unix, day, read, body,
## sign_off, name, elder}.
var letters: Array = []
## The game day the last overnight decision was made for.
var decided_day := ""
var first_given := false
## The last letter id sent for each species (a species' next letter is never the same one).
var last_by_species: Dictionary = {}
## Seasons already noted, as "<year>-<season>".
var noted_seasons: Array = []


func _init(elder_tuning: Dictionary, day_phases: DayPhases, letters_data: Dictionary = {}, elders_data: Dictionary = {}) -> void:
	tuning = elder_tuning
	phases = day_phases
	book = letters_data if not letters_data.is_empty() else ElderLetters.read_json(LETTERS_PATH)
	family = elders_data if not elders_data.is_empty() else ElderLetters.read_json(ELDERS_PATH)


## `path` read as JSON: a file inside the companion package (`LETTERS_PATH`, `ELDERS_PATH`), or a
## res:// or user:// file; {} if missing or broken.
static func read_json(path: String) -> Dictionary:
	var parsed = null
	if path.contains("://"):
		parsed = JSON.parse_string(FileAccess.get_file_as_string(path)) if FileAccess.file_exists(path) else null
	elif ScenePackages.companion() != null:
		parsed = ScenePackages.companion().read_json(path)
	return parsed if parsed is Dictionary else {}


func pool() -> Array:
	return book.get("letters", [])


# The elder ---------------------------------------------------------------------------------------

## A whole, valid choice: who (an elder id), the relationship and the name ("" for the default).
func sanitize(choice: Dictionary) -> Dictionary:
	var order: Array = family.get("order", [])
	var relations: Array = family.get("relations", [])
	var who := String(choice.get("who", ""))
	var relation := String(choice.get("relation", ""))
	return {
		"who": who if order.has(who) else (String(order[0]) if not order.is_empty() else ""),
		"relation": relation if relations.has(relation) else (String(relations[0]) if not relations.is_empty() else ""),
		"name": String(choice.get("name", "")).strip_edges().left(24),
	}


func elder_of(choice: Dictionary) -> Dictionary:
	return family.get("elders", {}).get(String(sanitize(choice)["who"]), {})


## The name they sign with: yours for them, or the default for that elder and relationship.
func name_of(choice: Dictionary) -> String:
	var c := sanitize(choice)
	if String(c["name"]) != "":
		return String(c["name"])
	return default_name(c)


func default_name(choice: Dictionary) -> String:
	var c := sanitize(choice)
	return String(elder_of(c).get("default_name", {}).get(String(c["relation"]), ""))


func sign_off(choice: Dictionary) -> String:
	return String(family.get("sign_off", {}).get(String(sanitize(choice)["relation"]), ""))


## The portrait slot's path for the chosen elder (issue 241), "" if none: its `portrait`, a companion file.
func portrait_path(choice: Dictionary) -> String:
	var rel := String(elder_of(choice).get("portrait", ""))
	return AssetLibrary.companion_file(rel) if rel != "" else ""


## Every token filled for the chosen elder and relationship; `photo` gives {photo_time}.
func fill(text: String, choice: Dictionary, photo: Dictionary = {}) -> String:
	var c := sanitize(choice)
	var elder := elder_of(c)
	var given := String(elder.get("given", ""))
	var partner := String(elder.get("partner", ""))
	var values := {
		"{elder_name}": name_of(c),
		"{partner}": partner,
		"{partner_they}": String(elder.get("partner_they", "")),
		"{partner_them}": String(elder.get("partner_them", "")),
		"{partner_their}": String(elder.get("partner_their", "")),
		"{relation}": String(elder.get("relation", {}).get(String(c["relation"]), "")),
		"{sign_off}": sign_off(c),
		"{elder_initial}": given.left(1),
		"{partner_initial}": partner.left(1),
		"{photo_time}": photo_time(String(photo.get("time", ""))),
	}
	for token in values:
		text = text.replace(token, String(values[token]))
	return text


# Photo facts -------------------------------------------------------------------------------------

func phase_of(time: String) -> String:
	if not time.contains(":"):
		return ""
	return phases.phase_at(DayPhases.minutes(time))


func photo_time(time: String) -> String:
	return String(tuning["photo_time"].get(phase_of(time), "that day"))


static func season_of(month: int, seasons: Dictionary) -> String:
	for season in seasons:
		for m in seasons[season]:
			if int(m) == month:
				return String(season)
	return ""


## What a letter can be matched on, from a sent photo's own metadata only.
func facts(entry: Dictionary) -> Dictionary:
	var date := String(entry.get("date", ""))
	var month := int(date.split("-")[1]) if date.split("-").size() == 3 else 0
	return {
		"species": entry.get("species", []),
		"weather": String(tuning["weather"].get(String(entry.get("weather", "")), "")),
		"season": ElderLetters.season_of(month, tuning["seasons"]),
		"place": String(entry.get("place", tuning["place"])),
		"time_of_day": String(tuning["time_of_day"].get(phase_of(String(entry.get("time", ""))), "")),
		"first_of": entry.get("first_of", []),
	}


func species_match(want: String, have: Array) -> bool:
	var group: Array = tuning["species_groups"].get(want, [])
	for h in have:
		if String(h) == want or group.has(String(h)):
			return true
	return false


## How well a letter fits a photo: the number of keys it names (first_seen counts double), or -1 when
## any key does not match. A key the photo cannot answer (behaviour: photos do not record it) never matches.
func score(letter: Dictionary, f: Dictionary) -> int:
	var total := 0
	var keys: Dictionary = letter.get("keys", {})
	for key in keys:
		var want = keys[key]
		if want == null:
			continue
		match String(key):
			"species":
				if not species_match(String(want), f["species"]):
					return -1
				total += 1
			"first_seen":
				if bool(want):
					if not keys.has("species") or not species_match(String(keys["species"]), f["first_of"]):
						return -1
					total += 2
			"weather", "season", "place", "time_of_day":
				if String(f[key]) != String(want):
					return -1
				total += 1
			_:
				return -1
	return total


# Sending -----------------------------------------------------------------------------------------

func is_sent(photo_id: String) -> bool:
	return sent.has(photo_id)


## Sends a photo (one click, never undone). `photo` is the album's entry; only its metadata is kept.
func send(photo: Dictionary, now: float, day: String, place: String = "") -> bool:
	var id := String(photo.get("id", ""))
	if id == "" or sent.has(id):
		return false
	var species: Array = PhotoAlbum.clean_species(photo.get("species", []))
	var before: Array = []
	for other in sent.values():
		before.append_array(other.get("species", []))
	sent[id] = {
		"unix": now, "day": day,
		"date": String(photo.get("date", "")), "time": String(photo.get("time", "")),
		"weather": PhotoAlbum.clean_weather(photo.get("weather", "")),
		"species": species,
		"place": place if place != "" else String(tuning["place"]),
		"first_of": species.filter(func(s) -> bool: return not before.has(s)),
		"replied": false,
	}
	changed.emit()
	return true


# Letters -----------------------------------------------------------------------------------------

## The letter waiting to be read, or {}. Never more than one.
func waiting() -> Dictionary:
	for letter in letters:
		if not bool(letter["read"]):
			return letter
	return {}


func mark_read() -> void:
	var any := false
	for letter in letters:
		if not bool(letter["read"]):
			letter["read"] = true
			any = true
	if any:
		changed.emit()


## Whether the waiting letter is still to be read on the log (issue 270): the sitter takes it out once per letter.
func due_on_log() -> bool:
	var letter := waiting()
	return not letter.is_empty() and not bool(letter.get("on_log", false))


## The waiting letter was taken out on the log; it is not read there again (it still waits in the journal).
func mark_on_log() -> void:
	var letter := waiting()
	if letter.is_empty() or bool(letter.get("on_log", false)):
		return
	letter["on_log"] = true
	changed.emit()


## Newest first, for the journal.
func kept() -> Array:
	var out := letters.duplicate()
	out.reverse()
	return out


## The first letter, waiting after the welcome (until it exists, on the first launch). Not counted by
## any of the overnight rules.
func give_first(now: float, day: String, choice: Dictionary) -> Dictionary:
	if first_given:
		return {}
	first_given = true
	for letter in pool():
		if String(letter.get("kind", "")) == "first":
			return _deliver(letter, {}, "", now, day, choice)
	changed.emit()
	return {}


## Once a game day, while you are not at the log: maybe a reply, maybe a note, usually nothing.
## Returns the new letter, or {}.
func overnight(now: float, day: String, choice: Dictionary, rng: RandomNumberGenerator) -> Dictionary:
	if day == decided_day:
		return {}
	decided_day = day
	changed.emit()
	if not waiting().is_empty():
		return {}
	var counted := letters.filter(func(l: Dictionary) -> bool: return String(l["kind"]) != "first")
	for letter in counted:
		if now - float(letter["unix"]) < float(tuning["min_gap_days"]) * DAY_SEC:
			return {}
	var this_week := counted.filter(func(l: Dictionary) -> bool: return now - float(l["unix"]) < 7.0 * DAY_SEC)
	if this_week.size() >= int(tuning["week_max"]):
		return {}
	var candidates: Array = []
	for id in sent:
		var entry: Dictionary = sent[id]
		if not bool(entry["replied"]) and String(entry["day"]) < day and now - float(entry["unix"]) <= float(tuning["window_days"]) * DAY_SEC:
			candidates.append(id)
	if not candidates.is_empty() and rng.randf() < float(tuning["reply_chance"]):
		var pick := pick_reply(candidates, now, rng)
		if not pick.is_empty():
			return _deliver(pick["letter"], sent[pick["photo"]], String(pick["photo"]), now, day, choice)
	if rng.randf() < float(tuning["note_chance"]):
		var notes := eligible_notes(now, day)
		if not notes.is_empty():
			var note: Dictionary = notes[rng.randi() % notes.size()]
			if String(note["kind"]) == "season":
				noted_seasons.append(season_key(day))
			return _deliver(note, {}, "", now, day, choice)
	return {}


## The photo whose best letter scores highest (a tie goes to the most recent photo) and, among that
## photo's top letters, one at random. Letters sent in the last repeat_days, and a species' last letter,
## are left out; a photo with nothing left gets no reply. {photo, letter} or {}.
func pick_reply(candidates: Array, now: float, rng: RandomNumberGenerator) -> Dictionary:
	var recent := {}
	for letter in letters:
		if now - float(letter["unix"]) < float(tuning["repeat_days"]) * DAY_SEC:
			recent[String(letter["id"])] = true
	var best_id := ""
	var best_score := -1
	var best_unix := -1.0
	var best_letters: Array = []
	for id in candidates:
		var entry: Dictionary = sent[id]
		var f := facts(entry)
		var top := -1
		var tops: Array = []
		for letter in pool():
			if String(letter.get("kind", "")) != "reply" or recent.has(String(letter["id"])):
				continue
			if entry["species"].any(func(s) -> bool: return String(last_by_species.get(String(s), "")) == String(letter["id"])):
				continue
			var s := score(letter, f)
			if s < 0:
				continue
			if s > top:
				top = s
				tops = [letter]
			elif s == top:
				tops.append(letter)
		if top < 0:
			continue
		if top > best_score or (top == best_score and float(entry["unix"]) > best_unix):
			best_id = String(id)
			best_score = top
			best_unix = float(entry["unix"])
			best_letters = tops
	if best_id == "":
		return {}
	return {"photo": best_id, "letter": best_letters[rng.randi() % best_letters.size()]}


## Notes that may come now: a seasonal note in its season's first season_first_days, once a season;
## a place tip for a place that is there or next to arrive (tip_places). Never within note_gap_days of
## the last note, never a letter sent in the last repeat_days.
func eligible_notes(now: float, day: String) -> Array:
	for letter in letters:
		if String(letter["kind"]) in ["tip", "season"] and now - float(letter["unix"]) < float(tuning["note_gap_days"]) * DAY_SEC:
			return []
	var recent := {}
	for letter in letters:
		if now - float(letter["unix"]) < float(tuning["repeat_days"]) * DAY_SEC:
			recent[String(letter["id"])] = true
	var out: Array = []
	var parts := day.split("-")
	var month := int(parts[1]) if parts.size() == 3 else 0
	var season := ElderLetters.season_of(month, tuning["seasons"])
	for letter in pool():
		if recent.has(String(letter["id"])):
			continue
		var keys: Dictionary = letter.get("keys", {})
		match String(letter.get("kind", "")):
			"season":
				if String(keys.get("season", "")) == season and days_into_season(day) < int(tuning["season_first_days"]) \
						and not noted_seasons.has(season_key(day)) and String(keys.get("place", tuning["place"])) == String(tuning["place"]):
					out.append(letter)
			"tip":
				if (tuning["tip_places"] as Array).has(String(keys.get("place", ""))):
					out.append(letter)
	return out


## Days since the first day of the season `day` ("YYYY-MM-DD") falls in.
func days_into_season(day: String) -> int:
	var parts := day.split("-")
	if parts.size() != 3:
		return 999
	var year := int(parts[0])
	var month := int(parts[1])
	var first := int(tuning["seasons"][ElderLetters.season_of(month, tuning["seasons"])][0])
	var start_year := year if month >= first else year - 1
	var start := Time.get_unix_time_from_datetime_dict({"year": start_year, "month": first, "day": 1})
	var now := Time.get_unix_time_from_datetime_dict({"year": year, "month": month, "day": int(parts[2])})
	return int((now - start) / DAY_SEC)


func season_key(day: String) -> String:
	var parts := day.split("-")
	if parts.size() != 3:
		return ""
	var month := int(parts[1])
	var season := ElderLetters.season_of(month, tuning["seasons"])
	var first := int(tuning["seasons"][season][0])
	return "%d-%s" % [int(parts[0]) if month >= first else int(parts[0]) - 1, season]


func _deliver(letter: Dictionary, photo: Dictionary, photo_id: String, now: float, day: String, choice: Dictionary) -> Dictionary:
	var c := sanitize(choice)
	var out := {
		"id": String(letter["id"]), "kind": String(letter.get("kind", "")),
		"photo": photo_id, "photo_date": String(photo.get("date", "")), "photo_time": String(photo.get("time", "")),
		"unix": now, "day": day, "read": false, "on_log": false,
		"body": fill(String(letter["text"]), c, photo),
		"sign_off": sign_off(c), "name": name_of(c), "elder": String(c["who"]),
	}
	letters.append(out)
	if photo_id != "" and sent.has(photo_id):
		sent[photo_id]["replied"] = true
		for s in sent[photo_id]["species"]:
			last_by_species[String(s)] = String(letter["id"])
	changed.emit()
	return out


# Save --------------------------------------------------------------------------------------------

func to_dict() -> Dictionary:
	return {"sent": sent, "letters": letters, "decided_day": decided_day, "first_given": first_given,
			"last_by_species": last_by_species, "noted_seasons": noted_seasons}


func from_dict(d: Dictionary) -> void:
	sent = {}
	var saved_sent = d.get("sent", {})
	if saved_sent is Dictionary:
		for id in saved_sent:
			var e = saved_sent[id]
			if e is Dictionary and e.has("unix") and e.has("day"):
				sent[String(id)] = {
					"unix": float(e["unix"]), "day": String(e["day"]), "date": String(e.get("date", "")), "time": String(e.get("time", "")),
					"weather": PhotoAlbum.clean_weather(e.get("weather", "")), "species": PhotoAlbum.clean_species(e.get("species", [])),
					"place": String(e.get("place", tuning["place"])), "first_of": PhotoAlbum.clean_species(e.get("first_of", [])),
					"replied": bool(e.get("replied", false)),
				}
	letters = []
	var saved_letters = d.get("letters", [])
	if saved_letters is Array:
		for l in saved_letters:
			if l is Dictionary and l.has("id") and l.has("body") and l.has("unix"):
				letters.append({
					"id": String(l["id"]), "kind": String(l.get("kind", "")), "photo": String(l.get("photo", "")),
					"photo_date": String(l.get("photo_date", "")), "photo_time": String(l.get("photo_time", "")),
					"unix": float(l["unix"]), "day": String(l.get("day", "")), "read": bool(l.get("read", true)),
					"on_log": bool(l.get("on_log", false)), "body": String(l["body"]), "sign_off": String(l.get("sign_off", "")), "name": String(l.get("name", "")),
					"elder": String(l.get("elder", "")),
				})
	# At most one ever waits, whatever an old or edited save says.
	var unread := false
	for l in letters:
		if not bool(l["read"]):
			if unread:
				l["read"] = true
			unread = true
	decided_day = String(d.get("decided_day", ""))
	first_given = bool(d.get("first_given", false))
	last_by_species = d.get("last_by_species", {}) if d.get("last_by_species", {}) is Dictionary else {}
	noted_seasons = d.get("noted_seasons", []) if d.get("noted_seasons", []) is Array else []
