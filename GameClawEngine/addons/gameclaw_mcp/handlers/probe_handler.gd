## Handler for frame-level probing MCP commands.
## Dynamically creates observer Nodes that sample data each frame,
## recording only changes in NDJSON format.
## Implements the frame-level probing methodology from Iron Law 9.
class_name MCPProbeHandler
extends RefCounted

const LAYER_PROBE: String = "probe"
const PROBE_NODE_NAME: String = "__MCPFrameProbe__"
const DEFAULT_MAX_FRAMES: int = 300


## Register all probe-related tools on the given router.
static func register_tools(router: MCPCommandRouter) -> void:
	var handler := MCPProbeHandler.new()
	router.register_handler_instance(handler)
	router.register("start_frame_probe", handler._handle_start_frame_probe)
	router.register("read_probe_log", handler._handle_read_probe_log)
	router.register("stop_frame_probe", handler._handle_stop_frame_probe)


func _handle_start_frame_probe(params: Variant) -> Dictionary:
	if params is not Dictionary:
		return _fail("params must be a Dictionary with 'target' and 'fields'", [])

	var p: Dictionary = params as Dictionary
	var target_path: Variant = p.get("target", "")
	var fields: Variant = p.get("fields", [])
	var max_frames: int = int(p.get("max_frames", DEFAULT_MAX_FRAMES))

	if target_path is not String or (target_path as String).is_empty():
		return _fail("'target' must be a node path or entity_id", [])
	if fields is not Array or (fields as Array).is_empty():
		return _fail("'fields' must be a non-empty Array of property names", ["Example: [\"position\", \"rotation_degrees\", \"visible\"]"])

	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	if tree == null:
		return _fail("SceneTree not available", [])

	var existing: Node = tree.root.get_node_or_null(PROBE_NODE_NAME)
	if existing != null:
		existing.queue_free()

	var target_node: Node = _find_target_node(tree, target_path as String)
	if target_node == null:
		return _fail(
			"Target node not found: '%s'" % (target_path as String),
			["Use 'inspect_scene_tree' to find valid node paths.", "For entities, try 'Main/EntityRoot/<entity_id>'."]
		)

	var probe_node: Node = Node.new()
	probe_node.name = PROBE_NODE_NAME
	probe_node.set_meta("target_path", str(target_node.get_path()))
	probe_node.set_meta("fields", fields as Array)
	probe_node.set_meta("max_frames", max_frames)
	probe_node.set_meta("frame_count", 0)
	probe_node.set_meta("log_lines", PackedStringArray())
	probe_node.set_meta("prev_snapshot", {})
	probe_node.set_meta("active", true)

	var script: GDScript = GDScript.new()
	script.source_code = _generate_probe_script()
	script.reload()
	probe_node.set_script(script)

	tree.root.add_child(probe_node)

	return {"success": true, "data": {"started": true, "target": str(target_node.get_path()), "fields": fields, "max_frames": max_frames}}


func _handle_read_probe_log(params: Variant) -> Dictionary:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	if tree == null:
		return _fail("SceneTree not available", [])

	var probe: Node = tree.root.get_node_or_null(PROBE_NODE_NAME)
	if probe == null:
		return _fail("No active frame probe found", ["Call 'start_frame_probe' first."])

	var log_lines: PackedStringArray = probe.get_meta("log_lines", PackedStringArray())
	var active: bool = probe.get_meta("active", false)
	var frame_count: int = probe.get_meta("frame_count", 0)

	var lines_array: Array = []
	for line: String in log_lines:
		lines_array.append(line)

	return {
		"success": true,
		"data": {
			"active": active,
			"frames_observed": frame_count,
			"changes_recorded": log_lines.size(),
			"log": lines_array,
		}
	}


func _handle_stop_frame_probe(params: Variant) -> Dictionary:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	if tree == null:
		return _fail("SceneTree not available", [])

	var probe: Node = tree.root.get_node_or_null(PROBE_NODE_NAME)
	if probe == null:
		return _fail("No active frame probe to stop", [])

	var log_lines: PackedStringArray = probe.get_meta("log_lines", PackedStringArray())
	var frame_count: int = probe.get_meta("frame_count", 0)
	probe.queue_free()

	var lines_array: Array = []
	for line: String in log_lines:
		lines_array.append(line)

	return {
		"success": true,
		"data": {
			"stopped": true,
			"frames_observed": frame_count,
			"changes_recorded": log_lines.size(),
			"log": lines_array,
		}
	}


func _find_target_node(tree: SceneTree, target: String) -> Node:
	var node: Node = tree.root.get_node_or_null(target)
	if node != null:
		return node

	var entity_path: String = "Main/EntityRoot/%s" % target
	node = tree.root.get_node_or_null(entity_path)
	return node


func _generate_probe_script() -> String:
	return """extends Node

func _process(delta: float) -> void:
	if not get_meta("active", false):
		return

	var frame_count: int = get_meta("frame_count", 0)
	var max_frames: int = get_meta("max_frames", 300)

	if frame_count >= max_frames:
		set_meta("active", false)
		return

	var target_path: String = get_meta("target_path", "")
	var target: Node = get_node_or_null(target_path)
	if target == null:
		set_meta("active", false)
		return

	var fields: Array = get_meta("fields", [])
	var prev: Dictionary = get_meta("prev_snapshot", {})
	var current: Dictionary = {}
	var changed: bool = false

	for field in fields:
		var field_str: String = str(field)
		var value: Variant = target.get(field_str) if target.is_class("Node") else null
		if target is Node3D:
			match field_str:
				"position":
					value = [snapf(target.position.x, 0.001), snapf(target.position.y, 0.001), snapf(target.position.z, 0.001)]
				"rotation_degrees":
					value = [snapf(target.rotation_degrees.x, 0.001), snapf(target.rotation_degrees.y, 0.001), snapf(target.rotation_degrees.z, 0.001)]
				"scale":
					value = [snapf(target.scale.x, 0.001), snapf(target.scale.y, 0.001), snapf(target.scale.z, 0.001)]
				"visible":
					value = target.visible
				_:
					value = target.get(field_str)
		current[field_str] = value
		if not prev.has(field_str) or str(prev[field_str]) != str(value):
			changed = true

	frame_count += 1
	set_meta("frame_count", frame_count)

	if changed:
		var entry: Dictionary = {"f": frame_count, "t": snapf(Time.get_ticks_msec() / 1000.0, 0.001)}
		for key: String in current:
			entry[key] = current[key]
		var log_lines: PackedStringArray = get_meta("log_lines", PackedStringArray())
		log_lines.append(JSON.stringify(entry))
		set_meta("log_lines", log_lines)
		set_meta("prev_snapshot", current)
"""


func _fail(message: String, next_steps: Array) -> Dictionary:
	var result: Dictionary = {"success": false, "error": message, "layer": LAYER_PROBE}
	if not next_steps.is_empty():
		result["next_steps"] = next_steps
	return result
