## Routes JSON-RPC method names to handler functions.
## Each handler returns a Dictionary with at minimum: {"success": bool}.
## On failure, include: {"success": false, "error": String, "layer": String, "next_steps": Array}.
## On success: {"success": true, "data": Variant}.
class_name MCPCommandRouter
extends RefCounted

const MCPIRHandler = preload("res://addons/gameclaw_mcp/handlers/ir_handler.gd")
const MCPEventHandler = preload("res://addons/gameclaw_mcp/handlers/event_handler.gd")
const MCPSceneHandler = preload("res://addons/gameclaw_mcp/handlers/scene_handler.gd")
const MCPPerceptionHandler = preload("res://addons/gameclaw_mcp/handlers/perception_handler.gd")
const MCPProbeHandler = preload("res://addons/gameclaw_mcp/handlers/probe_handler.gd")
const MCPEvalHandler = preload("res://addons/gameclaw_mcp/handlers/eval_handler.gd")
const MCPUIHandler = preload("res://addons/gameclaw_mcp/handlers/ui_handler.gd")

var _handlers: Dictionary = {}
var _handler_instances: Array = []


func _init() -> void:
	_register_builtin_handlers()


## Register a handler for a given method name.
## handler_callable must accept (params: Variant) -> Dictionary.
func register(method: String, handler_callable: Callable) -> void:
	_handlers[method] = handler_callable


## Keep strong references to handler instances so Callable targets are not freed.
func register_handler_instance(handler_instance: RefCounted) -> void:
	if handler_instance != null:
		_handler_instances.append(handler_instance)


## Dispatch a method call to its registered handler.
func dispatch(method: String, params: Variant) -> Dictionary:
	if not _handlers.has(method):
		return {
			"success": false,
			"code": -32601,
			"error": "Method not found: %s" % method,
			"next_steps": ["Call 'list_tools' to see available methods."],
		}

	var handler: Callable = _handlers[method]
	if not handler.is_valid():
		return {
			"success": false,
			"code": -32603,
			"error": "Handler for '%s' is invalid (target freed)." % method,
			"next_steps": ["Restart the game to re-register handlers."],
		}
	var result: Variant = handler.call(params)
	if result is not Dictionary:
		return {
			"success": false,
			"code": -32603,
			"error": "Handler for '%s' returned non-Dictionary" % method,
		}
	var result_dict: Dictionary = result
	if result_dict.get("success", true) == false and not result_dict.has("error"):
		result_dict["error"] = "Handler failed without error message (check Godot console)"
	return result_dict


func _register_builtin_handlers() -> void:
	register("ping", _handle_ping)
	register("list_tools", _handle_list_tools)

	MCPIRHandler.register_tools(self)
	MCPEventHandler.register_tools(self)
	MCPSceneHandler.register_tools(self)
	MCPPerceptionHandler.register_tools(self)
	MCPProbeHandler.register_tools(self)
	MCPEvalHandler.register_tools(self)
	MCPUIHandler.register_tools(self)


func _handle_ping(params: Variant) -> Dictionary:
	return {"success": true, "data": {"pong": true, "engine": "GameClawEngine", "protocol": "json-rpc-2.0"}}


func _handle_list_tools(params: Variant) -> Dictionary:
	var tool_list: Array = []
	for method_name: String in _handlers:
		tool_list.append(method_name)
	tool_list.sort()
	return {"success": true, "data": {"tools": tool_list}}
