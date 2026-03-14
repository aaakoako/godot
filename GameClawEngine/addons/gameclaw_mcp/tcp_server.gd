## TCP server for MCP bridge. Only runs in dev/debug (or when GAMECLAW_MCP_ENABLED=1).
## Binds to a random available port (0) and can write the port to the user's global Cursor mcp.json.
extends Node

const DEFAULT_BIND: String = "127.0.0.1"
const READ_BUFFER_SIZE: int = 65536
const MAX_CLIENTS: int = 8

var _server: TCPServer = null
var _router: RefCounted = null
var _clients: Array = []
var _connection_count: int = 0
var _verbose: bool = false
var _current_client_peer: StreamPeerTCP = null

signal client_connected()
signal client_disconnected()


func _ready() -> void:
	if not _should_enable_mcp():
		return

	_verbose = OS.get_environment("GAMECLAW_MCP_VERBOSE") == "1"

	var CommandRouter := load("res://addons/gameclaw_mcp/command_router.gd")
	_router = CommandRouter.new()

	_server = TCPServer.new()
	var err: Error = _server.listen(0, DEFAULT_BIND)
	if err != OK:
		push_error("[MCP TCP] Failed to listen on %s — error %d" % [DEFAULT_BIND, err])
		return

	var port: int = _server.get_local_port()
	print("[MCP TCP] Listening on %s:%d" % [DEFAULT_BIND, port])

	var cursor_written: bool = _write_cursor_mcp_port(port)
	var opencode_written: bool = _write_opencode_mcp_config(port)

	if cursor_written:
		print("[MCP TCP] Updated global Cursor MCP config with GODOT_PORT=%d." % port)
	else:
		print("[MCP TCP] Could not write global Cursor mcp.json — set GODOT_PORT=%d manually." % port)

	if opencode_written:
		print("[MCP TCP] Updated OpenCode MCP config with GODOT_PORT=%d." % port)
	else:
		print("[MCP TCP] Could not write OpenCode config (~/.config/opencode/opencode.json).")

	print("[MCP TCP] Restart your MCP host (Cursor/OpenCode) to reconnect if needed.")


## Only enable MCP TCP in dev (debug/editor) or when explicitly requested (e.g. creator-mode release build).
func _should_enable_mcp() -> bool:
	if OS.get_environment("GAMECLAW_MCP_ENABLED") == "1":
		return true
	return OS.has_feature("debug")


func _process(_delta: float) -> void:
	if _server == null:
		return

	_accept_pending()
	_poll_clients()


func _accept_pending() -> void:
	while _clients.size() < MAX_CLIENTS and _server.is_connection_available():
		var peer: StreamPeerTCP = _server.take_connection()
		if peer == null:
			break
		_connection_count += 1
		client_connected.emit()
		if _connection_count == 1 or _verbose:
			print("[MCP TCP] Client connected from %s:%d" % [peer.get_connected_host(), peer.get_connected_port()])
		_clients.append({"peer": peer, "buffer": ""})


func _poll_clients() -> void:
	var to_remove: Array = []
	for i: int in range(_clients.size()):
		var entry: Dictionary = _clients[i]
		var peer: StreamPeerTCP = entry["peer"]
		peer.poll()
		var status: StreamPeerTCP.Status = peer.get_status()
		if status == StreamPeerTCP.STATUS_ERROR or status == StreamPeerTCP.STATUS_NONE:
			to_remove.append(i)
			continue
		if status != StreamPeerTCP.STATUS_CONNECTED:
			continue
		var available: int = peer.get_available_bytes()
		if available <= 0:
			continue
		var result: Array = peer.get_data(mini(available, READ_BUFFER_SIZE))
		var error_code: int = result[0]
		var data: PackedByteArray = result[1]
		if error_code != OK:
			to_remove.append(i)
			continue
		entry["buffer"] = entry["buffer"] + data.get_string_from_utf8()
		_current_client_peer = peer
		_process_buffer_for(entry)
		_current_client_peer = null
	for j: int in range(to_remove.size() - 1, -1, -1):
		_disconnect_client_at(to_remove[j])


func _process_buffer_for(entry: Dictionary) -> void:
	var buf: String = entry["buffer"]
	while true:
		var newline_pos: int = buf.find("\n")
		if newline_pos == -1:
			break
		var line: String = buf.substr(0, newline_pos).strip_edges()
		buf = buf.substr(newline_pos + 1)
		entry["buffer"] = buf
		if line.is_empty():
			continue
		_handle_message(line)


func _handle_message(raw_json: String) -> void:
	var parsed: Variant = JSON.parse_string(raw_json)
	if parsed == null or parsed is not Dictionary:
		_send_error_response(null, -32700, "Parse error: invalid JSON")
		return

	var request: Dictionary = parsed
	var id: Variant = request.get("id")
	var method: Variant = request.get("method")

	if method == null or method is not String:
		_send_error_response(id, -32600, "Invalid Request: missing 'method'")
		return

	var params: Variant = request.get("params", {})
	if params is not Dictionary and params is not Array:
		params = {}

	var response: Dictionary = _router.dispatch(method as String, params)
	_send_response(id, response)


