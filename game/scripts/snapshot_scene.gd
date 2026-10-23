class_name SnapshotScene
extends RefCounted

## The living scene in snapshot mode (Skypatch issue 98).
## Each preset (balance `scene.clips.presets`: a time of day, a weather phase, a seed, and maybe
## wet ground, fog or a faster front) builds the scene afresh and drives it frame by frame, so the
## same preset always gives the same pictures.
##
## `scene` path: a still of every preset after a few seconds, with checks (the kit loaded, the
## avatar on the log, rain falling in the rain, mist at dawn, a landing that dips its perch).
## `clip` path (`just snap-clip <name> [seconds]`): one preset, every frame saved as
## `<out>/frames/00001.png` over the desktop colour, for ffmpeg to make an MP4 at real size.

const CLIP_ENV := "VIBENATURE_CLIP"
const SECONDS_ENV := "VIBENATURE_CLIP_SECONDS"
## A recorded timeline for the clip's preset (issue 475, `just screencast`): see `with_timeline`.
const TIMELINE_ENV := "VIBENATURE_CLIP_TIMELINE"

var s: Snapshot
var game: Game
var clips: Dictionary = {}


func _init(owner: Snapshot) -> void:
	s = owner
	game = owner.game
	clips = SnapshotScene.with_timeline(game.balance.data["scene"]["clips"], OS.get_environment(CLIP_ENV),
			OS.get_environment(TIMELINE_ENV))


## `clips` with one preset's timeline read from a JSON file (issue 475):
## `{"events": [...], "seed": n, "skip": [[from, to]], "save_every": n}`, each key optional. The screencast records a
## real Claude Code session's hook events and plays them here at the times they came. A copy: the balance data is
## never changed. No file, an unknown preset or a file that is not a JSON object: `clips` as it was.
static func with_timeline(all: Dictionary, name: String, path: String) -> Dictionary:
	if path == "" or not all["presets"].has(name) or not FileAccess.file_exists(path):
		return all
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not data is Dictionary:
		return all
	var out := all.duplicate(true)
	if data.has("events"):
		var events: Array = (data["events"] as Array).duplicate(true)
		events.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["at"]) < float(b["at"]))
		if not out.has("events"):
			out["events"] = {}
		out["events"][name] = events
	for key in ["seed", "skip", "save_every"]:
		if data.has(key):
			out["presets"][name][key] = data[key]
	return out


func run(path: String) -> void:
	Pace.start_moving()
	if path == "clip":
		await _clip()
	else:
		await _stills()
	Pace.stop_moving()


## A fresh scene for `name`, replacing the game's, at the preset's time and weather.
func build(name: String) -> LivingScene:
	var preset: Dictionary = clips["presets"][name]
	var old := game.scene
	var scene := LivingScene.new()
	# A preset may wear another look ("avatar": a look id, its default colours), e.g. a departure in look06.
	var look: Dictionary = AvatarLook.look_defaults(String(preset["avatar"])) if preset.has("avatar") else game.avatar_look()
	scene.sitter.composed = AvatarLook.sheet(look)
	scene.avatar_look = look
	# A preset may paint the van ("van": {body, accent}, issue 279); otherwise the saved paint.
	scene.van.paint = preset.get("van", game.van_paint())
	var tuning: Dictionary = game.balance.data["scene"]
	scene.setup(tuning, game.settings.day_phases(), Game.scene_point_scale(true, 2.0),
			Avatar.resolve_id(String(game.settings.data["avatar_id"]), Avatar.choices(game.balance.data["placeholders"])),
			int(preset.get("seed", tuning["seed"])))
	scene.manual = true
	scene.set_random_visits(false)
	game.add_child(scene)
	scene.position = old.position if old != null else Vector2i.ZERO
	if old != null:
		old.queue_free()
	game.scene = scene
	# The desktop the scene sits in, for desktop flights: a screen of `desktop.screen_pt` with
	# the scene in its bottom-right corner (the clip draws it; nothing reaches the real screen).
	var desktop: Dictionary = preset.get("desktop", clips.get("desktop", {}))
	if not desktop.is_empty():
		scene.flights.desktop_rect = func() -> Rect2: return SnapshotScene.desktop_of(scene, desktop)
	scene.start()
	SnapshotScene.apply(scene, preset, clips)
	scene.advance(0.0, scene.minute)
	return scene


