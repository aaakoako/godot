## ProjectileSystem: moves active projectile entities and detects hits via distance.
## Autoload singleton. Data-driven movement: updates position via IR Patch each frame.
## D3 scope: linear movement, AABB/distance collision, no Godot Physics.
extends Node

## Minimum seconds between full projectile scan ticks.
const TICK_INTERVAL_SEC: float = 0.05
## Distance threshold (pixels / units) at which a projectile is considered a hit.
const HIT_DISTANCE: float = 30.0
## Projectile entity tag used to identify active projectiles.
const PROJECTILE_TAG: String = "projectile"

var _time_since_tick: float = 0.0


func _ready() -> void:
	print("ProjectileSystem: ready")


func _process(delta: float) -> void:
	_time_since_tick += delta
	if _time_since_tick < TICK_INTERVAL_SEC:
		return
	_time_since_tick = 0.0
	_tick_projectiles(TICK_INTERVAL_SEC)


func _tick_projectiles(dt: float) -> void:
	var ir_manager: Node = _get_ir_manager()
	if ir_manager == null:
		return

	var state: Dictionary = ir_manager.get_ir_state()
	var entities: Variant = state.get("entities", {})
	if entities is not Dictionary:
		return

	# Collect projectiles and potential targets.
	var projectiles: Array = []
	var targets: Array = []

	for entity_id: String in (entities as Dictionary):
		var entity: Variant = (entities as Dictionary)[entity_id]
		if entity is not Dictionary:
			continue
		var ed: Dictionary = entity as Dictionary
		if ed.get("type", "") != "game_entity":
			continue
		var components: Variant = ed.get("components", {})
		if components is not Dictionary:
			continue
		var tag_set: Variant = (components as Dictionary).get("tag_set", {})
		if tag_set is not Dictionary:
			continue
		var base_tags: Variant = (tag_set as Dictionary).get("base_tags", [])
		if base_tags is Array and PROJECTILE_TAG in (base_tags as Array):
			projectiles.append({"id": entity_id, "data": ed})
		else:
			# Potential target: must have lifecycle (alive=true) and attribute_set.
			var lifecycle: Variant = (components as Dictionary).get("lifecycle", {})
			var attr_set: Variant = (components as Dictionary).get("attribute_set", {})
			if lifecycle is Dictionary and (lifecycle as Dictionary).get("alive", false) and attr_set is Dictionary:
				targets.append({"id": entity_id, "data": ed})

	if projectiles.is_empty():
		return

	# Build all patches in one batch.
	var all_patches: Array = []

	for proj_info: Dictionary in projectiles:
		var proj_id: String = proj_info["id"]
		var proj_data: Dictionary = proj_info["data"]
		_process_one_projectile(proj_id, proj_data, targets, dt, all_patches, ir_manager, state)

	if all_patches.is_empty():
		return

	var patch_str: String = JSON.stringify({"ops": all_patches})
	var result: Dictionary = ir_manager.apply_patch(patch_str)
	if not result.get("ok", false):
		push_warning("ProjectileSystem: patch failed: %s" % result.get("reason", "?"))


func _process_one_projectile(proj_id: String, proj_data: Dictionary, targets: Array, dt: float, patches: Array, ir_manager: Node, state: Dictionary) -> void:
	var speed: float = _to_float(proj_data.get("_speed", 400.0))
	var velocity: Variant = proj_data.get("_velocity", [1.0, 0.0])
	var proj_def_id: String = str(proj_data.get("_projectile_def", ""))

	if velocity is not Array or (velocity as Array).size() < 2:
		return

	var vel_arr: Array = velocity as Array
	var vx: float = _to_float(vel_arr[0])
	var vy: float = _to_float(vel_arr[1])

	var components: Dictionary = proj_data.get("components", {}) as Dictionary
	var transform_2d: Dictionary = components.get("transform_2d", {}) as Dictionary
	var pos: Variant = transform_2d.get("position", [0.0, 0.0])
	if pos is not Array or (pos as Array).size() < 2:
		return

	var pos_arr: Array = pos as Array
	var px: float = _to_float(pos_arr[0]) + vx * speed * dt
	var py: float = _to_float(pos_arr[1]) + vy * speed * dt

	# Check hits before updating position.
	for target_info: Dictionary in targets:
		var target_id: String = target_info["id"]
		var target_data: Dictionary = target_info["data"]
		var target_components: Dictionary = target_data.get("components", {}) as Dictionary
		var target_transform: Dictionary = target_components.get("transform_2d", {}) as Dictionary
		var target_pos: Variant = target_transform.get("position", [0.0, 0.0])
		if target_pos is not Array or (target_pos as Array).size() < 2:
			continue
		var tp: Array = target_pos as Array
		var tx: float = _to_float(tp[0])
		var ty: float = _to_float(tp[1])
		var dist: float = sqrt((px - tx) * (px - tx) + (py - ty) * (py - ty))
		if dist <= HIT_DISTANCE:
			_on_hit(proj_id, proj_def_id, target_id, patches, state)
			return

	# Move the projectile.
	patches.append({
		"op": "replace",
		"path": "/entities/%s/components/transform_2d/position" % proj_id,
		"value": [px, py],
	})


func _on_hit(proj_id: String, proj_def_id: String, target_id: String, patches: Array, state: Dictionary) -> void:
	# Apply on_hit effect if defined.
	var projectile_defs: Variant = state.get("projectile_defs", {})
	if projectile_defs is Dictionary and (projectile_defs as Dictionary).has(proj_def_id):
		var proj_def: Dictionary = (projectile_defs as Dictionary)[proj_def_id] as Dictionary
		var on_hit: Variant = proj_def.get("on_hit", {})
		if on_hit is Dictionary:
			var apply_effect: String = str((on_hit as Dictionary).get("apply_effect", ""))
			if not apply_effect.is_empty():
				var instance_id: String = "active_%s_%s" % [apply_effect, target_id]
				patches.append({
					"op": "add",
					"path": "/active_effects/%s" % instance_id,
					"value": {
						"type": "active_effect",
						"effect_def": apply_effect,
						"target_entity": target_id,
						"elapsed": 0.0,
						"next_tick_at": 1.0,
						"_last_updated_at": 0.0,
					},
				})

	# Remove projectile entity.
	patches.append({"op": "remove", "path": "/entities/%s" % proj_id})


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
