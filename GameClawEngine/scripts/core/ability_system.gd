## AbilitySystem: handles input_action events and activates abilities in the IR.
## Autoload singleton. Writes only through IRManager.apply_patch (Iron Law 3).
## D3 scope: on_input trigger only; no animation, no 3D/2D node binding.
extends Node

## Maps input_action string → list of ability ids that listen to it.
var _action_to_abilities: Dictionary = {}
## Tracks per-ability cooldown expiry timestamp (unix seconds).
var _cooldown_expiry: Dictionary = {}

var _projectile_counter: int = 0


func _ready() -> void:
	print("AbilitySystem: ready")
	_rebuild_action_map()
	var ir_manager: Node = _get_ir_manager()
	if ir_manager != null:
		ir_manager.patch_applied.connect(_on_patch_applied)


## Rebuild input_action → [ability_id] mapping from current IR state.
func _rebuild_action_map() -> void:
	_action_to_abilities.clear()
	var ir_manager: Node = _get_ir_manager()
	if ir_manager == null:
		return
	var state: Dictionary = ir_manager.get_ir_state()
	var abilities: Variant = state.get("abilities", {})
	if abilities is not Dictionary:
		return
	for ability_id: String in (abilities as Dictionary):
		var ab: Variant = (abilities as Dictionary)[ability_id]
		if ab is not Dictionary:
			continue
		var trigger: Variant = (ab as Dictionary).get("trigger", {})
		if trigger is not Dictionary:
			continue
		var t_type: String = str((trigger as Dictionary).get("type", ""))
		if t_type != "on_input":
			continue
		var action: String = str((trigger as Dictionary).get("input_action", ""))
		if action.is_empty():
			continue
		if not _action_to_abilities.has(action):
			_action_to_abilities[action] = []
		(_action_to_abilities[action] as Array).append(ability_id)


## Called by MCP send_input_action handler (or future input layer).
func handle_input_action(action_name: String) -> Dictionary:
	if not _action_to_abilities.has(action_name):
		return {"ok": false, "reason": "no ability bound to input_action '%s'" % action_name}

	var ir_manager: Node = _get_ir_manager()
	if ir_manager == null:
		return {"ok": false, "reason": "IRManager not found"}

	var state: Dictionary = ir_manager.get_ir_state()
	var results: Array = []
	for ability_id: String in (_action_to_abilities[action_name] as Array):
		var result: Dictionary = _activate_ability(ir_manager, state, ability_id)
		results.append({"ability_id": ability_id, "result": result})

	return {"ok": true, "activations": results}


func _activate_ability(ir_manager: Node, state: Dictionary, ability_id: String) -> Dictionary:
	var abilities: Variant = state.get("abilities", {})
	if abilities is not Dictionary or not (abilities as Dictionary).has(ability_id):
		return {"ok": false, "reason": "ability '%s' not found in IR" % ability_id}

	var ability: Dictionary = (abilities as Dictionary)[ability_id] as Dictionary
	var owner_id: String = str(ability.get("owner", ""))

	# Check owner alive.
	if not ir_manager.has_tag(owner_id, "unit.hero") and not _entity_exists(state, owner_id):
		return {"ok": false, "reason": "owner '%s' not found" % owner_id}

	var lifecycle_path: String = "/entities/%s/components/lifecycle/alive" % owner_id
	var alive_result: Dictionary = ir_manager._resolve_ir_path(lifecycle_path)
	if alive_result.get("found", false) and alive_result["value"] == false:
		return {"ok": false, "reason": "owner '%s' is dead" % owner_id}

	# Check cooldown.
	var now: float = Time.get_unix_time_from_system()
	var expiry: float = _to_float(_cooldown_expiry.get(ability_id, 0.0))
	if now < expiry:
		return {"ok": false, "reason": "ability '%s' on cooldown (%.1fs remaining)" % [ability_id, expiry - now]}

	# Check cost.
	var cost: Variant = ability.get("cost", {})
	if cost is Dictionary:
		for resource: String in (cost as Dictionary):
			var required: float = _to_float((cost as Dictionary)[resource])
			var current_attr: Dictionary = ir_manager.get_attribute(owner_id, resource)
			var current_val: float = _to_float(current_attr.get("current", 0.0))
			if current_val < required:
				return {"ok": false, "reason": "insufficient %s: need %.0f, have %.0f" % [resource, required, current_val]}

	# Build patches: deduct cost + set cooldown entry.
	var patches: Array = []
	if cost is Dictionary:
		for resource: String in (cost as Dictionary):
			var required: float = _to_float((cost as Dictionary)[resource])
			var current_attr: Dictionary = ir_manager.get_attribute(owner_id, resource)
			var current_val: float = _to_float(current_attr.get("current", 0.0))
			patches.append({
				"op": "replace",
				"path": "/entities/%s/components/attribute_set/attributes/%s/current" % [owner_id, resource],
				"value": current_val - required,
			})

	# Apply cost patches first.
	if not patches.is_empty():
		var patch_str: String = JSON.stringify({"ops": patches})
		var r: Dictionary = ir_manager.apply_patch(patch_str)
		if not r.get("ok", false):
			return {"ok": false, "reason": "cost patch failed: %s" % r.get("reason", "?")}

	# Set cooldown.
	var cooldown: float = _to_float(ability.get("cooldown", 0.0))
	_cooldown_expiry[ability_id] = now + cooldown

	# Execute ability effects (e.g. spawn_projectile).
	var effects: Variant = ability.get("effects", [])
	var spawn_results: Array = []
	if effects is Array:
		for eff: Variant in (effects as Array):
			if eff is not Dictionary:
				continue
			var ef: Dictionary = eff as Dictionary
			var eff_type: String = str(ef.get("type", ""))
			if eff_type == "spawn_projectile":
				var proj_ref: String = str(ef.get("projectile_ref", ""))
				var spawn_result: Dictionary = _spawn_projectile(ir_manager, state, owner_id, proj_ref)
				spawn_results.append(spawn_result)

	return {"ok": true, "spawn_results": spawn_results}


