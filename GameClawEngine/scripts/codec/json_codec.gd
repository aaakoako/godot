## JSON fallback codec. Used as degraded fallback when TOON parsing fails.
## Wraps Godot's built-in JSON class behind the CodecInterface.
class_name JSONCodec
extends CodecInterface


func encode(data: Variant) -> String:
	return JSON.stringify(data, "  ")


func decode(text: String) -> Variant:
	var json := JSON.new()
	var err: Error = json.parse(text)
	if err != OK:
		push_error("JSONCodec: parse error at line %d: %s" % [json.get_error_line(), json.get_error_message()])
		return null
	return json.data
