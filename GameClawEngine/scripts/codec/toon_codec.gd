## TOON (Token-Oriented Object Notation) v3.0 Core Profile codec.
## Implements encode (Dictionary -> TOON string) and decode (TOON string -> Dictionary).
## Reference: https://github.com/toon-format/spec (SPEC v3.0, 2025-11-24)
class_name TOONCodec
extends CodecInterface

const INDENT_SIZE: int = 2
const DELIMITER: String = ","

# Regex patterns cached at load time
var _unquoted_key_re: RegEx
var _numeric_re: RegEx
var _leading_zero_re: RegEx


func _init() -> void:
	_unquoted_key_re = RegEx.new()
	_unquoted_key_re.compile("^[A-Za-z_][A-Za-z0-9_.]*$")
	_numeric_re = RegEx.new()
	_numeric_re.compile("^-?\\d+(?:\\.\\d+)?(?:[eE][+-]?\\d+)?$")
	_leading_zero_re = RegEx.new()
	_leading_zero_re.compile("^-?0\\d+$")


# ─── PUBLIC API ───────────────────────────────────────────────────────────────

func encode(data: Variant) -> String:
	return _encode_value(data, 0, true)


func decode(text: String) -> Variant:
	if text.strip_edges().is_empty():
		return {}
	var lines: Array = _split_lines(text)
	var ctx := {"lines": lines, "pos": 0}
	var first_line: String = _find_first_nonempty(lines)
	if first_line.is_empty():
		return {}
	if _is_root_array_header(first_line):
		return _decode_array_header_line(ctx, 0)
	if lines.size() == 1 and not _line_has_colon(first_line):
		return _decode_primitive_token(first_line.strip_edges())
	return _decode_object(ctx, 0)


# ─── ENCODER ──────────────────────────────────────────────────────────────────

func _encode_value(value: Variant, depth: int, is_root: bool = false) -> String:
	if value == null:
		return "null"
	if value is bool:
		return "true" if value else "false"
	if value is int:
		return str(value)
	if value is float:
		return _canonical_number(value)
	if value is String:
		return _encode_string_value(value)
	if value is Array:
		return _encode_array(value, depth, is_root)
	if value is Dictionary:
		return _encode_object(value, depth, is_root)
	return _encode_string_value(str(value))


func _encode_object(obj: Dictionary, depth: int, _is_root: bool = false) -> String:
	if obj.is_empty():
		return ""
	var indent: String = _make_indent(depth)
	var parts: PackedStringArray = PackedStringArray()
	for key: String in obj:
		var encoded_key: String = _encode_key(key)
		var val: Variant = obj[key]
		if val is Dictionary:
			if val.is_empty():
				parts.append(indent + encoded_key + ":")
			else:
				parts.append(indent + encoded_key + ":")
				parts.append(_encode_object(val, depth + 1))
		elif val is Array:
			parts.append(indent + _encode_array_with_key(encoded_key, val, depth))
		else:
			parts.append(indent + encoded_key + ": " + _encode_value(val, depth))
	return "\n".join(parts)


func _encode_array_with_key(key: String, arr: Array, depth: int) -> String:
	var n: int = arr.size()
	if n == 0:
		return key + "[0]:"
	if _is_tabular(arr):
		return _encode_tabular_array(key, arr, depth)
	if _all_primitives(arr):
		var vals: PackedStringArray = PackedStringArray()
		for v: Variant in arr:
			vals.append(_encode_inline_value(v))
		return key + "[" + str(n) + "]: " + DELIMITER.join(vals)
	return _encode_mixed_array(key, arr, depth)


func _encode_tabular_array(key: String, arr: Array, depth: int) -> String:
	var fields: PackedStringArray = PackedStringArray()
	var first: Dictionary = arr[0]
	for k: String in first:
		fields.append(_encode_key(k))
	var header: String = key + "[" + str(arr.size()) + "]{" + DELIMITER.join(fields) + "}:"
	var indent: String = _make_indent(depth + 1)
	var rows: PackedStringArray = PackedStringArray()
	rows.append(header)
	for item: Dictionary in arr:
		var vals: PackedStringArray = PackedStringArray()
		for k: String in first:
			vals.append(_encode_inline_value(item.get(k)))
		rows.append(indent + DELIMITER.join(vals))
	return "\n".join(rows)


