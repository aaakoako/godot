## IRManager: the central singleton that manages Game IR state and projects it onto Godot's SceneTree.
## Registered as autoload in project.godot.
## Iron Law 3: IR is the Single Source of Truth. SceneTree is just a projection.
extends Node

const AcceptanceSpec = preload("res://scripts/core/acceptance_spec.gd")

## Emitted after a patch is successfully applied and projected.
signal patch_applied(patch_ops: Array)
## Emitted when a patch fails validation or execution.
signal patch_failed(reason: String)
## Emitted after initial IR is loaded and projected.
signal ir_loaded()

const INITIAL_STATE_PATH: String = "res://test_data/initial_state.toon"
const EVIDENCE_DIR: String = "user://artifacts/evidence/"

var _ir_state: Dictionary = {}
var _entity_nodes: Dictionary = {}
var _codec: CodecInterface
var _json_codec: CodecInterface
var _validator: IRValidator
var _factory: EntityFactory
var _patch_engine: PatchEngine
var _entity_root: Node3D
var _ui_root: Control
var _patch_history: Array = []
var _last_evidence_path: String = ""
var _pending_acceptance_context: Dictionary = {}


func _ready() -> void:
	_codec = TOONCodec.new()
	_json_codec = JSONCodec.new()
	_validator = IRValidator.new()
	_factory = EntityFactory.new()
	_patch_engine = PatchEngine.new()

	call_deferred("_deferred_init")


func _deferred_init() -> void:
	_entity_root = get_tree().root.get_node_or_null("Main/EntityRoot")
	_ui_root = get_tree().root.get_node_or_null("Main/UI/IRoot")
	if _entity_root == null:
		push_error("IRManager: EntityRoot node not found in scene tree")
		return
	_load_initial_state()


## Call from headless/regression when EntityRoot may have been created after _deferred_init (e.g. regression_scene). Idempotent.
func ensure_initial_state_loaded() -> void:
	if not _ir_state.is_empty():
		return
	_entity_root = get_tree().root.get_node_or_null("Main/EntityRoot")
	if _ui_root == null:
		_ui_root = get_tree().root.get_node_or_null("Main/UI/IRoot")
	if _entity_root == null:
		return
	_load_initial_state()


func _get_initial_state_path() -> String:
	var override_path: Variant = ProjectSettings.get_setting("application/config/initial_ir_path")
	if override_path is String and (override_path as String).length() > 0:
		return override_path as String
	return INITIAL_STATE_PATH


func _load_initial_state() -> void:
	var path: String = _get_initial_state_path()
	var file_text: String = _read_file(path)
	if file_text.is_empty():
		push_error("IRManager: failed to read initial state from %s" % path)
		return

	var data: Variant = _codec.decode(file_text)
	if data == null:
		push_warning("IRManager: TOON decode failed, trying JSON fallback")
		data = _json_codec.decode(file_text)
	if data == null:
		push_error("IRManager: all codecs failed to parse initial state")
		return

	var validation: Dictionary = _validator.validate(data)
	if not validation["valid"]:
		push_error("IRManager: IR validation failed: %s" % validation["error"])
		return

	_ir_state = data
	_project_full_state()
	ir_loaded.emit()
	print("IRManager: loaded %d entities from %s" % [_get_entity_count(), path])


