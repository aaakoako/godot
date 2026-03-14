## PatchEngine: RFC 6902 JSON Patch semantics with ACID transactional guarantees.
## Iron Law 4: Every modification is an atomic transaction with automatic rollback.
##
## Supported operations (MVP subset):
##   test    - precondition check (value must match)
##   replace - replace existing value at path
##   add     - add new value at path
##   remove  - remove value at path
class_name PatchEngine
extends RefCounted


## Execute a list of patch operations against an IR state.
## Operations run on a deep copy; original state is never mutated.
## Returns {"success": true, "state": new_state} or {"success": false, "error": reason}.
func execute(ir_state: Dictionary, ops: Array) -> Dictionary:
	var working_copy: Dictionary = ir_state.duplicate(true)

	for i: int in range(ops.size()):
		var op: Variant = ops[i]
		if op is not Dictionary:
			return _fail("op[%d] is not a Dictionary" % i)

		var op_type: String = str(op.get("op", ""))
		var path: String = str(op.get("path", ""))

		if op_type.is_empty():
			return _fail("op[%d] missing 'op' field" % i)
		if path.is_empty():
			return _fail("op[%d] missing 'path' field" % i)

		var result: Dictionary
		match op_type:
			"test":
				result = _op_test(working_copy, path, op.get("value"))
			"replace":
				result = _op_replace(working_copy, path, op.get("value"))
			"add":
				result = _op_add(working_copy, path, op.get("value"))
			"remove":
				result = _op_remove(working_copy, path)
			_:
				return _fail("op[%d] unknown operation '%s'" % [i, op_type])

		if not result["success"]:
			return _fail("op[%d] (%s %s) failed: %s" % [i, op_type, path, result["error"]])

	return {"success": true, "state": working_copy}


# ─── OPERATIONS ───────────────────────────────────────────────────────────────

func _op_test(state: Dictionary, path: String, expected_value: Variant) -> Dictionary:
	var resolved: Dictionary = _resolve_path(state, path)
	if not resolved["found"]:
		return _fail("path '%s' not found" % path)

	var actual: Variant = resolved["value"]
	if not _values_equal(actual, expected_value):
		return _fail("test failed: expected '%s' but got '%s'" % [str(expected_value), str(actual)])

	return {"success": true}


func _op_replace(state: Dictionary, path: String, new_value: Variant) -> Dictionary:
	var segments: PackedStringArray = _parse_path(path)
	if segments.is_empty():
		return _fail("empty path")

	var parent_result: Dictionary = _resolve_parent(state, segments)
	if not parent_result["found"]:
		return _fail("parent path not found for '%s'" % path)

	var parent: Variant = parent_result["parent"]
	var last_key: String = segments[segments.size() - 1]

	if parent is Dictionary:
		if not parent.has(last_key):
			return _fail("key '%s' does not exist (use 'add' to create)" % last_key)
		parent[last_key] = _coerce_value(new_value)
		return {"success": true}

	if parent is Array:
		var idx: int = last_key.to_int()
		if idx < 0 or idx >= parent.size():
			return _fail("array index %d out of bounds" % idx)
		parent[idx] = _coerce_value(new_value)
		return {"success": true}

	return _fail("parent at path is neither Dictionary nor Array")


func _op_add(state: Dictionary, path: String, new_value: Variant) -> Dictionary:
	var segments: PackedStringArray = _parse_path(path)
	if segments.is_empty():
		return _fail("empty path")

	var parent_result: Dictionary = _resolve_parent(state, segments)
	if not parent_result["found"]:
		return _fail("parent path not found for '%s'" % path)

	var parent: Variant = parent_result["parent"]
	var last_key: String = segments[segments.size() - 1]

	if parent is Dictionary:
		parent[last_key] = _coerce_value(new_value)
		return {"success": true}

	if parent is Array:
		var idx: int = last_key.to_int()
		if idx < 0 or idx > parent.size():
			return _fail("array index %d out of bounds for add" % idx)
		parent.insert(idx, _coerce_value(new_value))
		return {"success": true}

	return _fail("parent at path is neither Dictionary nor Array")


