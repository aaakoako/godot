## IR Schema Validator: validates decoded IR data against Game IR v1 schema.
## All AI-output IR must pass validation before entering the engine (Iron Law 7).
class_name IRValidator
extends RefCounted

var _valid_entity_types: Array[String] = ["cube", "sphere", "plane", "sprite", "combat_dummy", "label", "button", "game_entity"]
const COLOR_PATTERN: String = "^#[0-9A-Fa-f]{6}$"
const SPRINT_C1_TYPES: Array[String] = ["combat_dummy", "label", "button"]
const VALID_COMPONENT_TYPES: Array[String] = ["attribute_set", "tag_set", "lifecycle", "presentation", "transform_2d"]
const VALID_DEATH_STATES: Array[String] = ["alive", "dead", "despawned"]

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

	if d.has("effect_defs"):
		var result: Dictionary = _validate_effect_defs(d["effect_defs"])
		if not result["valid"]:
			return result

	if d.has("active_effects"):
		var result: Dictionary = _validate_active_effects(d["active_effects"], d)
		if not result["valid"]:
			return result

	if d.has("abilities"):
		var result: Dictionary = _validate_abilities(d["abilities"], d)
		if not result["valid"]:
			return result

	if d.has("projectile_defs"):
		var result: Dictionary = _validate_projectile_defs(d["projectile_defs"])
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

	if entity_type == "game_entity":
		return _validate_game_entity(entity_id, d)

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


## Validate a game_entity: must have components dict, each component by known type key.
func _validate_game_entity(entity_id: String, d: Dictionary) -> Dictionary:
	if not d.has("components"):
		return _fail("entity '%s' (game_entity) missing required field 'components'" % entity_id)
	var components: Variant = d["components"]
	if components is not Dictionary:
		return _fail("entity '%s' components must be a Dictionary keyed by component type" % entity_id)
	var comp_dict: Dictionary = components as Dictionary
	for comp_type: String in comp_dict:
		if comp_type not in VALID_COMPONENT_TYPES:
			return _fail("entity '%s' has unknown component type '%s'" % [entity_id, comp_type])
		var comp_data: Variant = comp_dict[comp_type]
		if comp_data is not Dictionary:
			return _fail("entity '%s' component '%s' must be a Dictionary" % [entity_id, comp_type])
		var result: Dictionary = _validate_component(entity_id, comp_type, comp_data as Dictionary)
		if not result["valid"]:
			return result
	return {"valid": true}


func _validate_component(entity_id: String, comp_type: String, data: Dictionary) -> Dictionary:
	match comp_type:
		"attribute_set":
			return _validate_component_attribute_set(entity_id, data)
		"tag_set":
			return _validate_component_tag_set(entity_id, data)
		"lifecycle":
			return _validate_component_lifecycle(entity_id, data)
		"presentation":
			return {"valid": true}
		"transform_2d":
			return _validate_component_transform_2d(entity_id, data)
	return {"valid": true}


func _validate_component_attribute_set(entity_id: String, data: Dictionary) -> Dictionary:
	if not data.has("attributes"):
		return _fail("entity '%s' attribute_set missing 'attributes'" % entity_id)
	var attrs: Variant = data["attributes"]
	if attrs is not Dictionary:
		return _fail("entity '%s' attribute_set.attributes must be a Dictionary" % entity_id)
	for attr_name: String in (attrs as Dictionary):
		var attr_val: Variant = (attrs as Dictionary)[attr_name]
		if attr_val is not Dictionary:
			return _fail("entity '%s' attribute_set.attributes.%s must be a Dictionary with current/max" % [entity_id, attr_name])
		var av: Dictionary = attr_val as Dictionary
		if not av.has("current"):
			return _fail("entity '%s' attribute '%s' missing 'current'" % [entity_id, attr_name])
	return {"valid": true}


func _validate_component_tag_set(entity_id: String, data: Dictionary) -> Dictionary:
	if data.has("base_tags") and data["base_tags"] is not Array:
		return _fail("entity '%s' tag_set.base_tags must be an Array" % entity_id)
	if data.has("runtime_tags") and data["runtime_tags"] is not Array:
		return _fail("entity '%s' tag_set.runtime_tags must be an Array" % entity_id)
	return {"valid": true}