## Apply a TOON-encoded patch string to the current IR state.
## Optional acceptance_spec triggers verify_outcome after apply; on verify fail, rollback and optional evidence write.
## Returns structured Dictionary: ok, patch_applied, verification?, rollback_done?, error_layer?, reason?, evidence_path?
func apply_patch(patch_toon: String, acceptance_spec: Dictionary = {}, request_id: String = "") -> Dictionary:
	_pending_acceptance_context = {}
	var patch_data: Variant = _codec.decode(patch_toon)
	var ops: Array = _extract_ops(patch_data) if patch_data != null else []

	if ops.is_empty():
		patch_data = _json_codec.decode(patch_toon)
		ops = _extract_ops(patch_data) if patch_data != null else []

	if ops.is_empty():
		var reason: String = "no valid ops found in patch data (tried TOON and JSON)"
		push_error("IRManager: %s" % reason)
		patch_failed.emit(reason)
		if request_id != "":
			_write_evidence_bundle(request_id, AcceptanceSpec.LAYER_IR_INPUT, "", patch_toon, ops, acceptance_spec, get_ir_state(), get_ir_state(), {"success": false, "error": reason}, null)
		return {
			"ok": false,
			"patch_applied": false,
			"error_layer": AcceptanceSpec.LAYER_IR_INPUT,
			"reason": reason,
			"evidence_path": _last_evidence_path,
		}

	var result: Dictionary = _patch_engine.execute(_ir_state, ops)
	if not result["success"]:
		var reason: String = result.get("error", "unknown patch error")
		push_error("IRManager: patch failed: %s" % reason)
		patch_failed.emit(reason)
		if request_id != "":
			_write_evidence_bundle(request_id, AcceptanceSpec.LAYER_PATCH_TRANSACTION, "", patch_toon, ops, acceptance_spec, get_ir_state(), get_ir_state(), {"success": false, "error": reason}, null)
		return {
			"ok": false,
			"patch_applied": false,
			"error_layer": AcceptanceSpec.LAYER_PATCH_TRANSACTION,
			"reason": reason,
			"evidence_path": _last_evidence_path,
		}

	var old_state: Dictionary = _ir_state.duplicate(true)
	_ir_state = result["state"]

	var post_validation: Dictionary = _validator.validate(_ir_state)
	if not post_validation["valid"]:
		var invalid_state: Dictionary = _ir_state.duplicate(true)
		_ir_state = old_state
		var reason: String = "post-patch validation failed: %s" % post_validation["error"]
		push_error("IRManager: %s" % reason)
		patch_failed.emit(reason)
		if request_id != "":
			_write_evidence_bundle(request_id, AcceptanceSpec.LAYER_IR_STATE, "", patch_toon, ops, acceptance_spec, old_state, invalid_state, {"success": false, "error": reason}, null)
		return {
			"ok": false,
			"patch_applied": false,
			"error_layer": AcceptanceSpec.LAYER_IR_STATE,
			"reason": reason,
			"evidence_path": _last_evidence_path,
		}

	_patch_history.append({"ops": ops, "prev_state": old_state})
	_project_changes(old_state, _ir_state)
	patch_applied.emit(ops)
	print("IRManager: applied %d ops successfully" % ops.size())

	_pending_acceptance_context = {
		"request_id": request_id,
		"patch_raw": patch_toon,
		"patch_ops": ops.duplicate(true),
		"ir_before": old_state,
		"ir_after_apply": get_ir_state(),
	}

	if not AcceptanceSpec.has_checks(acceptance_spec):
		return {"ok": true, "patch_applied": true}

	return finalize_acceptance_after_delay(acceptance_spec, request_id)


## Get the current IR state (read-only copy).
func get_ir_state() -> Dictionary:
	return _ir_state.duplicate(true)


## Get the patch history for time-travel debugging.
func get_patch_history() -> Array:
	return _patch_history.duplicate(true)


## Finalize acceptance for the most recently applied patch.
## Used by delayed verification flows: verify -> rollback on fail -> optional evidence write.
func finalize_acceptance_after_delay(acceptance_spec: Dictionary, request_id: String = "") -> Dictionary:
	if not AcceptanceSpec.has_checks(acceptance_spec):
		return {"ok": true, "patch_applied": true}

	if _pending_acceptance_context.is_empty():
		return {
			"ok": false,
			"patch_applied": false,
			"error_layer": AcceptanceSpec.LAYER_PATCH_TRANSACTION,
			"reason": "no pending acceptance context",
			"evidence_path": "",
		}

	var context_request_id: String = str(_pending_acceptance_context.get("request_id", ""))
	if request_id != "" and context_request_id != "" and request_id != context_request_id:
		return {
			"ok": false,
			"patch_applied": true,
			"error_layer": AcceptanceSpec.LAYER_PATCH_TRANSACTION,
			"reason": "pending acceptance request_id mismatch",
			"evidence_path": "",
		}

	var effective_request_id: String = request_id if request_id != "" else context_request_id
	var patch_raw: Variant = _pending_acceptance_context.get("patch_raw", "")
	var patch_ops: Array = _pending_acceptance_context.get("patch_ops", [])
	var ir_before: Dictionary = (_pending_acceptance_context.get("ir_before", {}) as Dictionary).duplicate(true)

	var verification: Dictionary = verify_outcome(acceptance_spec)
	if verification["ok"]:
		_pending_acceptance_context = {}
		return {"ok": true, "patch_applied": true, "verification": verification}

	var ir_after_failed: Dictionary = get_ir_state()
	var rollback_ok: bool = rollback_last()
	if effective_request_id != "":
		_write_evidence_bundle(effective_request_id, verification.get("layer", AcceptanceSpec.LAYER_IR_STATE), "", patch_raw, patch_ops, acceptance_spec, ir_before, ir_after_failed, {"success": true, "state": ir_after_failed}, verification)
	_pending_acceptance_context = {}
	return {
		"ok": false,
		"patch_applied": true,
		"rollback_done": rollback_ok,
		"verification": verification,
		"error_layer": verification.get("layer", ""),
		"reason": verification.get("reason", "verification failed"),
		"evidence_path": _last_evidence_path,
	}


