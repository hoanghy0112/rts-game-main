@tool
extends Resource
class_name VillageTypeData

@export var id: StringName = &"default_village"
@export var display_name: String = "Default Village"
@export_multiline var description: String = ""
@export var house_scene: PackedScene
@export var house_scenes: Array[PackedScene] = []
@export var peasant_scene: PackedScene
@export_range(0, 512, 1, "or_greater") var peasant_target_count: int = 8
@export_range(0.0, 512.0, 0.1, "or_greater") var peasant_spawn_rate_per_minute: float = 12.0
@export_range(0.0, 512.0, 0.01, "or_greater") var peasant_death_rate_per_minute: float = 0.0
@export var decoration_scenes: Array[PackedScene] = []
@export var generation_settings: Dictionary = {}