## The clip's desktop in screen units: `screen_pt` points with the scene flush in its bottom-right corner.
static func desktop_of(scene: LivingScene, desktop: Dictionary) -> Rect2:
	var screen := Vector2(float(desktop["screen_pt"][0]), float(desktop["screen_pt"][1])) * scene.scale_px
	return Rect2(Vector2(scene.position + scene.size) - screen, screen)


## Puts a built scene at a preset's time, weather, wind and director state (the clip path and
## the behaviour probe share it, so a probe of a preset is the clip without the pictures).
static func apply(scene: LivingScene, preset: Dictionary, clips: Dictionary) -> void:
	scene.minute = float(DayPhases.minutes(String(preset["time"])))
	scene.env.force_weather(String(preset["weather"]))
	if preset.has("wet"):
		scene.env.weather.wet = float(preset["wet"])
	if preset.has("fog"):
		scene.env.overrides["fog"] = float(preset["fog"])
	# A preset may hold the wind where it wants it (a sustained blow, a still dawn); its own copy
	# of the weather's tuning, so the balance data is never changed.
	scene.env.weather.tuning = scene.env.weather.tuning.duplicate(true)
	if preset.has("wind_mean"):
		scene.env.weather.wind = float(preset["wind_mean"])
		scene.env.weather.tuning["phases"][String(preset["weather"])]["wind"] = float(preset["wind_mean"])
	if preset.has("gusts_per_min"):
		scene.env.weather.gusts_per_min = float(preset["gusts_per_min"])
		scene.env.weather.tuning["phases"][String(preset["weather"])]["gusts_per_min"] = float(preset["gusts_per_min"])
	if preset.has("gust"):
		scene.env.weather.gust_range = Vector2(float(preset["gust"][0]), float(preset["gust"][1]))
		scene.env.weather.tuning["phases"][String(preset["weather"])]["gust"] = preset["gust"]
	scene.env.force_wind_now()
	if preset.has("front_every_sec"):
		scene.env.weather_speed = float(preset.get("weather_speed", 60.0))
	# Clouds at 10× (Skypatch issue 146): they drift and change faster.
	scene.env.cloud_speed = float(preset.get("cloud_speed", 1.0))
	# The behaviour presets run the director from the preset's seed, on the scene's own clock.
	var behaviour: Variant = preset.get("behaviour", null)
	scene.set_random_visits(behaviour is Dictionary)
	scene.behaviour.unix_clock = func() -> float: return float(clips["unix_base"]) + scene.behaviour.t
	scene.behaviour.month_override = int(preset.get("month", 0))
	if behaviour is Dictionary:
		if behaviour.has("quiet_for"):
			scene.behaviour.director.quiet_for = float(behaviour["quiet_for"])
		if behaviour.has("hold"):
			scene.behaviour.director.hold = float(behaviour["hold"])