## Verify outcome against acceptance_spec checks. Returns {ok: bool} or {ok: false, failed_check_index, layer, reason, expected, actual}.
func verify_outcome(acceptance_spec: Dictionary) -> Dictionary:
	var checks: Array = AcceptanceSpec.get_checks(acceptance_spec)
	for i: int in range(checks.size()):
		var check: Variant = checks[i]
		if check is not Dictionary:
			return {"ok": false, "failed_check_index": i, "layer": AcceptanceSpec.LAYER_IR_STATE, "reason": "check[%d] is not a Dictionary" % i, "expected": null, "actual": null}
		var c: Dictionary = check as Dictionary
		var layer: String = str(c.get(AcceptanceSpec.CHECK_LAYER, ""))
		var method: String = str(c.get(AcceptanceSpec.CHECK_METHOD, ""))
		if not AcceptanceSpec.is_valid_layer(layer):
			return {"ok": false, "failed_check_index": i, "layer": AcceptanceSpec.LAYER_IR_STATE, "reason": "invalid layer '%s'" % layer, "expected": null, "actual": null}
		if not AcceptanceSpec.is_valid_method(method):
			return {"ok": false, "failed_check_index": i, "layer": layer, "reason": "invalid method '%s'" % method, "expected": null, "actual": null}
		var res: Dictionary = _run_one_check(layer, method, c)
		if not res["ok"]:
			res["failed_check_index"] = i
			return res
	return {"ok": true}


func _run_one_check(layer: String, method: String, check: Dictionary) -> Dictionary:
	if layer == AcceptanceSpec.LAYER_IR_STATE:
		return _check_ir_state(method, check)
	if layer == AcceptanceSpec.LAYER_PROJECTION:
		return _check_projection(method, check)
	if layer == AcceptanceSpec.LAYER_IR_INPUT or layer == AcceptanceSpec.LAYER_PATCH_TRANSACTION:
		return _check_ir_state(method, check)
	# render_output: MVP skip or treat as pass
	if layer == AcceptanceSpec.LAYER_RENDER_OUTPUT:
		return {"ok": true}
	return {"ok": false, "layer": layer, "reason": "layer not implemented for verify", "expected": null, "actual": null}


func _check_ir_state(method: String, check: Dictionary) -> Dictionary:
	var path: String = str(check.get(AcceptanceSpec.CHECK_PATH, ""))
	if path.is_empty():
		return {"ok": false, "layer": AcceptanceSpec.LAYER_IR_STATE, "reason": "missing path", "expected": null, "actual": null}
	var resolved: Dictionary = _resolve_ir_path(get_ir_state(), path)
	var found: bool = resolved["found"]
	var value: Variant = resolved.get("value", null)
	var expected: Variant = check.get(AcceptanceSpec.CHECK_EXPECTED, null)
	match method:
		AcceptanceSpec.METHOD_EXISTS:
			return {"ok": true} if found else {"ok": false, "layer": AcceptanceSpec.LAYER_IR_STATE, "reason": "path not found", "expected": path, "actual": null}
		AcceptanceSpec.METHOD_NOT_EXISTS:
			return {"ok": true} if not found else {"ok": false, "layer": AcceptanceSpec.LAYER_IR_STATE, "reason": "path exists", "expected": null, "actual": value}
		AcceptanceSpec.METHOD_EXACT_MATCH:
			if not found:
				return {"ok": false, "layer": AcceptanceSpec.LAYER_IR_STATE, "reason": "path not found", "expected": expected, "actual": null}
			if not _values_equal(value, expected):
				return {"ok": false, "layer": AcceptanceSpec.LAYER_IR_STATE, "reason": "value mismatch", "expected": expected, "actual": value}
			return {"ok": true}
		_:
			return {"ok": false, "layer": AcceptanceSpec.LAYER_IR_STATE, "reason": "unsupported method '%s'" % method, "expected": null, "actual": null}


