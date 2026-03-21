## Handler for game_entity MCP commands (Phase 2 / Sprint D1).
## Provides get_entity_debug_view to inspect components and key fields of a game_entity.
class_name MCPEntityHandler
extends RefCounted

const LAYER_IR_STATE: String = "ir_state"
const SELF_SCRIPT: Script = preload("res://addons/gameclaw_mcp/handlers/entity_handler.gd")


static func register_tools(router: MCPCommandRouter) -> void:
	var handler := SELF_SCRIPT.new() as MCPEntityHandler
	router.register_handler_instance(handler)
	router.register("get_entity_debug_view", handler._handle_get_entity_debug_view)


func _handle_get_entity_debug_view(params: Variant) -> Dictionary:
	if params is not Dictionary:
		return _fail("params must be a Dictionary with 'entity_id'", ["Provide {\"entity_id\": \"hero_1\"}"])

	var p: Dictionary = params as Dictionary
	var entity_id: String = str(p.get("entity_id", ""))
	if entity_id.is_empty():
		return _fail("'entity_id' is required", [])

	var ir_manager: Node = _get_ir_manager()
	if ir_manager == null:
		return _fail("IRManager autoload not found", ["Ensure IRManager is registered in project.godot autoloads."])

	var state: Dictionary = ir_manager.get_ir_state()
	var entities: Variant = state.get("entities", {})
	if entities is not Dictionary or not (entities as Dictionary).has(entity_id):
		return _fail("entity '%s' not found in IR state" % entity_id, ["Call get_ir_state to see all entities."])

	var entity_data: Dictionary = (entities as Dictionary)[entity_id] as Dictionary
	var entity_type: String = str(entity_data.get("type", ""))

	if entity_type != "game_entity":
		return _fail("entity '%s' is type '%s', not game_entity" % [entity_id, entity_type],
			["get_entity_debug_view is only for game_entity type."])

	var components: Variant = entity_data.get("components", {})
	if components is not Dictionary:
		return {"success": true, "data": {"entity_id": entity_id, "type": entity_type, "components": {}}}

	var comp_dict: Dictionary = components as Dictionary
	var debug_components: Dictionary = {}

	for comp_type: String in comp_dict:
		var comp_data: Variant = comp_dict[comp_type]
		if comp_data is Dictionary:
			debug_components[comp_type] = _summarize_component(comp_type, comp_data as Dictionary)
		else:
			debug_components[comp_type] = comp_data

	var node_host: Node = _get_entity_node(entity_id)
	var component_nodes: Array = []
	if node_host != null:
		for child: Node in node_host.get_children():
			component_nodes.append(child.name)

	return {
		"success": true,
		"data": {
			"entity_id": entity_id,
			"type": entity_type,
			"component_types": comp_dict.keys(),
			"components": debug_components,
			"projected_node_children": component_nodes,
		}
	}


func _summarize_component(comp_type: String, comp_data: Dictionary) -> Dictionary:
	match comp_type:
		"attribute_set":
			var attrs: Variant = comp_data.get("attributes", {})
			var summary: Dictionary = {}
			if attrs is Dictionary:
				for attr_name: String in (attrs as Dictionary):
					var av: Variant = (attrs as Dictionary)[attr_name]
					if av is Dictionary:
						summary[attr_name] = av
			return {"attributes": summary}
		"tag_set":
			return {
				"base_tags": comp_data.get("base_tags", []),
				"runtime_tags": comp_data.get("runtime_tags", []),
			}
		"lifecycle":
			return {
				"alive": comp_data.get("alive", true),
				"death_state": comp_data.get("death_state", "alive"),
			}
		"presentation":
			return {
				"icon_ref": comp_data.get("icon_ref", ""),
				"model_ref": comp_data.get("model_ref", ""),
			}
		"transform_2d":
			return {"position": comp_data.get("position", [0, 0])}
		_:
			return comp_data.duplicate()


func _get_entity_node(entity_id: String) -> Node:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	if tree == null:
		return null
	return tree.root.get_node_or_null("Main/EntityRoot/%s" % entity_id)


func _get_ir_manager() -> Node:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	if tree == null:
		return null
	return tree.root.get_node_or_null("/root/IRManager")


func _fail(message: String, next_steps: Array) -> Dictionary:
	var result: Dictionary = {"success": false, "error": message, "layer": LAYER_IR_STATE}
	if not next_steps.is_empty():
		result["next_steps"] = next_steps
	return result
