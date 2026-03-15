## AttributeSetComponent: holds named attributes (hp, mana, etc.), each with current and max.
## Attached as a child of a game_entity Node host.
## Read from IR; write only through IRManager.apply_patch (Iron Law 3).
class_name AttributeSetComponent
extends Node

## Stores {attr_name: {current, max}} — mirror of IR data. Read-only from outside.
var attributes: Dictionary = {}


## Sync this component's in-memory state from the IR component dict.
func sync_from_ir(comp_data: Dictionary) -> void:
	var attrs: Variant = comp_data.get("attributes", {})
	if attrs is Dictionary:
		attributes = (attrs as Dictionary).duplicate(true)


## Return a single attribute dict {current, max} or empty dict if not found.
func get_attribute(attr_name: String) -> Dictionary:
	var val: Variant = attributes.get(attr_name, null)
	if val is Dictionary:
		return (val as Dictionary).duplicate()
	return {}


## Return the current value of an attribute, or null if missing.
func get_current(attr_name: String) -> Variant:
	var attr: Dictionary = get_attribute(attr_name)
	if attr.is_empty():
		return null
	return attr.get("current", null)


## Return a debug summary of all attributes.
func debug_summary() -> Dictionary:
	return {"component": "attribute_set", "attributes": attributes.duplicate(true)}
