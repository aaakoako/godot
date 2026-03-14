## UI Controller: simulates AI input for MVP testing.
## Provides preset and custom TOON Patch application via simple UI.
extends Control

@onready var _patch_input: TextEdit = $VBox/PatchInput
@onready var _result_label: Label = $VBox/ResultLabel

## Preset test patch: changes box_1 color to blue, moves it up, changes sphere_1 to yellow.
var _test_patch: String = "ops[4]{op,path,value}:\n  test,/entities/box_1/material/color,\"#FF0000\"\n  replace,/entities/box_1/material/color,\"#0000FF\"\n  replace,/entities/box_1/transform/position,\"0,2,0\"\n  replace,/entities/sphere_1/material/color,\"#FFFF00\""


func _ready() -> void:
	var ir_manager: Node = _get_ir_manager()
	if ir_manager == null:
		return
	ir_manager.patch_applied.connect(_on_patch_applied)
	ir_manager.patch_failed.connect(_on_patch_failed)
	ir_manager.ir_loaded.connect(_on_ir_loaded)


func _on_apply_patch_pressed() -> void:
	_result_label.text = "Applying test patch..."
	var ir_manager: Node = _get_ir_manager()
	if ir_manager == null:
		_result_label.text = "ERROR: IRManager not found"
		return
	ir_manager.apply_patch(_test_patch)


func _on_apply_custom_pressed() -> void:
	var custom_patch: String = _patch_input.text.strip_edges()
	if custom_patch.is_empty():
		_result_label.text = "ERROR: patch input is empty"
		return
	_result_label.text = "Applying custom patch..."
	var ir_manager: Node = _get_ir_manager()
	if ir_manager == null:
		_result_label.text = "ERROR: IRManager not found"
		return
	ir_manager.apply_patch(custom_patch)


func _on_patch_applied(patch_ops: Array) -> void:
	_result_label.text = "OK: %d ops applied successfully" % patch_ops.size()


func _on_patch_failed(reason: String) -> void:
	_result_label.text = "FAIL: %s" % reason


func _on_ir_loaded() -> void:
	_result_label.text = "IR loaded. Ready for patches."


func _get_ir_manager() -> Node:
	return get_node_or_null("/root/IRManager")
