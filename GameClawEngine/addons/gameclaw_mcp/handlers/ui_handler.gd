## Handler for UI interaction MCP commands.
## Provides test automation primitives for real button clicks.
class_name MCPUIHandler
extends RefCounted

const LAYER_PROJECTION: String = "projection"
const MAX_MULTI_ACTIONS: int = 32
const MAX_CLICK_COUNT: int = 50


static func register_tools(router) -> void:
	var handler: RefCounted = load("res://addons/gameclaw_mcp/handlers/ui_handler.gd").new()
	router.register_handler_instance(handler)
	router.register("ui_click", handler._handle_ui_click)
	router.register("ui_multi_click", handler._handle_ui_multi_click)


func _handle_ui_click(params: Variant) -> Dictionary:
	if params is not Dictionary:
		return _fail("params must be a Dictionary with 'entity_id'", ["Provide {'entity_id':'btn_attack'}"])

	var p: Dictionary = params as Dictionary
	var entity_id: String = str(p.get("entity_id", ""))
	if entity_id.is_empty():
		return _fail("'entity_id' is required", [])

	var count: int = clampi(int(p.get("count", 1)), 1, MAX_CLICK_COUNT)
	var interval_ms: int = maxi(0, int(p.get("interval_ms", 0)))

	return _click_entity(entity_id, count, interval_ms)


func _handle_ui_multi_click(params: Variant) -> Dictionary:
	if params is not Dictionary:
		return _fail("params must be a Dictionary with 'actions'", ["Provide {'actions':[{'entity_id':'btn_attack','count':1}]}"])

	var actions: Variant = (params as Dictionary).get("actions", [])
	if actions is not Array or (actions as Array).is_empty():
		return _fail("'actions' must be a non-empty Array", [])

	var action_list: Array = actions as Array
	if action_list.size() > MAX_MULTI_ACTIONS:
		return _fail("Too many actions (max %d)" % MAX_MULTI_ACTIONS, [])

	var outbox: Node = _get_outbox()
	if outbox == null:
		return _fail("EventOutbox not found", ["Ensure EventOutbox autoload is registered."])
	var seq_start: int = int(outbox.get_last_seq())

	var per_action: Array = []
	for i: int in range(action_list.size()):
		var item: Variant = action_list[i]
		if item is not Dictionary:
			return _fail("actions[%d] must be Dictionary" % i, [])
		var a: Dictionary = item as Dictionary
		var entity_id: String = str(a.get("entity_id", ""))
		if entity_id.is_empty():
			return _fail("actions[%d].entity_id is required" % i, [])
		var count: int = clampi(int(a.get("count", 1)), 1, MAX_CLICK_COUNT)
		var interval_ms: int = maxi(0, int(a.get("interval_ms", 0)))
		var delay_ms: int = maxi(0, int(a.get("delay_ms", 0)))
		if delay_ms > 0:
			OS.delay_msec(delay_ms)
		var step: Dictionary = _click_entity(entity_id, count, interval_ms)
		if not step.get("success", false):
			return step
		per_action.append(step.get("data", {}))

	var seq_end: int = int(outbox.get_last_seq())
	var events: Array = outbox.get_event_log(seq_start, 200)
	return {
		"success": true,
		"data": {
			"accepted": true,
			"event_seq_start": seq_start,
			"event_seq_end": seq_end,
			"events_captured": events,
			"actions": per_action,
		}
	}


func _click_entity(entity_id: String, count: int, interval_ms: int) -> Dictionary:
	var node: Node = _find_entity_node(entity_id)
	if node == null:
		return _fail("UI entity '%s' not found" % entity_id, ["Call inspect_scene_tree to confirm projected node paths."])
	if node is not BaseButton:
		return _fail("Entity '%s' is not clickable button" % entity_id, ["ui_click currently supports BaseButton only."])

	var btn: BaseButton = node as BaseButton
	if btn.disabled:
		return _fail("Button '%s' is disabled" % entity_id, [])
	if not btn.visible:
		return _fail("Button '%s' is not visible" % entity_id, [])

	var outbox: Node = _get_outbox()
	if outbox == null:
		return _fail("EventOutbox not found", ["Ensure EventOutbox autoload is registered."])
	var seq_start: int = int(outbox.get_last_seq())

	for i: int in range(count):
		btn.emit_signal("pressed")
		if interval_ms > 0 and i < count - 1:
			OS.delay_msec(interval_ms)

	var seq_end: int = int(outbox.get_last_seq())
	var events: Array = outbox.get_event_log(seq_start, 200)
	return {
		"success": true,
		"data": {
			"accepted": true,
			"entity_id": entity_id,
			"count": count,
			"event_seq_start": seq_start,
			"event_seq_end": seq_end,
			"events_captured": events,
		}
	}


func _find_entity_node(entity_id: String) -> Node:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	if tree == null:
		return null
	var root: Node = tree.root
	var from_ui: Node = root.get_node_or_null("Main/UI/IRoot/%s" % entity_id)
	if from_ui != null:
		return from_ui
	var from_entity_root: Node = root.get_node_or_null("Main/EntityRoot/%s" % entity_id)
	if from_entity_root != null:
		return from_entity_root
	return root.find_child(entity_id, true, false)


func _get_outbox() -> Node:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	if tree == null:
		return null
	return tree.root.get_node_or_null("/root/EventOutbox")


func _fail(message: String, next_steps: Array) -> Dictionary:
	var result: Dictionary = {"success": false, "error": message, "layer": LAYER_PROJECTION}
	if not next_steps.is_empty():
		result["next_steps"] = next_steps
	return result
