## PresentationComponent: stores asset references for the entity's visual representation.
## D1: data-only. Actual node creation deferred to Phase 3 (Asset Layer).
## icon_ref / model_ref are semantic strings like "sprite2d://hero_knight_icon".
class_name PresentationComponent
extends Node

var icon_ref: String = ""
var model_ref: String = ""


## Sync from IR component dict.
func sync_from_ir(comp_data: Dictionary) -> void:
	var ir: Variant = comp_data.get("icon_ref", "")
	icon_ref = str(ir) if ir != null else ""
	var mr: Variant = comp_data.get("model_ref", "")
	model_ref = str(mr) if mr != null else ""


func debug_summary() -> Dictionary:
	return {"component": "presentation", "icon_ref": icon_ref, "model_ref": model_ref}
