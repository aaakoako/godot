## Handler for event-log MCP commands (Sprint C.1).
## get_event_log reads from EventOutbox for UI and other events.
class_name MCPEventHandler
extends RefCounted


static func register_tools(router: MCPCommandRouter) -> void:
	var handler := MCPEventHandler.new()
	router.register_handler_instance(handler)
	router.register("get_event_log", handler._handle_get_event_log)


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