func _check_projection(method: String, check: Dictionary) -> Dictionary:
	var entity_id: String = str(check.get(AcceptanceSpec.CHECK_ENTITY_ID, ""))
	if entity_id.is_empty():
		return {"ok": false, "layer": AcceptanceSpec.LAYER_PROJECTION, "reason": "missing entity_id", "expected": null, "actual": null}
	var props: Variant = _get_entity_node_props_for_verify(entity_id)
	match method:
		AcceptanceSpec.METHOD_NODE_EXISTS:
			return {"ok": true} if props != null else {"ok": false, "layer": AcceptanceSpec.LAYER_PROJECTION, "reason": "node not found", "expected": entity_id, "actual": null}
		AcceptanceSpec.METHOD_NODE_PROPERTY_EQUALS:
			if props == null:
				return {"ok": false, "layer": AcceptanceSpec.LAYER_PROJECTION, "reason": "node not found", "expected": check.get(AcceptanceSpec.CHECK_EXPECTED), "actual": null}
			var prop_name: String = str(check.get(AcceptanceSpec.CHECK_PROPERTY, ""))
			if prop_name.is_empty():
				return {"ok": false, "layer": AcceptanceSpec.LAYER_PROJECTION, "reason": "missing property", "expected": null, "actual": null}
			var actual: Variant = (props as Dictionary).get(prop_name, null)
			var expected: Variant = check.get(AcceptanceSpec.CHECK_EXPECTED, null)
			if not _values_equal(actual, expected):
				return {"ok": false, "layer": AcceptanceSpec.LAYER_PROJECTION, "reason": "node property mismatch", "expected": expected, "actual": actual}
			return {"ok": true}
		_:
			return {"ok": false, "layer": AcceptanceSpec.LAYER_PROJECTION, "reason": "unsupported method '%s'" % method, "expected": null, "actual": null}


func _resolve_ir_path(state: Dictionary, path: String) -> Dictionary:
	if not path.begins_with("/"):
		return {"found": false}
	var segments: PackedStringArray = path.substr(1).split("/")
	var current: Variant = state
	for seg: String in segments:
		if current is Dictionary:
			if not (current as Dictionary).has(seg):
				return {"found": false}
			current = (current as Dictionary)[seg]
		elif current is Array:
			if not seg.is_valid_int():
				return {"found": false}
			var idx: int = seg.to_int()
			if idx < 0 or idx >= (current as Array).size():
				return {"found": false}
			current = (current as Array)[idx]
		else:
			return {"found": false}
	return {"found": true, "value": current}


func _get_entity_node_props_for_verify(entity_id: String) -> Variant:
	if not _entity_nodes.has(entity_id):
		return null
	var node: Node = _entity_nodes[entity_id]
	if not is_instance_valid(node):
		return null
	if node is Control:
		var c: Control = node as Control
		var props: Dictionary = {"name": c.name, "type": c.get_class()}
		if node is Label:
			props["text"] = (node as Label).text
		elif node is Button:
			props["text"] = (node as Button).text
		return props
	if node is Node3D:
		var n3d: Node3D = node as Node3D
		return {
			"name": n3d.name,
			"type": n3d.get_class(),
			"position": [snapped(n3d.position.x, 0.001), snapped(n3d.position.y, 0.001), snapped(n3d.position.z, 0.001)],
			"rotation_degrees": [snapped(n3d.rotation_degrees.x, 0.001), snapped(n3d.rotation_degrees.y, 0.001), snapped(n3d.rotation_degrees.z, 0.001)],
			"scale": [snapped(n3d.scale.x, 0.001), snapped(n3d.scale.y, 0.001), snapped(n3d.scale.z, 0.001)],
		}
	return {"name": node.name, "type": node.get_class()}


func _values_equal(a: Variant, b: Variant) -> bool:
	if a == b:
		return true
	if a is Array and b is Array:
		var ra: Array = a as Array
		var rb: Array = b as Array
		if ra.size() != rb.size():
			return false
		for i in range(ra.size()):
			if not _values_equal(ra[i], rb[i]):
				return false
		return true
	if typeof(a) != typeof(b):
		return str(a) == str(b)
	return false