func _encode_mixed_array(key: String, arr: Array, depth: int) -> String:
	var indent: String = _make_indent(depth + 1)
	var parts: PackedStringArray = PackedStringArray()
	parts.append(key + "[" + str(arr.size()) + "]:")
	for item: Variant in arr:
		if item is Dictionary:
			var first_key: String = ""
			if not item.is_empty():
				first_key = str(item.keys()[0])
			var encoded_first_key: String = _encode_key(first_key)
			var first_val: Variant = item.get(first_key)
			if item.is_empty():
				parts.append(indent + "-")
			elif first_val is Dictionary or first_val is Array:
				parts.append(indent + "- " + encoded_first_key + ":")
				var remaining_nested: Dictionary = item.duplicate()
				remaining_nested.erase(first_key)
				if first_val is Dictionary and not first_val.is_empty():
					parts.append(_encode_object(first_val, depth + 2))
				elif first_val is Array:
					parts.append(_make_indent(depth + 2) + _encode_array_with_key(encoded_first_key, first_val, depth + 2))
				if not remaining_nested.is_empty():
					parts.append(_encode_object(remaining_nested, depth + 2))
			else:
				parts.append(indent + "- " + encoded_first_key + ": " + _encode_value(first_val, depth + 2))
				var remaining_flat: Dictionary = item.duplicate()
				remaining_flat.erase(first_key)
				if not remaining_flat.is_empty():
					parts.append(_encode_object(remaining_flat, depth + 2))
		elif item is Array:
			var inner: String = _encode_array_with_key("", item, depth + 1)
			parts.append(indent + "- " + inner)
		else:
			parts.append(indent + "- " + _encode_value(item, depth + 1))
	return "\n".join(parts)


func _encode_array(arr: Array, depth: int, _is_root: bool = false) -> String:
	var n: int = arr.size()
	if n == 0:
		return "[0]:"
	if _all_primitives(arr):
		var vals: PackedStringArray = PackedStringArray()
		for v: Variant in arr:
			vals.append(_encode_inline_value(v))
		return "[" + str(n) + "]: " + DELIMITER.join(vals)
	if _is_tabular(arr):
		return _encode_tabular_array("", arr, depth)
	return _encode_mixed_array("", arr, depth)


func _encode_inline_value(value: Variant) -> String:
	if value == null:
		return "null"
	if value is bool:
		return "true" if value else "false"
	if value is int:
		return str(value)
	if value is float:
		return _canonical_number(value)
	if value is String:
		return _encode_string_for_inline(value)
	return _encode_string_for_inline(str(value))


func _encode_string_value(s: String) -> String:
	if _needs_quoting(s, DELIMITER):
		return "\"" + _escape_string(s) + "\""
	return s


func _encode_string_for_inline(s: String) -> String:
	if s is not String:
		s = str(s)
	if _needs_quoting(s, DELIMITER):
		return "\"" + _escape_string(s) + "\""
	return s


func _encode_key(key: String) -> String:
	if _unquoted_key_re.search(key) != null:
		return key
	return "\"" + _escape_string(key) + "\""


func _needs_quoting(s: String, delim: String) -> bool:
	if s.is_empty():
		return true
	if s == "true" or s == "false" or s == "null":
		return true
	if s.begins_with(" ") or s.ends_with(" "):
		return true
	if s == "-" or s.begins_with("-"):
		return true
	if _numeric_re.search(s) != null:
		return true
	if _leading_zero_re.search(s) != null:
		return true
	for c: String in s:
		if c == ":" or c == "\"" or c == "\\" or c == "[" or c == "]" or c == "{" or c == "}":
			return true
		if c == "\n" or c == "\r" or c == "\t":
			return true
	if s.contains(delim):
		return true
	return false


func _escape_string(s: String) -> String:
	var result: String = ""
	for c: String in s:
		match c:
			"\\":
				result += "\\\\"
			"\"":
				result += "\\\""
			"\n":
				result += "\\n"
			"\r":
				result += "\\r"
			"\t":
				result += "\\t"
			_:
				result += c
	return result


func _canonical_number(f: float) -> String:
	if is_nan(f) or is_inf(f):
		return "null"
	if is_zero_approx(f):
		return "0"
	if f == floorf(f) and absf(f) < 1e15:
		return str(int(f))
	return str(f)


func _is_tabular(arr: Array) -> bool:
	if arr.is_empty():
		return false
	if arr[0] is not Dictionary:
		return false
	var first_keys: Array = (arr[0] as Dictionary).keys()
	if first_keys.is_empty():
		return false
	for item: Variant in arr:
		if item is not Dictionary:
			return false
		var d: Dictionary = item
		if d.keys().size() != first_keys.size():
			return false
		for k: String in first_keys:
			if not d.has(k):
				return false
			var v: Variant = d[k]
			if v is Dictionary or v is Array:
				return false
	return true