func _op_remove(state: Dictionary, path: String) -> Dictionary:
	var segments: PackedStringArray = _parse_path(path)
	if segments.is_empty():
		return _fail("empty path")

	var parent_result: Dictionary = _resolve_parent(state, segments)
	if not parent_result["found"]:
		return _fail("parent path not found for '%s'" % path)

	var parent: Variant = parent_result["parent"]
	var last_key: String = segments[segments.size() - 1]

	if parent is Dictionary:
		if not parent.has(last_key):
			return _fail("key '%s' does not exist for remove" % last_key)
		parent.erase(last_key)
		return {"success": true}

	if parent is Array:
		var idx: int = last_key.to_int()
		if idx < 0 or idx >= parent.size():
			return _fail("array index %d out of bounds for remove" % idx)
		parent.remove_at(idx)
		return {"success": true}

	return _fail("parent at path is neither Dictionary nor Array")


# ─── PATH RESOLUTION ──────────────────────────────────────────────────────────

## Parse an RFC 6902 path string into segments.
## "/entities/box_1/material/color" -> ["entities", "box_1", "material", "color"]
func _parse_path(path: String) -> PackedStringArray:
	if not path.begins_with("/"):
		push_error("PatchEngine: path must start with '/', got '%s'" % path)
		return PackedStringArray()
	var parts: PackedStringArray = path.substr(1).split("/")
	return parts


## Resolve a full path to its value in the state tree.
func _resolve_path(state: Dictionary, path: String) -> Dictionary:
	var segments: PackedStringArray = _parse_path(path)
	if segments.is_empty():
		return {"found": false}

	var current: Variant = state
	for seg: String in segments:
		if current is Dictionary:
			if not current.has(seg):
				return {"found": false}
			current = current[seg]
		elif current is Array:
			var idx: int = seg.to_int()
			if idx < 0 or idx >= current.size():
				return {"found": false}
			current = current[idx]
		else:
			return {"found": false}

	return {"found": true, "value": current}


## Resolve the parent container of the last path segment.
func _resolve_parent(state: Dictionary, segments: PackedStringArray) -> Dictionary:
	if segments.size() <= 1:
		return {"found": true, "parent": state}

	var current: Variant = state
	for i: int in range(segments.size() - 1):
		var seg: String = segments[i]
		if current is Dictionary:
			if not current.has(seg):
				return {"found": false}
			current = current[seg]
		elif current is Array:
			var idx: int = seg.to_int()
			if idx < 0 or idx >= current.size():
				return {"found": false}
			current = current[idx]
		else:
			return {"found": false}

	return {"found": true, "parent": current}


# ─── HELPERS ──────────────────────────────────────────────────────────────────

## Coerce patch values: comma-separated numeric strings become Arrays.
func _coerce_value(value: Variant) -> Variant:
	if value is String:
		var s: String = value
		if s.contains(",") and not s.begins_with("\""):
			var parts: PackedStringArray = s.split(",")
			var all_numeric: bool = true
			for p: String in parts:
				var stripped: String = p.strip_edges()
				if not stripped.is_valid_float() and not stripped.is_valid_int():
					all_numeric = false
					break
			if all_numeric:
				var arr: Array = []
				for p: String in parts:
					var stripped: String = p.strip_edges()
					if stripped.contains("."):
						arr.append(stripped.to_float())
					else:
						arr.append(stripped.to_int())
				return arr
	return value


func _values_equal(a: Variant, b: Variant) -> bool:
	if a == b:
		return true
	if a is Array and b is Array:
		var ra: Array = a as Array
		var rb: Array = b as Array
		if ra.size() != rb.size():
			return false
		for i: int in range(ra.size()):
			if not _values_equal(ra[i], rb[i]):
				return false
		return true
	if typeof(a) != typeof(b):
		return str(a) == str(b)
	return false


func _fail(message: String) -> Dictionary:
	return {"success": false, "error": message}
