class_name EventServer
extends Node

## The agent bridge's door (contract §2): HTTP on 127.0.0.1 only, `POST /event` with a body
## AgentEvent accepts. Anything else gets a bare 400 and is forgotten: only the `rejected`
## counter remembers it. Accepted events go out on `event_received` and are kept nowhere.
## Battery (§2.8): connections are checked on a timer (`poll_sec`), never every frame. A hook
## that gives up waiting still delivers: its request sits in the socket until the next check.

signal event_received(event: Dictionary)

const OK_RESPONSE := "HTTP/1.1 204 No Content\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"
const BAD_RESPONSE := "HTTP/1.1 400 Bad Request\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"

var accepted := 0
var rejected := 0
var tuning: Dictionary = {}
var _server := TCPServer.new()
## [{"peer": StreamPeerTCP, "data": PackedByteArray, "since": msec}]
var _open: Array = []
var _timer := Timer.new()


## Listens on 127.0.0.1:`port` (0: any free port, for tests and snapshots). False if it cannot.
func start(port: int, bridge_tuning: Dictionary) -> bool:
	tuning = bridge_tuning
	if _server.listen(port, "127.0.0.1") != OK:
		print("VibeNature: the event server cannot listen on 127.0.0.1:%d; agent activity will not reach the game" % port)
		return false
	_timer.wait_time = float(tuning["poll_sec"])
	if not _timer.timeout.is_connected(_poll):
		_timer.timeout.connect(_poll)
	if _timer.get_parent() == null:
		add_child(_timer)
	_timer.start()
	return true


func port() -> int:
	return _server.get_local_port() if _server.is_listening() else 0


func listening() -> bool:
	return _server.is_listening()


func stop() -> void:
	_timer.stop()
	for c in _open:
		(c["peer"] as StreamPeerTCP).disconnect_from_host()
	_open.clear()
	_server.stop()


func _exit_tree() -> void:
	stop()


func _poll() -> void:
	var now := Time.get_ticks_msec()
	while _server.is_connection_available():
		var peer := _server.take_connection()
		if _open.size() >= int(tuning["max_connections"]):
			peer.disconnect_from_host()
			rejected += 1
			continue
		_open.append({"peer": peer, "data": PackedByteArray(), "since": now})
	for c in _open.duplicate():
		if _advance(c, now):
			_open.erase(c)


## Reads what has arrived; answers and closes once the request is whole or broken. True when
## the connection is finished with.
func _advance(c: Dictionary, now: int) -> bool:
	var peer: StreamPeerTCP = c["peer"]
	peer.poll()
	var max_header := int(tuning["max_header_bytes"])
	var limit := max_header + AgentEvent.MAX_BYTES
	var data: PackedByteArray = c["data"]
	var available := peer.get_available_bytes()
	if available > 0:
		var got: Array = peer.get_partial_data(mini(available, limit + 1 - data.size()))
		if got[0] == OK:
			data.append_array(got[1])
			c["data"] = data
	var verdict = EventServer.read_request(data, max_header)
	if verdict is Dictionary:
		if (verdict as Dictionary).is_empty():
			return _answer(peer, false)
		accepted += 1
		_answer(peer, true)
		event_received.emit(verdict)
		return true
	var timed_out := now - int(c["since"]) > int(float(tuning["connection_timeout_sec"]) * 1000.0)
	if timed_out or peer.get_status() != StreamPeerTCP.STATUS_CONNECTED:
		peer.disconnect_from_host()
		return true
	return false


func _answer(peer: StreamPeerTCP, ok: bool) -> bool:
	if not ok:
		rejected += 1
	peer.put_data((OK_RESPONSE if ok else BAD_RESPONSE).to_ascii_buffer())
	peer.disconnect_from_host()
	return true


## What a request so far amounts to: the event (a non-empty Dictionary), a refusal ({}), or
## null while more bytes are needed. Pure, for tests.
static func read_request(data: PackedByteArray, max_header: int):
	var end := _find_header_end(data)
	if end < 0:
		return {} if data.size() > max_header else null
	if end > max_header:
		return {}
	var lines := data.slice(0, end).get_string_from_ascii().split("\r\n")
	var request := lines[0].split(" ")
	if request.size() != 3 or request[0] != "POST" or request[1] != "/event" or not request[2] in ["HTTP/1.1", "HTTP/1.0"]:
		return {}
	var length := -1
	for i in range(1, lines.size()):
		var colon := lines[i].find(":")
		if colon > 0 and lines[i].substr(0, colon).strip_edges().to_lower() == "content-length":
			var value := lines[i].substr(colon + 1).strip_edges()
			if not value.is_valid_int() or length >= 0:
				return {}
			length = int(value)
	if length <= 0 or length > AgentEvent.MAX_BYTES:
		return {}
	var body := data.slice(end + 4)
	if body.size() < length:
		return null
	if body.size() > length:
		return {}
	return AgentEvent.parse(body)


static func _find_header_end(data: PackedByteArray) -> int:
	for i in range(0, data.size() - 3):
		if data[i] == 13 and data[i + 1] == 10 and data[i + 2] == 13 and data[i + 3] == 10:
			return i
	return -1
