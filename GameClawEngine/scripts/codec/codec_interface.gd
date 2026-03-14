## Abstract Codec interface for serialization format pluggability (Iron Law 5).
## All IR read/write MUST go through this interface.
## Engine internals use Godot Dictionary, decoupled from wire format.
class_name CodecInterface
extends RefCounted


## Encode a Dictionary/Array/primitive into the codec's wire format string.
func encode(_data: Variant) -> String:
	push_error("CodecInterface.encode() is abstract — must be overridden")
	return ""


## Decode a wire format string into a Dictionary/Array/primitive.
## Returns null on parse failure.
func decode(_text: String) -> Variant:
	push_error("CodecInterface.decode() is abstract — must be overridden")
	return null