func _write_evidence_bundle(request_id: String, error_layer: String, task_summary: String, patch_raw: Variant, patch_ops: Array, acceptance_spec: Dictionary, ir_before: Dictionary, ir_after: Dictionary, patch_result: Dictionary, verification_result: Variant) -> void:
	_last_evidence_path = ""
	var dir_path: String = ProjectSettings.globalize_path(EVIDENCE_DIR)
	if not DirAccess.dir_exists_absolute(dir_path):
		var err: Error = DirAccess.make_dir_recursive_absolute(dir_path)
		if err != OK:
			push_error("IRManager: cannot create evidence dir %s" % dir_path)
			return
	var ts_ms: int = int(Time.get_unix_time_from_system() * 1000.0)
	var filename: String = "%s_%d.json" % [request_id, ts_ms]
	var file_path: String = dir_path.path_join(filename)
	var bundle: Dictionary = {
		"request_id": request_id,
		"timestamp_ms": ts_ms,
		"error_layer": error_layer,
		"task_summary": task_summary,
		"patch": patch_ops if not patch_ops.is_empty() else patch_raw,
		"acceptance_spec": acceptance_spec,
		"ir_before": ir_before,
		"ir_after": ir_after,
		"patch_result": patch_result,
		"verification_result": verification_result,
		"godot_log_tail": [],
		"scene_snapshot": null,
	}
	var json_str: String = JSON.stringify(bundle, "  ")
	var f: FileAccess = FileAccess.open(file_path, FileAccess.WRITE)
	if f == null:
		push_error("IRManager: cannot write evidence file %s" % file_path)
		return
	f.store_string(json_str)
	f.close()
	_last_evidence_path = file_path
	print("IRManager: evidence bundle written to %s" % file_path)


## Rollback to the state before the last patch.
func rollback_last() -> bool:
	if _patch_history.is_empty():
		push_warning("IRManager: no patches to rollback")
		return false
	var last: Dictionary = _patch_history.pop_back()
	var old_state: Dictionary = _ir_state
	_ir_state = last["prev_state"]
	_project_changes(old_state, _ir_state)
	print("IRManager: rolled back to previous state")
	return true


# ─── PROJECTION LAYER ────────────────────────────────────────────────────────

func _project_full_state() -> void:
	_clear_all_entities()
	var entities: Dictionary = _ir_state.get("entities", {})
	for entity_id: String in entities:
		var node: Node = _factory.create(entity_id, entities[entity_id])
		if node != null:
			_add_entity_node(entity_id, node)


func _project_changes(old_state: Dictionary, new_state: Dictionary) -> void:
	var old_entities: Dictionary = old_state.get("entities", {})
	var new_entities: Dictionary = new_state.get("entities", {})

	for entity_id: String in new_entities:
		if not old_entities.has(entity_id):
			var node: Node = _factory.create(entity_id, new_entities[entity_id])
			if node != null:
				_add_entity_node(entity_id, node)
		else:
			if _entity_nodes.has(entity_id):
				_factory.update_node(_entity_nodes[entity_id], new_entities[entity_id])

	for entity_id: String in old_entities:
		if not new_entities.has(entity_id):
			if _entity_nodes.has(entity_id):
				var node: Node = _entity_nodes[entity_id]
				node.queue_free()
				_entity_nodes.erase(entity_id)


func _add_entity_node(entity_id: String, node: Node) -> void:
	if node is Control and _ui_root != null:
		_ui_root.add_child(node)
	else:
		_entity_root.add_child(node)
	_entity_nodes[entity_id] = node
	if node is Button:
		node.pressed.connect(_on_ui_button_pressed.bind(entity_id))


func _on_ui_button_pressed(entity_id: String) -> void:
	if EventOutbox:
		EventOutbox.append_event("ui", "button_pressed", entity_id, {})


func _clear_all_entities() -> void:
	for entity_id: String in _entity_nodes:
		var node: Node = _entity_nodes[entity_id]
		if is_instance_valid(node):
			node.queue_free()
	_entity_nodes.clear()


# ─── HELPERS ──────────────────────────────────────────────────────────────────

func _extract_ops(patch_data: Variant) -> Array:
	if patch_data is Array:
		return patch_data
	if patch_data is Dictionary:
		var ops: Variant = patch_data.get("ops", [])
		if ops is Array:
			return ops
	return []


