@tool
extends Resource
class_name ForestPaletteData

@export var id: StringName = &"forest_palette"
@export var display_name: String = "Forest Palette"
@export_multiline var description: String = ""
@export var plant_types: Array[ForestPlantTypeData] = []


func get_plant_type_by_id(plant_id: StringName) -> ForestPlantTypeData:
	for plant_type: ForestPlantTypeData in plant_types:
		if plant_type and plant_type.id == plant_id:
			return plant_type
	return null


func get_all_plant_ids() -> Array[StringName]:
	var ids: Array[StringName] = []
	for plant_type: ForestPlantTypeData in plant_types:
		if plant_type and plant_type.id != &"":
			ids.append(plant_type.id)
	return ids


func get_default_selected_plant_ids() -> Array[StringName]:
	var ids: Array[StringName] = []
	for plant_type: ForestPlantTypeData in plant_types:
		if plant_type and plant_type.default_selected and plant_type.id != &"":
			ids.append(plant_type.id)
	if ids.is_empty():
		return get_all_plant_ids()
	return ids


func filter_plant_ids(plant_ids: Array[StringName]) -> Array[StringName]:
	var available := get_all_plant_ids()
	var filtered: Array[StringName] = []
	for plant_id: StringName in plant_ids:
		if available.has(plant_id) and not filtered.has(plant_id):
			filtered.append(plant_id)
	return filtered
