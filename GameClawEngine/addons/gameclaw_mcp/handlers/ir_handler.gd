## Handler for IR-layer MCP commands.
## Covers: IR Input layer, Patch Transaction layer, IR State layer.
## All methods return structured results with layer annotation for debug methodology.
class_name MCPIRHandler
extends RefCounted

const LAYER_IR_INPUT: String = "ir_input"
const LAYER_PATCH_TRANSACTION: String = "patch_transaction"
const LAYER_IR_STATE: String = "ir_state"


## Register all IR-related tools on the given router.
static func register_tools(router: MCPCommandRouter) -> void:
	var handler := MCPIRHandler.new()
	router.register_handler_instance(handler)
	router.register("get_ir_state", handler._handle_get_ir_state)
	router.register("apply_patch", handler._handle_apply_patch)
	router.register("query_ir_path", handler._handle_query_ir_path)
	router.register("get_patch_history", handler._handle_get_patch_history)
	router.register("validate_ir", handler._handle_validate_ir)
	router.register("rollback_last", handler._handle_rollback_last)


func _handle_get_ir_state(params: Variant) -> Dictionary:
	var ir_manager: Node = _get_ir_manager()
	if ir_manager == null:
		return _fail("IRManager autoload not found", LAYER_IR_STATE, ["Ensure IRManager is registered in project.godot autoloads."])

	var state: Dictionary = ir_manager.get_ir_state()
	return {"success": true, "data": {"state": state, "entity_count": state.get("entities", {}).size()}}


func _handle_apply_patch(params: Variant) -> Dictionary:
	if params is not Dictionary:
		return _fail("params must be a Dictionary with 'patch' field", LAYER_IR_INPUT, ["Provide {\"patch\": \"<TOON or JSON patch string>\"}"])

	var p: Dictionary = params as Dictionary
	var patch_str: Variant = p.get("patch", "")
	if patch_str is not String or (patch_str as String).is_empty():
		return _fail("'patch' field must be a non-empty string", LAYER_IR_INPUT, ["Provide a valid TOON or JSON encoded patch."])

	var acceptance_spec: Dictionary = p.get("acceptance_spec", {}) if p.get("acceptance_spec") is Dictionary else {}
	var request_id: String = str(p.get("request_id", ""))

	var ir_manager: Node = _get_ir_manager()
	if ir_manager == null:
		return _fail("IRManager autoload not found", LAYER_PATCH_TRANSACTION, [])

	var result: Dictionary = ir_manager.apply_patch(patch_str as String, acceptance_spec, request_id)
	if result.get("ok", false):
		var data: Dictionary = {"applied": true, "entity_count": ir_manager.get_ir_state().get("entities", {}).size()}
		if result.has("verification"):
			data["verification"] = result["verification"]
		return {"success": true, "data": data, "evidence": null}

	var reason: String = result.get("reason", "Patch application failed — check Godot console for details")
	var layer: String = result.get("error_layer", LAYER_PATCH_TRANSACTION)
	var next_steps: Array = [
		"Call 'get_ir_state' to inspect current state.",
		"Call 'read_godot_log' to see error details.",
		"Verify patch paths exist with 'query_ir_path'.",
	]
	var out: Dictionary = {"success": false, "error": reason, "layer": layer, "next_steps": next_steps}
	if result.get("evidence_path", "").is_empty() == false:
		out["evidence_path"] = result["evidence_path"]
	return out


func _handle_query_ir_path(params: Variant) -> Dictionary:
	if params is not Dictionary:
		return _fail("params must be a Dictionary with 'path' field", LAYER_IR_STATE, [])

	var path: Variant = (params as Dictionary).get("path", "")
	if path is not String or (path as String).is_empty():
		return _fail("'path' field must be a non-empty string starting with '/'", LAYER_IR_STATE, [])

	var ir_manager: Node = _get_ir_manager()
	if ir_manager == null:
		return _fail("IRManager autoload not found", LAYER_IR_STATE, [])

	var state: Dictionary = ir_manager.get_ir_state()
	var resolved: Variant = _resolve_path(state, path as String)
	if resolved is Dictionary and (resolved as Dictionary).has("__not_found__"):
		return _fail(
			"Path '%s' not found in IR state" % (path as String),
			LAYER_IR_STATE,
			["Call 'get_ir_state' to see the full state tree.", "Check for typos in entity IDs or field names."]
		)

	return {"success": true, "data": {"path": path, "value": resolved}}


func _handle_get_patch_history(params: Variant) -> Dictionary:
	var ir_manager: Node = _get_ir_manager()
	if ir_manager == null:
		return _fail("IRManager autoload not found", LAYER_PATCH_TRANSACTION, [])

	var history: Array = ir_manager.get_patch_history()
	var summary: Array = []
	for i: int in range(history.size()):
		var entry: Dictionary = history[i]
		var ops: Array = entry.get("ops", [])
		summary.append({"index": i, "op_count": ops.size(), "ops": ops})

	return {"success": true, "data": {"count": history.size(), "patches": summary}}


func _handle_validate_ir(params: Variant) -> Dictionary:
	if params is not Dictionary:
		return _fail("params must be a Dictionary with 'data' field", LAYER_IR_INPUT, [])

	var data: Variant = (params as Dictionary).get("data")
	if data == null:
		return _fail("'data' field is required", LAYER_IR_INPUT, ["Provide the IR Dictionary to validate."])

	var validator := IRValidator.new()
	var result: Dictionary = validator.validate(data)
	if result["valid"]:
		return {"success": true, "data": {"valid": true}}
	else:
		return _fail(
			"Validation failed: %s" % result.get("error", "unknown"),
			LAYER_IR_INPUT,
			["Fix the reported field and re-validate.", "Check schemas/game_ir_v1.toon for the expected schema."]
		)


func _handle_rollback_last(params: Variant) -> Dictionary:
	var ir_manager: Node = _get_ir_manager()
	if ir_manager == null:
		return _fail("IRManager autoload not found", LAYER_PATCH_TRANSACTION, [])

	var success: bool = ir_manager.rollback_last()
	if not success:
		return _fail("No patches to rollback", LAYER_PATCH_TRANSACTION, ["Patch history is empty."])

	var state: Dictionary = ir_manager.get_ir_state()
	return {"success": true, "data": {"rolled_back": true, "entity_count": state.get("entities", {}).size()}}


## Resolve a slash-separated path against a nested Dictionary/Array structure.
func _resolve_path(state: Dictionary, path: String) -> Variant:
	if not path.begins_with("/"):
		return {"__not_found__": true}

	var segments: PackedStringArray = path.substr(1).split("/")
	var current: Variant = state

	for seg: String in segments:
		if current is Dictionary:
			if not (current as Dictionary).has(seg):
				return {"__not_found__": true}
			current = (current as Dictionary)[seg]
		elif current is Array:
			if not seg.is_valid_int():
				return {"__not_found__": true}
			var idx: int = seg.to_int()
			if idx < 0 or idx >= (current as Array).size():
				return {"__not_found__": true}
			current = (current as Array)[idx]
		else:
			return {"__not_found__": true}

	return current


func _get_ir_manager() -> Node:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	if tree == null:
		return null
	return tree.root.get_node_or_null("/root/IRManager")


func _fail(message: String, layer: String, next_steps: Array) -> Dictionary:
	var result: Dictionary = {"success": false, "error": message, "layer": layer}
	if not next_steps.is_empty():
		result["next_steps"] = next_steps
	return result