## Runs `seconds` of `name` at the clip rate; `each_frame` is awaited after every frame.
func play(scene: LivingScene, name: String, seconds: float, each_frame: Callable = Callable()) -> void:
	var preset: Dictionary = clips["presets"][name]
	var fps := float(clips["fps"])
	var dt := 1.0 / fps
	var frames := int(round(seconds * fps))
	var events: Array = clips.get("events", {}).get(name, []).duplicate()
	var order: Array = scene.env.weather.order()
	var front_every := float(preset.get("front_every_sec", 0.0))
	var start_minute := scene.minute
	var minutes_per_sec := float(preset.get("minutes_per_sec", 0.0))
	for i in frames:
		var at := float(i) * dt
		while not events.is_empty() and float(events[0]["at"]) <= at:
			var e: Dictionary = events.pop_front()
			SnapshotScene.event(scene, e)
			if e.has("flight") and scene.flights.flying():
				_record_flight_level(scene, String(e["flight"]))
		if front_every > 0.0 and i > 0 and int(at / front_every) != int((at - dt) / front_every):
			var next := String(order[(order.find(scene.env.weather.phase) + 1) % order.size()])
			scene.env.weather.enter(next, true)
		scene.advance(dt, start_minute + at * minutes_per_sec)
		if each_frame.is_valid():
			await each_frame.call(i)
		elif i % 10 == 9:
			await game.get_tree().process_frame


## The level a started flight's window asks the native extension for (issue 235): above other
## windows even with the scene behind them. Recorded in report.json `notes.flight_window`.
func _record_flight_level(scene: LivingScene, kind: String) -> void:
	var w := scene.flights.transit
	var asked := {"title": w.title if w != null else "", "always_on_top": w != null and w.always_on_top,
			"scene_on_top": scene.always_on_top}
	s.notes["flight_window"] = asked
	s._expect(w != null and w.title == TransitWindow.OVERLAY_TITLE and w.always_on_top,
			"desktop flight %s: the flight window asks for the overlay level (%s)" % [kind, asked])


