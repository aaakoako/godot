## AcceptanceSpec: constants and structure for patch outcome verification.
## Sprint B: acceptance_spec must use a checks array (not single target_path + expected_value).
## Used by IRManager.apply_patch() and verify_outcome().
class_name AcceptanceSpec
extends RefCounted

## Valid layers for five-layer error attribution (Iron Law 8).
const LAYER_IR_INPUT: String = "ir_input"
const LAYER_PATCH_TRANSACTION: String = "patch_transaction"
const LAYER_IR_STATE: String = "ir_state"
const LAYER_PROJECTION: String = "projection"
const LAYER_RENDER_OUTPUT: String = "render_output"

## All valid layer names for validation.
const LAYERS: Array[String] = [
	LAYER_IR_INPUT,
	LAYER_PATCH_TRANSACTION,
	LAYER_IR_STATE,
	LAYER_PROJECTION,
	LAYER_RENDER_OUTPUT,
]

## MVP verification methods.
const METHOD_EXACT_MATCH: String = "exact_match"
const METHOD_EXISTS: String = "exists"
const METHOD_NOT_EXISTS: String = "not_exists"
const METHOD_NODE_EXISTS: String = "node_exists"
const METHOD_NODE_PROPERTY_EQUALS: String = "node_property_equals"

const METHODS: Array[String] = [
	METHOD_EXACT_MATCH,
	METHOD_EXISTS,
	METHOD_NOT_EXISTS,
	METHOD_NODE_EXISTS,
	METHOD_NODE_PROPERTY_EQUALS,
]

## Default frames to wait before running verification (projection may sync next frame).
const DEFAULT_TIMEOUT_FRAMES: int = 2

## Keys expected in acceptance_spec Dictionary.
const KEY_TIMEOUT_FRAMES: String = "timeout_frames"
const KEY_CHECKS: String = "checks"

## Keys in each check item: layer, method; then path (IR) or entity_id+property (projection); optional expected.
const CHECK_LAYER: String = "layer"
const CHECK_METHOD: String = "method"
const CHECK_PATH: String = "path"
const CHECK_ENTITY_ID: String = "entity_id"
const CHECK_PROPERTY: String = "property"
const CHECK_EXPECTED: String = "expected"


## Return timeout_frames from spec, or default.
static func get_timeout_frames(spec: Dictionary) -> int:
	var v: Variant = spec.get(KEY_TIMEOUT_FRAMES, DEFAULT_TIMEOUT_FRAMES)
	if v is int and (v as int) >= 0:
		return v as int
	return DEFAULT_TIMEOUT_FRAMES


## Return checks array from spec; empty if missing or invalid.
static func get_checks(spec: Dictionary) -> Array:
	var v: Variant = spec.get(KEY_CHECKS, [])
	if v is Array:
		return v as Array
	return []


## Return true if spec has at least one check (non-empty acceptance).
static func has_checks(spec: Dictionary) -> bool:
	return get_checks(spec).size() > 0


## Return true if layer is one of the five valid layers.
static func is_valid_layer(layer: String) -> bool:
	return layer in LAYERS


## Return true if method is one of the MVP methods.
static func is_valid_method(method: String) -> bool:
	return method in METHODS
