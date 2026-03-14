## IR Schema Validator: validates decoded IR data against Game IR v1 schema.
## All AI-output IR must pass validation before entering the engine (Iron Law 7).
class_name IRValidator
extends RefCounted

var _valid_entity_types: Array[String] = ["cube", "sphere", "plane", "sprite", "combat_dummy", "label", "button"]
const COLOR_PATTERN: String = "^#[0-9A-Fa-f]{6}$"
const SPRINT_C1_TYPES: Array[String] = ["combat_dummy", "label", "button"]

var _color_re: RegEx


func _init() -> void:
	_color_re = RegEx.new()
	_color_re.compile(COLOR_PATTERN)


## Validate a full IR state dictionary.
## Returns {"valid": true} or {"valid": false, "error": "description"}.
func validate(data: Variant) -> Dictionary:
	if data is not Dictionary:
		return _fail("IR root must be a Dictionary, got %s" % type_string(typeof(data)))

	var d: Dictionary = data

	if not d.has("version"):
		return _fail("missing required field 'version'")
	if not d.has("entities"):
		return _fail("missing required field 'entities'")

	var entities: Variant = d.get("entities")
	if entities is not Dictionary:
		return _fail("'entities' must be a Dictionary, got %s" % type_string(typeof(entities)))

	for entity_id: String in entities:
		var result: Dictionary = _validate_entity(entity_id, entities[entity_id])
		if not result["valid"]:
			return result

	return {"valid": true}


## Validate a single entity dictionary.
func _validate_entity(entity_id: String, entity_data: Variant) -> Dictionary:
	if entity_data is not Dictionary:
		return _fail("entity '%s' must be a Dictionary" % entity_id)

	var d: Dictionary = entity_data

	if not d.has("type"):
		return _fail("entity '%s' missing required field 'type'" % entity_id)

	var entity_type: String = str(d["type"])
	if entity_type not in _valid_entity_types:
		return _fail("entity '%s' has invalid type '%s'" % [entity_id, entity_type])

	if entity_type in SPRINT_C1_TYPES:
		return _validate_sprint_c1_entity(entity_id, entity_type, d)

	if d.has("transform"):
		var result: Dictionary = _validate_transform(entity_id, d["transform"])
		if not result["valid"]:
			return result

	if d.has("material"):
		var result: Dictionary = _validate_material(entity_id, d["material"])
		if not result["valid"]:
			return result

	return {"valid": true}


func _validate_sprint_c1_entity(entity_id: String, entity_type: String, d: Dictionary) -> Dictionary:
	if entity_type == "combat_dummy":
		if not d.has("hp"):
			return _fail("entity '%s' (combat_dummy) missing 'hp'" % entity_id)
		if not d.has("alive"):
			return _fail("entity '%s' (combat_dummy) missing 'alive'" % entity_id)
		return {"valid": true}
	if entity_type == "label" or entity_type == "button":
		if not d.has("text"):
			return _fail("entity '%s' (%s) missing 'text'" % [entity_id, entity_type])
		if d.has("position") and not (d["position"] is Array):
			return _fail("entity '%s' position must be Array" % entity_id)
		if d.has("size") and not (d["size"] is Array):
			return _fail("entity '%s' size must be Array" % entity_id)
		return {"valid": true}
	return {"valid": true}


func _validate_transform(entity_id: String, transform_data: Variant) -> Dictionary:
	if transform_data is not Dictionary:
		return _fail("entity '%s' transform must be a Dictionary" % entity_id)

	var td: Dictionary = transform_data
	for field: String in ["position", "rotation", "scale"]:
		if td.has(field):
			var arr: Variant = td[field]
			if arr is not Array:
				return _fail("entity '%s' transform.%s must be an Array" % [entity_id, field])
			if (arr as Array).size() != 3:
				return _fail("entity '%s' transform.%s must have exactly 3 elements" % [entity_id, field])

	return {"valid": true}


func _validate_material(entity_id: String, material_data: Variant) -> Dictionary:
	if material_data is not Dictionary:
		return _fail("entity '%s' material must be a Dictionary" % entity_id)

	var md: Dictionary = material_data
	if md.has("color"):
		var color_str: String = str(md["color"])
		if _color_re.search(color_str) == null:
			return _fail("entity '%s' material.color '%s' does not match pattern %s" % [entity_id, color_str, COLOR_PATTERN])

	return {"valid": true}


func _fail(message: String) -> Dictionary:
	return {"valid": false, "error": message}
