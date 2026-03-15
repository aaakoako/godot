## LifecycleComponent: tracks entity alive/dead/despawned state.
## State transitions must go through IRManager.apply_patch (Iron Law 3).
class_name LifecycleComponent
extends Node

var alive: bool = true
var death_state: String = "alive"


## Sync from IR component dict.
func sync_from_ir(comp_data: Dictionary) -> void:
	var a: Variant = comp_data.get("alive", true)
	alive = bool(a)
	var ds: Variant = comp_data.get("death_state", "alive")
	death_state = str(ds)


func is_alive() -> bool:
	return alive


func debug_summary() -> Dictionary:
	return {"component": "lifecycle", "alive": alive, "death_state": death_state}