func _validate_component_lifecycle(entity_id: String, data: Dictionary) -> Dictionary:
	if not data.has("alive"):
		return _fail("entity '%s' lifecycle missing 'alive'" % entity_id)
	if data.has("death_state"):
		var ds: String = str(data["death_state"])
		if ds not in VALID_DEATH_STATES:
			return _fail("entity '%s' lifecycle.death_state '%s' must be one of %s" % [entity_id, ds, str(VALID_DEATH_STATES)])
	return {"valid": true}


func _validate_component_transform_2d(entity_id: String, data: Dictionary) -> Dictionary:
	if data.has("position"):
		var pos: Variant = data["position"]
		if pos is not Array or (pos as Array).size() < 2:
			return _fail("entity '%s' transform_2d.position must be an Array with at least 2 elements" % entity_id)
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


# ─── SPRINT D2: EFFECT VALIDATION ────────────────────────────────────────────

## Validate effect_defs: dict keyed by effect id; each must have type + policy + modifiers.
func _validate_effect_defs(effect_defs: Variant) -> Dictionary:
	if effect_defs is not Dictionary:
		return _fail("'effect_defs' must be a Dictionary keyed by effect id")
	for effect_id: String in (effect_defs as Dictionary):
		var ed: Variant = (effect_defs as Dictionary)[effect_id]
		if ed is not Dictionary:
			return _fail("effect_def '%s' must be a Dictionary" % effect_id)
		var result: Dictionary = _validate_one_effect_def(effect_id, ed as Dictionary)
		if not result["valid"]:
			return result
	return {"valid": true}


func _validate_one_effect_def(effect_id: String, d: Dictionary) -> Dictionary:
	var dtype: String = str(d.get("type", ""))
	if dtype != "gameplay_effect_def":
		return _fail("effect_def '%s' must have type 'gameplay_effect_def', got '%s'" % [effect_id, dtype])
	if not d.has("policy"):
		return _fail("effect_def '%s' missing required field 'policy'" % effect_id)
	var policy: Variant = d["policy"]
	if policy is not Dictionary:
		return _fail("effect_def '%s' policy must be a Dictionary" % effect_id)
	var pd: Dictionary = policy as Dictionary
	if not pd.has("duration"):
		return _fail("effect_def '%s' policy missing 'duration'" % effect_id)
	if not pd.has("tick_rate"):
		return _fail("effect_def '%s' policy missing 'tick_rate'" % effect_id)
	var duration: Variant = pd["duration"]
	if not (duration is float or duration is int) or float(duration) < 0.0:
		return _fail("effect_def '%s' policy.duration must be a non-negative number" % effect_id)
	var tick_rate: Variant = pd["tick_rate"]
	if not (tick_rate is float or tick_rate is int) or float(tick_rate) <= 0.0:
		return _fail("effect_def '%s' policy.tick_rate must be a positive number" % effect_id)
	if d.has("modifiers"):
		var mods: Variant = d["modifiers"]
		if mods is not Array:
			return _fail("effect_def '%s' modifiers must be an Array" % effect_id)
	return {"valid": true}


## Validate active_effects: dict keyed by instance id; references must resolve.
func _validate_active_effects(active_effects: Variant, root: Dictionary) -> Dictionary:
	if active_effects is not Dictionary:
		return _fail("'active_effects' must be a Dictionary keyed by instance id")
	var effect_defs: Variant = root.get("effect_defs", {})
	var entities: Variant = root.get("entities", {})
	for instance_id: String in (active_effects as Dictionary):
		var ae: Variant = (active_effects as Dictionary)[instance_id]
		if ae is not Dictionary:
			return _fail("active_effect '%s' must be a Dictionary" % instance_id)
		var result: Dictionary = _validate_one_active_effect(instance_id, ae as Dictionary, effect_defs, entities)
		if not result["valid"]:
			return result
	return {"valid": true}


