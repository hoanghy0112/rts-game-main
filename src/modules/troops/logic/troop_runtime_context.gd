extends RefCounted
class_name TroopRuntimeContext

var troop


func setup(host: Node) -> void:
	troop = host


func is_valid() -> bool:
	return is_instance_valid(troop)
