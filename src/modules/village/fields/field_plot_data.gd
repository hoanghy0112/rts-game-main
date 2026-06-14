@tool
extends Resource
class_name FieldPlotData

@export var id: StringName = &""
@export var center: Vector3 = Vector3.ZERO
@export var row_direction: Vector3 = Vector3.RIGHT
@export var lateral_direction: Vector3 = Vector3.FORWARD
@export var length: float = 1.0
@export var width: float = 1.0
@export var area: float = 1.0
@export var stage: StringName = &"empty"

@export_range(0.0, 1.0, 0.01) var water_level: float = 0.0
@export_range(0.0, 1.0, 0.01) var flood_level: float = 0.0
@export_range(0.0, 1.0, 0.01) var irrigation_level: float = 0.0
@export_range(0.0, 1.0, 0.01) var labor_level: float = 0.0
@export_range(0.0, 1.0, 0.01) var safety_level: float = 1.0
@export_range(0.0, 1.0, 0.01) var mud_level: float = 0.0

var ground_state_id: StringName = &"dry"
var ground_state_data: FieldGroundStateData


func configure(
	new_id: StringName,
	new_center: Vector3,
	new_row_direction: Vector3,
	new_lateral_direction: Vector3,
	new_length: float,
	new_width: float
) -> void:
	id = new_id
	center = new_center
	row_direction = new_row_direction.normalized()
	lateral_direction = new_lateral_direction.normalized()
	length = maxf(new_length, 0.0)
	width = maxf(new_width, 0.0)
	area = length * width
