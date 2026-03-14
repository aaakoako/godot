## Handler for Projection-layer MCP commands.
## Covers: SceneTree inspection, entity node property reading.
## Enables AI to verify that IR state is correctly projected onto Godot nodes.
class_name MCPSceneHandler
extends RefCounted

const LAYER_PROJECTION: String = "projection"


## Register all scene-related tools on the given router.
static func register_tools(router: MCPCommandRouter) -> void:
	var handler := MCPSceneHandler.new()
	router.register_handler_instance(handler)
	router.register("inspect_scene_tree", handler._handle_inspect_scene_tree)
	router.register("get_entity_node_props", handler._handle_get_entity_node_props)


func _handle_inspect_scene_tree(params: Variant) -> Dictionary:
	var root_path: String = "/root"
	var max_depth: int = 10

	if params is Dictionary:
		root_path = (params as Dictionary).get("root_path", root_path) as String
		max_depth = int((params as Dictionary).get("max_depth", max_depth))

	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	if tree == null:
		return _fail("SceneTree not available", ["Ensure the game is running."])

	var root_node: Node = tree.root.get_node_or_null(root_path)
	if root_node == null:
		root_node = tree.root
		if root_path != "/root":
			return _fail("Node not found at path '%s'" % root_path, ["Use '/root' or a valid absolute node path."])

	var tree_data: Dictionary = _serialize_node(root_node, 0, max_depth)
	return {"success": true, "data": tree_data}


func _handle_get_entity_node_props(params: Variant) -> Dictionary:
	if params is not Dictionary:
		return _fail("params must be a Dictionary with 'entity_id' field", ["Provide {\"entity_id\": \"box_1\"}"])

	var entity_id: Variant = (params as Dictionary).get("entity_id", "")
	if entity_id is not String or (entity_id as String).is_empty():
		return _fail("'entity_id' must be a non-empty string", [])

	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	if tree == null:
		return _fail("SceneTree not available", [])

	var entity_root: Node = tree.root.get_node_or_null("Main/EntityRoot")
	if entity_root == null:
		return _fail("EntityRoot node not found in scene tree", ["Ensure main scene is loaded with EntityRoot node."])

	var entity_node: Node = entity_root.get_node_or_null(entity_id as String)
	if entity_node == null:
		return _fail(
			"Entity node '%s' not found under EntityRoot" % (entity_id as String),
			["Call 'get_ir_state' to check if entity exists in IR.", "Call 'inspect_scene_tree' to see all nodes under EntityRoot."]
		)

	var props: Dictionary = _extract_entity_props(entity_node)
	return {"success": true, "data": props}


func _serialize_node(node: Node, depth: int, max_depth: int) -> Dictionary:
	var result: Dictionary = {
		"name": node.name,
		"type": node.get_class(),
		"path": str(node.get_path()),
	}

	if node is Node3D:
		var n3d: Node3D = node as Node3D
		result["position"] = _vec3_to_array(n3d.position)
		result["rotation_degrees"] = _vec3_to_array(n3d.rotation_degrees)
		result["scale"] = _vec3_to_array(n3d.scale)
		result["visible"] = n3d.visible

	if depth < max_depth and node.get_child_count() > 0:
		var children: Array = []
		for child: Node in node.get_children():
			children.append(_serialize_node(child, depth + 1, max_depth))
		result["children"] = children

	return result


func _extract_entity_props(node: Node) -> Dictionary:
	var props: Dictionary = {
		"name": node.name,
		"type": node.get_class(),
		"path": str(node.get_path()),
	}

	if node is Node3D:
		var n3d: Node3D = node as Node3D
		props["position"] = _vec3_to_array(n3d.position)
		props["rotation_degrees"] = _vec3_to_array(n3d.rotation_degrees)
		props["scale"] = _vec3_to_array(n3d.scale)
		props["visible"] = n3d.visible

	if node is MeshInstance3D:
		var mi: MeshInstance3D = node as MeshInstance3D
		props["mesh_type"] = mi.mesh.get_class() if mi.mesh != null else "null"
		var mat: Material = mi.get_surface_override_material(0)
		if mat is StandardMaterial3D:
			var std_mat: StandardMaterial3D = mat as StandardMaterial3D
			props["albedo_color"] = std_mat.albedo_color.to_html(false)

	return props


func _vec3_to_array(v: Vector3) -> Array:
	return [snapped(v.x, 0.001), snapped(v.y, 0.001), snapped(v.z, 0.001)]


func _fail(message: String, next_steps: Array) -> Dictionary:
	var result: Dictionary = {"success": false, "error": message, "layer": LAYER_PROJECTION}
	if not next_steps.is_empty():
		result["next_steps"] = next_steps
	return result