func _validate_one_active_effect(instance_id: String, d: Dictionary, effect_defs: Variant, entities: Variant) -> Dictionary:
	var atype: String = str(d.get("type", ""))
	if atype != "active_effect":
		return _fail("active_effect '%s' must have type 'active_effect', got '%s'" % [instance_id, atype])
	if not d.has("effect_def"):
		return _fail("active_effect '%s' missing required field 'effect_def'" % instance_id)
	var def_ref: String = str(d["effect_def"])
	if effect_defs is Dictionary and not (effect_defs as Dictionary).has(def_ref):
		return _fail("active_effect '%s' references unknown effect_def '%s'" % [instance_id, def_ref])
	if not d.has("target_entity"):
		return _fail("active_effect '%s' missing required field 'target_entity'" % instance_id)
	var target: String = str(d["target_entity"])
	if entities is Dictionary and not (entities as Dictionary).has(target):
		return _fail("active_effect '%s' references unknown target_entity '%s'" % [instance_id, target])
	return {"valid": true}


# ─── SPRINT D3: ABILITY + PROJECTILE VALIDATION ───────────────────────────────

## Validate abilities: dict keyed by ability id.
func _validate_abilities(abilities: Variant, root: Dictionary) -> Dictionary:
	if abilities is not Dictionary:
		return _fail("'abilities' must be a Dictionary keyed by ability id")
	var entities: Variant = root.get("entities", {})
	for ability_id: String in (abilities as Dictionary):
		var ab: Variant = (abilities as Dictionary)[ability_id]
		if ab is not Dictionary:
			return _fail("ability '%s' must be a Dictionary" % ability_id)
		var result: Dictionary = _validate_one_ability(ability_id, ab as Dictionary, entities)
		if not result["valid"]:
			return result
	return {"valid": true}


func _validate_one_ability(ability_id: String, d: Dictionary, entities: Variant) -> Dictionary:
	var atype: String = str(d.get("type", ""))
	if atype != "ability":
		return _fail("ability '%s' must have type 'ability', got '%s'" % [ability_id, atype])
	if not d.has("owner"):
		return _fail("ability '%s' missing required field 'owner'" % ability_id)
	var owner: String = str(d["owner"])
	if entities is Dictionary and not (entities as Dictionary).has(owner):
		return _fail("ability '%s' references unknown owner entity '%s'" % [ability_id, owner])
	if not d.has("trigger"):
		return _fail("ability '%s' missing required field 'trigger'" % ability_id)
	var trigger: Variant = d["trigger"]
	if trigger is not Dictionary:
		return _fail("ability '%s' trigger must be a Dictionary" % ability_id)
	var td: Dictionary = trigger as Dictionary
	if not td.has("type"):
		return _fail("ability '%s' trigger missing 'type'" % ability_id)
	if not td.has("input_action"):
		return _fail("ability '%s' trigger missing 'input_action'" % ability_id)
	return {"valid": true}


## Validate projectile_defs: dict keyed by projectile id.
func _validate_projectile_defs(projectile_defs: Variant) -> Dictionary:
	if projectile_defs is not Dictionary:
		return _fail("'projectile_defs' must be a Dictionary keyed by projectile def id")
	for proj_id: String in (projectile_defs as Dictionary):
		var pd: Variant = (projectile_defs as Dictionary)[proj_id]
		if pd is not Dictionary:
			return _fail("projectile_def '%s' must be a Dictionary" % proj_id)
		var result: Dictionary = _validate_one_projectile_def(proj_id, pd as Dictionary)
		if not result["valid"]:
			return result
	return {"valid": true}


func _validate_one_projectile_def(proj_id: String, d: Dictionary) -> Dictionary:
	var ptype: String = str(d.get("type", ""))
	if ptype != "projectile_def":
		return _fail("projectile_def '%s' must have type 'projectile_def', got '%s'" % [proj_id, ptype])
	if not d.has("speed"):
		return _fail("projectile_def '%s' missing required field 'speed'" % proj_id)
	var speed: Variant = d["speed"]
	if not (speed is float or speed is int) or float(speed) <= 0.0:
		return _fail("projectile_def '%s' speed must be a positive number" % proj_id)
	if not d.has("movement"):
		return _fail("projectile_def '%s' missing required field 'movement'" % proj_id)
	var mov: Variant = d["movement"]
	if mov is not Dictionary:
		return _fail("projectile_def '%s' movement must be a Dictionary" % proj_id)
	return {"valid": true}


func _fail(message: String) -> Dictionary:
	return {"valid": false, "error": message}