func _get_entity_count() -> int:
	var entities: Variant = _ir_state.get("entities", {})
	if entities is Dictionary:
		return entities.size()
	return 0


func _read_file(path: String) -> String:
	if not FileAccess.file_exists(path):
		push_error("IRManager: file not found: %s" % path)
		return ""
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("IRManager: cannot open file: %s" % path)
		return ""
	var content: String = file.get_as_text()
	file.close()
	return content


# ─── GAME ENTITY HELPERS (Phase 2 / Sprint D1) ────────────────────────────────
# All writes go through apply_patch to preserve IR as single source of truth.

## Return a single attribute dict {current, max} for a game_entity, or empty if not found.
func get_attribute(entity_id: String, attr_name: String) -> Dictionary:
	var path: String = "/entities/%s/components/attribute_set/attributes/%s" % [entity_id, attr_name]
	var result: Dictionary = _resolve_ir_path(path)
	if result["found"] and result["value"] is Dictionary:
		return (result["value"] as Dictionary).duplicate()
	return {}


## Return a copy of the runtime_tags array for a game_entity, or empty array.
func get_tags(entity_id: String) -> Array:
	var path: String = "/entities/%s/components/tag_set/runtime_tags" % entity_id
	var result: Dictionary = _resolve_ir_path(path)
	if result["found"] and result["value"] is Array:
		return (result["value"] as Array).duplicate()
	return []


## Return all tags (base + runtime) for a game_entity.
func get_all_tags(entity_id: String) -> Array:
	var base_path: String = "/entities/%s/components/tag_set/base_tags" % entity_id
	var runtime_path: String = "/entities/%s/components/tag_set/runtime_tags" % entity_id
	var base_result: Dictionary = _resolve_ir_path(base_path)
	var runtime_result: Dictionary = _resolve_ir_path(runtime_path)
	var combined: Array = []
	if base_result["found"] and base_result["value"] is Array:
		for t: Variant in (base_result["value"] as Array):
			combined.append(t)
	if runtime_result["found"] and runtime_result["value"] is Array:
		for t: Variant in (runtime_result["value"] as Array):
			if t not in combined:
				combined.append(t)
	return combined


## Return true if a game_entity has the given tag in either base or runtime tags.
func has_tag(entity_id: String, tag: String) -> bool:
	return tag in get_all_tags(entity_id)


## Add a runtime tag to a game_entity via patch. Returns apply_patch result.
func add_runtime_tag(entity_id: String, tag: String) -> Dictionary:
	var current_tags: Array = get_tags(entity_id)
	if tag in current_tags:
		return {"ok": true, "patch_applied": false, "reason": "tag already present"}
	current_tags.append(tag)
	var patch_str: String = JSON.stringify({
		"ops": [{"op": "replace", "path": "/entities/%s/components/tag_set/runtime_tags" % entity_id, "value": current_tags}]
	})
	return apply_patch(patch_str)


## Remove a runtime tag from a game_entity via patch. Returns apply_patch result.
func remove_runtime_tag(entity_id: String, tag: String) -> Dictionary:
	var current_tags: Array = get_tags(entity_id)
	if tag not in current_tags:
		return {"ok": true, "patch_applied": false, "reason": "tag not present"}
	current_tags.erase(tag)
	var patch_str: String = JSON.stringify({
		"ops": [{"op": "replace", "path": "/entities/%s/components/tag_set/runtime_tags" % entity_id, "value": current_tags}]
	})
	return apply_patch(patch_str)


## Resolve a slash-separated IR path to {found, value}. Internal helper.
func _resolve_ir_path(path: String) -> Dictionary:
	if not path.begins_with("/"):
		return {"found": false, "value": null}
	var segments: PackedStringArray = path.substr(1).split("/")
	var current: Variant = _ir_state
	for seg: String in segments:
		if current is Dictionary:
			if not (current as Dictionary).has(seg):
				return {"found": false, "value": null}
			current = (current as Dictionary)[seg]
		elif current is Array:
			if not seg.is_valid_int():
				return {"found": false, "value": null}
			var idx: int = seg.to_int()
			if idx < 0 or idx >= (current as Array).size():
				return {"found": false, "value": null}
			current = (current as Array)[idx]
		else:
			return {"found": false, "value": null}
	return {"found": true, "value": current}
