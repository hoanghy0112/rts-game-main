@tool
extends Resource
class_name CropTypeData

@export var crop_id: StringName = &"field"
@export var display_name: String = "Field"
@export_multiline var description: String = ""
@export var field_scene: PackedScene
@export var default_stage_id: StringName = &"empty"
@export var default_ground_state_id: StringName = &"dry"

@export_group("Ground States")
@export var dry_ground_state: FieldGroundStateData
@export var wet_ground_state: FieldGroundStateData
@export var flooded_ground_state: FieldGroundStateData
@export var muddy_ground_state: FieldGroundStateData


func get_ground_state_id() -> StringName:
	return default_ground_state_id


func get_crop_stage_id() -> StringName:
	return default_stage_id


func get_ground_state_data(ground_state_id: StringName) -> FieldGroundStateData:
	match ground_state_id:
		&"wet":
			return wet_ground_state if wet_ground_state else dry_ground_state
		&"flooded":
			return flooded_ground_state if flooded_ground_state else wet_ground_state
		&"muddy":
			return muddy_ground_state if muddy_ground_state else wet_ground_state
		_:
			return dry_ground_state