func _all_primitives(arr: Array) -> bool:
	for v: Variant in arr:
		if v is Dictionary or v is Array:
			return false
	return true


func _make_indent(depth: int) -> String:
	return " ".repeat(depth * INDENT_SIZE)


# ─── DECODER ──────────────────────────────────────────────────────────────────

func _split_lines(text: String) -> Array:
	var raw: PackedStringArray = text.replace("\r\n", "\n").split("\n")
	var result: Array = []
	for line: String in raw:
		result.append(line)
	return result


func _find_first_nonempty(lines: Array) -> String:
	for line: String in lines:
		if not line.strip_edges().is_empty():
			return line
	return ""


func _is_root_array_header(line: String) -> bool:
	var stripped: String = line.strip_edges()
	if not stripped.begins_with("["):
		return false
	# Check for bracket followed by colon somewhere: [N]: or [N]{...}:
	var bracket_end: int = stripped.find("]")
	if bracket_end < 0:
		return false
	var after_bracket: String = stripped.substr(bracket_end + 1).strip_edges()
	# Could be ":" or "{fields}:" or ": values"
	if after_bracket.begins_with(":"):
		return true
	if after_bracket.begins_with("{"):
		var brace_end: int = after_bracket.find("}")
		if brace_end >= 0:
			var after_brace: String = after_bracket.substr(brace_end + 1).strip_edges()
			return after_brace.begins_with(":")
	return false


func _line_has_colon(line: String) -> bool:
	var stripped: String = line.strip_edges()
	var in_quotes: bool = false
	for i: int in range(stripped.length()):
		var c: String = stripped[i]
		if c == "\"":
			if i > 0 and stripped[i - 1] == "\\":
				continue
			in_quotes = not in_quotes
		elif c == ":" and not in_quotes:
			return true
	return false


func _get_line_depth(line: String) -> int:
	var spaces: int = 0
	for c: String in line:
		if c == " ":
			spaces += 1
		else:
			break
	@warning_ignore("integer_division")
	return spaces / INDENT_SIZE


func _decode_object(ctx: Dictionary, depth: int) -> Dictionary:
	var result: Dictionary = {}
	while ctx["pos"] < (ctx["lines"] as Array).size():
		var line: String = (ctx["lines"] as Array)[ctx["pos"]]
		if line.strip_edges().is_empty():
			ctx["pos"] += 1
			continue
		var line_depth: int = _get_line_depth(line)
		if line_depth < depth:
			break
		if line_depth > depth:
			ctx["pos"] += 1
			continue
		var stripped: String = line.strip_edges()
		var parse_result: Dictionary = _parse_key_value_line(stripped)
		if parse_result.is_empty():
			ctx["pos"] += 1
			continue
		var key: String = parse_result["key"]
		var after_colon: String = parse_result["after_colon"]
		var header_info: Dictionary = _try_parse_array_header(key, after_colon)
		if not header_info.is_empty():
			ctx["pos"] += 1
			result[header_info["key"]] = _decode_array_from_header(ctx, depth, header_info)
			continue
		if after_colon.is_empty():
			ctx["pos"] += 1
			result[key] = _decode_object(ctx, depth + 1)
			continue
		ctx["pos"] += 1
		result[key] = _decode_primitive_token(after_colon)
	return result


func _parse_key_value_line(stripped: String) -> Dictionary:
	if stripped.is_empty():
		return {}
	var key: String = ""
	var rest: String = ""
	if stripped.begins_with("\""):
		var end_quote: int = _find_closing_quote(stripped, 0)
		if end_quote < 0:
			return {}
		key = _unescape_string(stripped.substr(1, end_quote - 1))
		rest = stripped.substr(end_quote + 1).strip_edges()
	else:
		var colon_pos: int = _find_unquoted_colon(stripped)
		if colon_pos < 0:
			return {}
		key = stripped.substr(0, colon_pos).strip_edges()
		rest = stripped.substr(colon_pos).strip_edges()
	if not rest.begins_with(":"):
		return {}
	var after_colon: String = rest.substr(1).strip_edges()
	return {"key": key, "after_colon": after_colon}


