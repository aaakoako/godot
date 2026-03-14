## Handler for restricted GDScript runtime evaluation.
## Provides a sandboxed eval capability for AI agents to query runtime state.
## Iron Law 7: Security boundaries enforced — no filesystem, network, or process access.
class_name MCPEvalHandler
extends RefCounted

const LAYER_EVAL: String = "eval"

var _forbidden_patterns: Array[String] = [
	"FileAccess",
	"DirAccess",
	"OS.execute",
	"OS.shell_open",
	"OS.create_process",
	"OS.create_instance",
	"OS.kill",
	"OS.get_environment",
	"OS.set_environment",
	"HTTPClient",
	"HTTPRequest",
	"TCPServer",
	"StreamPeerTCP",
	"UDPServer",
	"PacketPeerUDP",
	"WebSocketPeer",
	"Thread.new",
	"Mutex.new",
	"Semaphore.new",
	"ClassDB.instantiate",
	"ResourceLoader.load",
	"ResourceSaver.save",
	"load(",
	"preload(",
]


## Register eval tools on the given router.
static func register_tools(router: MCPCommandRouter) -> void:
	var handler := MCPEvalHandler.new()
	router.register_handler_instance(handler)
	router.register("eval_gdscript", handler._handle_eval_gdscript)


func _handle_eval_gdscript(params: Variant) -> Dictionary:
	if params is not Dictionary:
		return _fail("params must be a Dictionary with 'code' field", ["Provide {\"code\": \"<expression>\", \"mode\": \"expression\"}"])

	var p: Dictionary = params as Dictionary
	var code: Variant = p.get("code", "")
	var mode: String = str(p.get("mode", "expression"))

	if code is not String or (code as String).strip_edges().is_empty():
		return _fail("'code' must be a non-empty string", [])

	var code_str: String = code as String

	var violation: String = _check_security(code_str)
	if not violation.is_empty():
		return _fail(
			"Security violation: forbidden pattern '%s' detected" % violation,
			["eval_gdscript is restricted to read-only operations.", "Use MCP tools (apply_patch, etc.) for mutations."]
		)

	match mode:
		"expression":
			return _eval_expression(code_str)
		"statements":
			return _fail(
				"'statements' mode is not yet implemented. Godot Expression only supports single expressions.",
				["Use mode='expression' with a single GDScript expression.", "Use MCP tools (apply_patch, etc.) for mutations."]
			)
		_:
			return _fail("Unknown mode '%s'. Use 'expression'." % mode, [])


func _eval_expression(code: String) -> Dictionary:
	var expression := Expression.new()
	var parse_err: Error = expression.parse(code)
	if parse_err != OK:
		return _fail(
			"Parse error: %s" % expression.get_error_text(),
			["Check GDScript expression syntax.", "Ensure all referenced variables are available."]
		)

	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	var base_instance: Object = tree if tree != null else null

	var result: Variant = expression.execute([], base_instance, true, false)
	if expression.has_execute_failed():
		return _fail(
			"Execution error: %s" % expression.get_error_text(),
			["Verify the expression references valid objects/methods.", "Use 'inspect_scene_tree' to find valid node paths."]
		)

	var result_str: String
	if result == null:
		result_str = "null"
	elif result is Dictionary or result is Array:
		result_str = JSON.stringify(result)
	else:
		result_str = str(result)

	return {"success": true, "data": {"result": result_str, "type": type_string(typeof(result))}}


func _check_security(code: String) -> String:
	for pattern: String in _forbidden_patterns:
		if code.contains(pattern):
			return pattern
	return ""


func _fail(message: String, next_steps: Array) -> Dictionary:
	var result: Dictionary = {"success": false, "error": message, "layer": LAYER_EVAL}
	if not next_steps.is_empty():
		result["next_steps"] = next_steps
	return result
