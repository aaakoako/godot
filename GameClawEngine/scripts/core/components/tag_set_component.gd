## TagSetComponent: holds base_tags (immutable identity) and runtime_tags (dynamic state).
## base_tags: set at entity creation; never changed by effects.
## runtime_tags: added/removed by Gameplay Effects via IRManager.apply_patch.
class_name TagSetComponent
extends Node

var base_tags: Array[String] = []
var runtime_tags: Array[String] = []


## Sync from IR component dict.
func sync_from_ir(comp_data: Dictionary) -> void:
	var bt: Variant = comp_data.get("base_tags", [])
	if bt is Array:
		base_tags.clear()
		for t: Variant in (bt as Array):
			base_tags.append(str(t))

	var rt: Variant = comp_data.get("runtime_tags", [])
	if rt is Array:
		runtime_tags.clear()
		for t: Variant in (rt as Array):
			runtime_tags.append(str(t))


## Return true if the tag is present in either base or runtime tags.
func has_tag(tag: String) -> bool:
	return tag in base_tags or tag in runtime_tags


## Return true if the tag is in runtime_tags.
func has_runtime_tag(tag: String) -> bool:
	return tag in runtime_tags


## Return all tags (base + runtime), deduplicated.
func all_tags() -> Array[String]:
	var combined: Array[String] = []
	for t: String in base_tags:
		if t not in combined:
			combined.append(t)
	for t: String in runtime_tags:
		if t not in combined:
			combined.append(t)
	return combined


func debug_summary() -> Dictionary:
	return {"component": "tag_set", "base_tags": base_tags.duplicate(), "runtime_tags": runtime_tags.duplicate()}