func _spawn_projectile(ir_manager: Node, state: Dictionary, owner_id: String, proj_def_id: String) -> Dictionary:
	var projectile_defs: Variant = state.get("projectile_defs", {})
	if projectile_defs is not Dictionary or not (projectile_defs as Dictionary).has(proj_def_id):
		return {"ok": false, "reason": "projectile_def '%s' not found" % proj_def_id}

	_projectile_counter += 1
	var instance_id: String = "proj_%s_%d" % [proj_def_id, _projectile_counter]

	var proj_def: Dictionary = (projectile_defs as Dictionary)[proj_def_id] as Dictionary
	var movement: Dictionary = proj_def.get("movement", {}) as Dictionary
	var direction: Variant = movement.get("direction", [1.0, 0.0])
	if direction is not Array:
		direction = [1.0, 0.0]

	# Spawn at owner position (or [0,0] fallback).
	var owner_pos: Dictionary = ir_manager.get_attribute(owner_id, "position")
	var spawn_x: float = 0.0
	var spawn_y: float = 0.0

	# Read owner transform_2d position if available.
	var pos_result: Dictionary = ir_manager._resolve_ir_path("/entities/%s/components/transform_2d/position" % owner_id)
	if pos_result.get("found", false) and pos_result["value"] is Array:
		var pos_arr: Array = pos_result["value"] as Array
		if pos_arr.size() >= 2:
			spawn_x = _to_float(pos_arr[0])
			spawn_y = _to_float(pos_arr[1])

	var patches: Array = [{
		"op": "add",
		"path": "/entities/%s" % instance_id,
		"value": {
			"type": "game_entity",
			"components": {
				"transform_2d": {"position": [spawn_x, spawn_y]},
				"lifecycle": {"alive": true, "death_state": "alive"},
				"tag_set": {"base_tags": ["projectile"], "runtime_tags": []},
			},
			"_projectile_def": proj_def_id,
			"_owner": owner_id,
			"_velocity": direction,
			"_speed": proj_def.get("speed", 400.0),
		},
	}]

	var patch_str: String = JSON.stringify({"ops": patches})
	var result: Dictionary = ir_manager.apply_patch(patch_str)
	if not result.get("ok", false):
		return {"ok": false, "reason": "spawn patch failed: %s" % result.get("reason", "?")}

	return {"ok": true, "projectile_id": instance_id}


func _on_patch_applied(_ops: Array) -> void:
	# Rebuild action map if abilities section may have changed.
	_rebuild_action_map()


func _entity_exists(state: Dictionary, entity_id: String) -> bool:
	var entities: Variant = state.get("entities", {})
	return entities is Dictionary and (entities as Dictionary).has(entity_id)


func _get_ir_manager() -> Node:
	return get_node_or_null("/root/IRManager")


func _to_float(value: Variant) -> float:
	if value is float:
		return value
	if value is int:
		return float(value)
	if value is String:
		return (value as String).to_float()
	return 0.0