static func event(scene: LivingScene, e: Dictionary) -> void:
	if e.has("day"):
		scene.day(String(e["day"]))
	# A letter due on the log (issue 270): read at the end of the first rest once you sit.
	if e.has("letter"):
		scene.letter_due = bool(e["letter"])
	if e.has("bird"):
		var wanted := String(e.get("perch", ""))
		for perch in scene.perches():
			if wanted == "" or String(perch["piece"]) == wanted:
				scene.visitors.visit(String(e["bird"]), perch, float(e.get("stay_sec", 8.0)))
				return
	if e.has("gust"):
		scene.env.wind.spawn_gust(float(e["gust"]))
	if e.has("turn"):
		if String(e["turn"]) == "start":
			# `with_van`: this turn brought the van (with a `day` "arrive"), as the game passes it (issue 239).
			scene.behaviour.turn_started(bool(e.get("with_van", false)))
		else:
			scene.behaviour.turn_ended()
	if e.has("lineup"):
		scene.behaviour.lineup()
	if e.has("spawn"):
		# A clip may name which of the songbirds comes (the species data's `cast`).
		scene.behaviour.next_cast = String(e.get("cast", ""))
		scene.behaviour.next_entrance = String(e.get("entrance", ""))
		# And which of the heron's approaches it glides in on (issue 272).
		scene.behaviour.next_approach = String(e.get("approach", ""))
		# And which natural group comes (issue 320: a `herd` kind's id).
		scene.behaviour.next_herd = String(e.get("herd", ""))
		# And which bask spot a turtle climbs onto (issue 334: an index into the places' `bask`).
		scene.behaviour.next_bask = int(e.get("bask", -1))
		scene.behaviour.spawn(String(e["spawn"]), "debug", String(e.get("habitat", "")))
		if e.has("z") and not scene.behaviour.creatures.is_empty():
			# And how far back in the cut-away a fish comes (0 the glass, 1 the murk; issue 340).
			var fish: SceneCreature = scene.behaviour.creatures[-1]
			if fish.sp.body == "fish":
				fish.depth_z = float(e["z"])
				fish._z_target = fish.depth_z
		# And where the party lands (`land_on`, a piece-id prefix), how long it stays, and how it
		# leaves (`leave`: "trees").
		if not scene.behaviour.flocks.is_empty() and (e.has("land_on") or e.has("leave") or e.has("stay_sec")):
			var flock: SceneFlock = scene.behaviour.flocks[-1]
			flock.prefer = String(e.get("land_on", ""))
			flock._land = flock._land or e.has("land_on")
			flock.leave = String(e.get("leave", ""))
			flock.stay = float(e.get("stay_sec", flock.stay))
		# And grass to drop to only near his feet (`ground_near`: [from, to] points either side of the seat; issue 123).
		if not scene.behaviour.flocks.is_empty() and e.has("ground_near"):
			var party: SceneFlock = scene.behaviour.flocks[-1]
			var r: Array = e["ground_near"]
			var grounds: Array = []
			for g in scene.behaviour.flock_grounds():
				if String(g["area"]) == "near_bank":
					var y: float = (g["from"] as Vector2).y
					grounds.append({"from": Vector2(scene.sitter.seat.x + float(r[0]), y), "to": Vector2(scene.sitter.seat.x + float(r[1]), y),
							"band": g["band"], "weight": 1.0, "area": g["area"]})
			if not grounds.is_empty():
				party._grounds = grounds
				party.cfg = party.cfg.duplicate()
				party.cfg["ground_share"] = 1.0
				party.member = party.member.duplicate()
				party.member["ground_share"] = 1.0
	# The sitter starts an idle activity now (issue 123: "thermos", "paperback", "glance_down", ...).
	if e.has("sitter"):
		scene.sitter.act(String(e["sitter"]))
	if e.has("drop"):
		scene.drops.drop(String(e["drop"]))
	if e.has("act"):
		# A clip may have one animal do something now (a bluegill's rise with `leap`).
		for c in scene.behaviour.creatures:
			if c.sp.id == String(e.get("who", "")) and c.state in ["arriving", "living"] and c.leader == null:
				c.beats.clear()
				c.beat = {}
				c.state = "living"
				# Its group sees what it is doing (a fawn comes down to drink beside its mother, issue 320).
				c.activity = String(e["act"])
				c.call("_do_" + String(e["act"]), e)
				break
	if e.has("hawk"):
		# The hawk pass now (issue 311): from which side, out across or away, if given.
		var hawk := {}
		for key in ["side", "exit", "perch", "stay"]:
			if e.has(key):
				hawk[key] = e[key]
		scene.behaviour.hawk_pass.next = hawk
		if not scene.behaviour.hawk_pass.start():
			scene.behaviour.hawk_pass.next = {}
			scene.behaviour.note("hawk pass: no small birds to scatter")
	if e.has("geese"):
		# Geese landing now (issue 356): how many, which way in, how they leave and how long they stay, if given.
		var pin := {}
		for key in ["n", "family", "leave", "stay", "dir"]:
			if e.has(key):
				pin[key] = e[key]
		scene.behaviour.geese.next = pin
		if not scene.behaviour.geese.start():
			scene.behaviour.geese.next = {}
			scene.behaviour.note("geese: no landing")
	if e.has("osprey"):
		# The osprey's dive now (issue 362): catch, miss or abort, one or two hovers, the side it comes in from, if given.
		var pin := {}
		for key in ["outcome", "hovers", "side"]:
			if e.has(key):
				pin[key] = e[key]
		scene.behaviour.osprey.next = pin
		if not scene.behaviour.osprey.start():
			scene.behaviour.osprey.next = {}
			scene.behaviour.note("osprey: no dive")
	if e.has("kingfisher"):
		# The kingfisher now (issue 364): the side it comes in from, each dive's mode and outcome, the twig, if given.
		var pin := {}
		for key in ["side", "modes", "outcomes", "perch"]:
			if e.has(key):
				pin[key] = e[key]
		scene.behaviour.kingfisher.next = pin
		if not scene.behaviour.kingfisher.start():
			scene.behaviour.kingfisher.next = {}
			scene.behaviour.note("kingfisher: no hunt")
	if e.has("beaver"):
		# The beaver now (issue 366): cross or slap, the way it swims, if given.
		var pin := {}
		for key in ["kind", "dir"]:
			if e.has(key):
				pin[key] = e[key]
		scene.behaviour.beaver.next = pin
		if not scene.behaviour.beaver.start():
			scene.behaviour.beaver.next = {}
			scene.behaviour.note("beaver: no swim")
	if e.has("otters"):
		# River otters now (issue 368): porpoise or slide, how many, which way, a catch eaten on the bank.
		var pin := {}
		for key in ["kind", "n", "dir", "bank"]:
			if e.has(key):
				pin[key] = e[key]
		scene.behaviour.otters.next = pin
		if not scene.behaviour.otters.start():
			scene.behaviour.otters.next = {}
			scene.behaviour.note("otters: none")
	if e.has("deer"):
		# The deer moment now (issue 372): bound in or startle, strip or meadow, the group, which way, how out.
		var pin := {}
		for key in ["kind", "stage", "herd", "dir", "exit"]:
			if e.has(key):
				pin[key] = e[key]
		scene.behaviour.deer_bound.next = pin
		if not scene.behaviour.deer_bound.start():
			scene.behaviour.deer_bound.next = {}
			scene.behaviour.note("deer: none")
	if e.has("swallows"):
		# Tree swallows now (issue 374): how many, from which side, out which side, how many perch, how long.
		var pin := {}
		for key in ["n", "side", "leave", "perch", "hawk_sec", "all_beats"]:
			if e.has(key):
				pin[key] = e[key]
		scene.behaviour.swallows.next = pin
		if not scene.behaviour.swallows.start():
			scene.behaviour.swallows.next = {}
			scene.behaviour.note("swallows: none")
	if e.has("hatch"):
		# The mayfly hatch now (issue 376): a bass breaking clear, where the dance is, if given.
		var pin := {}
		for key in ["leap", "swarm_u"]:
			if e.has(key):
				pin[key] = e[key]
		scene.behaviour.hatch.next = pin
		if not scene.behaviour.hatch.start():
			scene.behaviour.hatch.next = {}
			scene.behaviour.note("hatch: none")
	if e.has("ducks"):
		# Wood ducks now (issue 378): the pair or the brood, from which side, how they leave, how long, how many.
		var pin := {}
		for key in ["kind", "side", "leave", "stay", "out", "n"]:
			if e.has(key):
				pin[key] = e[key]
		scene.behaviour.wood_ducks.next = pin
		if not scene.behaviour.wood_ducks.start(String(e.get("kind", "pair"))):
			scene.behaviour.wood_ducks.next = {}
			scene.behaviour.note("wood ducks: none")
	if e.has("turtles"):
		# Painted turtles (issue 370): `place` puts n basking on the snag now (true: the seed's count), `plop` sends them off.
		if e.has("place"):
			scene.behaviour.turtles.place(0 if e["place"] is bool else int(e["place"]))
		if bool(e.get("plop", false)) and not scene.behaviour.turtles.start():
			scene.behaviour.note("turtles: none to plop")
	if e.has("starlings"):
		# A starling murmuration now (issue 380): how many, from which side, how long, how many drops and streams.
		var pin := {}
		for key in ["n", "side", "display_sec", "drops", "streams", "force"]:
			if e.has(key):
				pin[key] = e[key]
		scene.behaviour.starlings.next = pin
		if not scene.behaviour.starlings.start():
			scene.behaviour.starlings.next = {}
			scene.behaviour.note("starlings: none")
	if e.has("gust_sweep") or e.has("shower"):
		# A weather beat now (issue 380): the gust (strength, after-gusts) or the shower (bow, its timings, `speed`).
		var pin := {"force": true}
		for key in ["strength", "after", "bow", "close_sec", "rain_sec", "peak"]:
			if e.has(key):
				pin[key] = e[key]
		var wb = scene.behaviour.weather_beats if e.has("gust_sweep") else scene.behaviour.shower_beats
		wb.speed = float(e.get("speed", 1.0))
		wb.next = pin
		var ok = wb.start_gust() if e.has("gust_sweep") else wb.start_shower()
		if not ok:
			scene.behaviour.note("weather beat: none")
	if e.get("leap") is String:
		# The bass leap now (issue 299): which bass, and catch or miss, head-first or slap if given.
		# Only a named leaper: a rise's or a hatch's `leap` is a bool, theirs (issue 473).
		var pin := {"who": String(e["leap"])}
		for key in ["catch", "slap"]:
			if e.has(key):
				pin[key] = bool(e[key])
		scene.behaviour.bass_leap.next = pin
		if not scene.behaviour.bass_leap.start():
			scene.behaviour.bass_leap.next = {}
			scene.behaviour.note("bass leap: nobody to leap")
	if e.has("flight"):
		# A clip may pick the flight's shape, its company and which songbird goes.
		scene.flights.next = {"shape": String(e.get("shape", "")), "company": String(e.get("company", "")), "who": String(e.get("who", ""))}
		if not scene.flights.start(String(e["flight"])):
			scene.behaviour.note("desktop flight %s: nobody to fly" % e["flight"])


