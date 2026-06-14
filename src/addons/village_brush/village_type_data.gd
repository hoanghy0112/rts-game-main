@tool
extends Resource
class_name VillageTypeData

@export var id: StringName = &"default_village"
@export var display_name: String = "Default Village"
@export_multiline var description: String = ""
@export var house_scene: PackedScene
@export var house_scenes: Array[PackedScene] = []
@export var decoration_scenes: Array[PackedScene] = []
@export var generation_settings: Dictionary = {}
