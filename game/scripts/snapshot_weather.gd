class_name SnapshotWeather
extends RefCounted

## The weather path of snapshot mode (`just snap-weather`, issue 81): after the first launch,
## contract §2 events are posted over real HTTP to the game's own event server (on a free
## port, never 47474) as two Claude Code sessions would send them, and the sky is captured as
## it changes: clear, golden window (both busy), sun (a turn ended), clouds (failed tools),
## rain. Bodies that break the contract are posted too, and must change nothing.

const A := "a1b2c3d4e5f60718"
const B := "0f1e2d3c4b5a6978"

var s: Snapshot
var game: Game
var _index := 10


func _init(owner: Snapshot) -> void:
	s = owner
	game = owner.game


func run() -> void:
	var port := game.bridge.server.port()
	s._expect(game.bridge.server.listening() and port != 47474, "the event server listens on 127.0.0.1, on its own port (%d)" % port)
	_expect_sky({"sun": false, "clouds": 0, "rain": false, "golden": false}, "a clear sky before any agent")
	await _shot("weather_clear")

	for event in [["session_start", A], ["session_start", B], ["turn_start", A], ["turn_start", B]]:
		await _post_event(event[0], event[1])
	s._expect(game.signals.is_golden(), "two sessions, both busy: the golden window opens")
	_expect_sky({"sun": false, "clouds": 0, "rain": false, "golden": true}, "golden sparkles over every island")
	await _shot("weather_golden")

	await _post_event("turn_end", A)
	s._expect(not game.signals.is_golden(), "a turn ends: not every session is busy, the golden window closes")
	s._expect(game.weather.sunlight_today == 1, "a finished turn is one sunlight (got %d)" % game.weather.sunlight_today)
	_expect_sky({"sun": true, "clouds": 0, "rain": false, "golden": false}, "the sun comes out")
	await _shot("weather_sun")

	var threshold := int(game.balance.data["rain_clouds_threshold"])
	for i in threshold - 1:
		await _post_event("tool_fail", B)
	_expect_sky({"sun": true, "clouds": threshold - 1, "rain": false, "golden": false}, "failed tools gather clouds")
	await _shot("weather_clouds")

	await _post_event("tool_fail", B)
	s._expect(game.weather.raining, "the %dth failed tool brings rain" % threshold)
	_expect_sky({"sun": false, "clouds": int(game.balance.data["sky"]["rain_clouds"]), "rain": true, "golden": false}, "rain falls; the sun hides")
	await _shot("weather_rain")
	await s._settle()
	await _shot("weather_rain_falling")

	var before := _world()
	var refused := game.bridge.server.rejected
	var bad := [
		'{"kind":"turn_end","source":"claude_code","session_hash":"%s","ts":1,"prompt":"fix the billing bug"}' % A,
		'{"kind":"turn_end","source":"claude_code","session_hash":"%s"}' % A,
		'{"kind":"reboot","source":"claude_code","session_hash":"%s","ts":1}' % A,
		'{"kind":"turn_end","source":"claude_code","session_hash":"/Users/x/acme","ts":1}',
		'{"kind":"turn_end","source":"claude_code","session_hash":"%s","ts":1}%s' % [A, " ".repeat(600)],
	]
	for body in bad:
		var status := await _post(body)
		s._expect(status == 400, "a body that breaks contract §2 gets 400 (got %d): %s" % [status, body.left(60)])
	s._expect(game.bridge.server.rejected == refused + bad.size(), "each refusal is counted (%d)" % (game.bridge.server.rejected - refused))
	s._expect(_world() == before, "refused bodies change nothing (%s, then %s)" % [before, _world()])

	await _post_event("session_end", A)
	await _post_event("session_end", B)
	s._expect(game.bridge.sessions.sessions.is_empty(), "both sessions ended: none tracked")
	s.notes["bridge"] = {"accepted": game.bridge.server.accepted, "rejected": game.bridge.server.rejected,
			"sunlight_today": game.weather.sunlight_today, "raining": game.weather.raining}
	s.notes["save_has_no_session_hash"] = not JSON.stringify(_save_text()).contains(A)
	s._expect(bool(s.notes["save_has_no_session_hash"]), "no session hash reaches the save")


func _world() -> Dictionary:
	return {"sessions": game.bridge.sessions.sessions.size(), "sunlight": game.weather.sunlight_today,
			"clouds": game.weather.clouds, "raining": game.weather.raining, "golden": game.signals.is_golden()}


func _save_text() -> String:
	game.save_now()
	return FileAccess.get_file_as_string(game.save_game.path)


func _expect_sky(wanted: Dictionary, what: String) -> void:
	for patch in game.patches:
		var sky := _sky(patch)
		s._expect(sky != null and sky.state() == wanted, "%s: %s (got %s)" % [patch.def.id, what, sky.state() if sky != null else "no sky"])


static func _sky(patch: PatchWindow) -> SkyOverlay:
	for child in patch.overlay().get_children():
		if child is SkyOverlay:
			return child
	return null


func _shot(what: String) -> void:
	await s._settle()
	await s._capture("%02d_%s" % [_index, what])
	_index += 1


func _post_event(kind: String, session: String) -> void:
	var body := JSON.stringify({"kind": kind, "source": "claude_code", "session_hash": session, "ts": int(Time.get_unix_time_from_system())})
	var status := await _post(body)
	s._expect(status == 204, "%s is accepted (got %d)" % [kind, status])


## POSTs `body` to the game's event server as the hook's curl would; the HTTP status, or 0.
func _post(body: String) -> int:
	var bytes := body.to_utf8_buffer()
	var request := "POST /event HTTP/1.1\r\nHost: 127.0.0.1\r\nContent-Type: application/json\r\nContent-Length: %d\r\n\r\n" % bytes.size()
	var peer := StreamPeerTCP.new()
	if peer.connect_to_host("127.0.0.1", game.bridge.server.port()) != OK:
		return 0
	var tree := game.get_tree()
	var left := 2.0
	while peer.get_status() == StreamPeerTCP.STATUS_CONNECTING and left > 0.0:
		await tree.create_timer(0.02).timeout
		left -= 0.02
		peer.poll()
	var data := request.to_ascii_buffer()
	data.append_array(bytes)
	peer.put_data(data)
	var reply := PackedByteArray()
	while left > 0.0:
		await tree.create_timer(0.02).timeout
		left -= 0.02
		peer.poll()
		var available := peer.get_available_bytes()
		if available > 0:
			reply.append_array(peer.get_data(available)[1])
		if reply.size() >= 12 or peer.get_status() != StreamPeerTCP.STATUS_CONNECTED:
			break
	peer.disconnect_from_host()
	var text := reply.get_string_from_ascii()
	return int(text.substr(9, 3)) if text.begins_with("HTTP/1.1 ") else 0
