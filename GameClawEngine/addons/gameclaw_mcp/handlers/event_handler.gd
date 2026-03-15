## Handler for event-log MCP commands (Sprint C.1 + D3).
## get_event_log reads from EventOutbox for UI and other events.
## send_input_action dispatches a named input action to AbilitySystem (Sprint D3).
class_name MCPEventHandler
extends RefCounted

const LAYER_PROJECTION: String = "projection"


static func register_tools(router: MCPCommandRouter) -> void:
	var handler := MCPEventHandler.new()
	router.register_handler_instance(handler)
	router.register("get_event_log", handler._handle_get_event_log)
	router.register("send_input_action", handler._handle_send_input_action)


func _handle_get_event_log(params: Variant) -> Dictionary:
	var main_loop: SceneTree = Engine.get_main_loop() as SceneTree
	if main_loop == null:
		return {"success": false, "error": "No main loop", "data": null}
	var outbox_node: Node = main_loop.root.get_node_or_null("EventOutbox")
	if outbox_node == null or not outbox_node.has_method("get_event_log"):
		return {"success": false, "error": "EventOutbox autoload not found or missing get_event_log", "data": null}

	var since_seq: int = 0
	var limit: int = 50
	if params is Dictionary:
		since_seq = int(params.get("since_seq", 0))
		limit = int(params.get("limit", 50))

	var events: Array = outbox_node.get_event_log(since_seq, limit)
	return {"success": true, "data": {"events": events}}


func _handle_send_input_action(params: Variant) -> Dictionary:
	if params is not Dictionary:
		return {"success": false, "error": "params must be a Dictionary with 'action_name'", "layer": LAYER_PROJECTION, "next_steps": ["Provide {\"action_name\": \"cast_fireball\"}"]}

	var p: Dictionary = params as Dictionary
	var action_name: String = str(p.get("action_name", ""))
	if action_name.is_empty():
		return {"success": false, "error": "'action_name' is required", "layer": LAYER_PROJECTION, "next_steps": ["Provide a non-empty action_name matching an ability's trigger.input_action."]}

	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	if tree == null:
		return {"success": false, "error": "No SceneTree", "layer": LAYER_PROJECTION, "next_steps": []}

	var ability_system: Node = tree.root.get_node_or_null("/root/AbilitySystem")
	if ability_system == null or not ability_system.has_method("handle_input_action"):
		return {"success": false, "error": "AbilitySystem autoload not found or missing handle_input_action", "layer": LAYER_PROJECTION, "next_steps": ["Ensure AbilitySystem is registered in project.godot autoloads."]}

	var result: Dictionary = ability_system.handle_input_action(action_name)
	if result.get("ok", false):
		return {"success": true, "data": {"action_name": action_name, "activations": result.get("activations", [])}}
	else:
		return {"success": false, "error": result.get("reason", "AbilitySystem returned error"), "layer": LAYER_PROJECTION, "next_steps": ["Check get_ir_state to verify abilities and entity state."]}
