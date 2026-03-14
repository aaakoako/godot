## EventOutbox: in-memory event log for UI and other sources.
## Godot only emits events; no game logic. MCP get_event_log reads from here.
extends Node

const MAX_EVENTS: int = 500

var _events: Array = []
var _seq: int = 0


## Append one event. source, type, entity_id, payload (dict).
func append_event(source: String, event_type: String, entity_id: String, payload: Dictionary = {}) -> void:
	_seq += 1
	var ts_ms: int = int(Time.get_unix_time_from_system() * 1000.0)
	var event_id: String = "evt_%d_%d" % [ts_ms, _seq]
	var ev: Dictionary = {
		"seq": _seq,
		"event_id": event_id,
		"ts_ms": ts_ms,
		"source": source,
		"type": event_type,
		"entity_id": entity_id,
		"payload": payload,
	}
	_events.append(ev)
	while _events.size() > MAX_EVENTS:
		_events.pop_front()


## Get events with seq > since_seq, up to limit.
func get_event_log(since_seq: int, limit: int = 50) -> Array:
	var out: Array = []
	for ev: Dictionary in _events:
		if (ev["seq"] as int) > since_seq:
			out.append(ev)
			if out.size() >= limit:
				break
	return out


## Get the latest sequence number.
func get_last_seq() -> int:
	return _seq
