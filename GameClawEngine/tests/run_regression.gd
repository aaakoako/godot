extends Node

const ImplScript := preload("res://validation/tests/run_regression_impl.gd")
var _impl: Node = null


func _ready() -> void:
	_impl = ImplScript.new()
	add_child(_impl)
