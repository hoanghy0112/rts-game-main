@tool
extends Resource
class_name FieldGroundStateData

@export var id: StringName = &"dry"
@export var display_name: String = "Dry"
@export var material: Material
@export_range(0.0, 2.0, 0.01, "or_greater") var default_speed_multiplier: float = 1.0
@export_range(0.0, 2.0, 0.01, "or_greater") var infantry_speed_multiplier: float = 1.0
@export_range(0.0, 2.0, 0.01, "or_greater") var cavalry_speed_multiplier: float = 1.0
@export_range(0.0, 2.0, 0.01, "or_greater") var cart_speed_multiplier: float = 1.0


func get_speed_multiplier(unit_type: StringName) -> float:
	match unit_type:
		&"infantry":
			return infantry_speed_multiplier
		&"cavalry":
			return cavalry_speed_multiplier
		&"cart", &"wagon", &"supply_cart":
			return cart_speed_multiplier
		_:
			return default_speed_multiplier
