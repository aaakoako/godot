## Transform2DComponent: stores 2D position for a game_entity.
## D1: data-only mirror of IR. No Node2D/visual binding yet.
class_name Transform2DComponent
extends Node

var position: Vector2 = Vector2.ZERO


## Sync from IR component dict.
func sync_from_ir(comp_data: Dictionary) -> void:
	var pos: Variant = comp_data.get("position", null)
	if pos is Array and (pos as Array).size() >= 2:
		var arr: Array = pos as Array
		position = Vector2(_to_float(arr[0]), _to_float(arr[1]))


func _to_float(value: Variant) -> float:
	if value is float:
		return value
	if value is int:
		return float(value)
	if value is String:
		return (value as String).to_float()
	return 0.0


func debug_summary() -> Dictionary:
	return {"component": "transform_2d", "position": [position.x, position.y]}