func _try_parse_array_header(key: String, after_colon: String) -> Dictionary:
	# The key-value parser already split on the colon. Two cases:
	# 1. "position[3]" with after_colon="0,0,0" — colon was the header terminator
	# 2. "ops[4]{op,path,value}" with after_colon="" — colon was the header terminator
	# We need to detect the bracket in the key portion.
	var bracket_start: int = -1
	var in_quotes: bool = false
	for i: int in range(key.length()):
		var c: String = key[i]
		if c == "\"":
			if i > 0 and key[i - 1] == "\\":
				continue
			in_quotes = not in_quotes
		elif c == "[" and not in_quotes:
			bracket_start = i
			break
	if bracket_start < 0:
		return {}
	var bracket_end: int = key.find("]", bracket_start)
	if bracket_end < 0:
		return {}
	var actual_key: String = key.substr(0, bracket_start).strip_edges()
	var bracket_content: String = key.substr(bracket_start + 1, bracket_end - bracket_start - 1)
	var count_str: String = bracket_content.strip_edges()
	if not count_str.is_valid_int():
		return {}
	var count: int = count_str.to_int()
	var key_remaining: String = key.substr(bracket_end + 1).strip_edges()
	var fields: Array = []
	if key_remaining.begins_with("{"):
		var brace_end: int = key_remaining.find("}")
		if brace_end >= 0:
			var fields_str: String = key_remaining.substr(1, brace_end - 1)
			fields = _split_by_delimiter(fields_str)
			key_remaining = key_remaining.substr(brace_end + 1).strip_edges()
	# The colon was already consumed by _parse_key_value_line, so after_colon
	# contains the inline values (if any). Accept this as a valid header.
	if not key_remaining.is_empty():
		return {}
	return {
		"key": actual_key,
		"count": count,
		"fields": fields,
		"inline_values": after_colon
	}


func _decode_array_header_line(ctx: Dictionary, depth: int) -> Variant:
	var line: String = (ctx["lines"] as Array)[ctx["pos"]]
	var stripped: String = line.strip_edges()
	# Root array headers like "[3]: a,b,c" — parse as key-value first
	var kv: Dictionary = _parse_key_value_line(stripped)
	if kv.is_empty():
		# Try direct parsing for bare root headers like "[3]:"
		var colon_pos: int = stripped.rfind(":")
		if colon_pos >= 0:
			var before_colon: String = stripped.substr(0, colon_pos).strip_edges()
			var after_colon_val: String = stripped.substr(colon_pos + 1).strip_edges()
			var bare_header: Dictionary = _try_parse_array_header(before_colon, after_colon_val)
			if not bare_header.is_empty():
				ctx["pos"] += 1
				return _decode_array_from_header(ctx, depth, bare_header)
		ctx["pos"] += 1
		return []
	var header_info: Dictionary = _try_parse_array_header(kv["key"], kv["after_colon"])
	if header_info.is_empty():
		ctx["pos"] += 1
		return []
	ctx["pos"] += 1
	return _decode_array_from_header(ctx, depth, header_info)


func _decode_array_from_header(ctx: Dictionary, depth: int, header: Dictionary) -> Array:
	var count: int = header["count"]
	var fields: Array = header["fields"]
	var inline_values: String = header.get("inline_values", "")
	if count == 0:
		return []
	if not inline_values.is_empty():
		if not fields.is_empty():
			var field_vals: Array = _split_by_delimiter(inline_values)
			var obj: Dictionary = {}
			for i: int in range(mini(fields.size(), field_vals.size())):
				obj[fields[i].strip_edges()] = _decode_primitive_token(field_vals[i].strip_edges())
			return [obj]
		var vals: Array = _split_by_delimiter(inline_values)
		var result: Array = []
		for v: String in vals:
			result.append(_decode_primitive_token(v.strip_edges()))
		return result
	if not fields.is_empty():
		return _decode_tabular_rows(ctx, depth + 1, fields, count)
	return _decode_list_items(ctx, depth + 1, count)


func _decode_tabular_rows(ctx: Dictionary, depth: int, fields: Array, _count: int) -> Array:
	var result: Array = []
	while ctx["pos"] < (ctx["lines"] as Array).size():
		var line: String = (ctx["lines"] as Array)[ctx["pos"]]
		if line.strip_edges().is_empty():
			ctx["pos"] += 1
			continue
		var line_depth: int = _get_line_depth(line)
		if line_depth < depth:
			break
		var stripped: String = line.strip_edges()
		if _is_key_value_not_row(stripped):
			break
		var vals: Array = _split_by_delimiter(stripped)
		var obj: Dictionary = {}
		for i: int in range(mini(fields.size(), vals.size())):
			obj[fields[i].strip_edges()] = _decode_primitive_token(vals[i].strip_edges())
		result.append(obj)
		ctx["pos"] += 1
	return result