func _stills() -> void:
	var names: Array = clips["presets"].keys()
	for name in names:
		var scene := build(String(name))
		s._expect(scene.kit.problems().is_empty(), "%s: the scene kit loads cleanly (%s)" % [name, ", ".join(scene.kit.problems())])
		s._expect(scene.sitter.ok, "%s: the avatar sits on the log" % name)
		s._expect(scene.sway.entries.size() >= 4, "%s: the pieces sway (%d)" % [name, scene.sway.entries.size()])
		await play(scene, String(name), 4.0)
		await game.get_tree().process_frame
		match String(name):
			"rain":
				s._expect(scene.env.rain > 0.9 and scene.water_fx.rings.size() > 5,
						"rain: it rains and rings open on the water (%d rings)" % scene.water_fx.rings.size())
			"dawn_mist":
				s._expect(scene.env.mist > 0.3, "dawn_mist: mist lies on the water (%.2f)" % scene.env.mist)
			"gusty":
				s._expect(scene.env.wind.mean > 0.4 and not scene.env.wind.gusts.is_empty(), "gusty: the wind is up and gusts cross (%.2f)" % scene.env.wind.mean)
			"calm":
				s._expect(scene.visitors.birds.size() == 1, "calm: a bird comes to the reeds")
			"wind":
				var reeds := scene.sway.bend_at("reeds", scene.size_pt.x - 100.0) if scene.sway.entries.has("reeds") else Vector2.ZERO
				s._expect(absf(reeds.x) > 0.5, "wind: the reeds lean (%.2f pt)" % reeds.x)
			"fog":
				s._expect(scene.env.fog > 0.5, "fog: the fog is in (%.2f)" % scene.env.fog)
		await s._capture("scene_" + String(name))


