## Headless regression suite for Sprint B.
## Run: godot --path . --headless -s res://tests/run_regression.gd
## Ensures Main/EntityRoot exist for IRManager, then runs golden-path cases and prints pass/fail summary.
extends Node

var _ir_manager: Node = null
var _total: int = 0
var _passed: int = 0
var _failed_ids: Array[String] = []


func _ready() -> void:
	call_deferred("_ensure_entity_root")


func _ensure_entity_root() -> void:
	var root: Node = get_tree().root
	if root.get_node_or_null("Main/EntityRoot") == null:
		var main: Node3D = Node3D.new()
		main.name = "Main"
		root.add_child(main)
		var entity_root: Node3D = Node3D.new()
		entity_root.name = "EntityRoot"
		main.add_child(entity_root)
	call_deferred("_run_after_ready")


func _run_after_ready() -> void:
	await get_tree().process_frame
	_ir_manager = get_tree().root.get_node_or_null("/root/IRManager")
	if _ir_manager == null:
		print("run_regression: ERROR - IRManager autoload not found")
		get_tree().quit(1)
		return
	_ir_manager.ensure_initial_state_loaded()
	await get_tree().process_frame
	await _run_regression()


func _run_regression() -> void:
	var cases: Array = _get_golden_path_cases()
	_total = cases.size()
	_passed = 0
	_failed_ids.clear()

	for case_dict: Dictionary in cases:
		var id: String = case_dict.get("id", "unknown")
		var pass_case: bool = await _run_one_case(case_dict)
		if pass_case:
			_passed += 1
			print("run_regression: PASS %s" % id)
		else:
			_failed_ids.append(id)
			print("run_regression: FAIL %s" % id)

	print("")
	print("run_regression: total=%d passed=%d failed=%d" % [_total, _passed, _total - _passed])
	if not _failed_ids.is_empty():
		print("run_regression: failed_ids=%s" % str(_failed_ids))
	get_tree().quit(0 if _failed_ids.is_empty() else 1)


func _run_one_case(case_dict: Dictionary) -> bool:
	var id: String = case_dict.get("id", "unknown")
	var patch_str: String = case_dict.get("patch", "")
	var acceptance_spec: Dictionary = case_dict.get("acceptance_spec", {})
	var expected_pass: bool = case_dict.get("expected_pass", true)
	var expected_error_layer: String = case_dict.get("expected_error_layer", "")

	if patch_str.is_empty():
		print("run_regression: skip %s (no patch)" % id)
		return true

	var ok: bool = false
	var error_layer: String = ""
	var timeout_frames: int = acceptance_spec.get("timeout_frames", 0)
	var checks: Array = acceptance_spec.get("checks", []) if acceptance_spec.get("checks") is Array else []
	var has_checks: bool = checks.size() > 0

	if has_checks and timeout_frames > 0:
		var apply_result: Dictionary = _ir_manager.apply_patch(patch_str, {}, id)
		if not apply_result.get("ok", false):
			ok = false
			error_layer = apply_result.get("error_layer", "")
		else:
			for _i in range(timeout_frames):
				await get_tree().process_frame
			var fin: Dictionary = _ir_manager.finalize_acceptance_after_delay(acceptance_spec, id)
			ok = fin.get("ok", true)
			error_layer = fin.get("error_layer", "")
	else:
		var result: Dictionary = _ir_manager.apply_patch(patch_str, acceptance_spec, id)
		ok = result.get("ok", false)
		error_layer = result.get("error_layer", "")

	if expected_pass:
		if ok:
			return true
		print("run_regression: %s expected PASS but got ok=false" % id)
		return false
	else:
		if not ok:
			if expected_error_layer.is_empty() or error_layer == expected_error_layer:
				return true
			print("run_regression: %s expected FAIL layer=%s but got error_layer=%s" % [id, expected_error_layer, error_layer])
			return false
		print("run_regression: %s expected FAIL but got ok=true" % id)
		return false


func _get_golden_path_cases() -> Array:
	return [
		_case_01_legal_position(),
		_case_02_illegal_path(),
		_case_03_test_op_failure(),
		_case_04_acceptance_failure(),
		_case_05_node_missing(),
	]


func _case_01_legal_position() -> Dictionary:
	var patch_str: String = JSON.stringify([
		{"op": "replace", "path": "/entities/box_1/transform/position", "value": [0, 0, -3]},
	])
	return {
		"id": "case_01_legal_position",
		"patch": patch_str,
		"acceptance_spec": {
			"timeout_frames": 2,
			"checks": [
				{"layer": "ir_state", "method": "exact_match", "path": "/entities/box_1/transform/position", "expected": [0, 0, -3]},
				{"layer": "projection", "method": "node_property_equals", "entity_id": "box_1", "property": "position", "expected": [0, 0, -3]},
			],
		},
		"expected_pass": true,
	}


func _case_02_illegal_path() -> Dictionary:
	var patch_str: String = JSON.stringify([
		{"op": "replace", "path": "/entities/nonexistent/transform/position", "value": [1, 1, 1]},
	])
	return {
		"id": "case_02_illegal_path",
		"patch": patch_str,
		"acceptance_spec": {},
		"expected_pass": false,
		"expected_error_layer": "patch_transaction",
	}


func _case_03_test_op_failure() -> Dictionary:
	var patch_str: String = JSON.stringify([
		{"op": "test", "path": "/entities/box_1/hp", "value": 999},
		{"op": "replace", "path": "/entities/box_1/hp", "value": 1},
	])
	return {
		"id": "case_03_test_op_failure",
		"patch": patch_str,
		"acceptance_spec": {},
		"expected_pass": false,
		"expected_error_layer": "patch_transaction",
	}


func _case_04_acceptance_failure() -> Dictionary:
	var patch_str: String = JSON.stringify([
		{"op": "replace", "path": "/entities/box_1/transform/position", "value": [1, 2, 3]},
	])
	return {
		"id": "case_04_acceptance_failure",
		"patch": patch_str,
		"acceptance_spec": {
			"timeout_frames": 0,
			"checks": [
				{"layer": "ir_state", "method": "exact_match", "path": "/entities/box_1/transform/position", "expected": [9, 9, 9]},
			],
		},
		"expected_pass": false,
		"expected_error_layer": "ir_state",
	}


func _case_05_node_missing() -> Dictionary:
	# Add entity with invalid type -> post-patch validation fails (ir_state). Projection never runs.
	var patch_str: String = JSON.stringify([
		{"op": "add", "path": "/entities/ghost_1", "value": {
			"type": "unknown",
			"transform": {"position": [0, 0, 0], "rotation": [0, 0, 0], "scale": [1, 1, 1]},
			"material": {"color": "#FFFFFF"},
		}},
	])
	return {
		"id": "case_05_node_missing",
		"patch": patch_str,
		"acceptance_spec": {},
		"expected_pass": false,
		"expected_error_layer": "ir_state",
	}