func _send_response(id: Variant, result: Dictionary) -> void:
	var envelope: Dictionary = {
		"jsonrpc": "2.0",
		"id": id,
	}
	if result.get("success", false):
		envelope["result"] = {"data": result.get("data", {}), "evidence": result.get("evidence")}
	else:
		var err_msg: Variant = result.get("error", "")
		if typeof(err_msg) != TYPE_STRING or (err_msg as String).is_empty():
			err_msg = "Internal error (no message from handler)"
		envelope["error"] = {
			"code": result.get("code", -32603),
			"message": str(err_msg),
		}
		var err_data: Dictionary = {}
		if result.has("layer"):
			err_data["layer"] = result["layer"]
		if result.has("next_steps"):
			err_data["next_steps"] = result["next_steps"]
		if result.get("evidence_path", "").is_empty() == false:
			err_data["evidence_path"] = result["evidence_path"]
		if not err_data.is_empty():
			envelope["error"]["data"] = err_data

	_send_raw(JSON.stringify(envelope))


func _send_error_response(id: Variant, code: int, message: String) -> void:
	var envelope: Dictionary = {
		"jsonrpc": "2.0",
		"id": id,
		"error": {"code": code, "message": message},
	}
	_send_raw(JSON.stringify(envelope))


func _send_raw(json_str: String) -> void:
	if _current_client_peer == null:
		return
	var payload: PackedByteArray = (json_str + "\n").to_utf8_buffer()
	_current_client_peer.put_data(payload)


func _disconnect_client_at(index: int) -> void:
	if index < 0 or index >= _clients.size():
		return
	var entry: Dictionary = _clients[index]
	var peer: StreamPeerTCP = entry["peer"]
	if peer != null:
		peer.disconnect_from_host()
	_clients.remove_at(index)
	client_disconnected.emit()
	if _verbose:
		print("[MCP TCP] Client disconnected.")


func _exit_tree() -> void:
	for i: int in range(_clients.size() - 1, -1, -1):
		_disconnect_client_at(i)
	if _server != null:
		_server.stop()
		_server = null


## Write the current port to user's global Cursor mcp.json.
## Path: Windows %USERPROFILE%/.cursor/mcp.json, Unix $HOME/.cursor/mcp.json
func _write_cursor_mcp_port(port: int) -> bool:
	var mcp_server_cwd: String = _get_project_root_cwd()

	var home: String = OS.get_environment("USERPROFILE")
	if home.is_empty():
		home = OS.get_environment("HOME")
	if home.is_empty():
		return false

	var path: String = (home + "/.cursor/mcp.json").replace("\\", "/")
	return _write_single_cursor_mcp_file(path, mcp_server_cwd, port)


func _write_single_cursor_mcp_file(path: String, mcp_server_cwd: String, port: int) -> bool:
	var config: Dictionary = _read_json_file(path)

	if not config.has("mcpServers"):
		config["mcpServers"] = {}
	var servers: Dictionary = config["mcpServers"]
	if not servers.has("gameclaw"):
		servers["gameclaw"] = {}
	var gameclaw: Dictionary = servers["gameclaw"]
	var script_path: String = mcp_server_cwd.path_join("gameclaw_mcp.py")

	gameclaw["command"] = "python"
	gameclaw["args"] = [script_path]
	gameclaw["cwd"] = mcp_server_cwd
	if not gameclaw.has("env"):
		gameclaw["env"] = {}
	gameclaw["env"]["GODOT_HOST"] = DEFAULT_BIND
	gameclaw["env"]["GODOT_PORT"] = str(port)

	return _write_json_file(path, config)


func _write_opencode_mcp_config(port: int) -> bool:
	var mcp_server_cwd: String = _get_project_root_cwd()
	var home: String = OS.get_environment("USERPROFILE")
	if home.is_empty():
		home = OS.get_environment("HOME")
	if home.is_empty():
		return false

	var path: String = (home + "/.config/opencode/opencode.json").replace("\\", "/")
	var config: Dictionary = _read_json_file(path)
	if config.is_empty():
		config["$schema"] = "https://opencode.ai/config.json"

	if not config.has("mcp"):
		config["mcp"] = {}
	var mcp: Dictionary = config["mcp"]
	if not mcp.has("gameclaw"):
		mcp["gameclaw"] = {}
	var gameclaw: Dictionary = mcp["gameclaw"]
	var script_path: String = mcp_server_cwd.path_join("gameclaw_mcp.py")

	gameclaw["type"] = "local"
	gameclaw["command"] = ["python", script_path]
	if not gameclaw.has("environment"):
		gameclaw["environment"] = {}
	gameclaw["environment"]["GODOT_HOST"] = DEFAULT_BIND
	gameclaw["environment"]["GODOT_PORT"] = str(port)

	return _write_json_file(path, config)


## Project root directory where gameclaw_mcp.py lives (for Python MCP bridge).
func _get_project_root_cwd() -> String:
	var root: String = ProjectSettings.globalize_path("res://")
	if root.ends_with("/") or root.ends_with("\\"):
		root = root.substr(0, root.length() - 1)
	if OS.get_name() == "Windows":
		root = root.replace("/", "\\")
	return root


func _read_json_file(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var f: FileAccess = FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var raw: String = f.get_as_text()
	f.close()
	if raw.strip_edges().is_empty():
		return {}
	var parsed: Variant = JSON.parse_string(raw)
	if parsed is Dictionary:
		return parsed
	return {}


func _write_json_file(path: String, data: Dictionary) -> bool:
	var dir: String = path.get_base_dir()
	if not DirAccess.dir_exists_absolute(dir):
		var err: Error = DirAccess.make_dir_recursive_absolute(dir)
		if err != OK:
			return false
	var json_str: String = JSON.stringify(data, "  ")
	var fw: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if fw == null:
		return false
	fw.store_string(json_str)
	fw.close()
	return true
