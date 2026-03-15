## EffectSystem: time-driven tick for active_effects in the Game IR.
## Autoload singleton. All attribute writes go through IRManager.apply_patch (Iron Law 3).
## D2 design: logic-correct timing, not frame-perfect. ~10% tolerance is acceptable.
extends Node

## Minimum seconds between full IR scans to avoid per-frame dictionary churn.
const SCAN_INTERVAL_SEC: float = 0.05

var _time_since_scan: float = 0.0


func _ready() -> void:
	print("EffectSystem: ready")


func _process(delta: float) -> void:
	_time_since_scan += delta
	if _time_since_scan < SCAN_INTERVAL_SEC:
		return
	_time_since_scan = 0.0
	_tick_all_effects()


## Scan active_effects and process each one.
func _tick_all_effects() -> void:
	var ir_manager: Node = _get_ir_manager()
	if ir_manager == null:
		return

	var state: Dictionary = ir_manager.get_ir_state()
	var active_effects: Variant = state.get("active_effects", null)
	if active_effects is not Dictionary or (active_effects as Dictionary).is_empty():
		return

	var effect_defs: Variant = state.get("effect_defs", {})
	var now: float = Time.get_unix_time_from_system()

	for instance_id: String in (active_effects as Dictionary):
		var ae: Variant = (active_effects as Dictionary)[instance_id]
		if ae is not Dictionary:
			continue
		_process_one_effect(ir_manager, instance_id, ae as Dictionary, effect_defs, state, now)


func _process_one_effect(ir_manager: Node, instance_id: String, ae: Dictionary, effect_defs: Variant, state: Dictionary, now: float) -> void:
	var def_ref: String = str(ae.get("effect_def", ""))
	var target_id: String = str(ae.get("target_entity", ""))
	if def_ref.is_empty() or target_id.is_empty():
		return

	if effect_defs is not Dictionary or not (effect_defs as Dictionary).has(def_ref):
		return

	var effect_def: Dictionary = (effect_defs as Dictionary)[def_ref] as Dictionary
	var policy: Dictionary = effect_def.get("policy", {}) as Dictionary
	var duration: float = _to_float(policy.get("duration", 0.0))
	var tick_rate: float = _to_float(policy.get("tick_rate", 1.0))

	# _last_updated_at == 0 means this effect was just injected this tick cycle.
	# Initialize it + apply granted_tags, but do NOT compute a delta yet.
	var last_updated_at: float = _to_float(ae.get("_last_updated_at", 0.0))
	var is_new: bool = last_updated_at <= 0.0

	var patches: Array = []

	if is_new:
		# First encounter: stamp the clock and apply granted_tags.
		patches.append({"op": "replace", "path": "/active_effects/%s/_last_updated_at" % instance_id, "value": now})
		_append_granted_tag_patches(patches, effect_def, target_id, ir_manager)
		if not patches.is_empty():
			var patch_str: String = JSON.stringify({"ops": patches})
			var _r: Dictionary = ir_manager.apply_patch(patch_str)
		return

	var elapsed: float = _to_float(ae.get("elapsed", 0.0))
	var next_tick_at: float = _to_float(ae.get("next_tick_at", tick_rate))
	var real_delta: float = now - last_updated_at
	if real_delta <= 0.0:
		return

	var new_elapsed: float = elapsed + real_delta

	# Update elapsed + clock.
	patches.append({"op": "replace", "path": "/active_effects/%s/elapsed" % instance_id, "value": new_elapsed})
	patches.append({"op": "replace", "path": "/active_effects/%s/_last_updated_at" % instance_id, "value": now})

	# Accumulate ticks that have fired since last scan.
	var ticks_to_apply: int = 0
	var tick_cursor: float = next_tick_at
	while tick_cursor <= new_elapsed:
		ticks_to_apply += 1
		tick_cursor += tick_rate

	if ticks_to_apply > 0:
		_append_modifier_patches(patches, effect_def, target_id, ticks_to_apply, ir_manager)
		patches.append({"op": "replace", "path": "/active_effects/%s/next_tick_at" % instance_id, "value": tick_cursor})

	# Expiry: new_elapsed has passed duration.
	var expired: bool = duration > 0.0 and new_elapsed >= duration
	if expired:
		_append_revoke_tag_patches(patches, effect_def, target_id, ir_manager)
		patches.append({"op": "remove", "path": "/active_effects/%s" % instance_id})

	if patches.is_empty():
		return

	var patch_str: String = JSON.stringify({"ops": patches})
	var result: Dictionary = ir_manager.apply_patch(patch_str)
	if not result.get("ok", false):
		push_warning("EffectSystem: patch failed for '%s': %s" % [instance_id, result.get("reason", "?")])


## Build patches to apply modifiers for N ticks.
func _append_modifier_patches(patches: Array, effect_def: Dictionary, target_id: String, tick_count: int, ir_manager: Node) -> void:
	var modifiers: Variant = effect_def.get("modifiers", [])
	if modifiers is not Array:
		return
	for mod: Variant in (modifiers as Array):
		if mod is not Dictionary:
			continue
		var m: Dictionary = mod as Dictionary
		var attr_name: String = str(m.get("attribute", ""))
		var op_str: String = str(m.get("op", "add"))
		var per_tick_value: float = _to_float(m.get("value", 0.0))
		if attr_name.is_empty():
			continue
		var current_attr: Dictionary = ir_manager.get_attribute(target_id, attr_name)
		if current_attr.is_empty():
			continue
		var current_val: float = _to_float(current_attr.get("current", 0.0))
		var new_val: float = current_val
		match op_str:
			"add":
				new_val = current_val + per_tick_value * tick_count
			"mul":
				new_val = current_val * (per_tick_value * tick_count)
			"set":
				new_val = per_tick_value
		patches.append({
			"op": "replace",
			"path": "/entities/%s/components/attribute_set/attributes/%s/current" % [target_id, attr_name],
			"value": new_val,
		})


## Build patches to apply granted_tags to target's runtime_tags.
func _append_granted_tag_patches(patches: Array, effect_def: Dictionary, target_id: String, ir_manager: Node) -> void:
	var granted_tags: Variant = effect_def.get("granted_tags", [])
	if granted_tags is not Array or (granted_tags as Array).is_empty():
		return
	var current_tags: Array = ir_manager.get_tags(target_id)
	var changed: bool = false
	for tag: Variant in (granted_tags as Array):
		var tag_str: String = str(tag)
		if tag_str not in current_tags:
			current_tags.append(tag_str)
			changed = true
	if changed:
		patches.append({
			"op": "replace",
			"path": "/entities/%s/components/tag_set/runtime_tags" % target_id,
			"value": current_tags,
		})


## Build patches to remove granted_tags from target's runtime_tags on expiry.
func _append_revoke_tag_patches(patches: Array, effect_def: Dictionary, target_id: String, ir_manager: Node) -> void:
	var granted_tags: Variant = effect_def.get("granted_tags", [])
	if granted_tags is not Array or (granted_tags as Array).is_empty():
		return
	var current_tags: Array = ir_manager.get_tags(target_id)
	var changed: bool = false
	for tag: Variant in (granted_tags as Array):
		var tag_str: String = str(tag)
		if tag_str in current_tags:
			current_tags.erase(tag_str)
			changed = true
	if changed:
		patches.append({
			"op": "replace",
			"path": "/entities/%s/components/tag_set/runtime_tags" % target_id,
			"value": current_tags,
		})


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