func _is_key_value_not_row(stripped: String) -> bool:
	var first_delim: int = _find_first_unquoted(stripped, DELIMITER)
	var first_colon: int = _find_first_unquoted(stripped, ":")
	if first_colon >= 0 and first_delim < 0:
		return true
	if first_colon >= 0 and first_delim >= 0 and first_colon < first_delim:
		return true
	return false


func _find_first_unquoted(s: String, ch: String) -> int:
	var in_quotes: bool = false
	var i: int = 0
	while i < s.length():
		var c: String = s[i]
		if c == "\\" and in_quotes:
			i += 2
			continue
		if c == "\"":
			in_quotes = not in_quotes
		elif c == ch and not in_quotes:
			return i
		i += 1
	return -1


func _decode_list_items(ctx: Dictionary, depth: int, _count: int) -> Array:
	var result: Array = []
	while ctx["pos"] < (ctx["lines"] as Array).size():
		var line: String = (ctx["lines"] as Array)[ctx["pos"]]
		if line.strip_edges().is_empty():
			ctx["pos"] += 1
			continue
		var line_depth: int = _get_line_depth(line)
		if line_depth < depth:
			break
		var stripped: String = line.strip_edges()
		if not stripped.begins_with("- ") and stripped != "-":
			break
		ctx["pos"] += 1
		if stripped == "-":
			result.append({})
			continue
		var item_content: String = stripped.substr(2).strip_edges()
		var inner_header: Dictionary = _try_parse_array_header(item_content, "")
		if not inner_header.is_empty():
			result.append(_decode_array_from_header(ctx, depth, inner_header))
			continue
		if _line_has_colon(item_content):
			var kv: Dictionary = _parse_key_value_line(item_content)
			if not kv.is_empty():
				var obj: Dictionary = {}
				var k: String = kv["key"]
				var ac: String = kv["after_colon"]
				var sub_header: Dictionary = _try_parse_array_header(k, ac)
				if not sub_header.is_empty():
					obj[sub_header["key"]] = _decode_array_from_header(ctx, depth, sub_header)
				elif ac.is_empty():
					obj[k] = _decode_object(ctx, depth + 1)
				else:
					obj[k] = _decode_primitive_token(ac)
				var extra: Dictionary = _decode_object(ctx, depth + 1)
				for ek: String in extra:
					obj[ek] = extra[ek]
				result.append(obj)
				continue
		result.append(_decode_primitive_token(item_content))
	return result


func _decode_primitive_token(token: String) -> Variant:
	if token.is_empty():
		return ""
	if token.begins_with("\"") and token.ends_with("\"") and token.length() >= 2:
		return _unescape_string(token.substr(1, token.length() - 2))
	if token == "null":
		return null
	if token == "true":
		return true
	if token == "false":
		return false
	if _leading_zero_re.search(token) != null:
		return token
	if _numeric_re.search(token) != null:
		if token.contains(".") or token.contains("e") or token.contains("E"):
			return token.to_float()
		return token.to_int()
	return token


func _split_by_delimiter(s: String) -> Array:
	var result: Array = []
	var current: String = ""
	var in_quotes: bool = false
	var i: int = 0
	while i < s.length():
		var c: String = s[i]
		if c == "\\" and in_quotes and i + 1 < s.length():
			current += c + s[i + 1]
			i += 2
			continue
		if c == "\"":
			in_quotes = not in_quotes
			current += c
		elif c == DELIMITER and not in_quotes:
			result.append(current.strip_edges())
			current = ""
		else:
			current += c
		i += 1
	result.append(current.strip_edges())
	return result


func _find_closing_quote(s: String, start: int) -> int:
	var i: int = start + 1
	while i < s.length():
		var c: String = s[i]
		if c == "\\" and i + 1 < s.length():
			i += 2
			continue
		if c == "\"":
			return i
		i += 1
	return -1


func _find_unquoted_colon(s: String) -> int:
	return _find_first_unquoted(s, ":")


func _unescape_string(s: String) -> String:
	var result: String = ""
	var i: int = 0
	while i < s.length():
		if s[i] == "\\" and i + 1 < s.length():
			match s[i + 1]:
				"\\":
					result += "\\"
				"\"":
					result += "\""
				"n":
					result += "\n"
				"r":
					result += "\r"
				"t":
					result += "\t"
				_:
					push_error("TOONCodec: invalid escape sequence: \\" + s[i + 1])
					return ""
			i += 2
		else:
			result += s[i]
			i += 1
	return result