func _clip() -> void:
	var name := OS.get_environment(CLIP_ENV)
	if not clips["presets"].has(name):
		s._expect(false, "the clip %s is one of %s" % [name, clips["presets"].keys()])
		return
	var seconds := float(OS.get_environment(SECONDS_ENV)) if OS.get_environment(SECONDS_ENV) != "" else float(clips["default_seconds"])
	var scene := build(name)
	s._expect(scene.kit.problems().is_empty(), "the scene kit loads cleanly (%s)" % ", ".join(scene.kit.problems()))
	var frames_dir := s.out_dir.path_join("frames")
	DirAccess.make_dir_recursive_absolute(frames_dir)
	for old in DirAccess.get_files_at(frames_dir):
		DirAccess.remove_absolute(frames_dir.path_join(old))
	var preset: Dictionary = clips["presets"][name]
	# A preset may keep the frames transparent ("00000000"), to lay them over real desktops after.
	var background := Color(String(preset.get("background", clips["background"])))
	var every := maxi(1, int(preset.get("save_every", 1)))
	var out_scale := float(preset.get("out_scale", 1.0))
	var saved := [0]
	# PNGs are written on worker threads, a few at a time, while the next frames draw.
	var pending: Array = []
	# A preset may cut stretches out of the clip ("skip": [[from, to] seconds]): the scene still runs through them.
	var skip: Array = preset.get("skip", [])
	var fps := float(clips["fps"])
	# When the sitter changes what it does (standing, resting, reading...), to place a preset's cuts.
	var modes: Array = []
	await play(scene, name, seconds, func(i: int) -> void:
		var mode := "standing" if scene.sitter.standing() else "%s %s" % [scene.sitter.doing(), scene.sitter.step_anim()]
		if modes.is_empty() or String(modes[-1][1]) != mode:
			modes.append([snappedf(float(i) / fps, 0.1), mode])
		var cut := false
		for span in skip:
			cut = cut or (float(i) / fps >= float(span[0]) and float(i) / fps < float(span[1]))
		if i % every != 0 or cut:
			if i % 30 == 29:
				await game.get_tree().process_frame
			return
		await game.get_tree().process_frame
		if not s._rendered:
			return
		WindowChrome.redraw(scene)
		RenderingServer.force_draw(false)
		var image := scene.get_texture().get_image()
		if image == null or image.is_empty():
			return
		image.convert(Image.FORMAT_RGBA8)
		var out: Image
		if preset.has("desktop"):
			out = _desktop_frame(scene, image, preset["desktop"], background)
		else:
			out = Image.create_empty(image.get_width(), image.get_height(), false, Image.FORMAT_RGBA8)
			out.fill(background)
			out.blend_rect(image, Rect2i(Vector2i.ZERO, image.get_size()), Vector2i.ZERO)
		var file := frames_dir.path_join("%05d.png" % (saved[0] + 1))
		pending.append(WorkerThreadPool.add_task(func() -> void:
			if out_scale != 1.0:
				out.resize(int(out.get_width() * out_scale), int(out.get_height() * out_scale), Image.INTERPOLATE_LANCZOS)
			out.save_png(file)))
		while pending.size() > 6:
			WorkerThreadPool.wait_for_task_completion(pending.pop_front())
		saved[0] += 1)
	for task in pending:
		WorkerThreadPool.wait_for_task_completion(task)
	s.notes["clip"] = {"name": name, "seconds": seconds, "fps": clips["fps"], "frames": saved[0], "summary": scene.env.summary(),
			"save_every": every, "sitter": modes, "behaviour": scene.behaviour.events.map(func(e: Dictionary) -> String: return "%7.1f  %s" % [float(e["t"]), e["what"]])}
	s._expect(not s._rendered or saved[0] > 0, "the clip saved its frames (%d)" % saved[0])
	await s._capture("clip_" + name + "_last")


## A frame of the whole desktop: the desktop colour, the scene in its corner, and the flight's
## transit window where it is, as the player would see them.
func _desktop_frame(scene: LivingScene, scene_image: Image, desktop: Dictionary, background: Color) -> Image:
	var rect := SnapshotScene.desktop_of(scene, desktop)
	var out := Image.create_empty(int(rect.size.x), int(rect.size.y), false, Image.FORMAT_RGBA8)
	out.fill(Color(String(desktop.get("color", background.to_html(false)))))
	out.blend_rect(scene_image, Rect2i(Vector2i.ZERO, scene_image.get_size()), Vector2i(Vector2(scene.position) - rect.position))
	var transit := scene.flights.transit
	if transit != null and scene.flights.flying() and String(scene.flights.active["where"]) == "desktop":
		var bird := transit.get_texture().get_image()
		if bird != null and not bird.is_empty():
			bird.convert(Image.FORMAT_RGBA8)
			out.blend_rect(bird, Rect2i(Vector2i.ZERO, bird.get_size()), Vector2i(Vector2(transit.position) - rect.position))
	return out
