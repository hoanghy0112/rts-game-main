@tool
extends Resource
class_name WallTypeData

@export var id: StringName = &"default_wall"
@export var display_name: String = "Default Wall"
@export_multiline var description: String = ""
@export var wall_segment_scene: PackedScene
@export var gate_scene: PackedScene
@export var generation_settings: Dictionary = {}
